@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@group(1) @binding(0) var texture_radiance: texture_storage_2d<bgra8unorm, write>;

@group(2) @binding(0) var brickgrid: texture_3d<u32>;
// @group(2) @binding(1) var bricktrees: binding_array<array<u32>>;
@group(2) @binding(2) var brickmaps: binding_array<texture_3d<u32>>;

@compute @workgroup_size(8, 8, 1) fn cs_main(
    @builtin(global_invocation_id)   global_id: vec3<u32>,
    @builtin(workgroup_id)           workgroup_id: vec3<u32>,
    @builtin(local_invocation_id)    local_id:  vec3<u32>,
    @builtin(local_invocation_index) local_idx: u32,
) {
    let pixel = global_id.xy;
    textureStore(
        texture_radiance,
        pixel,
        vec4<f32>(
            vec2<f32>(pixel) / vec2<f32>(uniforms.width, uniforms.height),
            0., 1.,
        ),
    );
}
