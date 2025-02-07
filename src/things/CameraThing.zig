const std = @import("std");

const wgm2 = @import("wgm2");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const brick = @import("../brick.zig");

const AnyThing = @import("../AnyThing.zig");

const GPUThing = @import("GpuThing.zig");

const Brickmap = @import("../things/gpu/Map.zig").Brickmap;

const BrickmapCoordinates = brick.BrickmapCoordinates;
const VoxelCoordinates = brick.VoxelCoordinates;

const PackedVoxel = brick.PackedVoxel;
const Voxel = brick.Voxel;

const g = &@import("../main.zig").g;

const Self = @This();

pub const Any = struct {
    fn init(self: *Self) AnyThing {
        return .{
            .thing = @ptrCast(self),

            .destroy = Any.destroy,

            .on_raw_event = Any.on_raw_event,

            .on_tick = Any.on_tick,

            .render = Any.render,
            .do_gui = Any.do_gui,
        };
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

    pub fn render(self_arg: *anyopaque, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).render(encoder, onto);
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

mouse_capture: bool = false,
input_state: InputState = std.mem.zeroes(InputState),
mouse_delta: [2]f32 = .{ 0, 0 },

global_coords: [3]f64 = .{0} ** 3,
look: [3]f64 = .{0} ** 3,

gpu_thing: *GPUThing,

pub fn init(gpu_thing: *GPUThing) !Self {
    return .{
        .gpu_thing = gpu_thing,
    };
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
                self.mouse_delta = wgm2.add(self.mouse_delta, [2]f32{ event.xrel, event.yrel });
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
    _ = delta_ns;

    // The tick thread will be used for loading stuff so it might get pretty
    // laggy. We don't want to depend on the tickrate for movement.
    //
    // TODO: Add another tick function for movement. It will be handled in the
    // render thread in the meanwhile.

    // const input_state: InputState = @bitCast(@atomicRmw(
    //     u32,
    //     @as(*u32, @ptrCast(&self.input_state)),
    //     .And,
    //     0x8000_007F,
    //     .acq_rel,
    // ));
    // _ = input_state;

    {
        const wgm = @import("wgm");
        var ret = std.mem.zeroes(Brickmap);
        const bm_coords: BrickmapCoordinates = wgm.splat3uz(0);

        const base_coords: VoxelCoordinates = wgm.mulew(
            bm_coords,
            Brickmap.Traits.side_length,
        );

        for (0..Brickmap.Traits.volume) |voxel_index| {
            const local_coords: VoxelCoordinates = wgm.vec3uz(
                voxel_index % Brickmap.Traits.side_length,
                (voxel_index / Brickmap.Traits.side_length) % Brickmap.Traits.side_length,
                voxel_index / (Brickmap.Traits.side_length * Brickmap.Traits.side_length),
            );

            const coords = wgm.add(base_coords, local_coords);

            _ = coords;

            const t = wgm.divew(
                local_coords.lossy_cast(f32),
                @as(f32, @floatFromInt(Brickmap.Traits.side_length)),
            );

            const dist = wgm.length(wgm.sub(t, 0.5));

            const param = std.math.sin(@as(f32, @floatFromInt(g.frame_no % 240)) / 240 * 2 * std.math.pi);
            if (dist > 0.65 + param / 10) {
                ret.set(local_coords, PackedVoxel{
                    .r = 0xFF,
                    .g = 0,
                    .b = 0xFF,
                    .i = 0x40,
                });
            }
        }

        ret.generate_tree();

        try self.gpu_thing.map.queue_brickmap(wgm.splat3uz(0), &ret);
    }
}

pub fn render(self: *Self, _: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
    const ns_elapsed: u64 = 16_500_000;

    const secs_elapsed = @as(f64, @floatFromInt(ns_elapsed)) / std.time.ns_per_s;

    const speed_slow: f64 = 4.0; // units/sec
    const speed_fast: f64 = 40.0; // units/sec
    const rotation_speed = 0.01; // radians/pixel

    const input_state = self.input_state;

    var movement = [_]i32{0} ** 3;
    if (input_state.forward) movement = wgm2.add(movement, [_]i32{ 0, 0, 1 });
    if (input_state.left) movement = wgm2.add(movement, [_]i32{ -1, 0, 0 });
    if (input_state.backward) movement = wgm2.add(movement, [_]i32{ 0, 0, -1 });
    if (input_state.right) movement = wgm2.add(movement, [_]i32{ 1, 0, 0 });
    if (input_state.up) movement = wgm2.add(movement, [_]i32{ 0, 1, 0 });
    if (input_state.down) movement = wgm2.add(movement, [_]i32{ 0, -1, 0 });

    if (wgm2.compare(.some, movement, .not_equal, [_]i32{0} ** 3)) {
        const movement_f = wgm2.mulew(
            wgm2.normalized(wgm2.lossy_cast(f64, movement)),
            secs_elapsed * if (input_state.fast) speed_fast else speed_slow,
        );

        self.global_coords = wgm2.add(self.global_coords, movement_f);
    }

    const radian_delta = wgm2.mulew(wgm2.lossy_cast(f64, self.mouse_delta), rotation_speed);
    self.look = wgm2.add(self.look, [3]f64{
        radian_delta[0],
        radian_delta[1],
        0,
    });
    self.mouse_delta = .{ 0, 0 };

    const perspective = comptime wgm2.perspective_fov(f64, 0.01, 1000.0, 1.5, 16.0 / 9.0);

    const view = wgm2.mulmm(
        wgm2.rotation_3d_affine(f64, -self.look[0], -self.look[1], 0),
        wgm2.translate_3d(wgm2.negate(self.global_coords)),
    );

    const transform = wgm2.mulmm(perspective, view);

    const inverse_transform = wgm2.inverse(transform).?;

    self.gpu_thing.uniforms.transform = wgm2.lossy_cast(f32, transform);
    self.gpu_thing.uniforms.inverse_transform = wgm2.lossy_cast(f32, inverse_transform);

     self.gpu_thing.uniforms.pos = wgm2.lossy_cast(f32, self.global_coords);
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
    }
    imgui.end();
}
