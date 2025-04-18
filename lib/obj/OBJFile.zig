const std = @import("std");

const core = @import("core");
const qov = @import("qov");
const wgm = @import("wgm");

const PackedVoxel = qov.PackedVoxel;

const Self = @This();

pub const MaterialRange = struct {
    no_faces: usize,
    material: PackedVoxel,
};

alloc: std.mem.Allocator,
physical_range: [2][3]f32,
vertices: [][3]f32,
faces: [][3]u32,
material_ranges: []MaterialRange,
tree: []const TreeNode,

pub fn deinit(self: Self) void {
    self.alloc.free(self.vertices);
    self.alloc.free(self.faces);
    self.alloc.free(self.material_ranges);
    self.alloc.free(self.tree);
}

fn parse_face_arg(s: []const u8) ?u32 {
    const til = std.mem.indexOfScalar(u8, s, '/') orelse s.len;
    var r: u32 = 0;
    for (s[0..til]) |c| {
        r *= 10;
        r += @intCast(c - '0');
    }
    return r - 1;
}

// soft error handling, gotta go fast
fn parse_line(line: []const u8) union(enum) {
    Ignore: void,
    Vertex: [3]f32,
    Face: [3]u32,
} {
    const s0 = std.mem.indexOfScalarPos(u8, line, 0, ' ') orelse return .{ .Ignore = {} };
    const s1 = std.mem.indexOfScalarPos(u8, line, s0 + 1, ' ') orelse return .{ .Ignore = {} };
    const s2 = std.mem.indexOfScalarPos(u8, line, s0 + s1 + 1, ' ') orelse return .{ .Ignore = {} };
    const s3 = std.mem.indexOfScalarPos(u8, line, s0 + s1 + s2 + 1, ' ') orelse line.len;

    const directive = line[0..s0];
    const args: [3][]const u8 = .{ line[s0 + 1 .. s1], line[s1 + 1 .. s2], line[s2 + 1 .. s3] };

    if (std.mem.eql(u8, directive, "v")) {
        return .{ .Vertex = .{
            std.fmt.parseFloat(f32, args[0]) catch return .{ .Ignore = {} },
            std.fmt.parseFloat(f32, args[1]) catch return .{ .Ignore = {} },
            -(std.fmt.parseFloat(f32, args[2]) catch return .{ .Ignore = {} }),
        } };
    } else if (std.mem.eql(u8, directive, "f")) {
        return .{ .Face = .{
            parse_face_arg(args[0]) orelse return .{ .Ignore = {} },
            parse_face_arg(args[2]) orelse return .{ .Ignore = {} },
            parse_face_arg(args[1]) orelse return .{ .Ignore = {} },
        } };
    }

    return .{ .Ignore = {} };
}

pub const LoadStatus = enum {
    start,
    parsed,
    normalised,
    constructed_tree,
};

