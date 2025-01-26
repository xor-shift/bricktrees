const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const Buffer = wgpu.Buffer;
const CommandBuffer = wgpu.CommandBuffer;
const Extent3D = wgpu.Extent3D;
const ImageCopyTexture = wgpu.ImageCopyTexture;
const TextureDataLayout = wgpu.TextureDataLayout;

const Queue = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPUQueueDescriptor;

    label: ?[:0]const u8 = null,

    pub fn get(self: Descriptor) NativeType {
        return .{
            .nextInChain = null,
            .label = if (self.label) |v| v.ptr else null,
        };
    }
};

pub const Handle = c.WGPUQueue;

handle: Handle = null,

pub fn deinit(self: Queue) void {
    if (self.handle != null) c.wgpuQueueRelease(self.handle);
}

pub fn submit(self: Queue, command_buffers: []const CommandBuffer) void {
    const converted_ptr: [*]const CommandBuffer.Handle = @ptrCast(command_buffers.ptr);

    c.wgpuQueueSubmit(self.handle, command_buffers.len, converted_ptr);
}

pub fn write_buffer(self: Queue, buffer: Buffer, offset: u64, data: []const u8) void {
    c.wgpuQueueWriteBuffer(self.handle, buffer.handle, offset, data.ptr, data.len);
}

pub fn write_texture(self: Queue, destination: ImageCopyTexture, data: []const u8, write_size: Extent3D, layout: TextureDataLayout) void {
    c.wgpuQueueWriteTexture(self.handle, &destination.get(), data.ptr, data.len, &layout.get(), &write_size.get());
}
