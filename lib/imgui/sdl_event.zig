const std = @import("std");

const sdl = @import("gfx").sdl;

const ContextGuard = @import("root.zig").ContextGuard;

const c = @import("root.zig").c;

fn translate_button(sdl_button: u8) ?c.ImGuiMouseButton {
    return switch (sdl_button) {
        sdl.c.SDL_BUTTON_LEFT => c.ImGuiMouseButton_Left,
        sdl.c.SDL_BUTTON_RIGHT => c.ImGuiMouseButton_Right,
        sdl.c.SDL_BUTTON_MIDDLE => c.ImGuiMouseButton_Middle,
        else => null,
    };
}

fn translate_key(sdl_key: sdl.c.SDL_Scancode) ?c.ImGuiKey {
    // zig fmt: off
    return switch (sdl_key) {
        sdl.c.SDL_SCANCODE_A => c.ImGuiKey_A, sdl.c.SDL_SCANCODE_B => c.ImGuiKey_B, sdl.c.SDL_SCANCODE_C => c.ImGuiKey_C,
        sdl.c.SDL_SCANCODE_D => c.ImGuiKey_D, sdl.c.SDL_SCANCODE_E => c.ImGuiKey_E, sdl.c.SDL_SCANCODE_F => c.ImGuiKey_F,
        sdl.c.SDL_SCANCODE_G => c.ImGuiKey_G, sdl.c.SDL_SCANCODE_H => c.ImGuiKey_H, sdl.c.SDL_SCANCODE_I => c.ImGuiKey_I,
        sdl.c.SDL_SCANCODE_J => c.ImGuiKey_J, sdl.c.SDL_SCANCODE_K => c.ImGuiKey_K, sdl.c.SDL_SCANCODE_L => c.ImGuiKey_L,
        sdl.c.SDL_SCANCODE_M => c.ImGuiKey_M, sdl.c.SDL_SCANCODE_N => c.ImGuiKey_N, sdl.c.SDL_SCANCODE_O => c.ImGuiKey_O,
        sdl.c.SDL_SCANCODE_P => c.ImGuiKey_P, sdl.c.SDL_SCANCODE_Q => c.ImGuiKey_Q, sdl.c.SDL_SCANCODE_R => c.ImGuiKey_R,
        sdl.c.SDL_SCANCODE_S => c.ImGuiKey_S, sdl.c.SDL_SCANCODE_T => c.ImGuiKey_T, sdl.c.SDL_SCANCODE_U => c.ImGuiKey_U,
        sdl.c.SDL_SCANCODE_V => c.ImGuiKey_V, sdl.c.SDL_SCANCODE_W => c.ImGuiKey_W, sdl.c.SDL_SCANCODE_X => c.ImGuiKey_X,
        sdl.c.SDL_SCANCODE_Y => c.ImGuiKey_Y, sdl.c.SDL_SCANCODE_Z => c.ImGuiKey_Z,

        sdl.c.SDL_SCANCODE_0 => c.ImGuiKey_0, sdl.c.SDL_SCANCODE_1 => c.ImGuiKey_1,
        sdl.c.SDL_SCANCODE_2 => c.ImGuiKey_2, sdl.c.SDL_SCANCODE_3 => c.ImGuiKey_3,
        sdl.c.SDL_SCANCODE_4 => c.ImGuiKey_4, sdl.c.SDL_SCANCODE_5 => c.ImGuiKey_5,
        sdl.c.SDL_SCANCODE_6 => c.ImGuiKey_6, sdl.c.SDL_SCANCODE_7 => c.ImGuiKey_7,
        sdl.c.SDL_SCANCODE_8 => c.ImGuiKey_8, sdl.c.SDL_SCANCODE_9 => c.ImGuiKey_9,

        sdl.c.SDL_SCANCODE_KP_0 => c.ImGuiKey_Keypad0, sdl.c.SDL_SCANCODE_KP_1 => c.ImGuiKey_Keypad1,
        sdl.c.SDL_SCANCODE_KP_2 => c.ImGuiKey_Keypad2, sdl.c.SDL_SCANCODE_KP_3 => c.ImGuiKey_Keypad3,
        sdl.c.SDL_SCANCODE_KP_4 => c.ImGuiKey_Keypad4, sdl.c.SDL_SCANCODE_KP_5 => c.ImGuiKey_Keypad5,
        sdl.c.SDL_SCANCODE_KP_6 => c.ImGuiKey_Keypad6, sdl.c.SDL_SCANCODE_KP_7 => c.ImGuiKey_Keypad7,
        sdl.c.SDL_SCANCODE_KP_8 => c.ImGuiKey_Keypad8, sdl.c.SDL_SCANCODE_KP_9 => c.ImGuiKey_Keypad9,

        sdl.c.SDL_SCANCODE_SPACE => c.ImGuiKey_Space,
        sdl.c.SDL_SCANCODE_BACKSPACE => c.ImGuiKey_Backspace,

        sdl.c.SDL_SCANCODE_LSHIFT => c.ImGuiKey_LeftShift, sdl.c.SDL_SCANCODE_RSHIFT => c.ImGuiKey_RightShift,
        sdl.c.SDL_SCANCODE_LCTRL => c.ImGuiKey_LeftCtrl, sdl.c.SDL_SCANCODE_RCTRL => c.ImGuiKey_RightCtrl,
        sdl.c.SDL_SCANCODE_LALT => c.ImGuiKey_LeftAlt, sdl.c.SDL_SCANCODE_RALT => c.ImGuiKey_RightAlt,

        else => null,
    };
    // zig fmt: on
}

