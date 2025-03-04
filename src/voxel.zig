const wgm = @import("wgm");

fn pack_ior(ior: f64) u6 {
    const v = @min(@max(ior, 1.0), 3.25);

    const unrounded = if (v)
        (v - 1.0) * 48.0
    else
        (v - 2.0) * 12.0 + 48.0;

    const ret: u6 = @intFromFloat(@round(unrounded));

    return ret;
}

fn unpack_ior(ior: u6) f64 {
    const v: f64 = @floatFromInt(ior);

    return if (v < 48.0)
        v / 48.0 + 1.0
    else
        (v - 48.0) / 12.0 + 2.0;
}

pub const Voxel = union(enum) {
    Air: struct {},

    Normal: struct {
        rgb: [3]f64,
        rougness: f64,
    },

    Emissive: struct {
        rgb: [3]f64,
    },

    Transparent: struct {
        absorption: [3]f64,
        ior: f64,
    },

    pub fn pack(self: Voxel) PackedVoxel {
        return switch (self) {
            .Air => .{ .r = 0, .g = 0, .b = 0, .i = 0 },
            .Normal => |v| .{
                .r = @intFromFloat(@trunc(@max(@min(v.rgb[0] * 255, 255), 0))),
                .g = @intFromFloat(@trunc(@max(@min(v.rgb[1] * 255, 255), 0))),
                .b = @intFromFloat(@trunc(@max(@min(v.rgb[2] * 255, 255), 0))),
                .i = @intFromFloat(@trunc(@max(@min(v.rougness * 63, 63), 0))),
            },
            .Emissive => |v| blk: {
                const length = wgm.length(v.rgb);
                const norm = wgm.div(v.rgb, length);
                break :blk .{
                    .r = @intFromFloat(@trunc(@max(@min(norm[0] * 255, 255), 0))),
                    .g = @intFromFloat(@trunc(@max(@min(norm[1] * 255, 255), 0))),
                    .b = @intFromFloat(@trunc(@max(@min(norm[2] * 255, 255), 0))),
                    .i = @intFromFloat(@trunc(@max(@min(length, 0), 63))),
                };
            },
            .Transparent => undefined,
        };
    }
};

/// I        type             description
/// 00iiiiii transparent      `i` is the IOR (see note 1). RGB is the absorption.
/// 01mmmmmm emissive         `m` is the multiplier. RGB denotes the base color.
/// 10------ reserved
/// 11rrrrrr diffuse/metallic `r` is the roughness.
///
/// Note 1:
///
/// `ior` is a unorm biased by 1, divided by 2.375.
///
/// JS functions for packing and unpacking `ior`:
///
///  0 1.0
/// 31 2.0
/// 63 3.375
///
/// ```js
/// let pack = v => Math.round(
///     (v < 2)
///         ? (v - 1) * 48
///         : (v - 2) * 12 + 48
/// )
///
/// let unpack = v => (
///     (v < 48)
///         ? v / 48 + 1
///         : (v - 48) / 12 + 2
/// )
/// ```
pub const PackedVoxel = packed struct {
    pub const air: PackedVoxel = .{ .r = 0, .g = 0, .b = 0, .i = 0 };
    pub const white: PackedVoxel = .{ .r = 255, .g = 255, .b = 255, .i = 255 };

    r: u8,
    g: u8,
    b: u8,

    i: u8,

    pub fn unpack(self: PackedVoxel) Voxel {
        _ = self;
        return undefined;
    }
};
