const std = @import("std");

const core = @import("core");
const dyn = @import("dyn");
const imgui = @import("imgui");
const qoi = @import("qoi");
const tracy = @import("tracy");
const wgm = @import("wgm");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const Ticker = core.Ticker;

const Globals = @import("globals.zig");
const Things = @import("Things.zig");

const PackedVoxel = @import("voxel.zig").PackedVoxel;

const IThing = @import("IThing.zig");

pub var g: Globals = undefined;

fn initialize_things(alloc: std.mem.Allocator) void {
    g = Globals.init(Globals.default_resolution, alloc) catch @panic("Globals.init");

    g.thing_store.add_thing(dyn.Fat(*IThing).init(&g), "globals", &.{});

    const GuiThing = @import("things/GuiThing.zig");
    _ = g.thing_store.add_new_thing(GuiThing, "gui", .{});

    const CameraThing = @import("things/CameraThing.zig");
    _ = g.thing_store.add_new_thing(CameraThing, "camera", .{});

    const VisualiserThing = @import("things/VisualiserThing.zig");
    _ = g.thing_store.add_new_thing(VisualiserThing, "visualiser", .{});

    const EditorThing = @import("things/EditorThing.zig");
    const editor = g.thing_store.add_new_thing(EditorThing, "editor", .{.{ 768, 768, 768 }});
    // _ = editor;
    foo(g.alloc, editor.voxels, editor.dims) catch @panic("");

    const DemoProvider = @import("voxel_providers/test.zig");
    _ = g.thing_store.add_new_thing(DemoProvider, "test voxel provider", .{});

    for ([_]struct { []const u8, []const u8 }{
        .{ "globals", "start" },
        .{ "end", "gui" },
        .{ "start", "camera" },

        .{ "camera", "backend" },
        .{ "backend", "visualiser" },

        .{ "camera", "editor" },
        .{ "visualiser", "editor" },
        .{ "editor", "end" },
    }) |p| g.thing_store.render_graph.add_dependency(
        p.@"0",
        p.@"1",
    ) catch @panic("");

    for ([_]struct { []const u8, []const u8 }{
        .{ "globals", "start" },
        .{ "start", "gui" },
        .{ "start", "camera" },

        .{ "start", "backend" },

        .{ "start", "visualiser" },
        .{ "start", "editor" },
    }) |p| g.thing_store.tick_graph.add_dependency(
        p.@"0",
        p.@"1",
    ) catch @panic("");

    for ([_]struct { []const u8, []const u8 }{
        .{ "globals", "start" },
        .{ "start", "gui" },
        .{ "start", "camera" },
        .{ "start", "backend" },
        .{ "start", "visualiser" },

        .{ "visualiser", "backend" },

        .{ "start", "editor" },
    }) |p| g.thing_store.event_graph.add_dependency(
        p.@"0",
        p.@"1",
    ) catch @panic("");

    g.do_resize(Globals.default_resolution) catch @panic("");
}

fn deinitialize_things() void {
    g.do_deinit();
}

