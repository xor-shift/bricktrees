const std = @import("std");

const wgpu = @import("gfx").wgpu;

const Self = @This();

textures: []wgpu.Texture = &.{},
views: []wgpu.TextureView = &.{},

pub fn init(n: usize, device: wgpu.Device, tex_desc: wgpu.Texture.Descriptor, view_desc: ?wgpu.TextureView.Descriptor, alloc: std.mem.Allocator) !Self {
    const textures = try alloc.alloc(wgpu.Texture, n);
    errdefer alloc.free(textures);

    const views = try alloc.alloc(wgpu.TextureView, n);
    errdefer alloc.free(views);

    var tvs_created: usize = 0;
    errdefer for (0..tvs_created) |i| {
        views[i].deinit();
        textures[i].deinit();
    };

    for (0..n) |i| {
        const texture = try device.create_texture(tex_desc);
        errdefer texture.deinit();

        const view = try texture.create_view(view_desc);
        errdefer view.deinit();

        textures[i] = texture;
        views[i] = view;

        tvs_created += 1;
    }

    return .{
        .textures = textures,
        .views = views,
    };
}

pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
    for (self.views) |view| view.deinit();
    for (self.textures) |texture| texture.deinit();

    alloc.free(self.views);
    alloc.free(self.textures);
}
