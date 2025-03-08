const scene_config = @import("scene_config");

pub const Config = struct {
    sc: scene_config.SceneConfig,

    Brickmap: type,
    BricktreeStorage: type,
    bricktree: type,

    bytes_per_bricktree_buffer: usize,

    pub fn from_scene_config(maybe_config: ?scene_config.SceneConfig) Config {
        const c = if (maybe_config) |v| v else scene_config.scene_config;

        const Brickmap = switch (c) {
            .brickmap => |config| @import("brickmap.zig").Brickmap(config.bml_coordinate_bits),
            .brickmap_u8_bricktree => |config| @import("brickmap.zig").Brickmap(config.base_config.bml_coordinate_bits),
            .brickmap_u64_bricktree => |config| @import("brickmap.zig").Brickmap(config.base_config.bml_coordinate_bits),
        };

        const bricktree = switch (c) {
            .brickmap => void,
            .brickmap_u8_bricktree => @import("bricktree/u8.zig"),
            .brickmap_u64_bricktree => @import("bricktree/u64.zig"),
        };

        const BricktreeStorage = switch (c) {
            .brickmap => void,
            .brickmap_u8_bricktree => [bricktree.tree_bits(Brickmap.depth) / 8]u8,
            .brickmap_u64_bricktree => [bricktree.tree_bits(Brickmap.depth) / 64]u64,
            // else => @compileError("scene type not supported"),
        };

        const bytes_per_bricktree_buffer: usize = switch (c) {
            .brickmap => undefined,
            .brickmap_u8_bricktree => bricktree.tree_bits(Brickmap.depth) / 8 + 3,
            .brickmap_u64_bricktree => bricktree.tree_bits(Brickmap.depth) / 8,
            // else => @compileError("scene type not supported"),
        };

        return .{
            .sc = c,
            .Brickmap = Brickmap,
            .bricktree = bricktree,
            .BricktreeStorage = BricktreeStorage,
            .bytes_per_bricktree_buffer = bytes_per_bricktree_buffer,
        };
    }
};

pub const ConfigArgs = union(enum) {
    pub const CurveKind = enum {
        raster,
        llm1,
        llm2,
    };

    Vanilla: struct {
        bits_per_axis: usize,
    },

    Bricktree: struct {
        bits_per_axis: usize,
        tree_node: type,
        curve_kind: CurveKind,
        manual_cache: bool,
    },
};

pub const MustacheSettings = struct {
    use_brickmaps: bool,
    brickmap_depth: usize,

    use_bricktrees: bool,
    use_u8_bricktrees: bool,
    use_u64_bricktrees: bool,
    bricktree_width_log2: usize,
    bricktree_use_raster: bool,
    bricktree_use_llm: bool,
    bricktree_cache: bool,

    no_levels: usize,

    fn from_cfg(comptime Cfg: type) MustacheSettings {
        if (!Cfg.has_tree) return .{
            .use_brickmaps = true,
            .brickmap_depth = Cfg.bits_per_axis,

            .use_bricktrees = false,
            .use_u8_bricktrees = false,
            .use_u64_bricktrees = false,
            .bricktree_width_log2 = 0,
            .bricktree_use_raster = false,
            .bricktree_use_llm = false,
            .bricktree_cache = false,

            .no_levels = 2,
        };

        return .{
            .use_brickmaps = true,
            .brickmap_depth = Cfg.bits_per_axis,

            .use_bricktrees = true,
            .use_u8_bricktrees = Cfg.BricktreeNode == u8,
            .use_u64_bricktrees = Cfg.BricktreeNode == u64,
            .bricktree_width_log2 = switch (Cfg.BricktreeNode) {
                u8 => 3,
                u64 => 6,
                else => unreachable,
            },
            .bricktree_use_raster = Cfg.curve_kind == .raster,
            .bricktree_use_llm = Cfg.curve_kind == .llm1,
            .bricktree_cache = Cfg.manual_cache,

            .no_levels = switch (Cfg.BricktreeNode) {
                u8 => Cfg.bits_per_axis + 1,
                u64 => Cfg.bits_per_axis / 2 + 1,
                else => unreachable,
            },
        };
    }
};

pub fn Config2(comptime Args: ConfigArgs) type {
    const bm = @import("brickmap.zig");

    return switch (Args) {
        .Vanilla => |v| return struct {
            pub const Brickmap = bm.Brickmap(v.bits_per_axis);
            pub const BricktreeStorage = void;
            pub const has_tree = false;

            pub const bits_per_axis: usize = v.bits_per_axis;

            pub fn to_mustache() MustacheSettings {
                return MustacheSettings.from_cfg(@This());
            }
        },
        .Bricktree => |v| return struct {
            pub const Brickmap = bm.Brickmap(v.bits_per_axis);
            pub const has_tree = true;

            pub const bricktree = switch (v.tree_node) {
                u8 => @import("bricktree/u8.zig"),
                u64 => @import("bricktree/u64.zig"),
                else => unreachable,
            };

            pub const BricktreeNode = v.tree_node;

            pub const curve_kind = v.curve_kind;
            pub const manual_cache = v.manual_cache;

            pub const BricktreeStorage = [bricktree.tree_bits(Brickmap.depth) / @bitSizeOf(BricktreeNode)]BricktreeNode;

            pub const bits_per_axis: usize = v.bits_per_axis;
            pub const bytes_per_bricktree_buffer: usize = switch (v.tree_node) {
                u8 => bricktree.tree_bits(Brickmap.depth) / 8 + 3,
                u64 => bricktree.tree_bits(Brickmap.depth) / 8,
                else => unreachable,
            };

            pub fn to_mustache() MustacheSettings {
                return MustacheSettings.from_cfg(@This());
            }
        },
    };
}
