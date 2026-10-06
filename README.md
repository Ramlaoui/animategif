# animategif — animated GIFs in PDF documents

![A beamer slide in which \animategif plays a matplotlib animation of gradient descent](https://raw.githubusercontent.com/Ramlaoui/animategif/main/docs/hero.gif)

<sub>Every frame above is a page of a real beamer PDF, rendered by poppler
(source: [`docs/hero`](https://github.com/Ramlaoui/animategif/tree/main/docs/hero)).</sub>

```latex
\usepackage{animategif}
...
\animategif[width=6cm]{movie}   % movie.gif
```

`animategif` embeds an animated GIF as a PDF animation, straight from the
`.gif` file. It decodes the GIF itself, in pure Lua, so ImageMagick and other
external programs are not needed, and it hands the frames to the
[animate](https://ctan.org/pkg/animate) package.

- Follows the GIF: per-frame delays, disposal methods, transparency,
  interlacing, local palettes and loop count.
- Small PDFs: frames become indexed PNGs, and only the pixels that change
  between frames are stored. Identical frames cost nothing.
- Cached: each GIF is decoded once, into `animategif-cache/`.
- Options: `frames=10-40`, `step=2`, `speed=0.5`, `fps=12`, `plays=3`,
  `downsample=2`, `still=last`, plus any `animate` option (`controls`,
  `poster=last`, …).
- Beamer handouts get still images automatically.

## Engines

| Engine | Needs |
| --- | --- |
| LuaLaTeX | nothing (decodes in-process) |
| pdfLaTeX, XeLaTeX | `-shell-escape` (runs `texlua animategif.lua`) |
| any engine, cache already filled | nothing |

Ship `animategif-cache/` with your sources (e.g. to arXiv or a journal) and the
document compiles anywhere without shell escape.

## Viewers

Animations play in viewers that run animate's JavaScript: Adobe
Acrobat/Reader, KDE Okular, PDF-XChange and Foxit Reader. Other viewers show
a poster frame (the first frame by default, or set `poster=last`).

## Installation

Once the package is on CTAN, TeX Live and MiKTeX will install it. Until then,
put `animategif.sty` and `animategif.lua` next to your document, or install
them into your TEXMF tree with `l3build install`.

## Documentation

See [animategif.pdf](https://github.com/Ramlaoui/animategif/releases) or build
it with `l3build doc`. `texlua animategif.lua info movie.gif` prints a GIF's
size, frame count, duration and loop count.

## Development

- `test/verify.sh`: decodes the test GIFs with several option sets, rebuilds
  every displayed frame from the stacked images exactly as the timeline shows
  it, and compares it pixel by pixel (and its delay) with ImageMagick.
- `l3build doc`: builds the manual.
- `l3build ctan`: builds the CTAN archive.

## License

Copyright © 2026 Ali Ramlaoui. Released under the
[LaTeX Project Public License 1.3c](https://www.latex-project.org/lppl.txt)
or later. Status: maintained.
