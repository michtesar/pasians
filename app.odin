package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

import "game"

Overlay :: enum {
  None,
  Help,
  Stats,
}

Selection :: struct {
  from:  game.Pile_Ref,
  count: int,
}

// What `.` repeats: the command, not the concrete move. `f.` sends from
// wherever the cursor is now.
Command_Kind :: enum {
  None,
  Draw,
  Found,
  Auto,
  To,
  Cell,
}

Command :: struct {
  kind: Command_Kind,
  arg:  int,
}

App :: struct {
  g:            game.Game,
  seed:         u64,
  daily_date:   string,
  counted:      bool, // counts towards stats (not a restart or a replayed daily)
  undo:         [dynamic]game.Game,
  redo:         [dynamic]game.Game,
  cursor:       game.Pile_Ref,
  depth:        int,
  held:         Maybe(Selection),
  last:         Command,
  count:        int, // pending count prefix, 0 for none
  count_cursor: game.Pile_Ref, // where the cursor was before the digit jumped it
  count_depth:  int,
  awaiting_to:  bool, // `t` pressed, waiting for a column
  overlay:      Overlay,
  cmdline_open: bool,
  cmdline:      [dynamic]u8,
  message:      [160]u8,
  message_len:  int,
  message_at:   f64,
  hint:         Maybe(game.Move),
  started_at:   f64,
  finished_in:  f64,
  started:      bool,
  won:          bool,
  theme:        Theme,
  theme_stamp:  i64,
  theme_check:  f64,
  wallpaper:    rl.Texture2D,
  has_wallpaper: bool,
  logo:         rl.Font,
  has_logo:     bool,
  save:         Save,
  font:         rl.Font,
  bounce:       Bounce,
  last_click:   f64,
  last_click_on: game.Pile_Ref,
  quit:         bool,
}

app: App

MESSAGE_SECONDS :: 2.5

say :: proc(format: string, args: ..any) {
  s := fmt.bprintf(app.message[:], format, ..args)
  app.message_len = len(s)
  app.message_at = rl.GetTime()
}

current_message :: proc() -> string {
  if app.message_len == 0 || rl.GetTime() - app.message_at > MESSAGE_SECONDS {
    return ""
  }
  return string(app.message[:app.message_len])
}

pending_keys :: proc() -> string {
  if app.awaiting_to {
    return "t"
  }
  if app.count > 0 {
    return fmt.tprint(app.count)
  }
  return ""
}

elapsed :: proc() -> f64 {
  if app.won {
    return app.finished_in
  }
  if !app.started {
    return 0
  }
  return rl.GetTime() - app.started_at
}

// ---- games ----

abandon_game :: proc() {
  if app.counted && app.started && !app.won {
    record_loss(&app.save, mode_key(app.g.mode, app.g.draw_count))
  }
}

reset_play_state :: proc() {
  clear(&app.undo)
  clear(&app.redo)
  app.held = nil
  app.hint = nil
  app.started = false
  app.won = false
  app.last = {}
  app.count = 0
  app.awaiting_to = false
  app.depth = 1
  app.cursor = game.tableau(0)
  stop_bounce()
}

start_game :: proc(mode: game.Mode, seed: u64, daily_date := "") {
  abandon_game()
  draw_count := app.save.settings.draw_count
  app.g = game.new_game(mode, seed, draw_count)
  app.seed = seed
  delete(app.daily_date)
  app.daily_date = strings.clone(daily_date)
  app.counted = true
  reset_play_state()

  app.save.settings.mode = mode == .FreeCell ? "freecell" : "klondike"
  if daily_date != "" {
    key := fmt.tprintf("%s:%s", mode_key(mode, draw_count), daily_date)
    if app.save.dailies[key] {
      app.counted = false
      say("today's daily was already played: this one is practice")
    } else {
      app.save.dailies[strings.clone(key)] = true
    }
  }
  write_save(&app.save)
}

random_seed :: proc(mode: game.Mode) -> u64 {
  r := game.Rng{u64(time.now()._nsec)}
  if mode == .FreeCell {
    return game.rng_below(&r, 32000) + 1
  }
  return game.rng_next(&r)
}

new_random_game :: proc(mode: game.Mode) {
  start_game(mode, random_seed(mode))
}

start_daily :: proc(mode: game.Mode) {
  date := today()
  d := game.daily(date, mode, app.save.settings.draw_count)
  start_game(mode, d.seed, date)
  if app.counted && !d.proven {
    say("daily challenge: no win was proven for this deal")
  }
}

restart_game :: proc() {
  abandon_game()
  app.g = game.new_game(app.g.mode, app.seed, app.g.draw_count)
  app.counted = false
  reset_play_state()
  say("restarted: this attempt doesn't count")
}

