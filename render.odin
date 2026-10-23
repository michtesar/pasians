package main

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

import "game"

Layout :: struct {
  w, h:      f32,
  card_w:    f32,
  card_h:    f32,
  gap:       f32,
  left:      f32,
  top_y:     f32,
  tab_y:     f32,
  floor:     f32, // bottom of the table, above the status bar
  status_h:  f32,
  unit:      f32, // 1 at a 1280px-wide window; scales strokes and text
}

compute_layout :: proc(g: ^game.Game) -> (l: Layout) {
  l.w = f32(rl.GetScreenWidth())
  l.h = f32(rl.GetScreenHeight())
  l.unit = max(min(l.w / 1280, l.h / 860), 0.5)
  l.status_h = math.round(30 * l.unit)
  l.floor = l.h - l.status_h

  cols := f32(8) // Klondike gets FreeCell's card size so both modes match
  margin := 28 * l.unit
  gap_ratio: f32 = 0.16
  l.card_w = (l.w - 2 * margin) / (cols + (cols - 1) * gap_ratio)
  l.card_h = l.card_w * 1.4
  if limit := (l.floor - 2 * margin) * 0.27; l.card_h > limit {
    l.card_h = limit
    l.card_w = l.card_h / 1.4
  }
  l.gap = l.card_w * gap_ratio
  n := f32(game.columns(g))
  l.left = (l.w - (n * l.card_w + (n - 1) * l.gap)) / 2
  l.top_y = margin
  l.tab_y = l.top_y + l.card_h + l.gap * 1.6
  return
}

column_x :: proc(l: Layout, col: int) -> f32 {
  return l.left + f32(col) * (l.card_w + l.gap)
}

// Which column a top-row pile sits above, and back.
top_column :: proc(g: ^game.Game, ref: game.Pile_Ref) -> int {
  #partial switch ref.kind {
  case .Stock:
    return 0
  case .Waste:
    return 1
  case .Cell:
    return ref.index
  case .Foundation:
    return g.mode == .FreeCell ? 4 + ref.index : 3 + ref.index
  }
  return 0
}

top_pile_at :: proc(g: ^game.Game, col: int) -> game.Pile_Ref {
  if g.mode == .FreeCell {
    return col < 4 ? game.cell(col) : game.foundation(col - 4)
  }
  switch col {
  case 0:
    return game.STOCK
  case 1, 2:
    return game.WASTE
  }
  return game.foundation(col - 3)
}

top_row :: proc(g: ^game.Game) -> []game.Pile_Ref {
  @(static) klondike := [6]game.Pile_Ref{game.STOCK, game.WASTE, {.Foundation, 0}, {.Foundation, 1}, {.Foundation, 2}, {.Foundation, 3}}
  @(static) freecell := [8]game.Pile_Ref{{.Cell, 0}, {.Cell, 1}, {.Cell, 2}, {.Cell, 3}, {.Foundation, 0}, {.Foundation, 1}, {.Foundation, 2}, {.Foundation, 3}}
  return g.mode == .FreeCell ? freecell[:] : klondike[:]
}

slot_rect :: proc(l: Layout, g: ^game.Game, ref: game.Pile_Ref) -> rl.Rectangle {
  if ref.kind == .Tableau {
    return {column_x(l, ref.index), l.tab_y, l.card_w, l.card_h}
  }
  return {column_x(l, top_column(g, ref)), l.top_y, l.card_w, l.card_h}
}

// Fan offsets for a column, squeezed when it would run off the table.
column_offsets :: proc(l: Layout, p: game.Pile) -> (down, up: f32) {
  down, up = l.card_h * 0.11, l.card_h * 0.26
  if p.len < 2 {
    return
  }
  ups := f32(game.face_up_count(p))
  downs := f32(p.len) - ups
  need := downs * down + (ups - 1) * up
  room := l.floor - l.gap - l.tab_y - l.card_h
  if need > room && need > 0 {
    k := room / need
    down *= k
    up *= k
  }
  return
}

// Where card i of a pile is drawn.
card_rect :: proc(l: Layout, g: ^game.Game, ref: game.Pile_Ref, i: int) -> rl.Rectangle {
  r := slot_rect(l, g, ref)
  p := game.pile(g, ref)
  #partial switch ref.kind {
  case .Tableau:
    down, up := column_offsets(l, p^)
    for j in 0 ..< i {
      r.y += p.cards[j].face_up ? up : down
    }
  case .Waste:
    if g.draw_count == 3 {
      shown := min(p.len, 3)
      if k := i - (p.len - shown); k > 0 {
        r.x += f32(k) * l.card_w * 0.24
      }
    }
  }
  return r
}

