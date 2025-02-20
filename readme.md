# Requirements

Check `flake.nix`.

`luajit` and `nu` are necessary for `cimgui`.

`nu` is additionally necessary for the shader scripts.

# Building

- Go to `thirdparty/wgpu-native` and run `cargo build` and `cargo build --release`
- Go to `thirdparty/SDL` and do:
    - `mkdir build-debug`
    - `cd build-debug`
    - `cmake -DCMAKE_BUILD_TYPE=Debug -DSDL_STATIC=ON -DSDL_WAYLAND=ON -DSDL_X11=ON ..`

    - `mkdir build-release`
    - `cd build-release`
    - `cmake -DCMAKE_BUILD_TYPE=Release -DSDL_STATIC=ON -DSDL_WAYLAND=ON -DSDL_X11=ON ..`

`CImgui` is handled automatically by `build.zig`.

`mustache-zig` is a Zig dependency so it is also handle by the `build.zig` file.

# Structure

There used to be a filetree of sorts here but I CBA to update it whenever there's something new or whenever sth changes.

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
