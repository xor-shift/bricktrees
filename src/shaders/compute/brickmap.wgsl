{{#use_brickmaps}}

@group(2) @binding(0) var brickgrid: texture_3d<u32>;
@group(2) @binding(1) var<storage, read> brickmaps: array<u32>;

// X_dims can index into an array X
// X_size is a real quantity representing X_dims * X_element_size
//
// Say X is the brickgrid, then the `X_element` in `X_element_size` is a
// `brickmap` so the expression `X_size` is `brickgrid_dims * brickmap_size`
//
// When X is a brickmap, then `X_element` is a voxel, which is by
// definition 1x1x1 in *size* so `X_size` == `X_dims` == `brickmap_size`

const brickmap_depth: u32 = {{brickmap_depth}};
const iteration_depth = brickmap_depth + 1;

// voxel_dims = vec3<u32>(1)
const brickmap_dims = vec3<u32>(1u << brickmap_depth);

// let voxel_size = vec3<f32>(voxel_dims) * nothing
const brickmap_size = vec3<f32>(brickmap_dims); // * voxel_size

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

const sentinel_brickmap: u32 = 0xFFFFFFFFu;

struct LevelProps {
    sidelength: i32,
    parent_dims: vec3<i32>,
};

fn get_level_props(level: u32) -> LevelProps {
    let brickgrid_dims = vec3<i32>(textureDimensions(brickgrid));

{{#use_bricktrees}}
    // for 6:
    // 0: 64, brickgrid_dims * 1 ,  // brickgrid
    // 1: 16, brickgrid_dims * 4 , // tree level 0
    // 2: 4 , brickgrid_dims * 16, // tree level 1
    // 3: 1 , brickgrid_dims * 64  // voxel
    return LevelProps(
        i32(1) << (brickmap_depth - level * bricktree_level_depth),
        brickgrid_dims * (i32(1) << (level * bricktree_level_depth)),
    );
{{/use_bricktrees}}

{{^use_bricktrees}}
    if (level == 0u) { return LevelProps(i32(1) << brickmap_depth, brickgrid_dims); }
    else { return LevelProps(i32(1), brickgrid_dims * (i32(1) << brickmap_depth)); }
{{/use_bricktrees}}
}

struct Iterator {
    ray: Ray,

    level: u32,
    material: u32,
    current_brickmap: u32,

    stack: array<StackFrame, iteration_depth>,
};

fn new_iterator(ray_arg: Ray, out_iterator: ptr<function, Iterator>) -> bool {
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

    var stack = array<StackFrame, iteration_depth>();
    stack[0].coords = vec3<i32>(ray.origin / brickmap_size);

    *out_iterator = Iterator(
        /* ray */ ray,
        /* lvl */ 0u,
        /* mat */ 0u,
        /* bm  */ sentinel_brickmap,
        /* stk */ stack,
    );

    return true;
}

fn iterator_cur_frame(it: ptr<function, Iterator>) -> StackFrame {
    return (*it).stack[(*it).level];
}

// 0 -> no OOB
// 1 -> sub-OOB
// 2 -> yeah we're out of the box
fn iterator_check_oob(it: ptr<function, Iterator>) -> u32 {
    let props = get_level_props((*it).level);

    let basic_oob =
        any((*it).stack[(*it).level].coords < vec3<i32>(0)) ||
        any((*it).stack[(*it).level].coords >= props.parent_dims);

    if (basic_oob) {
        return 2u;
    }

    if ((*it).level == 0u) { return 0u; }

    let parent_size = vec3<i32>(get_level_props((*it).level - 1u).sidelength);
    let min_coord = (*it).stack[(*it).level - 1u].coords * parent_size;

    let sub_oob =
        any((*it).stack[(*it).level].coords * props.sidelength < min_coord) ||
        any((*it).stack[(*it).level].coords * props.sidelength >= (min_coord + parent_size));

    if (sub_oob) { return 1u; }

    return 0u;
}

const voxel_level = {{no_levels}}u - 1u;

fn iterator_detect_hit(it: ptr<function, Iterator>, i: u32, first_time_on_level: bool) -> bool {
    let brickgrid_dims = vec3<i32>(textureDimensions(brickgrid));
    let frame = iterator_cur_frame(it);

    if ((*it).level == 0u) {
        let brickmap = textureLoad(brickgrid, frame.coords, 0).r;
        if (brickmap == sentinel_brickmap) { return false; }

        (*it).current_brickmap = brickmap;
        return true;
    }

    if ((*it).level == voxel_level) {
        let brickmap_coords = frame.coords / vec3<i32>(brickmap_dims);
        let bml_voxel_coords = frame.coords - brickmap_coords * vec3<i32>(brickmap_dims);

        debug_vec(4u, i, vec3<f32>(brickmap_coords) / vec3<f32>(brickgrid_dims));
        debug_vec(5u, i, vec3<f32>(bml_voxel_coords) / vec3<f32>(brickmap_dims));

        let material = get_material((*it).current_brickmap, vec3<u32>(bml_voxel_coords));
        if (material == 0u) { return false; }

        (*it).material = material;
        return true;
    }

{{#use_bricktrees}}
    let props = get_level_props((*it).level);

    let level_relative_brickmap_origin =
      (*it).stack[0].coords * vec3<i32>(brickmap_dims) / props.sidelength;

    return tree_check(
        (*it).current_brickmap,
        (*it).level,
        vec3<u32>(frame.coords - level_relative_brickmap_origin),
        first_time_on_level,
    );
{{/use_bricktrees}}

{{^use_bricktrees}}
    return false;
{{/use_bricktrees}}
}

/// Returns whether to continue iterating
fn iterator_iterate(it: ptr<function, Iterator>, i: u32) -> bool {
    debug_u32(0u, i + 1, i);

    if (i >= 256) {
        debug_vec(1u, i, vec3<f32>(1, 0, 0));
        return false;
    }

    let props = get_level_props((*it).level);

    var first_time_on_level = !(*it).stack[(*it).level].iterate_first;
    if (!first_time_on_level) {
        let frame = (*it).stack[(*it).level];

        let bit = iterate_box(
            (*it).ray,
            frame.coords,
            props.sidelength,
            i, 5u,
        );

        (*it).ray.origin += (*it).ray.direction * bit.t;
        (*it).stack[(*it).level].coords += bit.next_box_offset;
        (*it).stack[(*it).level].iterate_first = false;

        debug_vec(1u, i, vec3<f32>(0, 1, 0));
    }

    let frame = (*it).stack[(*it).level];

    let bound_check_res = iterator_check_oob(it);

    if (bound_check_res == 2u) {
        debug_vec(1u, i, vec3<f32>(1, 0, 1));
        return false;
    }

    if (bound_check_res == 1u) {
        debug_vec(1u, i, vec3<f32>(0, 0, 0.6));
        (*it).level -= 1u;
        return true;
    }

    let have_hit = iterator_detect_hit(it, i, first_time_on_level);
    debug_bool(1u, i, have_hit);

    debug_u32(2u, i, (*it).level);
    debug_u32(3u, i, (*it).current_brickmap);

    if (!have_hit) {
        (*it).stack[(*it).level].iterate_first = true;
        return true;
    }

    // we're done
    if ((*it).level == voxel_level) {
        return false;
    }

    // for the next iteration
    (*it).stack[(*it).level].iterate_first = true;

    let box_origin = vec3<f32>(frame.coords * props.sidelength);
    let norm_box_local_pt = ((*it).ray.origin - box_origin) / f32(props.sidelength);
    let factor = props.sidelength / get_level_props((*it).level + 1u).sidelength;
    let next_inner =
        frame.coords * vec3<i32>(factor) +
        clamp(
            vec3<i32>(trunc(norm_box_local_pt * f32(factor))),
            vec3<i32>(0),
            vec3<i32>(factor - 1),
        );

    (*it).stack[(*it).level + 1u].coords = next_inner;
    (*it).stack[(*it).level + 1u].iterate_first = false;

    (*it).level += 1u;

    return true;
}

fn trace(ray_arg: Ray, out_isection: ptr<function, Intersection>) -> bool {
    let tree_length = power_sum(brickmap_depth, 3u) / 8 / 4;

    var iterator: Iterator;
    if (!new_iterator(ray_arg, &iterator)) { return false; }

    for (var i = 2u;; i++) {
        let should_continue = iterator_iterate(&iterator, i);

        if (!should_continue) { break; }
    }

    *out_isection = Intersection(
        vec3<i32>(iterator.stack[iterator.level].coords),
        iterator.ray.origin - vec3<f32>(iterator.stack[iterator.level].coords),
        length(ray_arg.origin - iterator.ray.origin),
        iterator.material,
        Statistics(),
    );

    return iterator.material != 0u;
}

fn hit_check_coarse(
    origin_arg: vec3<f32>,
    direction: vec3<f32>,
    no_iters: u32,
    iter_step: f32,
) -> u32 {
    var origin = origin_arg;

    let brickgrid_dims = vec3<i32>(textureDimensions(brickgrid));
    let voxel_dims = vec3<i32>(brickmap_dims) * brickgrid_dims;

    for (var i = 0u; i < no_iters; i++) {
        let voxel_coords = vec3<i32>(trunc(origin + f32(i) * iter_step * direction));
        if (any(voxel_coords < vec3<i32>(0)) || any(voxel_coords >= voxel_dims)) {
            continue;
        }

        let brickmap_coords = voxel_coords / vec3<i32>(brickmap_dims);
        let bml_voxel_coords = voxel_coords - brickmap_coords * vec3<i32>(brickmap_dims);

        let brickmap = textureLoad(brickgrid, brickmap_coords, 0).r;
        if (brickmap == sentinel_brickmap) {
            continue;
        }

        let material = get_material(brickmap, vec3<u32>(bml_voxel_coords));
        if (material != 0u) {
            return i;
        }
    }

    return no_iters;
}

{{/use_brickmaps}}
