# dev/

Prototyping and measurement scripts. **None of this is shipping code** — it is
deliberately outside `src/`, which Rojo syncs. Nothing here is required for the
game to build or run.

| path | what it is |
|---|---|
| `rbxshim.luau` | Roblox API shim so real `src/` modules run under Lune on the command line |
| `analysis/` | measurement and verification scripts (`lune run dev/analysis/<x>.luau` from the repo root) |
| `skins/`, `tiermarks/`, `divine/` | standalone `BUILD_*.luau` rebuild scripts, pasted into the Studio command bar |

---

## The Studio MCP bridge times out even though the plugin is fine

**This has cost this project hours across several sessions. Read this before
debugging the plugin.**

### Symptom

Every Studio MCP tool call fails with:

```
Tool execution failed: Studio plugin connection timeout.
Make sure the Roblox Studio plugin is running and activated.
```

The message points at the plugin, so the natural response is to restart Studio,
reinstall the plugin, or go hunting for a watchdog kill. **All of that is wasted
time if the cause is the one below**, and none of it fixes anything.

### Cause

`robloxstudio-mcp` runs one server process **per client session**. Each tries to
bind port **3002** for the Studio plugin to talk to. Only the first one gets it;
the rest fall back to ephemeral ports and keep running perfectly happily.

So with several sessions open you get several servers, and there is no guarantee
the one *your* tools are wired to is the one the Studio plugin actually
connected to. When they differ, your server correctly reports "no plugin" —
because no plugin is attached *to it* — while the plugin sits fully alive on a
different port.

### Diagnosis

Ask each server whether it has the plugin. The one answering `pluginConnected:
true` is where Studio is:

```bash
for p in 3002 58741 58742 58743; do
  echo -n "$p: "; curl -s --max-time 3 "http://127.0.0.1:$p/status" || echo "(nothing)"
done
```

Find the candidate ports first if they are not the usual ones — on Windows:

```powershell
$nodePids = (Get-CimInstance Win32_Process -Filter "Name = 'node.exe'").ProcessId
Get-NetTCPConnection -State Listen | Where-Object { $nodePids -contains $_.OwningProcess } |
  Select-Object LocalPort, OwningProcess
```

A healthy server looks like:

```json
{"pluginConnected":true,"instanceCount":1,"instances":[{"role":"edit"}],"mcpServerActive":true}
```

**Confirming the plugin is alive does not mean your tools can reach it.** Those
are two different questions, and conflating them is the whole trap.

### `pluginConnected` lies in the other direction too

The recipe above has now produced a **false negative**: every port answered
`"pluginConnected":false`, with `instanceCount:0` and an empty `instances`
array, while `execute_luau` on two of those same ports ran perfectly and
returned the right place name. Studio was attached the whole time.

So `/status` is a hint, not an answer, and it can be wrong in *both*
directions — it can point at a server your tools are not wired to, and it can
deny holding a plugin it is holding. **Ask the server to do something instead
of asking it how it feels:**

```python
# the only trustworthy probe: a real tools/call
tools/call {"name": "execute_luau", "arguments": {"code": "return 1"}}
```

Cheap, unambiguous, and it fails for the one reason you care about. Anything
that reads `pluginConnected` and stops there will eventually send you off
restarting a plugin that was never broken — which is the same hour this file
already exists to save.

### The playtest flag gets stuck, and the play-mode targets may not route

Two separate failures, both hit in one session, both of which look like Studio
misbehaving and are not:

- **`start_playtest` refuses with `A test is already running` while the
  DataModel is in edit mode.** `get_playtest_output` reports `isRunning: true`;
  `execute_luau` in that same instant returns `IsRunning=false IsEdit=true`.
  The engine is right and the server's flag is stale. `stop_playtest` says
  `Playtest stop signal sent` and does not clear it, however many times it is
  called. **Trust `RunService:IsRunning()`, never `isRunning`.**

- **`target="server"` / `"client-1"` / `"client-2"` all time out during a
  playtest, while `target="edit"` runs inside the play CLIENT.** The plugin
  registers one instance and it is not the server. `dev/analysis/
  runtime_mesh_probe.luau`'s how-to-run section assumes those three targets
  work, so as written it cannot be driven from here.

**The workaround for both is to stop driving the runtime over the bridge at
all.** Write a `Script` into `ServerScriptService` and a `LocalScript` into
`StarterPlayerScripts`, press Play by hand, and read their `print`s back with
`get_output_log`. An installed script does not care how the bridge routes
anything — it runs because the engine runs it, in the real context.
`dev/legendary/U2_RUNTIME.luau` installs and removes exactly that pair.