// Rectangle around the top `count` cards of a pile.
selection_rect :: proc(l: Layout, g: ^game.Game, ref: game.Pile_Ref, count: int) -> rl.Rectangle {
  p := game.pile(g, ref)
  if p.len == 0 {
    return slot_rect(l, g, ref)
  }
  first := card_rect(l, g, ref, p.len - max(count, 1))
  last := card_rect(l, g, ref, p.len - 1)
  return {first.x, first.y, last.x + last.width - first.x, last.y + last.height - first.y}
}

// ---- drawing primitives ----

ROUND :: 0.12
SEGMENTS :: 12

rounded :: proc(r: rl.Rectangle, c: rl.Color) {
  rl.DrawRectangleRounded(r, ROUND, SEGMENTS, c)
}

outline :: proc(r: rl.Rectangle, thick: f32, c: rl.Color) {
  rl.DrawRectangleRoundedLinesEx(r, ROUND, SEGMENTS, thick, c)
}

inflate :: proc(r: rl.Rectangle, d: f32) -> rl.Rectangle {
  return {r.x - d, r.y - d, r.width + 2 * d, r.height + 2 * d}
}

// raylib wants counter-clockwise vertices; take them in any order.
triangle :: proc(a, b, c: rl.Vector2, col: rl.Color) {
  cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  if cross > 0 {
    rl.DrawTriangle(a, c, b, col)
  } else {
    rl.DrawTriangle(a, b, c, col)
  }
}

// Suits are drawn from circles and triangles rather than font glyphs: sharp
// at any size and no font needs to carry ♠♥♦♣.
draw_suit :: proc(suit: game.Suit, center: rl.Vector2, r: f32, col: rl.Color) {
  x, y := center.x, center.y
  switch suit {
  case .Diamonds:
    w := r * 0.78
    triangle({x, y - r}, {x - w, y}, {x + w, y}, col)
    triangle({x, y + r}, {x - w, y}, {x + w, y}, col)
  case .Hearts:
    lobe := r * 0.52
    rl.DrawCircleV({x - r * 0.47, y - r * 0.3}, lobe, col)
    rl.DrawCircleV({x + r * 0.47, y - r * 0.3}, lobe, col)
    triangle({x - r * 0.97, y - r * 0.12}, {x + r * 0.97, y - r * 0.12}, {x, y + r * 0.95}, col)
  case .Spades:
    lobe := r * 0.47
    rl.DrawCircleV({x - r * 0.45, y + r * 0.18}, lobe, col)
    rl.DrawCircleV({x + r * 0.45, y + r * 0.18}, lobe, col)
    triangle({x - r * 0.9, y + r * 0.05}, {x + r * 0.9, y + r * 0.05}, {x, y - r * 0.95}, col)
    stem(x, y, r, col)
  case .Clubs:
    lobe := r * 0.38
    rl.DrawCircleV({x, y - r * 0.47}, lobe, col)
    rl.DrawCircleV({x - r * 0.46, y + r * 0.1}, lobe, col)
    rl.DrawCircleV({x + r * 0.46, y + r * 0.1}, lobe, col)
    rl.DrawCircleV({x, y}, r * 0.22, col)
    stem(x, y, r, col)
  }
}

stem :: proc(x, y, r: f32, col: rl.Color) {
  triangle({x, y + r * 0.1}, {x - r * 0.32, y + r}, {x + r * 0.32, y + r}, col)
}

text :: proc(s: string, pos: rl.Vector2, size: f32, col: rl.Color) {
  cs := strings.clone_to_cstring(s, context.temp_allocator)
  rl.DrawTextEx(app.font, cs, pos, size, 0, col)
}

text_width :: proc(s: string, size: f32) -> f32 {
  cs := strings.clone_to_cstring(s, context.temp_allocator)
  return rl.MeasureTextEx(app.font, cs, size, 0).x
}

suit_colour :: proc(c: game.Card) -> rl.Color {
  return game.is_red(c) ? app.theme.red : app.theme.ink
}