pub fn translate_event(context: *c.ImGuiContext, ev: sdl.c.SDL_Event) void {
    const context_guard = ContextGuard.init(context);
    defer context_guard.deinit();

    const io = c.igGetIO();

    // pub extern fn ImGuiIO_AddKeyEvent(self: [*c]ImGuiIO, key: ImGuiKey, down: bool) void;
    // pub extern fn ImGuiIO_AddKeyAnalogEvent(self: [*c]ImGuiIO, key: ImGuiKey, down: bool, v: f32) void;
    // pub extern fn ImGuiIO_AddMousePosEvent(self: [*c]ImGuiIO, x: f32, y: f32) void;
    // pub extern fn ImGuiIO_AddMouseButtonEvent(self: [*c]ImGuiIO, button: c_int, down: bool) void;
    // pub extern fn ImGuiIO_AddMouseWheelEvent(self: [*c]ImGuiIO, wheel_x: f32, wheel_y: f32) void;
    // pub extern fn ImGuiIO_AddMouseSourceEvent(self: [*c]ImGuiIO, source: ImGuiMouseSource) void;
    // pub extern fn ImGuiIO_AddMouseViewportEvent(self: [*c]ImGuiIO, id: ImGuiID) void;
    // pub extern fn ImGuiIO_AddFocusEvent(self: [*c]ImGuiIO, focused: bool) void;
    // pub extern fn ImGuiIO_AddInputCharacter(self: [*c]ImGuiIO, c: c_uint) void;
    // pub extern fn ImGuiIO_AddInputCharacterUTF16(self: [*c]ImGuiIO, c: ImWchar16) void;
    // pub extern fn ImGuiIO_AddInputCharactersUTF8(self: [*c]ImGuiIO, str: [*c]const u8) void;

    switch (ev.common.type) {
        sdl.c.SDL_EVENT_WINDOW_RESIZED => io.*.DisplaySize = .{
            .x = @floatFromInt(ev.window.data1),
            .y = @floatFromInt(ev.window.data2),
        },

        sdl.c.SDL_EVENT_MOUSE_MOTION => c.ImGuiIO_AddMousePosEvent(io, ev.motion.x, ev.motion.y),
        sdl.c.SDL_EVENT_MOUSE_WHEEL => c.ImGuiIO_AddMouseWheelEvent(io, ev.wheel.x, ev.wheel.y),
        sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => if (translate_button(ev.button.button)) |b| c.ImGuiIO_AddMouseButtonEvent(io, b, true),
        sdl.c.SDL_EVENT_MOUSE_BUTTON_UP => if (translate_button(ev.button.button)) |b| c.ImGuiIO_AddMouseButtonEvent(io, b, false),
        sdl.c.SDL_EVENT_KEY_DOWN => if(translate_key(ev.key.scancode)) |k| c.ImGuiIO_AddKeyEvent(io, k, true),
        sdl.c.SDL_EVENT_KEY_UP => if(translate_key(ev.key.scancode)) |k| c.ImGuiIO_AddKeyEvent(io, k, false),

        else => {},
    }
}
