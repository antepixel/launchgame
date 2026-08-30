#!/usr/bin/env python3
"""Calibrate the round-trip instrument that U2_RUNTIME.luau carries.

    python dev/legendary/encode_probe.py            # from the repo root

Two jobs, and the second is the one that matters.

REFERENCE. Decodes dev/out/bake/tiger.png and computes, from its PIXELS, the
same in-map / mark / edge counts BUILD_LEGENDARY_PAINT computes from its
analytic mark function. These are the constants U2_RUNTIME.luau asserts against
at runtime -- if this file and that one ever disagree, the probe says so out
loud instead of silently measuring against a stale number.

  Why the pixel-derived counts CAN reproduce the analytic ones: the bake writes
  `p = primary + (mark - primary) * a`, so `a > 0.5` is exactly "p is past the
  midpoint of the primary->mark segment", which inverts from the pixel with no
  reference to the mark function. The check that this is true and not merely
  plausible is that 2A/P comes back at 19.6 px through the log's own framing
  constants -- asserted below, not assumed.

SENSITIVITY, AND THIS IS THE POINT. Before believing a number that says "the
sheet survived", ask what would have to happen to the sheet for it to say
otherwise. So the reference is put through JPEG at four qualities and two
downsample round-trips, and every candidate metric is scored on all of them.

The result is that 2A/P -- the project's own feature-size number, the 19.6 px
against the 8 px floor -- BARELY MOVES. It rises about 2% under JPEG q50 and
about 5% under a 4x downsample that visibly destroys the sheet. It cannot fail
this test. It is a floor check, not a damage detector, and U2_RUNTIME.luau
prints it labelled that way. What DOES move, monotonically and by a lot, is the
per-texel error and the count of texels whose class flips across a = 0.5.

This is dev/README.md's standing trap caught in advance rather than afterwards:
a metric that cannot notice its own irrelevance needs a guard, not a comment.
"""
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshsink import png_to_rgba  # noqa: E402 -- the bake's own decoder, not a second one

W = 512
BAKE = os.path.join("dev", "out", "bake", "tiger.png")

# BUILD_LEGENDARY_PAINT.luau's tiger entry, verbatim.
PRI = (250, 150, 45)   # tangerine
MRK = (46, 26, 92)     # deep indigo
D = tuple(MRK[i] - PRI[i] for i in range(3))
HALF = 0.5 * sum(x * x for x in D)

# A texel is off the UV map iff the bake wrote it black. 16 is a threshold in a
# gap that is not close on either side: the darkest painted colour is the mark
# at max-channel 92, and off-map is exactly 0. It is a threshold rather than
# `!= 0` because a lossy encode bleeds the silhouette, and the SAME rule has to
# apply to both images or the comparison is between two different questions.
INMAP_LEVEL = 16

# dev/out/bake_legendary_paint.log's own framing numbers, for the conversion.
FEAT_BASE_PX = 19.6
FEAT_REVEAL_PX = 21.1
FLOOR_PX = 8.0
PX_BASE, BASE_WIDTH_STUDS = 25.13, 7.0
PX_REVEAL, REVEAL_WIDTH_STUDS = 11.82, 16.0


def classify(rgba):
    """in-map and mark bitmaps, by the rule above."""
    inmap = bytearray(W * W)
    mark = bytearray(W * W)
    for i in range(W * W):
        o = i * 4
        r, g, b = rgba[o], rgba[o + 1], rgba[o + 2]
        if max(r, g, b) > INMAP_LEVEL:
            inmap[i] = 1
            if (r - PRI[0]) * D[0] + (g - PRI[1]) * D[1] + (b - PRI[2]) * D[2] > HALF:
                mark[i] = 1
    return inmap, mark


def counts(inmap, mark):
    """markN and edgeN exactly as BUILD_LEGENDARY_PAINT's paint loop counts
    them: a transition is scored only when the CURRENT texel is on the map, and
    an off-map texel reads as not-mark, so entering the silhouette already in
    the mark colour scores an edge. Reproduced, not improved -- the number has
    to be the same number."""
    markN = edgeN = 0
    for py in range(W):
        row = [False] * W
        for px in range(W):
            i = py * W + px
            if inmap[i]:
                m = bool(mark[i])
                if m:
                    markN += 1
                row[px] = m
                if px > 0 and row[px - 1] != row[px]:
                    edgeN += 1
    return markN, edgeN


