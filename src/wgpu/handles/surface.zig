const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const CompositeAlphaMode = wgpu.CompositeAlphaMode;
const Device = wgpu.Device;
const PresentMode = wgpu.PresentMode;
const Texture = wgpu.Texture;
const TextureFormat = wgpu.TextureFormat;
const TextureUsage = wgpu.TextureUsage;

const Surface = @This();

pub const SurfaceTexture = struct {
    pub const NativeType = c.WGPUSurfaceTexture;

    suboptimal: bool,
    texture: Texture,
};

pub const Configuration = struct {
    pub const NativeType = c.WGPUSurfaceConfiguration;

    device: Device,
    format: TextureFormat = .Undefined,
    usage: TextureUsage = .{},
    view_formats: []const TextureFormat = &.{},
    alpha_mode: CompositeAlphaMode = .Auto,
    width: u32 = 0,
    height: u32 = 0,
    present_mode: PresentMode = .Fifo,

    pub fn get(self: Configuration) Configuration.NativeType {
        return .{
            .nextInChain = null,
            .device = self.device.handle,
            .format = @intFromEnum(self.format),
            .usage = auto.get_flags(self.usage),
            .viewFormatCount = self.view_formats.len,
            .viewFormats = @ptrCast(self.view_formats.ptr),
            .alphaMode = @intFromEnum(self.alpha_mode),
            .width = self.width,
            .height = self.height,
            .presentMode = @intFromEnum(self.present_mode),
        };
    }
};

pub const Handle = c.WGPUSurface;

handle: Handle = null,

pub fn get_current_texture(self: Surface) Error!SurfaceTexture {
    var out: c.WGPUSurfaceTexture = undefined;
    c.wgpuSurfaceGetCurrentTexture(self.handle, &out);

    switch (out.status) {
        c.WGPUSurfaceGetCurrentTextureStatus_Success => {
            return .{
                .texture = .{ .handle = out.texture orelse return Error.UnexpectedNull },
                .suboptimal = out.suboptimal != 0,
            };
        },
        c.WGPUSurfaceGetCurrentTextureStatus_Timeout => return Error.Timeout,
        c.WGPUSurfaceGetCurrentTextureStatus_Outdated => return Error.Outdated,
        c.WGPUSurfaceGetCurrentTextureStatus_Lost => return Error.Lost,
        c.WGPUSurfaceGetCurrentTextureStatus_OutOfMemory => return Error.OutOfMemory,
        c.WGPUSurfaceGetCurrentTextureStatus_DeviceLost => return Error.DeviceLost,

        else => unreachable,
    }
}

pub fn configure(self: Surface, config: Configuration) Error!void {
    const c_config = config.get();
    c.wgpuSurfaceConfigure(self.handle, &c_config);
}

pub fn present(self: Surface) void {
    c.wgpuSurfacePresent(self.handle);
}
