const std = @import("std");

pub const Self = @This();

pub const GraphType = std.StringHashMapUnmanaged(std.StringHashMapUnmanaged(void));

pub const Iterator = struct {
    alloc: std.mem.Allocator,

    graph: GraphType,

    remaining: std.StringHashMapUnmanaged(usize),

    queue_ptr: usize = 0,
    queue: std.ArrayListUnmanaged([]const u8),

    pub fn init(dependency_graph: GraphType, alloc: std.mem.Allocator) !Iterator {
        var remaining: std.StringHashMapUnmanaged(usize) = .{};
        var queue: std.ArrayListUnmanaged([]const u8) = .{};

        errdefer remaining.deinit(alloc);
        errdefer queue.deinit(alloc);

        var iter = dependency_graph.iterator();
        while (iter.next()) |entry| {
            const count = entry.value_ptr.count();

            try remaining.put(alloc, entry.key_ptr.*, count);

            if (count == 0) try queue.append(alloc, entry.key_ptr.*);
        }

        return .{
            .alloc = alloc,
            .graph = dependency_graph,

            .remaining = remaining,

            .queue = queue,
        };
    }

    pub fn deinit(self: *Iterator) void {
        self.remaining.deinit(self.alloc);
        self.queue.deinit(self.alloc);
    }

    pub fn next(self: *Iterator) ?[]const u8 {
        if (self.queue_ptr == self.queue.items.len) return null;
        const ret = self.queue.items[self.queue_ptr];
        self.queue_ptr += 1;
        return ret;
    }

    pub fn done(self: *Iterator, name: []const u8) !void {
        var iter = self.graph.iterator();
        while (iter.next()) |entry| {
            if (!entry.value_ptr.contains(name)) continue;

            const inner = self.remaining.getEntry(entry.key_ptr.*) orelse unreachable;
            std.debug.assert(inner.value_ptr.* != 0);

            if (inner.value_ptr.* == 1) {
                try self.queue.append(self.alloc, entry.key_ptr.*);
            }

            inner.value_ptr.* -= 1;
        }
    }
};

alloc: std.mem.Allocator,

/// `['a'] = ['b', 'c']` means that 'a' must run after 'b' and 'c', meaning
/// that it depends on the two.
///
/// The values in the inner hash set are not owned as every known identifier
/// must have an entry in the outer one, regardless of whether they have
/// dependencies. This means that, for the above example to be possible, there
/// must exist two additional entries: `['b'] = []` and ['c'] = []`.
graph: std.StringHashMapUnmanaged(std.StringHashMapUnmanaged(void)),

pub fn init(gpa: std.mem.Allocator) Self {
    return .{
        .alloc = gpa,
        .graph = .{},
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.graph.iterator();
    while (iter.next()) |item| {
        self.alloc.free(item.key_ptr.*);
        item.value_ptr.deinit(self.alloc);
    }

    self.graph.deinit(self.alloc);
}

fn add_one(self: *Self, v: []const u8) !GraphType.GetOrPutResult {
    const res = try self.graph.getOrPutAdapted(self.alloc, v, std.hash_map.StringContext{});
    errdefer if (!res.found_existing) {
        _ = self.graph.remove(v);
    };

    if (!res.found_existing) {
        const copy = try self.alloc.dupe(u8, v);

        res.key_ptr.* = copy;
        res.value_ptr.* = .{};
    }

    return res;
}

/// `before` is the dependency and `after` is the dependant.
pub fn add_dependency(self: *Self, before: []const u8, after: []const u8) !void {
    const b_res = try self.add_one(before);
    errdefer if (!b_res.found_existing) self.alloc.free(b_res.key_ptr.*);
    errdefer if (!b_res.found_existing) {
        _ = self.graph.remove(before);
    };

    const a_res = try self.add_one(after);
    errdefer if (!a_res.found_existing) self.alloc.free(a_res.key_ptr.*);
    errdefer if (!a_res.found_existing) {
        _ = self.graph.remove(after);
    };

    try a_res.value_ptr.put(self.alloc, b_res.key_ptr.*, {});
}

pub fn start(self: *Self) !Iterator {
    return try Iterator.init(self.graph, self.alloc);
}

test {
    const alloc = std.testing.allocator;

    var graph = Self.init(alloc);
    defer graph.deinit();

    try graph.add_dependency("a", "b");
    try graph.add_dependency("b", "c");
    try graph.add_dependency("b", "d");

    try graph.add_dependency("x", "y");

    const iter_to_vec = struct {
        fn aufruf(comptime T: type, gpa: std.mem.Allocator, iter: anytype) std.ArrayList(T) {
            var ret = std.ArrayList(T).init(gpa);

            while (iter.next()) |item| ret.append(item) catch unreachable;

            return ret;
        }
    }.aufruf;

    const str_asc = struct {
        fn aufruf(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.aufruf;

    var iter = try graph.start();
    defer iter.deinit();

    const do_iteration = struct {
        fn aufruf(iterator: anytype, expected: []const []const u8) !void {
            const vec = iter_to_vec([]const u8, alloc, iterator);
            std.mem.sort([]const u8, vec.items, {}, str_asc);
            defer vec.deinit();

            try std.testing.expectEqual(expected.len, vec.items.len);
            for (0..expected.len) |i| try std.testing.expectEqualSlices(u8, expected[i], vec.items[i]);

            for (vec.items) |item| iterator.done(item) catch unreachable;
        }
    }.aufruf;

    try do_iteration(&iter, &.{ "a", "x" });
    try do_iteration(&iter, &.{ "b", "y" });
    try do_iteration(&iter, &.{ "c", "d" });
    try do_iteration(&iter, &.{});
}