`RunService:Run()` is plugin-reachable and looks like a way to get a server
context without the playtest machinery. It did **not** work here: the call
returned successfully and `IsRunning` stayed false. Do not spend a second
attempt on it.

**`get_playtest_output` returns nothing while the playtest is running fine.**
This one was misdiagnosed here first, and the correction is the useful part.
A `{"mode":"play","numPlayers":2}` call returned `Playtest started in play mode
with 2 player(s)`; sixty seconds of polling produced `outputCount: 0`, and
`execute_luau` kept reaching a DataModel reporting `IsRunning=false`. The
conclusion written here was "it claims success without starting anything."

**That was wrong.** Studio's own log file had the whole run in it —

```
21:31:23.992  [FLog::CreatorOutput] [U2RT server] context: IsServer=true IsClient=false
21:31:23.992  [FLog::CreatorOutput] [U2RT server] srv_white_TID via TextureID write=true
```

— six seconds after the call. The playtest started, the installed script ran on
a real server, and it printed. What failed was the bridge's output capture, and
what misled the follow-up check was that `execute_luau` was answering from a
DIFFERENT DataModel than the one running.

Two lessons, and the second is the general one:

- **Read `%LOCALAPPDATA%\Roblox\logs\*_Studio_*_last.log` directly.** Server
  and client `print`s land there as `[FLog::CreatorOutput]`, timestamped, with
  no bridge in the path. It is strictly better than `get_playtest_output` and
  it works after the playtest has ended.
- **A silent channel is not an idle system.** Every check available through the
  bridge agreed that nothing was happening, and all of them were reading the
  wrong end of it. When a tool reports absence, confirm the absence somewhere
  the tool cannot reach before believing it.

The stale `A test is already running` flag is real and does block later calls.
Pressing Play by hand sidesteps it entirely.

**`numPlayers` did not produce clients.** Both runs came back `IsServer=true`
with no player ever joining — the probe's `PlayerAdded` attach never fired and
printed nothing. So `numPlayers: 2` got a server-only run, which answers a
server-capability question and cannot answer a replication one. For anything
needing a real client, press Play in Studio.

### Rojo eats anything you install into a `$path` folder

Installed probes disappeared between being written and being read, with no
error, because nothing failed. `default.project.json` gives both
`ServerScriptService` and `StarterPlayer/StarterPlayerScripts` a `$path`, which
makes them **managed** folders: a sync prunes any child that is not on disk.
`workspace.U3Test` sat untouched through the same interval, which is the tell —
Workspace is not `$path`-managed (the project names only `Baseplate` under it).

Install runtime probes where Rojo has no opinion:

- **A `Script` in `Workspace` runs on the server** exactly as one in
  `ServerScriptService` does.
- **Create the `LocalScript` at runtime** — have the server clone it into each
  player's `PlayerGui` on join. There is no sync that can prune an instance
  created after the sync.

`dev/legendary/U2_RUNTIME.luau` does both.

### Fix

Do **not** kill the other node processes — they belong to other live sessions
and killing them breaks those.

The server exposes MCP over streamable HTTP at `POST /mcp`, so talk straight to
whichever port holds the plugin. `dev/analysis/` does not carry a client for
this because it is a workaround, not project code; the shape is small enough to
rebuild in a few minutes:

1. `POST /mcp` with `initialize`, keeping the `mcp-session-id` response header.
2. `POST` a `notifications/initialized` notification with that header.
3. `POST` `tools/call` with `{name, arguments}`, same header.

Send `Accept: application/json, text/event-stream`; replies come back as either
plain JSON or SSE `data:` frames, so handle both.

---

## A number stays computable after the thing it described stops existing

**This has now caught us four times, in four unrelated places** — the fourth
before it could do any damage, which is the interesting one. It is not a
Studio problem or a maths problem — it is what happens when a measurement
outlives the representation it was defined on. The code keeps running. The
number keeps printing. It looks healthy. It is describing something that is no
longer there.

### The four

