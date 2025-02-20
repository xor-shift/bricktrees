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
            .label = auto.make_string(self.label),
        };
    }
};

pub const Handle = c.WGPUCommandBuffer;

handle: Handle = null,

pub fn deinit(self: CommandBuffer) void {
    if (self.handle != null) c.wgpuCommandBufferRelease(self.handle);
}
