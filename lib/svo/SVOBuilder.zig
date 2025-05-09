const std = @import("std");

const bit_utils = @import("core").bit_utils;

const qov = @import("qov");

const PackedVoxel = qov.PackedVoxel;

const Self = @This();

const Elem = packed union {
    Node: packed struct {
        leaf_mask: u8,
        valid_mask: u8,
        offset: u16,
    },
    Material: PackedVoxel,
    ChildrenStart: u32,
};

const Node = struct {
    valid: u8,
    start: u32,
};

const LayerProgress = struct {
    progress: u3 = 0,
    node: Node,
};

const Layer = struct {
    progress: LayerProgress = .{
        .node = .{
            .valid = 0,
            .start = 0,
        },
    },
    data: std.ArrayListUnmanaged(Node) = .{},
};

alloc: std.mem.Allocator,

voxel_layer: std.ArrayListUnmanaged(PackedVoxel) = .{},
layers: []Layer,

pub fn init(alloc: std.mem.Allocator) !Self {
    const layers = try alloc.alloc(Layer, 1);
    layers[0] = .{
        .progress = .{
            .node = .{
                .valid = 0,
                .start = 0,
            },
        },
    };

    return .{
        .alloc = alloc,
        .layers = layers,
    };
}

pub fn deinit(self: *Self) void {
    self.voxel_layer.deinit(self.alloc);
    for (0..self.layers.len) |i| self.layers[i].data.deinit(self.alloc);
    self.alloc.free(self.layers);
}

pub fn submit(self: *Self, block: [8]PackedVoxel) !void {
    const zeroes: @Vector(8, u32) = @splat(0);
    const powers: @Vector(8, u32) = .{ 1, 2, 4, 8, 16, 32, 64, 128 };
    const block_vec: @Vector(8, u32) = @bitCast(block);
    const mask = block_vec == zeroes;

    const valid: u8 = @intCast(@reduce(.Add, @select(u32, mask, zeroes, powers)));
    const no_valid = @popCount(valid);
    const compressed: [8]u32 = bit_utils.compress(u32, block_vec, valid);

    const starts_at = self.voxel_layer.items.len;
    try self.voxel_layer.resize(self.alloc, starts_at + no_valid);
    @memcpy(
        self.voxel_layer.items[starts_at .. starts_at + no_valid],
        @as([]const PackedVoxel, @ptrCast(compressed[0..no_valid])),
    );

    try self.new_node(valid, starts_at);
}

fn add_layer(self: *Self) !void {
    const new_layers = try self.alloc.alloc(Layer, self.layers.len + 1);
    @memcpy(new_layers[0..self.layers.len], self.layers);
    new_layers[self.layers.len] = .{};

    self.alloc.free(self.layers);
    self.layers = new_layers;
}

fn new_node(self: *Self, valid: u8, at: usize) !void {
    var occupied = valid != 0;
    if (occupied) {
        try self.layers[0].data.append(self.alloc, .{
            .valid = valid,
            .start = @intCast(at),
        });
    }

    var layer_no: usize = 1;
    while (true) : (layer_no += 1) {
        if (layer_no >= self.layers.len) {
            try self.add_layer();
        }

        const layer = &self.layers[layer_no];
        layer.progress.node.valid >>= 1;
        layer.progress.node.valid |= if (occupied) 0x80 else 0x00;

        if (layer.progress.progress != 7) {
            layer.progress.progress += 1;
            break;
        }

        occupied = layer.progress.node.valid != 0;
        if (occupied) {
            try layer.data.append(self.alloc, layer.progress.node);
        }

        layer.progress = .{
            .progress = 0,
            .node = .{
                .valid = 0,
                .start = @intCast(self.layers[layer_no - 1].data.items.len),
            },
        };
    }

    // var layer_no: usize = 0;
    // while (true) {
    //     if (layer_no >= self.upper_layers.len) {
    //         const new_layers = try self.alloc.alloc(Layer, self.upper_layers.len + 1);
    //         @memcpy(new_layers[0..self.upper_layers.len], self.upper_layers);
    //         new_layers[self.upper_layers.len] = .{};
    //     }

    //     const layer = &self.upper_layers[layer_no];
    //     if (layer.progress == 7) {
    //         // layer.
    //     }
    // }
}

fn is_complete(self: Self) bool {
    if (self.layers[self.layers.len - 1].progress.progress != 1) return false;

    for (1..self.layers.len) |i| {
        if (self.layers[self.layers.len - i - 1].progress.progress != 0) {
            return false;
        }
    }

    return true;
}

