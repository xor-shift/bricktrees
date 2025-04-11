struct Uniforms {
    rs_0: u32,
    rs_1: u32,
    rs_2: u32,
    rs_3: u32,
    rs_4: u32,
    rs_5: u32,
    rs_6: u32,
    rs_7: u32,

    transform: mat4x4<f32>,
    inverse_transform: mat4x4<f32>,

    dims: vec2<f32>,
    _padding_1: u32,
    _padding_2: u32,

    debug_variable_0: u32,
    debug_variable_1: u32,
    debug_mode: u32,
    debug_level: u32,

    custom: vec4<u32>,
}

