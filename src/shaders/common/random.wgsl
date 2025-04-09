var<private> random_schedule_ctr: u32 = 0;
var<private> random_schedule: array<u32, 16>;

fn rotl(x: u32, k: u32) -> u32 {
    return (x << k) | (x >> (32u - k));
}

fn xoroshiro_64ss_next(sp: ptr<function, vec2<u32>>) -> u32 {
    let s = *sp;
    let s0 = s[0];
    let s1 = s[1] ^ s0;
    let result = rotl(s0 * 0x9E3779BBu, 5u) * 5u;

    *sp = vec2<u32>(
        rotl(s0, 26u) ^ s1 ^ (s1 << 9u),
        rotl(s1, 13u),
    );

    return result;
}

// LGTM
fn init_random(pixel: vec2<u32>, rs: array<u32, 8>) {
    var state = vec2<u32>(
        ((pixel.x | (pixel.x << 16)) * 13) ^ rs[6],
        ((pixel.y | (pixel.y << 16)) * 13) ^ rs[7],
    );
    xoroshiro_64ss_next(&state);
    xoroshiro_64ss_next(&state);

    state.x ^= rs[5];
    state.y ^= rs[5];

    random_schedule[0] = rs[0] ^ xoroshiro_64ss_next(&state);
    random_schedule[1] = rs[1] ^ xoroshiro_64ss_next(&state);
    random_schedule[2] = rs[2] ^ xoroshiro_64ss_next(&state);
    random_schedule[3] = rs[3] ^ xoroshiro_64ss_next(&state);
    random_schedule[4] = rs[4] ^ xoroshiro_64ss_next(&state);
    // random_schedule[5] = rs[5] ^ xoroshiro_64ss_next(&state);
}

fn next_u32() -> u32 {
    let ret = random_schedule[random_schedule_ctr % 5u];
    random_schedule_ctr += 1u;
    return ret;
}

fn next_f32_uniform() -> f32 {
    return ldexp(f32(next_u32() & 0xFFFFFF), -24); // sticking to the classics
}

fn uniform_to_normal(sample: vec2<f32>) -> vec2<f32> {
    let r = sqrt(-2.0 * log(sample.x));
    let sc = vec2<f32>(
        sin(2 * M_PI * sample.y),
        cos(2 * M_PI * sample.y),
    );

    return r * sc;
}

fn next_two_normal() -> vec2<f32> {
    let sample = vec2<f32>(
        next_f32_uniform(),
        next_f32_uniform(),
    );
    return uniform_to_normal(sample);
}

fn next_unit_vector() -> vec3<f32> {
    let theta = next_f32_uniform() * 2 * M_PI;

    let cos_phi = 2 * next_f32_uniform() - 1;
    let sin_phi = 1 - cos_phi * cos_phi;

    return vec3<f32>(
        sin(theta) * sin_phi,
        cos(theta) * sin_phi,
        cos_phi,
    );
}
