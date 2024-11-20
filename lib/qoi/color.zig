const std = @import("std");

pub const ColorSpace = enum(u8) {
    Any,

    Linear,
    sRGB,
    XYZ,
};

const ConverterSet = struct {
    fun_f64: *const fn (in: Color(f64, .Any)) Color(f64, .Any),
    fun_u64: *const fn (in: Color(u64, .Any)) Color(u64, .Any),
};

const ColorConversion = struct {
    from: ColorSpace,
    to: ColorSpace,

    set: ConverterSet,

    fn convert(self: @This(), comptime T: type, in: Color(T, .Any)) Color(T, .Any) {
        switch (T) {
            f64 => return self.set.fun_f64(in),
            u64 => return self.set.fun_u64(in),
            else => switch (@typeInfo(T)) {
                .Float => return self.set.fun_f64(in.cast(f64)),
                .Integer => return self.set.fun_u64(in.cast(u64)),
                else => @compileError(std.fmt.comptimePrint("unsupported type for color conversion: {any}", .{T})),
            },
        }
    }
};

const ConversionPath = struct {
    const max_length = @typeInfo(ColorSpace).Enum.fields.len - 1;

    storage: [max_length]usize = undefined,
    length: usize = 0,

    fn get(self: *const ConversionPath) []const usize {
        return self.storage[0..self.length];
    }
};

fn SmallQueue(comptime T: type, comptime storage_size: usize) type {
    return struct {
        storage: [storage_size]T = undefined,
        write_head: usize = 0,
        elem_count: usize = 0,

        fn enqueue(self: *@This(), v: T) void {
            if (self.elem_count == storage_size) {
                std.debug.panic("failed to enqueue element, storage is full", .{});
            }

            self.storage[self.write_head % storage_size] = v;
            self.elem_count += 1;
            self.write_head += 1;
        }

        fn dequeue(self: *@This()) ?T {
            if (self.elem_count == 0) {
                return null;
            }

            const index = (self.write_head + storage_size - self.elem_count) % storage_size;
            const to_ret = self.storage[index];
            self.elem_count -= 1;

            return to_ret;
        }
    };
}

test SmallQueue {
    var queue_0: SmallQueue(i32, 4) = .{};
    queue_0.enqueue(1);
    try std.testing.expectEqual(queue_0.dequeue(), 1);
    try std.testing.expectEqual(queue_0.dequeue(), null);
    queue_0.enqueue(2);
    queue_0.enqueue(3);
    try std.testing.expectEqual(queue_0.dequeue(), 2);
    try std.testing.expectEqual(queue_0.dequeue(), 3);
    try std.testing.expectEqual(queue_0.dequeue(), null);
    queue_0.enqueue(4);
    queue_0.enqueue(5);
    queue_0.enqueue(6);
    queue_0.enqueue(7);
    try std.testing.expectEqual(queue_0.dequeue(), 4);
    try std.testing.expectEqual(queue_0.dequeue(), 5);
    try std.testing.expectEqual(queue_0.dequeue(), 6);
    try std.testing.expectEqual(queue_0.dequeue(), 7);
    try std.testing.expectEqual(queue_0.dequeue(), null);
}

fn shortest_conversion_chain(conversions: []const ColorConversion, from: ColorSpace, to: ColorSpace) ?ConversionPath {
    if (from == to) {
        return .{};
    }

    var queue: SmallQueue(ConversionPath, 64) = .{};
    queue.enqueue(.{});

    while (queue.dequeue()) |current_path| {
        const currently_at = if (current_path.length == 0) from else conversions[current_path.storage[current_path.length - 1]].to;

        for (0.., conversions) |candidate_index, candidate_conversion| {
            if (candidate_conversion.from != currently_at) {
                continue;
            }

            const next_path = val: {
                var new_path = current_path;
                new_path.length += 1;
                new_path.storage[new_path.length - 1] = candidate_index;
                break :val new_path;
            };

            if (candidate_conversion.to == to) {
                return next_path;
            }

            queue.enqueue(next_path);
        }
    }

    return null;
}

