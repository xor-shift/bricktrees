const std = @import("std");

pub const EBFImpl = struct {
    name: []const u8,
    fields: [][]const u8,

    pub fn deinit(self: EBFImpl, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        for (self.fields) |v| alloc.free(v);
        alloc.free(self.fields);
    }

    pub fn clone(self: EBFImpl, alloc: std.mem.Allocator) !EBFImpl {
        return self.merge_with(.{
            .name = self.name,
            .fields = &.{},
        }, alloc);
    }

    pub fn merge_with(self: EBFImpl, other: EBFImpl, alloc: std.mem.Allocator) !EBFImpl {
        std.debug.assert(std.mem.eql(u8, self.name, other.name));

        const name_copy = try alloc.dupe(u8, self.name);
        errdefer alloc.free(name_copy);

        var copied_fields: usize = 0;
        const fields_copy = try alloc.alloc([]u8, self.fields.len);
        errdefer alloc.free(fields_copy);
        errdefer for (0..copied_fields) |i| alloc.free(fields_copy[i]);

        for (0..self.fields.len) |i| {
            fields_copy[copied_fields] = try alloc.dupe(u8, self.fields[i]);
            copied_fields += 1;
        }

        for (0..other.fields.len) |i| {
            fields_copy[copied_fields] = try alloc.dupe(u8, other.fields[i]);
            copied_fields += 1;
        }

        return .{
            .name = name_copy,
            .fields = fields_copy,
        };
    }
};

pub fn deinit_hashmap_impl(map: anytype, alloc: std.mem.Allocator) void {
    var iter = map.iterator();
    while (iter.next()) |kv| kv.value_ptr.deinit(alloc);
    map.deinit(alloc);
}

pub fn clone_hashmap_impl(map: anytype, alloc: std.mem.Allocator) !@TypeOf(map) {
    var cloned = try map.clone(alloc);
    errdefer cloned.deinit(alloc);
    var iter = cloned.iterator();

    var managed_to_clone: usize = 0;
    errdefer {
        var iter_ = cloned.iterator();
        while (iter_.next()) |entry| {
            if (managed_to_clone == 0) break;
            managed_to_clone -= 1;

            entry.value_ptr.deinit(alloc);
        }
    }

    while (iter.next()) |entry| {
        entry.value_ptr.* = try entry.value_ptr.clone(alloc);
        entry.key_ptr.* = entry.value_ptr.inner.name;
        managed_to_clone += 1;
    }

    return cloned;
}

pub fn merge_impl(lhs: anytype, rhs: anytype, alloc: std.mem.Allocator) !void {
    var iter = rhs.iterator();
    while (iter.next()) |other_entry| {
        if (lhs.getEntry(other_entry.key_ptr.*)) |self_entry| {
            const merged = try self_entry.value_ptr.merge_with(other_entry.value_ptr.*, alloc);
            errdefer merged.deinit(alloc);

            try lhs.put(alloc, merged.inner.name, merged);
        } else {
            const cloned = try other_entry.value_ptr.clone(alloc);
            errdefer cloned.deinit(alloc);

            try lhs.put(alloc, cloned.inner.name, cloned);
        }
    }
}
