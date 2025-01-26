const std = @import("std");

const wgpu = @import("gfx").wgpu;

const Self = @This();

buffers: []wgpu.Buffer = &.{},

pub fn init(n: usize, device: wgpu.Device, desc: wgpu.Buffer.Descriptor, alloc: std.mem.Allocator) !Self {
    const buffers = try alloc.alloc(wgpu.Buffer, n);
    errdefer alloc.free(buffers);

    var buffers_created: usize = 0;
    errdefer for (0..buffers_created) |i| {
        buffers[i].deinit();
    };

    for (0..n) |i| {
        const buffer = try device.create_buffer(desc);
        errdefer buffer.deinit();

        buffers[i] = buffer;

        buffers_created += 1;
    }

    return .{
        .buffers = buffers,
    };
}

pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
    for (self.buffers) |buffer| buffer.deinit();

    alloc.free(self.buffers);
}
