const wgpu = @import("gfx").wgpu;

const Self = @This();

desc: wgpu.Buffer.Descriptor,
buffer: wgpu.Buffer,

pub fn init(device: wgpu.Device, base_desc: wgpu.Buffer.Descriptor) !Self {
    var ret: Self = .{
        .desc = base_desc,
        .buffer = undefined,
    };

    try ret.reinit_buffer(device, @intCast(base_desc.size), false);

    return ret;
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
    self.* = undefined;
}

fn reinit_buffer(self: *Self, device: wgpu.Device, with_size: usize, do_deinit: bool) !void {
    var new_descriptor = self.desc;
    new_descriptor.size = @intCast(with_size);

    const new_buffer = try device.create_buffer(new_descriptor);
    errdefer new_buffer.deinit();

    if (do_deinit) {
        self.buffer.deinit();
    }

    self.desc = new_descriptor;
    self.buffer = new_buffer;
}

pub fn ensure_size(self: *Self, device: wgpu.Device, size: usize) !void {
    if (size <= self.desc.size) return;

    try self.reinit_buffer(device, size, true);
}
