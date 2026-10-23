package main

import "core:c/libc"
import "core:encoding/json"
import "core:os"
import "core:strings"

import "game"

MAX_TIMES :: 200

Mode_Stats :: struct {
  played:       int,
  won:          int,
  streak:       int,
  best_streak:  int,
  best_time_ms: i64,
  fewest_moves: int,
  times_ms:     [dynamic]i64, // recent win times, for the histogram
}

Settings :: struct {
  mode:       string,
  draw_count: int,
  wallpaper:  bool,
}

Save :: struct {
  settings: Settings,
  modes:    map[string]Mode_Stats,
  // "<mode key>:<YYYY-MM-DD>" for every daily started; a second start is
  // practice and doesn't count.
  dailies:  map[string]bool,
}

data_dir :: proc() -> string {
  base := os.get_env("XDG_DATA_HOME", context.temp_allocator)
  if base == "" {
    base = strings.concatenate({os.get_env("HOME", context.temp_allocator), "/.local/share"}, context.temp_allocator)
  }
  return strings.concatenate({base, "/pasians"}, context.temp_allocator)
}

save_path :: proc() -> string {
  return strings.concatenate({data_dir(), "/stats.json"}, context.temp_allocator)
}

load_save :: proc() -> (s: Save) {
  s.settings = {mode = "klondike", draw_count = 1}
  data, err := os.read_entire_file(save_path(), context.temp_allocator)
  if err == nil {
    json.unmarshal(data, &s)
  }
  if s.modes == nil {
    s.modes = make(map[string]Mode_Stats)
  }
  if s.dailies == nil {
    s.dailies = make(map[string]bool)
  }
  if s.settings.draw_count != 3 {
    s.settings.draw_count = 1
  }
  return
}

// Written to a temp file and renamed, so a crash mid-write can't eat the
// stats.
write_save :: proc(s: ^Save) {
  data, err := json.marshal(s^, {pretty = true, use_spaces = true, spaces = 2}, context.temp_allocator)
  if err != nil {
    return
  }
  dir := data_dir()
  os.make_directory_all(dir)
  tmp := strings.concatenate({save_path(), ".tmp"}, context.temp_allocator)
  if os.write_entire_file(tmp, data) == nil {
    os.rename(tmp, save_path())
  }
}

mode_key :: proc(mode: game.Mode, draw_count: int) -> string {
  switch mode {
  case .FreeCell:
    return "freecell"
  case .Klondike:
    return draw_count == 3 ? "klondike-draw3" : "klondike-draw1"
  }
  unreachable()
}

mode_stats :: proc(s: ^Save, key: string) -> ^Mode_Stats {
  if key not_in s.modes {
    s.modes[strings.clone(key)] = {}
  }
  return &s.modes[key]
}

record_loss :: proc(s: ^Save, key: string) {
  m := mode_stats(s, key)
  m.played += 1
  m.streak = 0
  write_save(s)
}

record_win :: proc(s: ^Save, key: string, time_ms: i64, moves: int) {
  m := mode_stats(s, key)
  m.played += 1
  m.won += 1
  m.streak += 1
  m.best_streak = max(m.best_streak, m.streak)
  if m.best_time_ms == 0 || time_ms < m.best_time_ms {
    m.best_time_ms = time_ms
  }
  if m.fewest_moves == 0 || moves < m.fewest_moves {
    m.fewest_moves = moves
  }
  append(&m.times_ms, time_ms)
  if len(m.times_ms) > MAX_TIMES {
    ordered_remove(&m.times_ms, 0)
  }
  write_save(s)
}

// Local date as YYYY-MM-DD: the daily turns over at local midnight.
today :: proc() -> string {
  now := libc.time(nil)
  buf: [16]u8
  n := libc.strftime(raw_data(buf[:]), len(buf), "%Y-%m-%d", libc.localtime(&now))
  return strings.clone(string(buf[:n]), context.temp_allocator)
}
