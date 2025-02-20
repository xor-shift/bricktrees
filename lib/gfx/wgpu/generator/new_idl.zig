const std = @import("std");
const util = @import("util.zig");

const RawIDL = @import("raw.zig");

const IDL = @This();

pub const Enumeration = struct {
    pub const Inner = struct {
        prefix: u32,
        fields: []?RawIDL.EBEntry,

        pub fn deinit(self: Inner, alloc: std.mem.Allocator) void {
            for (self.fields) |field| if (field) |v| v.deinit(alloc);
            alloc.free(self.fields);
        }
    };

    name: []const u8,
    field_groups: []Inner,

    pub fn init(alloc: std.mem.Allocator, name: []const u8) !Enumeration {
        const name_copy = try alloc.dupe(u8, name);
        errdefer alloc.free(name_copy);

        return .{
            .name = name_copy,
            .field_groups = alloc.alloc(Inner, 0) catch unreachable,
        };
    }

    pub fn deinit(self: Enumeration, alloc: std.mem.Allocator) void {
        alloc.free(self.name);

        for (self.field_groups) |group| group.deinit(alloc);
        alloc.free(self.field_groups);
    }

    pub fn get_group(self: Enumeration, prefix: u32) ?Inner {
        for (self.field_groups) |group| {
            if (group.prefix == prefix) return group;
        }

        return null;
    }

    pub fn add_group(self: *Enumeration, alloc: std.mem.Allocator, prefix: u32, fields: []const ?RawIDL.EBEntry) !void {
        const new_groups = try alloc.alloc(Inner, self.field_groups.len + 1);
        errdefer alloc.free(new_groups);

        @memcpy(new_groups[0..self.field_groups.len], self.field_groups);

        const new_group = &new_groups[new_groups.len - 1];

        new_group.* = .{
            .prefix = prefix,
            .fields = try alloc.alloc(?RawIDL.EBEntry, fields.len),
        };
        errdefer alloc.free(new_group.fields);

        var cloned_fields: usize = 0;
        errdefer for (0..cloned_fields) |i| if (new_group.fields[i]) |v| v.deinit(alloc);
        while (cloned_fields < fields.len) : (cloned_fields += 1) {
            new_group.fields[cloned_fields] = if (fields[cloned_fields]) |v|
                try v.clone(alloc)
            else
                null;
        }

        alloc.free(self.field_groups);
        self.field_groups = new_groups;
    }
};

alloc: std.mem.Allocator,
enumerations: std.ArrayListUnmanaged(Enumeration),
bitflags: std.ArrayListUnmanaged(RawIDL.EBDecl),

pub fn init(alloc: std.mem.Allocator) IDL {
    return .{
        .alloc = alloc,
        .enumerations = .{},
        .bitflags = .{},
    };
}

pub fn deinit(self: *IDL) void {
    for (self.enumerations.items) |enumeration| enumeration.deinit(self.alloc);
    self.enumerations.deinit(self.alloc);

    for (self.bitflags.items) |bitflags| bitflags.deinit(self.alloc);
    self.bitflags.deinit(self.alloc);
}

pub fn try_get_enumeration(self: *IDL, name: []const u8) ?*Enumeration {
    for (0.., self.enumerations.items) |i, enumeration| {
        if (std.mem.eql(u8, enumeration.name, name)) {
            return &self.enumerations.items[i];
        }
    }

    return null;
}

pub fn get_or_init_enumeration(self: *IDL, name: []const u8) !*Enumeration {
    if (self.try_get_enumeration(name)) |v| return v;

    try self.enumerations.append(
        self.alloc,
    );

    return &self.enumerations.items[self.enumerations.items.len - 1];
}

fn append_raw_enum(self: *IDL, raw_enum: RawIDL.EBDecl, prefix: u32) !void {
    if (self.try_get_enumeration(raw_enum.name)) |preexisting| {
        std.log.debug("preexisting group for enumeration \"{s}\"", .{raw_enum.name});
        try preexisting.add_group(self.alloc, prefix, raw_enum.entries);
    } else {
        std.log.debug("new enumeration group for \"{s}\"", .{raw_enum.name});
        var new_enum = try Enumeration.init(self.alloc, raw_enum.name);
        errdefer new_enum.deinit(self.alloc);

        try new_enum.add_group(self.alloc, prefix, raw_enum.entries);

        try self.enumerations.append(self.alloc, new_enum);
    }
}

pub fn append_raw(self: *IDL, raw: RawIDL) !void {
    const prefix = try std.fmt.parseInt(u32, raw.enum_prefix[2..], 16);

    for (raw.enums) |raw_enumeration| {
        try self.append_raw_enum(raw_enumeration, prefix);
    }

    for (raw.bitflags) |raw_bitflags| {
        try self.bitflags.append(self.alloc, try raw_bitflags.clone(self.alloc));
    }
}
