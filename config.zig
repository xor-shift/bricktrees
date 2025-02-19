pub const CurveKind = enum {
    raster,
    last_layer_morton,
};

pub const BaseBrickmapConfig = struct {
    /// Number of bits required to represent a brickmap-local coordinate.
    /// If, for example, this value is 4, a brickmap will be 16x16x16.
    bml_coordinate_bits: usize,
};

pub const BrickmapWithBricktreeConfig = struct {
    base_config: BaseBrickmapConfig,
    curve_kind: CurveKind,
    cache_if_possible: bool,
};

pub const SceneConfig = union(enum) {
    brickmap: BaseBrickmapConfig,
    brickmap_u8_bricktree: BrickmapWithBricktreeConfig,
    brickmap_u64_bricktree: BrickmapWithBricktreeConfig,
};

pub const scene_config: SceneConfig = .{ .brickmap_u8_bricktree = .{
    .base_config = .{ .bml_coordinate_bits = 4 },
    .curve_kind = .raster,
    .cache_if_possible = false,
} };

// pub const scene_config: SceneConfig = .{ .brickmap = .{
//     .bml_coordinate_bits = 5,
// } };

pub const MustacheSettings = struct {
    use_brickmaps: bool,
    brickmap_depth: usize,

    use_bricktrees: bool,
    bricktree_width_log2: usize,
    bricktree_use_raster: bool,
    bricktree_use_llm: bool,
    bricktree_cache: bool,

    no_levels: usize,

    pub fn from_config(config: SceneConfig) MustacheSettings {
        return switch (config) {
            .brickmap => |v| .{
                .use_brickmaps = true,
                .brickmap_depth = v.bml_coordinate_bits,

                .use_bricktrees = false,
                .bricktree_width_log2 = 0,
                .bricktree_use_raster = false,
                .bricktree_use_llm = false,
                .bricktree_cache = false,

                .no_levels = 2,
            },
            .brickmap_u8_bricktree => |v| .{
                .use_brickmaps = true,
                .brickmap_depth = v.base_config.bml_coordinate_bits,

                .use_bricktrees = true,
                .bricktree_width_log2 = 3,
                .bricktree_use_raster = v.curve_kind == .raster,
                .bricktree_use_llm = v.curve_kind == .last_layer_morton,
                .bricktree_cache = v.cache_if_possible,

                .no_levels = v.base_config.bml_coordinate_bits + 1,
            },
            .brickmap_u64_bricktree => |v| .{
                .use_brickmaps = true,
                .brickmap_depth = v.base_config.bml_coordinate_bits,

                .use_bricktrees = false,
                .bricktree_width_log2 = 6,
                .bricktree_use_raster = v.curve_kind == .raster,
                .bricktree_use_llm = v.curve_kind == .last_layer_morton,
                .bricktree_cache = v.cache_if_possible,

                .no_levels = v.base_config.bml_coordinate_bits + 1,
            },
        };
    }
};
