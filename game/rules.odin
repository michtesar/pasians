package game

Mode :: enum u8 {
  Klondike,
  FreeCell,
}

Pile_Kind :: enum u8 {
  Stock,
  Waste,
  Cell,
  Foundation,
  Tableau,
}

Pile_Ref :: struct {
  kind:  Pile_Kind,
  index: int,
}

STOCK :: Pile_Ref{.Stock, 0}
WASTE :: Pile_Ref{.Waste, 0}

cell :: proc(i: int) -> Pile_Ref {
  return {.Cell, i}
}

foundation :: proc(i: int) -> Pile_Ref {
  return {.Foundation, i}
}

tableau :: proc(i: int) -> Pile_Ref {
  return {.Tableau, i}
}

// The whole game is one value: copying it is a complete snapshot. Klondike
// uses stock, waste and 7 columns; FreeCell uses the cells and 8 columns.
Game :: struct {
  mode:        Mode,
  stock:       Pile,
  waste:       Pile,
  cells:       [4]Pile,
  foundations: [4]Pile,
  tableau:     [8]Pile,
  draw_count:  int, // Klondike: 1 or 3
  moves:       int,
}

columns :: proc(g: ^Game) -> int {
  return g.mode == .FreeCell ? 8 : 7
}

pile :: proc(g: ^Game, ref: Pile_Ref) -> ^Pile {
  switch ref.kind {
  case .Stock:
    return &g.stock
  case .Waste:
    return &g.waste
  case .Cell:
    return &g.cells[ref.index]
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

deal_klondike :: proc(seed: u64, draw_count := 1) -> (g: Game) {
  g.mode = .Klondike
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
draw :: proc(g: ^Game) -> bool {
  if g.mode != .Klondike {
    return false
  }
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

fits_tableau :: proc(g: ^Game, dst: Pile, c: Card) -> bool {
  top, ok := pile_top(dst)
  if !ok {
    return g.mode == .FreeCell || c.rank == KING
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

// Longest run the top of a column can be taken as. Unlike face_up_count this
// stops at a break in the sequence, which FreeCell deals are full of.
run_length :: proc(p: Pile) -> int {
  if p.len == 0 || !p.cards[p.len - 1].face_up {
    return 0
  }
  n := 1
  for i := p.len - 1; i > 0; i -= 1 {
    a, b := p.cards[i - 1], p.cards[i]
    if !a.face_up || is_red(a) == is_red(b) || a.rank != b.rank + 1 {
      break
    }
    n += 1
  }
  return n
}

// FreeCell moves one card at a time, so a run can only travel as far as the
// free cells and empty columns let it: (cells+1) * 2^columns, counting the
// target column out when it is one of the empty ones.
freecell_capacity :: proc(g: ^Game, to: Pile_Ref) -> int {
  free_cells, empty_cols := 0, 0
  for c in g.cells {
    if c.len == 0 {
      free_cells += 1
    }
  }
  for i in 0 ..< 8 {
    if g.tableau[i].len == 0 && !(to.kind == .Tableau && to.index == i) {
      empty_cols += 1
    }
  }
  return (free_cells + 1) << uint(empty_cols)
}

// Moving `count` cards from the top of `from` onto `to`.
can_move :: proc(g: ^Game, from: Pile_Ref, count: int, to: Pile_Ref) -> bool {
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
  case .Waste, .Cell:
    if count != 1 {
      return false
    }
  case .Foundation:
    // Win95 Klondike lets a card come back down; FreeCell never does.
    if count != 1 || g.mode == .FreeCell {
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
  case .Cell:
    return g.mode == .FreeCell && count == 1 && dst.len == 0
  case .Foundation:
    return count == 1 && fits_foundation(dst^, moving[0])
  case .Tableau:
    if g.mode == .FreeCell && count > freecell_capacity(g, to) {
      return false
    }
    return fits_tableau(g, dst^, moving[0])
  }
  unreachable()
}

move :: proc(g: ^Game, from: Pile_Ref, count: int, to: Pile_Ref) -> bool {
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
foundation_for :: proc(g: ^Game, c: Card) -> (Pile_Ref, bool) {
  for f, i in g.foundations {
    if fits_foundation(f, c) {
      return foundation(i), true
    }
  }
  return {}, false
}

send_to_foundation :: proc(g: ^Game, from: Pile_Ref) -> bool {
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

// Parks the top card of `from` in the first free cell.
send_to_cell :: proc(g: ^Game, from: Pile_Ref) -> bool {
  if from.kind == .Cell {
    return false
  }
  for c, i in g.cells {
    if c.len == 0 {
      return move(g, from, 1, cell(i))
    }
  }
  return false
}

foundation_rank :: proc(g: ^Game, suit: Suit) -> u8 {
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
is_safe :: proc(g: ^Game, c: Card) -> bool {
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

AUTO_SOURCES := [13]Pile_Ref {
  WASTE,
  {.Cell, 0}, {.Cell, 1}, {.Cell, 2}, {.Cell, 3},
  {.Tableau, 0}, {.Tableau, 1}, {.Tableau, 2}, {.Tableau, 3},
  {.Tableau, 4}, {.Tableau, 5}, {.Tableau, 6}, {.Tableau, 7},
}

// Sends every safe card up, repeating until nothing moves. Returns how many
// cards went.
auto_play :: proc(g: ^Game) -> int {
  moved := 0
  for {
    progress := false
    for from in AUTO_SOURCES {
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

is_won :: proc(g: ^Game) -> bool {
  for f in g.foundations {
    if f.len != 13 {
      return false
    }
  }
  return true
}
