const std = @import("std");

const common = @import("common.zig");
const c = common.c;

const ConversionHelper = common.ConversionHelper;

pub fn get_flags(f: anytype) c.WGPUFlags {
    const IntType = @Type(.{
        .Int = .{
            .signedness = .unsigned,
            .bits = @bitSizeOf(@TypeOf(f)),
        },
    });

    const as_int: IntType = @bitCast(f);
    return @intCast(as_int);
}

fn RemoveOptional(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Optional => |v| v.child,
        else => T,
    };
}

test RemoveOptional {
    try std.testing.expectEqual(u32, RemoveOptional(u32));
    try std.testing.expectEqual(u32, RemoveOptional(?u32));
    try std.testing.expectEqual([:0]const u8, RemoveOptional(?[:0]const u8));
}

fn is_c_string(comptime T: type) bool {
    const U = RemoveOptional(T);

    const valid_types = [_]type{ [:0]const u8, [*:0]const u8 };
    inline for (valid_types) |ValidType| if (U == ValidType) return true;

    return false;
}

test is_c_string {
    try std.testing.expect(is_c_string([:0]const u8));
    try std.testing.expect(is_c_string(?[:0]const u8));
    try std.testing.expect(!is_c_string(?[:0]const u16));
}

inline fn wgpu_struct_get_recursive(helper: ?*ConversionHelper, comptime OutType: type, out: *OutType, comptime out_index: usize, comptime InType: type, in: InType, comptime in_index: usize) void {
    const in_field_info = @typeInfo(InType).Struct.fields[in_index];
    const InField = in_field_info.type;

    const in_value = @field(in, std.meta.fields(InType)[in_index].name);
    const out_ptr = &@field(out.*, std.meta.fields(OutType)[out_index].name);

    const out_increment = switch (@typeInfo(InField)) {
        .Int => val: {
            out_ptr.* = @intCast(in_value);
            break :val 1;
        },

        .Float => val: {
            out_ptr.* = @floatCast(in_value);
            break :val 1;
        },

        .Enum => val: {
            out_ptr.* = @intCast(@intFromEnum(in_value));
            break :val 1;
        },

        .Bool => val: {
            out_ptr.* = @intFromBool(in_value);
            break :val 1;
        },

        .Pointer => |v| val: {
            if (InField == [:0]const u8) {
                out_ptr.* = if (@as(?[:0]const u8, in_value)) |w| w.ptr else null;
                break :val 1;
            }

            out_ptr.* = in_value.len;

            // TODO
            _ = v;
            if (true) {
                @compileError(std.fmt.comptimePrint("type {any} at index {d} is not supported: array translation is NYI", .{ InField, in_index }));
            }

            break :val 2;
        },

        .Optional => |v| val: {
            if (InField == ?[:0]const u8) {
                out_ptr.* = if (@as(?[:0]const u8, in_value)) |w| w.ptr else null;
                break :val 1;
            }

            _ = v;
            if (true) {
                @compileError(std.fmt.comptimePrint("type {any} at index {d} is not supported: optional translation is NYI", .{ InField, in_index }));
            }

            break :val 1;
        },

        .Struct => |v| val: {
            if (v.layout == .@"packed") {
                out_ptr.* = @intCast(get_flags(in_value));
            }

            // TODO

            break :val 1;
        },

        else => @compileError(std.fmt.comptimePrint("unsupported type at index {d}: {any}", .{ in_index, InField })),
    };

    // std.log.err("cur: {any} @ {d}, {any} @ {d}", .{ void, out_index, InField, in_index });
    // std.log.err("next: {d} + {d}, {d} + 1", .{ out_index, out_increment, in_index });

    const in_finished = in_index + 1 == @typeInfo(InType).Struct.fields.len;
    const out_finished = out_index + out_increment == @typeInfo(OutType).Struct.fields.len;
    //comptime std.debug.assert(in_finished == out_finished);
    const finished = in_finished or out_finished;

    if (!finished) {
        wgpu_struct_get_recursive(helper, OutType, out, out_index + out_increment, InType, in, in_index + 1);
    }
}

/// Passing null as the first argument asserts that the structure requires no external storage (which may be required by optional fields or slices).
pub fn wgpu_struct_get(helper: ?*ConversionHelper, comptime NativeType: type, zig_struct: anytype) NativeType {
    const ZigType = @TypeOf(zig_struct);

    var out: NativeType = undefined;

    const start_out_index = if (comptime std.mem.eql(u8, std.meta.fields(NativeType)[0].name, "nextInChain")) val: {
        out.nextInChain = null;
        break :val 1;
    } else 0;

    wgpu_struct_get_recursive(helper, NativeType, &out, start_out_index, ZigType, zig_struct, 0);

    return out;
}

test wgpu_struct_get {
    const TestStructC = extern struct {
        label: [*c]const u8 = null,
        maybeALabel: [*c]const u8 = null, // there isn't really an example of this in wgpu.h
        // notALabel0Len: usize = 0,
        // notALabel0: [*c]const u32 = null,
        // notALabel1Len: usize = 0,
        // notALabel1: [*c]const u32 = null,

        aBool: c.WGPUBool = 0,

        anEnumeration: c_int = 0,
        someFlags: c.WGPUFlags = 0,
    };

    const TestFlags = packed struct {
        flag_0: bool,
        flag_1: bool,
        flag_2: bool,
    };

    const TestEnum = enum(u32) {
        Undefined = 0,
        Foo = 1,
        Bar = 2,
    };

    const TestStructZig = struct {
        label: ?[:0]const u8,
        maybe_a_label: [:0]const u8,
        // not_a_label_0: []const u32,
        // not_a_label_1: ?[]const u32,

        a_bool: bool,

        an_enumeration: TestEnum,
        some_flags: TestFlags,
    };

    const gotten = wgpu_struct_get(common.begin_helper(), TestStructC, TestStructZig{
        .label = "label",
        .maybe_a_label = "maybe a label",
        //.not_a_label_0 = &.{ 1, 2, 3 },
        //.not_a_label_1 = &.{ 4, 5, 6, 7 },

        .a_bool = false,

        .an_enumeration = .Bar,
        .some_flags = .{
            .flag_0 = false,
            .flag_1 = true,
            .flag_2 = true,
        },
    });

    try std.testing.expectEqual(.eq, std.mem.orderZ(u8, "label", gotten.label));
    try std.testing.expectEqual(.eq, std.mem.orderZ(u8, "maybe a label", gotten.maybeALabel));
    // try std.testing.expectEqual(3, gotten.notALabel0Len);
    // try std.testing.expectEqual(4, gotten.notALabel1Len);
    try std.testing.expectEqual(0, gotten.aBool);
    try std.testing.expectEqual(2, gotten.anEnumeration);
    try std.testing.expectEqual(6, gotten.someFlags);
}
