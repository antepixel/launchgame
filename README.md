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

## Pre-launch checklist

- [ ] **Delete the dev panel.** It's a Studio-only testing tool (money/slime/base/
      save cheats) and must not ship. It's already hard-gated so a forgotten
      deletion is harmless in a published server (see below), but delete it anyway
      before publishing. Delete these four files:
      - `src/ReplicatedStorage/Config/DevConfig.luau`
      - `src/ServerScriptService/DevPanelServer.server.luau`
      - `src/StarterPlayer/StarterPlayerScripts/DevPanelClient.client.luau`
      - the `-- ===== DEV PANEL SUPPORT =====` ... `-- ===== END DEV PANEL SUPPORT
        =====` block near the bottom of `src/ServerScriptService/PlayerProfile.luau`
        (everything between those two markers, inclusive)

      Every file above it starts with a `-- TODO: REMOVE BEFORE LAUNCH` banner.
      Why it's safe even if you forget: the server half hard-gates on
      `RunService:IsStudio()` before creating anything, so in a published server no
      dev remote is ever created at all -- there is nothing for a client to call, not
      just a check that rejects the call. A second, independent check (a UserId
      allowlist in `DevConfig.luau`, re-checked on every action) protects it even if
      the Studio gate is ever loosened by mistake.
