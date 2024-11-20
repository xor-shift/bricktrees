//! An assortment of cool:tm: utilities

const std = @import("std");

pub fn snake_to_pascal_writer(v: []const u8, writer: anytype) anyerror!void {
    var waiting: bool = true;
    for (v) |c| {
        if (c == '_') {
            waiting = true;
            continue;
        }

        if (waiting) {
            _ = try writer.write((&std.ascii.toUpper(c))[0..1]);
            waiting = false;
        } else {
            _ = try writer.write((&c)[0..1]);
        }
    }
}

pub fn snake_to_pascal_len(v: []const u8) usize {
    var writer = std.io.countingWriter(std.io.null_writer);
    snake_to_pascal_writer(v, &writer) catch unreachable;

    return writer.bytes_written;
}

pub fn snake_to_pascal(v: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const pascal_case = try alloc.alloc(u8, snake_to_pascal_len(v));

    const WriterContext = struct {
        out_idx: usize = 0,

        out: *const []u8,

        pub fn write_fn(self: *@This(), bytes: []const u8) anyerror!usize {
            @memcpy(self.out.*[self.out_idx .. self.out_idx + bytes.len], bytes);
            self.out_idx += bytes.len;
            return bytes.len;
        }
    };
    var writer_context: WriterContext = .{
        .out = &pascal_case,
    };

    var writer: std.io.GenericWriter(*WriterContext, anyerror, WriterContext.write_fn) = .{
        .context = &writer_context,
    };

    _ = try snake_to_pascal_writer(v, &writer);

    return pascal_case;
}

pub fn swap_first_two_chars_if_leading_is_digit(v: *const []u8) void {
    if (std.ascii.isDigit(v.*[0])) {
        std.mem.swap(u8, &v.*[0], &v.*[1]);
    }
}

pub fn snake_to_snake(v: []const u8, alloc: std.mem.Allocator) ![]u8 {
    var ret = try alloc.alloc(u8, v.len);

    for (0.., v) |i, c| ret[i] = std.ascii.toLower(c);

    return ret;
}
