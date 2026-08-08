# Chest reveal: built

The slime now rises out of the chest, on the platform, in front of a player who keeps control
of their camera the whole time. Four files changed.

**Both things you asked me to be careful about came back clean, and one of them was the
diagnosis I was least sure of.** §1 and §2.

**Verification:** static analysis and reading only. All files parse. No playtest was run.

---

## 1. Box-neutrality — provable, not argued

The concern was right to raise, and the answer turned out better than I expected when I read
the code properly.

**`showSlimeReveal` was the *only* place the box leaked into the reveal.** Everything
downstream — `entranceCFrame`, `updateSlimeReveal`, the hover — already reads a dedicated
`slimeRevealRestCFrame`, not `boxRestCFrame`. So there was exactly one derivation to redirect,
and it is this:

```lua
-- before
local centre = boxRestCFrame.Position
slimeRevealRestCFrame = CFrame.lookAt(centre, centre + boxRestTowardPlayer)

-- after
local centre = if revealAnchorCFrame then revealAnchorCFrame.Position else boxRestCFrame.Position
local toward = revealAnchorToward or boxRestTowardPlayer
slimeRevealRestCFrame = CFrame.lookAt(centre, centre + toward)
```

**When `revealAnchorCFrame` is nil, those two lines evaluate to the literal expressions they
replaced.** Not "equivalent" — the same operands, the same call, the same result.

Every difference on the chest path is behind the same nil check:

| what | box path (anchor nil) | chest path |
|---|---|---|
| rest position | `boxRestCFrame.Position` — unchanged | chest top face + lift |
| facing | `boxRestTowardPlayer` — unchanged | +Z, back down the road |
| build width | `SlimeConfig.SLIME_REVEAL_WIDTH_STUDS` — unchanged | `CHEST_REVEAL_WIDTH_STUDS` |
| rise / entrance | `SlimeConfig.SLIME_REVEAL_*` — unchanged | `CHEST_REVEAL_*` |
| `PointLight` | not created | Divine only |
| camera, character hiding, HUD suppression, dismissal | **not touched at all** | not taken |

### Why the anchor can never be set on a box landing

Not by inspection — structurally. `showWorldBox` calls `endRewardScene()` as its **first**
statement, and `endRewardScene` now clears the anchor. So any box landing wipes a leftover chest
anchor before it can be read, on the same line that already wipes a leftover box and a leftover
reveal slime. There is no ordering in which a box reveal sees a chest anchor.

**Same position, same camera, same dismissal.** The camera code, `releaseBoxCamera`,
`releaseHiddenCharacter`, `releaseSuppressedHuds`, `dismissRevealAndReturn` and the `InputBegan`
branches were not edited at all — verified by diff, not by memory.

---

## 2. The 180s abandon path — traced, and it is covered

You were right to make me check, and the answer is **it reaches `setGrounded`**:

```
server: abandon timer → moveToLaneReturn → resetReadyRemote:FireClient
client: resetReadyRemote.OnClientEvent  (line 2668)
          → canRelease = true
          → resetFlightState()
          → setGrounded(true)            ← line 2681
              → hideFlightBoxRevealUI()
                  → endRewardScene()
                      → destroySlimeReveal()   ← the model dies
                      → revealAnchorCFrame = nil
```

So a player who opens the chest and then idles out gets the reveal torn down correctly. **No
leak, and no fix needed** — the concern I flagged as unconfirmed was unfounded. The handler's
own comment says exactly why it works: `setGrounded(true)` was deliberately made the central
teardown so "every OTHER path back to grounded gets the exact same guarantee, not just this
one." The abandon path benefits from a decision made before it existed.

### Every teardown path, re-checked against the built reveal

| path | route | model destroyed | anchor cleared |
|---|---|---|---|
| dismiss (MB1/touch) | `dismissRevealAndReturn` → `endRewardScene` | yes | yes |
| death / respawn | `CharacterAdded` → `setGrounded` → `hideFlightBoxRevealUI` | yes | yes |
| **abandon timeout (180s)** | `ResetReady` → `setGrounded(true)` → … | **yes** | **yes** |
| disconnect | client session ends; the model is client-only | yes | n/a |
| a later box landing | `showWorldBox` → `endRewardScene` first | yes | yes |
| mount / dismount | `setGrounded(false)` → `hideFlightBoxRevealUI` | yes | yes |

**Single acquire, single release, unchanged in structure.** The anchor is set in one place (the
`ChestRevealStarted` handler) and cleared in one place (`endRewardScene`), alongside the camera
and character hiding that already worked that way. The Divine `PointLight` is parented to the
reveal **model**, so `destroySlimeReveal` takes it with everything else — no second registry, no
seventh row in this table.

---

## 3. What was built

