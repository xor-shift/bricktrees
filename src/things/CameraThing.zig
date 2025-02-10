const std = @import("std");

const wgm = @import("wgm");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const brick = @import("../brick.zig");

const AnyThing = @import("../AnyThing.zig");

const GPUThing = @import("GpuThing.zig");
const MapThing = @import("MapThing.zig");

const Brickmap = MapThing.Brickmap;

const PackedVoxel = brick.PackedVoxel;
const Voxel = brick.Voxel;

const g = &@import("../main.zig").g;

// Inter-tick chunk loading status
// the heap and the bitset is allocated on g.alloc
const LoadCycleStatus = struct {
    bg_size: [3]usize,
    origin: [3]isize,

    heap: std.PriorityQueue([3]usize, [3]usize, compare_fun),
    seen: std.DynamicBitSet,

    fn compare_fun(bgl_size: [3]usize, lhs: [3]usize, rhs: [3]usize) std.math.Order {
        const bgl_center = wgm.div(bgl_size, 2);

        const weight: [3]isize = .{1, 2, 1};

        const lv = wgm.sub(
            wgm.mulew(wgm.cast(isize, lhs).?, weight),
            wgm.mulew(wgm.cast(isize, bgl_center).?, weight),
        );

        const rv = wgm.sub(
            wgm.mulew(wgm.cast(isize, rhs).?, weight),
            wgm.mulew(wgm.cast(isize, bgl_center).?, weight),
        );

        const ldist = wgm.dot(lv, lv);
        const rdist = wgm.dot(rv, rv);

        return std.math.order(ldist, rdist);
    }

    fn init(bg_size: [3]usize, origin: [3]isize) !@This() {
        var heap = std.PriorityQueue([3]usize, [3]usize, compare_fun).init(g.alloc, bg_size);
        errdefer heap.deinit();

        var seen = try std.DynamicBitSet.initEmpty(
            g.alloc,
            bg_size[0] * bg_size[1] * bg_size[2],
        );
        errdefer seen.deinit();

        var ret: LoadCycleStatus = .{
            .bg_size = bg_size,
            .origin = origin,

            .heap = heap,
            .seen = seen,
        };

        const bgl_center = wgm.div(bg_size, 2);

        try ret.heap.add(bgl_center);
        ret.mark_seen(bgl_center);

        return ret;
    }

    fn deinit(self: *@This()) void {
        self.heap.deinit();
        self.seen.deinit();
    }

    fn queue(self: *@This(), bgl_coords: [3]usize) !void {
        try self.heap.add(bgl_coords);
        self.mark_seen(bgl_coords);
    }

    fn mark_seen(self: *@This(), bgl_coords: [3]usize) void {
        self.seen.set( //
            bgl_coords[0] +
            bgl_coords[1] * self.bg_size[0] +
            bgl_coords[2] * (self.bg_size[0] * self.bg_size[1]));
    }

    fn is_seen(self: *@This(), bgl_coords: [3]usize) bool {
        return self.seen.isSet( //
            bgl_coords[0] +
            bgl_coords[1] * self.bg_size[0] +
            bgl_coords[2] * (self.bg_size[0] * self.bg_size[1]));
    }

    fn iterate(self: *@This()) !?[3]isize {
        if (self.heap.items.len == 0) return null;

        const bgl_cur = self.heap.remove();

        const g_cur = wgm.add(wgm.cast(isize, bgl_cur).?, self.origin);

        for (0..3) |z_offset| for (0..3) |y_offset| for (0..3) |x_offset| {
            const offset = wgm.sub(wgm.cast(isize, [_]usize{ x_offset, y_offset, z_offset }).?, 1);
            if (wgm.compare(.all, offset, .equal, [_]isize{ 0, 0, 0 })) continue;

            const bgl_next = wgm.add(wgm.cast(isize, bgl_cur).?, offset);

            const under_bounds = wgm.compare(
                .some,
                bgl_next,
                .less_than,
                [_]isize{ 0, 0, 0 },
            );

            if (under_bounds) continue;

            const bgl_next_u = wgm.cast(usize, bgl_next).?;

            const over_bounds = wgm.compare(
                .some,
                bgl_next_u,
                .greater_than_equal,
                self.bg_size,
            );

            if (under_bounds or over_bounds) continue;

            if (self.is_seen(bgl_next_u)) continue;
            try self.queue(bgl_next_u);
        };

        return g_cur;
    }
};

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

do_recenter: bool = true,
mouse_capture: bool = false,
input_state: InputState = std.mem.zeroes(InputState),
mouse_delta: [2]f32 = .{ 0, 0 },
fov: f64 = 45.0,

