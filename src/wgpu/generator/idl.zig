const std = @import("std");
const util = @import("util.zig");
const idl_utils = @import("idl_utils.zig");

const RawIDL = @import("raw.zig");

const IDL = @This();

pub const Enumeration = struct {
    inner: idl_utils.EBFImpl,

    pub fn deinit(self: Enumeration, alloc: std.mem.Allocator) void {
        return self.inner.deinit(alloc);
    }

    pub fn clone(self: Enumeration, alloc: std.mem.Allocator) !Enumeration {
        return .{ .inner = try self.inner.clone(alloc) };
    }

    pub fn merge_with(self: Enumeration, other: Enumeration, alloc: std.mem.Allocator) !Enumeration {
        return .{ .inner = try self.inner.merge_with(other.inner, alloc) };
    }

    pub fn write_zig_struct(self: Enumeration, idl: IDL, writer: anytype) !void {
        _ = idl;

        try std.fmt.format(writer, "pub const {s} = enum(c_uint) {{\n", .{self.inner.name});
        for (0.., self.inner.fields) |i, field| {
            try std.fmt.format(writer, "    {s} = {d},\n", .{ field, i });
        }
        _ = try writer.write("};\n");
    }
};

pub const Bitflags = struct {
    inner: idl_utils.EBFImpl,

    pub fn deinit(self: Bitflags, alloc: std.mem.Allocator) void {
        return self.inner.deinit(alloc);
    }

    pub fn clone(self: Bitflags, alloc: std.mem.Allocator) !Bitflags {
        return .{ .inner = try self.inner.clone(alloc) };
    }

    pub fn merge_with(self: Bitflags, other: Bitflags, alloc: std.mem.Allocator) !Bitflags {
        return .{ .inner = try self.inner.merge_with(other.inner, alloc) };
    }

    pub fn deficiency(self: Bitflags) usize {
        return 32 - self.inner.fields.len;
    }

    pub fn write_zig_struct(self: Bitflags, idl: IDL, writer: anytype) !void {
        _ = idl;

        try std.fmt.format(writer, "pub const {s} = packed struct(u32) {{\n", .{self.inner.name});
        for (self.inner.fields) |flag| {
            try std.fmt.format(writer, "    {s}: bool = false,\n", .{flag});
        }
        try std.fmt.format(writer, "    _padding: u{d} = 0,\n}};\n", .{self.deficiency()});
    }
};

enumerations: std.StringHashMapUnmanaged(Enumeration) = .{},
bitflags: std.StringHashMapUnmanaged(Bitflags) = .{},

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

pub fn init() IDL {
    return .{
        .enumerations = .{},
        .bitflags = .{},
    };
}

pub fn from_raw(raw_idl: RawIDL, alloc: std.mem.Allocator) !IDL {
    var ret = IDL.init();

    try iterate_enum_or_bitflags(true, raw_idl.enums, alloc, struct {
        alloc: std.mem.Allocator,
        self: *IDL,
        raw_idl: RawIDL,

        fn start(ctx: @This(), name: []const u8, num_fields: usize) !void {
            const name_copy = try ctx.alloc.dupe(u8, name);
            try ctx.self.enumerations.put(ctx.alloc, name_copy, Enumeration{ .inner = .{
                .name = name_copy,
                .fields = try ctx.alloc.alloc([]const u8, num_fields),
            } });
        }

        fn field(ctx: @This(), name: []const u8, index: usize, field_name: []const u8) !void {
            ctx.self.enumerations.getPtr(name).?.inner.fields[index] = try ctx.alloc.dupe(u8, field_name);
        }

        fn end(ctx: @This(), name: []const u8) !void {
            _ = ctx;
            _ = name;
        }
    }{ .self = &ret, .alloc = alloc, .raw_idl = raw_idl });

    try iterate_enum_or_bitflags(false, raw_idl.bitflags, alloc, struct {
        alloc: std.mem.Allocator,
        self: *IDL,

        fn start(ctx: @This(), name: []const u8, num_fields: usize) !void {
            const name_copy = try ctx.alloc.dupe(u8, name);
            try ctx.self.bitflags.put(ctx.alloc, name_copy, Bitflags{ .inner = .{
                .name = name_copy,
                .fields = try ctx.alloc.alloc([]const u8, num_fields - 1),
            } });
        }

        fn field(ctx: @This(), name: []const u8, index: usize, field_name: []const u8) !void {
            if (index == 0) {
                std.debug.assert(std.mem.eql(u8, field_name, "none"));
                return;
            }

            ctx.self.bitflags.getPtr(name).?.inner.fields[index - 1] = try ctx.alloc.dupe(u8, field_name);
        }

        fn end(ctx: @This(), name: []const u8) !void {
            _ = ctx;
            _ = name;
        }
    }{ .self = &ret, .alloc = alloc });

    return ret;
}

pub fn deinit(self: *IDL, alloc: std.mem.Allocator) void {
    idl_utils.deinit_hashmap_impl(&self.enumerations, alloc);
    idl_utils.deinit_hashmap_impl(&self.bitflags, alloc);

    self.* = undefined;
}

pub fn clone(self: IDL, alloc: std.mem.Allocator) !IDL {
    var cloned_enumerations = try idl_utils.clone_hashmap_impl(self.enumerations, alloc);
    errdefer idl_utils.deinit_hashmap_impl(&cloned_enumerations, alloc);

    var cloned_bitflags = try idl_utils.clone_hashmap_impl(self.bitflags, alloc);
    errdefer idl_utils.deinit_hashmap_impl(&cloned_bitflags, alloc);

    return .{
        .enumerations = cloned_enumerations,
        .bitflags = cloned_bitflags,
    };
}

pub fn merge_with(self: IDL, other: IDL, alloc: std.mem.Allocator) !IDL {
    var ret = try self.clone(alloc);
    errdefer ret.deinit(alloc);

    try idl_utils.merge_impl(&ret.enumerations, other.enumerations, alloc);
    try idl_utils.merge_impl(&ret.bitflags, other.bitflags, alloc);

    return ret;
}
