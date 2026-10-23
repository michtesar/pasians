package game

// A move as the player would make it. A draw from the stock is
// {from = STOCK}; everything else goes through `move`.
Move :: struct {
  from:  Pile_Ref,
  count: int,
  to:    Pile_Ref,
}

DRAW :: Move{STOCK, 0, STOCK}

Move_List :: struct {
  moves: [192]Move,
  len:   int,
}

add_move :: proc(l: ^Move_List, m: Move) {
  if l.len < len(l.moves) {
    l.moves[l.len] = m
    l.len += 1
  }
}

apply_move :: proc(g: ^Game, m: Move) -> bool {
  if m.from.kind == .Stock {
    return draw(g)
  }
  return move(g, m.from, m.count, m.to)
}

// Candidate moves, most promising first: up to the foundations, then moves
// that turn a card or empty a column, then the rest, then drawing. Moves
// that can't help (a king from an otherwise empty column to another empty
// column, a card back down from a foundation) are left out, which keeps the
// solver's search small and the hint sensible.
legal_moves :: proc(g: ^Game, out: ^Move_List) {
  out.len = 0
  cols := columns(g)

  for from in AUTO_SOURCES {
    top, ok := pile_top(pile(g, from)^)
    if !ok || !top.face_up {
      continue
    }
    if to, found := foundation_for(g, top); found {
      add_move(out, {from, 1, to})
    }
  }

  // Two passes over column-to-column moves: revealing first.
  for pass in 0 ..< 2 {
    for src in 0 ..< cols {
      p := g.tableau[src]
      longest := run_length(p)
      for count := longest; count >= 1; count -= 1 {
        reveals := count == p.len || !p.cards[p.len - count - 1].face_up
        if (pass == 0) != reveals {
          continue
        }
        if g.mode == .Klondike && count < longest {
          // A partial run only helps by freeing the card under it for a
          // foundation.
          under := p.cards[p.len - count - 1]
          if _, up := foundation_for(g, under); !up {
            continue
          }
        }
        for dst in 0 ..< cols {
          if count == p.len && g.tableau[dst].len == 0 {
            continue
          }
          if can_move(g, tableau(src), count, tableau(dst)) {
            add_move(out, {tableau(src), count, tableau(dst)})
          }
        }
      }
    }
  }

  for from in ([5]Pile_Ref{WASTE, cell(0), cell(1), cell(2), cell(3)}) {
    for dst in 0 ..< cols {
      if can_move(g, from, 1, tableau(dst)) {
        add_move(out, {from, 1, tableau(dst)})
      }
    }
  }

  if g.mode == .FreeCell {
    free := -1
    for c, i in g.cells {
      if c.len == 0 {
        free = i
        break
      }
    }
    if free >= 0 {
      for src in 0 ..< cols {
        if g.tableau[src].len > 0 {
          add_move(out, {tableau(src), 1, cell(free)})
        }
      }
    }
  }

  if g.mode == .Klondike && (g.stock.len > 0 || g.waste.len > 0) {
    add_move(out, DRAW)
  }
}

hash_game :: proc(g: ^Game) -> u64 {
  h: u64 = 0xcbf29ce484222325
  mix :: proc(h: ^u64, b: u8) {
    h^ = (h^ ~ u64(b)) * 0x100000001b3
  }
  piles := [?]^Pile {
    &g.stock, &g.waste,
    &g.cells[0], &g.cells[1], &g.cells[2], &g.cells[3],
    &g.foundations[0], &g.foundations[1], &g.foundations[2], &g.foundations[3],
    &g.tableau[0], &g.tableau[1], &g.tableau[2], &g.tableau[3],
    &g.tableau[4], &g.tableau[5], &g.tableau[6], &g.tableau[7],
  }
  for p in piles {
    mix(&h, u8(p.len))
    for c in p.cards[:p.len] {
      mix(&h, c.rank | u8(c.suit) << 4 | (c.face_up ? 0x80 : 0))
    }
  }
  return h
}

Solve_Result :: enum {
  Solved,
  Unsolvable,
  Gave_Up,
}

@(private)
Frame :: struct {
  g:     Game,
  moves: Move_List,
  next:  int,
}

// Depth-first search over legal_moves, with safe cards sent up after every
// move. Visits at most `budget` new positions. On success `first` is the
// opening move of the solution, which is what the hint shows.
solve :: proc(start: Game, budget: int, first: ^Move = nil) -> Solve_Result {
  if g := start; is_won(&g) {
    return .Solved
  }
  stack := make([dynamic]Frame, 0, 64)
  defer delete(stack)
  seen := make(map[u64]struct{})
  defer delete(seen)

  append(&stack, Frame{g = start})
  legal_moves(&stack[0].g, &stack[0].moves)
  seen[hash_game(&stack[0].g)] = {}
  visited := 0

  for len(stack) > 0 {
    top := len(stack) - 1
    if stack[top].next >= stack[top].moves.len {
      pop(&stack)
      continue
    }
    m := stack[top].moves.moves[stack[top].next]
    stack[top].next += 1

    child := stack[top].g
    if !apply_move(&child, m) {
      continue
    }
    auto_play(&child)
    if is_won(&child) {
      if first != nil {
        first^ = stack[0].moves.moves[stack[0].next - 1]
      }
      return .Solved
    }
    h := hash_game(&child)
    if h in seen {
      continue
    }
    seen[h] = {}
    visited += 1
    if visited > budget {
      return .Gave_Up
    }
    append(&stack, Frame{g = child})
    last := &stack[len(stack) - 1]
    legal_moves(&last.g, &last.moves)
  }
  return .Unsolvable
}

// A move worth showing as a hint: the solver's opening move when it finds a
// win within budget, otherwise the most promising legal move.
hint :: proc(g: ^Game, budget := 20_000) -> (Move, bool) {
  m: Move
  if solve(g^, budget, &m) == .Solved && !is_won(g) {
    return m, true
  }
  list: Move_List
  legal_moves(g, &list)
  if list.len == 0 {
    return {}, false
  }
  return list.moves[0], true
}
