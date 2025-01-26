const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const BackendType = wgpu.BackendType;
const Device = wgpu.Device;
const PowerPreference = wgpu.PowerPreference;
const Surface = wgpu.Surface;

const Adapter = @This();

pub const Options = struct {
    pub const NativeType = c.WGPURequestAdapterOptions;

    compatible_surface: Surface,
    power_preference: PowerPreference = .Undefined,
    backend_type: BackendType = .Undefined,
    force_fallback_adapter: bool = false,

    pub fn get(self: Options) Options.NativeType {
        return .{
            .nextInChain = null,
            .compatibleSurface = self.compatible_surface.handle,
            .powerPreference = @intFromEnum(self.power_preference),
            .backendType = @intFromEnum(self.backend_type),
            .forceFallbackAdapter = @intFromBool(self.force_fallback_adapter),
        };
    }
};

pub const Handle = c.WGPUAdapter;

handle: Handle = null,

pub fn deinit(self: Adapter) void {
    if (self.handle != null) c.wgpuAdapterRelease(self.handle);
}

pub fn request_device_sync(self: Adapter, descriptor: Device.Descriptor) !Device {
    return common.sync_request_impl(self, descriptor, Device, Adapter.request_device, "device");
}

pub fn request_device(self: Adapter, descriptor: Device.Descriptor, callback_arg: anytype) void {
    common.async_request_impl(
        self,
        descriptor.get(common.begin_helper()),
        callback_arg,
        c.wgpuAdapterRequestDevice,
        c.WGPURequestDeviceStatus_Success,
        [_]std.meta.Tuple(&.{ c_uint, Error }){
            .{ c.WGPURequestAdapterStatus_Error, Error.Error },
            .{ c.WGPURequestAdapterStatus_Unknown, Error.Unknown },
        },
        c.WGPUDevice,
        Device,
    );
}
