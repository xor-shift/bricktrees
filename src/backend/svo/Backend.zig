const std = @import("std");

const dyn = @import("dyn");
const wgm = @import("wgm");

const wgpu = @import("gfx").wgpu;

const VisualiserThing = @import("../../things/VisualiserThing.zig");

const IBackend = @import("../IBackend.zig");
const IThing = @import("../../IThing.zig");
const IVoxelProvider = @import("../../IVoxelProvider.zig");

const Common = @import("../Common.zig");
const Uniforms = @import("../uniforms.zig").Uniforms;

const g = &@import("../../main.zig").g;

const Self = @This();

const Configuration = struct {
    depth: u6,
    batch_bpa: u6,
};

pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IBackend });

common: Common,

compute_pipeline_layout: wgpu.PipelineLayout,
compute_pipeline: wgpu.ComputePipeline,

svo_bgl: wgpu.BindGroupLayout,
svo_bg: wgpu.BindGroup = .{},
svo_buffer: wgpu.Buffer = .{},

config: Configuration = .{
    .depth = 0,
    .batch_bpa = 3,
},
origin: [3]f64 = .{0} ** 3,

fn make_sphere(alloc: std.mem.Allocator, depth: u6, radius: f32) ![]u32 {
    const ret = try alloc.alloc(u32, @as(usize, 1) << (3 * depth));

    const sl = @as(usize, 1) << depth;

    for (0..sl) |z| for (0..sl) |y| for (0..sl) |x| {
        const out_coords = [_]usize{ x, y, z };

        const centered_coords = wgm.add(wgm.lossy_cast(f32, out_coords), 0.5);
        const dist = wgm.length(wgm.sub(centered_coords, [_]f32{@floatFromInt(sl / 2)} ** 3));

        ret[wgm.to_idx(out_coords, [_]usize{sl} ** 3)] = if (dist < radius) 1 else 0;
    };

    return ret;
}

const FatNode = packed struct {
    is_leaf: bool,

    inner: packed union {
        Leaf: packed struct {
            material: u32,
        },
        Node: packed struct {
            level: u6,
            packed_coords: u48,

            /// in number of nodes
            children_index: u32 = undefined,
            valid: u8 = undefined,
            leaf: u8 = undefined,
        },

        Pass1Leaf: packed struct {
            material: u32,
            word_tracker: u32,
        },

        Pass1Node: packed struct {
            word_tracker: u32,
            _padding: u22 = undefined,

            /// in number of words
            children_offset: u32 = undefined,
            valid: u8 = undefined,
            leaf: u8 = undefined,
        },
    },

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (self.is_leaf) {
            return writer.print("{X:0>8}", .{self.inner.Leaf.material});
        } else {
            const node = self.inner.Node;

            var children_string = [_]u8{'.'} ** 8;
            for (0..8) |i| {
                const status = ((node.valid >> @intCast(i)) & 1) + ((node.leaf >> @intCast(i)) & 1) * 2;
                children_string[7 - i] = ".v?l"[@intCast(status)];
            }

            return writer.print("{d}, {d}, {d} @ {d}. {s} @ {d}", .{ (node.packed_coords >> 0) & 0xFFFF, (node.packed_coords >> 16) & 0xFFFF, (node.packed_coords >> 32) & 0xFFFF, node.level, &children_string, node.children_index });
        }
    }
};