draw_card :: proc(l: Layout, c: game.Card, r: rl.Rectangle) {
  t := app.theme
  shadow := r
  shadow.y += 2 * l.unit
  rounded(shadow, fade(rl.BLACK, t.light ? 0.12 : 0.35))

  if !c.face_up {
    rounded(r, t.back)
    inner := inflate(r, -r.width * 0.08)
    rounded(inner, mix(t.back, t.back_mark, 0.35))
    if app.has_logo {
      // The Omarchy mark from Omarchy's own icon font, in the theme's colours.
      size := inner.width * 0.72
      m := rl.MeasureTextEx(app.logo, OMARCHY_LOGO, size, 0)
      rl.DrawTextEx(app.logo, OMARCHY_LOGO, {inner.x + (inner.width - m.x) / 2, inner.y + (inner.height - m.y) / 2}, size, 0, mix(t.back, t.face, 0.45))
      return
    }
    // Outside Omarchy: a lattice of small diamonds, kept inside the inner panel.
    step := inner.width / 5
    for row := 0; f32(row) * step < inner.height - step * 0.5; row += 1 {
      for col in 0 ..< 5 {
        cx := inner.x + (f32(col) + 0.5) * step
        cy := inner.y + (f32(row) + 0.5) * step + (inner.height - step * math.floor(inner.height / step)) / 2
        if cy + step * 0.3 > inner.y + inner.height {
          continue
        }
        draw_suit(.Diamonds, {cx, cy}, step * 0.28, fade(t.back, 0.9))
      }
    }
    return
  }

  rounded(r, t.face)
  outline(r, max(1, l.unit), fade(t.ink, 0.25))
  ink := suit_colour(c)
  rank := game.RANK_NAMES[c.rank]
  size := r.height * 0.2
  pad := r.width * 0.08
  text(rank, {r.x + pad, r.y + pad * 0.6}, size, ink)
  // Rank and suit both sit in the strip a fanned column leaves visible.
  small := r.width * 0.09
  draw_suit(c.suit, {r.x + r.width - pad - small, r.y + pad + small}, small, ink)

  center := rl.Vector2{r.x + r.width / 2, r.y + r.height * 0.6}
  if c.rank >= game.JACK {
    big := r.height * 0.36
    w := text_width(rank, big)
    text(rank, {center.x - w / 2, center.y - big * 0.55}, big, ink)
  } else {
    draw_suit(c.suit, center, r.width * 0.24, ink)
  }
}

draw_empty_slot :: proc(l: Layout, r: rl.Rectangle, label: string) {
  t := app.theme
  rounded(r, fade(t.ink, t.light ? 0.06 : 0.3))
  outline(r, max(1, 1.5 * l.unit), fade(t.muted, 0.6))
  if label != "" {
    size := r.height * 0.18
    w := text_width(label, size)
    text(label, {r.x + (r.width - w) / 2, r.y + (r.height - size) / 2}, size, fade(t.muted, 0.8))
  }
}

draw_pile :: proc(l: Layout, g: ^game.Game, ref: game.Pile_Ref) {
  p := game.pile(g, ref)
  if p.len == 0 {
    r := slot_rect(l, g, ref)
    draw_empty_slot(l, r, ref.kind == .Foundation ? "A" : "")
    if ref.kind == .Stock && g.waste.len > 0 {
      // Win95's ring: click to turn the waste over.
      c := rl.Vector2{r.x + r.width / 2, r.y + r.height / 2}
      rl.DrawRing(c, r.width * 0.2, r.width * 0.27, 0, 360, 48, fade(app.theme.muted, 0.9))
    }
    return
  }
  first := 0
  #partial switch ref.kind {
  case .Stock, .Foundation, .Cell:
    first = p.len - 1
  case .Waste:
    first = max(0, p.len - (g.draw_count == 3 ? 3 : 1))
  }
  held, holding := app.held.?
  for i in first ..< p.len {
    r := card_rect(l, g, ref, i)
    lifted := holding && held.from == ref && i >= p.len - held.count
    if lifted {
      r.y -= 6 * l.unit
    }
    draw_card(l, p.cards[i], r)
    if lifted {
      rounded(r, fade(app.theme.selection, 0.28))
    }
  }
}

draw_table :: proc(l: Layout) {
  rl.ClearBackground(app.theme.table)
  if app.save.settings.wallpaper && app.has_wallpaper {
    tex := app.wallpaper
    // Cover the window, cropped from the centre, then wash it out under the
    // felt.
    s := max(l.w / f32(tex.width), l.h / f32(tex.height))
    sw, sh := l.w / s, l.h / s
    src := rl.Rectangle{(f32(tex.width) - sw) / 2, (f32(tex.height) - sh) / 2, sw, sh}
    rl.DrawTexturePro(tex, src, {0, 0, l.w, l.h}, {}, 0, rl.WHITE)
    rl.DrawRectangleRec({0, 0, l.w, l.h}, fade(app.theme.table, 0.82))
  }
}