const color_conversions = [_]ColorConversion{
    .{
        .from = .sRGB,
        .to = .Linear,
        .set = .{
            .fun_f64 = struct {
                fn srgb_to_linear_floating(val: anytype) @TypeOf(val) {
                    return if (val > 0.04045) std.math.pow(@TypeOf(val), (val + 0.055) / 1.055, 2.4) else val / 12.92;
                }
                fn aufruf(in_color: Color(f64, .Any)) Color(f64, .Any) {
                    return .{
                        .r = srgb_to_linear_floating(in_color.r),
                        .g = srgb_to_linear_floating(in_color.g),
                        .b = srgb_to_linear_floating(in_color.b),
                    };
                }
            }.aufruf,
            .fun_u64 = struct {
                fn aufruf(in_color: Color(u64, .Any)) Color(u64, .Any) {
                    return in_color;
                }
            }.aufruf,
        },
    },
    .{
        .from = .Linear,
        .to = .sRGB,
        .set = .{
            .fun_f64 = struct {
                fn linear_to_srgb_floating(val: anytype) @TypeOf(val) {
                    return if (val > 0.0031308) 1.055 * std.math.pow(@TypeOf(val), val, 1.0 / 2.4) - 0.055 else 12.92 * val;
                }
                fn aufruf(in_color: Color(f64, .Any)) Color(f64, .Any) {
                    return .{
                        .r = linear_to_srgb_floating(in_color.r),
                        .g = linear_to_srgb_floating(in_color.g),
                        .b = linear_to_srgb_floating(in_color.b),
                    };
                }
            }.aufruf,
            .fun_u64 = struct {
                fn aufruf(in_color: Color(u64, .Any)) Color(u64, .Any) {
                    return in_color;
                }
            }.aufruf,
        },
    },
    .{
        .from = .Linear,
        .to = .XYZ,
        .set = .{
            .fun_f64 = struct {
                const matrix: [3][3]f64 = .{
                    .{ 0.4124, 0.3576, 0.1805 },
                    .{ 0.2126, 0.7152, 0.0722 },
                    .{ 0.0193, 0.1192, 0.9505 },
                };
                fn aufruf(in_color: Color(f64, .Any)) Color(f64, .Any) {
                    return .{
                        .r = in_color.r * matrix[0][0] + in_color.g * matrix[0][1] + in_color.b * matrix[0][2],
                        .g = in_color.r * matrix[1][0] + in_color.g * matrix[1][1] + in_color.b * matrix[1][2],
                        .b = in_color.r * matrix[2][0] + in_color.g * matrix[2][1] + in_color.b * matrix[2][2],
                    };
                }
            }.aufruf,
            .fun_u64 = struct {
                fn aufruf(in_color: Color(u64, .Any)) Color(u64, .Any) {
                    return in_color;
                }
            }.aufruf,
        },
    },
    .{
        .from = .XYZ,
        .to = .Linear,
        .set = .{
            .fun_f64 = struct {
                const matrix: [3][3]f64 = .{
                    .{ 3.2406, -1.5372, -0.4986 },
                    .{ -0.9689, 1.8758, 0.04515 },
                    .{ 0.0557, -0.2040, 1.0570 },
                };
                fn aufruf(in_color: Color(f64, .Any)) Color(f64, .Any) {
                    return .{
                        .r = in_color.r * matrix[0][0] + in_color.g * matrix[0][1] + in_color.b * matrix[0][2],
                        .g = in_color.r * matrix[1][0] + in_color.g * matrix[1][1] + in_color.b * matrix[1][2],
                        .b = in_color.r * matrix[2][0] + in_color.g * matrix[2][1] + in_color.b * matrix[2][2],
                    };
                }
            }.aufruf,
            .fun_u64 = struct {
                fn aufruf(in_color: Color(u64, .Any)) Color(u64, .Any) {
                    return in_color;
                }
            }.aufruf,
        },
    },
};

fn get_aggregate_conversion_path(comptime from: ColorSpace, comptime to: ColorSpace) ColorConversion {
    const conversion_path = comptime shortest_conversion_chain(&color_conversions, from, to) orelse unreachable;

    return .{
        .from = from,
        .to = to,

        .set = .{
            .fun_f64 = struct {
                fn aufruf(in_color: Color(f64, .Any)) Color(f64, .Any) {
                    var ret = in_color;
                    for (conversion_path.get()) |i| {
                        const conversion = color_conversions[i];

                        ret = conversion.set.fun_f64(ret);
                    }
                    return ret;
                }
            }.aufruf,
            .fun_u64 = struct {
                fn aufruf(in_color: Color(u64, .Any)) Color(u64, .Any) {
                    var ret = in_color;
                    for (conversion_path.get()) |i| {
                        const conversion = color_conversions[i];

                        ret = conversion.set.fun_u64(ret);
                    }
                    return ret;
                }
            }.aufruf,
        },
    };
}

