@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@group(1) @binding(0) var texture_radiance: texture_storage_2d<bgra8unorm, write>;

@group(2) @binding(0) var<storage, read> svo_buffer: array<u32>;

struct VoxelExtents {
    first: vec3<u32>,
    last: vec3<u32>,
};

struct StackElement {
    extents: VoxelExtents,
    processed_children: u32,

    children_start: u32,
    flags: u32,
    child_offsets: u32,
};

fn make_stack_element(node_idx: u32, extents: VoxelExtents) -> StackElement {
    let node = get_node(node_idx);
    let leaves = node & 0xFF;
    let valid = (node >> 8) & 0xFF;

    let base_offset = node >> 16;
    let is_far = base_offset == 0xFFFF;
    let children_start = select(
        node_idx + base_offset + 1,
        get_node(node_idx + 1),
        is_far,
    );

    var offset_tracker = 0u;
    var child_offsets = 0u;

    for (var i = 0u; i < 8u; i++) {
        let child_is_valid = ((valid >> i) & 1) != 0;
        let child_is_leaf = ((leaves >> i) & 1) != 0;
        let child_is_far = (get_node(children_start + offset_tracker) >> 16) == 0xFFFF;

        let child_size = select(
            0u,
            select(
                select(1u, 2u, child_is_far),
                1u,
                child_is_leaf,
            ),
            child_is_valid,
        );

        child_offsets <<= 4;
        child_offsets |= offset_tracker;
        offset_tracker += child_size;
    }

    child_offsets = (child_offsets >> 16) | (child_offsets << 16);
    child_offsets = ((child_offsets >> 8) & 0x00FF00FF) | ((child_offsets << 8) & 0xFF00FF00);
    child_offsets = ((child_offsets >> 4) & 0x0F0F0F0F) | ((child_offsets << 4) & 0xF0F0F0F0);

    return StackElement(
      extents,
      0u,

      children_start,
      node & 0xFFFF,
      child_offsets,
    );
}

// invariant: `index < 8u`
fn get_split(extents: VoxelExtents, index: u32) -> VoxelExtents {
    let hi = (vec3<u32>(index) & vec3<u32>(1, 2, 4)) != vec3<u32>(0);

    //let mid = (extents.last + extents.first) / 2;
    let mid = extents.first + (extents.last - extents.first) / 2;

    return VoxelExtents(
        select(extents.first, mid + vec3<u32>(1), hi),
        select(mid, extents.last, hi),
    );
}

