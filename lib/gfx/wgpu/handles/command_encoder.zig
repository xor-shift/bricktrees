const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const CommandBuffer = wgpu.CommandBuffer;
const ComputePass = wgpu.ComputePass;
const RenderPass = wgpu.RenderPass;

const CommandEncoder = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPUCommandEncoderDescriptor;

    label: ?[]const u8 = null,

    pub fn get(self: Descriptor) Descriptor.NativeType {
        return .{
            .label = auto.make_string(self.label),
        };
    }
};

pub const Handle = c.WGPUCommandEncoder;

handle: Handle = null,

pub fn deinit(self: CommandEncoder) void {
    if (self.handle != null) c.wgpuCommandEncoderRelease(self.handle);
}

pub fn begin_render_pass(self: CommandEncoder, descriptor: RenderPass.Descriptor) Error!RenderPass {
    const desc = descriptor.get(common.begin_helper());

    const render_pass = c.wgpuCommandEncoderBeginRenderPass(self.handle, &desc);

    return .{ .handle = render_pass orelse return Error.UnexpectedNull };
}

pub fn begin_compute_pass(self: CommandEncoder, descriptor: ComputePass.Descriptor) Error!ComputePass {
    return .{ .handle = c.wgpuCommandEncoderBeginComputePass(self.handle, &descriptor.get()) orelse return Error.UnexpectedNull };
}

pub fn finish(self: CommandEncoder, descriptor: ?CommandBuffer.Descriptor) Error!CommandBuffer {
    const c_desc: ?*const CommandBuffer.Descriptor.NativeType = if (descriptor) |v| &(v.get()) else null;
    const buffer = c.wgpuCommandEncoderFinish(self.handle, c_desc);

    return .{
        .handle = buffer orelse return Error.UnexpectedNull,
    };
}
