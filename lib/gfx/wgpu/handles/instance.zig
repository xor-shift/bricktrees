const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const Adapter = wgpu.Adapter;

const Instance = @This();

pub const Handle = c.WGPUInstance;

handle: Handle = null,

pub fn init() Instance {
    const instance = c.wgpuCreateInstance(&.{}) orelse {
        @panic("failed to create a wgpu instance");
    };

    return .{
        .handle = instance,
    };
}

pub fn deinit(self: Instance) void {
    if (self.handle != null) c.wgpuInstanceRelease(self.handle);
}

pub fn request_adapter_sync(self: Instance, options: Adapter.Options) !Adapter {
    return common.sync_request_impl(
        self,
        options,
        Adapter,
        Instance.request_adapter,
        "adapter",
    );
}

pub fn request_adapter(self: Instance, options: Adapter.Options, callback_arg: anytype) void {
    common.async_request_impl(
        self,
        options.get(),
        callback_arg,
        c.wgpuInstanceRequestAdapter,
        c.WGPURequestAdapterStatus_Success,
        [_]std.meta.Tuple(&.{ c_uint, Error }){
            .{ c.WGPURequestAdapterStatus_Unavailable, Error.Unavailable },
            .{ c.WGPURequestAdapterStatus_Error, Error.Error },
            .{ c.WGPURequestAdapterStatus_Unknown, Error.Unknown },
        },
        c.WGPUAdapter,
        c.WGPURequestAdapterCallbackInfo,
        Adapter,
    );
}
