struct Uniforms {
    dummy: u32,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage> vertices: array<vec3<f32>>;
@group(0) @binding(2) var<storage> faces: array<vec3<u32>>;

