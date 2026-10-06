#!/bin/sh
# Rebuilds docs/hero.gif, the README animation. Needs uv, LuaLaTeX and
# poppler (pdftoppm). Every frame is a page of hero.pdf as poppler
# renders it, with the delays animategif read from descent.gif.
set -eu
cd "$(dirname "$0")"
export TEXINPUTS=../..//: LUAINPUTS=../..//:
uv run --quiet --python 3.12 descent.py descent.gif
n=$(texlua ../../animategif.lua info descent.gif | sed -E 's/.* ([0-9]+) frames.*/\1/')
for run in 1 2; do # animate needs two runs
  lualatex -interaction=nonstopmode "\\def\\heroframes{$n}\\input{hero}" > /dev/null
done
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pdftoppm -r 144 -png hero.pdf "$tmp/p"
info=$(ls animategif-cache/descent-*/v1-*-d1/info.tex | head -1)
uv run --quiet --python 3.12 assemble.py ../hero.gif "$info" "$tmp"/p-*.png
[ -n "${KEEP:-}" ] || rm -rf animategif-cache hero.aux hero.log hero.nav hero.out hero.snm hero.toc hero.pdf
