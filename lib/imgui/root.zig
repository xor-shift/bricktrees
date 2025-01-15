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

    const allocation = g.allocator.alignedAlloc(u8, 32, sz + @sizeOf(AllocationHeader)) catch std.debug.panic("failed to allocate for imgui", .{});

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

test {}
