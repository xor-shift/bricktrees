const std = @import("std");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub fn foo() void {
    c.SDL_Init(0);
}
