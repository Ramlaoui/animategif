# /// script
# dependencies = ["pillow"]
# ///
"""Assembles PNG pages into a GIF: assemble.py out.gif info.tex page.png...

Delays come from animategif's info.tex. All frames share one median-cut
palette, without dithering, so colours stay faithful and deltas small."""
import re
import sys

from PIL import Image

out, info, pages = sys.argv[1], sys.argv[2], sys.argv[3:]
delays = [int(d) * 10 for d in re.findall(r"\{(\d+)\}\{[^}]*\}", open(info).read())]
assert len(delays) == len(pages), (len(delays), len(pages))
frames = [Image.open(p).convert("RGB") for p in pages]
w, h = frames[0].size
# quantize all frames as one image: one shared palette, mapped exactly
stack = Image.new("RGB", (w, h * len(frames)))
for k, f in enumerate(frames):
    stack.paste(f, (0, k * h))
stack = stack.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
frames = [stack.crop((0, k * h, w, (k + 1) * h)) for k in range(len(frames))]
frames[0].save(out, save_all=True, append_images=frames[1:], duration=delays, loop=0, optimize=True)
