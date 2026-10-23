package game

import "core:testing"

up :: proc(rank: u8, suit: Suit) -> Card {
  return {rank, suit, true}
}

down :: proc(rank: u8, suit: Suit) -> Card {
  return {rank, suit, false}
}

pile_of :: proc(cards: ..Card) -> (p: Pile) {
  for c in cards {
    pile_push(&p, c)
  }
  return
}

empty_game :: proc(draw_count := 1) -> (g: Game) {
  g.draw_count = draw_count
  return
}

full_foundation :: proc(suit: Suit) -> (p: Pile) {
  for rank in u8(ACE) ..= KING {
    pile_push(&p, up(rank, suit))
  }
  return
}

@(test)
splitmix_matches_reference :: proc(t: ^testing.T) {
  // Reference outputs from Vigna's splitmix64.c for seed 1234567.
  r := Rng{1234567}
  testing.expect_value(t, rng_next(&r), 6457827717110365317)
  testing.expect_value(t, rng_next(&r), 3203168211198807973)
  testing.expect_value(t, rng_next(&r), 9817491932198370423)
}

@(test)
deal_lays_out_klondike :: proc(t: ^testing.T) {
  g := deal_klondike(42)
  seen: [Suit][14]bool
  for col in 0 ..< 7 {
    p := g.tableau[col]
    testing.expect_value(t, p.len, col + 1)
    testing.expect_value(t, face_up_count(p), 1)
    for c in p.cards[:p.len] {
      seen[c.suit][c.rank] = true
    }
  }
  testing.expect_value(t, g.stock.len, 24)
  testing.expect_value(t, face_up_count(g.stock), 0)
  for c in g.stock.cards[:g.stock.len] {
    seen[c.suit][c.rank] = true
  }
  for suit in Suit {
    for rank in u8(ACE) ..= KING {
      testing.expectf(t, seen[suit][rank], "%v of %v missing from deal", rank, suit)
    }
  }
}

@(test)
deal_is_stable_per_seed :: proc(t: ^testing.T) {
  a, b, c := deal_klondike(7), deal_klondike(7), deal_klondike(8)
  testing.expect(t, a == b, "same seed must give the same deal")
  testing.expect(t, a != c, "different seeds should give different deals")

  // Pinned so a change to the shuffle or the Rng can't silently change
  // every daily deal. Update only on purpose.
  g := deal_klondike(1)
  tops: [7]Card
  for col in 0 ..< 7 {
    tops[col], _ = pile_top(g.tableau[col])
  }
  pinned := [7]Card{up(7, .Diamonds), up(6, .Diamonds), up(2, .Diamonds), up(2, .Clubs), up(KING, .Hearts), up(11, .Spades), up(8, .Spades)}
  testing.expect_value(t, tops, pinned)
}

@(test)
king_only_on_empty_column :: proc(t: ^testing.T) {
  g := empty_game()
  g.tableau[0] = pile_of(up(12, .Hearts))
  g.tableau[1] = pile_of(up(KING, .Spades))
  testing.expect(t, !move(&g, tableau(0), 1, tableau(2)), "queen must not go to an empty column")
  testing.expect(t, move(&g, tableau(1), 1, tableau(2)), "king goes to an empty column")
  testing.expect(t, move(&g, tableau(0), 1, tableau(2)), "red queen goes on black king")
  testing.expect_value(t, g.tableau[2].len, 2)
}

@(test)
tableau_needs_alternating_colour_and_rank :: proc(t: ^testing.T) {
  g := empty_game()
  g.tableau[0] = pile_of(up(9, .Spades))
  g.tableau[1] = pile_of(up(8, .Clubs))
  g.tableau[2] = pile_of(up(7, .Hearts))
  g.tableau[3] = pile_of(up(8, .Diamonds))
  testing.expect(t, !move(&g, tableau(1), 1, tableau(0)), "same colour")
  testing.expect(t, !move(&g, tableau(2), 1, tableau(0)), "rank gap")
  testing.expect(t, move(&g, tableau(3), 1, tableau(0)), "red 8 on black 9")
}

@(test)
run_moves_and_flips_exposed_card :: proc(t: ^testing.T) {
  g := empty_game()
  g.tableau[0] = pile_of(down(3, .Clubs), up(9, .Hearts), up(8, .Spades), up(7, .Diamonds))
  g.tableau[1] = pile_of(up(10, .Clubs))
  testing.expect(t, !move(&g, tableau(0), 4, tableau(1)), "face-down card can't be taken")
  testing.expect(t, move(&g, tableau(0), 3, tableau(1)), "run of three onto black 10")
  testing.expect_value(t, g.tableau[1].len, 4)
  testing.expect_value(t, g.tableau[0].len, 1)
  testing.expect(t, g.tableau[0].cards[0].face_up, "exposed card turns face up")
}

@(test)
broken_run_cannot_move :: proc(t: ^testing.T) {
  g := empty_game()
  // Not reachable by play, but the rules must not trust the layout.
  g.tableau[0] = pile_of(up(9, .Hearts), up(7, .Spades))
  g.tableau[1] = pile_of(up(10, .Clubs))
  testing.expect(t, !move(&g, tableau(0), 2, tableau(1)))
}

@(test)
foundation_builds_up_by_suit :: proc(t: ^testing.T) {
  g := empty_game()
  g.tableau[0] = pile_of(up(2, .Hearts))
  g.tableau[1] = pile_of(up(2, .Spades))
  g.waste = pile_of(up(ACE, .Hearts))
  testing.expect(t, !send_to_foundation(&g, tableau(0)), "two before ace")
  testing.expect(t, send_to_foundation(&g, WASTE), "ace on empty foundation")
  testing.expect(t, !send_to_foundation(&g, tableau(1)), "wrong suit")
  testing.expect(t, send_to_foundation(&g, tableau(0)), "two of hearts on ace of hearts")
  testing.expect_value(t, g.foundations[0].len, 2)
}

