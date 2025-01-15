// straight off wikipedia
pub fn mul_strassen_2x2_2x2(out: anytype, lhs: anytype, rhs: anytype) void {
    const a = lhs.el;
    const b = rhs.el;

    const m1 = (a[0][0] + a[1][1]) * (b[0][0] + b[1][1]);
    const m2 = (a[1][0] + a[1][1]) * b[0][0];
    const m3 = a[0][0] * (b[0][1] - b[1][1]);
    const m4 = a[1][1] * (b[1][0] - b[0][0]);
    const m5 = (a[0][0] + a[0][1]) * b[1][1];
    const m6 = (a[1][0] - a[0][0]) * (b[0][0] + b[0][1]);
    const m7 = (a[0][1] - a[1][1]) * (b[1][0] + b[1][1]);

    out.el[0][0] = m1 + m4 - m5 + m7;
    out.el[0][1] = m3 + m5;
    out.el[1][0] = m2 + m4;
    out.el[1][1] = m1 - m2 + m3 + m6;
}