def compare(base, base_in, base_mk, other):
    """Everything that is measured across the bake's own in-map texels."""
    oth_in, oth_mk = classify(other)
    n = tot = mx = over8 = over32 = flips = mapflips = 0
    for i in range(W * W):
        if oth_in[i] != base_in[i]:
            mapflips += 1
        if not base_in[i]:
            continue
        n += 1
        if oth_mk[i] != base_mk[i]:
            flips += 1
        o = i * 4
        e = max(abs(other[o + c] - base[o + c]) for c in range(3))
        tot += e
        mx = max(mx, e)
        over8 += e > 8
        over32 += e > 32
    markN, edgeN = counts(oth_in, oth_mk)
    return {
        "markN": markN, "edgeN": edgeN,
        "ratio": (2 * markN / edgeN) if edgeN else 0.0,
        "classflips": flips, "classflip_pct": 100.0 * flips / n,
        "mapflips": mapflips,
        "mean_err": tot / n, "max_err": mx,
        "over8_pct": 100.0 * over8 / n, "over32_pct": 100.0 * over32 / n,
    }


def main():
    base = png_to_rgba(BAKE)
    assert len(base) == W * W * 4, "%s is %d bytes, wanted %d" % (BAKE, len(base), W * W * 4)
    base_in, base_mk = classify(base)
    markN, edgeN = counts(base_in, base_mk)
    inmap = sum(base_in)
    ratio = 2 * markN / edgeN

    print("==== the reference, from dev/out/bake/tiger.png's own pixels ====")
    print("  byte sum      %d" % sum(base))
    print("  in-map texels %d   (post-dilation; the log's 256966 is the" % inmap)
    print("                          UV coverage BEFORE dilate(POS, MASK, W, 3))")
    print("  markN         %d" % markN)
    print("  edgeN         %d" % edgeN)
    print("  2A/P          %.4f texels" % ratio)

    # The check that the pixel-derived count IS the analytic one: one texelStep
    # has to satisfy both framings' published pixel figures at once.
    step_base = FEAT_BASE_PX / (ratio * (BASE_WIDTH_STUDS / 2) * PX_BASE)
    step_reveal = FEAT_REVEAL_PX / (ratio * (REVEAL_WIDTH_STUDS / 2) * PX_REVEAL)
    skew = abs(step_base - step_reveal) / step_base
    print("  implied texelStep %.6f (from %.1f px base) / %.6f (from %.1f px reveal), %.2f%% apart"
          % (step_base, FEAT_BASE_PX, step_reveal, FEAT_REVEAL_PX, skew * 100))
    assert skew < 0.01, (
        "the two framings imply different texel steps -- the pixel-derived 2A/P is NOT "
        "the paint rig's 2A/P and nothing below can be trusted")
    print("  -> the pixel-derived 2A/P reproduces the paint rig's, through both framings")

    print()
    print("==== sensitivity: what would have to happen for the metric to fail ====")
    from PIL import Image
    img = Image.frombytes("RGBA", (W, W), bytes(base))
    cases = [("bake (identity)", base)]
    for q in (95, 85, 70, 50):
        b = io.BytesIO()
        img.convert("RGB").save(b, "JPEG", quality=q)
        cases.append(("jpeg q%d" % q,
                      Image.open(io.BytesIO(b.getvalue())).convert("RGBA").tobytes()))
    for n in (256, 128):
        cases.append(("resize %d->512" % n,
                      img.resize((n, n), Image.LANCZOS).resize((W, W), Image.LANCZOS).tobytes()))

    print("  %-16s %9s %11s %10s %8s %7s %7s"
          % ("case", "featBase", "2A/P drift", "classflip", "meanErr", "maxErr", ">8/ch"))
    for tag, rgba in cases:
        m = compare(base, base_in, base_mk, rgba)
        feat = FEAT_BASE_PX * m["ratio"] / ratio
        print("  %-16s %8.2fpx %+10.2f%% %9.2f%% %8.2f %7d %6.1f%%"
              % (tag, feat, (m["ratio"] / ratio - 1) * 100, m["classflip_pct"],
                 m["mean_err"], m["max_err"], m["over8_pct"]))

    print()
    print("  READ THE FIRST COLUMN AND THEN STOP TRUSTING IT. featBase stays within a")
    print("  few percent of %.1f px through every case, including a 4x downsample, and" % FEAT_BASE_PX)
    print("  never comes near the %.0f px floor. It is a floor check that cannot fail," % FLOOR_PX)
    print("  so it is not evidence the sheet survived. classflip and meanErr are the")
    print("  columns that move, and they are what says whether anything happened.")


if __name__ == "__main__":
    main()
