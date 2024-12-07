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
        cl_coords.x + cl_coords.y * 64,
        cl_coords.z
    ), chunk_index, 0).x;
}

