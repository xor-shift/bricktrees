if you are seeing this repo on git, how?
im pushing there so as to not lose work in case i somehow lose my disks

if you are seeing these two lines, i've not yet forked cimgui or otherwise have not made anything to automate the imconfig.h stuff.

you need to cd into `thirdparty/cimgui/generator` and run: `bash generator.sh -c -DIMGUI_USER_CONFIG='"../../../lib/imgui/imconfig.h"'`

# Structure

- `lib/blas` - Linear algebra stuff.
- `lib/gfx/wgpu` - my own Zig bindings for _webgpu\_headers_ (`webgpu.h`) + `wgpu.h` (native extensions provided by _wgpu.rs_).
- `lib/gfx/sdl` - WIP and very incomplete Zig bindings for SDL3.
- `lib/gfx/imgui` - WIP Zig bindings for ImGui with a WebGPU (for rendering) + SDL3 (for events) backend.
- `lib/qoi` - QoI support. Will be extended later on for voxel storage.
- `src/brick` - Brickmaps -- WIP.
- `src/shaders` - Shaders for brickmaps. Must be run through by `merge_shaders.nu` before they're usable.
- `src/things/gpu.zig` - Not yet sure as to what exactly this should encompass but yeah.

