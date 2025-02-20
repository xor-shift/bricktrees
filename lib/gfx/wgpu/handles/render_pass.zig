const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const BindGroup = wgpu.BindGroup;
const Buffer = wgpu.Buffer;
const Color = wgpu.Color;
const LoadOp = wgpu.LoadOp;
const RenderPipeline = wgpu.RenderPipeline;
const StoreOp = wgpu.StoreOp;
const TextureView = wgpu.TextureView;

const RenderPass = @This();

pub const ColorAttachment = struct {
    pub const NativeType = c.WGPURenderPassColorAttachment;

    view: ?TextureView = null,
    depth_slice: u32 = 0,
    resolve_target: ?TextureView = null,
    load_op: LoadOp = .Undefined,
    store_op: StoreOp = .Undefined,
    clear_value: Color = .{},

    pub fn get(self: ColorAttachment) ColorAttachment.NativeType {
        return .{
            .view = if (self.view) |v| v.handle else null,
            .depthSlice = self.depth_slice,
            .resolveTarget = if (self.resolve_target) |v| v.handle else null,
            .loadOp = @intFromEnum(self.load_op),
            .storeOp = @intFromEnum(self.store_op),
            .clearValue = self.clear_value.get(),
        };
    }
};

pub const DepthStencilAttachment = struct {
    pub const NativeType = c.WGPURenderPassDepthStencilAttachment;

    pub fn get(self: DepthStencilAttachment) DepthStencilAttachment.NativeType {
        _ = self;
        return .{};
    }
};

pub const Descriptor = struct {
    pub const NativeType = c.WGPURenderPassDescriptor;

    label: ?[]const u8 = null,
    color_attachments: []const ColorAttachment = &.{},
    depth_stencil_attachment: ?DepthStencilAttachment = null,
    // TODO: occlusion_query_set
    // TODO: timestamp_writes

    pub fn get(self: Descriptor, helper: *ConversionHelper) Descriptor.NativeType {
        const color_attachments = helper.alloc(ColorAttachment.NativeType, self.color_attachments.len);
        for (0.., self.color_attachments) |i, v| color_attachments[i] = v.get();

        const depth_stencil_attachment: ?*DepthStencilAttachment.NativeType = val: {
            if (self.depth_stencil_attachment) |v| {
                const ret = helper.create(DepthStencilAttachment.NativeType);
                ret.* = v.get();
                break :val ret;
            } else {
                break :val null;
            }
        };

        return .{
            .label = auto.make_string(self.label),
            .colorAttachmentCount = color_attachments.len,
            .colorAttachments = color_attachments.ptr,
            .depthStencilAttachment = depth_stencil_attachment,
            .occlusionQuerySet = null,
            .timestampWrites = null,
        };
    }
};

pub const Handle = c.WGPURenderPassEncoder;

handle: Handle = null,

pub fn deinit(self: RenderPass) void {
    if (self.handle != null) c.wgpuRenderPassEncoderRelease(self.handle);
}

pub fn set_pipeline(self: RenderPass, pipeline: RenderPipeline) void {
    c.wgpuRenderPassEncoderSetPipeline(self.handle, pipeline.handle);
}

pub fn set_bind_group(self: RenderPass, group_index: u32, bind_group: BindGroup, dynamic_offsets: ?[]const u32) void {
    c.wgpuRenderPassEncoderSetBindGroup(self.handle, group_index, bind_group.handle, if (dynamic_offsets) |v| v.len else 0, if (dynamic_offsets) |v| v.ptr else null);
}

pub fn set_vertex_buffer(self: RenderPass, slot: u32, buffer: Buffer, offset: u64, size: u64) void {
    c.wgpuRenderPassEncoderSetVertexBuffer(self.handle, slot, buffer.handle, offset, size);
}

pub fn set_index_buffer(self: RenderPass, buffer: Buffer, format: wgpu.IndexFormat, offset: u64, size: u64) void {
    c.wgpuRenderPassEncoderSetIndexBuffer(self.handle, buffer.handle, @intFromEnum(format), offset, size);
}

pub fn set_scissor_rect(self: RenderPass, top_left: [2]u32, dims: [2]u32) void {
    c.wgpuRenderPassEncoderSetScissorRect(self.handle, top_left[0], top_left[1], dims[0], dims[1]);
}

pub const DrawArgs = struct {
    first_vertex: u32,
    vertex_count: u32,

    first_instance: u32,
    instance_count: u32,
};

pub fn draw(self: RenderPass, args: DrawArgs) void {
    c.wgpuRenderPassEncoderDraw(self.handle, args.vertex_count, args.instance_count, args.first_vertex, args.first_instance);
}

pub const IndexedDrawArgs = struct {
    index_count: u32,
    first_index: u32,

    base_vertex: i32,

    first_instance: u32,
    instance_count: u32,
};

pub fn draw_indexed(self: RenderPass, args: IndexedDrawArgs) void {
    c.wgpuRenderPassEncoderDrawIndexed(self.handle, args.index_count, args.instance_count, args.first_index, args.base_vertex, args.first_instance);
}

pub fn end(self: RenderPass) void {
    c.wgpuRenderPassEncoderEnd(self.handle);
}
