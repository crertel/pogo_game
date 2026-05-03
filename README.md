# Pogo Chasm

```text
        __        __        __
     __/  \__  __/  \__  __/  \__
    /  \__/  \/  \__/  \/  \__/  \
    \__/  \__/    \__/    \__/  \__/
       \__/          \__/       \__/

          hop the bright hexes
          do not trust the red ones
```

Pogo Chasm is a small Godot 4 first-person platforming prototype about crossing a floating hex bridge through a black chasm.

## Run

Enter the dev shell:

```bash
nix develop
```

Then:

```bash
just run
```

Open the editor:

```bash
just edit
```

Smoke-check the project:

```bash
just check
```

## Controls

- `WASD`: move
- `Mouse`: look
- `Space`: jump / double jump when available
- `RMB` or `E`: grapple when available
- `R`: restart run
- `Tab` or `F3`: toggle debug overlay and path markers
- `G`: reroll the current level
- `N`: skip to the next level
- `M`: force the end-of-level transition

## Structure

The run has 24 levels. Mechanics arrive in three-level arcs: new, practice, master. Each mechanic gets an isolated arc and then a combo arc.

- Double jump
- Bunny hop
- Grapple
- Exploding hexes
