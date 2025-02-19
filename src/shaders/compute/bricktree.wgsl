{{#use_bricktrees}}

@group(2) @binding(2) var<storage, read> bricktrees: array<u32>;

const bricktree_level_depth = {{bricktree_width_log2}}u / 3u;

fn bricktree_words() -> u32 {
    if ({{bricktree_width_log2}}u == 3u) {
        return power_sum(brickmap_depth, {{bricktree_width_log2}}u) / 8 / 4 + 1;
    } else if ({{bricktree_width_log2}}u == 6u) {
        return power_sum(brickmap_depth / bricktree_level_depth, {{bricktree_width_log2}}u) / 32;
    } else {
        return 0u;
    }
}

{{#bricktree_use_raster}}
fn curve_forward(level: u32, coords: vec3<u32>) -> u32 {
    // let mask = (1u << level) - 1u;

    return
       (coords[0] /*& mask*/) |
      ((coords[1] /*& mask*/) << (level * bricktree_level_depth)) |
      ((coords[2] /*& mask*/) << (level * bricktree_level_depth * 2));
}
{{/bricktree_use_raster}}

{{#bricktree_use_llm}}
fn curve_forward(level: u32, coords: vec3<u32>) -> u32 {
    return
      (coords[0] & 1) << 0 |
      (coords[1] & 1) << 1 |
      (coords[2] & 1) << 2 |
      (coords[0] >> 1) << (3 + (level * bricktree_level_depth - 1) * 0) |
      (coords[1] >> 1) << (3 + (level * bricktree_level_depth - 1) * 1) |
      (coords[2] >> 1) << (3 + (level * bricktree_level_depth - 1) * 2);
}
{{/bricktree_use_llm}}


{{#bricktree_cache}}
{{#use_u8_bricktrees}}
var<private> bricktree_cache: array<u32, {{no_levels}}>;
{{/use_u8_bricktrees}}
{{#use_u64_bricktrees}}
var<private> bricktree_cache: array<array<u32, 2>, 8>;
{{/use_u64_bricktrees}}
{{/bricktree_cache}}

fn tree_check(
    brickmap: u32,
    level: u32,
    bml_voxel_coords: vec3<u32>,
    first_time_on_level: bool
) -> bool {
    if (uniforms.debug_variable_1 == 1u) { return true; }

    let ll_bo = curve_forward(level, bml_voxel_coords);

{{#bricktree_cache}}
    if (first_time_on_level) {
{{/bricktree_cache}}
/*
   |   btl_level_bo 1 (24 + n)
   |   | btl_level_bo 2 (24 + n + 8)
   |---| |         btl_level_bo 3 (24 + n + 76)
   |   | |         |
   |   v v         v
... XXX0 1111 1111 2222 2222 222 ...
  ^   |  \
  |   |    \
  |   |      \
  |   01234567 -> [(0, 0, 0), (1, 0, 0), (0, 1, 0), ...]
  |
  n bits before (g_bt_wo * 4)
*/
        let g_bt_bo = (brickmap * bricktree_words()) * 32;

        let btl_level_bo_offset = select(0u, 24u, {{bricktree_width_log2}} == 3);
        let btl_level_bo = power_sum(level, {{bricktree_width_log2}}u) - 1 + btl_level_bo_offset;

        let g_bo = g_bt_bo + btl_level_bo + ll_bo;

        let sample = bricktrees[g_bo / 32];
{{#bricktree_cache}}
        bricktree_cache[level - 1u] = sample;
    }
    let sample = bricktree_cache[level - 1u];
{{/bricktree_cache}}

    return ((sample >> (ll_bo % 32)) & 1u) != 0u;
}

{{/use_bricktrees}}

