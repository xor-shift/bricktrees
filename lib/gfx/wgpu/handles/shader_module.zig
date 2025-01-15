const std = @import("std");

const auto = @import("../auto.zig");
const common = @import("../common.zig");
const wgpu = @import("../wgpu.zig");

const c = common.c;

const ConversionHelper = common.ConversionHelper;
const Error = common.Error;

const ShaderModule = @This();

pub const Handle = c.WGPUShaderModule;

handle: Handle = null,

pub fn deinit(self: ShaderModule) void {
    c.wgpuShaderModuleRelease(self.handle);
}
