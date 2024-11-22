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
        offset: u64,
        size: u64,
    },

    Sampler: Sampler,
    TextureView: TextureView,

    TextureViewArray: []TextureView,
};

pub const Entry = struct {
    pub const NativeType = c.WGPUBindGroupEntry;

    binding: u32,
    resource: BindingResource,

    pub fn get(self: Entry) NativeType {
        var ret: NativeType = .{
            .binding = self.binding,
        };

        switch (self.resource) {
            .Buffer => |v| {
                ret.buffer = v.buffer.handle;
                ret.offset = v.offset;
                ret.size = v.size;
            },
            .Sampler => |v| ret.sampler = v.handle,
            .TextureView => |v| ret.textureView = v.handle,
            .TextureViewArray => |_| std.debug.panic("NYI", .{}),
        }

        return ret;
    }
};

pub const Descriptor = struct {
    pub const NativeType = c.WGPUBindGroupDescriptor;

    label: ?[:0]const u8,
    layout: BindGroupLayout,
    entries: []const Entry,

    pub fn get(self: Descriptor, helper: *ConversionHelper) NativeType {
        return .{
            .nextInChain = null,
            .label = if (self.label) |v| v.ptr else null,
            .layout = self.layout.handle,
            .entryCount = self.entries.len,
            .entries = helper.array_helper(false, Entry, self.entries),
        };
    }
};

pub const Handle = c.WGPUBindGroup;

handle: Handle = null,

pub fn release(self: BindGroup) void {
    c.wgpuBindGroupRelease(self.handle);
}
