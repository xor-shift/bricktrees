@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@group(1) @binding(0) var texture_radiance: texture_storage_2d<bgra8unorm, write>;

fn quasi_ao(p: vec3<f32>, n: vec3<f32>) -> f32 {
    let sq3 = 0.577350269;
    let sq2 = 0.707106781;
    /*var directions = array<vec3<f32>, 8>(
        vec3<f32>(sq3, sq3, sq3),
        vec3<f32>(0, sq2, sq2),
        vec3<f32>(-sq3, sq3, sq3),
        vec3<f32>(-sq2, 0, sq2),
        vec3<f32>(-sq3, -sq3, sq3),
        vec3<f32>(0, -sq2, sq2),
        vec3<f32>(sq3, -sq3, sq3),
        vec3<f32>(sq2, 0, sq2),
    );*/

    let tan26 = 0.4877325885658614;
    let sec26 = 1.1126019404751888;
    var directions = array<vec2<f32>, 8>(
        vec2<f32>(0, 1),
        vec2<f32>(1, 1 - tan26),
        vec2<f32>(sec26 * 0.5, -1),
        vec2<f32>(-sec26 * 0.5),
        vec2<f32>(-1, 1 - tan26),

        vec2<f32>(1, 1) / 3,
        vec2<f32>(-1, 0) / 3,
        vec2<f32>(0, -1) / 3,
    );

    let biggest_axis = select(
        select(2, 1, abs(n).z < abs(n).y),
        select(2, 0, abs(n).z < abs(n).x),
        abs(n).y < abs(n).x,
    );

    var occlusion = 0u;
    for (var i = 0u; i < 8u; i++) {
        let direction_base = normalize(vec3<f32>(directions[i], 1));

        let direction_rot = vec3<f32>(
            select(direction_base.x, direction_base.z, biggest_axis == 0),
            select(direction_base.y, direction_base.z, biggest_axis == 1),
            direction_base[biggest_axis],
        );

        let direction = select(
            direction_rot,
            -direction_rot,
            n[biggest_axis] < 0,
        );

        occlusion += hit_check_coarse(p, direction, 16u, 0.65);
        //occlusion += dot(direction, n);
    }

    return f32(occlusion) / (16 * 8);
}

fn stochastic_ao(p: vec3<f32>, n: vec3<f32>, ray_ct: u32) -> f32 {
    var occlusion: u32 = 0;
    for (var i = 0u; i < ray_ct; i++) {
        let direction_base = next_unit_vector();
        let direction = select(
            direction_base,
            -direction_base,
            dot(direction_base, n) < 0,
        );
        occlusion += hit_check_coarse(p, direction, 16u, 0.65);
    }

    return f32(occlusion) / f32(16u * ray_ct);
}

@compute @workgroup_size(8, 8, 1) fn cs_main(
    @builtin(global_invocation_id)   global_id: vec3<u32>,
    @builtin(workgroup_id)           workgroup_id: vec3<u32>,
    @builtin(local_invocation_id)    local_id:  vec3<u32>,
    @builtin(local_invocation_index) local_idx: u32,
) {
    let pixel = global_id.xy;
    init_random(pixel);

    if (false) {
        textureStore(texture_radiance, pixel, vec4<f32>(0.1, 0.2, 0.3, 1));
        return;
    }

    let ray = generate_ray(pixel);
    var intersection: Intersection;
    let intersected = trace(ray, &intersection);

    // debug_vec(0u, 0u, intersection.local_coords);
    // debug_bool(0u, 0u, intersected);
    debug_vec(1u, 0u, vec3<f32>(intersection.distance / 5, 0, 0));

    debug_jet(2u, 0u, f32(pixel.x) / uniforms.dims[0]);

    let stat_div = vec3<f32>(64, 192, 96);
    let stats = vec3<f32>(vec3<u32>(
        intersection.stats.brickgrid_iterations,
        intersection.stats.bricktree_iterations,
        intersection.stats.voxel_iterations,
    ));
    let ds = stats / stat_div;

    debug_vec(3u, 0u, ray.origin / 32);
    debug_vec(4u, 0u, ray.direction);
    debug_vec(5u, 0u, vec3<f32>(ray.iter_direction + vec3<i32>(1)) / 2);
    debug_jet(6u, 0u, ds.x);
    debug_jet(7u, 0u, ds.y);
    debug_jet(8u, 0u, ds.z);
    debug_jet(9u, 0u, (ds.x + ds.y + ds.z) / 3);

    if (did_debug) {
        textureStore(texture_radiance, pixel, vec4<f32>(debug_out, 1));
        return;
    }

    if (!intersected) {
        textureStore(texture_radiance, pixel, vec4<f32>(0, 0, 0, 1));
        return;
    }

    let mat_color = unpack4x8unorm(intersection.material).rgb;
    let n = intersection_normal(intersection);
    let c = -dot(n, ray.direction);
    let p = vec3<f32>(intersection.voxel_coords) + intersection.local_coords + n * 0.01;

    //let mult = quasi_ao(p, n);
    let mult = stochastic_ao(p, n, 5u);

    textureStore(texture_radiance, pixel, vec4<f32>(mat_color * mult, 1));
    // textureStore(texture_radiance, pixel, vec4<f32>(-n, 1));
}

