pub fn Vec(comptime T: type) type {
    return struct {
        pub const Self = Vec(T);

        capacity: usize,
        items: []T,

        pub fn from_native(native_vec: anytype) Self {
            return if (native_vec.Size == 0)
                .{
                    .capacity = @intCast(native_vec.Capacity),
                    .items = &.{},
                }
            else
                .{
                    .capacity = @intCast(native_vec.Capacity),
                    .items = native_vec.Data[0..@as(usize, @intCast(native_vec.Size))],
                };
        }
    };
}

pub fn make_vec(native_vec: anytype) Vec(@TypeOf(native_vec.Data[0])) {
    const ReturnType = Vec(@TypeOf(native_vec.Data[0]));
    return ReturnType.from_native(native_vec);
}

