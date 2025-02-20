const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const Extent3D = wgpu.Extent3D;
const TextureView = wgpu.TextureView;
const TextureUsage = wgpu.TextureUsage;
const TextureDimension = wgpu.TextureDimension;
const TextureFormat = wgpu.TextureFormat;

const Texture = @This();

pub const Descriptor = struct {
    pub const NativeType = c.WGPUTextureDescriptor;

    label: ?[]const u8 = null,
    usage: TextureUsage = .{},
    dimension: TextureDimension,
    size: Extent3D,
    format: TextureFormat,
    mipLevelCount: u32,
    sampleCount: u32,
    view_formats: []const TextureFormat,

    pub fn get(self: Descriptor) Descriptor.NativeType {
        return .{
            .nextInChain = null,
            .label = auto.make_string(self.label),
            .usage = auto.get_flags(self.usage),
            .dimension = @intFromEnum(self.dimension),
            .size = self.size.get(),
            .format = @intFromEnum(self.format),
            .mipLevelCount = self.mipLevelCount,
            .sampleCount = self.sampleCount,
            .viewFormatCount = self.view_formats.len,
            .viewFormats = @ptrCast(self.view_formats),
        };
    }
};

pub const Handle = c.WGPUTexture;

handle: Handle = null,

pub fn deinit(self: Texture) void {
    if (self.handle != null) c.wgpuTextureRelease(self.handle);
}

pub fn create_view(self: Texture, descriptor: ?TextureView.Descriptor) Error!TextureView {
    const c_desc: ?*const TextureView.Descriptor.NativeType = if (descriptor) |v| &(v.get()) else null;

    const view = c.wgpuTextureCreateView(self.handle, c_desc);

    return .{ .handle = view orelse return Error.UnexpectedNull };
}
