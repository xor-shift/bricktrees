const std = @import("std");

const wgm = @import("wgm");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const AnyThing = @import("../thing.zig").AnyThing;

const g = &@import("../main.zig").g;

const Self = @This();

pub const Any = struct {
    pub fn deinit(self_arg: *anyopaque) void {
        @as(*Self, @ptrCast(@alignCast(self_arg))).deinit();
    }

    pub fn destroy(self_arg: *anyopaque, on_alloc: std.mem.Allocator) void {
        on_alloc.destroy(@as(*Self, @ptrCast(@alignCast(self_arg))));
    }
};

pub fn init() !Self {
    return .{};
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn to_any(self: *Self) AnyThing {
    return .{
        .thing = @ptrCast(self),

        .deinit = Self.Any.deinit,
        .destroy = Self.Any.destroy,
    };
}

const uniforms: struct {
    dims: wgm.Vec2u,
    fov: f32,
    position: wgm.Vec3f,
} = .{
    .dims = wgm.vec2u(768, 576),
    .fov = 45,
    .position = wgm.vec3f(0.0, 0.0, 0.0),
};

fn generate_ray(pixel_arg: wgm.Vec2uz) wgm.Vec3f {
    const pixel = wgm.vec2f(
        @as(f32, @floatFromInt(pixel_arg.x())),
        @as(f32, @floatFromInt(pixel_arg.y())),
    );

    const dims = wgm.vec2f(
        @as(f32, @floatFromInt(uniforms.dims.width())),
        @as(f32, @floatFromInt(uniforms.dims.height())),
    );

    const aspect = dims.x() / dims.y();
    const fov = uniforms.fov;

    const z = 69.420; // does not matter what value this has

    const ray_direction = wgm.normalized(wgm.vec3f(
        @tan(fov) * z * (pixel.x() / dims.width() - 0.5),
        @tan(fov / aspect) * z * (0.5 - pixel.y() / dims.height()),
        z,
    ));

    return ray_direction;
}

pub fn draw(alloc: std.mem.Allocator) !void {
    const qoi = @import("qoi");

    const img_width: usize = 768;
    const img_height: usize = 576;

    const image = try qoi.Image.init(img_width, img_height, 1, .Linear, alloc);
    defer image.deinit();
    @memset(image.data, .{ 255, 0, 255, 255 });

    for (0..img_height) |img_y| {
        for (0..img_width) |img_x| {
            const ray_direction = generate_ray(wgm.vec2uz(img_x, img_y));

            const index = img_x + img_y * img_width;
            image.data[index] = .{
                @intFromFloat(@max(@min(@abs(ray_direction.x()) * 255, 255.0), 0.0)),
                @intFromFloat(@max(@min(@abs(ray_direction.y()) * 255, 255.0), 0.0)),
                @intFromFloat(@max(@min(@abs(ray_direction.z()) * 255, 255.0), 0.0)),
                255,
            };
        }
    }

    const out_file = try std.fs.cwd().createFile("out.qoi", std.fs.File.CreateFlags{
        .read = false,
        .truncate = true,
    });
    defer out_file.close();

    const writer = out_file.writer();
    const any_writer = writer.any();

    _ = try qoi.encode_image(image, any_writer);
}
