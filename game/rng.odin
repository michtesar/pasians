package game

// splitmix64, written out here rather than taken from core:math/rand so a
// seed deals the same cards on every version, compiler and machine. Daily
// deals depend on that: changing anything in this file changes them all.
Rng :: struct {
  state: u64,
}

rng_next :: proc(r: ^Rng) -> u64 {
  r.state += 0x9e3779b97f4a7c15
  z := r.state
  z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
  z = (z ~ (z >> 27)) * 0x94d049bb133111eb
  return z ~ (z >> 31)
}

// Uniform value in [0, n) without modulo bias.
rng_below :: proc(r: ^Rng, n: u64) -> u64 {
  threshold := (max(u64) - n + 1) % n
  for {
    x := rng_next(r)
    if x >= threshold {
      return x % n
    }
  }
}
