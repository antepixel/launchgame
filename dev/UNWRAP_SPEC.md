# Re-unwrap spec — `slime_uv` body mesh

**Asset:** `rbxassetid://105035515248342` (the model in `workspace.slime_uv`)
**Why:** the current unwrap is *not injective* on the underside — two different
patches of the body land on the same texels — and it uses only 32.8% of the
sheet. The first causes the smudge under the slime; the second wastes two thirds
of the texture memory.

This is a spec, not a tutorial in unwrapping. It says what the result has to
satisfy and how to check it. Every number below was measured off the current
mesh, so they are the "before" values to beat.

---

## What is wrong today

| measured | now | target |
|---|---|---|
| `u` range | **0.0000 .. 1.2517** | 0 .. 1 exactly |
| `v` range | 0.3340 .. 0.6907 | 0 .. 1 |
| sheet used by the island | **32.8%** | ≥ 85% |
| texels claimed by two disagreeing faces | **3.84% of the island** (3290 at 512²), 96% of them below the equator, worst disagreement 0.77 body-radii | **0** |
| tears (sheet-neighbours far apart in 3D) | **26**, all in sheet rows 332–335 | **0** |
| texel density spread (p95/p05 step) | **3.40** | < 3 |
| triangles straddling the `u` wrap | **2** | **0** |
| stray geometry | a unit cube, 24 verts / 12 faces, ~500 units above the body | deleted |

The `u` overshoot past 1.0 and the contested texels are the same defect seen from
two directions: geometry is mapped outside the 0..1 square, wraps back round, and
lands on texels another face already owns.

---

## Requirements

**R1 — Injective.** No two points on the body may map to the same point in UV
space. This is the one that fixes the smudge. Everything else is optimisation.

**R2 — The underside gets its own chart.** It is a concave bowl; no single
projection can cover it and the outer dome injectively, which is exactly why it
folds today.

**R3 — `u` and `v` both inside 0..1**, with no overshoot and nothing negative.

**R4 — The island fills the sheet**, ≥ 85% after packing. Going from 32.8% to 85%
is 2.6× the area, so **1.61× the linear resolution for the same memory** — a 512
sheet would then resolve like an 824.

**R5 — Zero straddling triangles.** Every triangle must lie wholly inside one
chart. The seam must be a real cut with duplicated UV vertices.

**R6 — Chart padding ≥ 8 texels** at the working resolution (512), so mip
generation cannot blend one chart into its neighbour. In Blender terms that is a
pack margin of about **0.016**.

---

## Seam placement

The patterns are evaluated **in 3D**, not in UV space. That has a consequence
worth being explicit about, because it is counter-intuitive:

> **A UV seam does not put a seam in the pattern.** The stripe field is a
> function of the 3D point, so it is continuous across any cut you make. You are
> free to place the seam wherever is convenient for the unwrap.

What a seam *does* cost is filtering: bilinear and mip sampling blend across
chart edges in the sheet, which is what R6's padding is for.

So:

- **Put the meridian seam at the BACK**, opposite the face. The face points along
  roughly `(-0.62, +0.05, -0.78)` in body-local coordinates, so the back is
  `(+0.62, -0.05, +0.78)`. Any residual filtering error then lands where nobody
  looks.
- **One meridian cut only**, from the rim to the crown.
- **Cut the rim** where the outer dome meets the underside — that is the boundary
  between chart 1 and chart 2.

Do **not** cut along a line of latitude anywhere else. A latitude cut puts a
horizontal chart edge across the middle of the body, and every stripe crosses it.

---

## Step by step

Written for someone who has done one cylindrical unwrap. If a step does not look
like the description, the **"if it looks wrong"** note under it says what to do.

### 1. Delete the stray cube

Open the mesh. There is a unit cube floating about 500 units above the body,
left over from the original import.

Select it (box-select well above the body — nothing else is up there) and delete
it. Vertex count should drop by **24**, face count by **12**.

*If it looks wrong:* if deleting drops far more than 24 verts you have caught
part of the body — undo and zoom in first. If you cannot find a cube, check the
outliner for a second mesh object rather than loose geometry in the same mesh.

**This step changes the imported part's `Size`** from `63 × 501 × 59` to roughly
`14 × 9.5 × 14`, because the cube is what inflates the bounding box. That is
desirable, but see *Code changes* at the bottom — two scripts currently depend on
the cube being there.

### 2. Clear what is there

Select all. `UV → Reset` is not enough — remove the existing UV map entirely in
Object Data Properties → UV Maps, then add a fresh one. Also clear all existing
seams (`Edge → Clear Seam` with everything selected).

*If it looks wrong:* if the UV editor still shows the old layout, you removed a
second UV map and left the original active. There should be exactly one when you
are done.

### 3. Mark the rim seam

Select the edge loop where the outer dome meets the underside — the silhouette
you would see looking at the slime side-on. `Alt+Click` on one edge of that loop
usually selects the whole ring.

`Edge → Mark Seam`.

