@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@group(1) @binding(0) var texture_radiance: texture_storage_2d<bgra8unorm, write>;

@compute @workgroup_size(8, 8, 1) fn cs_main(
    @builtin(global_invocation_id)   global_id: vec3<u32>,
    @builtin(workgroup_id)           workgroup_id: vec3<u32>,
    @builtin(local_invocation_id)    local_id:  vec3<u32>,
    @builtin(local_invocation_index) local_idx: u32,
) {
    let pixel = global_id.xy;

    let ray = generate_ray(pixel);
    var intersection: Intersection;
    let intersected = trace(ray, &intersection);

    // debug_vec(0u, 0u, intersection.local_coords);
    // debug_bool(0u, 0u, intersected);
    debug_vec(1u, 0u, vec3<f32>(intersection.distance / 5, 0, 0));

    debug_jet(2u, 0u, f32(pixel.x) / uniforms.dims[0]);

    debug_vec(3u, 0u, ray.origin / 32);
    debug_vec(4u, 0u, ray.direction);
    debug_vec(5u, 0u, vec3<f32>(ray.iter_direction + vec3<i32>(1)) / 2);

    if (did_debug) {
        textureStore(texture_radiance, pixel, vec4<f32>(debug_out, 1));
    } else if (intersected) {
        let n = intersection_normal(intersection);
        let c = -dot(n, ray.direction);
        textureStore(texture_radiance, pixel, vec4<f32>(abs(n) * c, 1));
    } else {
        textureStore(texture_radiance, pixel, vec4<f32>(0, 0, 0, 1));
    }
}