draw_scene :: proc(show_cursor: bool) {
  g := &app.g
  l := compute_layout(g)
  draw_table(l)
  for ref in top_row(g) {
    draw_pile(l, g, ref)
  }
  for col in 0 ..< game.columns(g) {
    draw_pile(l, g, game.tableau(col))
  }

  thick := max(2, 3 * l.unit)
  if hint, ok := app.hint.?; ok {
    if hint.from.kind == .Stock {
      outline(inflate(slot_rect(l, g, game.STOCK), 4 * l.unit), thick, app.theme.hint)
    } else {
      outline(inflate(selection_rect(l, g, hint.from, hint.count), 4 * l.unit), thick, app.theme.hint)
      outline(inflate(selection_rect(l, g, hint.to, 1), 4 * l.unit), thick, fade(app.theme.hint, 0.6))
    }
  }
  if show_cursor && !app.won {
    r := selection_rect(l, g, app.cursor, app.cursor.kind == .Tableau ? app.depth : 1)
    if _, holding := app.held.?; holding && app.cursor != app.held.?.from {
      // Show where the held cards would land.
      p := game.pile(g, app.cursor)
      if p.len > 0 {
        r = card_rect(l, g, app.cursor, p.len - 1)
      }
    }
    outline(inflate(r, 4 * l.unit), thick, app.theme.cursor)
  }
  draw_status(l)
}

format_time :: proc(seconds: f64) -> string {
  s := int(seconds)
  return fmt.tprintf("%d:%02d", s / 60, s % 60)
}

game_title :: proc() -> string {
  g := &app.g
  name: string
  if g.mode == .FreeCell {
    name = fmt.tprintf("FreeCell #%v", app.seed)
  } else {
    name = fmt.tprintf("Klondike · draw %v", g.draw_count)
  }
  if app.daily_date != "" {
    name = fmt.tprintf("%s · daily %s%s", name, app.daily_date, app.counted ? "" : " (practice)")
  } else if !app.counted {
    name = fmt.tprintf("%s · practice", name)
  }
  return name
}

draw_status :: proc(l: Layout) {
  t := app.theme
  y := l.floor
  rl.DrawRectangleRec({0, y, l.w, l.status_h}, fade(t.ink, t.light ? 0.08 : 0.5))
  size := l.status_h * 0.6
  pad := 14 * l.unit
  ty := y + (l.status_h - size) / 2

  if app.cmdline_open {
    line := fmt.tprintf(":%s_", string(app.cmdline[:]))
    text(line, {pad, ty}, size, t.text)
    return
  }

  text(game_title(), {pad, ty}, size, t.muted)

  right := fmt.tprintf("%s%s   moves %v   %s", pending_keys(), app.held != nil ? "  holding" : "", app.g.moves, format_time(elapsed()))
  w := text_width(right, size)
  text(right, {l.w - pad - w, ty}, size, t.muted)

  if msg := current_message(); msg != "" {
    mw := text_width(msg, size)
    text(msg, {(l.w - mw) / 2, ty}, size, t.text)
  }
}

// ---- overlays ----

panel :: proc(l: Layout, width, height: f32) -> rl.Rectangle {
  t := app.theme
  rl.DrawRectangleRec({0, 0, l.w, l.h}, fade(rl.BLACK, 0.45))
  r := rl.Rectangle{(l.w - width) / 2, (l.h - height) / 2, width, height}
  rl.DrawRectangleRounded(r, 0.04, SEGMENTS, t.ink)
  rl.DrawRectangleRoundedLinesEx(r, 0.04, SEGMENTS, max(1, 2 * l.unit), t.cursor)
  return r
}

HELP_LINES := [?][2]string {
  {"h l  ← →", "previous / next pile"},
  {"j k  ↓ ↑", "fewer / more cards; past the run, up a row"},
  {"1–8", "jump to column"},
  {"Space  Enter", "pick up / put down"},
  {"t{n}", "move selection to column n"},
  {"f", "send card to its foundation"},
  {"F", "send everything safe to the foundations"},
  {"c", "park card in a free cell (FreeCell)"},
  {"s", "draw from stock (Klondike)"},
  {"u  Ctrl-r", "undo / redo"},
  {".", "repeat last command"},
  {"{n}s {n}u {n}.", "count prefix"},
  {"H", "hint"},
  {"Esc", "cancel"},
  {":new  :daily  :restart", "new deal, today's deal, same deal again"},
  {":deal N", "seed N, or FreeCell game #N"},
  {":mode klondike|freecell", "switch game"},
  {":draw 1|3", "Klondike draw count"},
  {":stats  :wallpaper  :q", "statistics, theme wallpaper, quit"},
}

