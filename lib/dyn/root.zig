const std = @import("std");

const dyn = @import("root.zig");

const log_stuff: bool = false;

fn __dyn_pure_virtual() void {
    @panic("pure virtual called");
}

const TypeInfo = struct {
    name: []const u8,
    no_virtuals: usize,
};

const VTableEntry = union {
    NoInterfaces: usize,
    OffsetToTop: usize,
    TypeInfo: *const TypeInfo,
    Function: *const fn () void,
};

fn try_normalize(comptime fun: anytype) ?type {
    if (@TypeOf(fun) == type) switch (@typeInfo(fun)) {
        .Fn => |v| {
            if (v.is_generic) {
                if (log_stuff) @compileLog("generic functions can't be virtual");
                return null;
            }

            if (v.is_var_args) {
                if (log_stuff) @compileLog("variadic functions can't be virtual");
                return null;
            }

            if (v.calling_convention != .Unspecified) {
                if (log_stuff) @compileLog("virtual functions must not have a specified calling convention");
                return null;
            }

            const Ret = if (v.return_type) |w| w else {
                if (log_stuff) @compileLog("virtual functions must have simple return types");
                return null;
            };

            if (v.params.len == 0) {
                if (log_stuff) @compileLog("virtual functions must have at least 1 parameter");
                return null;
            }

            for (v.params) |p| {
                if (p.type == null or p.is_generic) {
                    if (log_stuff) @compileLog("virtual functions may not have generic parameters");
                    return null;
                }

                if (p.is_noalias) {
                    if (log_stuff) @compileLog("noalias parameters in virtual functions are not yet supported");
                    return null;
                }
            }

            if (@typeInfo(v.params[0].type.?) != .Struct or !@hasDecl(v.params[0].type.?, "DynFatPtrTag")) {
                if (log_stuff) @compileLog("virtual functions' first parameter must be a fat pointer");
                return null;
            }

            _ = Ret;

            return fun;
        },
        else => return null,
    } else switch (@typeInfo(@TypeOf(fun))) {
        .Fn => return try_normalize(@TypeOf(fun)),
        else => return null,
    }
}

const VirtualFnEntry = struct {
    name: []const u8,
    ty: type,
};

fn virtual_by_name(comptime IFace: type, comptime decl_name: []const u8) ?VirtualFnEntry {
    const NormFn = try_normalize(@field(IFace, decl_name)) orelse {
        if (log_stuff) {
            @compileLog(std.fmt.comptimePrint("failed to normalize {any}::{s}: {any}", .{
                IFace,
                decl_name,
                @TypeOf(@field(IFace, decl_name)),
            }));
        }
        return null;
    };

    if (log_stuff) {
        @compileLog(std.fmt.comptimePrint("{any}::{s} resolves to {any}", .{
            IFace,
            decl_name,
            NormFn,
        }));
    }

    return .{
        .name = decl_name,
        .ty = NormFn,
    };
}

fn write_virtual_fn_types(comptime IFace: type, types: []VirtualFnEntry) usize {
    if (log_stuff) {
        @compileLog(std.fmt.comptimePrint("figuring out the virtual functions of {any}...", .{IFace}));
    }

    var idx: usize = 0;
    for (@typeInfo(IFace).Struct.decls) |decl_info| {
        const decl_name = decl_info.name;

        const virt = virtual_by_name(IFace, decl_name) orelse continue;
        types[idx] = virt;
        idx += 1;
    }

    return idx;
}

fn virtual_fn_count(comptime IFace: type) usize {
    const info = @typeInfo(IFace).Struct;
    var tmp: [info.decls.len]VirtualFnEntry = undefined;
    return write_virtual_fn_types(IFace, tmp[0..]);
}

fn virtual_fns(comptime IFace: type) [virtual_fn_count(IFace)]VirtualFnEntry {
    var tmp: [virtual_fn_count(IFace)]VirtualFnEntry = undefined;
    _ = write_virtual_fn_types(IFace, tmp[0..]);
    return tmp;
}

