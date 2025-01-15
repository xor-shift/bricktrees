const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const DepthStencilState = wgpu.DepthStencilState;
const FragmentState = wgpu.FragmentState;
const MultisampleState = wgpu.MultisampleState;
const PipelineLayout = wgpu.PipelineLayout;
const PrimitiveState = wgpu.PrimitiveState;
const VertexState = wgpu.VertexState;

const RenderPipeline = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPURenderPipelineDescriptor;

    label: ?[:0]const u8 = null,
    layout: ?PipelineLayout = null,
    vertex: VertexState,
    primitive: PrimitiveState,
    depth_stencil: ?DepthStencilState = null,
    multisample: MultisampleState = .{},
    fragment: ?FragmentState = null,

    pub fn get(self: Descriptor, helper: *ConversionHelper) Descriptor.NativeType {
        return .{
            .nextInChain = null,
            .label = if (self.label) |v| v.ptr else null,
            .layout = if (self.layout) |v| v.handle else null,
            .vertex = self.vertex.get(helper),
            .primitive = self.primitive.get(),
            .depthStencil = helper.optional_helper(false, DepthStencilState, self.depth_stencil),
            .multisample = self.multisample.get(),
            .fragment = helper.optional_helper(true, FragmentState, self.fragment),
        };
    }
};

pub const NativeType = c.WGPURenderPipeline;

handle: NativeType = null,

pub fn deinit(self: RenderPipeline) void {
    c.wgpuRenderPipelineRelease(self.handle);
}
