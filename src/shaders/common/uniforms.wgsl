struct Uniforms {
    transform: mat4x4<f32>,
    inverse_transform: mat4x4<f32>,

    dims: vec2<f32>,
    debug_mode: u32,
    debug_level: u32,

    pos: vec3<f32>,
    debug_variable_0: u32,

    brickgrid_origin: vec3<i32>,
    debug_variable_1: u32,
}