pub fn IFaceStuff(comptime IFace: type) type {
    return struct {
        const type_info: TypeInfo = .{
            .name = @typeName(IFace),
            .no_virtuals = virtual_fn_count(IFace),
        };

        const vtable: [2 + type_info.no_virtuals]VTableEntry = blk: {
            var ret: [2 + type_info.no_virtuals]VTableEntry = [2]VTableEntry{
                .{ .OffsetToTop = 0 },
                .{ .TypeInfo = &type_info },
            } ++ [1]VTableEntry{
                .{ .Function = __dyn_pure_virtual },
            } ** type_info.no_virtuals;

            for (virtual_fns(IFace), 0..) |fun, i| {
                const field = @field(IFace, fun.name);

                if (@TypeOf(field) == type) continue;

                if (log_stuff) {
                    @compileLog(std.fmt.comptimePrint("detected default function for {any}::{s}", .{
                        IFace,
                        fun.name,
                    }));
                }

                ret[2 + i].Function = @ptrCast(&field);
            }

            if (log_stuff) {
                @compileLog(std.fmt.comptimePrint("the vtable of {s} has {d} entries:", .{
                    @typeName(IFace),
                    2 + type_info.no_virtuals,
                }));
            }

            break :blk ret;
        };
    };
}

/// note to self: THIS IS NOT A THUNK!!!!!!!!!!
fn ProxyOMatic(comptime IFace: type, comptime Concrete: type, comptime name: []const u8) ?virtual_by_name(IFace, name).?.ty {
    if (!@hasDecl(Concrete, name)) return null;

    const VFn = virtual_by_name(IFace, name).?.ty;
    const vfn_info = @typeInfo(VFn).Fn;

    const concrete_fn = @field(Concrete, name);
    const do_deref = @typeInfo(@typeInfo(@TypeOf(concrete_fn)).Fn.params[0].type.?) != .Pointer;

    return switch (vfn_info.params.len) {
        1 => struct {
            pub fn aufruf(
                self: vfn_info.params[0].type.?,
            ) vfn_info.return_type.? {
                const concrete = self.get_concrete(Concrete);
                const _self = if (do_deref) concrete.* else concrete;
                return @call(.auto, concrete_fn, .{_self});
            }
        }.aufruf,
        2 => struct {
            pub fn aufruf(
                self: vfn_info.params[0].type.?,
                a0: vfn_info.params[1].type.?,
            ) vfn_info.return_type.? {
                const concrete = self.get_concrete(Concrete);
                const _self = if (do_deref) concrete.* else concrete;
                return @call(.auto, concrete_fn, .{ _self, a0 });
            }
        }.aufruf,
        3 => struct {
            pub fn aufruf(
                self: vfn_info.params[0].type.?,
                a0: vfn_info.params[1].type.?,
                a1: vfn_info.params[2].type.?,
            ) vfn_info.return_type.? {
                const concrete = self.get_concrete(Concrete);
                const _self = if (do_deref) concrete.* else concrete;
                return @call(.auto, concrete_fn, .{ _self, a0, a1 });
            }
        }.aufruf,
        4 => struct {
            pub fn aufruf(
                self: vfn_info.params[0].type.?,
                a0: vfn_info.params[1].type.?,
                a1: vfn_info.params[2].type.?,
                a2: vfn_info.params[3].type.?,
            ) vfn_info.return_type.? {
                const concrete = self.get_concrete(Concrete);
                const _self = if (do_deref) concrete.* else concrete;
                return @call(.auto, concrete_fn, .{ _self, a0, a1, a2 });
            }
        }.aufruf,
        else => @compileError("unsupported number of arguments"),
    };
}

pub fn ConcreteStuff(comptime Concrete: type, comptime interfaces: anytype) type {
    return struct {
        const implemented_interfaces: [interfaces.len]type = interfaces;

        const vtable_len = blk: {
            var acc: usize = 0;

            for (implemented_interfaces) |IFace| {
                acc += IFace.DynStatic.vtable.len;
            }

            break :blk acc + 1;
        };

        pub const vtable: [vtable_len]VTableEntry = blk: {
            var ret: [vtable_len]VTableEntry = undefined;

            ret[0] = .{ .NoInterfaces = implemented_interfaces.len };

            var offset: usize = 1;
            for (implemented_interfaces) |IFace| {
                const local_vtable = IFace.DynStatic.vtable;
                @memcpy(ret[offset .. offset + local_vtable.len], &local_vtable);
                ret[offset].OffsetToTop = offset;

                for (virtual_fns(IFace), 0..) |fun, i| {
                    const proxy = ProxyOMatic(IFace, Concrete, fun.name) orelse continue;
                    ret[offset + 2 + i] = .{ .Function = @ptrCast(&proxy) };
                }

                offset += local_vtable.len;
            }

            if (log_stuff) {
                @compileLog(std.fmt.comptimePrint("the vtable of {s} has {d} entries:", .{
                    @typeName(Concrete),
                    vtable_len,
                }));
            }

            break :blk ret;
        };
    };
}

