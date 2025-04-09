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

    label: ?[]const u8 = null,
    usage: UsageFlags,
    size: u64,
    mapped_at_creation: bool = false,

    pub fn get(self: Descriptor) NativeType {
        return .{
            .nextInChain = null,
            .label = auto.make_string(self.label),
            .usage = auto.get_flags(self.usage),
            .size = self.size,
            .mappedAtCreation = @intFromBool(self.mapped_at_creation),
        };
    }
};

pub const Handle = c.WGPUBuffer;

handle: Handle = null,

pub fn deinit(self: Buffer) void {
    if (self.handle != null) c.wgpuBufferRelease(self.handle);
}

pub fn destroy(self: Buffer) void {
    if (self.handle != null) c.wgpuBufferDestroy(self.handle);
}

pub fn get_size(self: Buffer) usize {
    return @intCast(c.wgpuBufferGetSize(self.handle));
}

pub const MappedSlice = struct {
    handle: Handle,
    offset: usize,
    size: usize,

    pub fn deinit(self: MappedSlice) void {
        c.wgpuBufferUnmap(self.handle);
    }

    pub fn const_mapped_range(self: MappedSlice) []const u8 {
        const res: [*]const u8 = @ptrCast(c.wgpuBufferGetConstMappedRange(self.handle, self.offset, self.size));

        return res[0 .. self.size];
    }
};

pub const Slice = struct {
    handle: Handle,
    offset: usize,
    size: usize,

    pub fn map_async(
        self: Slice,
        map_mode: wgpu.MapMode,
        callback: *const fn (context: *anyopaque, map_result: MapResult) void,
        context: *anyopaque,
    ) MappedSlice {
        _ = c.wgpuBufferMapAsync(
            self.handle,
            auto.get_flags(map_mode),
            self.offset,
            self.size,
            c.WGPUBufferMapCallbackInfo{
                .nextInChain = null,
                .mode = c.WGPUCallbackMode_AllowSpontaneous,
                .callback = struct {
                    pub fn aufruf(
                        status: c.WGPUMapAsyncStatus,
                        edesc: c.WGPUStringView,
                        userdata1: ?*anyopaque,
                        userdata2: ?*anyopaque,
                    ) callconv(.C) void {
                        const res: MapResult = if (status == c.WGPUMapAsyncStatus_Success)
                            .{ .Success = {} }
                        else
                            .{ .Error = .{
                                .kind = switch (status) {
                                    c.WGPUMapAsyncStatus_InstanceDropped => .InstanceDropped,
                                    c.WGPUMapAsyncStatus_Error => .Error,
                                    c.WGPUMapAsyncStatus_Aborted => .Aborted,
                                    c.WGPUMapAsyncStatus_Unknown => .Unknown,
                                    else => unreachable,
                                },
                                .desc = auto.from_string(edesc),
                            } };

                        const _callback: *const fn (context: *anyopaque, map_result: MapResult) void = @ptrCast(@alignCast(userdata1.?));
                        @call(.auto, _callback, .{ userdata2.?, res });
                    }
                }.aufruf,
                .userdata1 = @ptrCast(@constCast(callback)),
                .userdata2 = context,
            },
        );

        return .{
            .handle = self.handle,
            .offset = self.offset,
            .size = self.size,
        };
    }
};

pub fn slice(self: Buffer, from: usize, to: ?usize) Slice {
    return .{
        .handle = self.handle,
        .offset = from,
        .size = if (to) |v| v - from else self.get_size() - from,
    };
}

pub const MapResult = union(enum) {
    Error: struct {
        pub const ErrorKind = enum {
            InstanceDropped,
            Error,
            Aborted,
            Unknown,
        };
        kind: ErrorKind,
        desc: []const u8,
    },
    Success: void,
};
