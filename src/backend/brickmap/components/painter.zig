const std = @import("std");

const dyn = @import("dyn");
const qov = @import("qov");
const wgm = @import("wgm");

const curves = @import("../bricktree/curves.zig");
const worker_pool = @import("core").worker_pool;

const PackedVoxel = qov.PackedVoxel;
const Voxel = qov.Voxel;

const IVoxelProvider = @import("../../../IVoxelProvider.zig");

const g = &@import("../../../main.zig").g;

pub fn Painter(comptime Cfg: type) type {
    return struct {
        const Self = @This();

        const Backend = @import("../backend.zig").Backend(Cfg);
        const Computer = @import("computer.zig").Computer(Cfg);
        const Storage = @import("storage.zig").Storage(Cfg);

        // const Storage = @import("Storage.zig");

        backend: *Backend = undefined,
        storage: *Storage = undefined,
        computer: *Computer = undefined,

        brickmap_gen_pool: *Pool,
        /// if null, everything is drawn, otherwise, a recenter occurred and this range is already drawn
        already_drawn: ?[2][3]isize = .{
            .{0} ** 3,
        } ** 2,

        pub fn init() !Self {
            return .{
                .brickmap_gen_pool = try Pool.init(@min(std.Thread.getCpuCount() catch 1, 14), g.alloc, Self.pool_producer_fn, Self.pool_worker_fn),
            };
        }

        pub fn deinit(self: *Self) void {
            self.brickmap_gen_pool.deinit();
            g.alloc.destroy(self.brickmap_gen_pool);
        }

        pub fn render(self: *Self, to_load: []const u32) !void {
            if (to_load.len != 0) {
                std.log.debug("going to load {d} brickmaps (@ {any})", .{ to_load.len, to_load.ptr });
            }

            const voxel_providers: []dyn.Fat(*IVoxelProvider) = blk: {
                var list = std.ArrayList(dyn.Fat(*IVoxelProvider)).init(g.frame_alloc);

                var iter = g.thing_store.things.iterator();
                while (iter.next()) |thing| {
                    const vp = thing.value_ptr.sideways_cast(IVoxelProvider) orelse continue;
                    try list.append(vp);
                }

                break :blk try list.toOwnedSlice();
            };

            const already_drawn_range = if (self.already_drawn) |v| v else self.backend.get_view_volume();
            self.already_drawn = null;

            for (voxel_providers) |p| {
                p.d("voxel_draw_start", .{});
            }

            defer for (voxel_providers) |p| {
                p.d("voxel_draw_end", .{});
            };

            var context: PoolContext = .{
                .self = self,
                .voxel_providers = voxel_providers,

                .to_load = to_load,
                // .curve = .{
                //     .dims = self.backend.config.?.grid_dimensions,
                // },

                .already_drawn_range = already_drawn_range,
            };
            self.brickmap_gen_pool.begin_work(&context);

            while (self.brickmap_gen_pool.get_result()) |info| {
                const result = info.result;
                const absolute_bm_coords = info.for_work.brickmap_coords;

                const the_brickmap = &result.brickmap;
                const the_bricktree = &result.bricktree;

                if (result.is_empty) {
                    // std.log.debug("removing the empty brickmap at {any}", .{absolute_bm_coords});
                    _ = self.backend.remove_brickmap(absolute_bm_coords);
                } else {
                    // std.log.debug("uploading the brickmap at {any}", .{absolute_bm_coords});
                    const managed_to_upload = self.backend.upload_brickmap(absolute_bm_coords, the_brickmap, the_bricktree);
                    if (!managed_to_upload) {
                        _ = self.backend.remove_brickmap(absolute_bm_coords);
                    }
                }
            }
        }

        const Curve = struct {
            iteration: usize = 0,
            dims: [3]usize,

            fn next(ctx: *Curve) ?[3]usize {
                const z = ctx.iteration / (ctx.dims[1] * ctx.dims[0]);
                const y = (ctx.iteration / ctx.dims[0]) % ctx.dims[1];
                const x = ctx.iteration % ctx.dims[0];

                if (z >= ctx.dims[2]) return null;

                ctx.iteration += 1;

                return .{ x, y, z };
            }
        };

        const PoolContext = struct {
            self: *Self,
            voxel_providers: []dyn.Fat(*IVoxelProvider) = &.{},

            issued: usize = 0,
            // relaxed atomic
            nonempty: u32 = 0,
            idx: usize = 0,
            to_load: []const u32,
            //curve: Curve,

            already_drawn_range: [2][3]isize,
        };

        const PoolWork = struct {
            brickmap_coords: [3]isize,
            range: IVoxelProvider.VoxelRange,
        };

        const PoolResult = struct {
            is_empty: bool,
            brickmap: Cfg.Brickmap,
            bricktree: Cfg.BricktreeStorage,
        };

        const Pool = worker_pool.WorkerPool(PoolContext, PoolWork, PoolResult);

        fn pool_producer_fn(ctx: *PoolContext) ?PoolWork {
            while (true) {
                if (ctx.idx >= ctx.to_load.len or @atomicLoad(u32, &ctx.nonempty, .seq_cst) >= 256) { // or ctx.issued >= 256
                    return null;
                }

                const v = ctx.to_load[ctx.idx];
                ctx.idx += 1;

                const cfg = ctx.self.backend.config.?;
                const dims = wgm.cast(u32, cfg.grid_dimensions).?;
                const vv_local_coords = [_]u32{
                    v % dims[0],
                    (v / dims[0]) % dims[1],
                    v / (dims[0] * dims[1]),
                };

                const abs_coords = wgm.add(wgm.cast(isize, vv_local_coords).?, ctx.self.backend.origin_brickmap);
                const abs_vox_coords = wgm.mulew(abs_coords, Cfg.Brickmap.side_length_i);

                const range: IVoxelProvider.VoxelRange = .{
                    .origin = abs_vox_coords,
                    .volume = .{Cfg.Brickmap.side_length} ** 3,
                };

                const should_draw_from_scratch = true; // TODO
                const should_draw = blk: {
                    for (ctx.voxel_providers) |p| {
                        const status = p.d("status_for_region", .{range});
                        if (status == .empty) continue;
                        if (status == .want_redraw) break :blk true;

                        if (should_draw_from_scratch and status == .want_draw) break :blk true;
                    }

                    break :blk false;
                };

                if (!should_draw) continue;

                ctx.issued += 1;

                return PoolWork{
                    .brickmap_coords = abs_coords,
                    .range = range,
                };
            }
        }

        // fn pool_producer_fn(ctx: *PoolContext) ?PoolWork {
        //     while (true) {
        //         const vv_local_coords = ctx.curve.next() orelse return null;
        //         const abs_coords = wgm.add(wgm.cast(isize, vv_local_coords).?, ctx.self.backend.origin_brickmap);

        //         const voxel_coords = wgm.mulew(abs_coords, Cfg.Brickmap.side_length_i);
        //         const range = [_][3]isize{
        //             voxel_coords,
        //             wgm.add(voxel_coords, Cfg.Brickmap.side_length_i),
        //         };

        //         if (!should_draw(ctx, range)) {
        //             continue;
        //         }

        //         return PoolWork{
        //             .brickmap_coords = abs_coords,
        //             .range = range,
        //         };
        //     }
        // }

        fn pool_worker_fn(ctx: *PoolContext, out_result: *PoolResult, work: PoolWork) void {
            const voxel_storage = out_result.brickmap.flat()[0..];
            @memset(voxel_storage, std.mem.zeroes(PackedVoxel));

            for (ctx.voxel_providers) |p| {
                p.d("draw_voxels", .{ work.range, voxel_storage });
            }

            const as_brickmap: *Cfg.Brickmap = @ptrCast(voxel_storage.ptr);

            const is_empty = if (!Cfg.has_tree) blk: {
                break :blk std.mem.allEqual(u32, as_brickmap.c_flat_u32()[0..], 0);
            } else blk: {
                @memset(out_result.bricktree[0..], 0);
                Cfg.bricktree.make_tree_inplace(
                    Cfg.Brickmap.depth,
                    as_brickmap,
                    &out_result.bricktree,
                    switch (Cfg.curve_kind) {
                        .raster => curves.raster,
                        .llm1 => curves.llm,
                        .llm2 => @panic("unimplemented"),
                    },
                );

                break :blk out_result.bricktree[0] == 0;
            };

            if (!is_empty) _ = @atomicRmw(u32, &ctx.nonempty, .Add, 1, .seq_cst);
            out_result.is_empty = is_empty;
        }
    };
}
