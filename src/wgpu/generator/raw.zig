const std = @import("std");

pub const ConstantDecl = struct {
    name: []const u8,
    value: []const u8,
    doc: []const u8,
};

pub const EBEntry = struct {
    name: []const u8,
    doc: []const u8,
};

pub const EBDecl = struct {
    name: []const u8,
    doc: []const u8,
    entries: []const EBEntry,
};

pub const StructMember = struct {
    name: []const u8,
    doc: []const u8,
    type: []const u8,
    optional: bool = false,
};

pub const StructDecl = struct {
    name: []const u8,
    doc: []const u8,
    type: []const u8,
    members: []const StructMember = &.{},
};

copyright: []const u8,
name: []const u8,
enum_prefix: []const u8,

constants: []const ConstantDecl,
enums: []const EBDecl,
bitflags: []const EBDecl,
structs: []const StructDecl,

const RawIDL = @This();

pub fn from_file(filename: []const u8, alloc: std.mem.Allocator) !std.json.Parsed(RawIDL) {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{});
    defer file.close();

    var json_reader = std.json.reader(alloc, file.reader());
    defer json_reader.deinit();

    var diagnostics: std.json.Diagnostics = .{};
    json_reader.enableDiagnostics(&diagnostics);

    const res = val: {
        const res_or_err = std.json.parseFromTokenSource(RawIDL, alloc, &json_reader, .{
            .ignore_unknown_fields = true,
        });
        const res = res_or_err catch |e| {
            std.log.err("failed to parse at line {d}, column {d} (i.e. at the byte offset {d})", .{
                diagnostics.getLine(),
                diagnostics.getColumn(),
                diagnostics.getByteOffset(),
            });
            return e;
        };
        break :val res;
    };

    return res;
}
