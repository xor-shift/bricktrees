const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const ConstantEntry = wgpu.ConstantEntry;
const PipelineLayout = wgpu.PipelineLayout;
const ShaderModule = wgpu.ShaderModule;

const ComputePipeline = @This();

pub const ProgrammableStageDescriptor = struct {
    pub const NativeType = c.WGPUProgrammableStageDescriptor;

    module: ShaderModule,
    entry_point: ?[:0]const u8 = null,
    constants: []const ConstantEntry,

    pub fn get(self: ProgrammableStageDescriptor, helper: *ConversionHelper) NativeType {
        return .{
            .nextInChain = null,
            .module = self.module.handle,
            .entryPoint = if (self.entry_point) |v| v.ptr else null,
            .constantCount = self.constants.len,
            .constants = helper.array_helper(false, ConstantEntry, self.constants),
        };
    }
};

pub const Descriptor = struct {
    pub const NativeType = c.WGPUComputePipelineDescriptor;

    label: ?[:0]const u8 = null,
    layout: ?PipelineLayout = null,
    compute: ProgrammableStageDescriptor,

    pub fn get(self: Descriptor, helper: *ConversionHelper) NativeType {
        return .{
            .nextInChain = null,
            .label = if (self.label) |v| v.ptr else null,
            .layout = if (self.layout) |v| v.handle else null,
            .compute = self.compute.get(helper),
        };
    }
};

pub const Handle = c.WGPUComputePipeline;

handle: Handle = null,

pub fn deinit(self: ComputePipeline) void {
    if (self.handle != null) c.wgpuComputePipelineRelease(self.handle);
}
