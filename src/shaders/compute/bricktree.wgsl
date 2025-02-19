{{#use_bricktrees}}

@group(2) @binding(2) var<storage, read> bricktrees: array<u32>;

{{#cache_if_possible}}
var<private> bricktree_cache: array<u32, 8>;
{{/cache_if_possible}}

fn bricktree_words() -> u32 {
    return power_sum(brickmap_depth, {{bricktree_width_log2}}u) / 8 / 4 + 1;
}

{{#bricktree_use_raster}}
fn curve_forward(level: u32, coords: vec3<u32>) -> u32 {
    // let mask = (1u << level) - 1u;

    return
       (coords[0] /*& mask*/) |
      ((coords[1] /*& mask*/) << level) |
      ((coords[2] /*& mask*/) << (level * 2));
}
{{/bricktree_use_raster}}

{{#bricktree_use_llm}}
fn curve_forward(level: u32, coords: vec3<u32>) -> u32 {
    return
      (coords[0] & 1) << 0 |
      (coords[1] & 1) << 1 |
      (coords[2] & 1) << 2 |
      (coords[0] >> 1) << (3 + (level - 1) * 0) |
      (coords[1] >> 1) << (3 + (level - 1) * 1) |
      (coords[2] >> 1) << (3 + (level - 1) * 2) |
      0;
}
{{/bricktree_use_llm}}

fn tree_check(brickmap: u32, level: u32, level_sidelength: i32, bml_voxel_coords: vec3<u32>, first_time_on_level: bool) -> bool {
    if (uniforms.debug_variable_1 == 1u) { return true; }

    let global_word_offset = brickmap * bricktree_words();

    let bit_offset = curve_forward(level, bml_voxel_coords);

{{#cache_if_possible}}
    if (first_time_on_level) {
{{/cache_if_possible}}
        // 8^1 + ... + 8^(level-1) + 24
        let level_offset = power_sum(level, 3u) - 1 + 24;

        let bit_index = bit_offset + level_offset;
        let local_word_offset = bit_index / 32;

        let sample = bricktrees[global_word_offset + local_word_offset];
{{#cache_if_possible}}
        bricktree_cache[level - 1u] = sample;
    }

    let sample = bricktree_cache[level - 1u];
{{/cache_if_possible}}

    let bit = (sample >> (bit_offset % 32)) & 1;

    return bit != 0u;
}

{{/use_bricktrees}}

