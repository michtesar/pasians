# pasians

Keyboard-first Klondike and FreeCell for Omarchy, written in Odin with raylib. It takes its colours from the active Omarchy theme and switches with it live.

## Build and install

```bash
make test
make install
```

`make install` puts the binary, desktop entry and icon under `~/.local` (`PREFIX=` to change it). On Omarchy it also installs the theme-set hook, and copies the Hyprland window rule to `~/.config/hypr/pasians.lua`. Add `require("hypr.pasians")` to `~/.config/hypr/hyprland.lua` to load it. The rule floats the window, centres it and fixes its size; the file also has a commented-out `SUPER + ALT + P` binding.

A `PKGBUILD` for the AUR is included.

## Keys

| Key | Action |
|---|---|
| `h` `l` / `←` `→` | previous / next pile |
| `j` `k` / `↓` `↑` | fewer / more cards from a column; `k` past the run goes up to the top row, `j` comes back |
| `1`–`8` | jump to column |
| `Space` / `Enter` | pick up / put down (on the stock: draw) |
| `t{n}` | move the held cards, or the cards under the cursor, to column n |
| `f` | send the card to its foundation |
| `F` | send every card that is safe to the foundations |
| `c` | park the card in a free cell (FreeCell) |
| `s` | draw (Klondike) |
| `u` / `Ctrl-r` | undo / redo |
| `.` | repeat the last command (`s`, `f`, `F`, `t{n}`, `c`) from where the cursor is now |
| `3s`, `2u`, `4.` | count prefix |
| `H` | hint: the solver's next move when it finds a win, else the most promising move |
| `?` | help |
| `Esc` | cancel |

Command line: `:new`, `:daily`, `:restart`, `:deal N`, `:mode klondike|freecell`, `:draw 1|3`, `:stats`, `:wallpaper`, `:q`.

A digit both jumps to its column and sets a count. When `s`, `u`, `Ctrl-r` or `.` follows, the jump is taken back. Digits are read as key codes, so the number row works on layouts where it types letters, Czech included.

The mouse works too: click to pick up and put down, double-click to send a card to its foundation.

## How it works

- `game/` is the pure core, with no drawing or I/O, covered by `odin test game`. It holds the rules for both games, the deals, a solver and the daily seed.
- The whole game state is one value. Undo stores a copy of it after every command, and redo is a second stack.
- Klondike deals come from a seed through our own splitmix64. The same seed gives the same deal on every machine and in every version.
- FreeCell uses the Windows deal generator, so `:deal 11982` is the famous unsolvable one.
- Daily deals hash the date and mode. FreeCell maps that hash onto the 32000 Windows deals and skips #11982. Klondike tries seed, seed+1, … until the solver proves a win. If none is proven within 32 tries, the status bar calls it a daily challenge.
- Stats live in `$XDG_DATA_HOME/pasians/stats.json`, kept separately for Klondike draw 1, Klondike draw 3 and FreeCell.
  - A daily counts only the first time it is started; a restart is practice.
  - Leaving a game you have played in counts as a loss.
- Theme colours come from `omarchy-theme-color --all`, so pasians resolves the same palette as every other themed app. Outside Omarchy it reads `colors.toml` directly, and without either it falls back to Tokyo Night.
  - Card faces are the theme's `foreground` and their ink is its `background`, so light themes get dark cards.
  - Red suits must reach WCAG 3:1 against the card face. Otherwise pasians tries `bright_red`, then darkens the red until it passes.
  - Card backs carry the Omarchy logo (`U+E900` from Omarchy's icon font) in the theme's accent. The font is found through fontconfig, `/usr/share/fonts/omarchy/` or `$OMARCHY_PATH`; without it the backs fall back to a diamond pattern.
- The theme-set hook sends `SIGUSR1` and the colours reload at once. Without the hook, a once-a-second check of `colors.toml` and the wallpaper catches the change.
- The Linux build uses Odin's bundled raylib, which talks to X11, so it runs under XWayland. Omarchy sets `force_zero_scaling`, so the window renders at native resolution, and the layout scales with the window size.

## Testing flags

`--deal N`, `--mode`, `--daily`, `--keys KEYS` (typed at start; `:cmd\n` works), `--click X,Y` (repeatable), `--autoplay` (replays the solver's win through the same pick-up-and-drop path a player uses), `--shot PATH --frames N` (save a PNG and quit) and `--win` (start on the victory animation).
