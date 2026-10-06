#!/bin/bash
# Decodes every test GIF with several option sets, rebuilds each displayed
# frame from the stacked images exactly as the timeline shows them, and
# compares it pixel by pixel (and its delay) with ImageMagick's decoding.
# Needs ImageMagick 7 (`magick`). Usage: test/verify.sh [gif ...]
set -u
here=$(cd "$(dirname "$0")" && pwd)
lua=$here/../animategif.lua
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

optsets=("optimize=false" "optimize=true" "keyframe=3" "first=2 last=9 step=3")
gifs=("$@")
[ ${#gifs[@]} -eq 0 ] && gifs=("$here"/gifs/*.gif)

# flatten transparency to black, so fully transparent pixels compare equal
flat() { echo "( $1 -alpha on -background black -alpha background -alpha off )"; }

fail=0
for gif in "${gifs[@]}"; do
  name=$(basename "$gif" .gif)
  magick "$gif" -coalesce "$work/$name-ref-%d.png"
  delays=($(magick identify -format "%T " "$gif"))
  for opts in "${optsets[@]}"; do
    out=$work/$name-$(echo "$opts" | tr ' =' '__')
    first=0 step=1 last=-1
    for kv in $opts; do case $kv in first=*|step=*|last=*) eval "$kv";; esac; done
    n=${#delays[@]}; { [ "$last" -lt 0 ] || [ "$last" -ge "$n" ]; } && last=$((n - 1))
    # shellcheck disable=SC2086
    if ! texlua "$lua" frames "$gif" "$out" $opts > /dev/null 2>&1; then
      if [ "$first" -ge "$n" ]; then
        printf "ok   %-12s %-26s rejected: range starts after the last frame\n" "$name" "[$opts]"
      else
        echo "FAIL $name [$opts]: decoder error"; fail=1
      fi
      continue
    fi
    W=$(magick identify -format "%w" "$out/f-0.png"); H=$(magick identify -format "%h" "$out/f-0.png")
    k=0 bad=""
    while read -r delay ids; do
      ref=$((first + k * step))
      layers=""
      for id in $ids; do layers="$layers $out/f-$id.png -composite"; done
      # shellcheck disable=SC2046,SC2086
      ae=$(magick compare -metric AE $(flat "$work/$name-ref-$ref.png") \
        $(flat "( -size ${W}x${H} xc:none $layers )") null: 2>&1 | awk '{print int($1)}')
      want=0
      for ((j = ref; j < ref + step && j <= last; j++)); do
        d=${delays[$j]}; [ "$d" -le 1 ] && d=10; want=$((want + d))
      done
      [ "$ae" != 0 ] && bad="$bad frame $k: $ae px;"
      [ "$delay" != "$want" ] && bad="$bad frame $k: delay $delay != $want;"
      k=$((k + 1))
    done < <(texlua "$here/stacks.lua" "$out/info.tex")
    expected=$(( (last - first) / step + 1 ))
    [ "$k" != "$expected" ] && bad="$bad $k frames, expected $expected;"
    imgs=$(ls "$out"/f-*.png | wc -l | tr -d ' ')
    if [ -n "$bad" ]; then
      echo "FAIL $name [$opts]:$bad"; fail=1
    else
      printf "ok   %-12s %-26s %2d frames, %2d images, %s\n" "$name" "[$opts]" "$k" "$imgs" \
        "$(( $(cat "$out"/f-*.png | wc -c) / 1024 ))K"
    fi
  done
done
exit $fail