// ---- moves ----

// Every change goes through here: one undo step, then the bookkeeping.
change :: proc(apply: proc(cmd: Command, times: int) -> bool, cmd := Command{}, times := 1) -> bool {
  if app.won {
    return false
  }
  before := app.g
  if !apply(cmd, times) || before == app.g {
    return false
  }
  append(&app.undo, before)
  clear(&app.redo)
  after_change()
  return true
}

after_change :: proc() {
  app.hint = nil
  if !app.started {
    app.started = true
    app.started_at = rl.GetTime()
  }
  clamp_cursor()
  if game.is_won(&app.g) && !app.won {
    app.won = true
    app.finished_in = rl.GetTime() - app.started_at
    app.held = nil
    if app.counted {
      record_win(&app.save, mode_key(app.g.mode, app.g.draw_count), i64(app.finished_in * 1000), app.g.moves)
    }
    start_bounce()
  }
}

max_depth :: proc(ref: game.Pile_Ref) -> int {
  if ref.kind != .Tableau {
    return 1
  }
  p := app.g.tableau[ref.index]
  return max(1, app.g.mode == .FreeCell ? game.run_length(p) : game.face_up_count(p))
}

clamp_cursor :: proc() {
  app.depth = clamp(app.depth, 1, max_depth(app.cursor))
}

// The cards a command acts on: what is held, or what the cursor is on.
source :: proc() -> Selection {
  if held, ok := app.held.?; ok {
    return held
  }
  return {app.cursor, app.cursor.kind == .Tableau ? app.depth : 1}
}

apply_command :: proc(cmd: Command, times: int) -> bool {
  any := false
  for _ in 0 ..< times {
    done := false
    src := source()
    switch cmd.kind {
    case .None:
    case .Draw:
      done = game.draw(&app.g)
    case .Found:
      done = game.send_to_foundation(&app.g, src.from)
    case .Auto:
      done = game.auto_play(&app.g) > 0
    case .To:
      done = game.move(&app.g, src.from, src.count, game.tableau(cmd.arg))
    case .Cell:
      done = game.send_to_cell(&app.g, src.from)
    }
    if !done {
      break
    }
    app.held = nil
    clamp_cursor()
    any = true
  }
  return any
}

run_command :: proc(cmd: Command, times := 1) -> bool {
  ok := change(apply_command, cmd, times)
  if cmd.kind != .None {
    app.last = cmd
  }
  if !ok && !app.won {
    say("can't do that")
  }
  return ok
}

move_held_to_cursor :: proc() {
  held := app.held.?
  if held.from == app.cursor {
    app.held = nil
    return
  }
  if !change(proc(_: Command, _: int) -> bool {
    h := app.held.?
    return game.move(&app.g, h.from, h.count, app.cursor)
  }) {
    say("can't go there")
    return
  }
  app.held = nil
  if app.cursor.kind == .Tableau {
    app.depth = 1
  }
}

space :: proc() {
  if _, holding := app.held.?; holding {
    move_held_to_cursor()
    return
  }
  if app.cursor.kind == .Stock {
    run_command({.Draw, 0})
    return
  }
  p := game.pile(&app.g, app.cursor)
  if p.len == 0 || !p.cards[p.len - 1].face_up {
    return
  }
  app.held = source()
}

undo :: proc(times: int) {
  if app.won {
    return
  }
  for _ in 0 ..< times {
    if len(app.undo) == 0 {
      break
    }
    append(&app.redo, app.g)
    app.g = pop(&app.undo)
  }
  app.held = nil
  app.hint = nil
  clamp_cursor()
}

redo :: proc(times: int) {
  for _ in 0 ..< times {
    if len(app.redo) == 0 {
      break
    }
    append(&app.undo, app.g)
    app.g = pop(&app.redo)
  }
  app.hint = nil
  after_change()
}

show_hint :: proc() {
  m, ok := game.hint(&app.g)
  if !ok {
    say("no moves left: :restart or :new")
    return
  }
  app.hint = m
  if m.from.kind != .Stock {
    app.cursor = m.from
    app.depth = m.count
  } else {
    app.cursor = game.STOCK
  }
  app.held = nil
}

// ---- cursor ----

cursor_horizontal :: proc(dir: int) {
  g := &app.g
  if app.cursor.kind == .Tableau {
    app.cursor = game.tableau(clamp(app.cursor.index + dir, 0, game.columns(g) - 1))
    app.depth = 1
    return
  }
  row := top_row(g)
  for ref, i in row {
    if ref == app.cursor {
      app.cursor = row[clamp(i + dir, 0, len(row) - 1)]
      return
    }
  }
}