// lmao
fn create_svo(
    comptime T: type,
    depth: u6,
    data: []const T,
    zero: T,
    alloc: std.mem.Allocator,
) ![]u32 {
    comptime std.debug.assert(@sizeOf(T) == @sizeOf(u32));
    comptime std.debug.assert(@bitSizeOf(T) == @bitSizeOf(u32));

    // excludes layers `0` and `depth`.
    // [0] corresponds to layer 1.
    var layers = try alloc.alloc(std.DynamicBitSet, depth - 1);
    defer alloc.free(layers);

    var managed_to_init: usize = 0;
    for (0..layers.len) |i| {
        layers[i] = try std.DynamicBitSet.initEmpty(
            alloc,
            @as(usize, 1) << @intCast((i + 1) * 3),
        );
        managed_to_init += 1;
    }
    defer for (0..managed_to_init) |i| layers[i].deinit();

    for (0..depth - 1) |i| { // 0 1 2 3
        const level: u6 = @intCast(depth - i - 1);
        const level_sl = @as(usize, 1) << level;

        const layer = &layers[level - 1];
        // std.log.debug("level: {d}, sl: {d}, len: {d}", .{
        //     level,
        //     level_sl,
        //     layer.unmanaged.bit_length,
        // });

        for (0..level_sl) |z| for (0..level_sl) |y| for (0..level_sl) |x| {
            const ll_coords = [_]usize{ x, y, z };
            const index = wgm.to_idx(ll_coords, [_]usize{
                @as(usize, 1) << level,
            } ** 3);

            var occupied = false;
            for (0..8) |offset_idx| {
                const inner_offset = [_]usize{
                    if ((offset_idx & 1) != 0) 1 else 0,
                    if ((offset_idx & 2) != 0) 1 else 0,
                    if ((offset_idx & 4) != 0) 1 else 0,
                };

                const inner_coords = wgm.add(wgm.mulew(ll_coords, 2), inner_offset);
                const inner_idx = wgm.to_idx(inner_coords, [_]usize{
                    @as(usize, 1) << level + 1,
                } ** 3);

                if (level + 1 == depth) {
                    if (data[inner_idx] != zero) {
                        occupied = true;
                        break;
                    }
                } else {
                    const inner_layer = layers[level];
                    if (inner_layer.isSet(inner_idx)) {
                        occupied = true;
                        break;
                    }
                }
            }

            layer.setValue(index, occupied);
        };
    }

    if (false) for (0..layers[0].unmanaged.bit_length) |i| {
        const v = layers[0].isSet(i);
        const writer = std.io.getStdOut().writer();
        if ((i % 2) == 0) try writer.writeByte('\n');
        if ((i % 4) == 0) try writer.writeByte('\n');
        try writer.writeByte(if (v == false) '.' else '#');
    };

    if (false) for (0..layers[1].unmanaged.bit_length) |i| {
        const v = layers[1].isSet(i);
        const writer = std.io.getStdOut().writer();
        if ((i % 4) == 0) try writer.writeByte('\n');
        if ((i % 16) == 0) try writer.writeByte('\n');
        try writer.writeByte(if (v == false) '.' else '#');
    };

    // this is straight ASS

    var ret = std.ArrayList(FatNode).init(alloc);
    defer ret.deinit();
    try ret.append(.{
        .is_leaf = false,
        .inner = .{ .Node = .{
            .level = 0,
            .packed_coords = 0,
        } },
    });

    {
        var i: usize = 0;
        while (i < ret.items.len) {
            defer i += 1;

            const cur_fat = ret.items[i];
            if (cur_fat.is_leaf) continue;

            const cur_node = cur_fat.inner.Node;

            const coords = [_]usize{
                @intCast((cur_node.packed_coords >> 0) & 0xFFFF),
                @intCast((cur_node.packed_coords >> 16) & 0xFFFF),
                @intCast((cur_node.packed_coords >> 32) & 0xFFFF),
            };

            ret.items[i].inner.Node.children_index = @intCast(ret.items.len);

            for (0..8) |inner_offset| {
                const inner_coords = wgm.add(wgm.mulew(coords, 2), [_]usize{
                    if ((inner_offset & 1) != 0) 1 else 0,
                    if ((inner_offset & 2) != 0) 1 else 0,
                    if ((inner_offset & 4) != 0) 1 else 0,
                });

                const inner_level = cur_node.level + 1;

                const inner_index = wgm.to_idx(inner_coords, [_]usize{
                    @as(usize, 1) << inner_level,
                } ** 3);

                const node_ptr = &ret.items[i].inner.Node; // cant do this above, append invalidates

                node_ptr.valid >>= 1;
                node_ptr.leaf >>= 1;

                if (inner_level == depth) {
                    const mat: u32 = @bitCast(data[inner_index]);
                    const zero_u32: u32 = @bitCast(zero);
                    if (mat == zero_u32) continue;

                    node_ptr.valid |= 0x80;
                    node_ptr.leaf |= 0x80;

                    try ret.append(.{
                        .is_leaf = true,
                        .inner = .{ .Leaf = .{
                            .material = mat,
                        } },
                    });
                } else {
                    const occupied = layers[inner_level - 1].isSet(inner_index);
                    if (!occupied) continue;

                    node_ptr.valid |= 0x80;

                    try ret.append(.{
                        .is_leaf = false,
                        .inner = .{
                            .Node = .{
                                .level = inner_level,
                                .packed_coords = @intCast( //
                                    ((inner_coords[0] & 0xFFFF) << 0) |
                                    ((inner_coords[1] & 0xFFFF) << 16) |
                                    ((inner_coords[2] & 0xFFFF) << 32)),
                            },
                        },
                    });
                }
            }
        }
    }

    // for (ret.items, 0..) |v, i| {
    //     std.log.debug("{d:0>3}: {any}", .{ i, v });
    // }

    // pass 1: compute offsets
    {
        var word_tracker: usize = 0;
        for (0..ret.items.len) |i| {
            const j = ret.items.len - i - 1;
            const node = ret.items[j];
            // if (node.is_leaf) {
            //     std.log.debug("{d}: {any}", .{ j, node.inner.Leaf });
            // } else {
            //     std.log.debug("{d}: {any}", .{ j, node.inner.Node });
            // }

            if (node.is_leaf) {
                word_tracker += 1;
                ret.items[j] = FatNode{
                    .is_leaf = true,
                    .inner = .{ .Pass1Leaf = .{
                        .word_tracker = @intCast(word_tracker),
                        .material = node.inner.Leaf.material,
                    } },
                };
            } else {
                const first_child = ret.items[node.inner.Node.children_index];
                const tracker_at_child = if (first_child.is_leaf)
                    first_child.inner.Pass1Leaf.word_tracker
                else
                    first_child.inner.Pass1Node.word_tracker;
                const offset = word_tracker - tracker_at_child;

                const is_far = offset >= 0xFFFF;

                word_tracker += if (is_far) 2 else 1;

                ret.items[j] = FatNode{
                    .is_leaf = false,
                    .inner = .{ .Pass1Node = .{
                        .word_tracker = @intCast(word_tracker),
                        .children_offset = @intCast(offset),
                        .valid = node.inner.Node.valid,
                        .leaf = node.inner.Node.leaf,
                    } },
                };
            }
        }
    }

    // pass 2: electric boogaloo

    const as_u32: [*]u32 = @ptrCast(ret.items.ptr);
    var out_ptr: usize = 0;
    for (ret.items) |fat_node| {
        if (fat_node.is_leaf) {
            as_u32[out_ptr] = fat_node.inner.Pass1Leaf.material;
            out_ptr += 1;
            continue;
        }

        const node = fat_node.inner.Pass1Node;
        const is_far = node.children_offset >= 0xFFFF;
        const lower_half = (@as(u32, @intCast(node.valid)) << 8) | @as(u32, @intCast(node.leaf));

        as_u32[out_ptr] = if (is_far)
            0xFFFF0000 | lower_half
        else
            (@as(u32, @intCast(node.children_offset)) << 16) | lower_half;
        out_ptr += 1;

        if (is_far) {
            as_u32[out_ptr] = @intCast(node.children_offset);
            out_ptr += 1;
        }
    }

    const true_ret = try alloc.dupe(u32, as_u32[0..out_ptr]);

    return true_ret;
}

