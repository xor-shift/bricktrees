const std = @import("std");

pub const c = @cImport({
    @cInclude("webgpu.h");
    // extensions
    @cInclude("wgpu.h");
});

pub const sdl_c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_system.h");
});

const auto = @import("auto.zig");

pub const Error = error{
    UnexpectedNull,

    OutOfMemory,

    InstanceDropped,
    Unavailable,
    Error,
    Unknown,
    DeviceLost,

    Timeout,
    Outdated,
    Lost,
};

/// A small arena meant to assist in the conversion of structs from Zig ones to C ones.
///
/// A funny side effect of this thing is that some conversions from Zig to C are not signal safe.
pub const ConversionHelper = struct {
    remaining: []u8 = undefined,

    pub fn begin(self: *@This(), buffer: []u8) void {
        self.remaining = buffer;
    }

    pub fn alloc(self: *@This(), comptime T: type, n: usize) []T {
        const aligned = std.mem.alignInBytes(self.remaining, @alignOf(T)) orelse unreachable;
        const ret = aligned[0 .. n * @sizeOf(T)];
        self.remaining = aligned[n * @sizeOf(T) ..];
        return @as([*]T, @ptrCast(@as([*]align(@alignOf(T)) u8, @alignCast(ret.ptr))))[0..n];
    }

    pub fn create(self: *ConversionHelper, comptime T: type) *T {
        return &self.alloc(T, 1)[0];
    }

    pub fn optional_helper(self: *ConversionHelper, comptime pass_on_helper: bool, comptime T: type, v: ?T) ?*T.NativeType {
        if (v == null) return null;

        const ret = self.create(T.NativeType);
        ret.* = if (pass_on_helper) v.?.get(self) else v.?.get();
        return ret;
    }

    pub fn array_helper(self: *ConversionHelper, comptime pass_on_helper: bool, comptime T: type, v: []const T) [*]T.NativeType {
        const ret = self.alloc(T.NativeType, v.len);
        for (0.., v) |i, elem| ret[i] = if (pass_on_helper) elem.get(self) else elem.get();
        return ret.ptr;
    }
};

pub threadlocal var conversion_helper_buffer: [8 * 1024]u8 = undefined;
pub threadlocal var conversion_helper: ConversionHelper = .{};

pub fn begin_helper() *ConversionHelper {
    conversion_helper.begin(&conversion_helper_buffer);
    return &conversion_helper;
}

pub fn sync_request_impl(
    self: anytype,
    zig_descriptor: anytype,
    comptime Requested: type,
    comptime requester: fn (@TypeOf(self), @TypeOf(zig_descriptor), callback: anytype) void,
    comptime requested_name: []const u8,
) Error!Requested {
    var res: Error!Requested = undefined;

    requester(self, zig_descriptor, struct {
        out_res: *Error!Requested,

        fn aufruf(ctx: @This(), res_arg: Error!Requested, error_desc: []const u8) void {
            const actual_res = res_arg catch |e| {
                std.log.err("failed to request a/an " ++ requested_name ++ ". error: {any}, error_desc: {?s}", .{ e, error_desc });
                ctx.out_res.* = e;
                return;
            };

            ctx.out_res.* = actual_res;
        }
    }{ .out_res = &res });

    return res;
}

pub fn async_request_impl(
    self: anytype,
    c_descriptor: anytype,
    callback_arg: anytype,
    comptime requester_fun: anytype, // cant be bothered
    comptime success_code: c_uint,
    comptime result_codes: anytype,
    comptime WGPUType: type,
    comptime InfoType: type,
    comptime Type: type,
) void {
    const Callback = @TypeOf(callback_arg);

    const actual_callback = struct {
        fn aufruf(status: c_uint, maybe_res: WGPUType, error_desc: c.WGPUStringView, userdata1: ?*anyopaque, userdata2: ?*anyopaque) callconv(.C) void {
            _ = userdata2;
            const callback: *Callback = @ptrCast(@alignCast(userdata1));

            if (status == success_code) {
                const res = maybe_res orelse {
                    callback.aufruf(Error.UnexpectedNull, auto.from_string(error_desc));
                    return;
                };
                callback.aufruf(Type{ .handle = res }, auto.from_string(error_desc));
                return;
            }

            inline for (result_codes) |code_err_pair| {
                if (status == code_err_pair.@"0") {
                    callback.aufruf(code_err_pair.@"1", auto.from_string(error_desc));
                    return;
                }
            }

            unreachable;
        }
    }.aufruf;

    const info: InfoType = .{
        .nextInChain = null,
        .mode = c.WGPUCallbackMode_AllowProcessEvents,
        .callback = actual_callback,
        .userdata1 = @constCast(@ptrCast(&callback_arg)),
        .userdata2 = null,
    };

    //const converted_descriptor = options.get();
    // TODO: ignored future
    _ = requester_fun(self.handle, &c_descriptor, info);
}