*If it looks wrong:* if `Alt+Click` selects a meridian instead of the rim, you
clicked an edge running the wrong way — click one that runs *around* the body,
not up it. If the loop stops partway, the mesh has a pole or an n-gon there;
finish the selection by hand with `Ctrl+Click` along the ring.

### 4. Mark the back meridian seam

Select an edge path from the rim up to the crown, on the **back** of the body
(the `+X, +Z` side, away from the eyes). `Ctrl+Click` from the rim vertex to the
top vertex will path it.

`Edge → Mark Seam`.

*If it looks wrong:* if the path wanders diagonally instead of running straight
up, the mesh's edge flow is not meridional there — pick the straightest path you
can and do not worry, a slightly wobbly seam is harmless since it is a cut, not a
pattern feature.

### 5. Unwrap

Select all faces. `U → Unwrap`, method **Angle Based**, **Fill Holes** on.

You should get **exactly two islands**: a large roughly-rectangular one for the
dome, and a small disc for the underside.

*If it looks wrong:*
- **One island, not two** — the rim seam did not take. Go back to step 3; check
  the loop is red (marked) all the way round with no gaps.
- **More than two islands** — you have a stray seam somewhere. Clear all seams and
  redo steps 3–4.
- **The dome island is a fan or a spiral rather than a rectangle** — the meridian
  seam is missing or incomplete, so it unwrapped as a disc from the pole. Redo
  step 4.
- **Overlapping geometry inside one island** (turn on UV → Overlay → Display
  Stretch, or just look for folded-over triangles) — this is R1 failing and is
  the single thing this whole exercise exists to fix. It usually means the
  underside is still attached to the dome chart; recheck the rim seam.

### 6. Pack

`UV → Pack Islands`, **Rotate** on, **Margin 0.016**.

Both islands should now fill the 0..1 square with a thin gap between them and a
thin border at the edges.

*If it looks wrong:* if there is a large empty band, run Pack Islands again — it
is iterative and one pass often leaves slack. If the islands touch, raise the
margin; if the border is enormous, lower it. The target is ≥ 85% filled, and you
can eyeball that as "the empty space is clearly less than a fifth of the square".

### 7. Export and upload

Export as `.fbx` or `.obj`, upload to Roblox, and put the new asset id into
`workspace.slime_uv`.

Keep the old asset id. If the new unwrap turns out worse you want to be able to
put it straight back.

---

## Verification after import

Run **`dev/skins/VERIFY_UNWRAP.luau`** — paste it into the Studio command bar with
the new mesh in `workspace.slime_uv`. It checks every requirement above against
the real mesh and prints a pass/fail line for each.

What each failure means:

| the check says | it means | fix |
|---|---|---|
| `u range 0.000..1.252` (or anything > 1) | geometry mapped outside the square and wrapped back onto occupied texels | R3 — repack; the overshoot is usually an island that did not get scaled down |
| `CONTESTED: n texels` with n > 0 | **R1 failed** — two surface points share a texel. This is the smudge. | the underside is still folded into the dome chart; recheck the rim seam |
| `TEARS: n` with n > 0 | sheet-neighbours are far apart on the body; filtering will bleed across them | raise the pack margin (R6) |
| `coverage 40%` (or < 85) | wasting resolution | repack, or scale islands up before packing |
| `straddling triangles: n` with n > 0 | a triangle spans the wrap | the seam is not a real cut — re-mark it and re-unwrap |
| `stray faces above Y=0: 12` | the cube is still there | step 1 |

**What success looks like:** contested 0, tears 0, straddling 0, `u` and `v`
both inside 0..1, coverage above 85%, and the reported texel step roughly
constant from the crown to the underside rather than doubling anywhere.

**What partial success looks like, and why it is still a fail:** coverage fixed
but contested still non-zero is the *worse* of the two outcomes to accept,
because the extra resolution makes the wrong-texel patches sharper rather than
softer. Fix injectivity first; treat coverage as the bonus.

---

## Code changes needed after the re-unwrap

Two things in the repo currently depend on the mesh being the way it is. Both
will silently misbehave rather than error.

**1. The stray-cube filter.** `BUILD_SKINS.luau` and `BUILD_GALAXY.luau` both
exclude the cube with `if p.Y < 0` — every body vertex currently sits below Y=0,
so the test works by accident of where the body happens to be. Once the cube is
gone the test is unnecessary, and if the re-export re-centres the mesh it will
**exclude the entire body** and the build will produce an empty texture. Delete
the filter, do not adjust it.

**2. The mesh-units-to-studs conversion.** Both scripts compute
`studsPerMeshUnit = src.Size.X / fullMeshWidth`, where `fullMeshWidth` includes
the cube. That is correct today and stays correct after — the full bbox simply
becomes the body bbox — so this one needs no change, but check the reported body
radius is still `7.00` studs after import and not something odd.

**3. The resolution decision can be revisited.** At 85% coverage a 512 sheet
resolves like today's 824. If that holds up, 512 stays the right choice and the
1.61× is banked as quality rather than spent. The numbers to re-run are in
`BUILD_SKINS.luau`'s header.
