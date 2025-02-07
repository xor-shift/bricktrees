const std = @import("std");

pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "");
    @cInclude("cimgui.h");
});

pub const sdl_event = @import("sdl_event.zig");

pub usingnamespace @import("vec.zig");

pub const ContextGuard = struct {
    previous_context: ?*c.ImGuiContext,

    pub fn init(context: *c.ImGuiContext) ContextGuard {
        const old = c.igGetCurrentContext();

        c.igSetCurrentContext(context);

        return .{
            .previous_context = old,
        };
    }

    pub fn deinit(self: ContextGuard) void {
        c.igSetCurrentContext(self.previous_context);
    }
};

pub const Uniforms = extern struct {
    dimensions: [2]u32,
    padding: [8]u8 = undefined,
};

pub const WGPUContext = @import("wgpu_context.zig");

const Globals = struct {
    allocator: std.mem.Allocator,
};

const AllocationHeader = extern struct {
    allocation_size: u64,
    padding: [3]u64 = undefined,
};

var globals: Globals = undefined;

fn im_alloc_func(sz: usize, user_data: ?*anyopaque) callconv(.C) ?*anyopaque {
    const g: *Globals = @ptrCast(@alignCast(user_data.?));
    std.debug.assert(g == &globals);

    const allocation = g.allocator.alignedAlloc(u8, 32, sz + @sizeOf(AllocationHeader)) catch @panic("failed to allocate for imgui");

    const header: AllocationHeader = .{
        .allocation_size = @intCast(sz),
    };

    @memcpy(allocation[0..@sizeOf(AllocationHeader)], std.mem.asBytes(&header));

    return allocation.ptr + @sizeOf(AllocationHeader);
}

fn im_free_func(maybe_unaligned_ptr: ?*anyopaque, user_data: ?*anyopaque) callconv(.C) void {
    const g: *Globals = @ptrCast(@alignCast(user_data.?));
    std.debug.assert(g == &globals);

    // Why would John ImGui do this?
    const unaligned_ptr = maybe_unaligned_ptr orelse return;

    const unoffset_ptr: [*]align(32) u8 = @ptrCast(@alignCast(unaligned_ptr));
    const ptr: [*]align(32) u8 = unoffset_ptr - @sizeOf(AllocationHeader);

    const header = blk: {
        var header: AllocationHeader = undefined;
        @memcpy(std.mem.asBytes(&header), ptr[0..@sizeOf(AllocationHeader)]);

        break :blk header;
    };

    const slice = ptr[0 .. header.allocation_size + @sizeOf(AllocationHeader)];

    g.allocator.free(slice);
}

pub fn init(im_alloc: std.mem.Allocator) void {
    globals = .{
        .allocator = im_alloc,
    };

    c.igSetAllocatorFunctions(im_alloc_func, im_free_func, &globals);
}

pub fn deinit() void {
    c.igSetAllocatorFunctions(null, null, null);
}

const WindowFlags = packed struct(c_int) {
    no_title_bar: bool = false,
    no_resize: bool = false,
    no_move: bool = false,
    no_scrollbar: bool = false,
    no_scroll_with_mouse: bool = false,
    no_collapse: bool = false,
    always_auto_resize: bool = false,
    no_background: bool = false,
    no_saved_settings: bool = false,
    no_mouse_inputs: bool = false,
    menu_bar: bool = false,
    horizontal_scrollbar: bool = false,
    no_focus_on_appearing: bool = false,
    no_bring_to_front_on_focus: bool = false,
    always_vertical_scrollbar: bool = false,
    always_horizontal_scrollbar: bool = false,
    no_nav_inputs: bool = false,
    no_nav_focus: bool = false,
    unsaved_document: bool = false,
    no_docking: bool = false,
    _reserved_0: u4 = 0,
    child_window: bool = false,
    tooltip: bool = false,
    popup: bool = false,
    modal: bool = false,
    child_menu: bool = false,
    dock_node_host: bool = false,
    _reserved_1: u2 = 0,

    const no_navigation: WindowFlags = .{
        .no_nav_inputs = true,
        .no_nav_focus = true,
    };

    const no_inputs: WindowFlags = .{
        .no_nav_inputs = true,
        .no_nav_focus = true,
        .no_mouse_inputs = true,
    };

    const no_decoration: WindowFlags = .{
        .no_title_bar = true,
        .no_resize = true,
        .no_scrollbar = true,
        .no_collapse = true,
    };
};

/// Call end() regardless of whether this returns true.
pub fn begin(label: [:0]const u8, is_open: ?*bool, flags: WindowFlags) bool {
    return c.igBegin(label.ptr, is_open, @bitCast(flags));
}

pub fn end() void {
    return c.igEnd();
}

pub fn button(label: [:0]const u8, size: ?[2]f32) bool {
    return c.igButton(
        label.ptr,
        if (size) |v| .{ .x = v[0], .y = v[1] } //
        else .{ .x = 0, .y = 0 },
    );
}

pub fn input_scalar(comptime T: type, label: [:0]const u8, v: *T, step: T, step_fast: T) bool {
    const is_ilp32 = @bitSizeOf(c_long) != @bitSizeOf(c_longlong);

    const args = switch (T) {
        i8 => .{ c.ImGuiDataType_S8, "%hhd" },
        u8 => .{ c.ImGuiDataType_U8, "%hhu" },
        i16 => .{ c.ImGuiDataType_S16, "%hd" },
        u16 => .{ c.ImGuiDataType_U16, "%hu" },
        i32 => .{ c.ImGuiDataType_S32, if (is_ilp32) "%l" else "%d" },
        u32 => .{ c.ImGuiDataType_U32, if (is_ilp32) "%lu" else "%u" },
        i64 => .{ c.ImGuiDataType_S64, if (is_ilp32) "%lld" else "%ld" },
        u64 => .{ c.ImGuiDataType_U64, if (is_ilp32) "%llu" else "%lu" },
        f32 => .{ c.ImGuiDataType_Float, "%f" },
        f64 => .{ c.ImGuiDataType_Double, "%d" },
        else => @compileError("unsupported type passed into input_scalar"),
    };

    return c.igInputScalar(
        label.ptr,
        args.@"0",
        @ptrCast(v),
        &step,
        &step_fast,
        args.@"1",
        0,
    );
}

pub fn cformat(fmt: [:0]const u8, args: anytype) void {
    @call(.auto, c.igText, .{fmt} ++ args);
}
