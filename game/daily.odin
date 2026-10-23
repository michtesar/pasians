package game

// FreeCell's legendary unsolvable deal, kept out of the daily rotation.
FREECELL_UNSOLVABLE :: 11982

DAILY_SOLVER_BUDGET :: 100_000
DAILY_ATTEMPTS :: 32

fnv1a :: proc(s: string) -> u64 {
  h: u64 = 0xcbf29ce484222325
  for i in 0 ..< len(s) {
    h = (h ~ u64(s[i])) * 0x100000001b3
  }
  return h
}

// Stable hash of the date ("YYYY-MM-DD") and mode, pushed through splitmix
// so neighbouring days land far apart.
daily_hash :: proc(date: string, mode: Mode, draw_count: int) -> u64 {
  r := Rng{fnv1a(date) ~ (u64(mode) << 56) ~ (u64(draw_count) << 48)}
  return rng_next(&r)
}

Daily :: struct {
  seed:   u64, // Klondike seed or FreeCell game number
  proven: bool, // the solver found a win
}

// Today's deal. Klondike tries seed, seed+1, ... until the solver proves one
// winnable; if none is proven within DAILY_ATTEMPTS it is a daily challenge
// that may not have a solution. FreeCell maps onto the 32000 MS deals, all
// solvable but one.
daily :: proc(date: string, mode: Mode, draw_count: int) -> Daily {
  h := daily_hash(date, mode, draw_count)
  switch mode {
  case .FreeCell:
    n := h % 32000 + 1
    if n == FREECELL_UNSOLVABLE {
      n += 1
    }
    return {n, true}
  case .Klondike:
    for attempt in 0 ..< u64(DAILY_ATTEMPTS) {
      if solve(deal_klondike(h + attempt, draw_count), DAILY_SOLVER_BUDGET) == .Solved {
        return {h + attempt, true}
      }
    }
    return {h, false}
  }
  unreachable()
}

new_game :: proc(mode: Mode, seed: u64, draw_count: int) -> Game {
  switch mode {
  case .FreeCell:
    return deal_freecell(u32(seed))
  case .Klondike:
    return deal_klondike(seed, draw_count)
  }
  unreachable()
}
