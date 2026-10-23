package main

import rl "vendor:raylib"

import "game"

// The Win95 victory: cards leave the foundations one at a time, kings first,
// fall and bounce off the bottom. They are drawn into a render texture that
// is never cleared, so every position stays stamped and leaves the trail.

GRAVITY :: 2600.0 // px/s² at unit scale
DAMPING :: 0.7
STEP :: 1.0 / 240.0
STAMP_EVERY :: 4 // steps between stamps: separate cards, like Win95, not a ribbon

Launch :: struct {
  card:       game.Card,
  foundation: int,
  below:      Maybe(game.Card), // what the foundation shows once it leaves
}

Bounce :: struct {
  active:  bool,
  rt:      rl.RenderTexture2D,
  layout:  Layout,
  queue:   [52]Launch,
  len:     int,
  next:    int,
  flying:  bool,
  card:    game.Card,
  pos:     rl.Vector2,
  vel:     rl.Vector2,
  rng:     game.Rng,
  carry:   f32,
  steps:   int,
}

bouncing :: proc() -> bool {
  return app.bounce.active
}

dpi_scale :: proc() -> f32 {
  return f32(rl.GetRenderWidth()) / f32(rl.GetScreenWidth())
}

begin_stamp :: proc() {
  rl.BeginTextureMode(app.bounce.rt)
  rl.BeginMode2D({zoom = dpi_scale()})
}

end_stamp :: proc() {
  rl.EndMode2D()
  rl.EndTextureMode()
}

start_bounce :: proc() {
  b := &app.bounce
  stop_bounce()
  b.layout = compute_layout(&app.g)
  b.len = 0
  for rank := game.KING; rank >= game.ACE; rank -= 1 {
    for f, i in app.g.foundations {
      if f.len >= rank {
        launch := Launch{card = f.cards[rank - 1], foundation = i}
        if rank > 1 {
          launch.below = f.cards[rank - 2]
        }
        b.queue[b.len] = launch
        b.len += 1
      }
    }
  }
  b.next = 0
  b.flying = false
  b.rng = {u64(rl.GetTime() * 1e6) | 1}
  b.rt = rl.LoadRenderTexture(rl.GetRenderWidth(), rl.GetRenderHeight())
  b.active = true

  begin_stamp()
  draw_scene(false)
  end_stamp()
}

stop_bounce :: proc() {
  b := &app.bounce
  if b.active {
    rl.UnloadRenderTexture(b.rt)
  }
  b.active = false
}

random_between :: proc(r: ^game.Rng, lo, hi: f32) -> f32 {
  return lo + (hi - lo) * f32(game.rng_below(r, 10_000)) / 10_000
}

update_bounce :: proc(dt: f32) {
  b := &app.bounce
  if !b.active {
    return
  }
  l := b.layout
  // A resized window would leave the texture and the table out of step.
  if l.w != f32(rl.GetScreenWidth()) || l.h != f32(rl.GetScreenHeight()) {
    stop_bounce()
    return
  }
  b.carry += min(dt, 0.1)
  begin_stamp()
  defer end_stamp()
  for b.carry >= STEP {
    b.carry -= STEP
    if !b.flying {
      if b.next >= b.len {
        stop_bounce_soon()
        return
      }
      launch := b.queue[b.next]
      b.next += 1
      slot := slot_rect(l, &app.g, game.foundation(launch.foundation))
      // Uncover what's left on the foundation.
      draw_table_patch(l, slot)
      if below, ok := launch.below.?; ok {
        draw_card(l, below, slot)
      } else {
        draw_empty_slot(l, slot, "A")
      }
      b.card = launch.card
      b.pos = {slot.x, slot.y}
      dir: f32 = game.rng_below(&b.rng, 2) == 0 ? -1 : 1
      b.vel = {dir * random_between(&b.rng, 180, 520) * l.unit, -random_between(&b.rng, 0, 700) * l.unit}
      b.flying = true
    }
    b.vel.y += GRAVITY * l.unit * STEP
    b.pos += b.vel * STEP
    if b.pos.y + l.card_h > l.floor {
      b.pos.y = l.floor - l.card_h
      b.vel.y = -b.vel.y * DAMPING
    }
    if b.pos.x > l.w || b.pos.x + l.card_w < 0 {
      b.flying = false
      continue
    }
    b.steps += 1
    if b.steps % STAMP_EVERY == 0 {
      draw_card(l, b.card, {b.pos.x, b.pos.y, l.card_w, l.card_h})
    }
  }
}

// Leaves the finished picture up until a key is pressed.
stop_bounce_soon :: proc() {
  app.bounce.flying = false
  app.bounce.next = app.bounce.len
}

draw_table_patch :: proc(l: Layout, r: rl.Rectangle) {
  rl.DrawRectangleRec(inflate(r, 3 * l.unit), app.theme.table)
}

draw_bounce :: proc() {
  b := &app.bounce
  w, h := f32(b.rt.texture.width), f32(b.rt.texture.height)
  rl.DrawTexturePro(b.rt.texture, {0, 0, w, -h}, {0, 0, b.layout.w, b.layout.h}, {}, 0, rl.WHITE)
}
