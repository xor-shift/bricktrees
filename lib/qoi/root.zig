const std = @import("std");
const builtin = @import("builtin");

const color = @import("color.zig");

const Image = @import("image.zig");

test {
    std.testing.refAllDecls(color);
    std.testing.refAllDecls(Image);
}

fn qoi_hash(pix: [4]u8) u8 {
    return (pix[0] *% 3 +% pix[1] *% 5 +% pix[2] *% 7 +% pix[3] *% 11) % 64;
}

const Encoder = struct {
    writer: std.io.AnyWriter,

    cur_run: usize = 0,
    hashmap: [64][4]u8 = std.mem.zeroes([64][4]u8),
    prev: [4]u8 = .{ 0, 0, 0, 255 },

    fn update_state(self: *Encoder, pix: [4]u8) void {
        self.prev = pix;
        self.hashmap[qoi_hash(pix)] = pix;
    }

    pub fn process(self: *Encoder, pix: [4]u8) !usize {
        var ret: usize = 0;
        defer self.update_state(pix);

        if (self.cur_run == 62) {
            try self.writer.writeByte(@intCast(0xC0 | (self.cur_run - 1)));
            ret += 1;
            self.cur_run = 0;
        }

        if (std.mem.eql(u8, &pix, &self.prev)) {
            self.cur_run += 1;
            return ret;
        }

        if (self.cur_run != 0) {
            try self.writer.writeByte(@intCast(0xC0 | (self.cur_run - 1)));
            ret += 1;
            self.cur_run = 0;
        }

        if (std.mem.eql(u8, &pix, &self.hashmap[qoi_hash(pix)])) {
            try self.writer.writeByte(qoi_hash(pix));
            ret += 1;
            return ret;
        }

        const dr = pix[0] -% self.prev[0];
        const dg = pix[1] -% self.prev[1];
        const db = pix[2] -% self.prev[2];

        if (pix[3] == self.prev[3] and (dr +% 2) < 4 and (dg +% 2) < 4 and (db +% 2) < 4) {
            const delta = ((dr +% 2) << 4) | ((dg +% 2) << 2) | (db +% 2);
            try self.writer.writeByte(0x40 | delta);
            ret += 1;
            return ret;
        }

        const drdg = dr -% dg;
        const dbdg = db -% dg;

        if (pix[3] == self.prev[3] and (dg +% 32) < 64 and (drdg +% 8) < 16 and (dbdg +% 8) < 16) {
            try self.writer.writeByte(0x80 | (dg +% 32));
            ret += 1;
            try self.writer.writeByte(((drdg +% 8) << 4) | (dbdg +% 8));
            ret += 1;
            return ret;
        }

        if (pix[3] == self.prev[3]) {
            ret += try self.writer.write(&[_]u8{ 0xFE, pix[0], pix[1], pix[2] });
        } else {
            ret += try self.writer.write(&[_]u8{ 0xFF, pix[0], pix[1], pix[2], pix[3] });
        }

        return ret;
    }

    pub fn finish(self: *Encoder) !usize {
        if (self.cur_run != 0) {
            try self.writer.writeByte(@intCast(0xC0 | (self.cur_run - 1)));
            self.cur_run = 0;
            return 1;
        }

        return 0;
    }
};

pub const Error = error{
    /// didn't even have 4 bytes in the buffer
    NoMagic,

    /// The magic value was not recognised ('qoif' and 'qoie' are supported)
    BadMagic,

    ///
    NoHeader,

    UnsupportedChannels,

    UnsupportedColorspace,

    InsufficientPixelData,

    TooMuchData,

    BadEndMark,

    CantEncodeDeep,

    CantEncodeColorspace,
};

pub fn encode_image(image: Image, writer: std.io.AnyWriter) !usize {
    var written: usize = 0;

    if (image.depth != 1) {
        return Error.CantEncodeDeep;
    }

    written += try writer.write("qoif");
    written += try writer.write(&std.mem.toBytes(std.mem.nativeToBig(u32, @intCast(image.width))));
    written += try writer.write(&std.mem.toBytes(std.mem.nativeToBig(u32, @intCast(image.height))));
    try writer.writeByte(4);
    written += 1;
    try writer.writeByte(switch (image.color_space) {
        .Linear => 1,
        .sRGB => 0,
        else => return Error.CantEncodeColorspace,
    });
    written += 1;

    var encoder: Encoder = .{
        .writer = writer,
    };
    for (image.data) |pix| {
        written += try encoder.process(pix);
    }
    written += try encoder.finish();

    written += try writer.write(&.{ 0, 0, 0, 0, 0, 0, 0, 1 });

    return written;
}