fn foo(alloc: std.mem.Allocator, out: []PackedVoxel, dims: [3]usize) !void {
    const cwd = std.fs.cwd();

    const file = try cwd.openFile("scenes/hairball/hairball.obj", .{});

    var line_buffer: []u8 = try alloc.alloc(u8, 8192);
    defer alloc.free(line_buffer);
    var buffer_usage: usize = 0;

    var vertices = std.ArrayList([3]f32).init(alloc);
    defer vertices.deinit();
    var faces = std.ArrayList([3]u32).init(alloc);
    defer faces.deinit();

    while (true) {
        const read_bytes = try file.read(line_buffer[buffer_usage..]);
        if (read_bytes == 0) break;
        buffer_usage += read_bytes;

        var read_idx: usize = 0;
        while (true) {
            const remaining = line_buffer[read_idx..buffer_usage];
            const next_newline = std.mem.indexOfScalar(u8, remaining[0..], '\n') orelse break;
            read_idx += next_newline + 1;

            const line = if (remaining[next_newline - 1] == '\r')
                remaining[0 .. next_newline - 1]
            else
                remaining[0..next_newline];

            errdefer std.log.debug("line: {s}", .{line});

            var split_iter = std.mem.splitScalar(u8, line, ' ');

            const directive = split_iter.next() orelse continue;

            const read_coord = struct {
                fn aufruf(iter: *std.mem.SplitIterator(u8, .scalar)) !f32 {
                    const segment = iter.next() orelse return error.InsufficientArguments;
                    return std.fmt.parseFloat(f32, segment) catch return error.BadArgument;
                }
            }.aufruf;

            const read_vertex = struct {
                fn aufruf(iter: *std.mem.SplitIterator(u8, .scalar)) !u32 {
                    const segment = iter.next() orelse return error.InsufficientArguments;
                    const i = std.mem.indexOfScalar(u8, segment, '/') orelse segment.len;
                    return std.fmt.parseInt(u32, segment[0..i], 10) catch return error.BadArgument;
                }
            }.aufruf;

            if (std.mem.eql(u8, directive, "v")) {
                const coords = .{
                    try read_coord(&split_iter),
                    try read_coord(&split_iter),
                    try read_coord(&split_iter),
                };
                try vertices.append(coords);
            } else if (std.mem.eql(u8, directive, "f")) {
                const tri_vertices = .{
                    try read_vertex(&split_iter),
                    try read_vertex(&split_iter),
                    try read_vertex(&split_iter),
                };
                try faces.append(tri_vertices);
            }
        }

        std.mem.copyForwards(u8, line_buffer[0..], line_buffer[read_idx..buffer_usage]);
        buffer_usage -= read_idx;

        if (buffer_usage == line_buffer.len) {
            return error.LineTooLong;
        }
    }
    std.log.debug("read {d} vertices and {d} faces", .{ vertices.items.len, faces.items.len });

    const min, const max = blk: {
        var min = [3]f32{
            std.math.inf(f32),
            std.math.inf(f32),
            std.math.inf(f32),
        };

        var max = [3]f32{
            -std.math.inf(f32),
            -std.math.inf(f32),
            -std.math.inf(f32),
        };

        for (faces.items) |face| for (face) |idx| {
            const coord = vertices.items[@intCast(idx - 1)];

            min[0] = @min(min[0], coord[0]);
            min[1] = @min(min[1], coord[1]);
            min[2] = @min(min[2], coord[2]);

            max[0] = @max(max[0], coord[0]);
            max[1] = @max(max[1], coord[1]);
            max[2] = @max(max[2], coord[2]);
        };

        break :blk .{ min, max };
    };

    std.log.debug("min: {any}", .{min});
    std.log.debug("max: {any}", .{max});

    var max_vox = [3]i32{
        std.math.minInt(i32),
        std.math.minInt(i32),
        std.math.minInt(i32),
    };

    var check_ct: u512 = 0;

    const fd = wgm.mulew(wgm.lossy_cast(f32, dims), 0.999);
    for (faces.items) |face| {
        const tri: [3][3]f32 = .{
            .{
                fd[0] * (vertices.items[@intCast(face[0] - 1)][0] - min[0]) / (max[0] - min[0]),
                fd[1] * (vertices.items[@intCast(face[0] - 1)][1] - min[1]) / (max[1] - min[1]),
                fd[2] * (vertices.items[@intCast(face[0] - 1)][2] - min[2]) / (max[2] - min[2]),
            },
            .{
                fd[0] * (vertices.items[@intCast(face[1] - 1)][0] - min[0]) / (max[0] - min[0]),
                fd[1] * (vertices.items[@intCast(face[1] - 1)][1] - min[1]) / (max[1] - min[1]),
                fd[2] * (vertices.items[@intCast(face[1] - 1)][2] - min[2]) / (max[2] - min[2]),
            },
            .{
                fd[0] * (vertices.items[@intCast(face[2] - 1)][0] - min[0]) / (max[0] - min[0]),
                fd[1] * (vertices.items[@intCast(face[2] - 1)][1] - min[1]) / (max[1] - min[1]),
                fd[2] * (vertices.items[@intCast(face[2] - 1)][2] - min[2]) / (max[2] - min[2]),
            },
        };

        const vox_span = [2][3]i32{
            .{
                @intFromFloat(@trunc(@min(@min(tri[0][0], tri[1][0]), tri[2][0]))),
                @intFromFloat(@trunc(@min(@min(tri[0][1], tri[1][1]), tri[2][1]))),
                @intFromFloat(@trunc(@min(@min(tri[0][2], tri[1][2]), tri[2][2]))),
            },
            .{
                @intFromFloat(@ceil(@max(@max(tri[0][0], tri[1][0]), tri[2][0]))),
                @intFromFloat(@ceil(@max(@max(tri[0][1], tri[1][1]), tri[2][1]))),
                @intFromFloat(@ceil(@max(@max(tri[0][2], tri[1][2]), tri[2][2]))),
            },
        };

        const vox_span_size = [3]i32{
            vox_span[1][0] - vox_span[0][0],
            vox_span[1][1] - vox_span[0][1],
            vox_span[1][2] - vox_span[0][2],
        };

        max_vox[0] = @max(max_vox[0], vox_span_size[0]);
        max_vox[1] = @max(max_vox[1], vox_span_size[1]);
        max_vox[2] = @max(max_vox[2], vox_span_size[2]);

        check_ct += @intCast(vox_span_size[0] * vox_span_size[1] * vox_span_size[2]);

        const triuz: [3][3]usize = .{
            wgm.lossy_cast(usize, tri[0]),
            wgm.lossy_cast(usize, tri[1]),
            wgm.lossy_cast(usize, tri[2]),
        };

        out[
            triuz[0][0] //
            + triuz[0][1] * dims[0] //
            + triuz[0][2] * dims[0] * dims[1]
        ] = PackedVoxel.white;

        out[
            triuz[1][0] //
            + triuz[1][1] * dims[0] //
            + triuz[1][2] * dims[0] * dims[1]
        ] = PackedVoxel.white;

        out[
            triuz[2][0] //
            + triuz[2][1] * dims[0] //
            + triuz[2][2] * dims[0] * dims[1]
        ] = PackedVoxel.white;
    }

    std.log.debug("max vox: {any}", .{max_vox});
    std.log.debug("check ct: {d}", .{check_ct});
}

