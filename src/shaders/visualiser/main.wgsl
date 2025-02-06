@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(1) @binding(0) var samp: sampler;
@group(1) @binding(1) var text: texture_2d<f32>;

struct VertexOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

struct HardcodedVertex {
    pos: vec3<f32>,
    uv: vec2<f32>,
};

@vertex fn vs_main(
    @builtin(vertex_index) vertex_index : u32,
) -> VertexOut {
    var vertices = array<HardcodedVertex, 6>(
        HardcodedVertex(vec3<f32>(-1.0,  1.0, 1), vec2<f32>(0.0, 0.0)),
        HardcodedVertex(vec3<f32>(-1.0, -1.0, 2), vec2<f32>(0.0, 1.0)),
        HardcodedVertex(vec3<f32>( 1.0, -1.0, 3), vec2<f32>(1.0, 1.0)),
        HardcodedVertex(vec3<f32>( 1.0, -1.0, 3), vec2<f32>(1.0, 1.0)),
        HardcodedVertex(vec3<f32>( 1.0,  1.0, 2), vec2<f32>(1.0, 0.0)),
        HardcodedVertex(vec3<f32>(-1.0,  1.0, 1), vec2<f32>(0.0, 0.0)),
    );

    // Leaving this in from me trying to debug why my transforms were fucked.
    // Turns out matn<T> is column-major...
    // let pos = uniforms.transform * vec4<f32>(vertices[vertex_index].pos, 1);
    return VertexOut(
        // pos,
        vec4<f32>(vertices[vertex_index].pos.xy, 0.5, 1),
        vertices[vertex_index].uv,
    );
}

@fragment fn fs_main(in: VertexOut) -> @location(0) vec4f {
    let sample = textureSample(text, samp, in.uv);
    return sample;

    // return vec4<f32>(vec3<f32>(in.uv, in.pos.w), 1);
}
