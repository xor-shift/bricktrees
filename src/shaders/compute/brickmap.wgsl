@group(2) @binding(0) var brickgrid: texture_3d<u32>;
@group(2) @binding(1) var<storage, read> bricktrees: array<u32>;
@group(2) @binding(2) var<storage, read> brickmaps: array<u32>;

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

const nudge_factor = 1.00001;

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
};

fn iterate_box(
    ray: Ray,

    box_coords: vec3<i32>,
    box_sidelength: i32,

    iteration: u32,
    debug_offset: u32,
) -> BoxIteration {
    let box_origin = vec3<f32>(box_coords * box_sidelength);
    let box_local_pt = ray.origin - box_origin;

    let ray_relative_box_local_pt = select(
        vec3<f32>(box_sidelength) - box_local_pt,
        box_local_pt,
        ray.iter_direction == vec3<i32>(1),
    );

    let delta = vec3<f32>(box_sidelength) - ray_relative_box_local_pt;
    let tv = delta * abs(ray.direction_reciprocals);

    debug_vec(debug_offset + 0u, iteration, abs(delta) / f32(box_sidelength));
    debug_vec(debug_offset + 1u, iteration, abs(delta) * vec3<f32>(1, 1, 0) / f32(box_sidelength));
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
    );
}

struct StackFrame {
    coords: vec3<i32>,

    // The issue this solves is the following situation:
    // - At level n we get a hit
    // - We prepare the next coordinate for level n (big computation)
    // - Traversal continues to n+1
    // - n+1 has a hit!
    // - It turns out to be a voxel hit so we return
    // The issue here is that we know what the next level n box is despite it
    // being irrelevant.
    iterate_first: bool,
};

struct LevelProps {
    sidelength: i32,
    parent_dims: vec3<i32>,
};

fn tree_check(brickmap: u32, level: u32, level_sidelength: i32, bml_voxel_coords: vec3<u32>) -> bool {
    if (uniforms.debug_variable_1 == 1u) { return true; }

    let global_word_offset = brickmap * bricktree_words();

    if (level == 1u) {
        // where's my boy Morton when i need him

        let sample = bricktrees[global_word_offset + bml_voxel_coords.z];

        let shift = bml_voxel_coords.y * 4 + bml_voxel_coords.x * 2;
        let sm = (sample >> shift) & 0x00330033;

        return sm != 0u;
    }

    let mask = (1u << level) - 1u;
    let bit_offset =
       (bml_voxel_coords[0] & mask) |
      ((bml_voxel_coords[1] & mask) << level) |
      ((bml_voxel_coords[2] & mask) << (level * 2));

    // 8^2 + ... + 8^(level-1)
    let level_offset = power_sum(level, 3u) - 9;

    let bit_index = bit_offset + level_offset;
    let local_word_offset = bit_index / 32;

    let sample = bricktrees[global_word_offset + local_word_offset];
    let bit = (sample >> (bit_index % 32)) & 1;

    return bit != 0u;
}

