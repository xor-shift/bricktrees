pub const BaseBrickmapConfig = struct {
    /// Number of bits required to represent a brickmap-local coordinate.
    /// If, for example, this value is 4, a brickmap will be 16x16x16.
    bml_coordinate_bits: usize,
};

pub const BrickmapWithBricktreeConfig = struct {
    base_config: BaseBrickmapConfig,

    // Must be between 1 and `bml_coordinate_bits - 1` inclusive.
    // Must also be ordered.
    levels_to_process: []const usize,
};

pub const SceneConfig = union(enum) {
    brickmap: BaseBrickmapConfig,
    brickmap_u8_bricktree: BrickmapWithBricktreeConfig,
    brickmap_u64_bricktree: BrickmapWithBricktreeConfig,
};

pub const scene_config: SceneConfig = .{ .brickmap_u8_bricktree = .{
    .base_config = .{ .bml_coordinate_bits = 4 },
    .levels_to_process = &.{ 1, 2 },
} };

