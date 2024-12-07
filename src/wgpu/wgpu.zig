const std = @import("std");
const builtin = @import("builtin");

const future = @import("../core/future.zig");

const auto = @import("auto.zig");
const common = @import("common.zig");

//pub usingnamespace @import("enums.zig");
pub usingnamespace @import("generated/enums.zig");
pub usingnamespace @import("generated/bitflags.zig");

test {
    std.testing.refAllDecls(auto);
}

const c = common.c;
const sdl_c = common.sdl_c;

const ConversionHelper = common.ConversionHelper;

pub const Error = common.Error;

pub const Adapter = @import("handles/adapter.zig");
pub const BindGroup = @import("handles/bind_group.zig");
pub const BindGroupLayout = @import("handles/bind_group_layout.zig");
pub const Buffer = @import("handles/buffer.zig");
pub const CommandBuffer = @import("handles/command_buffer.zig");
pub const CommandEncoder = @import("handles/command_encoder.zig");
pub const ComputePass = @import("handles/compute_pass.zig");
pub const ComputePipeline = @import("handles/compute_pipeline.zig");
pub const Device = @import("handles/device.zig");
pub const Instance = @import("handles/instance.zig");
pub const PipelineLayout = @import("handles/pipeline_layout.zig");
pub const Queue = @import("handles/queue.zig");
pub const RenderPass = @import("handles/render_pass.zig");
pub const RenderPipeline = @import("handles/render_pipeline.zig");
pub const Sampler = @import("handles/sampler.zig");
pub const ShaderModule = @import("handles/shader_module.zig");
pub const Surface = @import("handles/surface.zig");
pub const Texture = @import("handles/texture.zig");
pub const TextureView = @import("handles/texture_view.zig");

const wgpu = @This();

pub const BlendComponent = struct {
    pub const NativeType = c.WGPUBlendComponent;

    operation: wgpu.BlendOperation,
    src_factor: wgpu.BlendFactor,
    dst_factor: wgpu.BlendFactor,

    pub fn get(self: BlendComponent) NativeType {
        return .{
            .operation = @intFromEnum(self.operation),
            .srcFactor = @intFromEnum(self.src_factor),
            .dstFactor = @intFromEnum(self.dst_factor),
        };
    }
};

pub const BlendState = struct {
    pub const NativeType = c.WGPUBlendState;

    color: BlendComponent,
    alpha: BlendComponent,

    pub fn get(self: BlendState) NativeType {
        return .{
            .color = self.color.get(),
            .alpha = self.alpha.get(),
        };
    }
};

pub const Color = struct {
    pub const NativeType = c.WGPUColor;

    r: f64 = 0.0,
    g: f64 = 0.0,
    b: f64 = 0.0,
    a: f64 = 0.0,

    pub fn get(self: Color) NativeType {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
    }
};

pub const ColorTargetState = struct {
    pub const NativeType = c.WGPUColorTargetState;

    format: wgpu.TextureFormat,
    blend: ?BlendState = null,
    write_mask: wgpu.ColorWriteMask = .{},

    pub fn get(self: ColorTargetState, helper: *ConversionHelper) NativeType {
        return .{
            .format = @intFromEnum(self.format),
            .blend = helper.optional_helper(false, BlendState, self.blend),
            .writeMask = auto.get_flags(self.write_mask),
        };
    }
};

pub const DepthStencilState = struct {
    pub const NativeType = c.WGPUDepthStencilState;

    pub fn get(self: DepthStencilState) NativeType {
        _ = self;
        return .{
            .nextInChain = null,
            // .format = undefined,
            // .depthWriteEnabled = undefined,
            // .depthCompare = undefined,
            // .stencilFront = undefined,
            // .stencilBack = undefined,
            // .stencilReadMask = undefined,
            // .stencilWriteMask = undefined,
            // .depthBias = undefined,
            // .depthBiasSlopeScale = undefined,
            // .depthBiasClamp = undefined,
        };
    }
};

