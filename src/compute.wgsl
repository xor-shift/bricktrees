struct Uniforms {
    dims: vec2<u32>,
    fov: f32,
    _padding_0: u32,
    location: vec3<f32>,
    _padding_1: f32,
    transform: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(1) @binding(0) var texture_geo_0: texture_storage_2d<rgba32uint, write>;
@group(1) @binding(1) var texture_geo_1: texture_storage_2d<rgba32uint, write>;
@group(1) @binding(2) var texture_radiance: texture_storage_2d<rgba8unorm, write>;
//@group(2) @binding(0) var texture_map: texture_3d<u32>;
@group(2) @binding(0) var texture_map: texture_2d_array<u32>;
@group(2) @binding(1) var chunk_mapping: texture_3d<u32>;

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
    direction_reciprocal: vec3<f32>,
};

struct Intersection {
    voxel_coords: vec3<u32>,
    local_coords: vec3<f32>,
    distance: f32,
};

struct StatsAndDebug {
    gridmap_iterations: u32,
    total_chunk_iterations: u32,

    // first hit data
    hit_chunk: vec3<i32>,
    hit_voxel: vec3<i32>,
    delta_in_t: vec3<f32>,
    vl_point: vec3<f32>,
    smallest_axis_vec: vec3<f32>,
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

fn get_debug_color(v: u32) -> vec3<f32> {
    var colors = array<vec3<f32>, 7>(
        // vec3<f32>(0, 0, 0),
        vec3<f32>(1, 0, 0),
        vec3<f32>(0, 1, 0),
        vec3<f32>(1, 1, 0),
        vec3<f32>(0, 0, 1),
        vec3<f32>(1, 0, 1),
        vec3<f32>(0, 1, 1),
        vec3<f32>(1, 1, 1),
    );

    return colors[v % 7];
}

const chunk_sz: vec3<i32> = vec3<i32>(64);

fn is_solid(coord: vec3<i32>, chunk_no: u32) -> bool {
    let res = textureLoad(texture_map, vec2<i32>(coord.z * 64 + coord.x, coord.y), chunk_no, 0);
    // let res = textureLoad(chunk_mapping, coord, 0);
    return res.x != 0;
}

// *out_intersection is clobbered only if there was an intersection
fn intersect(ray: Ray, chunk_coords: vec3<i32>, out_intersection: ptr<function, Intersection>) -> bool {
    // X_dims -> vector of f32 specifying the physical size of X
    // X_sz   -> vector of integers specifying the discrete size of X
    // X      -> probably a global coordinate
    // cl_X   -> chunk-local coordinate
    // vl_X   -> voxel-local coordinate

    let raw_chunk_index = textureLoad(chunk_mapping, chunk_coords, 0).x;
    if (raw_chunk_index == 0) { return false; }
    let chunk_index = raw_chunk_index - 1;

    let chunk_min = vec3<f32>(0);
    let chunk_max = vec3<f32>(chunk_sz);
    let chunk_dims = chunk_max - chunk_min;

    var t_slab: f32;
    let is_outside = any(ray.origin < chunk_min) || any(ray.origin > chunk_max);
    let intersects = slab(ray.origin, ray.direction, chunk_min, chunk_max, &t_slab);

    if (is_outside && !intersects) { return false; }

    let origin_inside = select(
        ray.origin,
        ray.origin + ray.direction * t_slab * 1.0001,
        is_outside,
    );

    let gl_ray_origin = clamp(origin_inside - chunk_min, vec3<f32>(0), chunk_dims);
    let first_vox = vec3<i32>(floor(gl_ray_origin));

    let positiveness = ray.direction >= vec3<f32>(0);
    let signs = vec3<i32>(select(vec3<f32>(-1), vec3<f32>(1), positiveness));

    var gl_cur_point = gl_ray_origin;
    var cur_vox = first_vox;
    var no_iters = 0u;
    let debug = 0u;
    while (true) {
        let gl_cur_vox_origin = vec3<f32>(cur_vox);

        let raw_vl_cur_point = (gl_cur_point - gl_cur_vox_origin);

        if (is_solid(cur_vox, chunk_index) && debug == 0) {
            *out_intersection = Intersection(
                /* voxel_coords */ vec3<u32>(cur_vox),
                /* local_coords */ raw_vl_cur_point,
                /* distance     */ length(gl_cur_point - ray.origin),
            );
            return true;
        }

        let vl_cur_point = clamp(select(
            vec3<f32>(1) - raw_vl_cur_point,
            raw_vl_cur_point,
            positiveness
        ), vec3<f32>(0), vec3<f32>(1));

        let t_delta = (vec3<f32>(1) - vl_cur_point) / abs(ray.direction);

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

        let next_vox = cur_vox + signs[smallest_axis] * smallest_axis_vec;

        var debug_color: vec3<f32>;
        switch (debug) {
            case 1u: { debug_color = vec3<f32>(cur_vox) / vec3<f32>(chunk_sz); }
            case 2u: { debug_color = raw_vl_cur_point; }
            case 3u: { debug_color = vl_cur_point; }
            case 4u: { debug_color = vec3<f32>(t_delta); }
            case 5u: { debug_color = vec3<f32>(smallest_axis_vec);}
            default: {}
        }

        if (debug != 0) {
            *out_intersection = Intersection(vec3<u32>(cur_vox), debug_color, 1);
            return true;
        }

        if (any(next_vox >= chunk_sz) || any(next_vox < vec3<i32>(0))) {
            break;
        }

        no_iters += 1u;
        cur_vox = next_vox;
        gl_cur_point += t_delta[smallest_axis] * ray.direction;
    }

    // return colors[no_iters % 7u];
    // return vec3<f32>(no_iters) / 5;

    return false;
}

fn intersect_new(ray: Ray, out_intersection: ptr<function, Intersection>) -> bool {
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
        uniforms.location,
        ray_direction,
        vec3<f32>(1) / ray_direction,
    );

    var intersection: Intersection;
    let res = intersect(ray, vec3<i32>(0, 0, 2), &intersection);

    textureStore(texture_radiance, pixel, vec4<f32>(intersection.local_coords, 1.));
}

