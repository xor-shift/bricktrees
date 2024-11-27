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

fn debug_vec(ident: u32, value: vec3<f32>, iteration: u32, out_isection: ptr<function, Intersection>) -> bool {
    if (uniforms.display_mode != ident) { return false; }
    if (uniforms.debug_capture_point != iteration) { return false; }

    (*out_isection).local_coords = value;

    return true;
}

fn debug_bool(ident: u32, value: bool, iteration: u32, out_isection: ptr<function, Intersection>) -> bool { return debug_vec(ident, vec3<f32>(select(0., 1., value)), iteration, out_isection); }
fn debug_u32(ident: u32, value: u32, iteration: u32, out_isection: ptr<function, Intersection>) -> bool { return debug_vec(ident, vec3<f32>(get_debug_color(value)), iteration, out_isection); }

const do_debug: bool = true;

