package game

// The Windows FreeCell deal: Microsoft's C rand() seeded with the game
// number, so game #11982 is the same unsolvable deal it was in 1995.
deal_freecell :: proc(number: u32) -> (g: Game) {
  g.mode = .FreeCell
  // MS order: AC AD AH AS 2C ... which is rank-major in our suit order.
  deck: [52]int
  for i in 0 ..< 52 {
    deck[i] = i
  }
  state := number
  left := 52
  for i in 0 ..< 52 {
    state = state * 214013 + 2531011
    j := int((state >> 16) & 0x7fff) % left
    c := deck[j]
    deck[j] = deck[left - 1]
    left -= 1
    pile_push(&g.tableau[i % 8], Card{u8(c / 4 + 1), Suit(c % 4), true})
  }
  return
}