fn get_node_test(node_idx: u32) -> u32 {
    // A: extraneous empty node
    // B: invalid material leaf (larger than 1 voxel in size)

    // 2 ** 3
    // 00000000
    var test_0 = array<u32, 1>(0x00000000);

    // 2 ** 3
    // 00000101
    // ╰00000000 (0)
    var test_1 = array<u32, 2>(0x00000101, 0x00000000);

    // 4 ** 3
    // 00000100
    // ╰00000000 (0 *A)
    var test_2 = array<u32, 2>(0x00000100, 0x00000000);

    // 4 ** 3
    // 00000301
    // ├00000000 (0 *A)
    // ╰DEADBEEF (1 *B)
    var test_3 = array<u32, 3>(0x00000302, 0x00000000, 0xDEADBEEF);

    // yeah
    var test_4 = array<u32, 9>(
        0x0000FFFF,
        select(0x00000000u, 0xFFFFFFFFu, uniforms.debug_variable_1 == 0),
        select(0x00000000u, 0xFFFFFFFFu, uniforms.debug_variable_1 == 1),
        select(0x00000000u, 0xFFFFFFFFu, uniforms.debug_variable_1 == 2),
        select(0x00000000u, 0xFFFFFFFFu, uniforms.debug_variable_1 == 3),
        select(0x00000000u, 0xFFFFFFFFu, uniforms.debug_variable_1 == 4),
        select(0x00000000u, 0xFFFFFFFFu, uniforms.debug_variable_1 == 5),
        select(0x00000000u, 0xFFFFFFFFu, uniforms.debug_variable_1 == 6),
        select(0x00000000u, 0xFFFFFFFFu, uniforms.debug_variable_1 == 7),
    );

    // 4 ** 3
    // *
    // ╰*
    //  ╰DEADBEEF (0)
    var test_5 = array<u32, 3>(
        0x00000100,
        0x00000101,
        0xDEADBEEF,
    );

    // 4 ** 3
    // *
    // ├*
    // │╰DEADBEEF (0)
    // ╰*
    //  ╰B1FF3D17 (7)
    var test_6 = array<u32, 6>(
        0x00008100,

        0x00020101,

        0xFFFF8080,
        0x00000004,

        0xDEADBEEF,

        0xB1FF3D17,
    );

    // more of a DAG
    var test_7 = array<u32, 13>(
        0x0000FF00,

        0x00071717, // 11 10 10 00 00010111 17
        0x00062B2B, // 11 01 01 00 00101011 2B
        0x00054D4D, // 10 11 00 10 01001101 4D
        0x00048E8E, // 01 11 00 01 10001110 8E
        0x00037171, // 10 00 11 10 01110001 71
        0x0002B2B2, // 01 00 11 01 10110010 B2
        0x0001D4D4,
        0x0000E8E8,

        // at most 4 voxels in a group
        0xDEADBEEF,
        0xDEADBEEF,
        0xDEADBEEF,
        0xDEADBEEF,
    );

    switch (uniforms.debug_variable_0) {
        case 0u: { return test_0[node_idx]; }
        case 1u: { return test_1[node_idx]; }
        case 2u: { return test_2[node_idx]; }
        case 3u: { return test_3[node_idx]; }
        case 4u: { return test_4[node_idx]; }
        case 5u: { return test_5[node_idx]; }
        case 6u: { return test_6[node_idx]; }
        case 7u: { return test_7[node_idx]; }
        default: { return 0u; }
    }
}

fn get_node(idx: u32) -> u32 {
    return svo_buffer[idx];
}

var<private> g_traversal_order: array<u32, 8>;

fn trace(pixel: vec2<u32>, ray_arg: Ray, out_isection: ptr<function, Intersection>) -> bool {
    var ray = ray_arg;
    var t = 0.0;

    var stack = array<StackElement, 16>();
    var stack_ptr = 1u;
    let root_extents = VoxelExtents(vec3<u32>(0), vec3<u32>((1u << uniforms.custom[0]) - 1));
    stack[0u] = make_stack_element(0, root_extents);

    var i = 1u;
    while (true) {
        if (i >= 1024) { break; }
        i += 1u;

        if (stack_ptr == 0) { break; }

        let frame = stack[stack_ptr - 1];
        if (frame.processed_children == 8) { stack_ptr -= 1u; continue; }

        stack[stack_ptr - 1].processed_children += 1u;
        let child_no = g_traversal_order[frame.processed_children];

        let is_leaf = ((frame.flags >> (0 + child_no)) & 1) != 0;
        let is_valid = ((frame.flags >> (8 + child_no)) & 1) != 0;

        if (!is_valid) { continue; }

        let child_index = frame.children_start + ((frame.child_offsets >> (4 * child_no)) & 15);

        let split_for_child = get_split(frame.extents, child_no);
        var t_for_child: f32;
        let child_intersection = slab(
            ray.origin,
            ray.direction_reciprocals,
            vec3<f32>(split_for_child.first),
            vec3<f32>(split_for_child.last + vec3<u32>(1)),
            &t_for_child,
        );

        if (!child_intersection) { continue; }

        if (is_leaf) {
            let material = get_node(child_index);

            let hit_pt = ray.origin + t_for_child * ray.direction;
            *out_isection = Intersection(
                vec3<i32>(split_for_child.first),
                hit_pt - vec3<f32>(split_for_child.first),
                t_for_child,
                material,
                Statistics(),
            );

            return true;
        }

        stack[stack_ptr] = make_stack_element(child_index, split_for_child);
        stack_ptr += 1u;
    }

    debug_u32(3u, 0u, i);

    return false;
}

