@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@group(1) @binding(0) var texture_radiance: texture_storage_2d<bgra8unorm, write>;

@group(2) @binding(0) var brickgrid: texture_3d<u32>;
@group(2) @binding(1) var<storage, read> bricktrees: array<u32>;
@group(2) @binding(2) var<storage, read> brickmaps: array<u32>;

const nudge_factor = 1.00001;

// X_dims can index into an array X
// X_size is a real quantity representing X_dims * X_element_size
//
// Say X is the brickgrid, then the `X_element` in `X_element_size` is a
// `brickmap` so the expression `X_size` is `brickgrid_dims * brickmap_size`
//
// When X is a brickmap, then `X_element` is a voxel, which is by
// definition 1x1x1 in *size* so `X_size` == `X_dims` == `brickmap_size`

const brickmap_depth: u32 = 4u;

// voxel_dims = vec3<u32>(1)
const brickmap_dims = vec3<u32>(1u << brickmap_depth);

// let voxel_size = vec3<f32>(voxel_dims) * nothing
const brickmap_size = vec3<f32>(brickmap_dims); // * voxel_size

fn bricktree_words() -> u32 { return power_sum(brickmap_depth, 3u) / 8 / 4; }
const brickmap_words: u32 = 1u << (3u * brickmap_depth);

fn blinkenlights(n: u32, pixel: vec2<u32>, out_color: ptr<function, vec3<f32>>) -> bool {
    let tree_length = bricktree_words();

    if (all(pixel >= vec2<u32>(6)) && all(pixel < vec2<u32>(10 + tree_length, 42))) {
        if (any(pixel < vec2<u32>(8)) || any(pixel >= vec2<u32>(8 + tree_length, 40))) {
            *out_color = vec3<f32>(1, select(0.0, 0.5, (pixel.x ^ pixel.y) % 2 == 0), 1);
            return true;
        }

        let bit = pixel.y - 8;
        let byte = pixel.x - 8;
        let value = bricktrees[n * tree_length + byte];

        *out_color = select(
            vec3<f32>(0),
            vec3<f32>(1),
            ((value >> bit) & 1) != 0
        );

        return true;
    }

    // let brickgrid_dims: vec3<u32> = textureDimensions(brickgrid);

    return false;
}

fn get_material(brickmap: u32, bl_coords: vec3<u32>) -> u32 {
    let g_offset = brickmap * brickmap_words;
    let l_offset =
       bl_coords[0] |
      (bl_coords[1] << brickmap_depth) |
      (bl_coords[2] << (brickmap_depth * 2u));

    return brickmaps[g_offset + l_offset];
}

struct BoxIteration {
    next_box_offset: vec3<i32>,
    t: f32,

    box_local_pt: vec3<f32>,
    new_origin: vec3<f32>,
};

/// `box_size` kind of goes against the convention of `_size` values being
/// vec3<f32>s but oh well
fn iterate_box(
    ray: Ray,

    box_coords: vec3<i32>,
    box_size: vec3<i32>,

    iteration: u32,
    debug_offset: u32,
) -> BoxIteration {
    let box_origin = vec3<f32>(box_coords * box_size);
    // let box_local_pt = ray.origin - box_origin;
    let box_local_pt = clamp(ray.origin - box_origin, vec3<f32>(0), vec3<f32>(box_size));

    let ray_relative_box_local_pt = select(
        vec3<f32>(box_size) - box_local_pt,
        box_local_pt,
        ray.iter_direction == vec3<i32>(1),
    );

    let delta = vec3<f32>(box_size) - ray_relative_box_local_pt;
    let tv = delta / abs(ray.direction);

    debug_vec(debug_offset + 0u, iteration, abs(delta) / vec3<f32>(box_size));
    debug_vec(debug_offset + 1u, iteration, abs(delta) * vec3<f32>(1, 1, 0) / vec3<f32>(box_size));
    debug_vec(debug_offset + 2u, iteration, tv / 64);
    debug_jet(debug_offset + 3u, iteration, tv.x / 64);
    debug_jet(debug_offset + 4u, iteration, tv.y / 64);
    debug_jet(debug_offset + 5u, iteration, tv.z / 64);

    let shortest_axis = select(
        select(2u, 1u, tv.y < tv.z),
        select(2u, 0u, tv.x < tv.z),
        tv.x < tv.y,
    );

    let t = tv[shortest_axis];

    var shortest_axis_vector: vec3<i32>;
    switch (shortest_axis) {
        case 0u: { shortest_axis_vector = vec3<i32>(1, 0, 0); }
        case 1u: { shortest_axis_vector = vec3<i32>(0, 1, 0); }
        case 2u: { shortest_axis_vector = vec3<i32>(0, 0, 1); }
        default: {}
    }
    shortest_axis_vector *= ray.iter_direction;

    debug_vec(
        debug_offset + 6u,
        iteration,
        vec3<f32>(select(
            shortest_axis_vector * 2,
            shortest_axis_vector + vec3<i32>(2),
            shortest_axis_vector == vec3<i32>(-1)
        )) / 2, // -1 0 1 -> 1 0 2
    );


    return BoxIteration(
        shortest_axis_vector,
        t,
        box_local_pt,
        ray.origin + ray.direction * t * nudge_factor,
        // clamp(ray.origin + ray.direction * t * 1.00001, box_origin * 0.9999, (box_origin + vec3<f32>(box_size)) * 1.0001),
    );
}

