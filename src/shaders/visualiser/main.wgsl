struct Uniforms {
    width: f32,
    height: f32,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(1) @binding(0) var samp: sampler;
@group(1) @binding(1) var text: texture_2d<f32>;

struct VertexOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

struct HardcodedVertex {
    pos: vec2<f32>,
    uv: vec2<f32>,
};

@vertex fn vs_main(
    @builtin(vertex_index) vertex_index : u32,
) -> VertexOut {
    var vertices = array<HardcodedVertex, 6>(
        HardcodedVertex(vec2<f32>(-1.0, 1.0 ), vec2<f32>(0.0, 0.0)),
        HardcodedVertex(vec2<f32>(-1.0, -1.0), vec2<f32>(0.0, 1.0)),
        HardcodedVertex(vec2<f32>(1.0 , -1.0), vec2<f32>(1.0, 1.0)),
        HardcodedVertex(vec2<f32>(1.0 , -1.0), vec2<f32>(1.0, 1.0)),
        HardcodedVertex(vec2<f32>(1.0 , 1.0 ), vec2<f32>(1.0, 0.0)),
        HardcodedVertex(vec2<f32>(-1.0, 1.0 ), vec2<f32>(0.0, 0.0)),
    );

    return VertexOut(
        vec4<f32>(vertices[vertex_index].pos, 0.0, 1.0),
        vertices[vertex_index].uv,
    );
}

@fragment fn fs_main(in: VertexOut) -> @location(0) vec4f {
    let sample = textureSample(text, samp, in.uv);
    return sample;
}