fn cbox(i: u32) -> vec3<f32> {
    var hi = (vec3<u32>(i) & vec3<u32>(1u, 2u, 4u)) != vec3<u32>(0u);

    return select(
        vec3<f32>(-1.0),
        vec3<f32>(1.0),
        hi,
    );
}

fn sort_swap(
    values: ptr<function, array<f32, 8>>,
    indices: ptr<function, array<u32, 8>>,
    lhs: u32, rhs: u32
) -> bool {
    let lhsi = (*indices)[lhs];
    let rhsi = (*indices)[rhs];

    let lhsv = (*values)[lhsi];
    let rhsv = (*values)[rhsi];

    let do_swap = lhsv < rhsv;

    let mini = select(lhsi, rhsi, do_swap);
    let maxi = select(rhsi, lhsi, do_swap);

    (*indices)[lhs] = mini;
    (*indices)[rhs] = maxi;

    return do_swap;
}

@compute @workgroup_size(8, 8, 1) fn cs_main(
    @builtin(global_invocation_id)   global_id: vec3<u32>,
    @builtin(workgroup_id)           workgroup_id: vec3<u32>,
    @builtin(local_invocation_id)    local_id:  vec3<u32>,
    @builtin(local_invocation_index) local_idx: u32,
) {
    let pixel = vec2<u32>(
        global_id.x,
        ((textureDimensions(texture_radiance).y + 7) / 8) * 8 - global_id.y - 1,
    );
    init_random(pixel, array<u32, 8>(
        uniforms.rs_0,
        uniforms.rs_1,
        uniforms.rs_2,
        uniforms.rs_3,
        uniforms.rs_4,
        uniforms.rs_5,
        uniforms.rs_6,
        uniforms.rs_7,
    ));

    g_debug_mode = uniforms.debug_mode;
    g_debug_level = uniforms.debug_level;

    let ray = generate_ray(pixel, uniforms.dims, uniforms.inverse_transform);
    var distances: array<f32, 8>;
    for (var i = 0u; i < 8u; i++) { distances[i] = -dot(cbox(i), ray.direction); }
    var order = array<u32, 8>(5, 6, 2, 4, 1, 3, 7, 0);
    // layer 0
    sort_swap(&distances, &order, 0, 2); sort_swap(&distances, &order, 1, 3);
    sort_swap(&distances, &order, 4, 6); sort_swap(&distances, &order, 5, 7);
    // layer 1
    sort_swap(&distances, &order, 0, 4); sort_swap(&distances, &order, 1, 5);
    sort_swap(&distances, &order, 2, 6); sort_swap(&distances, &order, 3, 7);
    // layer 2
    sort_swap(&distances, &order, 0, 1); sort_swap(&distances, &order, 2, 3);
    sort_swap(&distances, &order, 4, 5); sort_swap(&distances, &order, 6, 7);
    // layer 3
    sort_swap(&distances, &order, 2, 4); sort_swap(&distances, &order, 3, 5);
    // layer 4
    sort_swap(&distances, &order, 1, 4); sort_swap(&distances, &order, 3, 6);
    // layer 5
    sort_swap(&distances, &order, 1, 2); sort_swap(&distances, &order, 3, 4);
    sort_swap(&distances, &order, 5, 6);
    // ^ thanks, knuth

    debug_u32(1u, 0u, order[uniforms.debug_variable_0]);
    debug_f32(2u, 0u, distances[uniforms.debug_variable_0]);
    g_traversal_order = order;

    var intersection: Intersection;
    let intersected = trace(pixel, ray, &intersection);

    if (did_debug) {
        textureStore(texture_radiance, pixel, vec4<f32>(debug_out, 1));
    } else {
        //let out_color = select(
        //    vec4<f32>(0, 0, 0, 1),
        //    vec4<f32>(vec2<f32>(pixel) / uniforms.dims, 0, 1),
        //    intersected,
        //);
        textureStore(texture_radiance, pixel, vec4<f32>(intersection.local_coords, 1));
    }
}

