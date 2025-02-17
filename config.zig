pub const BaseBrickmapConfig = struct {
    /// Number of bits required to represent a brickmap-local coordinate.
    /// If, for example, this value is 4, a brickmap will be 16x16x16.
    bml_coordinate_bits: usize,
};

pub const BrickmapWithBricktreeConfig = struct {
    base_config: BaseBrickmapConfig,
};

pub const SceneConfig = union(enum) {
    brickmap: BaseBrickmapConfig,
    brickmap_u8_bricktree: BrickmapWithBricktreeConfig,
    brickmap_u64_bricktree: BrickmapWithBricktreeConfig,
};

pub const scene_config: SceneConfig = .{ .brickmap_u8_bricktree = .{
    .base_config = .{ .bml_coordinate_bits = 3 },
} };

pub const MustacheSettings = struct {
    use_brickmaps: bool,
    use_bricktrees: bool,
    brickmap_depth: usize,
    bricktree_width_log2: usize,

    no_levels: usize,

    pub fn from_config(config: SceneConfig) MustacheSettings {
        return switch (config) {
            .brickmap => |v| .{
                .use_brickmaps = true,
                .use_bricktrees = false,
                .brickmap_depth = v.bml_coordinate_bits,
                .bricktree_width_log2 = 0,
                .no_levels = 2,
            },
            .brickmap_u8_bricktree => |v| .{
                .use_brickmaps = true,
                .use_bricktrees = false,
                .brickmap_depth = v.base_config.bml_coordinate_bits,
                .bricktree_width_log2 = 3,
                .no_levels = v.base_config.bml_coordinate_bits + 1,
            },
            .brickmap_u64_bricktree => |v| .{
                .use_brickmaps = true,
                .use_bricktrees = true,
                .brickmap_depth = v.base_config.bml_coordinate_bits,
                .bricktree_width_log2 = 6,
                .no_levels = v.base_config.bml_coordinate_bits + 1,
            },
        };
    }
};
