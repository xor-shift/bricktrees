const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const CommandBuffer = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPUCommandBufferDescriptor;

    label: ?[:0]const u8,

    pub fn get(self: Descriptor) Descriptor.NativeType {
        return .{
            .nextInChain = null,
            .label = if (self.label) |v| v.ptr else null,
        };
    }
};

pub const Handle = c.WGPUCommandBuffer;

handle: Handle = null,

pub fn release(self: CommandBuffer) void {
    c.wgpuCommandBufferRelease(self.handle);
}
