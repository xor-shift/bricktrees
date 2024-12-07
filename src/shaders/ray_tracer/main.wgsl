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
        uniforms.location,
        ray_direction,
        vec3<f32>(1) / ray_direction,
    );

    var intersection: Intersection;
    let res = u8_intersect(ray, &intersection);

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

