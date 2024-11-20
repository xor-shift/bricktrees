const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const Buffer = @This();

pub const UsageFlags = packed struct {
    map_read: bool = false,
    map_write: bool = false,
    copy_src: bool = false,
    copy_dst: bool = false,
    index: bool = false,
    vertex: bool = false,
    uniform: bool = false,
    storage: bool = false,
    indirect: bool = false,
    query_resolve: bool = false,
};

pub const Descriptor = struct {
    pub const NativeType = c.WGPUBufferDescriptor;

    label: ?[:0]const u8 = null,
    usage: UsageFlags,
    size: u64,
    mapped_at_creation: bool = false,

    pub fn get(self: Descriptor) NativeType {
        return .{
            .nextInChain = null,
            .label = if (self.label) |v| v.ptr else null,
            .usage = auto.get_flags(self.usage),
            .size = self.size,
            .mappedAtCreation = @intFromBool(self.mapped_at_creation),
        };
    }
};

pub const Handle = c.WGPUBuffer;

handle: Handle = null,

//
