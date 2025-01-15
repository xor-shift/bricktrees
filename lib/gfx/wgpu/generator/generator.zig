const std = @import("std");
const util = @import("util.zig");

const IDL = @import("new_idl.zig");
const RawIDL = @import("raw.zig");

// fn emit_bitflags(idl: IDL, alloc: std.mem.Allocator) !void {
//     const cwd = std.fs.cwd();
//     const out_file = try cwd.createFile("../generated/bitflags.zig", .{});
//     defer out_file.close();
//
//     const writer = out_file.writer();
//
//     _ = alloc;
//
//     var iterator = idl.bitflags.iterator();
//     var i: usize = 0;
//     while (iterator.next()) |kv| {
//         defer i += 1;
//         if (i != 0) {
//             try writer.writeByte('\n');
//         }
//
//         try kv.value_ptr.write_zig_struct(idl, writer);
//     }
// }

fn write_enum(enumeration: IDL.Enumeration, writer: std.io.AnyWriter, alloc: std.mem.Allocator) !void {
    const enum_name = try util.snake_to_pascal(enumeration.name, alloc);
    defer alloc.free(enum_name);
    try std.fmt.format(writer, "pub const {s} = enum(c_uint) {{\n", .{enum_name});

    for (0.., enumeration.field_groups) |group_no, group| {
        for (0.., group.fields) |i, field| {
            const field_name = try util.snake_to_pascal(field.name, alloc);
            defer alloc.free(field_name);

            util.swap_first_two_chars_if_leading_is_digit(&field_name);

            const index = (if (group_no == 0) i else i + 1) + (group.prefix << 16);

            try std.fmt.format(writer, "    {s} = 0x{X:0>8},\n", .{ field_name, index });
        }
    }

    try std.fmt.format(writer, "}}; // {s}\n", .{enum_name});
}

fn emit_enums(idl: IDL, alloc: std.mem.Allocator) !void {
    const cwd = std.fs.cwd();
    const out_file = try cwd.createFile("../generated/enums.zig", .{});
    defer out_file.close();

    const writer = out_file.writer();
    // const writer = std.io.null_writer;

    for (0.., idl.enumerations.items) |i, enumeration| {
        if (i != 0) {
            try writer.writeByte('\n');
        }

        try write_enum(enumeration, writer.any(), alloc);
    }
}

fn write_bitflag(bitflags: RawIDL.EBDecl, writer: std.io.AnyWriter, alloc: std.mem.Allocator) !void {
    const bitflag_name = try util.snake_to_pascal(bitflags.name, alloc);
    defer alloc.free(bitflag_name);
    try std.fmt.format(writer, "pub const {s} = packed struct(u32) {{\n", .{bitflag_name});

    for (bitflags.entries) |flag| {
        const flag_name = try util.snake_to_pascal(flag.name, alloc);
        defer alloc.free(flag_name);

        try std.fmt.format(writer, "    {s}: bool = false,\n", .{flag_name});
    }

    const slack = 32 - bitflags.entries.len;
    if (slack != 0) {
        try std.fmt.format(writer, "_padding: u{d} = 0,", .{ slack });
    }

    try std.fmt.format(writer, "}}; // {s}\n", .{bitflag_name});
}

fn emit_bitflags(idl: IDL, alloc: std.mem.Allocator) !void {
    const cwd = std.fs.cwd();
    const out_file = try cwd.createFile("../generated/enums.zig", .{});
    defer out_file.close();

    const writer = out_file.writer();
    // const writer = std.io.null_writer;

    for (0.., idl.bitflags.items) |i, bitflags| {
        if (i != 0) {
            try writer.writeByte('\n');
        }

        try write_bitflag(bitflags, writer.any(), alloc);
    }
}

pub fn mk_idl(files: []const []const u8, alloc: std.mem.Allocator) !IDL {
    var ret = IDL.init(alloc);
    errdefer ret.deinit();

    for (files) |filename| {
        const raw_idl_val = try RawIDL.from_file(filename, alloc);
        defer raw_idl_val.deinit();
        const raw_idl = raw_idl_val.value;

        try ret.append_raw(raw_idl);
    }

    return ret;
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var idl = try mk_idl(&.{ "webgpu.json", "wgpu.json" }, alloc);
    defer idl.deinit();

    // std.log.debug("idl: {any}", .{idl});

    try emit_enums(idl, alloc);
    // try emit_bitflags(idl, alloc);
}
