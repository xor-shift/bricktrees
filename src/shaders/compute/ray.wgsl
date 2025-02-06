struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
    direction_reciprocals: vec3<f32>,
};

struct Intersection {
    voxel_coords: vec3<u32>,
    local_coords: vec3<f32>,
    material: u32,
    brickgrid_iterations: u32,
    bricktree_iterations: u32,
    brickmap_iterations: u32,
};

fn generate_ray(pixel: vec2<u32>) -> Ray {
    let inv = uniforms.inverse_transform;

    // TODO: send these 8 vectors through the uniforms

    let near_arr_h = array<vec4<f32>, 4>(
        inv * vec4<f32>(-1, 1, 0, 1),
        inv * vec4<f32>(1, 1, 0, 1),
        inv * vec4<f32>(-1, -1, 0, 1),
        inv * vec4<f32>(1, -1, 0, 1),
    );

    let far_arr_h = array<vec4<f32>, 4>(
        inv * vec4<f32>(-1, 1, 1, 1),
        inv * vec4<f32>(1, 1, 1, 1),
        inv * vec4<f32>(-1, -1, 1, 1),
        inv * vec4<f32>(1, -1, 1, 1),
    );

    let uv = vec2<f32>(pixel) / uniforms.dims;

    // bilinear gaming

    let near_h_t = near_arr_h[0] * (1 - uv.x) + near_arr_h[1] * uv.x;
    let near_h_b = near_arr_h[2] * (1 - uv.x) + near_arr_h[3] * uv.x;
    let near_h = near_h_t * (1 - uv.y) + near_h_b * uv.y;

    let far_h_t = far_arr_h[0] * (1 - uv.x) + far_arr_h[1] * uv.x;
    let far_h_b = far_arr_h[2] * (1 - uv.x) + far_arr_h[3] * uv.x;
    let far_h = far_h_t * (1 - uv.y) + far_h_b * uv.y;

    // let pos = vec2<f32>(uv.x * 2 - 1, 1 - uv.y * 2);

    // let near_h = inv * vec4<f32>(pos, 0, 1);
    // let far_h = inv * vec4<f32>(pos, 1, 1);

    let near = near_h.xyz / near_h.w;
    let far = far_h.xyz / far_h.w;

    let origin = near;
    let direction = normalize(far - near);

    return Ray(origin, direction, 1 / direction);
}

/// *out_t is always clobbered
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