draw_help :: proc(l: Layout) {
  size := 19 * l.unit
  line := size * 1.45
  r := panel(l, 760 * l.unit, line * f32(len(HELP_LINES) + 2))
  x, y := r.x + 28 * l.unit, r.y + line
  for row in HELP_LINES {
    text(row[0], {x, y}, size, app.theme.cursor)
    text(row[1], {x + 250 * l.unit, y}, size, app.theme.face)
    y += line
  }
}

draw_stats :: proc(l: Layout) {
  t := app.theme
  size := 19 * l.unit
  line := size * 1.5
  r := panel(l, 760 * l.unit, line * 11.5)
  x, y := r.x + 28 * l.unit, r.y + line * 0.8

  keys := [3]string{"klondike-draw1", "klondike-draw3", "freecell"}
  names := [3]string{"Klondike 1", "Klondike 3", "FreeCell"}
  cols := [6]string{"", "played", "won", "streak", "best", "best time"}
  col_x := [6]f32{0, 170, 270, 360, 450, 540}
  for c, i in cols {
    text(c, {x + col_x[i] * l.unit, y}, size, t.muted)
  }
  y += line
  for key, i in keys {
    m := app.save.modes[key]
    pct := m.played > 0 ? 100 * m.won / m.played : 0
    best := m.best_time_ms > 0 ? format_time(f64(m.best_time_ms) / 1000) : "–"
    cells := [6]string {
      names[i],
      fmt.tprint(m.played),
      fmt.tprintf("%v (%v%%)", m.won, pct),
      fmt.tprint(m.streak),
      fmt.tprint(m.best_streak),
      fmt.tprintf("%s%s", best, m.fewest_moves > 0 ? fmt.tprintf("  %v moves", m.fewest_moves) : ""),
    }
    current := key == mode_key(app.g.mode, app.g.draw_count)
    for c, j in cells {
      text(c, {x + col_x[j] * l.unit, y}, size, current ? t.face : t.muted)
    }
    y += line
  }

  // Histogram of win times for the current mode.
  y += line * 0.6
  m := app.save.modes[mode_key(app.g.mode, app.g.draw_count)]
  text("win times", {x, y}, size, t.muted)
  y += line
  chart := rl.Rectangle{x, y, r.width - 56 * l.unit, line * 5}
  if len(m.times_ms) == 0 {
    text("no wins yet", {x, y + line}, size, t.muted)
    return
  }
  BINS :: 10
  lo, hi := m.times_ms[0], m.times_ms[0]
  for v in m.times_ms {
    lo, hi = min(lo, v), max(hi, v)
  }
  span := max(hi - lo, 1)
  counts: [BINS]int
  peak := 1
  for v in m.times_ms {
    b := min(int(f64(v - lo) / f64(span) * BINS), BINS - 1)
    counts[b] += 1
    peak = max(peak, counts[b])
  }
  bar_w := chart.width / BINS
  for n, i in counts {
    h := chart.height * f32(n) / f32(peak)
    rl.DrawRectangleRec({chart.x + f32(i) * bar_w + 2, chart.y + chart.height - h, bar_w - 4, h}, t.cursor)
  }
  text(format_time(f64(lo) / 1000), {chart.x, chart.y + chart.height + 4 * l.unit}, size * 0.8, t.muted)
  hw := text_width(format_time(f64(hi) / 1000), size * 0.8)
  text(format_time(f64(hi) / 1000), {chart.x + chart.width - hw, chart.y + chart.height + 4 * l.unit}, size * 0.8, t.muted)
}

draw_won_banner :: proc(l: Layout) {
  t := app.theme
  size := 26 * l.unit
  msg := fmt.tprintf("Won in %s with %v moves", format_time(elapsed()), app.g.moves)
  sub := "Enter: new game    :daily    :stats"
  w := max(text_width(msg, size), text_width(sub, size * 0.7)) + 60 * l.unit
  r := rl.Rectangle{(l.w - w) / 2, l.floor - 150 * l.unit, w, 100 * l.unit}
  rl.DrawRectangleRounded(r, 0.2, SEGMENTS, fade(t.ink, 0.92))
  text(msg, {r.x + (w - text_width(msg, size)) / 2, r.y + 18 * l.unit}, size, t.face)
  text(sub, {r.x + (w - text_width(sub, size * 0.7)) / 2, r.y + 60 * l.unit}, size * 0.7, t.muted)
}
