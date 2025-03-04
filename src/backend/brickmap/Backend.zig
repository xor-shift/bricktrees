const std = @import("std");

test {
    std.testing.refAllDecls(@import("brickmap.zig"));
    std.testing.refAllDecls(@import("things/MapThing.zig"));
    std.testing.refAllDecls(@import("things/GpuThing.zig"));
    std.testing.refAllDecls(@import("things/VoxelThing.zig"));
    std.testing.refAllDecls(@import("bricktree/u8.zig"));
    std.testing.refAllDecls(@import("bricktree/u64.zig"));
    std.testing.refAllDecls(@import("bricktree/curves.zig"));
}