const Decoder = struct {
    image: *Image,

    written: usize = 0,
    hashmap: [64][4]u8 = std.mem.zeroes([64][4]u8),
    prev: [4]u8 = .{ 0, 0, 0, 255 },

    pub fn remaining(self: Decoder) usize {
        return self.image.width * self.image.height - self.written;
    }

    pub fn finished(self: Decoder) bool {
        return self.remaining() == 0;
    }

    /// Returns bytes consumed. The returned value will be no more than 5 and will be nonzero.
    /// Do not call if finished() returns true
    pub fn consume(self: *Decoder, command_window: [5]u8) Error!usize {
        const leading = command_window[0];

        const do_error_checking = self.remaining() < 62;

        const debug_out = false;

        switch (leading) {
            // index
            0x00...0x3F => {
                const new_color = self.hashmap[leading];

                self.image.data[self.written] = if (debug_out) .{ 255, 0, 255, 255 } else new_color;

                self.prev = new_color;
                self.written += 1;

                return 1;
            },

            // diff
            0x40...0x7F => {
                const dr = ((leading >> 4) & 3) -% 2;
                const dg = ((leading >> 2) & 3) -% 2;
                const db = (leading & 3) -% 2;

                const new_color = .{
                    self.prev[0] +% dr,
                    self.prev[1] +% dg,
                    self.prev[2] +% db,
                    self.prev[3],
                };

                self.image.data[self.written] = if (debug_out) .{ 127, 0, 255, 255 } else new_color;

                self.prev = new_color;
                self.hashmap[qoi_hash(new_color)] = new_color;
                self.written += 1;

                return 1;
            },

            // luma
            0x80...0xBF => {
                const dg = (leading & 0x3F) -% 32;
                const drdg = (command_window[1] >> 4) -% 8;
                const dbdg = (command_window[1] & 15) -% 8;

                const dr = drdg +% dg;
                const db = dbdg +% dg;

                const new_color = .{
                    self.prev[0] +% dr,
                    self.prev[1] +% dg,
                    self.prev[2] +% db,
                    self.prev[3],
                };

                self.image.data[self.written] = if (debug_out) .{ 0, 0, 255, 255 } else new_color;

                self.prev = new_color;
                self.hashmap[qoi_hash(new_color)] = new_color;
                self.written += 1;
                return 2;
            },

            // run
            0xC0...0xFD => {
                const run_len = (leading & 0x3F) + 1;
                if (do_error_checking and self.remaining() < run_len) {
                    return Error.TooMuchData;
                }

                @memset(self.image.data[self.written .. self.written + run_len], if (debug_out) .{ 0, 255, 0, 255 } else self.prev);

                self.written += run_len;

                return 1;
            },

            // rgb
            0xFE => {
                const new_color = .{
                    command_window[1],
                    command_window[2],
                    command_window[3],
                    self.prev[3],
                };

                self.image.data[self.written] = if (debug_out) .{ 255, 127, 0, 255 } else new_color;

                self.prev = new_color;
                self.hashmap[qoi_hash(new_color)] = new_color;
                self.written += 1;
                return 4;
            },

            // rgba
            0xFF => {
                const new_color = command_window[1..5].*;

                self.image.data[self.written] = if (debug_out) .{ 255, 0, 0, 255 } else new_color;

                self.prev = new_color;
                self.hashmap[qoi_hash(new_color)] = new_color;
                self.written += 1;
                return 5;
            },
        }

        return Error.InsufficientPixelData;
    }
};

pub fn decode_image(data: []const u8, alloc: std.mem.Allocator) !Image {
    if (data.len < 4) return Error.NoMagic;

    const magic: [4]u8 = data[0..4].*;
    if (!std.mem.eql(u8, &magic, &.{ 'q', 'o', 'i', 'f' })) {
        return Error.BadMagic;
    }

    if (data.len < 4 * 3 + 2) {
        return Error.NoHeader;
    }

    const width: u32 = std.mem.bigToNative(u32, @bitCast(data[4..8].*));
    const height: u32 = std.mem.bigToNative(u32, @bitCast(data[8..12].*));

    const channels: u8 = data[12];
    if (channels != 3 and channels != 4) {
        return Error.UnsupportedChannels;
    }

    const colorspace = val: {
        const colorspace_raw = data[13];
        switch (colorspace_raw) {
            0 => break :val color.ColorSpace.sRGB,
            1 => break :val color.ColorSpace.Linear,
            else => return Error.UnsupportedColorspace,
        }
    };

    var image = try Image.init(@intCast(width), @intCast(height), 1, colorspace, alloc);

    var consumed_bytes: usize = 0;
    const payload = data[4 * 3 + 2 ..];

    var decoder: Decoder = .{
        .image = &image,
    };

    while (!decoder.finished()) {
        const remaining_payload = payload.len - consumed_bytes;

        if (remaining_payload <= 8) {
            std.log.err("written {d}, remaining: {d}", .{ decoder.written, remaining_payload });
            return Error.InsufficientPixelData;
        }

        const window: [5]u8 = payload[consumed_bytes .. consumed_bytes + 5][0..5].*;
        const consumed_now = try decoder.consume(window);
        consumed_bytes += consumed_now;
    }

    if (payload.len - consumed_bytes > 8) {
        return Error.TooMuchData;
    }

    if (payload.len - consumed_bytes < 8) {
        return Error.InsufficientPixelData;
    }

    const trailing = payload[payload.len - 8 ..][0..8].*;
    if (!std.mem.eql(u8, &trailing, &.{ 0, 0, 0, 0, 0, 0, 0, 1 })) {
        return Error.BadEndMark;
    }

    return image;
}

test "decode encode redecode" {
    const write_to_file = struct {
        fn aufruf(image: Image) !void {
            const cwd = std.fs.cwd();
            const out_file = try cwd.createFile("out.bin", .{});
            defer out_file.close();

            std.log.err("{dd}x{d}", .{ image.width, image.height });
            _ = try out_file.write(std.mem.sliceAsBytes(image.data));
        }
    }.aufruf;

    _ = write_to_file;

    const testcard_qoi_reference = @embedFile("./test/kodim10.qoi");

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();

    const image = try decode_image(testcard_qoi_reference, alloc);
    defer image.deinit();

    var encoded_data = std.ArrayList(u8).init(alloc);
    var encoded_data_writer = encoded_data.writer();
    _ = try encode_image(image, encoded_data_writer.any());

    const re_decoded_image = try decode_image(encoded_data.items, alloc);
    defer re_decoded_image.deinit();

    //try write_to_file(re_decoded_image);
    try std.testing.expect(std.mem.eql(u8, std.mem.sliceAsBytes(re_decoded_image.data), std.mem.sliceAsBytes(image.data)));
}
