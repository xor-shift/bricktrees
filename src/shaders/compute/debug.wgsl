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

const do_debug: bool = true;
var<private> debug_out: vec3<f32>;
var<private> did_debug: bool = false;

fn debug_vec(ident: u32, iteration: u32, value: vec3<f32>) -> bool {
    if (uniforms.debug_mode != ident) { return false; }
    if (uniforms.debug_level != iteration) { return false; }

    debug_out = value;

    did_debug = true;

    return true;
}

fn debug_bool(ident: u32, iteration: u32, value: bool) -> bool { return debug_vec(ident, iteration, vec3<f32>(select(0., 1., value))); }

fn debug_u32(ident: u32, iteration: u32, value: u32) -> bool { return debug_vec(ident, iteration, vec3<f32>(get_debug_color(value))); }

fn debug_f32(ident: u32, iteration: u32, value: f32) -> bool { return debug_vec(ident, iteration, vec3<f32>(value)); }

fn debug_jet(ident: u32, iteration: u32, value: f32) -> bool {
    var r = array<f32, 5>(0, 0, 0, 1, 1);
    var g = array<f32, 5>(0, 1, 1, 1, 0);
    var b = array<f32, 5>(1, 1, 0, 0, 0);

    let gt = clamp(value * 5, 0., 5.);
    let i = u32(trunc(gt));

    let t = gt - f32(i);

    let v = vec3<f32>(
        r[i] * (1 - t) + r[i + 1] * t,
        g[i] * (1 - t) + g[i + 1] * t,
        b[i] * (1 - t) + b[i + 1] * t,
    );

    return debug_vec(ident, iteration, v);
}

