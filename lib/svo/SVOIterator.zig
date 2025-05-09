const std = @import("std");

const wgm = @import("wgm");
const qov = @import("qov");

const PackedVoxel = qov.PackedVoxel;

const Self = @This();

const Frame = struct {
    extents: [2][3]u32,

    processed_self: bool = false,
    processed_children: u32 = 0,

    children_start: u32,
    child_offsets: u32,

    // for debugging
    self_at: u32,
    raw_node: u32,
};

data: []const u32,
stack: [16]Frame = [_]Frame{undefined} ** 16,
dp: usize = 0,
sp: usize = 1,

pub fn init(data: []const u32, depth: u5) Self {
    var ret: Self = .{
        .data = data,
    };

    const root_extents = .{
        .{ 0, 0, 0 },
        .{(@as(u32, 1) << depth) - 1} ** 3,
    };

    ret.stack[0] = ret.make_frame(0, root_extents);

    return ret;
}

fn make_frame(self: Self, node_idx: u32, extents: [2][3]u32) Frame {
    const node = self.data[@intCast(node_idx)];
    const leaves = node & 0xFF;
    const valid = (node >> 8) & 0xFF;

    const base_offset = node >> 16;
    const is_far = base_offset == 0xFFFF;
    const children_start = if (is_far)
        self.data[@intCast(node_idx + 1)]
    else
        node_idx + base_offset + 1;

    var offset_tracker: u32 = 0;
    var child_offsets: u32 = 0;

    for (0..8) |i| {
        const child_is_valid = ((valid >> @intCast(i)) & 1) != 0;
        const child_is_leaf = ((leaves >> @intCast(i)) & 1) != 0;

        const child_is_far = if (child_is_valid)
            (self.data[@intCast(children_start + offset_tracker)] >> 16) == 0xFFFF
        else
            false;

        const child_size: u32 = if (!child_is_valid)
            0
        else if (child_is_leaf)
            1
        else if (child_is_far)
            2
        else
            1;

        child_offsets <<= 4;
        child_offsets |= offset_tracker;
        offset_tracker += child_size;
    }

    child_offsets = (child_offsets >> 16) | (child_offsets << 16);
    child_offsets = ((child_offsets >> 8) & 0x00FF00FF) | ((child_offsets << 8) & 0xFF00FF00);
    child_offsets = ((child_offsets >> 4) & 0x0F0F0F0F) | ((child_offsets << 4) & 0xF0F0F0F0);

    return .{
        .extents = extents,

        .children_start = children_start,
        .child_offsets = child_offsets,

        .self_at = node_idx,
        .raw_node = node,
    };
}

const Next = union(enum) {
    Node: struct {
        depth: u6,
        extents: [2][3]u32,
    },
    Voxel: struct {
        depth: u6,
        extents: [2][3]u32,
        material: PackedVoxel,
    },
};

fn next_impl(self: *Self) ?Next {
    std.debug.assert(self.sp != 0);

    const frame = &self.stack[self.sp - 1];
    if (!frame.processed_self) {
        defer frame.processed_self = true;
        return .{ .Node = .{
            .depth = @intCast(self.sp - 1),
            .extents = frame.extents,
        } };
    }

    if (frame.processed_children == 8) {
        self.sp -= 1;
        return null;
    }
    defer frame.processed_children += 1;

    const processed_children: u5 = @intCast(frame.processed_children);
    const child_offset = (frame.child_offsets >> (processed_children * 4)) & 15;
    const child_index = frame.children_start + child_offset;

    const child_is_valid = ((frame.raw_node >> (8 + processed_children)) & 1) != 0;
    const child_is_leaf = ((frame.raw_node >> processed_children) & 1) != 0;

    if (!child_is_valid) return null;

    const split_for_child = split_extent(
        frame.extents,
        @intCast(processed_children),
    );

    if (!child_is_leaf) {
        const child_frame = self.make_frame(child_index, split_for_child);

        self.stack[self.sp] = child_frame;
        self.sp += 1;
    } else {
        return .{ .Voxel = .{
            .depth = @intCast(self.sp),
            .extents = split_for_child,
            .material = @bitCast(self.data[child_index]),
        } };
    }

    return null;
}

pub fn next(self: *Self) ?Next {
    while (true) {
        if (self.sp == 0) return null;
        return self.next_impl() orelse continue;
    }
}

fn split_extent(extent: [2][3]u32, split_for: u3) [2][3]u32 {
    const mid = wgm.add(wgm.div(wgm.sub(extent[1], extent[0]), 2), extent[0]);

    const hi = [3]bool{
        ((split_for >> 0) & 1) != 0,
        ((split_for >> 1) & 1) != 0,
        ((split_for >> 2) & 1) != 0,
    };

    return .{
        .{
            if (hi[0]) mid[0] + 1 else extent[0][0],
            if (hi[1]) mid[1] + 1 else extent[0][1],
            if (hi[2]) mid[2] + 1 else extent[0][2],
        },
        .{
            if (hi[0]) extent[1][0] else mid[0],
            if (hi[1]) extent[1][1] else mid[1],
            if (hi[2]) extent[1][2] else mid[2],
        },
    };
}
