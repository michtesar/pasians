package main

import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:sys/posix"
import "core:time"
import rl "vendor:raylib"

THEME_DIR :: "/.local/state/omarchy/current/theme"
WALLPAPER :: "/.local/state/omarchy/current/background"

Theme :: struct {
  table:     rl.Color,
  face:      rl.Color, // card face: the theme foreground
  ink:       rl.Color, // black suits and text on cards: the theme background
  red:       rl.Color,
  back:      rl.Color,
  back_mark: rl.Color,
  cursor:    rl.Color,
  selection: rl.Color,
  hint:      rl.Color,
  text:      rl.Color,
  muted:     rl.Color,
  light:     bool,
}

// Tokyo Night, for running outside Omarchy.
DEFAULT_PALETTE := [?][2]string {
  {"background", "#1a1b26"},
  {"foreground", "#a9b1d6"},
  {"accent", "#7aa2f7"},
  {"selection", "#7aa2f7"},
  {"muted", "#444b6a"},
  {"red", "#f7768e"},
  {"bright_red", "#f7768e"},
  {"green", "#9ece6a"},
}

theme_reload_requested: bool

// `pkill -USR1 pasians` from the theme-set hook lands here. Only a flag is
// set; the main loop does the work.
on_sigusr1 :: proc "c" (_: posix.Signal) {
  sync.atomic_store(&theme_reload_requested, true)
}

watch_theme_signal :: proc() {
  posix.signal(.SIGUSR1, on_sigusr1)
}

theme_file :: proc() -> string {
  return strings.concatenate({os.get_env("HOME", context.temp_allocator), THEME_DIR, "/colors.toml"}, context.temp_allocator)
}

wallpaper_file :: proc() -> string {
  return strings.concatenate({os.get_env("HOME", context.temp_allocator), WALLPAPER}, context.temp_allocator)
}

// Stamp of the inputs a theme switch changes; polled once a second as a
// fallback for when the hook isn't installed.
theme_stamp :: proc() -> i64 {
  stamp: i64
  for path in ([2]string{theme_file(), wallpaper_file()}) {
    if fi, err := os.stat(path, context.temp_allocator); err == nil {
      stamp ~= time.to_unix_nanoseconds(fi.modification_time) ~ fi.size
    }
  }
  return stamp
}

// Resolved palette, key -> value. omarchy-theme-color applies the same
// alias and fallback cascade as every other themed app; without it (not on
// Omarchy) colors.toml is read as-is.
load_palette :: proc(allocator := context.temp_allocator) -> map[string]string {
  palette := make(map[string]string, allocator = allocator)
  for kv in DEFAULT_PALETTE {
    palette[kv[0]] = kv[1]
  }

  state, stdout, _, err := os.process_exec({command = {"omarchy-theme-color", "--all"}}, allocator)
  if err == nil && state.exit_code == 0 {
    out := string(stdout)
    for line in strings.split_lines_iterator(&out) {
      key, _, value := strings.partition(line, "\t")
      if key != "" && value != "" {
        palette[key] = value
      }
    }
    return palette
  }

  data, read_err := os.read_entire_file(theme_file(), allocator)
  if read_err != nil {
    return palette
  }
  text := string(data)
  for line in strings.split_lines_iterator(&text) {
    key, eq, value := strings.partition(line, "=")
    if eq == "" {
      continue
    }
    palette[strings.trim_space(key)] = strings.trim(strings.trim_space(value), "\"'")
  }
  return palette
}

parse_hex :: proc(s: string) -> (rl.Color, bool) {
  hex := strings.trim_prefix(strings.trim_space(s), "#")
  if len(hex) != 6 && len(hex) != 8 {
    return {}, false
  }
  v, ok := strconv.parse_u64_of_base(hex, 16)
  if !ok {
    return {}, false
  }
  if len(hex) == 6 {
    v = v << 8 | 0xff
  }
  return {u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}, true
}

colour :: proc(palette: map[string]string, keys: ..string) -> rl.Color {
  for key in keys {
    if value, found := palette[key]; found {
      if c, ok := parse_hex(value); ok {
        return c
      }
    }
  }
  return rl.MAGENTA
}

mix :: proc(a, b: rl.Color, t: f32) -> rl.Color {
  lerp :: proc(x, y: u8, t: f32) -> u8 {
    return u8(math.round(f32(x) + (f32(y) - f32(x)) * t))
  }
  return {lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t), lerp(a.a, b.a, t)}
}

fade :: proc(c: rl.Color, alpha: f32) -> rl.Color {
  return {c.r, c.g, c.b, u8(f32(c.a) * alpha)}
}

// WCAG relative luminance and contrast ratio.
luminance :: proc(c: rl.Color) -> f32 {
  channel :: proc(v: u8) -> f32 {
    s := f32(v) / 255
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}

contrast :: proc(a, b: rl.Color) -> f32 {
  la, lb := luminance(a), luminance(b)
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// Red suits need to read on the card face; some themes' red is too pale.
// Try the bright variant, then pull it toward the ink until it reaches the
// WCAG 3:1 for large graphics.
MIN_SUIT_CONTRAST :: 3.0

legible_red :: proc(red, bright_red, face, ink: rl.Color) -> rl.Color {
  if contrast(red, face) >= MIN_SUIT_CONTRAST {
    return red
  }
  if contrast(bright_red, face) >= MIN_SUIT_CONTRAST {
    return bright_red
  }
  c := red
  for step in 1 ..= 10 {
    c = mix(red, ink, f32(step) * 0.08)
    if contrast(c, face) >= MIN_SUIT_CONTRAST {
      break
    }
  }
  return c
}

load_theme :: proc() -> Theme {
  p := load_palette()
  bg := colour(p, "background")
  fg := colour(p, "foreground")
  light := p["mode"] == "light" || luminance(bg) > 0.5
  face := fg
  ink := bg
  // The table sits a shade off the window background so the felt reads as a
  // surface, darker in dark themes and lighter in light ones.
  table := light ? mix(bg, rl.WHITE, 0.35) : mix(bg, rl.BLACK, 0.25)
  return Theme {
    table = table,
    face = face,
    ink = ink,
    red = legible_red(colour(p, "red", "color1"), colour(p, "bright_red", "color9", "red"), face, ink),
    back = colour(p, "accent"),
    back_mark = colour(p, "muted", "color8"),
    cursor = colour(p, "accent"),
    selection = colour(p, "selection", "selection_background", "accent"),
    hint = colour(p, "green", "color2"),
    text = fg,
    muted = mix(fg, bg, 0.45),
    light = light,
  }
}
