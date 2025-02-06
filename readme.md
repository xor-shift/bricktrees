if you are seeing this line and the one below, i've not yet forked cimgui or otherwise have not done anything to automate the imconfig.h stuff.

you need to cd into `thirdparty/cimgui/generator` and run: `bash generator.sh -c -DIMGUI_USER_CONFIG='"../../../lib/imgui/imconfig.h"'`

# Structure

- `lib/wgm` - Linear algebra stuff.
- `lib/gfx/wgpu` - my own Zig bindings for _webgpu\_headers_ (`webgpu.h`) + `wgpu.h` (native extensions provided by _wgpu.rs_).
- `lib/gfx/sdl` - WIP and very incomplete Zig bindings for SDL3.
- `lib/gfx/imgui` - WIP Zig bindings for ImGui with a WebGPU (for rendering) + SDL3 (for events) backend.
- `lib/qoi` - QoI support. Will be extended later on for voxel storage.
- `src/brick` - Brickmaps -- WIP.
- `src/shaders` - Shaders for brickmaps. Must be run through by `merge_shaders.nu` before they're usable.
- `src/things/gpu.zig` - Not yet sure as to what exactly this should encompass but yeah.

# Note to Self: Statement Ordering

```zig
// the std module
const std = @import("std");

// modules registered to root in build.zig
const whatever = @import("whatever");

// local "modules"
const aeiou = @import("aeiou.zig");

// local types
const Aeiou = @import("Aeiou.zig");
const Foo = @import("../Foo.zig");

// types from modules
const Bar = aeiou.Bar;

// if applicable:
const Self = @This()

// exported types
pub const Baz = struct {};

pub const Quux = aeiou.Quuxer(1337);
```
