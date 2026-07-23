# launchgame

Launch-and-collect prototype. This build is **only** the launch mechanic: ride a
swing that sweeps on its own arc forever, release at the right moment, fly,
measure distance, reset. Nothing else exists yet on purpose.

## Workflow

`src/` is the only thing you ever edit. `game.rbxlx` is a generated build artifact,
never hand-edited, and never committed (see `.gitignore`).

```
src/  -->  rojo build default.project.json -o game.rbxlx  -->  open game.rbxlx in Studio
```

Re-run the build command any time `src/` changes, then reopen (or use `rojo serve`
with the Rojo Studio plugin for live sync instead of rebuilding a file each time).

## Tuning

Every feel-related constant (launch speed range, launch angle, gravity, landing
detection, reset delay, swing period/arc/rope length, sweet-spot position and
width) lives in one place: `src/ReplicatedStorage/Config/LaunchConfig.luau`.
Change numbers there; no other script should need editing to retune the feel.
