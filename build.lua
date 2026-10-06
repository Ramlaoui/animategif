-- l3build configuration for animategif
module = "animategif"

sourcefiles  = {"animategif.sty", "animategif.lua"}
installfiles = {"animategif.sty", "animategif.lua"}
typesetfiles = {"animategif.tex"}
docfiles     = {"animategif-demo.gif"}
textfiles    = {"README.md"}
typesetexe   = "lualatex"
-- the documentation decodes its demo GIF; keep the cache out of the archive
typesetruns  = 2

uploadconfig = {
  pkg          = "animategif",
  version      = "1.0.0 2026-10-06",
  author       = "Ali Ramlaoui",
  license      = "lppl1.3c",
  summary      = "Embed animated GIF files in PDF documents, decoded in pure Lua",
  topic        = {"graphics-motion", "graphics-incl", "luatex"},
  ctanPath     = "/macros/latex/contrib/animategif",
  repository   = "https://github.com/Ramlaoui/animategif",
  bugtracker   = "https://github.com/Ramlaoui/animategif/issues",
  update       = false,
  description  = [[
The package provides \animategif{file.gif}, which embeds an animated GIF as a
PDF animation. The GIF is decoded in pure Lua — in-process with LuaLaTeX, or
with texlua through shell escape with pdfLaTeX and XeLaTeX — so no external
programs such as ImageMagick are needed. Frames are written as compact PNG
images, storing only the pixels that change between frames, and cached. The
animate package then embeds them with a timeline that follows the GIF's
per-frame delays, disposal methods, transparency and loop count. Options
select frame ranges, change the speed or number of plays, downsample, or
include a single frame as a still image (automatically in beamer handouts).
]],
}