/// The volume is split `tree_depth` times. That is, there can at most be:
/// - 1 node if `tree_depth == 0`
/// - 9 nodes if `tree_depth == 1`
/// - 73 nodes if `tree_depth == 2`
/// And so on, and so forth
pub fn from_file(
    relative_path: []const u8,
    tree_depth: u6,
    alloc: std.mem.Allocator,
    progress_context: anytype,
    comptime progress_callback: fn (context: @TypeOf(progress_context), status: LoadStatus) void,
) !Self {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(relative_path, .{
        .mode = .read_only,
    });
    defer file.close();
    const file_stat = try file.stat();

    var vertices_fp = std.ArrayList([3]f32).init(alloc);
    defer vertices_fp.deinit();

    var faces = std.ArrayList([3]u32).init(alloc);
    defer faces.deinit();

    const mmapped = try std.posix.mmap(
        null,
        file_stat.size,
        std.posix.PROT.READ,
        .{ .TYPE = .SHARED },
        file.handle,
        0,
    );
    defer std.posix.munmap(mmapped);

    @call(.auto, progress_callback, .{ progress_context, .start });

    {
        var read_idx: usize = 0;

        while (true) {
            const remaining = mmapped[read_idx..];
            const next_newline = std.mem.indexOfScalar(u8, remaining[0..], '\n') orelse break;
            read_idx += next_newline + 1;

            if (next_newline == 0) continue;

            const line = if (remaining[next_newline - 1] == '\r')
                remaining[0 .. next_newline - 1]
            else
                remaining[0..next_newline];

            switch (parse_line(line)) {
                .Ignore => {},
                .Vertex => |v| try vertices_fp.append(v),
                .Face => |v| try faces.append(v),
            }
        }
    }

    @call(.auto, progress_callback, .{ progress_context, .parsed });

    const min, const max = blk2: {
        var min: [3]f32 = .{std.math.inf(f32)} ** 3;
        var max: [3]f32 = .{-std.math.inf(f32)} ** 3;
        for (vertices_fp.items) |fp_vertex| {
            min = wgm.min(min, fp_vertex);
            max = wgm.max(max, fp_vertex);
        }
        break :blk2 .{ min, max };
    };

    // const vertices, const range = blk: {
    //     const vertices = try alloc.alloc([3]u16, vertices_fp.items.len);

    //     // std.log.debug("min: {any}, max: {any}", .{ min, max });

    //     for (vertices_fp.items, 0..) |fp_vertex, i| {
    //         const normalised_vertex = wgm.div(
    //             wgm.mulew(wgm.sub(fp_vertex, min), 65535),
    //             wgm.sub(max, min),
    //         );
    //         vertices[i] = wgm.lossy_cast(u16, normalised_vertex);
    //     }

    //     break :blk .{ vertices, .{ min, max } };
    // };

    // @call(.auto, progress_callback, .{ progress_context, .normalised });

    const faces_slice = try faces.toOwnedSlice();
    errdefer alloc.free(faces_slice);

    const tree = try init_tree(tree_depth, alloc, faces_slice, vertices_fp.items, .{ min, max });

    @call(.auto, progress_callback, .{ progress_context, .constructed_tree });

    return .{
        .alloc = alloc,
        .physical_range = .{ min, max },
        .vertices = try vertices_fp.toOwnedSlice(),
        .faces = faces_slice,
        .material_ranges = &.{},
        .tree = tree,
    };
}

fn init_tree(
    max_depth: u6,
    alloc: std.mem.Allocator,
    faces: [][3]u32,
    vertices: []const [3]f32,
    range: [2][3]f32,
) ![]const TreeNode {
    var nodes = std.ArrayList(TreeNode).init(alloc);
    defer nodes.deinit();

    try nodes.append(.{
        .face_offset = 0,
        .face_count = faces.len,
        .face_count_incl_children = faces.len,
        .pos_in_parent = null,
        .child_info = null,
    });

    var iterator = TreeIterator.init(nodes.items, range);
    while (iterator.next()) |res| {
        defer iterator.prepare_next();
        if (res.depth >= max_depth) continue;

        var node = nodes.items[res.node];
        var local_faces = faces[node.face_offset .. node.face_offset + node.face_count];

        std.debug.assert(node.child_info == null);

        var potential_children = [_]TreeNode{undefined} ** 8;

        for (0..8) |i| {
            const j = 7 - i; // neater order
            const Context = struct {
                vertices: []const [3]f32,
                min: [3]f32,
                max: [3]f32,
            };
            const inner_range = TreeIterator.get_split_for(res.bounds, @intCast(j));

            const context: Context = .{
                .vertices = vertices,
                .min = inner_range.start,
                .max = inner_range.end,
            };

            const partition_point = core.unstable_partition([3]u32, local_faces, context, struct {
                pub fn aufruf(ctx: Context, indices: [3]u32) bool {
                    const face = [_][3]f32{
                        ctx.vertices[indices[0]],
                        ctx.vertices[indices[1]],
                        ctx.vertices[indices[2]],
                    };

                    for (face) |vertex| {
                        const contained = wgm.compare(.all, vertex, .greater_than_equal, ctx.min) //
                        and wgm.compare(.all, ctx.max, .greater_than_equal, vertex);
                        if (!contained) return false;
                    }

                    return true;
                }
            }.aufruf);

            potential_children[j] = .{
                .face_offset = node.face_offset + partition_point,
                .face_count = local_faces.len - partition_point,
                .face_count_incl_children = local_faces.len - partition_point,
                .pos_in_parent = @intCast(j),
                .child_info = null,
            };

            local_faces = local_faces[0..partition_point];
        }

        node.face_count = local_faces.len;

        const child_count = blk: {
            var child_count: usize = 0;

            for (potential_children) |child| {
                if (child.face_count == 0) continue;
                child_count += 1;
                try nodes.append(child);
            }

            break :blk child_count;
        };

        if (child_count != 0) {
            node.child_info = .{
                .offset = nodes.items.len - child_count,
                .count = child_count,
            };
            nodes.items[res.node] = node;
            iterator.nodes = nodes.items;
        }
    }

    return try nodes.toOwnedSlice();
}

