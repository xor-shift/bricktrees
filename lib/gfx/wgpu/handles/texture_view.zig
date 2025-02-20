const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const TextureAspect = wgpu.TextureAspect;
const TextureFormat = wgpu.TextureFormat;
const TextureUsage = wgpu.TextureUsage;
const TextureViewDimension = wgpu.TextureViewDimension;

const TextureView = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPUTextureViewDescriptor;

    label: ?[]const u8 = null,
    format: TextureFormat = .Undefined,
    dimension: TextureViewDimension = .Undefined,
    base_mip_level: u32 = 0,
    mip_level_count: u32 = 1,
    base_array_layer: u32 = 0,
    array_layer_count: u32 = 1,
    aspect: TextureAspect = .All,
    usage: TextureUsage = .{},

    pub fn get(self: Descriptor) Descriptor.NativeType {
        return auto.wgpu_struct_get(null, Descriptor.NativeType, self);
    }
};

pub const Handle = c.WGPUTextureView;

handle: Handle = null,

pub fn deinit(self: TextureView) void {
    if (self.handle != null) c.wgpuTextureViewRelease(self.handle);
}