test create_svo {
    const alloc = std.testing.allocator;

    const data = try make_sphere(alloc, 3, 3.5);
    defer alloc.free(data);

    if (false) for (data, 0..data.len) |v, i| {
        const writer = std.io.getStdOut().writer();
        if ((i % 8) == 0) try writer.writeByte('\n');
        if ((i % 64) == 0) try writer.writeByte('\n');
        try writer.writeByte(if (v == 0) '.' else '#');
    };

    const svo = try create_svo(u32, 3, data, 0, alloc);
    defer alloc.free(svo);

    // eyeball debugging yet again
    const fun = struct {
        fn aufruf(
            node: usize,
            tree: []const u32,
            level: usize,
            coords: [3]usize,
            is_leaf: bool,
        ) void {
            const padding = "          "[0 .. level * 2];

            const v = tree[node];

            if (is_leaf) {
                std.log.debug("{s}@{d} {X:0>8}", .{ padding, node, v });
                return;
            }

            const base_offset = v >> 16;
            const offset = (if (base_offset == 0xFFFF) tree[node + 1] else base_offset) + 1;

            const constructed_node: FatNode = .{
                .is_leaf = false,
                .inner = .{
                    .Node = .{
                        .packed_coords = @intCast( //
                            ((coords[0] & 0xFFFF) << 0) |
                            ((coords[1] & 0xFFFF) << 16) |
                            ((coords[2] & 0xFFFF) << 32)),
                        .leaf = @intCast((v >> 0) & 0xFF),
                        .valid = @intCast((v >> 8) & 0xFF),
                        .children_index = @as(u32, @intCast(node)) + offset,
                        .level = @intCast(level),
                    },
                },
            };

            std.log.debug("{s}@{d} {any}", .{
                padding,
                node,
                constructed_node,
            });

            const valid = constructed_node.inner.Node.valid;
            const leaf = constructed_node.inner.Node.leaf;

            var word_tracker: usize = 0;
            for (0..8) |i| {
                const inner_coords = wgm.add(wgm.mulew(coords, 2), [_]usize{
                    if ((i & 1) != 0) 1 else 0,
                    if ((i & 2) != 0) 1 else 0,
                    if ((i & 4) != 0) 1 else 0,
                });

                const inner_valid = ((valid >> @intCast(i)) & 1) != 0;
                const inner_leaf = ((leaf >> @intCast(i)) & 1) != 0;

                if (!inner_valid) continue;

                const child_start = @as(usize, @intCast(offset)) + node + word_tracker;
                const child_first_word = tree[child_start];
                const child_size: usize = if (inner_leaf) 1 else if ((child_first_word >> 16) == 0xFFFF) 2 else 1;
                word_tracker += child_size;

                aufruf(child_start, tree, level + 1, inner_coords, inner_leaf);
            }
        }
    }.aufruf;

    fun(0, svo, 0, .{ 0, 0, 0 }, false);

    // for (svo, 0..) |v, i| {
    //     std.log.debug("#{d:03}: {b:0>16} {b:0>8} {b:0>8}", .{
    //         i,
    //         v >> 16,
    //         (v >> 8) & 0xFF,
    //         (v >> 0) & 0xFF,
    //     });
    // }
}

