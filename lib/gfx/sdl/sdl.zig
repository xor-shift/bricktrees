const std = @import("std");

const wgpu = @import("../wgpu/wgpu.zig");

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_system.h");
});

const wgpu_c = @import("../wgpu/common.zig").c;

pub const Error = error{
    Failed,
};

pub const InitFlags = packed struct {
    _reserved_0_0: bool = false,
    _reserved_0_1: bool = false,
    _reserved_0_2: bool = false,
    _reserved_0_3: bool = false,

    audio: bool = false,
    video: bool = false,
    _reserved_1_2: bool = false,
    _reserved_1_3: bool = false,

    _reserved_2_0: bool = false,
    joystick: bool = false,
    _reserved_2_2: bool = false,
    _reserved_2_3: bool = false,

    haptic: bool = false,
    gamepad: bool = false,
    events: bool = false,
    sensor: bool = false,

    camera: bool = false,

    fn get(self: @This()) c.SDL_InitFlags {
        const as_uint: u17 = @bitCast(self);
        return @intCast(as_uint);
    }
};

pub fn init(init_flags: InitFlags) Error!void {
    if (!c.SDL_Init(init_flags.get())) {
        std.log.err("failed to initialize SDL: {s}", .{c.SDL_GetError()});
        return Error.Failed;
    }
}

pub fn deinit() void {
    c.SDL_Quit();
}

pub fn poll_event() Error!?c.SDL_Event {
    var out_event: c.SDL_Event = undefined;
    if (!c.SDL_PollEvent(&out_event)) {
        return null;
    }

    return out_event;
}

fn log_error(what_failed: []const u8) void {
    std.log.err("{s} failed: {s}", .{ what_failed, c.SDL_GetError() });
    std.debug.assert(c.SDL_ClearError());
}

