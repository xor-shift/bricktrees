const std = @import("std");

const wgm = @import("wgm");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const AnyThing = @import("../AnyThing.zig");

const GPUThing = @import("GpuThing.zig");
const MapThing = @import("MapThing.zig");

const PackedVoxel = @import("../voxel.zig").PackedVoxel;
const Voxel = @import("../voxel.zig").Voxel;

const g = &@import("../main.zig").g;

const Self = @This();

pub const Any = struct {
    fn init(self: *Self) AnyThing {
        return .{
            .thing = @ptrCast(self),

            .deinit = Any.deinit,
            .destroy = Any.destroy,

            .on_raw_event = Any.on_raw_event,

            .on_tick = Any.on_tick,

            .render = Any.render,
            .do_gui = Any.do_gui,
        };
    }

    pub fn deinit(self_arg: *anyopaque) void {
        @as(*Self, @ptrCast(@alignCast(self_arg))).deinit();
    }

    pub fn destroy(self_arg: *anyopaque, on_alloc: std.mem.Allocator) void {
        on_alloc.destroy(@as(*Self, @ptrCast(@alignCast(self_arg))));
    }

    pub fn on_raw_event(self_arg: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_raw_event(ev);
    }

    pub fn on_tick(self_arg: *anyopaque, delta_ns: u64) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_tick(delta_ns);
    }

    pub fn render(self_arg: *anyopaque, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).render(delta_ns, encoder, onto);
    }

    pub fn do_gui(self_arg: *anyopaque) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).do_gui();
    }
};

const InputState = packed struct(u32) {
    forward: bool,
    backward: bool,
    left: bool,
    right: bool,
    down: bool,
    up: bool,

    fast: bool,

    _reserved: u25 = undefined,
};

speed_slow: f64 = 4.0,
speed_fast: f64 = 40.0,
do_recenter: bool = true,
mouse_capture: bool = false,
input_state: InputState = std.mem.zeroes(InputState),
mouse_delta: [2]f32 = .{ 0, 0 },
fov: f64 = 45.0,

global_origin: [3]f64 = .{0} ** 3,
global_coords: [3]f64 = .{ 0, 10, 0 },
look: [3]f64 = .{0} ** 3,

map_thing: *MapThing = undefined,
gpu_thing: *GPUThing = undefined,

pub fn init() !Self {
    return .{};
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn to_any(self: *Self) AnyThing {
    return Any.init(self);
}

pub fn on_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    var input_state = self.input_state;
    defer @atomicStore(
        u32,
        @as(*u32, @ptrCast(&self.input_state)),
        @as(u32, @bitCast(input_state)),
        .release,
    );

    switch (ev.common.type) {
        sdl.c.SDL_EVENT_KEY_DOWN => switch (ev.key.key) {
            sdl.c.SDLK_W => input_state.forward = true,
            sdl.c.SDLK_A => input_state.left = true,
            sdl.c.SDLK_S => input_state.backward = true,
            sdl.c.SDLK_D => input_state.right = true,
            sdl.c.SDLK_SPACE => input_state.up = true,
            sdl.c.SDLK_LSHIFT => input_state.down = true,
            sdl.c.SDLK_LCTRL => input_state.fast = true,

            sdl.c.SDLK_ESCAPE => self.mouse_capture = false,
            else => {},
        },

        sdl.c.SDL_EVENT_KEY_UP => switch (ev.key.key) {
            sdl.c.SDLK_W => input_state.forward = false,
            sdl.c.SDLK_A => input_state.left = false,
            sdl.c.SDLK_S => input_state.backward = false,
            sdl.c.SDLK_D => input_state.right = false,
            sdl.c.SDLK_SPACE => input_state.up = false,
            sdl.c.SDLK_LSHIFT => input_state.down = false,
            sdl.c.SDLK_LCTRL => input_state.fast = false,
            else => {},
        },

        sdl.c.SDL_EVENT_MOUSE_MOTION => if (self.mouse_capture) {
            const event = ev.motion;
            const button_state = sdl.c.SDL_GetMouseState(null, null);

            if ((button_state & sdl.c.SDL_BUTTON_MASK(sdl.c.SDL_BUTTON_LEFT)) != 0) {
                self.mouse_delta = wgm.add(self.mouse_delta, [2]f32{ event.xrel, event.yrel });
            }
        },

        sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            self.mouse_capture = true;
        },

        else => {},
    }

    // _ = sdl.c.SDL_SetWindowMouseGrab(g.window.handle, self.mouse_capture);
}

