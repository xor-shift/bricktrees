{{#use_bricktrees}}

@group(2) @binding(2) var<storage, read> bricktrees: array<u32>;

fn tree_check(brickmap: u32, level: u32, level_sidelength: i32, bml_voxel_coords: vec3<u32>) -> bool {
    if (uniforms.debug_variable_1 == 1u) { return true; }

    let global_word_offset = brickmap * bricktree_words();

    if (level == 1u) {
        // where's my boy Morton when i need him

        let sample = bricktrees[global_word_offset + bml_voxel_coords.z];

        let shift = bml_voxel_coords.y * 4 + bml_voxel_coords.x * 2;
        let sm = (sample >> shift) & 0x00330033;

        return sm != 0u;
    }

    let mask = (1u << level) - 1u;
    let bit_offset =
       (bml_voxel_coords[0] & mask) |
      ((bml_voxel_coords[1] & mask) << level) |
      ((bml_voxel_coords[2] & mask) << (level * 2));

    // 8^2 + ... + 8^(level-1)
    let level_offset = power_sum(level, 3u) - 9;

    let bit_index = bit_offset + level_offset;
    let local_word_offset = bit_index / 32;

    let sample = bricktrees[global_word_offset + local_word_offset];
    let bit = (sample >> (bit_index % 32)) & 1;

    return bit != 0u;
}

{{/use_bricktrees}}

