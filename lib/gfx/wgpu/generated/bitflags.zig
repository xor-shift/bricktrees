pub const ShaderStage = packed struct(u32) {
    vertex: bool = false,
    fragment: bool = false,
    compute: bool = false,
    _padding: u29 = 0,
};

pub const ColorWriteMask = packed struct(u32) {
    red: bool = false,
    green: bool = false,
    blue: bool = false,
    alpha: bool = false,
    all: bool = false,
    _padding: u27 = 0,
};

pub const MapMode = packed struct(u32) {
    read: bool = false,
    write: bool = false,
    _padding: u30 = 0,
};

pub const BufferUsage = packed struct(u32) {
    map_read: bool = false,
    map_write: bool = false,
    copy_src: bool = false,
    copy_dst: bool = false,
    index: bool = false,
    vertex: bool = false,
    uniform: bool = false,
    storage: bool = false,
    indirect: bool = false,
    query_resolve: bool = false,
    _padding: u22 = 0,
};

pub const TextureUsage = packed struct(u32) {
    copy_src: bool = false,
    copy_dst: bool = false,
    texture_binding: bool = false,
    storage_binding: bool = false,
    render_attachment: bool = false,
    _padding: u27 = 0,
};
