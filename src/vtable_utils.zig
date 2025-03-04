const std = @import("std");

fn to_params(comptime args: anytype) [args.len]std.builtin.Type.Fn.Param {
    var ret: [args.len]std.builtin.Type.Fn.Param = undefined;
    for (args, 0..) |T, i| {
        ret[i] = .{ .is_generic = false, .is_noalias = false, .type = T };
    }

    return ret;
}

pub fn FnType(comptime R: type, comptime args: anytype) type {
    return @Type(.{ .Fn = .{
        .calling_convention = .auto,
        .is_generic = false,
        .is_var_args = false,
        .return_type = R,
        .params = &to_params(args),
    } });
}

pub fn FnType2(comptime R: type, comptime params: []const std.builtin.Type.Fn.Param) type {
    return @Type(.{ .Fn = .{
        .calling_convention = .Unspecified,
        .is_generic = false,
        .is_var_args = false,
        .return_type = R,
        .params = params,
    } });
}

pub fn mk_vtable(
    comptime Concrete: type,
    comptime Trait: type,
    comptime name: []const u8,
    comptime Defaults: type,
) Trait {
    const Impl = struct {
        inline fn get_thing(self: *Trait) *Concrete {
            return @fieldParentPtr("vtable_" ++ name, self);
        }

        fn ReturnType(comptime fn_name: []const u8) type {
            const idx = std.meta.fieldIndex(Trait, fn_name).?;
            const T = std.meta.fields(Trait)[idx].type;
            const F = @typeInfo(T).Pointer.child;
            return @typeInfo(F).Fn.return_type.?;
        }

        inline fn make_call(
            self: *Trait,
            comptime fn_name: []const u8,
            args: anytype,
            comptime default: anytype,
        ) ReturnType(fn_name) {
            const thing = get_thing(self);
            const impl_name = "impl_" ++ name ++ "_" ++ fn_name;
            if (@hasDecl(Concrete, impl_name)) {
                const impl = @field(Concrete, impl_name);
                return @call(.auto, impl, .{thing} ++ args);
            } else {
                if (@TypeOf(default) == void) {
                    @compileError(std.fmt.comptimePrint("function \"{s}\" was missing from the concrete class but the trait doesn't have it defaulted", .{
                        fn_name,
                    }));
                }
                return @call(.auto, default, .{self} ++ args);
            }
        }

        pub fn fn_0(comptime fn_name: []const u8, comptime R: type, comptime params: []const std.builtin.Type.Fn.Param, comptime default: anytype) FnType2(R, params) {
            return struct {
                pub fn aufruf(self: *Trait) R {
                    return make_call(self, fn_name, .{}, default);
                }
            }.aufruf;
        }

        pub fn fn_1(comptime fn_name: []const u8, comptime R: type, comptime params: []const std.builtin.Type.Fn.Param, comptime default: anytype) FnType2(R, params) {
            return struct {
                pub fn aufruf(self: *Trait, a0: params[1].type.?) R {
                    return make_call(self, fn_name, .{a0}, default);
                }
            }.aufruf;
        }

        pub fn fn_2(comptime fn_name: []const u8, comptime R: type, comptime params: []const std.builtin.Type.Fn.Param, comptime default: anytype) FnType2(R, params) {
            return struct {
                pub fn aufruf(self: *Trait, a0: params[1].type.?, a1: params[2].type.?) R {
                    return make_call(self, fn_name, .{ a0, a1 }, default);
                }
            }.aufruf;
        }

        pub fn fn_3(comptime fn_name: []const u8, comptime R: type, comptime params: []const std.builtin.Type.Fn.Param, comptime default: anytype) FnType2(R, params) {
            return struct {
                pub fn aufruf(self: *Trait, a0: params[1].type.?, a1: params[2].type.?, a2: params[3].type.?) R {
                    return make_call(self, fn_name, .{ a0, a1, a2 }, default);
                }
            }.aufruf;
        }
    };

    var ret: Trait = undefined;
    inline for (std.meta.fields(Trait)) |field| {
        const fn_info = blk: {
            const ptr_info = switch (@typeInfo(field.type)) {
                .Pointer => |v| v,
                else => continue,
            };

            const fn_info = switch (@typeInfo(ptr_info.child)) {
                .Fn => |v| v,
                else => continue,
            };

            break :blk fn_info;
        };

        const default = if (@hasDecl(Defaults, field.name)) @field(Defaults, field.name) else {};

        const fun = switch (fn_info.params.len) {
            1 => Impl.fn_0(field.name, fn_info.return_type.?, fn_info.params, default),
            2 => Impl.fn_1(field.name, fn_info.return_type.?, fn_info.params, default),
            3 => Impl.fn_2(field.name, fn_info.return_type.?, fn_info.params, default),
            4 => Impl.fn_3(field.name, fn_info.return_type.?, fn_info.params, default),
            else => unreachable,
        };

        @field(ret, field.name) = fun;
    }

    return ret;
}
