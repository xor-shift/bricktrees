const std = @import("std");

const wgm = @import("wgm");

const Config = @import("../defns.zig").Config;

const g = &@import("../../../main.zig").g;

pub fn Storage(comptime Cfg: type) type {
    return struct {
        const Self = @This();

        const Backend = @import("../backend.zig").Backend(Cfg);
        const Painter = @import("painter.zig").Painter(Cfg);
        const Computer = @import("computer.zig").Computer(Cfg);

        backend: *Backend = undefined,
        painter: *Painter = undefined,
        computer: *Computer = undefined,

        pub fn init() !Self {
            return .{};
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }
    };
}