cursor_up :: proc() {
  if app.cursor.kind == .Tableau {
    if app.depth < max_depth(app.cursor) && game.pile(&app.g, app.cursor).len > app.depth {
      app.depth += 1
    } else {
      app.cursor = top_pile_at(&app.g, app.cursor.index)
    }
  }
}

cursor_down :: proc() {
  if app.cursor.kind == .Tableau {
    app.depth = max(1, app.depth - 1)
  } else {
    app.cursor = game.tableau(min(top_column(&app.g, app.cursor), game.columns(&app.g) - 1))
    app.depth = 1
  }
}

jump_to_column :: proc(n: int) {
  if n < 1 || n > game.columns(&app.g) {
    return
  }
  app.cursor = game.tableau(n - 1)
  app.depth = 1
}

// ---- keyboard ----

// Digits come from key codes, not characters, so the number row works on
// layouts where it types letters (Czech: +ěščřžýáí).
digit_pressed :: proc() -> int {
  for k in 0 ..< 9 {
    if rl.IsKeyPressed(rl.KeyboardKey(int(rl.KeyboardKey.ONE) + k)) || rl.IsKeyPressed(rl.KeyboardKey(int(rl.KeyboardKey.KP_1) + k)) {
      return k + 1
    }
  }
  if rl.IsKeyPressed(.ZERO) || rl.IsKeyPressed(.KP_0) {
    return 0
  }
  return -1
}

handle_keys :: proc() {
  if app.cmdline_open {
    handle_cmdline()
    return
  }

  ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
  digit := digit_pressed()

  // Gather this frame's keys; characters are layout-aware, so they decide
  // letters and punctuation.
  for {
    ch := rl.GetCharPressed()
    if ch == 0 {
      break
    }
    if ch >= '0' && ch <= '9' {
      continue
    }
    handle_char(ch)
  }

  if digit > 0 {
    handle_digit(digit)
  }

  if ctrl && rl.IsKeyPressed(.R) {
    redo(take_count())
  }
  if rl.IsKeyPressed(.ESCAPE) {
    app.overlay = .None
    app.held = nil
    app.hint = nil
    app.awaiting_to = false
    app.count = 0
  }
  if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
    if app.won {
      new_random_game(app.g.mode)
    } else if app.overlay == .None {
      space()
    }
  }
  arrows := [4]struct {
    key: rl.KeyboardKey,
    ch:  rune,
  }{{.LEFT, 'h'}, {.RIGHT, 'l'}, {.UP, 'k'}, {.DOWN, 'j'}}
  for a in arrows {
    if rl.IsKeyPressed(a.key) || rl.IsKeyPressedRepeat(a.key) {
      handle_char(a.ch)
    }
  }
}

handle_digit :: proc(digit: int) {
  if app.overlay != .None || bouncing() {
    handle_char('0')
    return
  }
  if app.awaiting_to {
    app.awaiting_to = false
    if digit <= game.columns(&app.g) {
      run_command({.To, digit - 1})
    }
    return
  }
  app.count = digit
  app.count_cursor = app.cursor
  app.count_depth = app.depth
  jump_to_column(digit)
}

// A count applies to s, u, Ctrl-r and `.`; for those the digit's jump to a
// column is taken back, since the user meant "3 times", not "column 3".
take_count :: proc() -> int {
  n := app.count
  if n == 0 {
    return 1
  }
  app.count = 0
  app.cursor = app.count_cursor
  app.depth = app.count_depth
  return n
}

handle_char :: proc(ch: rune) {
  if app.overlay != .None {
    app.overlay = .None
    return
  }
  if bouncing() {
    stop_bounce()
    return
  }
  if app.awaiting_to && ch != 't' {
    app.awaiting_to = false
  }
  counted := ch == 's' || ch == 'u' || ch == '.'
  if !counted {
    app.count = 0
  }

  switch ch {
  case 'h':
    cursor_horizontal(-1)
  case 'l':
    cursor_horizontal(1)
  case 'k':
    cursor_up()
  case 'j':
    cursor_down()
  case ' ':
    space()
  case 't':
    app.awaiting_to = true
  case 'f':
    run_command({.Found, 0})
  case 'F':
    run_command({.Auto, 0})
  case 'c':
    if app.g.mode == .FreeCell {
      run_command({.Cell, 0})
    }
  case 's':
    if app.g.mode == .Klondike {
      run_command({.Draw, 0}, take_count())
    }
  case 'u':
    undo(take_count())
  case '.':
    times := take_count()
    if app.last.kind != .None {
      run_command(app.last, times)
    }
  case 'H':
    show_hint()
  case '?':
    app.overlay = .Help
  case ':':
    app.cmdline_open = true
    clear(&app.cmdline)
  }
}