pub fn main() !void {
    tracy.thread_name("main");
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) std.log.warn("leaked memory", .{});

    initialize_things(alloc);
    defer deinitialize_things();

    var ticker: Ticker = .{
        .config = .{
            .ns_per_tick = 50 * std.time.ns_per_ms,
            .mode = .aligned,
        },
        .time_ctx = undefined,
        .time_provider = struct {
            pub fn aufruf(_: *anyopaque) u64 {
                return g.time();
            }
        }.aufruf,
    };

    const TickFn = struct {
        const Self = @This();

        rand: std.rand.Xoshiro256,
        last: u64 = 0,

        pub fn aufruf(self: *Self) void {
            const time = g.time();
            // std.log.debug("ticking at {d} (+ {d})", .{
            //     time,
            //     @as(f64, @floatFromInt(time - self.last)) / std.time.ns_per_ms,
            // });
            defer self.last = time;

            g.thing_store.tick(time - self.last);

            // std.log.debug("tick took {d} ms", .{
            //     @as(f64, @floatFromInt(g.time() - time)) / std.time.ns_per_ms,
            // });

            // const ms = self.rand.next() % 100;
            // std.time.sleep(ms * std.time.ns_per_ms);
        }
    };

    var tick_fn: TickFn = .{
        .rand = std.rand.Xoshiro256.init(
            @truncate(@as(u128, @intCast(std.time.nanoTimestamp()))),
        ),
    };

    try ticker.run(
        .{},
        TickFn.aufruf,
        .{&tick_fn},
        struct {
            pub fn aufruf() void {
                tracy.thread_name("tick thread");
            }
        }.aufruf,
        .{},
    );
    defer ticker.stop();

    var last_frame_start = g.time() - 16_500_000;
    outer: while (true) {
        tracy.frame_mark(null);

        const frame_start = g.time();
        const frametime_ns = frame_start - last_frame_start;
        defer last_frame_start = frame_start;

        const frametime_ms = @as(f64, @floatFromInt(frametime_ns)) / std.time.ns_per_ms;

        _ = frametime_ms;
        // std.log.debug("new frame after {d} ms", .{frametime_ms});
        g.new_frame();

        while (try sdl.poll_event()) |ev| {
            g.submit_event(ev);

            switch (ev.common.type) {
                sdl.c.SDL_EVENT_QUIT => break :outer,
                else => {},
            }
        }

        const current_texture = g.surface.get_current_texture() catch |e| {
            if (e == wgpu.Error.Outdated) {
                std.log.debug("outdated", .{});
                try g.do_resize(g.window.get_size() catch unreachable);
                continue;
            } else {
                return e;
            }
        };

        const current_texture_view = try current_texture.texture.create_view(.{
            .label = "current render texture view",
        });

        g.gui().new_frame(frametime_ns);

        const command_encoder = try g.device.create_command_encoder(null);

        {
            const _context_guard = imgui.ContextGuard.init(g.gui().c());
            defer _context_guard.deinit();

            g.thing_store.call_on_every_thing("do_gui", .{});
        }

        g.thing_store.render(frametime_ns, command_encoder, current_texture_view);

        current_texture_view.deinit();

        const command_buffer = try command_encoder.finish(null);
        command_encoder.deinit();

        g.queue.submit((&command_buffer)[0..1]);
        command_buffer.deinit();

        g.surface.present() catch {};

        current_texture.texture.deinit();
    }
}

test {
    // std.debug.assert(false);

    // std.testing.refAllDecls(@import("backend/brickmap/Backend.zig"));
    std.testing.refAllDecls(@import("worker_pool.zig"));
    std.testing.refAllDecls(@import("rt/ray.zig"));

    std.testing.refAllDecls(@import("DependencyGraph.zig"));
}

// test "will leak" {
//     const alloc = std.testing.allocator_instance.allocator();
//     _ = try alloc.alloc(u8, 1);
// }
//
// test "will fail" {
//     try std.testing.expectEqual(true, false);
// }