pub fn init() !*Self {
    const common = try Common.init();

    const compute_shader = try g.device.create_shader_module_wgsl_from_file("SVO shader", "shaders/svo.wgsl", g.alloc);
    errdefer compute_shader.deinit();

    const svo_bgl = try g.device.create_bind_group_layout(.{
        .label = "SVO bind group",
        .entries = &.{
            wgpu.BindGroupLayout.Entry{
                .binding = 0,
                .visibility = .{ .compute = true },
                .layout = .{
                    .Buffer = .{ .type = .ReadOnlyStorage },
                },
            },
        },
    });
    errdefer svo_bgl.deinit();

    const data = try make_sphere(g.alloc, 5, 16);
    defer g.alloc.free(data);
    const svo = try create_svo(u32, 5, data, 0, g.alloc);
    defer g.alloc.free(svo);

    const svo_buffer = try g.device.create_buffer(.{
        .label = "SVO buffer",
        .size = svo.len * @sizeOf(u32),
        .usage = .{
            .copy_dst = true,
            .storage = true,
        },
        .mapped_at_creation = false,
    });
    errdefer svo_buffer.deinit();
    g.queue.write_buffer(svo_buffer, 0, std.mem.sliceAsBytes(svo));

    const svo_bg = try g.device.create_bind_group(.{
        .label = "SVO bind group",
        .layout = svo_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .Buffer = .{ .buffer = svo_buffer } },
            },
        },
    });
    errdefer svo_bg.deinit();

    const compute_pipeline_layout = try g.device.create_pipeline_layout(.{
        .label = "compute pipeline layout",
        .bind_group_layouts = &.{
            common.uniform_bgl,
            common.compute_textures_bgl,
            svo_bgl,
        },
    });
    errdefer compute_pipeline_layout.deinit();

    const compute_pipeline = try g.device.create_compute_pipeline(.{
        .label = "compute pipeline",
        .layout = compute_pipeline_layout,
        .compute = .{
            .module = compute_shader,
            .entry_point = "cs_main",
            .constants = &.{},
        },
    });
    errdefer compute_pipeline.deinit();

    const ret = try g.alloc.create(Self);
    ret.* = .{
        .common = common,

        .compute_pipeline_layout = compute_pipeline_layout,
        .compute_pipeline = compute_pipeline,

        .svo_bgl = svo_bgl,
        .svo_bg = svo_bg,
        .svo_buffer = svo_buffer,
    };

    try ret.configure(.{
        .desied_view_volume_size = .{1024} ** 3,
    });

    const dims = g.window.get_size() catch @panic("g.window.get_size()");
    try ret.resize(dims);

    return ret;
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn destroy(self: *Self, alloc: std.mem.Allocator) void {
    _ = self;
    _ = alloc;
}

