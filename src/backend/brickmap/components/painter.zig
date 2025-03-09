const std = @import("std");

const dyn = @import("dyn");
const wgm = @import("wgm");

const curves = @import("../bricktree/curves.zig");
const worker_pool = @import("../../../worker_pool.zig");

const PackedVoxel = @import("../../../voxel.zig").PackedVoxel;
const Voxel = @import("../../../voxel.zig").Voxel;

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

        pub fn render(self: *Self, feedback_buffer: Backend.FBuffer) !void {
            std.log.debug("{d} entries in the feedback buffer", .{feedback_buffer.next_idx});

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

                .curve = .{
                    .dims = self.backend.config.?.grid_dimensions,
                },

                .already_drawn_range = already_drawn_range,
            };
            self.brickmap_gen_pool.begin_work(&context);

            while (self.brickmap_gen_pool.get_result()) |info| {
                const result = info.result;
                const absolute_bm_coords = info.for_work.brickmap_coords;

                const the_brickmap = &result.brickmap;
                const the_bricktree = &result.bricktree;

                if (result.is_empty) {
                    _ = self.backend.remove_brickmap(absolute_bm_coords);
                } else {
                    _ = self.backend.upload_brickmap(absolute_bm_coords, the_brickmap, the_bricktree);
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

            curve: Curve,

            already_drawn_range: [2][3]isize,
        };

        const PoolWork = struct {
            brickmap_coords: [3]isize,
            range: [2][3]isize,
        };

        const PoolResult = struct {
            is_empty: bool,
            brickmap: Cfg.Brickmap,
            bricktree: Cfg.BricktreeStorage,
        };

        const Pool = worker_pool.WorkerPool(PoolContext, PoolWork, PoolResult);

        fn should_draw(ctx: *PoolContext, range: [2][3]isize) bool {
            const should_draw_from_scratch = //
                wgm.compare(.some, range[0], .less_than, ctx.already_drawn_range[0]) or //
                wgm.compare(.some, range[1], .greater_than, ctx.already_drawn_range[1]);

            const someone_wants_to_draw = if (should_draw_from_scratch) blk: {
                for (ctx.voxel_providers) |p| {
                    if (p.d("should_draw_voxels", .{range})) {
                        break :blk true;
                    }
                }
                break :blk false;
            } else false;

            const someone_wants_to_redraw = if (!should_draw_from_scratch) blk: {
                for (ctx.voxel_providers) |p| {
                    if (p.d("should_redraw_voxels", .{range})) {
                        break :blk true;
                    }
                }
                break :blk false;
            } else false;

            return someone_wants_to_redraw or someone_wants_to_draw;
        }

        fn pool_producer_fn(ctx: *PoolContext) ?PoolWork {
            while (true) {
                const vv_local_coords = ctx.curve.next() orelse return null;
                const abs_coords = wgm.add(wgm.cast(isize, vv_local_coords).?, ctx.self.backend.origin_brickmap);

                const voxel_coords = wgm.mulew(abs_coords, Cfg.Brickmap.side_length_i);
                const range = [_][3]isize{
                    voxel_coords,
                    wgm.add(voxel_coords, Cfg.Brickmap.side_length_i),
                };

                if (!should_draw(ctx, range)) {
                    continue;
                }

                return PoolWork{
                    .brickmap_coords = abs_coords,
                    .range = range,
                };
            }
        }

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

            out_result.is_empty = is_empty;
        }
    };
}
