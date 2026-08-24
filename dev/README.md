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
