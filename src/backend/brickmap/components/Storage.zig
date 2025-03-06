const Self = @This();

const Computer = @import("Computer.zig");
const Painter = @import("Painter.zig");
const Storage = @import("Storage.zig");

const g = &@import("../../../main.zig").g;

painter: *Painter = undefined,
storage: *Storage = undefined,
computer: *Computer = undefined,

pub fn init() !Self {
    return .{};
}

pub fn deinit(self: *Self) void {
    _ = self;
}