pub fn on_tick(self: *Self, delta_ns: u64) !void {
    _ = self;
    _ = delta_ns;
}

fn process_input(self: *Self, ns_elapsed: u64) void {
    const secs_elapsed = @as(f64, @floatFromInt(ns_elapsed)) / std.time.ns_per_s;

    const rotation_speed = 0.01; // radians/pixel

    const radian_delta = wgm.mulew(wgm.lossy_cast(f64, self.mouse_delta), rotation_speed);
    self.look = wgm.add(self.look, [3]f64{
        radian_delta[0],
        radian_delta[1],
        0,
    });
    self.look[1] = @min(self.look[1], std.math.pi / 2.0);
    self.look[1] = @max(self.look[1], -std.math.pi / 2.0);
    self.mouse_delta = .{ 0, 0 };

    const input_state = self.input_state;

    var movement = [_]i32{0} ** 3;
    if (input_state.forward) movement = wgm.add(movement, [_]i32{ 0, 0, 1 });
    if (input_state.left) movement = wgm.add(movement, [_]i32{ -1, 0, 0 });
    if (input_state.backward) movement = wgm.add(movement, [_]i32{ 0, 0, -1 });
    if (input_state.right) movement = wgm.add(movement, [_]i32{ 1, 0, 0 });
    if (input_state.up) movement = wgm.add(movement, [_]i32{ 0, 1, 0 });
    if (input_state.down) movement = wgm.add(movement, [_]i32{ 0, -1, 0 });

    if (wgm.compare(.some, movement, .not_equal, [_]i32{0} ** 3)) {
        const rotation = wgm.rotate_y_3d(f64, self.look[0]);
        const movement_f = wgm.mulew(
            wgm.mulmm(rotation, wgm.normalized(wgm.lossy_cast(f64, movement))),
            secs_elapsed * if (input_state.fast) self.speed_fast else self.speed_slow,
        );

        self.global_coords = wgm.add(
            self.global_coords,
            movement_f,
        );
    }
}

/// Recenters the map (if necessary) and returns the centered coordinates
fn recenter(self: *Self) [3]f64 {
    const sq_dist_to_center = self.map_thing.sq_distance_to_center(self.global_coords);
    //std.log.debug("{d}", .{sq_dist_to_center});
    if (sq_dist_to_center >= 512 and self.do_recenter) {
        std.log.debug("recentering", .{});
        self.global_origin = self.map_thing.recenter(self.global_coords);
    }

    return wgm.sub(self.global_coords, self.global_origin);
}

pub fn render(self: *Self, delta_ns: u64, _: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
    self.process_input(delta_ns);
    const real_coords = self.recenter();

    const dims = try g.window.get_size();

    const transform = wgm.mulmm(
        wgm.perspective_fov(
            f64,
            0.1,
            10,
            self.fov / 90.0 * std.math.pi,
            @as(f64, @floatFromInt(dims[0])) / @as(f64, @floatFromInt(dims[1])),
        ),
        wgm.mulmm(
            wgm.pad_affine(wgm.mulmm(
                wgm.rotate_x_3d(f64, -self.look[1]),
                wgm.rotate_y_3d(f64, -self.look[0]),
            )),
            wgm.translate_3d(wgm.negate(real_coords)),
        ),
    );

    const inverse_transform = wgm.inverse(transform).?;

    self.gpu_thing.uniforms.transform = wgm.lossy_cast(f32, transform);
    self.gpu_thing.uniforms.inverse_transform = wgm.lossy_cast(f32, inverse_transform);

    self.gpu_thing.uniforms.pos = wgm.lossy_cast(f32, real_coords);
}

pub fn do_gui(self: *Self) !void {
    if (imgui.begin("camera", null, .{})) {
        imgui.cformat("pos: %f, %f, %f", .{
            self.global_coords[0],
            self.global_coords[1],
            self.global_coords[2],
        });

        imgui.cformat("look: %f, %f, %f", .{
            self.look[0],
            self.look[1],
            self.look[2],
        });

        if (imgui.button("reset (fix NaNs)", null)) {
            self.global_coords = .{0} ** 3;
            self.look = .{0} ** 3;
        }

        _ = imgui.input_slider(f64, "fov", &self.fov, 0, 90);

        _ = imgui.c.igCheckbox("enable recentering", &self.do_recenter);

        _ = imgui.input_slider(f64, "slow speed", &self.speed_slow, 0.0, 10.0);
        _ = imgui.input_slider(f64, "fast speed", &self.speed_fast, 10.0, 400.0);
    }
    imgui.end();
}
