const std = @import("std");

const c = @cImport({
    @cDefine("TRACY_ENABLE", "");
    // @cDefine("TRACY_SYMBOL_OFFLINE_RESOLVE", "");
    @cInclude("tracy/TracyC.h");
});

pub const Context = struct {
    id: u32,
    active: i32,

    pub fn deinit(self: Context) void {
        c.___tracy_emit_zone_end(.{
            .id = self.id,
            .active = self.active,
        });
    }
};

pub fn zone(name: []const u8, comptime sloc: std.builtin.SourceLocation) Context {
    const sloc_handle = c.___tracy_alloc_srcloc_name(
        sloc.line,
        sloc.file.ptr,
        sloc.file.len,
        sloc.fn_name.ptr,
        sloc.fn_name.len,
        name.ptr,
        name.len,
        0xC0FFEE,
    );
    const native_context = c.___tracy_emit_zone_begin_alloc(sloc_handle, 1);

    return .{
        .id = native_context.id,
        .active = native_context.active,
    };
}

pub fn thread_name(name: [:0]const u8) void {
    c.___tracy_set_thread_name(name.ptr);
}

pub fn frame_mark(name: ?[:0]const u8) void {
    c.___tracy_emit_frame_mark(if (name) |v| v.ptr else null);
}

pub fn frame_start(name: ?[:0]const u8) void {
    c.___tracy_emit_frame_mark_start(if (name) |v| v.ptr else null);
}

pub fn frame_end(name: ?[:0]const u8) void {
    c.___tracy_emit_frame_mark_end(if (name) |v| v.ptr else null);
}
