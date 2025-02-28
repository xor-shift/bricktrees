struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
    direction_reciprocals: vec3<f32>,
    iter_direction: vec3<i32>,
};

struct Statistics {
    brickgrid_iterations: u32,
    bricktree_iterations: u32,
    voxel_iterations: u32,
}

struct Intersection {
    /// Coordinate of the voxel relative to the brickgrid origin
    voxel_coords: vec3<i32>,

    /// Coordinate of the intersection relative to the voxel intersected.
    /// No axis should ever exceed 1 or go below 0.
    local_coords: vec3<f32>,

    distance: f32,

    material: u32,

    stats: Statistics,
};

fn intersection_normal(intersection: Intersection) -> vec3<f32> {
    let lp = intersection.local_coords * 2.001 - 1.0005;
    let alp = abs(lp);

    let m = max(max(alp.x, alp.y), alp.z);
    let an = step(vec3<f32>(m - 0.0001), alp);

    return an * sign(lp);
}

fn generate_ray_transform(pixel: vec2<u32>) -> Ray {
    let inv = uniforms.inverse_transform;

    // TODO: send these 8 vectors through the uniforms

    let near_z = 0.;
    let far_z = 1.;

    let near_arr_h = array<vec4<f32>, 4>(
        inv * vec4<f32>(-1, 1, near_z, 1),
        inv * vec4<f32>(1, 1, near_z, 1),
        inv * vec4<f32>(-1, -1, near_z, 1),
        inv * vec4<f32>(1, -1, near_z, 1),
    );

    let far_arr_h = array<vec4<f32>, 4>(
        inv * vec4<f32>(-1, 1, far_z, 1),
        inv * vec4<f32>(1, 1, far_z, 1),
        inv * vec4<f32>(-1, -1, far_z, 1),
        inv * vec4<f32>(1, -1, far_z, 1),
    );

    let uv = vec2<f32>(pixel) / uniforms.dims;

    let use_bilinear = true;

    var near_h: vec4<f32>;
    var far_h: vec4<f32>;

    if (use_bilinear) {
        let interp_type = 0u;

        switch (interp_type) {
        case 0u: {
            near_h = mix(
                mix(near_arr_h[0], near_arr_h[1], uv.x),
                mix(near_arr_h[2], near_arr_h[3], uv.x),
                uv.y,
            );

            far_h = mix(
                mix(far_arr_h[0], far_arr_h[1], uv.x),
                mix(far_arr_h[2], far_arr_h[3], uv.x),
                uv.y,
            );
        }
        case 1u: {
            let near_h_t = near_arr_h[0] * (1 - uv.x) + near_arr_h[1] * uv.x;
            let near_h_b = near_arr_h[2] * (1 - uv.x) + near_arr_h[3] * uv.x;
            near_h = near_h_t * (1 - uv.y) + near_h_b * uv.y;

            let far_h_t = far_arr_h[0] * (1 - uv.x) + far_arr_h[1] * uv.x;
            let far_h_b = far_arr_h[2] * (1 - uv.x) + far_arr_h[3] * uv.x;
            far_h = far_h_t * (1 - uv.y) + far_h_b * uv.y;
        }
        case 2u: {
            let uvx = vec2<f32>(1 - uv.x, uv.x);
            let uvy = vec2<f32>(1 - uv.y, uv.y);

            let near_t_mat = mat2x4<f32>(near_arr_h[0], near_arr_h[1]);
            let near_b_mat = mat2x4<f32>(near_arr_h[2], near_arr_h[3]);
            let near_h_mat = mat2x4<f32>(near_t_mat * uvx, near_b_mat * uvx);
            near_h = near_h_mat * uvy;

            let far_t_mat = mat2x4<f32>(far_arr_h[0], far_arr_h[1]);
            let far_b_mat = mat2x4<f32>(far_arr_h[2], far_arr_h[3]);
            let far_h_mat = mat2x4<f32>(far_t_mat * uvx, far_b_mat * uvx);
            far_h = far_h_mat * uvy;
        }
        default: {}
        }
    } else {
        let pos = vec2<f32>(uv.x * 2 - 1, 1 - uv.y * 2);

        near_h = inv * vec4<f32>(pos, near_z, 1);
        far_h = inv * vec4<f32>(pos, far_z, 1);
    }

    let near = near_h.xyz / near_h.w;
    let far = far_h.xyz / far_h.w;

    let origin = near;
    let direction = normalize(far - near);

    return Ray(origin, direction, vec3<f32>(), vec3<i32>());
}

fn generate_ray(pixel: vec2<u32>) -> Ray {
    var ray = generate_ray_transform(pixel);

    ray.iter_direction = vec3<i32>(select(
        vec3<i32>(-1), vec3<i32>(1),
        ray.direction >= vec3<f32>(0),
    ));

    ray.direction_reciprocals = 1 / ray.direction;

    return ray;
}

/// *out_t is always clobbered
fn slab(origin: vec3<f32>, direction_reciprocals: vec3<f32>, min: vec3<f32>, max: vec3<f32>, out_t: ptr<function, f32>) -> bool {
    var t_min = 0.0;
    var t_max = 99999.0;

    for (var d = 0u; d < 3u; d++) {
        let t_1 = (min[d] - origin[d]) * direction_reciprocals[d];
        let t_2 = (max[d] - origin[d]) * direction_reciprocals[d];

        t_min = min(max(t_1, t_min), max(t_2, t_min));
        t_max = max(min(t_1, t_max), min(t_2, t_max));
    }

    *out_t = t_min;
    return t_min <= t_max;
}

