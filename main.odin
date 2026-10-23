// Step-one frontend: prints the table and reads commands from stdin, so the
// rules can be played before there is a window.
package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import "game"

RED :: "\x1b[31m"
DIM :: "\x1b[2m"
RESET :: "\x1b[0m"

HELP :: `commands:
  s              draw from stock
  m SRC DST [N]  move N cards (default 1); piles: w, 1-7, f1-f4
  f SRC          send top card of SRC to its foundation
  F              send every safe card to the foundations
  n [SEED]       new game
  q              quit`

// Prints a card padded to `width` columns; ANSI codes don't take space.
print_card :: proc(c: game.Card, width: int) {
  if !c.face_up {
    fmt.printf("%s##%s", DIM, RESET)
    pad(width - 2)
    return
  }
  rank := game.RANK_NAMES[c.rank]
  colour := game.is_red(c) ? RED : ""
  fmt.printf("%s%s%s%s", colour, rank, game.SUIT_GLYPHS[c.suit], RESET)
  pad(width - len(rank) - 1)
}

print_empty :: proc(width: int) {
  fmt.printf("%s··%s", DIM, RESET)
  pad(width - 2)
}

pad :: proc(n: int) {
  for _ in 0 ..< n {
    fmt.print(" ")
  }
}

print_game :: proc(g: ^game.Klondike, seed: u64) {
  fmt.printf("\nseed %v  draw %v  moves %v\n\n", seed, g.draw_count, g.moves)

  fmt.printf("stock [%2d]  waste ", g.stock.len)
  shown := min(g.waste.len, g.draw_count == 3 ? 3 : 1)
  if shown == 0 {
    print_empty(4)
  }
  for c in g.waste.cards[g.waste.len - shown:g.waste.len] {
    print_card(c, 4)
  }
  pad((3 - max(shown, 1)) * 4)
  fmt.print("   ")
  for f in g.foundations {
    if top, ok := game.pile_top(f); ok {
      print_card(top, 4)
    } else {
      print_empty(4)
    }
  }
  fmt.println()
  fmt.println()

  fmt.println("1    2    3    4    5    6    7")
  rows := 0
  for p in g.tableau {
    rows = max(rows, p.len)
  }
  for row in 0 ..< rows {
    for p in g.tableau {
      if row < p.len {
        print_card(p.cards[row], 5)
      } else {
        pad(5)
      }
    }
    fmt.println()
  }
  if game.is_won(g) {
    fmt.println("\nyou won")
  }
}

parse_ref :: proc(s: string) -> (game.Pile_Ref, bool) {
  if s == "w" {
    return game.WASTE, true
  }
  if len(s) == 2 && s[0] == 'f' && s[1] >= '1' && s[1] <= '4' {
    return game.foundation(int(s[1] - '1')), true
  }
  if len(s) == 1 && s[0] >= '1' && s[0] <= '7' {
    return game.tableau(int(s[0] - '1')), true
  }
  return {}, false
}

new_seed :: proc() -> u64 {
  return u64(time.now()._nsec)
}

main :: proc() {
  seed := new_seed()
  draw_count := 1
  for arg in os.args[1:] {
    if arg == "-3" {
      draw_count = 3
    } else if n, ok := strconv.parse_u64(arg); ok {
      seed = n
    } else {
      fmt.eprintfln("usage: pasians [SEED] [-3]")
      os.exit(2)
    }
  }

  g := game.deal(seed, draw_count)
  print_game(&g, seed)

  reader: bufio.Reader
  bufio.reader_init(&reader, os.to_stream(os.stdin))
  defer bufio.reader_destroy(&reader)

  for {
    free_all(context.temp_allocator)
    fmt.print("\n> ")
    line, err := bufio.reader_read_string(&reader, '\n', context.temp_allocator)
    if err != nil && len(line) == 0 {
      fmt.println()
      return
    }
    words := strings.fields(line, context.temp_allocator)
    if len(words) == 0 {
      continue
    }

    ok := true
    switch words[0] {
    case "q":
      return
    case "?", "h", "help":
      fmt.println(HELP)
      continue
    case "s":
      ok = game.draw(&g)
    case "F":
      ok = game.auto_play(&g) > 0
    case "f":
      from, parsed := parse_ref(len(words) > 1 ? words[1] : "")
      ok = parsed && game.send_to_foundation(&g, from)
    case "m":
      count := 1
      if len(words) > 3 {
        count = strconv.parse_int(words[3]) or_else 0
      }
      from, from_ok := parse_ref(len(words) > 1 ? words[1] : "")
      to, to_ok := parse_ref(len(words) > 2 ? words[2] : "")
      ok = from_ok && to_ok && game.move(&g, from, count, to)
    case "n":
      seed = new_seed()
      if len(words) > 1 {
        seed = strconv.parse_u64(words[1]) or_else seed
      }
      g = game.deal(seed, draw_count)
    case:
      fmt.println("unknown command, ? for help")
      continue
    }
    if !ok {
      fmt.println("not allowed")
      continue
    }
    print_game(&g, seed)
  }
}
