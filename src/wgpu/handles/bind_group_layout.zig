const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const BufferBindingType = wgpu.BufferBindingType;
const SamplerBindingType = wgpu.SamplerBindingType;
const ShaderStage = wgpu.ShaderStage;
const TextureSampleType = wgpu.TextureSampleType;
const TextureViewDimension = wgpu.TextureViewDimension;

const BindGroupLayout = @This();

pub const BindingLayout = union(enum) {
    Buffer: struct {
        const NativeType = c.WGPUBufferBindingLayout;

        type: BufferBindingType,
        has_dynamic_offset: bool = false,
        min_binding_size: u64 = 0,

        pub fn get(self: @This()) @This().NativeType {
            return .{
                .nextInChain = null,
                .type = @intFromEnum(self.type),
                .hasDynamicOffset = @intFromBool(self.has_dynamic_offset),
                .minBindingSize = self.min_binding_size,
            };
        }
    },

    Sampler: struct {
        pub const NativeType = c.WGPUSamplerBindingLayout;

        type: SamplerBindingType,

        pub fn get(self: @This()) @This().NativeType {
            return .{
                .nextInChain = null,
                .type = @intFromEnum(self.type),
            };
        }
    },

    Texture: struct {
        pub const NativeType = c.WGPUTextureBindingLayout;

        sample_type: TextureSampleType = .Undefined,
        view_dimension: TextureViewDimension = .Undefined,
        multisampled: bool = false,

        pub fn get(self: @This()) @This().NativeType {
            return .{
                .nextInChain = null,
                .sampleType = @intFromEnum(self.sample_type),
                .viewDimension = @intFromEnum(self.view_dimension),
                .multisampled = @intFromBool(self.multisampled),
            };
        }
    },

    StorageTexture: struct {
        pub const NativeType = c.WGPUStorageTextureBindingLayout;

        access: wgpu.StorageTextureAccess = .Undefined,
        format: wgpu.TextureFormat = .Undefined,
        view_dimension: wgpu.TextureViewDimension = .Undefined,

        pub fn get(self: @This()) @This().NativeType {
            return .{
                .nextInChain = null,
                .access = @intFromEnum(self.access),
                .format = @intFromEnum(self.format),
                .viewDimension = @intFromEnum(self.view_dimension),
            };
        }
    },
};

pub const Entry = struct {
    pub const NativeType = c.WGPUBindGroupLayoutEntry;

    binding: u32,
    visibility: ShaderStage,
    layout: BindingLayout,

    pub fn get(self: Entry) Entry.NativeType {
        var ret: Entry.NativeType = .{
            .binding = self.binding,
            .visibility = auto.get_flags(self.visibility),
        };

        switch (self.layout) {
            .Buffer => |v| ret.buffer = v.get(),
            .Sampler => |v| ret.sampler = v.get(),
            .Texture => |v| ret.texture = v.get(),
            .StorageTexture => |v| ret.storageTexture = v.get(),
        }

        return ret;
    }
};

pub const Descriptor = struct {
    pub const NativeType = c.WGPUBindGroupLayoutDescriptor;

    label: ?[:0]const u8,
    entries: []const Entry,

    pub fn get(self: Descriptor, helper: *ConversionHelper) @This().NativeType {
        return .{
            .nextInChain = null,
            .entryCount = self.entries.len,
            .entries = helper.array_helper(false, Entry, self.entries),
        };
    }
};

pub const Handle = c.WGPUBindGroupLayout;

handle: Handle = null,