fn trace(ray_arg: Ray, out_isection: ptr<function, Intersection>) -> bool {
    let tree_length = power_sum(brickmap_depth, 3u) / 8 / 4;

    let brickgrid_dims = vec3<i32>(textureDimensions(brickgrid));
    let brickgrid_size = vec3<f32>(brickgrid_dims) * brickmap_size;

    var ray = ray_arg;

    let outside_brickgrid =
        any(ray.origin <= vec3<f32>(0)) ||
        any(ray.origin >= brickgrid_size);

    if (outside_brickgrid) {
        var distance_to_the_brickgrid: f32;
        let is_intersecting_the_brickgrid = slab(
            ray.origin,
            ray.direction_reciprocals,
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
    var material = 0u;

    var level = 0u;
    var stack = array<StackFrame, 5u>(
        StackFrame(vec3<i32>(ray.origin / brickmap_size), false),
        StackFrame(vec3<i32>(0), false),
        StackFrame(vec3<i32>(0), false),
        StackFrame(vec3<i32>(0), false),
        StackFrame(vec3<i32>(0), false),
    );

    // read-only but we can't use vars to index into lets
    var level_props = array<LevelProps, 5u>(
        LevelProps(16, brickgrid_dims * 1 ),
        LevelProps(8 , brickgrid_dims * 2 ),
        LevelProps(4 , brickgrid_dims * 4 ),
        LevelProps(2 , brickgrid_dims * 8 ),
        LevelProps(1 , brickgrid_dims * 16),
    );

    for (var i = 2u;; i++) {
        if (i >= 256u) {
            debug_vec(0u, i, vec3<f32>(1, 0, 0));
            break;
        }

        var have_hit = false;

        let props = level_props[level];

        debug_u32(1u, i, level);
        debug_u32(2u, i, current_brickmap);
        debug_vec(3u, i, ray.origin / brickgrid_size);
        debug_vec(4u, i, vec3<f32>(stack[level].coords) / vec3<f32>(props.parent_dims));

        if (stack[level].iterate_first) {
            let iteration = iterate_box(
                ray,
                stack[level].coords,
                props.sidelength,
                i, 5u,
            );

            ray.origin += ray.direction * iteration.t;
            stack[level].coords += iteration.next_box_offset;
            stack[level].iterate_first = false;
        }

        let basic_oob =
            any(stack[level].coords < vec3<i32>(0)) ||
            any(stack[level].coords >= props.parent_dims);

        if (basic_oob) {
            debug_vec(0u, i, vec3<f32>(1, 0, 1));
            return false;
        }

        if (level != 0u) {
            let parent_size = vec3<i32>(level_props[level - 1u].sidelength);
            let min_coord = stack[level - 1u].coords * parent_size;

            let sub_oob =
                any(stack[level].coords * props.sidelength < min_coord) ||
                any(stack[level].coords * props.sidelength >= (min_coord + parent_size));

            if (sub_oob) {
                debug_vec(0u, i, vec3<f32>(0, 0, 0.6));
                level -= 1u;
                continue;
            }
        }

        if (level == 0u) {
            current_brickmap = textureLoad(brickgrid, stack[level].coords, 0).r;
            have_hit = current_brickmap != sentinel;
        } else if (level == 4u) {
            let brickmap_coords = stack[level].coords / vec3<i32>(brickmap_dims);
            let bml_voxel_coords = stack[level].coords - brickmap_coords * vec3<i32>(brickmap_dims);

            debug_vec(4u, i, vec3<f32>(brickmap_coords) / vec3<f32>(brickgrid_dims));
            debug_vec(5u, i, vec3<f32>(bml_voxel_coords) / vec3<f32>(brickmap_dims));

            material = get_material(current_brickmap, vec3<u32>(bml_voxel_coords));
            have_hit = material != 0u;
        } else {
            let level_relative_brickmap_origin = stack[0].coords * level_props[0].sidelength / props.sidelength;
            have_hit = tree_check(
                current_brickmap,
                level,
                props.sidelength,
                vec3<u32>(stack[level].coords - level_relative_brickmap_origin),
            );
            //have_hit = true;
        }

        debug_bool(0u, i, have_hit);

        if (have_hit) {
            if (level == 4u) {
                *out_isection = Intersection(
                    vec3<i32>(stack[level].coords),
                    ray.origin - vec3<f32>(stack[level].coords),
                    length(ray_arg.origin - ray.origin),
                    material,
                    Statistics(),
                );
                return true;
            }

            stack[level].iterate_first = true;

            let box_origin = vec3<f32>(stack[level].coords * props.sidelength);
            let norm_box_local_pt = (ray.origin - box_origin) / f32(props.sidelength);
            let next_sidelength = level_props[level + 1].sidelength;
            let factor = props.sidelength / next_sidelength;
            let next_inner =
                stack[level].coords * vec3<i32>(factor) +
                clamp(
                    vec3<i32>(trunc(norm_box_local_pt * f32(factor))),
                    vec3<i32>(0),
                    vec3<i32>(factor - 1),
                );

            stack[level + 1u].coords = next_inner;
            stack[level + 1u].iterate_first = false;

            level += 1u;
        } else {
            stack[level].iterate_first = true;
        }
    }

    return false;
}
