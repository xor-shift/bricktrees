struct Uniforms {
    dims: vec2<u32>,
    fov: f32,
    display_mode: u32,
    location: vec3<f32>,
    debug_capture_point: u32,
    transform: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@group(1) @binding(0) var texture_geo_0: texture_storage_2d<rgba32uint, write>;
@group(1) @binding(1) var texture_geo_1: texture_storage_2d<rgba32uint, write>;
@group(1) @binding(2) var texture_radiance: texture_storage_2d<rgba8unorm, write>;

@group(2) @binding(0) var chunkmap: texture_3d<u32>;
@group(2) @binding(1) var chunk_mipmaps: texture_2d<u32>;
@group(2) @binding(2) var chunks: texture_2d_array<u32>;

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
    direction_reciprocals: vec3<f32>,
};

struct Intersection {
    voxel_coords: vec3<u32>,
    local_coords: vec3<f32>,
    material: u32,
    chunkmap_iterations: u32,
    mipmap_iterations: u32,
    voxel_iterations: u32,
};

fn generate_ray_basic(pixel: vec2<u32>) -> vec3<f32> {
    let aspect = f32(uniforms.dims.x) / f32(uniforms.dims.y);
    let fov = uniforms.fov;

    let z = 69.420; // does not matter what value this has

    let ray_direction = normalize(vec3<f32>(
        tan(fov) * z * (f32(pixel.x) / f32(uniforms.dims.x) - 0.5),
        tan(fov / aspect) * z * (0.5 - f32(pixel.y) / f32(uniforms.dims.y)),
        z,
    ));

    return (uniforms.transform * vec4<f32>(ray_direction, 0)).xyz;
}

// *out_t is always clobbered
fn slab(origin: vec3<f32>, direction: vec3<f32>, min: vec3<f32>, max: vec3<f32>, out_t: ptr<function, f32>) -> bool {
    var t_min = 0.0;
    var t_max = 99999.0;

    for (var d = 0u; d < 3u; d++) {
        let t_1 = (min[d] - origin[d]) / direction[d];
        let t_2 = (max[d] - origin[d]) / direction[d];

        t_min = min(max(t_1, t_min), max(t_2, t_min));
        t_max = max(min(t_1, t_max), min(t_2, t_max));
    }

    *out_t = t_min;
    return t_min <= t_max;
}

const sentinel_chunk_id = 255u;
const chunk_sz: vec3<i32> = vec3<i32>(64);
const chunkmap_offset: vec3<i32> = vec3<i32>(-2);

/// adjusts the ray such that it is (at worst, barely) inside the chunkmap
fn prepare_ray(ray: Ray, out_ray: ptr<function, Ray>) -> bool {
    let chunkmap_sz = vec3<i32>(textureDimensions(chunkmap));

    let chunkmap_min = vec3<f32>(chunkmap_offset * chunk_sz);
    let chunkmap_max = vec3<f32>((chunkmap_offset + chunkmap_sz) * chunk_sz);

    let is_outside =
        any(ray.origin < chunkmap_min) ||
        any(ray.origin > chunkmap_max);

    if (!is_outside) {
        *out_ray = ray;
        return true;
    }

    var slab_t: f32;
    let intersected = slab(ray.origin, ray.direction, chunkmap_min, chunkmap_max, &slab_t);
    if (!intersected) {
        return false;
    }

    *out_ray = Ray(
        ray.origin + ray.direction * slab_t * 1.00001,
        ray.direction,
        ray.direction_reciprocals,
    );
    return true;
}

fn box_size_at_level(level: u32) -> i32 {
    return i32(1u << (7u - level));
}

fn get_shortest_axis(direction: vec3<f32>, box_size: vec3<f32>, bl_point: vec3<f32>, iteration_direction: vec3<i32>, out_t_delta: ptr<function, f32>) -> vec3<i32> {
    let rrbl_point = select(vec3<f32>(box_size) - bl_point, bl_point, iteration_direction == vec3<i32>(1));
    let t_delta = (vec3<f32>(box_size) - rrbl_point) / abs(direction);

    let smallest_axis = select(
        select(0, 1, t_delta.y < t_delta.x),
        select(0, 2, t_delta.z < t_delta.x),
        t_delta.z < t_delta.y
    );

    var axis_arr = array<vec3<i32>, 3>(
        vec3<i32>(1, 0, 0),
        vec3<i32>(0, 1, 0),
        vec3<i32>(0, 0, 1),
    );
    let smallest_axis_vec = axis_arr[smallest_axis];

    *out_t_delta = t_delta[smallest_axis];
    return smallest_axis_vec;
}

