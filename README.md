# pasians

Keyboard-first Klondike and FreeCell for Omarchy, written in Odin.

Step 1: the rules core in `game/` (no drawing, no I/O) and a terminal frontend for playing it.

```bash
odin test game
odin build . -out:pasians && ./pasians 1 -3
```

Run `./pasians [SEED] [-3]`, then type `?` for the list of commands. A seed always deals the same cards, because the shuffle uses its own splitmix64 instead of the system RNG.
