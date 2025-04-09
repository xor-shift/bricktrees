@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@group(1) @binding(0) var texture_radiance: texture_storage_2d<bgra8unorm, write>;

@group(2) @binding(0) var<storage, read> svo_buffer: array<u32>;

struct VoxelExtents {
    first: vec3<u32>,
    last: vec3<u32>,
};

struct StackElement {
    node: u32,
    extents: VoxelExtents,
    processed_bits: u32,
    processed_children: u32,
};

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

fn trace(pixel: vec2<u32>, ray_arg: Ray, out_isection: ptr<function, Intersection>) -> bool {
    var ray = ray_arg;
    var t = 0.0;

    var stack = array<StackElement, 13>();
    var stack_ptr = 1u;
    stack[0u] = StackElement(
        /* node               */ 0u,
        /* extents            */ VoxelExtents(vec3<u32>(0), vec3<u32>(1023)),
        /* processed_bits     */ 0u,
        /* processed_children */ 0u,
    );

    let default_nearest_t: f32 = 999999.0;
    var nearest_t: f32 = default_nearest_t;

    var i = 0u;
    while (true) {
        if (i >= 1024) { break; }
        i += 1u;

        if (stack_ptr == 0) { break; }

        let frame = stack[stack_ptr - 1];
        debug_u32(1u, i, frame.processed_bits);

        let node_idx = frame.node;
        let node = get_node(node_idx);
        debug_u32(2u, i, node);
        let leaf_mask = (node >> 0u) & 0xFFu;
        let valid_mask = (node >> 8u) & 0xFFu;
        let child_offset = (node >> 16u) + 1;
        let is_far = child_offset == 0x80000;
        let children_start = select(node_idx + child_offset, get_node(node_idx + 1), is_far);

        let remaining_valid = (valid_mask >> frame.processed_bits) << frame.processed_bits;

        if (remaining_valid == 0) {
            stack_ptr -= 1u;
            continue;
        }

        let geo_child_idx = firstTrailingBit(remaining_valid);
        debug_u32(3u, i, geo_child_idx);
        let is_leaf = ((leaf_mask >> geo_child_idx) & 1u) == 1u;

        stack[stack_ptr - 1].processed_bits = geo_child_idx + 1u;
        stack[stack_ptr - 1].processed_children += 1u;

        let split_for_child = get_split(frame.extents, geo_child_idx);
        var t_for_child: f32;
        let child_intersection = slab(
            ray.origin,
            ray.direction_reciprocals,
            vec3<f32>(split_for_child.first),
            vec3<f32>(split_for_child.last + vec3<u32>(1)),
            &t_for_child,
        );

        if (!child_intersection) {
            continue;
        }

        if (is_leaf) {
            if (nearest_t < t_for_child) { continue; }
            nearest_t = t_for_child;

            // can't be 0
            let material = get_node(children_start + frame.processed_children);

            let hit_pt = ray.origin + t_for_child * ray.direction;
            *out_isection = Intersection(
                vec3<i32>(split_for_child.first),
                hit_pt - vec3<f32>(split_for_child.first),
                t_for_child,
                material,
                Statistics(),
            );
            continue;
            // return true;
        }

        stack[stack_ptr] = StackElement(
            /* node               */ children_start + frame.processed_children,
            /* extents            */ split_for_child,
            /* processed_bits     */ 0,
            /* processed_children */ 0,
        );
        stack_ptr += 1u;
    }

    debug_u32(1u, 0u, i);

    return nearest_t != default_nearest_t;
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