global_coords: [3]f64 = .{0} ** 3,
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

fn generate_chunk(bm_coords: [3]isize) !?Brickmap {
    var ret = std.mem.zeroes(Brickmap);

    const base_coords: [3]isize = wgm.mulew(
        bm_coords,
        Brickmap.Traits.side_length_i,
    );

    const sl = Brickmap.Traits.side_length;

    for (0..sl) |bml_z| for (0..sl) |bml_x| {
        const bml_xz = [2]usize{ bml_x, bml_z };
        const g_xz = wgm.add(wgm.cast(isize, bml_xz).?, [_]isize{
            base_coords[0],
            base_coords[2],
        });
        const dist = wgm.length(wgm.lossy_cast(f64, g_xz));
        const height: isize = @intFromFloat(20 + 10 * @sin(dist / 10));
        const remaining_height: isize = height - base_coords[1];

        if (remaining_height < 0) continue;

        for (0..@min(sl, @as(usize, @intCast(remaining_height)))) |bml_y| {
            ret.set([3]usize{ bml_x, bml_y, bml_z }, PackedVoxel{
                .r = 0xFF,
                .g = 0,
                .b = 0xFF,
                .i = 0x40,
            });
        }
    };

    ret.generate_tree();

    if (ret.tree[0] == 0) return null;
    return ret;
}

pub fn on_tick(self: *Self, delta_ns: u64) !void {
    _ = delta_ns;

    // The tick thread will be used for loading stuff so it might get pretty
    // laggy. We don't want to depend on the tickrate for movement.
    //
    // TODO: Add another tick function for movement. It will be handled in the
    // render thread in the meanwhile.

    // This is terrible
    // While being loosey goosey with the value is fine, this wrong on so many levels
    const bg_origin = self.map_thing.origin_brickmap;
    const bg_size = self.map_thing.config.?.grid_dimensions;

    var asd = try LoadCycleStatus.init(bg_size, bg_origin);
    defer asd.deinit();
    var generated_chunks: usize = 0;
    while (try asd.iterate()) |g_coords| {
        if (generated_chunks >= 1024) break;

        const chunk = (try generate_chunk(g_coords)) orelse continue;
        generated_chunks += 1;

        try self.map_thing.queue_brickmap(g_coords, &chunk);
        // std.log.debug("{any}", .{g_coords});
    }
}

fn process_input(self: *Self, ns_elapsed: u64) void {
    const secs_elapsed = @as(f64, @floatFromInt(ns_elapsed)) / std.time.ns_per_s;

    const speed_slow: f64 = 4.0; // units/sec
    const speed_fast: f64 = 40.0; // units/sec
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
            secs_elapsed * if (input_state.fast) speed_fast else speed_slow,
        );

        self.global_coords = wgm.add(
            self.global_coords,
            movement_f,
        );
    }
}

/// Recenters the map (if necessary) and returns the brickgrid-local coordinates.
fn recenter(self: *Self) [3]f64 {
    const bgl_center = wgm.div(self.map_thing.config.?.grid_dimensions, @as(usize, 2));

    const currently_centered_on = wgm.add(
        self.map_thing.origin_brickmap,
        wgm.cast(isize, bgl_center).?,
    );

    const current_brickmap = wgm.lossy_cast(isize, wgm.trunc(wgm.div(
        self.global_coords,
        wgm.lossy_cast(f64, MapThing.Brickmap.Traits.side_length),
    )));

    const delta_v = wgm.sub(current_brickmap, currently_centered_on);
    const delta_sq = wgm.dot(delta_v, delta_v);

    const should_recenter = delta_sq >= 10;

    if (should_recenter and self.do_recenter) {
        self.map_thing.origin_brickmap = wgm.sub(
            current_brickmap,
            wgm.cast(isize, bgl_center).?,
        );

        std.log.debug("recentering!! current center: {any}, at: {any}, new origin: {any}", .{
            currently_centered_on,
            current_brickmap,
            self.map_thing.origin_brickmap,
        });
    }

    const origin_coords = wgm.mulew(
        self.map_thing.origin_brickmap,
        MapThing.Brickmap.Traits.side_length_i,
    );

    const bgl_coords = wgm.sub(self.global_coords, wgm.lossy_cast(f64, origin_coords));

    return bgl_coords;
}

pub fn render(self: *Self, _: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
    self.process_input(16_500_000);
    const real_coords = self.recenter();

    const dims = try g.window.get_size();

    const transform = wgm.mulmm(
        wgm.perspective_fov(
            f64,
            1,
            1000,
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
    }
    imgui.end();
}
