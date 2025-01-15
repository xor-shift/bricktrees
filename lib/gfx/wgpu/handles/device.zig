const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const BindGroup = wgpu.BindGroup;
const BindGroupLayout = wgpu.BindGroupLayout;
const Buffer = wgpu.Buffer;
const CommandEncoder = wgpu.CommandEncoder;
const ComputePipeline = wgpu.ComputePipeline;
const DeviceLostReason = wgpu.DeviceLostReason;
const FeatureName = wgpu.FeatureName;
const PipelineLayout = wgpu.PipelineLayout;
const Queue = wgpu.Queue;
const RenderPipeline = wgpu.RenderPipeline;
const RequiredLimits = wgpu.RequiredLimits;
const Sampler = wgpu.Sampler;
const ShaderModule = wgpu.ShaderModule;
const Texture = wgpu.Texture;

const Device = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPUDeviceDescriptor;

    label: ?[:0]const u8 = null,
    required_features: []const FeatureName = &.{},
    required_limits: ?RequiredLimits = null,
    default_queue: Queue.Descriptor = .{},

    // TODO

    // device_lost_callback: ?*const fn (ctx: ?*anyopaque, reason: DeviceLostReason, message: ?[:0]const u8) void = null,
    // device_lost_callback_userdata: ?*anyopaque = null,

    // uncapturedErrorCallbackInfo: WGPUUncapturedErrorCallbackInfo = @import("std").mem.zeroes(WGPUUncapturedErrorCallbackInfo),

    pub fn get(self: Descriptor, helper: *ConversionHelper) Descriptor.NativeType {
        return .{
            .label = if (self.label) |v| v.ptr else null,
            .requiredFeatureCount = self.required_features.len,
            .requiredFeatures = @ptrCast(self.required_features),
            .requiredLimits = helper.optional_helper(true, RequiredLimits, self.required_limits),
            .defaultQueue = self.default_queue.get(),
            .deviceLostCallback = null,
            .deviceLostUserdata = null,
            .uncapturedErrorCallbackInfo = .{
                .nextInChain = null,
                .callback = null,
                .userdata = null,
            },
        };
    }
};

pub const Handle = c.WGPUDevice;

handle: Handle = null,

pub fn deinit(self: Device) void {
    c.wgpuDeviceRelease(self.handle);
}

pub fn destroy(self: Device) void {
    c.wgpuDeviceDestroy(self.handle);
}

pub fn get_queue(self: Device) Error!Queue {
    return .{
        .handle = c.wgpuDeviceGetQueue(self.handle) orelse return Error.UnexpectedNull,
    };
}

pub fn create_command_encoder(self: Device, descriptor: ?CommandEncoder.Descriptor) Error!CommandEncoder {
    const desc = if (descriptor) |v| v.get() else null;

    return .{
        .handle = c.wgpuDeviceCreateCommandEncoder(self.handle, if (desc) |v| &v else null) orelse return Error.UnexpectedNull,
    };
}

pub fn create_shader_module_wgsl_from_file(self: Device, label: ?[:0]const u8, filename: []const u8, alloc: std.mem.Allocator) !ShaderModule {
    const shader_code = val: {
        const cwd = std.fs.cwd();

        const file = try cwd.openFile(filename, .{});
        defer file.close();

        const contents = try file.readToEndAllocOptions(alloc, 64 * 1024 * 1024, null, @alignOf(u8), 0);

        break :val contents;
    };
    defer alloc.free(shader_code);

    return try self.create_shader_module_wgsl(label, shader_code);
}

pub fn create_shader_module_wgsl(self: Device, label: ?[:0]const u8, source: [:0]const u8) Error!ShaderModule {
    const wgsl_descriptor = c.WGPUShaderModuleWGSLDescriptor{
        .chain = .{
            .next = null,
            .sType = c.WGPUSType_ShaderModuleWGSLDescriptor,
        },
        .code = source,
    };

    const descriptor = c.WGPUShaderModuleDescriptor{
        .nextInChain = &wgsl_descriptor.chain,
        .label = if (label) |v| v.ptr else null,
    };

    return .{
        .handle = c.wgpuDeviceCreateShaderModule(self.handle, &descriptor) orelse return Error.UnexpectedNull,
    };
}

pub fn create_render_pipeline(self: Device, descriptor: RenderPipeline.Descriptor) Error!RenderPipeline {
    return .{
        .handle = c.wgpuDeviceCreateRenderPipeline(self.handle, &descriptor.get(common.begin_helper())) orelse return Error.UnexpectedNull,
    };
}

pub fn create_compute_pipeline(self: Device, descriptor: ComputePipeline.Descriptor) Error!ComputePipeline {
    return .{
        .handle = c.wgpuDeviceCreateComputePipeline(self.handle, &descriptor.get(common.begin_helper())) orelse return Error.UnexpectedNull,
    };
}

pub fn create_bind_group_layout(self: Device, descriptor: BindGroupLayout.Descriptor) Error!BindGroupLayout {
    return .{
        .handle = c.wgpuDeviceCreateBindGroupLayout(self.handle, &descriptor.get(common.begin_helper())) orelse return Error.UnexpectedNull,
    };
}

pub fn create_bind_group(self: Device, descriptor: BindGroup.Descriptor) Error!BindGroup {
    return .{
        .handle = c.wgpuDeviceCreateBindGroup(self.handle, &descriptor.get(common.begin_helper())) orelse return Error.UnexpectedNull,
    };
}

pub fn create_pipeline_layout(self: Device, descriptor: PipelineLayout.Descriptor) Error!PipelineLayout {
    return .{
        .handle = c.wgpuDeviceCreatePipelineLayout(self.handle, &descriptor.get()) orelse return Error.UnexpectedNull,
    };
}

pub fn create_buffer(self: Device, descriptor: Buffer.Descriptor) Error!Buffer {
    return .{
        .handle = c.wgpuDeviceCreateBuffer(self.handle, &descriptor.get()) orelse return Error.UnexpectedNull,
    };
}

pub fn create_texture(self: Device, descriptor: Texture.Descriptor) Error!Texture {
    return .{
        .handle = c.wgpuDeviceCreateTexture(self.handle, &descriptor.get()) orelse return Error.UnexpectedNull,
    };
}

pub fn create_sampler(self: Device, descriptor: Sampler.Descriptor) Error!Sampler {
    return .{
        .handle = c.wgpuDeviceCreateSampler(self.handle, &descriptor.get()) orelse return Error.UnexpectedNull,
    };
}
