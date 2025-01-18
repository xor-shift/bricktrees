pub const Voxel = union(enum) {
    Air: struct {}, // -8 -8 -8 00------

    /// All fields are unorms.
    Normal: struct {
        roughness: u6,

        r: u8,
        g: u8,
        b: u8,
    }, // R8 G8 B8 rrrrrr01

    /// Incident light gets reflected as though this voxel is a normal one with max. roughness and white albedo.
    /// `r`, `g`, and `b` are unorms, multiplier is a uint.
    Emissive: struct {
        multiplier: u6,

        r: u8,
        g: u8,
        b: u8,
    }, // R8 G8 B8 10mmmmmm

    /// `r`, `g`, and `b` are unorms.a
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
    Transparent: struct {
        ior: u6,

        r: u8,
        g: u8,
        b: u8,

        pub fn pack_ior(ior: f64) u6 {
            const v = @min(@max(ior, 1.0), 3.25);

            const unrounded = if (v)
                (v - 1.0) * 48.0
            else
                (v - 2.0) * 12.0 + 48.0;

            const ret: u6 = @intFromFloat(@round(unrounded));

            return ret;
        }

        pub fn unpack_ior(ior: u6) f64 {
            const v: f64 = @floatFromInt(ior);

            return if (v < 48.0)
                v / 48.0 + 1.0
            else
                (v - 48.0) / 12.0 + 2.0;
        }
    }, // R8 G8 B8 11iiiiii

    pub fn unpack(packed_voxel: PackedVoxel) Voxel {
        _ = packed_voxel;
        return undefined;
    }

    pub fn pack(voxel: Voxel) PackedVoxel {
        _ = voxel;
        return undefined;
    }
};

pub const PackedVoxel = packed struct {
    r: u8,
    g: u8,
    b: u8,

    i: u8,
};