pub fn iterate_range(self: Self, range: CoordinateRange) RangeIterator {
    return .{
        .iter = TreeIterator.init(self.tree, self.physical_range),
        .range = range,
    };
}

pub fn iterate(self: Self) BuiltTreeIterator {
    return BuiltTreeIterator{
        .iter = TreeIterator.init(self.tree, self.physical_range),
    };
}

pub const TreeNode = struct {
    /// offset into `faces`
    face_offset: usize,
    face_count: usize,
    face_count_incl_children: usize,

    pos_in_parent: ?u3,

    /// offset into `tree_node`
    child_info: ?struct {
        offset: usize,
        count: usize,
    },
};

const TreeIterator = struct {
    const max_depth: usize = 32;

    const StackElement = struct {
        node: usize,
        bounds: CoordinateRange,
        done_with_children: bool = false,
    };

    const Result = struct {
        depth: usize,
        node: usize,
        bounds: CoordinateRange,
    };

    stack: [max_depth]StackElement,
    sp: usize = 1,

    nodes: []const TreeNode,

    fn init(nodes: []const TreeNode, range: [2][3]f32) TreeIterator {
        return .{
            .stack = .{.{
                .node = 0,
                .bounds = .{
                    .start = range[0],
                    .end = range[1],
                },
            }} ++ .{undefined} ** (max_depth - 1),

            .nodes = nodes,
        };
    }

    fn try_iterate_into_first_child(
        self: *TreeIterator,
        offset: usize,
        pred_context: anytype,
        comptime predicate: fn (ctx: @TypeOf(pred_context), node: TreeNode, bounds: CoordinateRange) bool,
    ) bool {
        const frame = self.stack[self.sp - 1];
        const cur_node = self.nodes[frame.node];

        const child_info = if (cur_node.child_info) |info| info else return false;

        std.debug.assert(child_info.count != 0);
        std.debug.assert(child_info.count >= offset);

        for (offset..child_info.count) |i| {
            const candidate = self.nodes[child_info.offset + i];
            std.debug.assert(candidate.pos_in_parent != null);

            const bounds = get_split_for(frame.bounds, candidate.pos_in_parent.?);

            if (!@call(.auto, predicate, .{ pred_context, candidate, bounds })) {
                continue;
            }

            self.sp += 1;
            self.stack[self.sp - 1] = .{
                .node = child_info.offset + i,
                .bounds = bounds,
            };

            return true;
        }

        return false;
    }

    fn try_iterate_into_next_sibling(
        self: *TreeIterator,
        pred_context: anytype,
        comptime predicate: fn (ctx: @TypeOf(pred_context), node: TreeNode, bounds: CoordinateRange) bool,
    ) bool {
        const frame = self.stack[self.sp - 1];

        const parent_frame = self.stack[self.sp - 2];
        const parent_node = self.nodes[parent_frame.node];
        std.debug.assert(parent_node.child_info != null);

        const cur_offset_into_siblings = frame.node - parent_node.child_info.?.offset;
        std.debug.assert(cur_offset_into_siblings < parent_node.child_info.?.count);

        for (cur_offset_into_siblings + 1..parent_node.child_info.?.count) |sibling_offset| {
            const sibling_candidate = parent_node.child_info.?.offset + sibling_offset;

            std.debug.assert(parent_node.child_info.?.count != 0);
            std.debug.assert(parent_node.child_info.?.offset < sibling_candidate);

            const candidate_node = self.nodes[sibling_candidate];
            std.debug.assert(candidate_node.pos_in_parent != null);

            const bounds = get_split_for(parent_frame.bounds, candidate_node.pos_in_parent.?);

            if (!@call(.auto, predicate, .{ pred_context, candidate_node, bounds })) {
                continue;
            }

            self.stack[self.sp - 1] = .{
                .node = sibling_candidate,
                .bounds = bounds,
            };

            return true;
        }

        return false;
    }

    pub fn prepare_next(self: *TreeIterator) void {
        return self.prepare_next_predicated({}, struct {
            pub fn aufruf(_: void, _: TreeNode, _: CoordinateRange) bool {
                return true;
            }
        }.aufruf);
    }

    pub fn prepare_next_predicated(
        self: *TreeIterator,
        pred_context: anytype,
        comptime predicate: fn (
            ctx: @TypeOf(pred_context),
            node: TreeNode,
            range: CoordinateRange,
        ) bool,
    ) void {
        if (self.sp == 0) return;

        const frame = self.stack[self.sp - 1];

        if (!frame.done_with_children and self.try_iterate_into_first_child(0, pred_context, predicate)) {
            return;
        }

        if (self.sp == 1) {
            self.sp -= 1;
            return;
        }

        if (self.try_iterate_into_next_sibling(pred_context, predicate)) {
            return;
        }

        self.sp -= 1;
        self.stack[self.sp - 1].done_with_children = true;
        return self.prepare_next_predicated(pred_context, predicate);
    }

    /// This function does not iterate the iterator. This is because we
    /// want the decisions on iterations to be controllable. Simply do a
    /// `prepare_next` at the end of an iteration to pursue a node further.
    pub fn next(self: *TreeIterator) ?Result {
        if (self.sp == 0) return null;
        const frame = self.stack[self.sp - 1];

        return .{
            .depth = self.sp - 1,
            .node = frame.node,
            .bounds = frame.bounds,
        };
    }

    fn get_split_for(range: CoordinateRange, index: u3) CoordinateRange {
        const midpoint = wgm.add(wgm.div(range.start, 2), wgm.div(range.end, 2));

        const hi = [3]bool{
            ((index >> 0) & 1) == 1,
            ((index >> 1) & 1) == 1,
            ((index >> 2) & 1) == 1,
        };

        return .{
            .start = .{
                if (hi[0]) std.math.nextAfter(f32, midpoint[0], std.math.inf(f32)) else range.start[0],
                if (hi[1]) std.math.nextAfter(f32, midpoint[1], std.math.inf(f32)) else range.start[1],
                if (hi[2]) std.math.nextAfter(f32, midpoint[2], std.math.inf(f32)) else range.start[2],
            },
            .end = .{
                if (hi[0]) range.end[0] else midpoint[0],
                if (hi[1]) range.end[1] else midpoint[1],
                if (hi[2]) range.end[2] else midpoint[2],
            },
        };
    }
};

const BuiltTreeIterator = struct {
    iter: TreeIterator,
    first_run: bool = true,

    pub fn next(self: *BuiltTreeIterator) ?TreeIterator.Result {
        if (!self.first_run) self.iter.prepare_next();
        self.first_run = false;
        return self.iter.next();
    }
};

/// Coordinates are inclusive
pub const CoordinateRange = struct {
    start: [3]f32,
    end: [3]f32,
};

const RangeIterator = struct {
    iter: TreeIterator,
    range: CoordinateRange,
    first_run: bool = true,

    fn predicate(ctx: CoordinateRange, _: TreeNode, range: CoordinateRange) bool {
        const min_ok = wgm.compare(.all, ctx.start, .less_than_equal, range.end);
        const max_ok = wgm.compare(.all, range.start, .less_than_equal, ctx.end);
        return min_ok and max_ok;
    }

    pub fn next(self: *RangeIterator) ?TreeIterator.Result {
        if (!self.first_run) self.iter.prepare_next_predicated(self.range, RangeIterator.predicate);
        self.first_run = false;
        return self.iter.next();
    }
};