test shortest_conversion_chain {
    try std.testing.expectEqual(shortest_conversion_chain(&color_conversions, .Linear, .Linear), ConversionPath{});
    try std.testing.expectEqual(shortest_conversion_chain(&color_conversions, .sRGB, .sRGB), ConversionPath{});
}

pub fn Color(comptime T: type, comptime space: ColorSpace) type {
    return struct {
        const ElemType = T;
        const color_space = space;

        r: T,
        g: T,
        b: T,

        pub fn space_cast(self: @This(), comptime new_space: ColorSpace) Color(T, new_space) {
            return .{ .r = self.r, .g = self.g, .b = self.b };
        }

        pub fn convert_space(self: @This(), comptime new_space: ColorSpace) Color(T, new_space) {
            const conversion_path = comptime shortest_conversion_chain(&color_conversions, space, new_space) orelse unreachable;

            var ret = self.space_cast(.Any);

            for (conversion_path.get()) |i| {
                const conversion = color_conversions[i];

                ret = conversion.convert(T, ret);
            }

            return ret.space_cast(new_space);
        }
    };
}

pub fn AnyColor(comptime T: type) type {
    return Color(T, .Any);
}

test "color conversions" {
    const diff = struct {
        fn aufruf(color_0: anytype, color_1: anytype) @TypeOf(color_0).ElemType {
            const Color0 = @TypeOf(color_0);
            const Color1 = @TypeOf(color_1);
            if (Color0.ElemType != Color1.ElemType) {
                @compileError(std.fmt.comptimePrint("expected color_0 and color_1 to have the same ElemType (they are {any}, {any} respectively)", .{ Color0.ElemType, Color1.ElemType }));
            }

            const T = Color0.ElemType;

            // magnitude + cosine
            const mag_c_0 = std.math.sqrt(color_0.r * color_0.r + color_0.g * color_0.g + color_0.b * color_0.b);
            const mag_c_1 = std.math.sqrt(color_1.r * color_1.r + color_1.g * color_1.g + color_1.b * color_1.b);

            const norm_c_0 = [_]T{
                color_0.r / mag_c_0,
                color_0.g / mag_c_0,
                color_0.b / mag_c_0,
            };

            const norm_c_1 = [_]T{
                color_1.r / mag_c_1,
                color_1.g / mag_c_1,
                color_1.b / mag_c_1,
            };

            const dot = norm_c_0[0] * norm_c_1[0] + norm_c_0[1] * norm_c_1[1] + norm_c_0[2] * norm_c_1[2];
            const mag_diff = @abs(mag_c_0 - mag_c_1);

            return @abs(1.0 - dot) + mag_diff;
        }
    }.aufruf;

    const linear_0: Color(f64, .Linear) = .{ .r = 0.1, .g = 0.2, .b = 0.3 };
    const linear_0_0 = linear_0.convert_space(.Linear);
    try std.testing.expectEqual(linear_0, linear_0_0);

    const srgb_0_0 = linear_0.convert_space(.sRGB);
    const srgb_0_0_expected: Color(f64, .sRGB) = .{ .r = 0.3491902126282938, .g = 0.48452920448170694, .b = 0.5838314900602575 };
    try std.testing.expect(diff(srgb_0_0, srgb_0_0_expected) < 0.01);

    const linear_0_1 = srgb_0_0.convert_space(.Linear);
    try std.testing.expect(diff(linear_0_1, linear_0) < 0.01);

    // TODO: test whether this works

    // const xyz_0: Color(f64, .XYZ) = .{ .r = 0, .g = 0, .b = 0 };

    // const xyz_0_0 = linear_0.convert_space(.XYZ);
    // std.log.err("xyz: {d}, {d}, {d}", .{ xyz_0_0.r, xyz_0_0.g, xyz_0_0.b });
    // try std.testing.expect(diff(xyz_0_0, xyz_0) < 0.01);

    // const xyz_0_1 = srgb_0_0.convert_space(.XYZ);
    // try std.testing.expect(diff(xyz_0_1, xyz_0) < 0.01);

    // const xyz_0_2 = linear_0_1.convert_space(.XYZ);
    // try std.testing.expect(diff(xyz_0_2, xyz_0) < 0.01);
}
