const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const BindGroupLayout = wgpu.BindGroupLayout;
const Buffer = wgpu.Buffer;
const Sampler = wgpu.Sampler;
const TextureView = wgpu.TextureView;

const BindGroup = @This();

pub const BindingResource = union(enum) {
    Buffer: struct {
        buffer: Buffer,
        offset: u64 = 0,
        size: ?u64 = null,
    },

    Sampler: Sampler,
    TextureView: TextureView,

    BufferArray: []Buffer,
    SamplerArray: []Sampler,
    TextureViewArray: []TextureView,
};

pub const Entry = struct {
    pub const NativeType = c.WGPUBindGroupEntry;

    binding: u32,
    resource: BindingResource,

    pub fn get(self: Entry, helper: *ConversionHelper) NativeType {
        var ret: NativeType = .{
            .binding = self.binding,
        };

        switch (self.resource) {
            .Buffer => |v| {
                ret.buffer = v.buffer.handle;
                ret.offset = v.offset;
                ret.size = v.size orelse wgpu.whole_map_size;
            },
            .Sampler => |v| ret.sampler = v.handle,
            .TextureView => |v| ret.textureView = v.handle,
            .BufferArray => |v| {
                const extras = helper.create(c.WGPUBindGroupEntryExtras);
                extras.* = c.WGPUBindGroupEntryExtras{
                    .chain = .{
                        .next = null,
                        .sType = c.WGPUSType_BindGroupEntryExtras,
                    },
                    .bufferCount = v.len,
                    .buffers = @ptrCast(v.ptr),
                };
                ret.nextInChain = &extras.chain;
            },
            .SamplerArray => |_| @panic("NYI"),
            .TextureViewArray => |v| {
                const extras = helper.create(c.WGPUBindGroupEntryExtras);
                extras.* = c.WGPUBindGroupEntryExtras{
                    .chain = .{
                        .next = null,
                        .sType = c.WGPUSType_BindGroupEntryExtras,
                    },
                    .textureViewCount = v.len,
                    .textureViews = @ptrCast(v.ptr),
                };
                ret.nextInChain = &extras.chain;
            },
        }

        return ret;
    }
};

pub const Descriptor = struct {
    pub const NativeType = c.WGPUBindGroupDescriptor;

    label: ?[]const u8,
    layout: BindGroupLayout,
    entries: []const Entry,

    pub fn get(self: Descriptor, helper: *ConversionHelper) NativeType {
        return .{
            .nextInChain = null,
            .label = auto.make_string(self.label),
            .layout = self.layout.handle,
            .entryCount = self.entries.len,
            .entries = helper.array_helper(true, Entry, self.entries),
        };
    }
};

pub const Handle = c.WGPUBindGroup;

handle: Handle = null,

pub fn deinit(self: BindGroup) void {
    if (self.handle != null) c.wgpuBindGroupRelease(self.handle);
}
