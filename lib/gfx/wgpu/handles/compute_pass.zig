const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

pub const Descriptor = struct {
    pub const NativeType = c.WGPUComputePassDescriptor;

    label: ?[]const u8 = null,
    // TODO: timestamp_writes

    pub fn get(self: Descriptor) NativeType {
        return .{
            .nextInChain = null,
            .label = auto.make_string(self.label),
            .timestampWrites = null,
        };
    }
};

const ComputePass = @This();

pub const Handle = c.WGPUComputePassEncoder;

handle: Handle = null,

pub fn deinit(self: ComputePass) void {
    if (self.handle != null) c.wgpuComputePassEncoderRelease(self.handle);
}

pub fn set_pipeline(self: ComputePass, pipeline: wgpu.ComputePipeline) void {
    c.wgpuComputePassEncoderSetPipeline(self.handle, pipeline.handle);
}

pub fn set_bind_group(self: ComputePass, group_index: u32, bind_group: wgpu.BindGroup, dynamic_offsets: ?[]const u32) void {
    c.wgpuComputePassEncoderSetBindGroup(self.handle, group_index, bind_group.handle, if (dynamic_offsets) |v| v.len else 0, if (dynamic_offsets) |v| v.ptr else null);
}

pub fn dispatch_workgroups(self: ComputePass, workgroup_counts: [3]u32) void {
    c.wgpuComputePassEncoderDispatchWorkgroups(
        self.handle,
        workgroup_counts[0],
        workgroup_counts[1],
        workgroup_counts[2],
    );
}

pub fn end(self: ComputePass) void {
    c.wgpuComputePassEncoderEnd(self.handle);
}
