const wgm = @import("wgm");

/// Be careful: the vecN<T> of WGSL and the [N]T of C/Zig may not have the same alignment!
pub const Uniforms = extern struct {
    random_seed: [8]u32 = .{0} ** 8,

    transform: [4][4]f32 = wgm.identity(f32, 4),
    inverse_transform: [4][4]f32 = wgm.identity(f32, 4),

    dims: [2]f32 = .{ 0, 0 },
    _padding_1: u32 = undefined,
    _padding_2: u32 = undefined,

    debug_variable_0: u32 = 0,
    debug_variable_1: u32 = 0,
    debug_mode: u32 = 0,
    debug_level: u32 = 0,

    custom: [4]u32 = undefined,
};
