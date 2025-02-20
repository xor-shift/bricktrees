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

    label: ?[]const u8 = null,
    bind_group_layouts: []const BindGroupLayout = &.{},

    pub fn get(self: Descriptor) Descriptor.NativeType {
        return .{
            .label = auto.make_string(self.label),
            .bindGroupLayoutCount = self.bind_group_layouts.len,
            .bindGroupLayouts = @ptrCast(self.bind_group_layouts.ptr),
        };
    }
};

pub const Handle = c.WGPUPipelineLayout;

handle: Handle = null,

pub fn deinit(self: PipelineLayout) void {
    if (self.handle != null) c.wgpuPipelineLayoutRelease(self.handle);
}