/// In- or out-of-core finish function
/// The following must be defined:
///  - `finish_ctx.preempt_size(words: usize) !void`
///  - `finish_ctx.append_word(word: u32) !void`
///  - `finish_ctx.append_words(words: []const u32) !void`
pub fn finish_context(self: *Self, finish_ctx: anytype) !void {
    std.debug.assert(self.is_complete());

    var written_so_far: usize = 0;

    for (0..self.layers.len) |j| {
        const i = self.layers.len - j - 1;
        const layer = self.layers[i];
        defer self.layers[i].data.deinit(self.alloc);
        const layer_len = layer.data.items.len;

        const out_layer_start = written_so_far;
        try finish_ctx.preempt_size(out_layer_start + layer_len * 2);
        const out_layer_end = out_layer_start + layer_len * 2;

        for (layer.data.items) |v| {
            const leading: u32 = @bitCast(Elem{ .Node = .{
                .leaf_mask = if (i == 0) v.valid else 0,
                .valid_mask = v.valid,
                .offset = 0xFFFF,
            } });
            try finish_ctx.append_word(leading);
            written_so_far += 1;

            const offset_into_next_layer = v.start * @as(u32, if (i == 0) 1 else 2);

            const trailing: u32 = @bitCast(Elem{
                .ChildrenStart = @as(u32, @intCast(out_layer_end)) + offset_into_next_layer,
            });
            try finish_ctx.append_word(trailing);
            written_so_far += 1;
        }
    }
    self.alloc.free(self.layers);

    const voxel_layer_start = written_so_far;
    try finish_ctx.preempt_size(voxel_layer_start + self.voxel_layer.items.len);
    try finish_ctx.append_words(@as([]const u32, @ptrCast(self.voxel_layer.items)));
    written_so_far += self.voxel_layer.items.len;

    self.voxel_layer.deinit(self.alloc);

    self.* = try Self.init(self.alloc);
}

pub const InCoreFinishContext = struct {
    const Context = @This();

    alloc: std.mem.Allocator,
    ret: std.ArrayListUnmanaged(u32),

    pub fn init(alloc: std.mem.Allocator) Context {
        return .{
            .alloc = alloc,
            .ret = .{},
        };
    }

    pub fn deinit(ctx: *Context) void {
        ctx.ret.deinit(ctx.alloc);
    }

    pub fn to_slice(ctx: *Context) ![]u32 {
        return ctx.ret.toOwnedSlice(ctx.alloc);
    }

    fn preempt_size(ctx: *Context, words: usize) !void {
        try ctx.ret.ensureTotalCapacity(ctx.alloc, words);
    }

    fn append_word(ctx: *Context, word: u32) !void {
        try ctx.ret.append(ctx.alloc, word);
    }

    fn append_words(ctx: *Context, words: []const u32) !void {
        try ctx.ret.appendSlice(ctx.alloc, words);
    }
};

/// calls `finish_context` with an `InCoreFinishContext`
pub fn finish(self: *Self) ![]u32 {
    std.debug.assert(self.is_complete());

    var context = InCoreFinishContext.init(self.alloc);
    defer context.deinit();

    try self.finish_context(&context);

    return try context.to_slice();
}

fn debug_print_tree(
    self: Self,
    layer_no: usize,
    node_no: usize,
) void {
    const no_spaces = self.layers.len - layer_no;
    const node: Node = self.layers[layer_no].data.items[node_no];

    std.log.debug("{s}#{d}: {d} children @ {d} /w {b:0>8}", .{
        "           "[0..no_spaces],
        node_no,
        @popCount(node.valid),
        node.start,
        node.valid,
    });

    if (layer_no == 0) return;

    var offset: usize = 0;
    for (0..8) |i| {
        if (((node.valid >> @intCast(i)) & 1) == 0) continue;
        defer offset += 1;

        self.debug_print_tree(layer_no - 1, node.start + offset);
    }
}

fn debug_print(self: Self) void {
    std.log.debug("{d} layer(s), {d} voxel(s), {d} node(s)", .{
        self.layers.len,
        self.voxel_layer.items.len,
        blk: {
            var ret: usize = 0;
            for (self.layers) |l| ret += l.data.items.len;
            break :blk ret;
        },
    });

    self.debug_print_tree(self.layers.len - 2, 0);
}

test "SVOBuilder" {
    const alloc = std.testing.allocator;
    var builder = try Self.init(alloc);
    defer builder.deinit();

    const v = [_]PackedVoxel{
        @bitCast(@as(u32, 0)),
        @bitCast(@as(u32, 1)),
        @bitCast(@as(u32, 2)),
        @bitCast(@as(u32, 3)),
    };

    const z = [_]PackedVoxel{PackedVoxel.air} ** 4;

    for (0..8) |i| {
        if ((i % 4) == 0) {
            for (0..8) |_| try builder.submit(z ** 2);
            continue;
        }
        try builder.submit(v ** 2);
        try builder.submit(z ** 2);
        try builder.submit(v ++ z);
        try builder.submit(z ++ v);
        try builder.submit(v ** 2);
        try builder.submit(z ** 2);
        try builder.submit(v ++ z);
        try builder.submit(z ++ v);
    }

    // builder.debug_print();

    try std.testing.expect(builder.is_complete());

    // std.log.debug("finishing up", .{});
    const res = try builder.finish();
    defer alloc.free(res);
    // std.log.debug("res.len: {d}", .{res.len});
}
