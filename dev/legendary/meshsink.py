#!/usr/bin/env python3
"""Local HTTP bridge between Studio and the offline rig. Two directions.

OUT OF STUDIO (POST). Studio cannot write files, but HttpService in the plugin
context can POST to localhost, and it carries a raw byte body unaltered
(verified with a 0..255 round-trip before this was trusted). So the mesh comes
out over a socket instead of over the MCP bridge, which keeps it off the ~30 s
execute_luau cap and out of JSON entirely. DUMP_MESH.luau is the writer.
APPENDS -- delete the target file first if you want a clean dump.

INTO STUDIO (GET). The reverse trip for the baked sheets, because the same
problem runs the other way: Studio cannot read a PNG off disk, and a 1 MB
texture will not go through execute_luau. GET /rgba/<design> decodes
dev/out/bake/<design>.png here and returns the raw RGBA bytes, which is
exactly what EditableImage:WritePixelsBuffer wants -- so U2U3.luau can bind
the offline bake to a real body with no upload and no asset id.

    python dev/legendary/meshsink.py            # then paste DUMP_MESH / U2U3
"""
import http.server
import os
import struct
import sys
import zlib

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join("dev", "out")
PORT = 8731


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        data = self.rfile.read(n)
        name = self.path.strip("/").replace("/", "_") or "blob"
        path = os.path.join(OUT, "slime_mesh.bin" if name == "mesh" else name)
        with open(path, "ab") as f:
            f.write(data)
        print(f"{len(data)} bytes -> {path}", flush=True)
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def do_GET(self):
        if not self.path.startswith("/rgba/"):
            self.send_error(404)
            return
        name = os.path.basename(self.path[len("/rgba/"):])
        path = os.path.join("dev", "out", "bake", name + ".png")
        try:
            data = png_to_rgba(path)
        except Exception as exc:  # noqa: BLE001 -- the message is the answer
            self.send_error(500, str(exc))
            return
        print(f"{path} -> {len(data)} bytes of RGBA", flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


PNG_MAGIC = bytes([137, 80, 78, 71, 13, 10, 26, 10])


def png_to_rgba(path):
    """Decode the PNGs BAKE_LEGENDARY_PAINT writes: 8-bit RGBA, filter 0 on
    every scanline. Deliberately not a general PNG decoder -- it asserts the
    shape it expects rather than quietly handling something else."""
    d = open(path, "rb").read()
    assert d[:8] == PNG_MAGIC, f"{path} is not a PNG"
    i, idat, hdr = 8, b"", None
    while i < len(d):
        ln = struct.unpack(">I", d[i:i + 4])[0]
        kind, body = d[i + 4:i + 8], d[i + 8:i + 8 + ln]
        if kind == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        i += 12 + ln
    w, h, depth, colour = hdr[0], hdr[1], hdr[2], hdr[3]
    assert (depth, colour) == (8, 6), f"{path} is depth {depth} colour {colour}, wanted 8/6"
    raw = zlib.decompress(idat)
    assert len(raw) == h * (1 + w * 4), "unexpected scanline count"
    out = bytearray()
    for y in range(h):
        off = y * (1 + w * 4)
        assert raw[off] == 0, f"{path} row {y} uses filter {raw[off]}, wanted None"
        out += raw[off + 1:off + 1 + w * 4]
    return bytes(out)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print(f"sink on 127.0.0.1:{PORT} -> {OUT}", flush=True)
    http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
