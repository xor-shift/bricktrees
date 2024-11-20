const std = @import("std");
const util = @import("util.zig");

const RawIDL = @import("raw.zig");

const IDL = @This();

pub const Field = struct {
    kind: enum {
        Primitive,
        String,
        Enumeration,
        Structure,
        Object,
    },

    is_array: bool,

    pub fn is_externable(self: @This(), idl: IDL) bool {
        if (self.is_array) {
            return false;
        }

        if (self.kind == .Structure) {}

        _ = idl;
        return true;
    }
};

pub const Enumeration = struct {
    name: []const u8,
    fields: [][]const u8,

    fn deinit(self: Enumeration, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        for (self.fields) |v| alloc.free(v);
        alloc.free(self.fields);
    }

    pub fn write_zig_struct(self: Enumeration, idl: IDL, writer: anytype) !void {
        _ = idl;

        try std.fmt.format(writer, "pub const {s} = enum(c_uint) {{\n", .{self.name});
        for (0.., self.fields) |i, field| {
            try std.fmt.format(writer, "    {s} = {d},\n", .{ field, i });
        }
        _ = try writer.write("};\n");
    }
};

pub const Bitflags = struct {
    name: []const u8,
    flags: [][]const u8,

    fn deinit(self: Bitflags, alloc: std.mem.Allocator) void {
        alloc.free(self.name);
        for (self.flags) |v| alloc.free(v);
        alloc.free(self.flags);
    }

    pub fn deficiency(self: Bitflags) usize {
        return 32 - self.flags.len;
    }

    pub fn write_zig_struct(self: Bitflags, idl: IDL, writer: anytype) !void {
        _ = idl;

        try std.fmt.format(writer, "pub const {s} = packed struct(u32) {{\n", .{self.name});
        for (self.flags) |flag| {
            try std.fmt.format(writer, "    {s}: bool = false,\n", .{flag});
        }
        try std.fmt.format(writer, "    _padding: u{d} = 0,\n}};\n", .{self.deficiency()});
    }
};

pub const Structure = struct {
    kind: enum {
        Standalone,
    },

    fields: []const Field,
};

enumerations: std.StringHashMapUnmanaged(Enumeration) = .{},
bitflags: std.StringHashMapUnmanaged(Bitflags) = .{},
structures: std.StringHashMapUnmanaged(Structure) = .{},

fn iterate_enum_or_bitflags(comptime pascal_field: bool, declarations: []const RawIDL.EBDecl, alloc: std.mem.Allocator, thing: anytype) !void {
    for (declarations) |decl| {
        const decl_name_pascal: []const u8 = try util.snake_to_pascal(decl.name, alloc);
        defer alloc.free(decl_name_pascal);

        try thing.start(decl_name_pascal, decl.entries.len);

        for (0.., decl.entries) |i, entry| {
            if (std.mem.eql(u8, entry.name, "error")) {
                const to_feed = if (pascal_field) "Error" else "err";
                try thing.field(decl_name_pascal, i, to_feed);
                continue;
            }

            const to_feed: []const u8 = val: {
                const ret = try (if (pascal_field) util.snake_to_pascal else util.snake_to_snake)(entry.name, alloc);
                util.swap_first_two_chars_if_leading_is_digit(&ret);
                break :val ret;
            };
            defer alloc.free(to_feed);

            try thing.field(decl_name_pascal, i, to_feed);
        }

        try thing.end(decl_name_pascal);
    }
}

pub fn from_raw(raw_idl: RawIDL, alloc: std.mem.Allocator) !IDL {
    var ret: IDL = .{
        .enumerations = .{},
        .bitflags = .{},
        .structures = .{},
    };

    try iterate_enum_or_bitflags(true, raw_idl.enums, alloc, struct {
        alloc: std.mem.Allocator,
        self: *IDL,

        fn start(ctx: @This(), name: []const u8, num_fields: usize) !void {
            const name_copy = try ctx.alloc.dupe(u8, name);
            try ctx.self.enumerations.put(ctx.alloc, name_copy, Enumeration{
                .name = name_copy,
                .fields = try ctx.alloc.alloc([]const u8, num_fields),
            });
        }

        fn field(ctx: @This(), name: []const u8, index: usize, field_name: []const u8) !void {
            ctx.self.enumerations.getPtr(name).?.fields[index] = try ctx.alloc.dupe(u8, field_name);
        }

        fn end(ctx: @This(), name: []const u8) !void {
            _ = ctx;
            _ = name;
        }
    }{ .self = &ret, .alloc = alloc });

    try iterate_enum_or_bitflags(false, raw_idl.bitflags, alloc, struct {
        alloc: std.mem.Allocator,
        self: *IDL,

        fn start(ctx: @This(), name: []const u8, num_fields: usize) !void {
            const name_copy = try ctx.alloc.dupe(u8, name);
            try ctx.self.bitflags.put(ctx.alloc, name_copy, Bitflags{
                .name = name_copy,
                .flags = try ctx.alloc.alloc([]const u8, num_fields - 1),
            });
        }

        fn field(ctx: @This(), name: []const u8, index: usize, field_name: []const u8) !void {
            if (index == 0) {
                std.debug.assert(std.mem.eql(u8, field_name, "none"));
                return;
            }

            ctx.self.bitflags.getPtr(name).?.flags[index - 1] = try ctx.alloc.dupe(u8, field_name);
        }

        fn end(ctx: @This(), name: []const u8) !void {
            _ = ctx;
            _ = name;
        }
    }{ .self = &ret, .alloc = alloc });

    return ret;
}

pub fn deinit(self: *IDL, alloc: std.mem.Allocator) void {
    var enum_iter = self.enumerations.iterator();
    while (enum_iter.next()) |kv| kv.value_ptr.deinit(alloc);
    self.enumerations.deinit(alloc);

    var bitflags_iter = self.bitflags.iterator();
    while (bitflags_iter.next()) |kv| kv.value_ptr.deinit(alloc);
    self.bitflags.deinit(alloc);
}
