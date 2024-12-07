fn u8_box_size_at_level(level: u32) -> i32 {
    return i32(1u << (7u - level));
}

fn u8_mipmap_indices(cl_voxel_coords: vec3<u32>) -> array<u32, 5> {
    var ret: array<u32, 5>;

    // short name
    let v = cl_voxel_coords;

    var mip_offset = 0u;
    for (var i = 0u; i < 5u; i++) {
        let level_x = (v.x >> (i + 1));
        let level_y = (v.y >> (i + 1));
        let level_z = (v.z >> (i + 1));

        let bpa = 5u - i;
        let level_offset =
            (level_z << (bpa * 2)) |
            (level_y << bpa) |
            level_x;

        ret[i] = mip_offset + level_offset;

        let level_size = 1u << (3u * bpa);
        mip_offset += level_size;
    }

    return ret;
}

struct StackElement {
    continue_at: vec3<i32>,
    should_break_out: bool,
}

fn u8_intersect(ray_arg: Ray, out_isection: ptr<function, Intersection>) -> bool {
    let chunkmap_sz = vec3<i32>(textureDimensions(chunkmap));

    (*out_isection).chunkmap_iterations = 0u;
    (*out_isection).mipmap_iterations = 0u;
    (*out_isection).voxel_iterations = 0u;

    var ray: Ray;
    if (!prepare_ray(ray_arg, &ray)) {
        if (do_debug) { debug_bool(5u, true, 0u, out_isection); }
        return false;
    }

    let iteration_direction = vec3<i32>(select(
        vec3<i32>(-1), vec3<i32>(1),
        ray.direction >= vec3<f32>(0),
    ));
    if (do_debug) {
        if (debug_vec(6u, vec3<f32>(iteration_direction + vec3<i32>(1)) / 2, 0u, out_isection)) { return false; }
    }

    var cml_point = ray.origin - vec3<f32>(chunk_sz * chunkmap_offset);
    var chunk_index: u32;

    var stack = array<StackElement, 7> (
        StackElement(vec3<i32>(floor(cml_point / vec3<f32>(chunk_sz))), false), // chunk
        StackElement(vec3<i32>(0), false), // 32**3
        StackElement(vec3<i32>(0), false), // 16**3
        StackElement(vec3<i32>(0), false), // 8**3
        StackElement(vec3<i32>(0), false), // 4**3
        StackElement(vec3<i32>(0), false), // 2**3
        StackElement(vec3<i32>(0), false), // voxel
    );

    var level = 1u;
    var iter = 0u;
    while (level != 0u) {
        iter += 1u;
        //if (iter == 255u) { return false; }

        if (level == 1u)      { (*out_isection).chunkmap_iterations += 1u; }
        else if (level == 7u) { (*out_isection).mipmap_iterations += 1u;   }
        else                  { (*out_isection).voxel_iterations += 1u;    }

        let frame = stack[level - 1u];

        if (frame.should_break_out) { level -= 1u; continue; }

        let cml_box_coord = frame.continue_at;
        let box_size = u8_box_size_at_level(level);
        let box_origin = cml_box_coord * box_size;
        let bl_point = cml_point - vec3<f32>(box_origin);
        var t_delta: f32;
        let shortest_axis = get_shortest_axis(ray.direction, vec3<f32>(box_size), bl_point, iteration_direction, &t_delta);
        let next_cml_box_coord = iteration_direction * shortest_axis + cml_box_coord;
        let next_cml_point = cml_point + t_delta * ray.direction * 1.00001;
        var should_break_out: bool; if (level == 1u) {
            should_break_out = any(next_cml_box_coord < vec3<i32>(0)) || any(next_cml_box_coord >= chunkmap_sz);
        } else {
            let cur_even = (cml_box_coord % 2) == vec3<i32>(0);
            let next_even = (next_cml_box_coord % 2) == vec3<i32>(0);
            let comparison_typ = iteration_direction == vec3<i32>(1);
            let regular_result = !cur_even && next_even;
            let inverted_result = cur_even && !next_even;
            let final_result = comparison_typ && regular_result || !comparison_typ && inverted_result;
            should_break_out = any(final_result);
        }

        if (do_debug) {
            if (debug_vec(1u, cml_point / 64., iter, out_isection)) { return false; }
            if (debug_vec(2u, vec3<f32>(cml_box_coord) / 8., iter, out_isection)) { return false; }
            if (debug_vec(3u, vec3<f32>(box_origin) / 256., iter, out_isection)) { return false; }
            if (debug_vec(4u, vec3<f32>(bl_point) / f32(box_size), iter, out_isection)) { return false; }
            if (debug_u32(5u, chunk_index, iter, out_isection)) { return false; }
            if (debug_vec(6u, vec3<f32>(shortest_axis), iter, out_isection)) { return false; }
            if (debug_bool(7u, should_break_out, iter, out_isection)) { return false; }
            if (debug_vec(8u, next_cml_point / 64., iter, out_isection)) { return false; }
            if (debug_vec(9u, vec3<f32>(next_cml_box_coord) / 8., iter, out_isection)) { return false; }
        }

        var recurse: bool; if (level == 1u) {
            chunk_index = textureLoad(chunkmap, cml_box_coord, 0).x;
            recurse = chunk_index != sentinel_chunk_id;
        } else if (level == 7u) {
            recurse = false;
            let material = get_material(chunk_index, cml_box_coord % 64);
            if (material != 0u) {
                (*out_isection).voxel_coords = vec3<u32>(cml_box_coord);
                (*out_isection).local_coords = bl_point;
                (*out_isection).material = material;
                return true;
            }
        } else {
            var indices = u8_mipmap_indices(vec3<u32>(box_origin) % 64);
            let mipmap_index = indices[4u - (level - 2u)];

            let mip_byte = textureLoad(chunk_mipmaps, vec2<u32>(
                mipmap_index / 8u, chunk_index,
            ), 0).x;

            if (do_debug && debug_bool(9u, (mipmap_index / 8u) == 1u, iter, out_isection)) { return false; }

            let mip_valid = ((mip_byte >> (mipmap_index % 8u)) & 1u) != 0u;
            //let mip_valid = mip_byte != 0u;

            if (do_debug && debug_bool(10u, mip_valid, iter, out_isection)) { return false; }

            recurse = mip_valid;
        }

        stack[level - 1u] = StackElement(next_cml_box_coord, should_break_out);

        if (do_debug) {
            if (debug_bool(15u, recurse, iter, out_isection)) { return false; }
        }

        if (!recurse) {
            cml_point = next_cml_point;
            if (should_break_out) {
                level -= 1u;
            }
            continue;
        }

        let next_box_size = u8_box_size_at_level(level + 1u);
        stack[level] = StackElement(
            cml_box_coord * box_size / next_box_size + clamp(vec3<i32>(floor(bl_point / vec3<f32>(box_size) * 2)), vec3<i32>(0), vec3<i32>(1)),
            false,
        );
        level += 1u;
    }

    return false;
}

