const std = @import("std");

const OBJFile = @import("qov").OBJFile;

pub fn progress(elapsed_ns: u64, done: u64, total: u64) void {
    std.fmt.format(std.io.getStdOut().writer(), "{d}/{d} {d}s elapsed, {d}s remaining        \r", .{
        done,
        total,
        elapsed_ns / std.time.ns_per_s,
        ((elapsed_ns * total / done) - elapsed_ns) / std.time.ns_per_s,
    }) catch {};
}

pub fn Pool(comptime impl: type) type {
    return @import("core").worker_pool.WorkerPool(
        impl.Context,
        impl.Work,
        impl.Result,
    );
}

pub fn CommonContext(comptime impl: type) type {
    return struct {
        out: std.fs.File,

        alloc: std.mem.Allocator,
        pool: *Pool(impl),

        timer: std.time.Timer,

        dims: [3]usize,
        file: *const OBJFile,
        norm_vertices: []const @Vector(3, f32),
    };
}