**A new remote, `ChestRevealStarted`**, fired immediately before `SlimeRevealed` and only on a
chest open. It carries the anchor CFrame and the facing vector. Order is guaranteed rather than
hoped for: both are RemoteEvents to the same client, which Roblox delivers in send order.

It carries the CFrame rather than having the client look up
`Workspace.GiantSlimeLandmark.TreasureChest`, so the client never learns the landmark's
structure — the same "send what the receiver needs, not where to find it" shape every other
remote here uses.

**The anchor** is the chest's own top face, derived from the lid's closed CFrame plus half its
height, so it tracks the chest wherever `MapBuilder` put it. `toward` is +Z — back down the
road, the direction the player walked in from — so the mesh's face (−Z, per `SlimeBuilder`'s
measured `MESH_FACE_AXIS`) meets them without correction.

**Reused, not duplicated:** `SlimeBuilder` for the model, the existing name/tier/NEW billboard
verbatim (tier colour, per-tier `TextSize`, asterisk flourish all carry over), the existing
entrance/hover/scale animation, and the existing dismissal with its `REVEAL_DISMISS_LOCKOUT_SECONDS`
— so a click already in flight from the 1.0s prompt hold cannot skip it, which was the specific
failure the lockout exists for and applies here unchanged.

**Its own numbers, in `TreasureConfig`:** 26 studs wide against the box reveal's 16, rising 9,
settling 14 above the chest's top face, over 0.9s against the box's 0.35s. The box's constants
are tuned for a slime at arm's length on a framed camera; this one is seen from wherever a
walking player happens to be standing under a 1,050-stud landmark. Bigger and slower is the
whole difference.

### Divine

Two changes, both to the **shape** of the moment rather than its decoration:

1. **It takes twice as long and settles higher** — 1.8s against 0.9s, 8 studs higher. Time is
   the strongest signal available in a game where everything else resolves fast.
2. **A `PointLight` in the slime's own tier colour** on the model, 90-stud range. Under a giant
   slime on an open platform this reads instantly and costs one instance.

**Deliberately no screen effect** — no flash, no shake, no full-screen anything. That is the
mystery box's idiom, and reusing it would blur exactly the distinction that makes walking to
this reward different from being played at. At a 20% rate roughly one chest in five is Divine,
which also rules out anything expensive or long on repetition grounds.

`DIVINE_TIER_INDEX` is derived as `#SLIME_TIER_NAMES`, not written as 8, so it keeps meaning
"the top tier" if that list grows.

### The camera: not taken

As specified and for the reason given last pass — `beginChestLanding` unanchors precisely so the
player can walk, and taking the camera at the moment they arrive would undo the one thing that
makes this reward different. There is a mechanical argument too: `releaseBoxCamera` only eases
its return when there is still a frozen character to frame, so on an unfrozen chest player it
would snap rather than ease. The `ChestRevealStarted` handler touches the camera, character
visibility and HUD suppression **not at all**.

### Also fixed in passing

The lid's re-close timer was borrowing `CHEST_ABANDON_SECONDS` — two unrelated concerns sharing
one number, which I flagged as a shortcut last pass. Split into `CHEST_LID_RECLOSE_SECONDS`
(45s): long enough that the opener never sees it shut in front of them, short enough that the
next visitor finds a closed chest.

---

## 4. Files

| file | change |
|---|---|
| `Config/TreasureConfig.luau` | reveal size/rise/height/entrance, Divine entrance/height/light, lid re-close |
| `LaunchServer.server.luau` | `ChestRevealStarted` declared + fired with the anchor; lid timer split |
| `LaunchClient.client.luau` | anchor state + handler; `showSlimeReveal` reads the anchor; Divine light; `endRewardScene` clears it |
| `REPORT.md` | this |

Nothing on the exclusion list was touched: the roll table, the 20% Divine, tier 11's reach and
snap, the luck distribution, the crown, the pending-chest flag, `SlimeBuilder`, `SignBuilder`,
and the mystery box's sequence, camera, character hiding and dismissal are all unmodified.

---

## 5. What I could not verify

Static analysis only — everything above is read off the code, not observed. What a playtest
would settle, in the order I would look:

1. **Is 26 studs the right size and 14 the right height** from where the player actually stands?
   The chest is 68 studs from the landing point, so the slime is read at that range against a
   1,050-stud backdrop. This is the number most likely to want a nudge, and it is one config
   value.
2. **Does the slime clear the open lid**, or does the lid at 100° intersect it? The lift is
   computed from the chest's top face, and the lid rotates up and back, so it should — but I
   have not seen either move.
3. **The Divine light's range and brightness** against Roblox's default outdoor lighting at that
   time of day. 90/6 is a guess.
4. **The billboard's readability** at that distance — it is sized in pixels, so it does not
   shrink, but it was positioned for a 16-stud slime and this one is 26.

None of these can strand a player or cost a reward: the slime is awarded server-side before any
of this renders, and every teardown path is confirmed above.
