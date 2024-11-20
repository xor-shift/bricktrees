const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const BindGroupLayout = wgpu.BindGroupLayout;

const Sampler = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPUSamplerDescriptor;

    label: ?[:0]const u8 = null,
    addressModeU: wgpu.AddressMode = .Repeat,
    addressModeV: wgpu.AddressMode = .Repeat,
    addressModeW: wgpu.AddressMode = .Repeat,
    magFilter: wgpu.FilterMode = .Nearest,
    minFilter: wgpu.FilterMode = .Nearest,
    mipmapFilter: wgpu.MipmapFilterMode = .Nearest,
    lodMinClamp: f32 = 0.0,
    lodMaxClamp: f32 = 32.0,
    compare: wgpu.CompareFunction = .Undefined,
    maxAnisotropy: u16 = 1,

    pub fn get(self: Descriptor) NativeType {
        return auto.wgpu_struct_get(null, NativeType, self);
    }
};

pub const Handle = c.WGPUSampler;

handle: Handle = null,
