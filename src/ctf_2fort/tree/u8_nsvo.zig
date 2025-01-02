const std = @import("std");

fn bits_at_layer(comptime layer: usize) usize {
    return 1 << (layer * 3);
}

fn bits_for_layers(comptime no_layers: usize) usize {
    var ret: usize = 0;

    for (0..no_layers) |layer| ret += bits_at_layer(layer);

    return ret;
}

pub fn U8NSVOStorage(comptime no_layers: usize) type {
    return struct {};
}

/// The topmost layer, layer 0, won't be stored explicitly as it's a simple `!= 0` check on the second layer, layer 1.
/// The lowermost layer won't represent the voxel grid, as the tree stops just short of reaching the voxels.
/// The voxel grid this tree represents has a side-length of `2^(layers+1)`.
pub fn U8NSVO(comptime no_layers: usize) type {
    comptime std.debug.assert(layers != 0);

    return struct {
        pub const side_length = 1 << (layers + 1);

        data: []
    };
}