@(test)
foundation_takes_one_card_at_a_time :: proc(t: ^testing.T) {
  g := empty_game()
  g.foundations[0] = pile_of(up(ACE, .Spades))
  g.tableau[0] = pile_of(up(3, .Hearts), up(2, .Spades))
  testing.expect(t, !move(&g, tableau(0), 2, foundation(0)))
  testing.expect(t, move(&g, tableau(0), 1, foundation(0)))
}

@(test)
foundation_card_can_come_back :: proc(t: ^testing.T) {
  g := empty_game()
  g.foundations[0] = pile_of(up(ACE, .Hearts), up(2, .Hearts))
  g.tableau[0] = pile_of(up(3, .Clubs))
  testing.expect(t, move(&g, foundation(0), 1, tableau(0)))
  testing.expect_value(t, g.foundations[0].len, 1)
}

@(test)
illegal_sources_and_targets :: proc(t: ^testing.T) {
  g := empty_game()
  g.stock = pile_of(down(KING, .Hearts))
  g.waste = pile_of(up(5, .Hearts), up(KING, .Spades))
  g.tableau[0] = pile_of(up(KING, .Clubs))
  testing.expect(t, !move(&g, STOCK, 1, tableau(1)), "stock is drawn, not moved from")
  testing.expect(t, !move(&g, WASTE, 2, tableau(1)), "waste gives one card")
  testing.expect(t, !move(&g, tableau(0), 1, WASTE), "nothing goes to waste")
  testing.expect(t, !move(&g, tableau(0), 1, STOCK), "nothing goes to stock")
  testing.expect(t, !move(&g, tableau(0), 1, tableau(0)), "same pile")
  testing.expect(t, !move(&g, tableau(1), 1, tableau(0)), "empty source")
  testing.expect(t, !move(&g, tableau(0), 0, tableau(1)), "zero cards")
  testing.expect_value(t, g.moves, 0)
}

@(test)
draw_three_takes_what_is_left :: proc(t: ^testing.T) {
  g := empty_game(3)
  g.stock = pile_of(down(4, .Clubs), down(5, .Clubs))
  testing.expect(t, draw(&g))
  testing.expect_value(t, g.stock.len, 0)
  testing.expect_value(t, g.waste.len, 2)
  top, _ := pile_top(g.waste)
  testing.expect_value(t, top, up(4, .Clubs))
}

@(test)
draw_three_shows_third_card :: proc(t: ^testing.T) {
  g := empty_game(3)
  g.stock = pile_of(down(1, .Clubs), down(2, .Clubs), down(3, .Clubs), down(4, .Clubs))
  draw(&g)
  // The packet of three is turned over as one: the top stock card ends at
  // the bottom, and the third one down is playable.
  top, _ := pile_top(g.waste)
  testing.expect_value(t, top, up(2, .Clubs))
  testing.expect_value(t, g.stock.len, 1)
}

@(test)
recycle_keeps_stock_order :: proc(t: ^testing.T) {
  g := deal_klondike(3)
  first, second: [24]Card
  for i in 0 ..< 24 {
    draw(&g)
    first[i], _ = pile_top(g.waste)
  }
  testing.expect(t, draw(&g), "empty stock turns the waste over")
  testing.expect_value(t, g.waste.len, 0)
  testing.expect_value(t, g.stock.len, 24)
  for i in 0 ..< 24 {
    draw(&g)
    second[i], _ = pile_top(g.waste)
  }
  testing.expect_value(t, second, first)
}

@(test)
draw_with_nothing_left :: proc(t: ^testing.T) {
  g := empty_game()
  testing.expect(t, !draw(&g))
  testing.expect_value(t, g.moves, 0)
}

@(test)
auto_play_sends_only_safe_cards :: proc(t: ^testing.T) {
  g := empty_game()
  g.foundations[0] = pile_of(up(ACE, .Hearts), up(2, .Hearts))
  g.foundations[1] = pile_of(up(ACE, .Spades))
  g.tableau[0] = pile_of(up(2, .Spades))
  g.tableau[1] = pile_of(up(3, .Hearts))
  g.tableau[2] = pile_of(up(4, .Hearts))
  // 2♠ is always safe. 3♥ is safe only once both black suits reach 2, and
  // clubs haven't started, so a black 2 might still need it.
  testing.expect_value(t, auto_play(&g), 1)
  testing.expect_value(t, g.foundations[1].len, 2)
  testing.expect_value(t, g.tableau[1].len, 1)

  g.foundations[2] = pile_of(up(ACE, .Clubs), up(2, .Clubs))
  // Now 3♥ is safe, and with it on, 4♥ still isn't: black 3s aren't up.
  testing.expect_value(t, auto_play(&g), 1)
  testing.expect_value(t, g.tableau[2].len, 1)
}

@(test)
won_when_all_foundations_full :: proc(t: ^testing.T) {
  g := empty_game()
  g.foundations = {full_foundation(.Clubs), full_foundation(.Diamonds), full_foundation(.Hearts), full_foundation(.Spades)}
  testing.expect(t, is_won(&g))
  g.foundations[3].len -= 1
  testing.expect(t, !is_won(&g))
}

@(test)
snapshot_is_a_copy :: proc(t: ^testing.T) {
  g := deal_klondike(5)
  saved := g
  draw(&g)
  testing.expect(t, saved != g)
  g = saved
  testing.expect(t, saved == g, "assigning a snapshot restores the game")
}
