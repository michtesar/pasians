// Package game is the pure core: state, rules and move validation.
// No drawing and no I/O, so everything here is covered by `odin test game`.
package game

Suit :: enum u8 {
  Clubs,
  Diamonds,
  Hearts,
  Spades,
}

// Rank runs 1 (ace) through 13 (king).
Card :: struct {
  rank:    u8,
  suit:    Suit,
  face_up: bool,
}

ACE :: 1
JACK :: 11
QUEEN :: 12
KING :: 13

is_red :: proc(c: Card) -> bool {
  return c.suit == .Diamonds || c.suit == .Hearts
}

// A fixed-size pile keeps the whole game state a plain value, so a
// snapshot for undo is a single assignment.
Pile :: struct {
  cards: [52]Card,
  len:   int,
}

pile_slice :: proc(p: ^Pile) -> []Card {
  return p.cards[:p.len]
}

pile_top :: proc(p: Pile) -> (Card, bool) {
  if p.len == 0 {
    return {}, false
  }
  return p.cards[p.len - 1], true
}

pile_push :: proc(p: ^Pile, c: Card) {
  p.cards[p.len] = c
  p.len += 1
}

pile_pop :: proc(p: ^Pile) -> Card {
  p.len -= 1
  return p.cards[p.len]
}

// Number of face-up cards at the top of a pile: how deep the cursor can
// reach into a tableau column.
face_up_count :: proc(p: Pile) -> int {
  n := 0
  for i := p.len - 1; i >= 0 && p.cards[i].face_up; i -= 1 {
    n += 1
  }
  return n
}

RANK_NAMES := [14]string{"?", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}
SUIT_GLYPHS := [Suit]string {
  .Clubs    = "♣",
  .Diamonds = "♦",
  .Hearts   = "♥",
  .Spades   = "♠",
}
