const std = @import("std");

const DependencyGraph = @import("DependencyGraph.zig");
const AnyThing = @import("AnyThing.zig");

const Self = @This();

alloc: std.mem.Allocator,

things: std.ArrayListUnmanaged(AnyThing),

render_graph: DependencyGraph,
tick_graph: DependencyGraph,

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .alloc = alloc,

        .things = .{},

        .render_graph = DependencyGraph.init(alloc),
        .tick_graph = DependencyGraph.init(alloc),
    };
}

pub const ThingConfig = struct {
    tick_before: []const []const u8 = &.{},
    tick_after: []const []const u8 = &.{},
    render_before: []const []const u8 = &.{},
    render_after: []const []const u8 = &.{},
};

pub fn add_thing(
    self: *Self,

    comptime T: type,

    name: []const u8,
    config: ThingConfig,
) !*T {
    var thing = self.alloc.create(T) catch @panic("OOM");

    self.things.append(thing.to_any()) catch @panic("OOM");

    for (config.tick_before) |other| self.tick_graph.add_dependency(name, other);
    for (config.tick_after) |other| self.tick_graph.add_dependency(other, name);
    for (config.render_before) |other| self.render_graph.add_dependency(name, other);
    for (config.render_after) |other| self.render_graph.add_dependency(other, name);

    return thing;
}