pub fn Fat(comptime IFaceArg: type) type {
    const _IFace, const _is_const, const _is_ptr = switch (@typeInfo(IFaceArg)) {
        .Pointer => |v| .{ v.child, v.is_const, true },
        else => .{ IFaceArg, true, false },
    };

    switch (@typeInfo(_IFace)) {
        .Struct => if (!@hasDecl(_IFace, "DynStatic")) {
            @compileError(std.fmt.comptimePrint("{any} is not a virtual type", .{_IFace}));
        },
        else => @compileError(std.fmt.comptimePrint("{any} is not a supported type", .{_IFace})),
    }

    _ = _is_ptr;

    return struct {
        const DynFatPtrTag: type = void;

        const Self = @This();
        const IFace = _IFace;

        const is_const = _is_const;

        this_ptr: *const anyopaque,
        vtable_ptr: [*]const VTableEntry,

        pub fn init(arg: anytype) Self {
            const T = @TypeOf(arg);
            if (@typeInfo(T) != .Pointer) {
                @compileError("fat pointers must be initialized by pointers to concrete types");
            }

            const got_const = @typeInfo(T).Pointer.is_const;

            if (got_const and !is_const) {
                @compileError("can't initialize a fat pointer of non-const interface type with a const pointer to a concrete type");
            }

            const Concrete = @typeInfo(T).Pointer.child;

            const vtable_offset = comptime blk: {
                var ret: usize = 1;
                for (Concrete.DynStatic.implemented_interfaces) |IIFace| {
                    if (IIFace == IFace) {
                        break :blk ret;
                    }

                    ret += IIFace.DynStatic.type_info.no_virtuals + 2;
                }

                @compileError(std.fmt.comptimePrint("the concrete class {any} does not implement {any}", .{
                    Concrete,
                    IFace,
                }));
            };

            const vtable = Concrete.DynStatic.vtable[vtable_offset .. vtable_offset + IFace.DynStatic.type_info.no_virtuals + 2];
            if (log_stuff) {
                @compileLog(std.fmt.comptimePrint("vtable {any} for {any} has {any} entries", .{
                    IFace,
                    Concrete,
                    vtable.len,
                }));
            }

            return .{
                .this_ptr = @ptrCast(arg),
                .vtable_ptr = vtable.ptr,
            };
        }

        pub fn add_const(self: Self) Fat(IFace) {
            return .{
                .this_ptr = self.this_ptr,
                .vtable_ptr = self.vtable_ptr,
            };
        }

        /// 'di' as in "dispatch with index"
        pub fn di(self: Self, comptime idx: usize, args: anytype) @typeInfo(virtual_fns(IFace)[idx].ty).Fn.return_type.? {
            const Fn = virtual_fns(IFace)[idx].ty;

            const raw_ptr = self.vtable_ptr[2 + idx].Function;
            const fn_ptr: *const Fn = @ptrCast(raw_ptr);

            const This = @typeInfo(Fn).Fn.params[0].type.?;

            if (This == Fat(*IFace)) {
                if (is_const) {
                    @compileError("cant call a non-const virtual function through a constant fat pointer");
                }
                return @call(.auto, fn_ptr, .{self} ++ args);
            } else {
                return @call(.auto, fn_ptr, .{self.add_const()} ++ args);
            }
        }

        /// 'd' as in "dispatch through the function name"
        pub fn d(self: Self, comptime fun_name: []const u8, args: anytype) @typeInfo(virtual_by_name(IFace, fun_name).?.ty).Fn.return_type.? {
            const idx = comptime blk: {
                for (virtual_fns(IFace), 0..) |vfun, i| {
                    if (std.mem.eql(u8, vfun.name, fun_name)) break :blk i;
                }
                unreachable;
            };
            return self.di(idx, args);
        }

        pub fn get_concrete(self: Self, comptime Concrete: type) if (is_const) *const Concrete else *Concrete {
            const base: *const Concrete = @ptrCast(@alignCast(self.this_ptr));
            if (!is_const) return @constCast(base);
            return base;
        }

        pub fn sideways_cast(self: Self, comptime IOther: type) ?Fat(if (is_const) *const IOther else *IOther) {
            const start = self.vtable_ptr - self.vtable_ptr[0].OffsetToTop;
            var offset: usize = 1;
            for (0..start[0].NoInterfaces) |_| {
                const offset_to_top = start[offset].OffsetToTop;
                std.debug.assert(offset_to_top == offset);

                const type_info = start[offset + 1].TypeInfo;

                if (type_info == &IOther.DynStatic.type_info) {
                    return .{
                        .this_ptr = self.this_ptr,
                        .vtable_ptr = start + offset,
                    };
                }

                offset += 2 + type_info.no_virtuals;
            }

            return null;
        }
    };
}

test {
    std.testing.refAllDecls(@import("test.zig"));
}