| The number | What it was defined on | What it was being read as | What went wrong |
| --- | --- | --- | --- |
| White pixels counted down the pole, to check dot distribution | A projected view | "Do the dots cover their share of the crown?" | An axis-on view sees the pole face-on and the flanks edge-on, so it over-reads whichever pole faces the camera *regardless of placement*. It moved 46.1% → 42.8% while the real error halved. It was measuring projection. |
| IoU between adjacent ladder rungs | Two binary masks | "Are these two tiers distinguishable?" | IoU measures *where the white sits*. Perceived rarity is not that. It called Uncommon → Rare the tight pair; the eye called Rare → Epic, and the eye was right. |
| Feature size 2A/P, on a ramp | A mask with a boundary | "Is the smallest visible feature above 8 px?" | A ramp's mask edge is invisible by design — the flame tip fades to the body colour. The number described a contour nobody can see, and it stayed comfortably above the floor while saying nothing. |
| Feature size 2A/P again, on the upload round trip | The paint rig’s mark mask | "Did Roblox’s encode eat tiger’s narrowest bar?" | 2A/P is a **mean** characteristic width over the whole mark set, and the wide bars carry it. Simulated offline it moved +1.8% through JPEG q50 and +5.2% through a 4x downsample that destroys the sheet, never approaching the 8 px floor. It cannot fail, so passing it is not evidence. |

### The rule

When the representation changes, **re-derive the metric from the thing you
actually care about** — do not keep reading the old number because the old code
still runs. In the first three the fix was to go back to the question:

- not "white per pole view" but *white share per height band on the texel set*;
- not "how much do the masks overlap" but *look at the grid*;
- not "how wide is the mask" but *how wide is the region that visibly differs
  from the body*.

The fourth had no lapsed representation to re-derive from — 2A/P still measures
exactly what it always measured. What lapsed was the QUESTION it was being put
to. So the fix there was not a new metric but a **measured sensitivity**: keep
printing 2A/P, label it as a floor check that cannot fail, and read the verdict
off the numbers that were shown to move.

Three habits that catch it earlier:

- **If a metric inverts or loses meaning for a class of inputs, switch it off
  for that class.** Do not annotate it and print it anyway. `J` and `lit` are
  not computed for ramp variants, because fire is a height field and would
  score as "lighting could have drawn this" while being brightest where the
  light is dimmest — the opposite of what a high score means everywhere else.
- **Simulate the failure before trusting the metric.** This is what caught the
  fourth one in advance, and it is cheap: take the artefact you have, damage it
  the way the real process might, and check that the number notices.
  `dev/legendary/encode_probe.py` puts the baked sheet through four JPEG
  qualities and two downsample round-trips and scores every candidate metric on
  all six. It took minutes, and it moved the verdict off a number that could not
  fail and onto two that track the damage monotonically. **A metric with no
  measured sensitivity is a guess about a guess.**
- **Keep printing the lapsed number, labelled.** `EXPLORE_PATTERNS` prints the
  ramp mask width as `(mask says N, which is not the number to read)`. Deleting
  it invites the next person to recompute it and trust it; labelling it spends
  one line and closes the question.

### The tell

Ask of any number in a report: *what would have to change about the object for
this to become wrong, and would the number notice?* A metric that cannot notice
its own irrelevance needs a guard, not a comment.

### More traps once you are through

- **`execute_luau` is capped at ~30 s.** A longer script does *not* stop when the
  call returns — it keeps running inside Studio while your bridge reports a
  timeout. Two of those overlapping will interleave on the main thread and
  corrupt any timing the script measures. For long work, wrap it in
  `task.spawn`, return immediately, and poll a `workspace` attribute for the
  result.
- **`os.clock()` cannot see a yield.** It measures wall time, so a span that
  parks inside an Async engine call looks exactly like a span that blocked the
  main thread. Any "did this stall?" measurement has to exclude known-yielding
  calls explicitly — see `newYielder`'s `mark()` in `skins/BUILD_GALAXY.luau`.
- **The viewport ignores a camera rotation written from a plugin.** Studio's
  edit-mode navigation owns `CurrentCamera` and re-asserts its own rotation every
  frame. Position survives, rotation does not, and reading the property straight
  back returns *your* value — so it looks like it worked while the viewport keeps
  rendering from wherever the user last dragged. Set
  `CameraType = Enum.CameraType.Scriptable` **before** writing `CFrame`, and set
  it back to `Fixed` when done or the viewport is left unnavigable. Verify with
  `cam:WorldToViewportPoint(target)`, never with the screenshot or the CFrame:
  a negative depth means the subject is behind a camera standing in exactly the
  right place. `skins/AIM.luau` does all of this.
- **A screenshot needs Studio to be the foreground window.** Background Studio
  throttles rendering, `capture_screenshot` never gets a frame, and it fails with
  "Ensure the Studio viewport is visible" — which reads like a tab-focus problem
  and is not. Foreground the window first. Captures can also lag a frame or two
  behind a camera move, so settle before shooting, and be aware that two captures
  of an *unchanged* view still differ byte-for-byte because the sky animates:
  comparing file hashes proves nothing.
