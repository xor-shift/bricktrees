struct Uniforms {
    width: f32,
    height: f32,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(1) @binding(0) var samp: sampler;
@group(1) @binding(1) var text: texture_2d<f32>;

struct VertexIn {
    @location(0) pos: vec3<f32>,
    @location(1) uv: vec2<f32>,
}

struct VertexOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec3<f32>,
}

@vertex fn vs_main(
    @builtin(vertex_index) vertex_index : u32,
    vert: VertexIn,
) -> VertexOut {
    var vertices = array<vec2<f32>, 6>(
        vec2<f32>(-1.0, 1.0),
        vec2<f32>(-1.0, -1.0),
        vec2<f32>(1.0, -1.0),
        vec2<f32>(1.0, -1.0),
        vec2<f32>(1.0, 1.0),
        vec2<f32>(-1.0, 1.0),
    );

    var colors = array<vec3<f32>, 6>(
        vec3<f32>(1.0, 0.0, 0.0),
        vec3<f32>(0.0, 1.0, 0.0),
        vec3<f32>(0.0, 0.0, 1.0),
        vec3<f32>(1.0, 0.0, 0.0),
        vec3<f32>(0.0, 1.0, 0.0),
        vec3<f32>(0.0, 0.0, 1.0),
    );

    return VertexOut(
        vec4<f32>(vert.pos, 1.0),
        vert.uv,
        colors[vertex_index],
    );
}

@fragment fn fs_main(in: VertexOut) -> @location(0) vec4f {
    let sample = textureSample(text, samp, in.uv);
    //return vec4<f32>(sample.xy + in.uv, sample.zw);
    return sample;
}

