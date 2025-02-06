const std = @import("std");

pub const Config = struct {
    // 2 4 3 7 5 2 2
    //
    // 0    5    10   15   20   25
    // #----#----#----#----#----#----#----#----#
    // []   [--] [-]  [-----]   [---][]   []     aligned
    // []   [--] [-]  [-----][---][] []          crammed
    /// Prefer crammed.
    const TickMode = enum {
        dumb,
        aligned,
        crammed,
    };

    ns_per_tick: u64,
    mode: TickMode,
};

const g = &@import("main.zig").g;

config: Config,

exit_mutex: std.Thread.Mutex = .{},
exit: bool = false,
exit_cv: std.Thread.Condition = .{},

thread: ?std.Thread = null,

next_tick_at: u64 = undefined,

const Self = @This();

/// Pins `self`.
pub fn run(
    self: *Self,
    thread_config: std.Thread.SpawnConfig,
    comptime function: anytype,
    args: anytype,
) !void {
    self.thread = try std.Thread.spawn(
        thread_config,
        worker,
        .{ self, function, args },
    );
}

const WaitResult = enum {
    quitting,
    do_tick,
};

fn wait(self: *Self) WaitResult {
    self.exit_mutex.lock();
    defer self.exit_mutex.unlock();

    while (true) {
        if (@atomicLoad(bool, &self.exit, .acquire)) return .quitting;

        const time = g.time();

        if (time >= self.next_tick_at) break;

        const remaining_ns = self.next_tick_at - time;

        self.exit_cv.timedWait(&self.exit_mutex, remaining_ns) catch {};
    }

    return .do_tick;
}

fn worker(
    self: *Self,
    comptime function: anytype,
    args: anytype,
) void {
    self.next_tick_at = g.time() + self.config.ns_per_tick;

    while (true) {
        if (self.wait() == .quitting) break;

        const start_time = g.time();

        if (start_time >= self.next_tick_at + std.time.ns_per_ms) {
            const lag_ns = start_time - self.next_tick_at;
            std.log.warn("tick started {d}ms late", .{
                @as(f64, @floatFromInt(lag_ns)) / std.time.ns_per_ms,
            });
        }

        @call(.auto, function, args);

        const end_time = g.time();

        const tick_duration = end_time - start_time;

        switch (self.config.mode) {
            .dumb => self.next_tick_at = start_time + self.config.ns_per_tick,
            .aligned => {
                const ticks_taken = ((tick_duration + self.config.ns_per_tick - 1) / self.config.ns_per_tick);

                if (ticks_taken > 1) {
                    std.log.warn("lagging behind by {d} tick(s) (last tick took {d} ms)", .{
                        ticks_taken - 1,
                        @as(f64, @floatFromInt(tick_duration)) / std.time.ns_per_ms,
                    });
                }

                self.next_tick_at += self.config.ns_per_tick * ticks_taken;
            },
            .crammed => {
                const ticks_taken = @max(1, tick_duration / self.config.ns_per_tick);

                self.next_tick_at += self.config.ns_per_tick * ticks_taken;
            },
        }
    }
}

pub fn stop(self: *Self) void {
    self.exit_mutex.lock();
    @atomicStore(bool, &self.exit, true, .release);
    self.exit_cv.signal();
    self.exit_mutex.unlock();
    self.thread.?.join();
}
