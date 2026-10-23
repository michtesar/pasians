package game

Pile_Kind :: enum u8 {
  Stock,
  Waste,
  Foundation,
  Tableau,
}

Pile_Ref :: struct {
  kind:  Pile_Kind,
  index: int,
}

STOCK :: Pile_Ref{.Stock, 0}
WASTE :: Pile_Ref{.Waste, 0}

foundation :: proc(i: int) -> Pile_Ref {
  return {.Foundation, i}
}

tableau :: proc(i: int) -> Pile_Ref {
  return {.Tableau, i}
}

// The whole game is one value: copying it is a complete snapshot.
Klondike :: struct {
  stock:       Pile,
  waste:       Pile,
  foundations: [4]Pile,
  tableau:     [7]Pile,
  draw_count:  int, // 1 or 3
  moves:       int,
}

pile :: proc(g: ^Klondike, ref: Pile_Ref) -> ^Pile {
  switch ref.kind {
  case .Stock:
    return &g.stock
  case .Waste:
    return &g.waste
  case .Foundation:
    return &g.foundations[ref.index]
  case .Tableau:
    return &g.tableau[ref.index]
  }
  unreachable()
}

new_deck :: proc() -> (deck: [52]Card) {
  i := 0
  for suit in Suit {
    for rank in u8(ACE) ..= KING {
      deck[i] = {rank, suit, false}
      i += 1
    }
  }
  return
}

// Fisher-Yates driven by our own Rng, so a seed is a deal forever.
shuffle :: proc(deck: ^[52]Card, seed: u64) {
  r := Rng{seed}
  for i := 51; i > 0; i -= 1 {
    j := int(rng_below(&r, u64(i + 1)))
    deck[i], deck[j] = deck[j], deck[i]
  }
}

deal :: proc(seed: u64, draw_count := 1) -> (g: Klondike) {
  deck := new_deck()
  shuffle(&deck, seed)
  next := 0
  // Row by row, as dealt by hand: column c gets c+1 cards, the last face up.
  for row in 0 ..< 7 {
    for col in row ..< 7 {
      c := deck[next]
      next += 1
      c.face_up = col == row
      pile_push(&g.tableau[col], c)
    }
  }
  for next < 52 {
    pile_push(&g.stock, deck[next])
    next += 1
  }
  g.draw_count = draw_count
  return
}

// Turns draw_count cards from stock to waste, or turns the waste back over
// when the stock is empty. False when both are empty.
draw :: proc(g: ^Klondike) -> bool {
  if g.stock.len == 0 {
    if g.waste.len == 0 {
      return false
    }
    for g.waste.len > 0 {
      c := pile_pop(&g.waste)
      c.face_up = false
      pile_push(&g.stock, c)
    }
  } else {
    n := min(g.draw_count, g.stock.len)
    for _ in 0 ..< n {
      c := pile_pop(&g.stock)
      c.face_up = true
      pile_push(&g.waste, c)
    }
  }
  g.moves += 1
  return true
}

fits_foundation :: proc(dst: Pile, c: Card) -> bool {
  top, ok := pile_top(dst)
  if !ok {
    return c.rank == ACE
  }
  return top.suit == c.suit && c.rank == top.rank + 1
}

fits_tableau :: proc(dst: Pile, c: Card) -> bool {
  top, ok := pile_top(dst)
  if !ok {
    return c.rank == KING
  }
  return top.face_up && is_red(top) != is_red(c) && top.rank == c.rank + 1
}

// Face-up cards descending by one in alternating colours.
is_run :: proc(cards: []Card) -> bool {
  for i in 1 ..< len(cards) {
    a, b := cards[i - 1], cards[i]
    if !b.face_up || is_red(a) == is_red(b) || a.rank != b.rank + 1 {
      return false
    }
  }
  return true
}

// Moving `count` cards from the top of `from` onto `to`.
can_move :: proc(g: ^Klondike, from: Pile_Ref, count: int, to: Pile_Ref) -> bool {
  if from == to || count < 1 {
    return false
  }
  src := pile(g, from)
  if count > src.len {
    return false
  }
  switch from.kind {
  case .Stock:
    return false
  case .Waste, .Foundation:
    if count != 1 {
      return false
    }
  case .Tableau:
    if count > face_up_count(src^) {
      return false
    }
  }
  moving := src.cards[src.len - count:src.len]
  if !is_run(moving) {
    return false
  }
  dst := pile(g, to)
  switch to.kind {
  case .Stock, .Waste:
    return false
  case .Foundation:
    return count == 1 && fits_foundation(dst^, moving[0])
  case .Tableau:
    return fits_tableau(dst^, moving[0])
  }
  unreachable()
}

move :: proc(g: ^Klondike, from: Pile_Ref, count: int, to: Pile_Ref) -> bool {
  if !can_move(g, from, count, to) {
    return false
  }
  src, dst := pile(g, from), pile(g, to)
  start := src.len - count
  for i in start ..< src.len {
    pile_push(dst, src.cards[i])
  }
  src.len = start
  if from.kind == .Tableau && src.len > 0 {
    src.cards[src.len - 1].face_up = true
  }
  g.moves += 1
  return true
}

// The foundation that accepts `c`: its suit's pile, or the first empty one
// for an ace.
foundation_for :: proc(g: ^Klondike, c: Card) -> (Pile_Ref, bool) {
  for f, i in g.foundations {
    if fits_foundation(f, c) {
      return foundation(i), true
    }
  }
  return {}, false
}

send_to_foundation :: proc(g: ^Klondike, from: Pile_Ref) -> bool {
  if from.kind == .Foundation {
    return false
  }
  top, ok := pile_top(pile(g, from)^)
  if !ok {
    return false
  }
  to, found := foundation_for(g, top)
  return found && move(g, from, 1, to)
}

foundation_rank :: proc(g: ^Klondike, suit: Suit) -> u8 {
  for f in g.foundations {
    if f.len > 0 && f.cards[0].suit == suit {
      return u8(f.len)
    }
  }
  return 0
}

// A card can go up without ever being needed in the tableau again: aces and
// twos always, otherwise once both opposite-colour suits are up to rank-1,
// since those are the only cards that could still be placed on it.
is_safe :: proc(g: ^Klondike, c: Card) -> bool {
  if c.rank <= 2 {
    return true
  }
  for suit in Suit {
    if is_red(Card{suit = suit}) != is_red(c) && foundation_rank(g, suit) < c.rank - 1 {
      return false
    }
  }
  return true
}

// Sends every safe card up, repeating until nothing moves. Returns how many
// cards went.
auto_play :: proc(g: ^Klondike) -> int {
  sources := [8]Pile_Ref{WASTE, tableau(0), tableau(1), tableau(2), tableau(3), tableau(4), tableau(5), tableau(6)}
  moved := 0
  for {
    progress := false
    for from in sources {
      top, ok := pile_top(pile(g, from)^)
      if !ok || !top.face_up || !is_safe(g, top) {
        continue
      }
      if send_to_foundation(g, from) {
        moved += 1
        progress = true
      }
    }
    if !progress {
      return moved
    }
  }
}

is_won :: proc(g: ^Klondike) -> bool {
  for f in g.foundations {
    if f.len != 13 {
      return false
    }
  }
  return true
}
