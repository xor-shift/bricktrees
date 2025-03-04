struct Uniforms {
    transform: mat4x4<f32>,
};

struct VertexIn {
    @location(0) pos: vec4<f32>,
    @location(1) color: vec4<f32>,
};

struct VertexOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec4<f32>,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@vertex fn vs_main(
    vertex: VertexIn,
    @builtin(vertex_index) vertex_index : u32,
) -> VertexOut {
    return VertexOut(
        uniforms.transform * vertex.pos,
        vertex.color,
    );
}

@fragment fn fs_main(in: VertexOut) -> @location(0) vec4f {
    return in.color;
}
