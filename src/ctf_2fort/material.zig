pub const Material = packed union {
    raw: u32,

    diffuse: packed struct {
        _reserved: u8,
        r: u8,
        g: u8,
        b: u8,
    },

    mirror: packed struct {
        _reserved: u8,
        r: u8,
        g: u8,
        b: u8,
    },
};
