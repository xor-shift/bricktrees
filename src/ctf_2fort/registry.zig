const std = @import("std");

const blas = @import("../blas/blas.zig");

pub const BlockBehaviour = struct {};

pub const Material = union(enum) {
    Invisible: void,

    Diffuse: struct {
        color: blas.Vec3d,
    },

    Translucent: struct {
        attenuation: blas.Vec3d = blas.vec3d(0, 0, 0),
    },

    Metal: struct {
        attenuation: blas.Vec3d = blas.vec3d(0, 0, 0),
        roughness: f64,
    },
};

pub const BlockProperties = struct {
    // TODO: stuff like breakability

    material: Material,
};

pub const Block = struct {
    id: []const u8,
    behaviour: BlockBehaviour,
    properties: BlockProperties,

    pub fn clone(self: Block, alloc: std.mem.Allocator) !Block {
        return .{
            .id = try alloc.dupe(u8, self.id),
            .behaviour = self.behaviour,
            .properties = self.properties,
        };
    }

    pub fn deinit(self: Block, alloc: std.mem.Allocator) void {
        alloc.free(self.id);
    }
};

const Self = @This();

alloc: std.mem.Allocator,
registered_blocks: std.ArrayListUnmanaged(Block),
id_numeric_translation: std.StringHashMapUnmanaged(usize),

pub fn register(self: *Self, block: Block) !usize {
    const id = self.registered_blocks.items.len;

    self.registered_blocks.append(self.alloc, try block.clone(self.alloc));

    return id;
}
