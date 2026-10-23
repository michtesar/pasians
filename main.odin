package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import rl "vendor:raylib"

import "game"

FONT_SIZE :: 160

USAGE :: `usage: pasians [options]
  --mode klondike|freecell   game to start (default: last played)
  --deal N                   seed, or FreeCell game number
  --daily                    today's deal
  --keys KEYS                type KEYS at start (testing)
  --shot PATH                save a PNG after --frames frames and quit (testing)
  --frames N                 frames before --shot (default 30)
  --win                      start with a won game (testing the animation)
  --install-hook             reload colours instantly on Omarchy theme switches`

HOOK :: #load("extras/theme-set-hook", string)

// Drops the hook into Omarchy's theme-set.d, which omarchy-theme-set runs
// after every switch. Without it the once-a-second check still catches up.
install_hook :: proc() {
  dir := strings.concatenate({os.get_env("HOME", context.temp_allocator), "/.config/omarchy/hooks/theme-set.d"}, context.temp_allocator)
  path := strings.concatenate({dir, "/pasians"}, context.temp_allocator)
  if err := os.make_directory_all(dir); err != nil && err != .Exist {
    fmt.eprintfln("pasians: can't create %s: %v", dir, err)
    os.exit(1)
  }
  if err := os.write_entire_file(path, transmute([]byte)string(HOOK)); err != nil {
    fmt.eprintfln("pasians: can't write %s: %v", path, err)
    os.exit(1)
  }
  fmt.println("installed", path)
}

// Font for ranks and UI: the user's monospace font through fontconfig, which
// on Omarchy is the theme font; raylib's built-in pixel font as a last resort.
load_font :: proc() -> rl.Font {
  candidates := make([dynamic]string, context.temp_allocator)
  state, out, _, err := os.process_exec({command = {"fc-match", "-f", "%{file}", "monospace:bold"}}, context.temp_allocator)
  if err == nil && state.exit_code == 0 && len(out) > 0 {
    append(&candidates, string(out))
  }
  append(&candidates, "/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf")

  codepoints := make([dynamic]rune, context.temp_allocator)
  for r in rune(32) ..= 126 {
    append(&codepoints, r)
  }
  for r in "·–←→↑↓" {
    append(&codepoints, r)
  }
  for path in candidates {
    if !os.exists(path) {
      continue
    }
    cpath := strings.clone_to_cstring(path, context.temp_allocator)
    font := rl.LoadFontEx(cpath, FONT_SIZE, raw_data(codepoints), i32(len(codepoints)))
    if font.texture.id != 0 && font.glyphCount > 0 {
      rl.GenTextureMipmaps(&font.texture)
      rl.SetTextureFilter(font.texture, .TRILINEAR)
      return font
    }
  }
  return rl.GetFontDefault()
}

reload_theme :: proc() {
  app.theme = load_theme()
  app.theme_stamp = theme_stamp()
  if app.has_wallpaper {
    rl.UnloadTexture(app.wallpaper)
    app.has_wallpaper = false
  }
  path := strings.clone_to_cstring(wallpaper_file(), context.temp_allocator)
  if rl.FileExists(path) {
    app.wallpaper = rl.LoadTexture(path)
    app.has_wallpaper = app.wallpaper.id != 0
  }
}

// The hook's signal is the fast path; the stamp check once a second catches
// a theme switch on a machine without the hook installed.
check_theme :: proc() {
  if sync.atomic_exchange(&theme_reload_requested, false) {
    reload_theme()
    return
  }
  now := rl.GetTime()
  if now < app.theme_check {
    return
  }
  app.theme_check = now + 1
  if theme_stamp() != app.theme_stamp {
    reload_theme()
  }
}

// Test hook: type keys as if pressed.
feed_keys :: proc(keys: string) {
  for ch in keys {
    if app.cmdline_open {
      if ch == '\n' {
        app.cmdline_open = false
        execute(strings.clone(string(app.cmdline[:]), context.temp_allocator))
      } else {
        append(&app.cmdline, u8(ch))
      }
    } else if ch >= '1' && ch <= '9' {
      handle_digit(int(ch - '0'))
    } else {
      handle_char(ch)
    }
  }
}

fail_usage :: proc() {
  fmt.eprintln(USAGE)
  os.exit(2)
}

main :: proc() {
  // First, before anything slow: SIGUSR1 would otherwise kill the process.
  watch_theme_signal()

  mode_arg := ""
  deal_arg := -1
  daily := false
  keys := ""
  shot := ""
  frames := 30
  win := false

  args := os.args[1:]
  for i := 0; i < len(args); i += 1 {
    value :: proc(args: []string, i: ^int) -> string {
      i^ += 1
      if i^ >= len(args) {
        fail_usage()
      }
      return args[i^]
    }
    switch args[i] {
    case "--mode":
      mode_arg = value(args, &i)
    case "--deal":
      deal_arg = strconv.parse_int(value(args, &i)) or_else -1
    case "--daily":
      daily = true
    case "--keys":
      keys = value(args, &i)
    case "--shot":
      shot = value(args, &i)
    case "--frames":
      frames = strconv.parse_int(value(args, &i)) or_else 30
    case "--win":
      win = true
    case "--install-hook":
      install_hook()
      return
    case "-h", "--help":
      fmt.println(USAGE)
      return
    case:
      fail_usage()
    }
  }

  rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .MSAA_4X_HINT, .VSYNC_HINT})
  rl.SetTraceLogLevel(.WARNING)
  rl.InitWindow(1280, 860, "pasians")
  defer rl.CloseWindow()
  rl.SetWindowMinSize(800, 560)
  rl.SetExitKey(.KEY_NULL)
  rl.SetTargetFPS(60)

  app.font = load_font()
  app.save = load_save()
  reload_theme()

  mode := app.save.settings.mode == "freecell" ? game.Mode.FreeCell : game.Mode.Klondike
  switch mode_arg {
  case "":
  case "freecell":
    mode = .FreeCell
  case "klondike":
    mode = .Klondike
  case:
    fail_usage()
  }
  if daily {
    start_daily(mode)
  } else if deal_arg >= 0 {
    start_game(mode, u64(deal_arg))
  } else {
    new_random_game(mode)
  }
  if win {
    for suit, i in game.Suit {
      app.g.foundations[i] = {}
      for rank in u8(game.ACE) ..= game.KING {
        game.pile_push(&app.g.foundations[i], {rank, suit, true})
      }
    }
    for &p in app.g.tableau {
      p.len = 0
    }
    app.g.stock.len, app.g.waste.len = 0, 0
    app.counted = false
    after_change()
  }
  feed_keys(keys)

  frame := 0
  for !rl.WindowShouldClose() && !app.quit {
    free_all(context.temp_allocator)
    check_theme()
    handle_keys()
    handle_mouse()
    update_bounce(rl.GetFrameTime())

    rl.BeginDrawing()
    l := compute_layout(&app.g)
    if bouncing() {
      draw_bounce()
      if app.bounce.next >= app.bounce.len && !app.bounce.flying {
        draw_won_banner(l)
      }
    } else {
      draw_scene(true)
      if app.won {
        draw_won_banner(l)
      }
    }
    switch app.overlay {
    case .None:
    case .Help:
      draw_help(l)
    case .Stats:
      draw_stats(l)
    }
    rl.EndDrawing()

    frame += 1
    if shot != "" && frame == frames {
      img := rl.LoadImageFromScreen()
      rl.ExportImage(img, strings.clone_to_cstring(shot, context.temp_allocator))
      rl.UnloadImage(img)
      break
    }
  }
  abandon_game()
}
