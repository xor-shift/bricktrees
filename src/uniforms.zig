const std = @import("std");

const blas = @import("blas/blas.zig");
const sdl = @import("sdl.zig");

const Self = @This();

dims: [2]usize = .{ 0, 0 },
location: blas.Vec3d = blas.vec3d(7.9545981307778195, 6.059075793279358, 7.151635256867796),
mouse_delta_sum: blas.Vec2d = blas.vec2d(0, 0),
rotation: blas.Vec3d = blas.vec3d(-0.42962824881448974, 0.31153445378859734, 0),

capturing_mouse: bool = false,

pub const Serialized = extern struct {
    width: u32,
    height: u32,
    _padding_0: [2]u32 = undefined,

    location: [3]f32,
    _padding_1: f32 = undefined,

    rotation_matrix: [16]f32,
};

pub fn serialize(self: Self) Serialized {
    const rotation = blas.rotation_matrix_3d_affine(f64, self.rotation.el[0], self.rotation.el[1], self.rotation.el[2]).lossy_cast(f32);

    std.log.debug("@ {d}, {d}, {d}; rot: {d}, {d}, {d}", .{
        self.location.el[0], self.location.el[1], self.location.el[2],
        self.rotation.el[0], self.rotation.el[1], self.rotation.el[2],
    });

    return .{
        .width = @intCast(self.dims[0]),
        .height = @intCast(self.dims[1]),
        .location = self.location.lossy_cast(f32).el,
        .rotation_matrix = rotation.el,
    };
}

pub fn resize(self: *Self, dims: [2]usize) void {
    self.dims = dims;
}

pub fn pre_frame(self: *Self, delta_ms: f64) void {
    const g_state = &@import("main.zig").g_state;

    if (self.capturing_mouse) {
        g_state.window.set_cursor_pos(.{ @as(f32, @floatFromInt(self.dims[0])) / 2, @as(f32, @floatFromInt(self.dims[1])) / 2 });

        const radians_per_pixel: f64 = 1.0 / (1080.0 / 2.0) * 3.1415926535897932384626433 / 2.0;
        const radians = blas.mulms(self.mouse_delta_sum, radians_per_pixel);
        self.rotation.add(blas.vec3d(radians.el[0], radians.el[1], 0));
        self.rotation.el[1] = std.math.clamp(self.rotation.el[1], -3.14159, 3.14159);
    }

    self.mouse_delta_sum = blas.vec2d(0, 0);

    const Entry = struct {
        key: u32,
        direction: blas.Vec3d,
    };

    const entries = [_]Entry{
        .{ .key = sdl.c.SDLK_W, .direction = blas.vec3d(0, 0, 1) },
        .{ .key = sdl.c.SDLK_A, .direction = blas.vec3d(-1, 0, 0) },
        .{ .key = sdl.c.SDLK_S, .direction = blas.vec3d(0, 0, -1) },
        .{ .key = sdl.c.SDLK_D, .direction = blas.vec3d(1, 0, 0) },
        .{ .key = sdl.c.SDLK_SPACE, .direction = blas.vec3d(0, 1, 0) },
        .{ .key = sdl.c.SDLK_LSHIFT, .direction = blas.vec3d(0, -1, 0) },
    };

    // units per second
    const velocity: f64 = if (sdl.get_key_status(sdl.c.SDLK_LCTRL)) 15 else 7.5;

    var direction = blas.vec3d(0, 0, 0);

    var any_triggered = false;
    for (entries) |entry| {
        if (sdl.get_key_status(entry.key)) {
            any_triggered = true;
            direction.add(entry.direction);
        }
    }

    if (!any_triggered) {
        return;
    }

    direction = blas.normalized(direction);
    direction = blas.mulmm(blas.rotation_matrix_3d(f64, self.rotation.el[0], self.rotation.el[1], self.rotation.el[2]), direction);

    const delta = blas.mulms(direction, velocity * delta_ms / 1000);
    self.location = blas.add(self.location, delta);
}

pub fn event(self: *Self, ev: sdl.c.SDL_Event) void {
    switch (ev.common.type) {
        sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (ev.button.button == sdl.c.SDL_BUTTON_LEFT) {
            //self.capturing_mouse = !self.capturing_mouse;
            //sdl.set_cursor_visibility(self.capturing_mouse);

            self.capturing_mouse = true;
            sdl.set_cursor_visibility(false) catch {};
        },
        sdl.c.SDL_EVENT_KEY_DOWN => {
            const key_event = ev.key;

            if (key_event.key == sdl.c.SDLK_ESCAPE) {
                self.capturing_mouse = false;
                sdl.set_cursor_visibility(true) catch {};
            }
        },
        sdl.c.SDL_EVENT_MOUSE_MOTION => {
            const motion_event = ev.motion;

            const movement = blas.vec2f(motion_event.xrel, motion_event.yrel);
            self.mouse_delta_sum.add(movement.lossy_cast(f64));
        },
        else => {},
    }
}
