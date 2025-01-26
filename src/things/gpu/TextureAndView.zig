const std = @import("std");

const wgpu = @import("gfx").wgpu;

const Self = @This();

texture: wgpu.Texture = .{},
view: wgpu.TextureView = .{},

pub fn init(device: wgpu.Device, tex_desc: wgpu.Texture.Descriptor, view_desc: ?wgpu.TextureView.Descriptor) !Self {
    const texture = try device.create_texture(tex_desc);
    errdefer texture.deinit();

    const view = try texture.create_view(view_desc);
    errdefer view.deinit();

    return .{
        .texture = texture,
        .view = view,
    };
}

pub fn deinit(self: Self) void {
    self.texture.deinit();
    self.view.deinit();
}
