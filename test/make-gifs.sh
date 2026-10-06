#!/bin/sh
# Regenerates the test GIFs in test/gifs. Needs ImageMagick 7 (`magick`).
# The GIFs are committed, so this is only needed to change the test corpus.
set -eu
cd "$(dirname "$0")/gifs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# moving circle over a gradient
for i in $(seq 0 15); do
  magick -size 160x120 gradient:navy-orange -fill "hsl($((i * 22)),80%,50%)" \
    -draw "circle $((20 + i * 8)),60 $((20 + i * 8)),40" \
    -fill white -draw "rectangle 0,0 $((i * 10)),8" "$tmp/b$(printf %02d "$i").png"
done
magick -delay 8 -loop 0 "$tmp"/b*.png plain.gif
magick -delay 8 -loop 0 "$tmp"/b*.png -layers Optimize optimized.gif
magick "$tmp"/b*.png -set delay '%[fx:t%3==0?30:5]' -loop 0 varying.gif
magick -delay 8 -loop 0 "$tmp"/b*.png -interlace GIF interlaced.gif
magick -delay 8 -loop 3 "$tmp"/b*.png localpal.gif
magick -delay 10 -loop 0 "$tmp/b00.png" "$tmp/b05.png" noloop.gif
texlua ../strip-loop.lua noloop.gif   # ImageMagick always writes a loop block

# transparency with "restore to background" and "restore to previous"
for i in $(seq 0 9); do
  magick -size 100x100 xc:none -fill red \
    -draw "circle $((15 + i * 7)),50 $((15 + i * 7)),35" "$tmp/s$i.png"
done
magick -dispose Background -delay 10 -loop 0 "$tmp"/s*.png transparent.gif
magick -dispose Previous -delay 10 -loop 0 -size 100x100 xc:skyblue "$tmp"/s*.png \
  -layers Optimize disposeprev.gif

# random noise: fills the 4096-entry LZW table (deferred clear codes)
for i in 0 1 2; do
  magick -size 300x200 xc: +noise Random -seed "$i" -colors 256 "$tmp/n$i.png"
done
magick -delay 20 -loop 0 "$tmp"/n*.png noise.gif

# two colours: minimum LZW code size 2
for i in 0 1 2 3; do
  magick -size 64x64 xc:black -fill white -draw "rectangle $((i * 16)),0 $((i * 16 + 15)),63" \
    -colors 2 "$tmp/m$i.png"
done
magick -delay 25 -loop 0 "$tmp"/m*.png twocolor.gif

# frames placed partly outside the logical screen (must be clipped)
magick -dispose None -delay 20 -loop 0 \
  \( -size 80x80 xc:white -set page 80x80+0+0 \) \
  \( -size 40x40 xc:red -set page 80x80+60+60 \) \
  \( -size 40x40 xc:blue -set page 80x80+50+0 \) offscreen.gif