pub const Window = struct {
    pub const ID = u32;

    handle: *c.SDL_Window,

    pub fn init(title: [:0]const u8, dims: [2]usize) Error!Window {
        const window = c.SDL_CreateWindow(title.ptr, @intCast(dims[0]), @intCast(dims[1]), c.SDL_WINDOW_RESIZABLE) orelse {
            std.log.err("SDL_CreateWindow failed: {s}", .{c.SDL_GetError()});
            return Error.Failed;
        };

        return .{
            .handle = window,
        };
    }

    pub fn deinit(self: Window) void {
        c.SDL_DestroyWindow(self.handle);
    }

    pub fn get_id(self: Window) ID {
        return c.SDL_GetWindowID(self.handle);
    }

    pub fn resize(self: Window, dims: [2]usize) !void {
        if (!c.SDL_SetWindowSize(self.handle, @intCast(dims.width()), @intCast(dims.height()))) {
            log_error("SDL_SetWindowSize");
            return Error.Failed;
        }
    }

    pub fn get_size(self: Window) ![2]usize {
        var out: [2]c_int = undefined;
        if (!c.SDL_GetWindowSizeInPixels(self.handle, &out[0], &out[1])) {
            log_error("SDL_GetWindowSize");
            return Error.Failed;
        }

        return [2]usize{ @intCast(out[0]), @intCast(out[1]) };
    }

    fn get_wl_surface(self: @This(), instance: wgpu.Instance) !wgpu.Surface {
        const properties = c.SDL_GetWindowProperties(self.handle);

        const wl_display = c.SDL_GetPointerProperty(properties, c.SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null) orelse {
            std.log.err("SDL_GetPointerProperty for SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER failed: {s}", .{c.SDL_GetError()});
            return Error.Failed;
        };

        std.log.debug("wl_display: {p}", .{wl_display});

        const wl_surface = c.SDL_GetPointerProperty(properties, c.SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null) orelse {
            std.log.err("SDL_GetPointerProperty for SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER failed: {s}", .{c.SDL_GetError()});
            return Error.Failed;
        };

        std.log.debug("wl_surface: {p}", .{wl_surface});

        const wgpu_surface_from_wl_surface: wgpu_c.WGPUSurfaceSourceWaylandSurface = .{
            .chain = .{ .sType = wgpu_c.WGPUSType_SurfaceSourceWaylandSurface, .next = null },
            .display = wl_display,
            .surface = wl_surface,
        };

        const surface_descriptor: wgpu_c.WGPUSurfaceDescriptor = .{
            .nextInChain = &wgpu_surface_from_wl_surface.chain,
            .label = wgpu.make_string("surface"),
        };

        const wgpu_surface = wgpu_c.wgpuInstanceCreateSurface(instance.handle, &surface_descriptor) orelse {
            @panic("failed to create a wgpu surface");
        };

        return .{ .handle = wgpu_surface };
    }

    fn get_x11_surface(self: @This(), instance: wgpu.Instance) !wgpu.Surface {
        const properties = c.SDL_GetWindowProperties(self.handle);

        const xlib_display = c.SDL_GetPointerProperty(properties, c.SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null) orelse {
            std.log.err("SDL_GetPointerProperty for {s} failed: {s}", .{
                c.SDL_PROP_WINDOW_X11_DISPLAY_POINTER,
                c.SDL_GetError(),
            });
            return Error.Failed;
        };
        std.log.debug("xlib_display: {p}", .{xlib_display});

        const xlib_window = c.SDL_GetNumberProperty(properties, c.SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
        if (xlib_window == 0) {
            std.log.err("SDL_GetNumberProperty for {s} failed: {s}", .{
                c.SDL_PROP_WINDOW_X11_WINDOW_NUMBER,
                c.SDL_GetError(),
            });
            return Error.Failed;
        }
        std.log.debug("xlib_window: {d}", .{xlib_window});

        const wgpu_surface_from_xlib_window: wgpu_c.WGPUSurfaceSourceXlibWindow = .{
            .chain = .{
                .sType = wgpu_c.WGPUSType_SurfaceSourceXlibWindow,
                .next = null,
            },
            .display = xlib_display,
            .window = @intCast(xlib_window),
        };

        const surface_descriptor: wgpu_c.WGPUSurfaceDescriptor = .{
            .nextInChain = &wgpu_surface_from_xlib_window.chain,
            .label = wgpu.make_string("surface"),
        };

        const wgpu_surface = wgpu_c.wgpuInstanceCreateSurface(instance.handle, &surface_descriptor) orelse {
            @panic("failed to create a wgpu surface");
        };

        return .{ .handle = wgpu_surface };
    }

    pub fn get_surface(self: @This(), instance: wgpu.Instance) !wgpu.Surface {
        const driver = c.SDL_GetCurrentVideoDriver();

        if (c.SDL_strcmp(driver, "wayland") == 0) {
            return try self.get_wl_surface(instance);
        }

        if (c.SDL_strcmp(driver, "x11") == 0) {
            return try self.get_x11_surface(instance);
        }

        std.log.err("Unknown video driver {s}. Couldn't get a surface.", .{driver});
        return error.NoCompatibleSurface;
    }

    /// Sets the cursor position relative to the window
    pub fn set_cursor_pos(self: Window, coords: [2]f32) void {
        c.SDL_WarpMouseInWindow(self.handle, coords[0], coords[1]);
    }
};

pub fn get_key_status(keycode: u32) bool {
    var num_keys: c_int = undefined;
    const keys_ptr = c.SDL_GetKeyboardState(&num_keys);
    const keys = keys_ptr[0..@as(usize, @intCast(num_keys))];

    //const modstate = c.SDL_GetModState();

    var required_modstate: c.SDL_Keymod = undefined;
    const required_scancode = c.SDL_GetScancodeFromKey(keycode, &required_modstate);

    return keys[required_scancode]; // and modstate == required_modstate;
}

pub fn set_cursor_visibility(visible: bool) Error!void {
    const success = (if (visible) &c.SDL_ShowCursor else &c.SDL_HideCursor)();

    if (!success) {
        log_error(if (visible) "SDL_ShowCursor" else "SDL_HideCursor");
        return Error.Failed;
    }
}
