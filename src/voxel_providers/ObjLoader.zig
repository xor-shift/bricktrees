const std = @import("std");

const dyn = @import("dyn");
const qov = @import("qov");
const wgm = @import("wgm");

const IThing = @import("../IThing.zig");
const IVoxelProvider = @import("../IVoxelProvider.zig");

const OBJFile = @import("../OBJFile.zig");

const PackedVoxel = qov.PackedVoxel;

const g = &@import("../main.zig").g;

const Self = @This();

pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IVoxelProvider });

file: OBJFile,
origin: [3]isize,
scale: u16 = 128,

pub fn init(relative_file_path: []const u8, origin: [3]isize) !Self {
    const obj_file = try OBJFile.from_file(relative_file_path, 16, g.alloc);

    return .{
        .file = obj_file,
        .origin = origin,
    };
}

fn overlap_info_for_range(self: Self, range: IVoxelProvider.VoxelRange) ?IVoxelProvider.OverlapInfo {
    return IVoxelProvider.overlap_info(range, .{
        .origin = self.origin,
        .volume = wgm.div([_]usize{65535} ** 3, self.scale),
    });
}

pub fn status_for_region(self: *Self, range: IVoxelProvider.VoxelRange) IVoxelProvider.RegionStatus {
    const info = self.overlap_info_for_range(range) orelse return .empty;
    _ = info;

    return .want_draw;
}

fn range_process_faces(
    self: Self,
    oinfo: IVoxelProvider.OverlapInfo,
    out: []PackedVoxel,
    out_volume: [3]usize,
    faces: []const [3]u32,
) void {
    const ml_origin_z = wgm.sub(oinfo.global_origin, self.origin);
    if (wgm.compare(.some, ml_origin_z, .less_than, [_]isize{0} ** 3)) return;
    const ml_origin = wgm.cast(u16, ml_origin_z).?;

    var processed: usize = 0;
    for (faces) |face| {
        for (face) |index| {
            const raw_vertex = self.file.vertices[index];

            if (wgm.compare(.some, wgm.cast(isize, raw_vertex).?, .less_than, oinfo.global_origin)) return;
            if (wgm.compare(.some, wgm.cast(isize, raw_vertex).?, .greater_than_equal, wgm.add(
                oinfo.global_origin,
                wgm.cast(isize, oinfo.volume).?,
            ))) return;

            const ol_vertex = wgm.div(wgm.sub(raw_vertex, ml_origin), self.scale);

            const i = wgm.cast(usize, ol_vertex).?;
            out[wgm.to_idx(i, out_volume)] = PackedVoxel.air;
            processed += 1;
        }
    }
}

pub fn draw_voxels(self: *Self, range: IVoxelProvider.VoxelRange, out: []PackedVoxel) void {
    const info = self.overlap_info_for_range(range) orelse return;

    var iterator = self.file.iterate_range(.{
        .start = wgm.cast(u16, wgm.mulew(info.local_origin, wgm.cast(usize, self.scale).?)).?,
        .end = wgm.cast(u16, wgm.mulew(
            wgm.add(info.local_origin, wgm.sub(info.volume, 1)),
            wgm.cast(usize, self.scale).?,
        )).?,
    });

    while (iterator.next()) |res| {
        const node = self.file.tree[res.node];
        const faces = self.file.faces[node.face_offset .. node.face_offset + node.face_count];
        self.range_process_faces(
            info,
            out,
            range.volume,
            faces,
        );
    }
}
