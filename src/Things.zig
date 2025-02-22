const std = @import("std");

const wgpu = @import("gfx").wgpu;
const sdl = @import("gfx").sdl;

const DependencyGraph = @import("DependencyGraph.zig");
const AnyThing = @import("AnyThing.zig");

const Self = @This();

alloc: std.mem.Allocator,

things: std.StringHashMapUnmanaged(AnyThing),

event_graph: DependencyGraph,
render_graph: DependencyGraph,
tick_graph: DependencyGraph,

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .alloc = alloc,

        .things = .{},

        .event_graph = DependencyGraph.init(alloc),
        .render_graph = DependencyGraph.init(alloc),
        .tick_graph = DependencyGraph.init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.things.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(entry.value_ptr.thing);
        entry.value_ptr.destroy(entry.value_ptr.thing, self.alloc);
        self.alloc.free(entry.key_ptr.*);
    }

    self.things.deinit(self.alloc);

    self.event_graph.deinit();
    self.render_graph.deinit();
    self.tick_graph.deinit();
}

pub const Dependency = struct {
    pub const Graph = enum {
        event,
        render,
        tick,
    };

    pub const Kind = enum {
        run_after,
        run_before,
    };

    graph: Graph,
    kind: Kind = .run_after,

    /// special targets include:
    /// - "start"
    /// - "end"
    target: []const u8,
};

pub const ThingConfig = struct {
    dependencies: []const Dependency = &.{},
};

pub fn add_thing(
    self: *Self,
    thing: AnyThing,
    name: []const u8,
    dependencies: []const Dependency,
) void {
    const name_copy = self.alloc.dupe(u8, name) catch @panic("OOM");
    self.things.put(self.alloc, name_copy, thing) catch @panic("OOM");

    for (dependencies) |dependency| {
        const graph: *DependencyGraph = switch (dependency.graph) {
            .tick => &self.tick_graph,
            .render => &self.render_graph,
            .event => &self.event_graph,
        };

        graph.add_dependency(
            switch (dependency.kind) {
                .run_after => dependency.target,
                .run_before => name,
            },
            switch (dependency.kind) {
                .run_after => name,
                .run_before => dependency.target,
            },
        ) catch @panic("OOM");
    }
}

pub fn add_new_thing(
    self: *Self,
    comptime T: type,
    name: []const u8,
    dependencies: []const Dependency,
) *T {
    var thing = self.alloc.create(T) catch @panic("OOM");
    self.add_thing(thing.to_any(), name, dependencies);

    return thing;
}

pub fn call_on_every_thing(self: *Self, comptime fun_str: []const u8, args: anytype) void {
    var iter = self.things.iterator();

    while (iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const thing = entry.value_ptr.*;

        // std.log.debug("calling \"{s}\" on {s} (@ {p})", .{
        //     fun_str,
        //     name,
        //     thing.thing,
        // });

        const fun = @field(thing, fun_str);
        @call(.auto, fun, .{thing.thing} ++ args) catch |e| {
            std.log.err("error calling " ++ fun_str ++ " on AnyThing named \"{s}\" @ {p}: {any}", .{
                name,
                thing.thing,
                e,
            });
        };
    }
}

pub fn process_graph(
    self: *Self,
    comptime graph_name: []const u8,
    comptime fun_name: []const u8,
    args: anytype,
) void {
    var iter = @field(self, graph_name).start() catch @panic("");
    defer iter.deinit();

    const Stage = enum {
        pre_start,
        pre_end,
        post_end,
    };

    var stage: Stage = .pre_start;

    // std.log.debug("-- began --", .{});
    while (true) {
        while (iter.next()) |name| {
            const thing = self.things.get(name) orelse continue;

            // std.log.debug("calling \"{s}\" on {s} (@ {p})", .{
            //     fun_name,
            //     name,
            //     thing.thing,
            // });

            @call(.auto, @field(thing, fun_name), .{thing.thing} ++ args) catch |e| {
                std.log.err("failed to call \"{s}\" on the Thing named \"{s}\" @ {p}: {s}", .{
                    fun_name,
                    name,
                    thing.thing,
                    @errorName(e),
                });
            };
            iter.done(name) catch @panic("");
        }

        switch (stage) {
            .pre_start => {
                // std.log.debug("-- start --", .{});
                iter.done("start") catch @panic("");
                stage = .pre_end;
            },
            .pre_end => {
                // std.log.debug("-- end --", .{});
                iter.done("end") catch @panic("");
                stage = .post_end;
            },
            .post_end => break,
        }
    }
    // std.log.debug("-- finished --", .{});
}

pub fn render(self: *Self, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) void {
    self.process_graph("render_graph", "render", .{ delta_ns, encoder, onto });
}

pub fn tick(self: *Self, delta_ns: u64) void {
    self.process_graph("tick_graph", "on_tick", .{delta_ns});
}

pub fn event(self: *Self, ev: sdl.c.SDL_Event) void {
    self.process_graph("event_graph", "on_raw_event", .{ev});

    switch (ev.common.type) {
        sdl.c.SDL_EVENT_WINDOW_RESIZED => {
            const evw = ev.window;
            const dims: [2]usize = .{ @intCast(evw.data1), @intCast(evw.data2) };

            self.process_graph("event_graph", "on_resize", .{dims});
        },
        else => {
            // std.log.debug("unknown event", .{});
        },
    }
}
