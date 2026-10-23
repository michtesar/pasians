package game

import "core:testing"

empty_freecell :: proc() -> (g: Game) {
  g.mode = .FreeCell
  return
}

@(test)
ms_deal_one_matches_windows :: proc(t: ^testing.T) {
  // First two rows of Windows FreeCell game #1:
  // JD 2D 9H JC 5D 7H 7C 5H / KD KC 9S 5S AD QC KH 3H
  g := deal_freecell(1)
  row0 := [8]Card {
    up(11, .Diamonds), up(2, .Diamonds), up(9, .Hearts), up(11, .Clubs),
    up(5, .Diamonds), up(7, .Hearts), up(7, .Clubs), up(5, .Hearts),
  }
  row1 := [8]Card {
    up(KING, .Diamonds), up(KING, .Clubs), up(9, .Spades), up(5, .Spades),
    up(ACE, .Diamonds), up(12, .Clubs), up(KING, .Hearts), up(3, .Hearts),
  }
  for col in 0 ..< 8 {
    testing.expect_value(t, g.tableau[col].cards[0], row0[col])
    testing.expect_value(t, g.tableau[col].cards[1], row1[col])
    testing.expect_value(t, g.tableau[col].len, col < 4 ? 7 : 6)
  }
}

@(test)
freecell_empty_column_takes_any_card :: proc(t: ^testing.T) {
  g := empty_freecell()
  g.tableau[0] = pile_of(up(5, .Hearts), up(3, .Clubs))
  testing.expect(t, move(&g, tableau(0), 1, tableau(1)))
}

@(test)
supermove_limited_by_free_cells :: proc(t: ^testing.T) {
  g := empty_freecell()
  g.tableau[0] = pile_of(up(9, .Hearts), up(8, .Spades), up(7, .Diamonds), up(6, .Clubs), up(5, .Hearts), up(4, .Spades))
  g.tableau[1] = pile_of(up(10, .Clubs))
  for i in 2 ..< 8 {
    g.tableau[i] = pile_of(up(KING, .Spades))
  }
  // Four cells and no empty columns: (4+1) * 2^0 = 5 cards at most.
  testing.expect(t, !can_move(&g, tableau(0), 6, tableau(1)))
  g.cells[0] = pile_of(up(KING, .Hearts))
  testing.expect(t, !can_move(&g, tableau(0), 5, tableau(1)), "three cells free: 4 cards")
  g.cells[0].len = 0
  g.tableau[0].len = 5
  testing.expect(t, move(&g, tableau(0), 5, tableau(1)))
}

@(test)
supermove_to_empty_column_does_not_count_it :: proc(t: ^testing.T) {
  g := empty_freecell()
  for i in 0 ..< 4 {
    g.cells[i] = pile_of(up(KING, Suit(i)))
  }
  g.tableau[0] = pile_of(up(9, .Hearts), up(8, .Spades), up(7, .Diamonds))
  g.tableau[1] = pile_of(up(9, .Diamonds))
  for i in 3 ..< 8 {
    g.tableau[i] = pile_of(up(QUEEN, .Spades))
  }
  g.tableau[3] = pile_of(up(10, .Clubs))
  // Cells full, one empty column (2): 2 cards onto a card, 1 into the hole.
  testing.expect(t, can_move(&g, tableau(0), 2, tableau(1)))
  testing.expect(t, !can_move(&g, tableau(0), 3, tableau(3)))
  testing.expect(t, !can_move(&g, tableau(0), 2, tableau(2)))
  testing.expect(t, can_move(&g, tableau(0), 1, tableau(2)))
}

@(test)
cells_hold_one_card :: proc(t: ^testing.T) {
  g := empty_freecell()
  g.tableau[0] = pile_of(up(9, .Hearts), up(8, .Spades))
  testing.expect(t, !move(&g, tableau(0), 2, cell(0)))
  testing.expect(t, send_to_cell(&g, tableau(0)))
  testing.expect(t, !move(&g, tableau(0), 1, cell(0)), "cell taken")
  testing.expect(t, send_to_cell(&g, tableau(0)), "goes to the next free cell")
  testing.expect_value(t, g.cells[1].len, 1)
}

@(test)
freecell_foundation_is_final :: proc(t: ^testing.T) {
  g := empty_freecell()
  g.foundations[0] = pile_of(up(ACE, .Hearts))
  testing.expect(t, !move(&g, foundation(0), 1, tableau(0)))
}

@(test)
klondike_has_no_cells :: proc(t: ^testing.T) {
  g := empty_game()
  g.tableau[0] = pile_of(up(5, .Hearts))
  testing.expect(t, !send_to_cell(&g, tableau(0)))
}

@(test)
solver_finishes_an_easy_game :: proc(t: ^testing.T) {
  g := empty_freecell()
  for suit in Suit {
    g.foundations[int(suit)] = full_foundation(suit)
  }
  // Pull the two top hearts back down, buried the wrong way round.
  hearts := &g.foundations[int(Suit.Hearts)]
  hearts.len = 11
  g.tableau[0] = pile_of(up(12, .Hearts), up(KING, .Hearts))
  first: Move
  testing.expect_value(t, solve(g, 1000, &first), Solve_Result.Solved)
  testing.expect_value(t, first.from, tableau(0))
}

@(test)
solver_proves_a_dead_end :: proc(t: ^testing.T) {
  g := empty_freecell()
  // Every cell is full of kings and the only column holds 2♣ on A♣ under
  // nothing that can move: the ace is buried with nowhere to put the two.
  for i in 0 ..< 4 {
    g.cells[i] = pile_of(up(KING, Suit(i)))
  }
  g.tableau[0] = pile_of(up(ACE, .Clubs), up(2, .Clubs))
  for i in 1 ..< 8 {
    g.tableau[i] = pile_of(up(QUEEN, .Hearts), up(QUEEN, .Diamonds))
  }
  testing.expect_value(t, solve(g, 1000), Solve_Result.Unsolvable)
}

@(test)
solver_wins_ms_game_one :: proc(t: ^testing.T) {
  testing.expect_value(t, solve(deal_freecell(1), 200_000), Solve_Result.Solved)
}

@(test)
daily_is_stable_and_winnable :: proc(t: ^testing.T) {
  a := daily("2026-10-23", .Klondike, 1)
  b := daily("2026-10-23", .Klondike, 1)
  testing.expect_value(t, a, b)
  testing.expect(t, a.proven, "a draw-1 daily should be proven winnable")
  testing.expect(t, daily("2026-10-24", .Klondike, 1).seed != a.seed)
  testing.expect(t, daily("2026-10-23", .FreeCell, 1).seed <= 32000)
}