pub const FragmentState = struct {
    pub const NativeType = c.WGPUFragmentState;

    module: ShaderModule,
    entry_point: [:0]const u8,
    targets: []const ColorTargetState = &.{},

    pub fn get(self: FragmentState, helper: *ConversionHelper) NativeType {
        return .{
            .nextInChain = null,
            .module = self.module.handle,
            .entryPoint = self.entry_point.ptr,
            .constantCount = 0,
            .constants = null,
            .targetCount = self.targets.len,
            .targets = helper.array_helper(true, ColorTargetState, self.targets),
        };
    }
};

pub const MultisampleState = struct {
    pub const NativeType = c.WGPUMultisampleState;

    count: u32 = 1,
    mask: u32 = ~@as(u32, 0),
    alpha_to_coverage_enabled: bool = false,

    pub fn get(self: MultisampleState) NativeType {
        return .{
            .nextInChain = null,
            .count = self.count,
            .mask = self.mask,
            .alphaToCoverageEnabled = @intFromBool(self.alpha_to_coverage_enabled),
        };
    }
};

pub const PrimitiveState = struct {
    pub const NativeType = c.WGPUPrimitiveState;

    topology: wgpu.PrimitiveTopology,
    strip_index_format: wgpu.IndexFormat = .Undefined,
    front_face: wgpu.FrontFace = .CCW,
    cull_mode: wgpu.CullMode = .None,
    unclipped_depth: bool = false,

    pub fn get(self: PrimitiveState) NativeType {
        return .{
            .nextInChain = null,
            .topology = @intFromEnum(self.topology),
            .stripIndexFormat = @intFromEnum(self.strip_index_format),
            .frontFace = @intFromEnum(self.front_face),
            .cullMode = @intFromBool(self.unclipped_depth),
        };
    }
};

pub const VertexAttribute = struct {
    pub const NativeType = c.WGPUVertexAttribute;

    format: wgpu.VertexFormat,
    offset: u64,
    shader_location: u32,

    pub fn get(self: VertexAttribute) NativeType {
        return .{
            .format = @intFromEnum(self.format),
            .offset = self.offset,
            .shaderLocation = self.shader_location,
        };
    }
};

pub const VertexBufferLayout = struct {
    pub const NativeType = c.WGPUVertexBufferLayout;

    array_stride: u64,
    step_mode: wgpu.VertexStepMode = .Vertex,
    attributes: []const VertexAttribute,

    pub fn get(self: VertexBufferLayout, helper: *ConversionHelper) NativeType {
        return .{
            .arrayStride = self.array_stride,
            .stepMode = @intFromEnum(self.step_mode),
            .attributeCount = self.attributes.len,
            .attributes = helper.array_helper(false, VertexAttribute, self.attributes),
        };
    }
};

pub const VertexState = struct {
    pub const NativeType = c.WGPUVertexState;

    module: ShaderModule,
    entry_point: [:0]const u8,
    // TODO: constants
    buffers: []const VertexBufferLayout = &.{},

    pub fn get(self: VertexState, helper: *ConversionHelper) NativeType {
        return .{
            .nextInChain = null,
            .module = self.module.handle,
            .entryPoint = self.entry_point.ptr,
            .constantCount = 0,
            .constants = undefined,
            .bufferCount = self.buffers.len,
            .buffers = helper.array_helper(true, VertexBufferLayout, self.buffers),
        };
    }
};

