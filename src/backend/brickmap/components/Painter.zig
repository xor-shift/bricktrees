const dyn = @import("dyn");

const Computer = @import("Computer.zig");
const Painter = @import("Painter.zig");
const Storage = @import("Storage.zig");

const g = &@import("../../../main.zig").g;

const Self = @This();

painter: *Painter = undefined,
storage: *Storage = undefined,
computer: *Computer = undefined,

pub fn init() !Self {
    return .{};
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn render(self: *Self) void {
    _ = self;
}