// ---- command line ----

handle_cmdline :: proc() {
  for {
    ch := rl.GetCharPressed()
    if ch == 0 {
      break
    }
    if ch >= '0' && ch <= '9' {
      continue // taken from key codes below
    }
    if ch < 128 {
      append(&app.cmdline, u8(ch))
    }
  }
  if d := digit_pressed(); d >= 0 {
    append(&app.cmdline, u8('0' + d))
  }
  if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
    if len(app.cmdline) == 0 {
      app.cmdline_open = false
    } else {
      pop(&app.cmdline)
    }
  }
  if rl.IsKeyPressed(.ESCAPE) {
    app.cmdline_open = false
  }
  if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
    app.cmdline_open = false
    execute(strings.clone(string(app.cmdline[:]), context.temp_allocator))
  }
}

execute :: proc(line: string) {
  words := strings.fields(line, context.temp_allocator)
  if len(words) == 0 {
    return
  }
  arg := len(words) > 1 ? words[1] : ""
  mode := app.g.mode
  switch words[0] {
  case "q", "q!", "quit", "wq", "x":
    app.quit = true
  case "new", "n":
    new_random_game(mode)
  case "daily", "d":
    start_daily(mode)
  case "restart", "r":
    restart_game()
  case "stats":
    app.overlay = .Stats
  case "help", "h":
    app.overlay = .Help
  case "deal":
    n, ok := strconv.parse_u64(arg)
    if !ok || (mode == .FreeCell && (n < 1 || n > 1_000_000)) {
      say("usage: :deal N (FreeCell: 1–1000000)")
      return
    }
    start_game(mode, n)
  case "mode", "m":
    switch arg {
    case "klondike", "k":
      new_random_game(.Klondike)
    case "freecell", "f":
      new_random_game(.FreeCell)
    case:
      say("usage: :mode klondike|freecell")
    }
  case "freecell":
    new_random_game(.FreeCell)
  case "klondike":
    new_random_game(.Klondike)
  case "draw":
    n, _ := strconv.parse_int(arg)
    if n != 1 && n != 3 {
      say("usage: :draw 1|3")
      return
    }
    app.save.settings.draw_count = n
    if mode == .Klondike {
      new_random_game(.Klondike)
    } else {
      write_save(&app.save)
    }
    say("draw %v", n)
  case "wallpaper", "wp":
    app.save.settings.wallpaper = !app.save.settings.wallpaper
    write_save(&app.save)
    say("wallpaper %s", app.save.settings.wallpaper ? "on" : "off")
  case:
    say("unknown command :%s", words[0])
  }
}

// ---- mouse ----

hit_test :: proc(pos: rl.Vector2) -> (ref: game.Pile_Ref, depth: int, ok: bool) {
  g := &app.g
  l := compute_layout(g)
  for col in 0 ..< game.columns(g) {
    p := g.tableau[col]
    col_ref := game.tableau(col)
    for i := p.len - 1; i >= 0; i -= 1 {
      if rl.CheckCollisionPointRec(pos, card_rect(l, g, col_ref, i)) {
        return col_ref, p.len - i, true
      }
    }
    if p.len == 0 && rl.CheckCollisionPointRec(pos, slot_rect(l, g, col_ref)) {
      return col_ref, 1, true
    }
  }
  for top in top_row(g) {
    r := slot_rect(l, g, top)
    if top.kind == .Waste && g.draw_count == 3 {
      r.width += l.card_w * 0.48
    }
    if rl.CheckCollisionPointRec(pos, r) {
      return top, 1, true
    }
  }
  return {}, 0, false
}

handle_mouse :: proc() {
  if rl.IsMouseButtonPressed(.LEFT) {
    click(rl.GetMousePosition())
  }
}

click :: proc(pos: rl.Vector2) {
  if bouncing() {
    stop_bounce()
    return
  }
  if app.overlay != .None {
    app.overlay = .None
    return
  }
  ref, depth, ok := hit_test(pos)
  if !ok {
    app.held = nil
    return
  }
  now := rl.GetTime()
  double := ref == app.last_click_on && now - app.last_click < 0.35
  app.last_click, app.last_click_on = now, ref

  app.cursor = ref
  if double && ref.kind != .Stock {
    app.held = nil
    app.depth = 1
    run_command({.Found, 0})
    return
  }
  if _, holding := app.held.?; holding {
    move_held_to_cursor()
    return
  }
  if ref.kind == .Stock {
    run_command({.Draw, 0})
    return
  }
  // Only a run can be picked up; clicking higher in a column takes the run.
  app.depth = min(depth, max_depth(ref))
  space()
}