fn get_material(chunk_index: u32, cl_coords: vec3<i32>) -> u32 {
    return textureLoad(chunks, vec2<i32>(
        cl_coords.x + cl_coords.z * 64,
        cl_coords.y
    ), chunk_index, 0).x;
}

fn mipmap_indices(cl_voxel_coords: vec3<u32>) -> array<u32, 5> {
    var ret: array<u32, 5>;

    // short name
    let v = cl_voxel_coords;

    var mip_offset = 0u;
    for (var i = 0u; i < 5u; i++) {
        let shift = 5 - i;

        let level_x = (v.x >> shift);
        let level_y = (v.y >> shift);
        let level_z = (v.z >> shift);

        let level_offset =
            (level_z << ((i + 1) * 2)) |
            (level_y << (i + 1)) |
            level_x;

        ret[i] = mip_offset + level_offset;

        let local_mip_offset = 1u << (i * 3u + 3u);

        mip_offset += local_mip_offset;
    }

    return ret;
}

struct StackElement {
    continue_at: vec3<i32>,
    should_break_out: bool,
}

fn intersect_new(ray_arg: Ray, out_isection: ptr<function, Intersection>) -> bool {
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
        let box_size = box_size_at_level(level);
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
            var indices = mipmap_indices(vec3<u32>(box_origin) % 64);
            let mipmap_index = indices[level - 2u];

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

        let next_box_size = box_size_at_level(level + 1u);
        stack[level] = StackElement(
            cml_box_coord * box_size / next_box_size + clamp(vec3<i32>(floor(bl_point / vec3<f32>(box_size) * 2)), vec3<i32>(0), vec3<i32>(1)),
            false,
        );
        level += 1u;
    }

    return false;
}

@compute @workgroup_size(8, 8, 1) fn cs_main(
    @builtin(global_invocation_id)   global_id: vec3<u32>,
    @builtin(workgroup_id)           workgroup_id: vec3<u32>,
    @builtin(local_invocation_id)    local_id:  vec3<u32>,
    @builtin(local_invocation_index) local_idx: u32,
) {
    let pixel = global_id.xy;

    let max_dim = max(uniforms.dims.x, uniforms.dims.y);
    let v = f32(pixel.x ^ pixel.y) / f32(max_dim);

    // let proper_pixel = vec2<f32>(
    //     (f32(pixel.x) / f32(uniforms.dims.x)) * 2.0 - 1.0,
    //     (1.0 - (f32(pixel.y) / f32(uniforms.dims.y))) * 2.0 - 1.0,
    // );
    // let front_aff = uniforms.transform * vec4<f32>(proper_pixel, 0, 0);
    // let front = front_aff.xyz / front_aff.w;
    // let back_aff = uniforms.transform * vec4<f32>(proper_pixel, 1, 1);
    // let back = back_aff.xyz / back_aff.w;

    let ray_direction = generate_ray_basic(global_id.xy);
    let ray = Ray(
        uniforms.location + vec3<f32>(-1.5010898015906742, -7.1260545055360405, -518.5215667332858),
        ray_direction,
        vec3<f32>(1) / ray_direction,
    );

    var intersection: Intersection;
    let res = intersect_new(ray, &intersection);

    var color_to_write: vec3<f32>;

    let min_iter = 0u;
    let min_color = vec3<f32>(0., 1., 0.);
    let max_iter = 150u;
    let max_color = vec3<f32>(1., 0., 0.);
    let iter_sum = intersection.chunkmap_iterations + intersection.mipmap_iterations + intersection.voxel_iterations;
    let iter_param = f32(clamp(iter_sum, min_iter, max_iter) - min_iter) / f32(max_iter - min_iter);
    let iter_color = (min_color * (1. - iter_param)) + (max_color * iter_param);

    if (uniforms.debug_capture_point == 0u) {
        switch (uniforms.display_mode) {
            case 0u: { color_to_write = vec3<f32>(select(0., 1., res)); }
            case 1u: { color_to_write = intersection.local_coords; }
            case 2u: { color_to_write = vec3<f32>(intersection.voxel_coords % 64) / 64; }
            case 3u: { color_to_write = get_debug_color(intersection.material); }
            case 4u: { color_to_write = iter_color; }
            default: { color_to_write = intersection.local_coords; }
        }
    } else {
        color_to_write = intersection.local_coords;
    }

    textureStore(texture_radiance, pixel, vec4<f32>(color_to_write, 1.));
}

