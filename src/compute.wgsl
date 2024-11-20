struct Uniforms {
    dims: vec2<u32>,
    _padding_0: vec2<u32>,
    location: vec3<f32>,
    _padding_1: f32,
    transform: mat4x4<f32>,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(1) @binding(0) var texture_geo_0: texture_storage_2d<rgba32uint, write>;
@group(1) @binding(1) var texture_geo_1: texture_storage_2d<rgba32uint, write>;
@group(1) @binding(2) var texture_radiance: texture_storage_2d<rgba8unorm, write>;

fn get_w_from_fov_z(fov: f32, z: f32) -> f32 {
    let rad = (fov / 2) / 180 * 3.1415926535897932384626433;
    return tan(rad) * z;
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

struct Intersection {
    voxel_coords: vec3<u32>,
    local_coords: vec3<f32>,
    distance: f32,
};

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

const grid_sz: vec3<i32> = vec3<i32>(128, 128, 128);

fn is_solid(coord: vec3<i32>) -> bool {
    let norm = vec3<f32>(coord) / vec3<f32>(grid_sz);
    let dist = length(norm - vec3<f32>(0.5));
    return dist < 0.5;
}

// *out_intersection is clobbered only if there was an intersection
fn intersect(origin: vec3<f32>, direction: vec3<f32>, out_intersection: ptr<function, Intersection>) -> bool {
    // X_dims -> vector of f32 specifying the physical size of X
    // X_sz   -> vector of integers specifying the discrete size of X
    // X      -> probably a global coordinate
    // gl_X   -> grid-local coordinate
    // vl_X   -> voxel-local coordinate

    let grid_min = vec3<f32>(-2, -2, 23);
    let scale = vec3<f32>(0.5);
    let grid_max = grid_min + vec3<f32>(grid_sz) * scale;
    let grid_dims = grid_max - grid_min;
    let vox_dims = grid_dims / vec3<f32>(grid_sz);

    var t_slab: f32;
    let is_outside = any(origin < grid_min) || any(origin > grid_max);
    let intersects = slab(origin, direction, grid_min, grid_max, &t_slab);

    if (is_outside && !intersects) { return false; }

    let origin_inside = select(
        origin,
        origin + direction * t_slab * 1.0001,
        is_outside,
    );

    let gl_ray_origin = clamp(origin_inside - grid_min, vec3<f32>(0), grid_dims);
    let first_vox = vec3<i32>(floor(gl_ray_origin / vox_dims));

    let positiveness = direction >= vec3<f32>(0);
    let signs = vec3<i32>(select(vec3<f32>(-1), vec3<f32>(1), positiveness));

    var gl_cur_point = gl_ray_origin;
    var cur_vox = first_vox;
    var no_iters = 0u;
    let debug = 0u;
    while (true) {
        let gl_cur_vox_origin = vec3<f32>(cur_vox) * vox_dims;

        let raw_vl_cur_point = (gl_cur_point - gl_cur_vox_origin) / scale;

        if (is_solid(cur_vox) && debug == 0) {
            *out_intersection = Intersection(
                /* voxel_coords */ vec3<u32>(cur_vox),
                /* local_coords */ raw_vl_cur_point,
                /* distance     */ length(gl_cur_point - origin),
            );
            return true;
        }

        let vl_cur_point = clamp(select(
            vec3<f32>(1) - raw_vl_cur_point,
            raw_vl_cur_point,
            positiveness
        ), vec3<f32>(0), vec3<f32>(1));

        let t_delta = (vec3<f32>(1) - vl_cur_point) / abs(direction);

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
            case 1u: { debug_color = vec3<f32>(cur_vox) / 8; }
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

        if (any(next_vox >= grid_sz) || any(next_vox < vec3<i32>(0))) {
            break;
        }

        no_iters += 1u;
        cur_vox = next_vox;
        gl_cur_point += t_delta[smallest_axis] * direction;
    }

    // return colors[no_iters % 7u];
    // return vec3<f32>(no_iters) / 5;

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

    let aspect = f32(uniforms.dims.x) / f32(uniforms.dims.y);
    let fov = 60.0;
    let z = 0.1;
    let ray_direction = normalize(vec3<f32>(
        get_w_from_fov_z(fov, z) * (f32(pixel.x) / f32(uniforms.dims.x) - 0.5),
        get_w_from_fov_z(fov / aspect, z) * (0.5 - f32(pixel.y) / f32(uniforms.dims.y)),
        z,
    ));
    let transformed = (uniforms.transform * vec4<f32>(ray_direction, 0)).xyz;

    var intersection: Intersection;
    let res = intersect(uniforms.location, transformed, &intersection);

    textureStore(texture_radiance, pixel, vec4<f32>(intersection.local_coords, 1.));
    // textureStore(texture_radiance, pixel, vec4<f32>(vec3<f32>(intersection.distance), 1.));
}