pub const Limits = struct {
    pub const NativeType = c.WGPULimits;

    max_texture_dimension_1d: u32 = 0,
    max_texture_dimension_2d: u32 = 0,
    max_texture_dimension_3d: u32 = 0,
    max_texture_array_layers: u32 = 0,
    max_bind_groups: u32 = 0,
    max_bind_groups_plus_vertex_buffers: u32 = 0,
    max_bindings_per_bind_group: u32 = 0,
    max_dynamic_uniform_buffers_per_pipeline_layout: u32 = 0,
    max_dynamic_storage_buffers_per_pipeline_layout: u32 = 0,
    max_sampled_textures_per_shader_stage: u32 = 0,
    max_samplers_per_shader_stage: u32 = 0,
    max_storage_buffers_per_shader_stage: u32 = 0,
    max_storage_textures_per_shader_stage: u32 = 0,
    max_uniform_buffers_per_shader_stage: u32 = 0,
    max_uniform_buffer_binding_size: u64 = 0,
    max_storage_buffer_binding_size: u64 = 0,
    min_uniform_buffer_offset_alignment: u32 = 0,
    min_storage_buffer_offset_alignment: u32 = 0,
    max_vertex_buffers: u32 = 0,
    max_buffer_size: u64 = 0,
    max_vertex_attributes: u32 = 0,
    max_vertex_buffer_array_stride: u32 = 0,
    max_inter_stage_shader_components: u32 = 0,
    max_inter_stage_shader_variables: u32 = 0,
    max_color_attachments: u32 = 0,
    max_color_attachment_bytes_per_sample: u32 = 0,
    max_compute_workgroup_storage_size: u32 = 0,
    max_compute_invocations_per_workgroup: u32 = 0,
    max_compute_workgroup_size_x: u32 = 0,
    max_compute_workgroup_size_y: u32 = 0,
    max_compute_workgroup_size_z: u32 = 0,
    max_compute_workgroups_per_dimension: u32 = 0,

    pub fn get(self: Limits) NativeType {
        return auto.wgpu_struct_get(null, NativeType, self);
    }
};

pub const NativeLimits = struct {
    pub const NativeType = c.WGPUNativeLimits;

    max_push_constant_size: u32 = 0,
    max_non_sampler_bindings: u32 = 0,

    pub fn get(self: NativeLimits) NativeType {
        return .{
            .maxPushConstantSize = self.max_push_constant_size,
            .maxNonSamplerBindings = self.max_non_sampler_bindings,
        };
    }
};

pub const RequiredLimits = struct {
    pub const NativeType = c.WGPURequiredLimits;

    native_limits: ?NativeLimits,
    limits: Limits,

    pub fn get(self: RequiredLimits, helper: *ConversionHelper) NativeType {
        const chained = helper.optional_helper(false, NativeLimits, self.native_limits);
        _ = chained;

        return .{
            .nextInChain = null,
            .limits = self.limits.get(),
        };
    }
};

pub const Extent3D = struct {
    pub const NativeType = c.WGPUExtent3D;

    width: u32,
    height: u32,
    depth_or_array_layers: u32,

    pub fn get(self: Extent3D) NativeType {
        return .{
            .width = self.width,
            .height = self.height,
            .depthOrArrayLayers = self.depth_or_array_layers,
        };
    }
};

pub const Origin3D = struct {
    pub const NativeType = c.WGPUOrigin3D;

    x: u32,
    y: u32,
    z: u32,

    pub fn get(self: Origin3D) NativeType {
        return .{
            .x = self.x,
            .y = self.y,
            .z = self.z,
        };
    }
};

pub const ImageCopyTexture = struct {
    pub const NativeType = c.WGPUImageCopyTexture;

    texture: Texture,
    mip_level: u32 = 0,
    origin: Origin3D = .{ .x = 0, .y = 0, .z = 0 },
    aspect: wgpu.TextureAspect = .All,

    pub fn get(self: ImageCopyTexture) NativeType {
        return .{
            .nextInChain = null,
            .texture = self.texture.handle,
            .mipLevel = self.mip_level,
            .origin = self.origin.get(),
            .aspect = @intFromEnum(self.aspect),
        };
    }
};

pub const TextureDataLayout = struct {
    pub const NativeType = c.WGPUTextureDataLayout;

    offset: u64,
    bytes_per_row: u32,
    rows_per_image: u32,

    pub fn get(self: TextureDataLayout) NativeType {
        return .{
            .nextInChain = null,
            .offset = self.offset,
            .bytesPerRow = self.bytes_per_row,
            .rowsPerImage = self.rows_per_image,
        };
    }
};

pub const ConstantEntry = struct {
    pub const NativeType = c.WGPUConstantEntry;

    key: [:0]const u8,
    value: f64,

    pub fn get(self: ConstantEntry) NativeType {
        return .{
            .nextInChain = null,
            .key = self.key.ptr,
            .value = self.value,
        };
    }
};