pub fn resize(self: *Self, dims: [2]usize) !void {
    try self.common.resize(dims);
}

pub fn recenter(self: *Self, desired_center: [3]f64) void {
    _ = self;
    _ = desired_center;
}

pub fn view_volume(self: *Self) [2][3]isize {
    _ = self;
    return .{
        .{0} ** 3,
        .{0} ** 3,
    };
}

pub fn options_ui(self: *Self) void {
    self.common.do_options_ui();
}

pub fn get_origin(self: Self) [3]f64 {
    _ = self;
    return .{0} ** 3;
}

pub fn configure(self: *Self, config: IBackend.BackendConfig) anyerror!void {
    const batch_bpa: u6 = 3;
    const batch_sidelength = @as(usize, 1) << batch_bpa;

    const vvs = config.desied_view_volume_size;
    const max_sidelength = @max(@max(vvs[0], vvs[1]), vvs[2]);
    const aligned_sidelength = std.math.ceilPowerOfTwo(usize, max_sidelength) catch @panic("the hell are you doing???");
    const sidelength = @max(batch_sidelength, aligned_sidelength);
    const sidelength_log2: u6 = @intCast(@ctz(sidelength));

    _ = sidelength_log2;
    const native_config: Configuration = .{
        .batch_bpa = batch_bpa,
        //.depth = sidelength_log2,
        .depth = 5,
    };

    try self.native_configure(native_config);
}

fn native_configure(self: *Self, config: Configuration) !void {
    self.config = config; // TODO: there are more things to do here
}

pub fn render(self: *Self, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
    self.common.uniforms.custom[0] = @intCast(self.config.depth);
    try self.common.render(delta_ns, encoder, onto);

    const dims = g.window.get_size() catch @panic("g.window.get_size()");

    const compute_pass = try encoder.begin_compute_pass(.{
        .label = "svo compute pass",
    });

    compute_pass.set_pipeline(self.compute_pipeline);
    compute_pass.set_bind_group(0, self.common.uniform_bg, null);
    compute_pass.set_bind_group(1, self.common.compute_textures_bg, null);
    compute_pass.set_bind_group(2, self.svo_bg, null);

    const wg_sz: [2]usize = .{ 8, 8 };
    const wg_count = wgm.div(
        wgm.sub(
            wgm.add(dims, wg_sz),
            [2]usize{ 1, 1 },
        ),
        wg_sz,
    );
    compute_pass.dispatch_workgroups(.{
        @intCast(wg_count[0]),
        @intCast(wg_count[1]),
        1,
    });

    compute_pass.end();
    compute_pass.deinit();
}

pub fn post_render(self: *Self) anyerror!void {
    _ = self;
}