fn trace(ray_arg: Ray, out_isection: ptr<function, Intersection>) -> bool {
    let tree_length = power_sum(brickmap_depth, 3u) / 8 / 4;

    let brickgrid_dims = vec3<i32>(textureDimensions(brickgrid));

    let brickgrid_size = vec3<f32>(brickgrid_dims) * brickmap_size;

    var ray = ray_arg;

    let outside_brickgrid = any(ray.origin <= vec3<f32>(0)) || any(ray.origin >= brickgrid_size);
    if (outside_brickgrid) {
        // are we intersecting the brickgrid?
        var distance_to_the_brickgrid: f32;
        let is_intersecting_the_brickgrid = slab(
            ray.origin,
            ray.direction,
            vec3<f32>(0),
            vec3<f32>(brickgrid_dims) * brickmap_size,
            &distance_to_the_brickgrid,
        );

        debug_bool(0u, 1u, is_intersecting_the_brickgrid);
        debug_jet(1u, 1u, select(0., sqrt(distance_to_the_brickgrid) / 5, is_intersecting_the_brickgrid));

        if (!is_intersecting_the_brickgrid) {
            return false;
        }

        ray.origin += distance_to_the_brickgrid * ray.direction * nudge_factor;
    }

    let sentinel = 0xFFFFFFFFu;

    var current_brickmap = sentinel;

    var stack = array<vec3<i32>, 2>(
        vec3<i32>(ray.origin / brickmap_size),
        vec3<i32>(0),
    );

    var lagged_stack = array<vec3<i32>, 2>(
        vec3<i32>(0),
        vec3<i32>(0),
    );

    var level = 0u;

    for (var i = 2u;; i++) {
        if (i >= 256u) {
            debug_vec(0u, i, vec3<f32>(1, 0, 1));
            break;
        }

        let current_box_coords = stack[level];

        debug_u32(0u, i, level);
        debug_u32(1u, i, current_brickmap);
        debug_vec(2u, i, ray.origin / 128);

        var have_hit = false;

        if (level == 0u) {
            if (
                any(current_box_coords < vec3<i32>(0u)) ||
                any(current_box_coords >= brickgrid_dims)
            ) {
                debug_vec(3u, i, vec3<f32>(1, 0.5, 1));
                return false;
            }

            debug_vec(4u, i, vec3<f32>(current_box_coords) / vec3<f32>(brickgrid_dims));

            current_brickmap = textureLoad(brickgrid, current_box_coords, 0).r;
            have_hit = current_brickmap != sentinel;

            debug_bool(3u, i, have_hit);

            let iteration = iterate_box(
                ray,
                current_box_coords,
                vec3<i32>(brickmap_dims),
                i, 6u,
            );

            lagged_stack[level] = current_box_coords;
            stack[level] = vec3<i32>(current_box_coords) + iteration.next_box_offset;

            if (!have_hit) {
                ray.origin = iteration.new_origin;
                //ray.origin += ray.direction * iteration.t;
            } else {
                let next_inner = current_box_coords * vec3<i32>(brickmap_dims) + clamp(
                    vec3<i32>(trunc(iteration.box_local_pt)),
                    vec3<i32>(0),
                    vec3<i32>(brickmap_dims) - vec3<i32>(1),
                );
                stack[level + 1] = next_inner;
                level += 1u;
            }
        } else if (level == 1) {
            let min_coord = lagged_stack[level - 1] * vec3<i32>(brickmap_dims);
            if (
                any(current_box_coords < min_coord) ||
                any(current_box_coords >= min_coord + vec3<i32>(brickmap_dims))
            ) {
                level -= 1u;
                continue;
            }

            let brickmap_coords = current_box_coords / vec3<i32>(brickmap_dims);
            let bml_voxel_coords = current_box_coords - brickmap_coords * vec3<i32>(brickmap_dims);

            debug_vec(4u, i, vec3<f32>(brickmap_coords) / vec3<f32>(brickgrid_dims));
            debug_vec(5u, i, vec3<f32>(bml_voxel_coords) / vec3<f32>(brickmap_dims));

            let material = get_material(current_brickmap, vec3<u32>(bml_voxel_coords));
            let have_hit = material != 0u;

            debug_bool(3u, i, have_hit);

            if (have_hit) {
                *out_isection = Intersection(
                    current_box_coords,
                    ray.origin - vec3<f32>(current_box_coords),
                    length(ray_arg.origin - ray.origin),
                    material,
                    Statistics(),
                );
                return true;
            }

            let iteration = iterate_box(
                ray,
                current_box_coords, vec3<i32>(1u),
                i, 6u,
            );

            let next = current_box_coords + iteration.next_box_offset;

            stack[level] = next;
            ray.origin = iteration.new_origin;
            // ray.origin += iteration.box_local_pt;
            // ray.origin += ray.direction * iteration.t * nudge_factor;
        } else {
            // unreachable
        }
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

    var blinkenlight: vec3<f32>;
    if (blinkenlights(0u, pixel, &blinkenlight)) {
        textureStore(texture_radiance, pixel, vec4<f32>(blinkenlight, 1));
        return;
    }

    let ray = generate_ray(pixel);
    var intersection: Intersection;
    let intersected = trace(ray, &intersection);

    debug_vec(0u, 0u, intersection.local_coords);
    // debug_bool(0u, 0u, intersected);
    debug_vec(1u, 0u, vec3<f32>(intersection.distance / 5, 0, 0));

    debug_jet(2u, 0u, f32(pixel.x) / uniforms.dims[0]);

    debug_vec(3u, 0u, ray.origin / 32);
    debug_vec(4u, 0u, ray.direction);
    debug_vec(5u, 0u, vec3<f32>(ray.iter_direction + vec3<i32>(1)) / 2);

    textureStore(texture_radiance, pixel, vec4<f32>(debug_out, 1));
}

