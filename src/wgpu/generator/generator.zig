const std = @import("std");
const util = @import("util.zig");

const IDL = @import("idl.zig");
const RawIDL = @import("raw.zig");

fn emit_bitflags(idl: IDL, alloc: std.mem.Allocator) !void {
    const cwd = std.fs.cwd();
    const out_file = try cwd.createFile("../generated/bitflags.zig", .{});
    defer out_file.close();

    const writer = out_file.writer();

    _ = alloc;

    var iterator = idl.bitflags.iterator();
    var i: usize = 0;
    while (iterator.next()) |kv| {
        defer i += 1;
        if (i != 0) {
            try writer.writeByte('\n');
        }

        try kv.value_ptr.write_zig_struct(idl, writer);
    }
}

fn emit_enums(idl: IDL, alloc: std.mem.Allocator) !void {
    const cwd = std.fs.cwd();
    const out_file = try cwd.createFile("../generated/enums.zig", .{});
    defer out_file.close();

    const writer = out_file.writer();

    _ = alloc;

    var iterator = idl.enumerations.iterator();
    var i: usize = 0;
    while (iterator.next()) |kv| {
        defer i += 1;
        if (i != 0) {
            try writer.writeByte('\n');
        }

        try kv.value_ptr.write_zig_struct(idl, writer);
    }
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const raw_idl_val = try RawIDL.from_file("webgpu.json", alloc);
    defer raw_idl_val.deinit();
    const raw_idl = raw_idl_val.value;

    var idl = try IDL.from_raw(raw_idl, alloc);
    defer idl.deinit(alloc);

    std.log.debug("idl: {any}", .{idl});

    try emit_enums(idl, alloc);
    try emit_bitflags(idl, alloc);
}
