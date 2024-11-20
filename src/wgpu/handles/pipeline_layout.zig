const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const BindGroupLayout = wgpu.BindGroupLayout;

const PipelineLayout = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPUPipelineLayoutDescriptor;

    label: ?[:0]const u8 = null,
    bind_group_layouts: []const BindGroupLayout = &.{},

    pub fn get(self: Descriptor) Descriptor.NativeType {
        return .{
            .label = if (self.label) |v| v.ptr else null,
            .bindGroupLayoutCount = self.bind_group_layouts.len,
            .bindGroupLayouts = @ptrCast(self.bind_group_layouts.ptr),
        };
    }
};

pub const Handle = c.WGPUPipelineLayout;

handle: Handle = null,
