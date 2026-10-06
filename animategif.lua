-- animategif.lua -- GIF decoder and frame writer for animategif.sty
--
-- Copyright (C) 2026 Ali Ramlaoui
--
-- This work may be distributed and/or modified under the conditions of the
-- LaTeX Project Public License, either version 1.3c of this license or (at
-- your option) any later version. The latest version of this license is in
-- https://www.latex-project.org/lppl.txt
--
-- This work has the LPPL maintenance status `maintained'.
-- The Current Maintainer of this work is Ali Ramlaoui.
--
-- Pure Lua 5.3: needs only the zlib and lfs libraries that ship with LuaTeX
-- and texlua. Used in-process by LuaLaTeX, and as a command-line tool
-- (through \write18) by pdfLaTeX and XeLaTeX:
--
--   texlua animategif.lua frames <gif> <dir> [key=value ...]
--   texlua animategif.lua still  <gif> <dir> [key=value ...]
--   texlua animategif.lua info   <gif>

local M = {
  version = "1.0.0",
  date = "2026-10-06",
}

local byte, char, unpack, concat = string.byte, string.char, table.unpack, table.concat
local spack, sunpack = string.pack, string.unpack

local profile = os.getenv("ANIMATEGIF_PROFILE") and {} or nil
local clock = os.clock
local function tick(phase, t0)
  if profile then profile[phase] = (profile[phase] or 0) + clock() - t0 end
end

------------------------------------------------------------------- decoding

-- Decodes LZW `data` into out[1..n] (palette indices); returns n.
local function lzw_decode(data, minsize, npix, out)
  local clear = 1 << minsize
  local eoi = clear + 1
  local prefix, suffix, first, len = {}, {}, {}, {}
  for i = 0, clear - 1 do suffix[i], first[i], len[i] = i, i, 1 end
  local op = 0
  local codesize, nextcode, prev = minsize + 1, eoi + 1, nil
  local codemask = (1 << codesize) - 1
  local bitbuf, bitcnt, pos, n = 0, 0, 1, #data
  while op < npix do
    while bitcnt < codesize do
      if pos > n then return op end
      bitbuf = bitbuf | (byte(data, pos) << bitcnt)
      pos, bitcnt = pos + 1, bitcnt + 8
    end
    local code = bitbuf & codemask
    bitbuf, bitcnt = bitbuf >> codesize, bitcnt - codesize
    if code == clear then
      codesize, nextcode, prev = minsize + 1, eoi + 1, nil
      codemask = (1 << codesize) - 1
    elseif code == eoi then
      break
    else
      if prev == nil then
        if code >= clear then return op end -- corrupt stream
      elseif nextcode < 4096 then
        if code < nextcode then
          suffix[nextcode] = first[code]
        elseif code == nextcode then
          suffix[nextcode] = first[prev]
        else
          return op -- corrupt stream
        end
        prefix[nextcode], first[nextcode], len[nextcode] = prev, first[prev], len[prev] + 1
        nextcode = nextcode + 1
        if nextcode > codemask and codesize < 12 then
          codesize = codesize + 1
          codemask = (1 << codesize) - 1
        end
      end
      local l, k = len[code], code
      if l == 1 then
        out[op + 1] = code
      else
        for j = op + l, op + 1, -1 do out[j] = suffix[k]; k = prefix[k] end
      end
      op = op + l
      prev = code
    end
  end
  return op
end

-- Decoded row number -> image row, for interlaced images.
local function interlace_rows(h)
  local rows = {}
  for _, p in ipairs({ { 0, 8 }, { 4, 8 }, { 2, 4 }, { 1, 2 } }) do
    for y = p[1], h - 1, p[2] do rows[#rows + 1] = y end
  end
  return rows
end

local function read_palette(s, pos, size)
  local pal = {}
  for i = 0, size - 1 do
    local r, g, b = byte(s, pos + 3 * i, pos + 3 * i + 2)
    pal[i] = (r << 16) | (g << 8) | b
  end
  return pal, pos + 3 * size
end

local function read_subblocks(s, pos)
  local parts = {}
  while true do
    local size = byte(s, pos)
    if not size then error("truncated GIF data", 0) end
    pos = pos + 1
    if size == 0 then return concat(parts), pos end
    parts[#parts + 1] = s:sub(pos, pos + size - 1)
    pos = pos + size
  end
end

local function header(s)
  local sig = s:sub(1, 6)
  if sig ~= "GIF87a" and sig ~= "GIF89a" then error("not a GIF file", 0) end
  return sunpack("<I2I2B", s, 7)
end

-- Composites the frames of GIF string `s` the way browsers do. For each frame
-- calls emit(i, canvas, delay) with i counting from 0, canvas[1..W*H] holding
-- 0xRRGGBB or -1 (transparent) and delay in centiseconds; emit returns true
-- to stop early. Returns W, H, loopcount (nil when the GIF plays once).
function M.decode(s, emit)
  local W, H, flags = header(s)
  local pos = 14
  local gpal
  if flags & 0x80 ~= 0 then gpal, pos = read_palette(s, pos, 1 << ((flags & 7) + 1)) end

  local canvas = {}
  for i = 1, W * H do canvas[i] = -1 end
  local idx = {}
  local loopcount
  local delay, disposal, trans = 0, 0, nil
  local pending -- previous frame: {disposal, x, y, w, h, saved}
  local frame = 0

  while true do
    local b = byte(s, pos)
    if b == nil or b == 0x3B then break end
    if b == 0x21 then
      local label = byte(s, pos + 1)
      local body
      body, pos = read_subblocks(s, pos + 2)
      if label == 0xF9 and #body >= 4 then
        local pf, d, ti = sunpack("<BI2B", body)
        delay, disposal = d, (pf >> 2) & 7
        trans = (pf & 1 ~= 0) and ti or nil
      elseif label == 0xFF and body:sub(1, 11) == "NETSCAPE2.0" and #body >= 14 then
        loopcount = sunpack("<I2", body, 13)
      end
    elseif b == 0x2C then
      local t0 = clock()
      local fx, fy, fw, fh, ff = sunpack("<I2I2I2I2B", s, pos + 1)
      pos = pos + 10
      local pal = gpal
      if ff & 0x80 ~= 0 then pal, pos = read_palette(s, pos, 1 << ((ff & 7) + 1)) end
      pal = pal or {}
      local minsize = byte(s, pos)
      local data
      data, pos = read_subblocks(s, pos + 1)
      local x1, y1 = math.min(fx + fw, W) - 1, math.min(fy + fh, H) - 1

      if pending then -- dispose of the previous frame
        local m, px, py, pw, ph, saved = unpack(pending)
        if m == 2 or m == 3 then
          local k = 0
          for y = py, math.min(py + ph, H) - 1 do
            for x = px, math.min(px + pw, W) - 1 do
              k = k + 1
              canvas[y * W + x + 1] = (m == 3) and saved[k] or -1
            end
          end
        end
      end

      local saved
      if disposal == 3 then
        saved = {}
        for y = fy, y1 do
          for x = fx, x1 do saved[#saved + 1] = canvas[y * W + x + 1] end
        end
      end

      local t1 = clock()
      local count = lzw_decode(data, minsize, fw * fh, idx)
      tick("lzw", t1)
      local rows = (ff & 0x40 ~= 0) and interlace_rows(fh) or nil
      local cols = x1 - fx
      for r = 0, fh - 1 do
        local y = fy + (rows and rows[r + 1] or r)
        if y <= y1 then
          local src, dst = r * fw, y * W + fx + 1
          local stop = math.min(cols, count - src - 1)
          if trans then
            for x = 0, stop do
              local ci = idx[src + x + 1]
              if ci ~= trans then canvas[dst + x] = pal[ci] or 0 end
            end
          else
            for x = 0, stop do canvas[dst + x] = pal[idx[src + x + 1]] or 0 end
          end
        end
      end
      tick("composite", t0)

      -- browsers play delays of 0 and 1 centiseconds at 10 centiseconds
      if emit(frame, canvas, delay <= 1 and 10 or delay) then return W, H, loopcount end
      frame = frame + 1
      pending = { disposal, fx, fy, fw, fh, saved }
      delay, disposal, trans = 0, 0, nil
    else
      error(string.format("unexpected block 0x%02X at byte %d", b, pos), 0)
    end
  end
  return W, H, loopcount
end

------------------------------------------------------------------ resampling

-- Box-filter downsampling by an integer factor. A target pixel is transparent
-- when most of its source pixels are.
local function downsample(canvas, W, H, f, out)
  local w, h = W // f, H // f
  local half = (f * f) / 2
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, n = 0, 0, 0, 0
      for yy = y * f, y * f + f - 1 do
        local base = yy * W + x * f
        for i = base + 1, base + f do
          local c = canvas[i]
          if c >= 0 then
            r, g, b, n = r + (c >> 16), g + ((c >> 8) & 255), b + (c & 255), n + 1
          end
        end
      end
      if n < half then
        out[y * w + x + 1] = -1
      else
        out[y * w + x + 1] = ((r // n) << 16) | ((g // n) << 8) | (b // n)
      end
    end
  end
  return out, w, h
end

------------------------------------------------------------------ PNG output

local function png_chunk(kind, data)
  return spack(">I4", #data) .. kind .. data .. spack(">I4", zlib.crc32(0, kind .. data))
end

-- RGB of a pixel value: 0xRRGGBB is opaque, -1 transparent, and -2 - 0xRRGGBB
-- transparent but carrying that colour (see `bleed`).
local function rgb(c)
  if c < -1 then c = -2 - c elseif c < 0 then c = 0 end
  return char((c >> 16) & 255, (c >> 8) & 255, c & 255)
end

-- Encodes pixels[1..w*h] as a PNG: palette when the image has at most 256
-- distinct values, RGB(A) otherwise.
local function encode_png(pixels, w, h)
  local t0 = clock()
  local map, colors, ncol, ntrans = {}, {}, 0, 0
  for i = 1, w * h do
    local c = pixels[i]
    if not map[c] then
      ncol = ncol + 1
      if ncol > 256 then break end
      map[c] = true
      colors[ncol] = c
      if c < 0 then ntrans = ntrans + 1 end
    end
  end

  local rows, row = {}, {}
  local ihdr, extra
  if ncol <= 256 then
    table.sort(colors) -- transparent (negative) entries first keeps tRNS short
    for i = 1, ncol do map[colors[i]] = i - 1 end
    for y = 0, h - 1 do
      local base = y * w
      for x = 1, w do row[x] = map[pixels[base + x]] end
      rows[y + 1] = "\0" .. char(unpack(row, 1, w))
    end
    local pal = {}
    for i = 1, ncol do pal[i] = rgb(colors[i]) end
    ihdr = spack(">I4I4BBBBB", w, h, 8, 3, 0, 0, 0)
    extra = png_chunk("PLTE", concat(pal))
      .. (ntrans > 0 and png_chunk("tRNS", string.rep("\0", ntrans)) or "")
  else
    local alpha = false
    for i = 1, w * h do if pixels[i] < 0 then alpha = true; break end end
    local memo = {}
    for y = 0, h - 1 do
      local base = y * w
      row[1] = "\0"
      for x = 1, w do
        local c = pixels[base + x]
        local p = memo[c]
        if not p then
          p = rgb(c) .. (not alpha and "" or c < 0 and "\0" or "\255")
          memo[c] = p
        end
        row[x + 1] = p
      end
      rows[y + 1] = concat(row, "", 1, w + 1)
    end
    ihdr = spack(">I4I4BBBBB", w, h, 8, alpha and 6 or 2, 0, 0, 0)
    extra = ""
  end
  tick("png", t0)

  local t1 = clock()
  local idat = zlib.compress(concat(rows), 6)
  tick("zlib", t1)
  return concat { "\137PNG\r\n\26\n", png_chunk("IHDR", ihdr), extra, png_chunk("IDAT", idat),
    png_chunk("IEND", "") }
end

--------------------------------------------------------------------- helpers

-- Finds `path` as given or, like TeX does, through kpathsea (TEXINPUTS).
local function locate(path)
  if lfs.isfile(path) or not kpse then return path end
  local ok, found = pcall(kpse.find_file, path, "graphic/figure", true)
  if not ok then -- plain texlua: kpathsea is not initialised yet
    kpse.set_program_name("luatex")
    found = kpse.find_file(path, "graphic/figure", true)
  end
  return found or path
end

local function read_file(path)
  path = locate(path)
  local f, err = io.open(path, "rb")
  if not f then error(err, 0) end
  local s = f:read("a")
  f:close()
  return s
end

local function write_file(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local function mkdirs(path)
  local acc = path:sub(1, 1) == "/" and "/" or ""
  for part in path:gmatch("[^/]+") do
    acc = acc .. part
    if not lfs.isdir(acc) then lfs.mkdir(acc) end
    acc = acc .. "/"
  end
end

local function clear_dir(dir)
  for name in lfs.dir(dir) do
    if name:match("%.png$") or name == "info.tex" then os.remove(dir .. "/" .. name) end
  end
end

local function options(opts)
  opts = opts or {}
  return {
    optimize = opts.optimize ~= false and opts.optimize ~= "false",
    keyframe = math.max(1, tonumber(opts.keyframe) or 30),
    first = math.max(0, tonumber(opts.first) or 0),
    last = tonumber(opts.last) or -1, -- negative: until the end
    step = math.max(1, tonumber(opts.step) or 1),
    downsample = math.max(1, tonumber(opts.downsample) or 1),
    frame = tonumber(opts.frame) or 0,
  }
end

------------------------------------------------------------------- frames

local BLEED = 2

-- Gives the transparent pixels of a delta frame that lie within BLEED pixels
-- of a changed (opaque) pixel the colour showing through them, encoded as
-- -2 - colour. Viewers that smooth a downscaled image blend each opaque
-- pixel with its transparent neighbours; with the default black they would
-- draw dark seams around every changed region. The changed pixels lie in
-- columns x0..x1 and rows y0..y1 (0-based).
local function bleed(cur, under, w, h, x0, x1, y0, y1)
  local r = BLEED
  x0, x1 = math.max(0, x0 - r), math.min(w - 1, x1 + r)
  y0, y1 = math.max(0, y0 - r), math.min(h - 1, y1 + r)
  local near = {} -- an opaque pixel lies within r columns
  for y = y0, y1 do
    local base, last = y * w + 1, -r - 1
    for x = x0, x1 do
      if cur[base + x] >= 0 then last = x end
      if x - last <= r then near[base + x] = true end
    end
    last = w + r
    for x = x1, x0, -1 do
      if cur[base + x] >= 0 then last = x end
      if last - x <= r then near[base + x] = true end
    end
  end
  for x = x0, x1 do
    local last = -r - 1
    for y = y0, y1 do
      local p = y * w + 1 + x
      if near[p] then last = y end
      if y - last <= r and cur[p] == -1 then cur[p] = -2 - under[p] end
    end
    last = h + r
    for y = y1, y0, -1 do
      local p = y * w + 1 + x
      if near[p] then last = y end
      if last - y <= r and cur[p] == -1 then cur[p] = -2 - under[p] end
    end
  end
end

-- Writes the animation frames of `gif` to `dir` and an info.tex describing
-- them. Frames are full keyframes, or (with optimize) deltas holding only the
-- pixels that changed since the previous frame, stacked by an `animate`
-- timeline. info.tex is written last, so its presence marks a complete cache.
function M.frames(gif, dir, opts)
  local o = options(opts)
  local s = read_file(gif)
  local W, H = header(s)
  mkdirs(dir)
  clear_dir(dir)

  local prev, cur, small = {}, {}, {}
  local entries = {} -- {delay, timeline transparencies}
  local nimg, since_key, keysize = 0, 0, 0
  local kept -- entry of the last kept frame, which absorbs skipped delays
  local _, _, loopcount = M.decode(s, function(i, canvas, delay)
    if o.last >= 0 and i > o.last then return true end
    if i < o.first then return false end
    if (i - o.first) % o.step ~= 0 then
      kept[1] = kept[1] + delay
      return false
    end
    local t0 = clock()
    local px, w, h = canvas, W, H
    if o.downsample > 1 then px, w, h = downsample(canvas, W, H, o.downsample, small) end
    local n = w * h

    local key, changed = not o.optimize or #entries == 0 or since_key + 1 >= o.keyframe, 0
    if not key then
      local x0, x1, y0, y1 = w, -1, h, -1
      for y = 0, h - 1 do
        local base = y * w
        for x = 0, w - 1 do
          local p = base + x + 1
          local c = px[p]
          if c ~= prev[p] then
            if c == -1 then key = true; break end -- deltas cannot erase pixels
            changed = changed + 1
            cur[p] = c
            if x < x0 then x0 = x end
            if x > x1 then x1 = x end
            if y < y0 then y0 = y end
            y1 = y
          else
            cur[p] = -1
          end
        end
        if key then break end
      end
      if changed * 4 > n * 3 then key = true end -- a delta would save little
      if not key and changed > 0 then bleed(cur, prev, w, h, x0, x1, y0, y1) end
    end
    tick("delta", t0)

    local spec, png
    if not key and changed > 0 then
      png = encode_png(cur, w, h)
      -- a delta that is not clearly smaller than a keyframe only adds layers
      if #png * 5 > keysize * 4 then key = true end
    end
    if key then
      png = encode_png(px, w, h)
      keysize = #png
      spec = o.optimize and string.format("c,%dx0", nimg) or tostring(nimg)
      since_key = 0
    elseif changed == 0 then
      spec, since_key = "", since_key + 1
    else
      spec = string.format("%dx0", nimg)
      since_key = since_key + 1
    end
    if png then
      write_file(string.format("%s/f-%d.png", dir, nimg), png)
      nimg = nimg + 1
    end
    table.move(px, 1, n, 1, prev)
    kept = { delay, spec }
    entries[#entries + 1] = kept
    return false
  end)

  if #entries == 0 then error("no frames in the selected range", 0) end
  local w, h = W // o.downsample, H // o.downsample
  local seq = {}
  for i, e in ipairs(entries) do seq[i] = string.format("{%d}{%s}", e[1], e[2]) end
  write_file(dir .. "/info.tex", string.format(
    "\\__animategif_info:nnnnn {%d} {%d} {%d} {%d}\n  {%s}\n",
    w, h, loopcount or -1, nimg, concat(seq, "\n   ")))
  return { width = w, height = h, loopcount = loopcount, images = nimg, frames = #entries }
end

-- Writes the fully composited frame o.frame (0-based; negative counts from
-- the end, -1 being the last frame) of `gif` to <dir>/still-<frame>.png.
function M.still(gif, dir, opts)
  local o = options(opts)
  local want = o.frame
  local s = read_file(gif)
  local W, H = header(s)
  mkdirs(dir)
  local ring, total, snap = {}, 0, nil
  M.decode(s, function(i, canvas)
    total = i + 1
    if want >= 0 then
      if i == want then snap = table.move(canvas, 1, W * H, 1, {}); return true end
    else -- keep the last -want frames
      ring[i % -want] = table.move(canvas, 1, W * H, 1, ring[i % -want] or {})
    end
  end)
  if want < 0 and total + want >= 0 then snap = ring[(total + want) % -want] end
  if not snap then error(string.format("frame %d requested, GIF has %d", want, total), 0) end
  local px, w, h = snap, W, H
  if o.downsample > 1 then px, w, h = downsample(snap, W, H, o.downsample, {}) end
  local path = string.format("%s/still-%d.png", dir, want)
  write_file(path, encode_png(px, w, h))
  return path
end

-- Size, frame count, duration and loop count, without writing anything.
function M.info(gif)
  local n, total = 0, 0
  local W, H, loopcount = M.decode(read_file(gif), function(_, _, delay)
    n, total = n + 1, total + delay
  end)
  return { width = W, height = H, frames = n, duration = total / 100, loopcount = loopcount }
end

----------------------------------------------------------------------- CLI

local function parse_options(list)
  local opts = {}
  for _, kv in ipairs(list) do
    local k, v = kv:match("^(%w+)=(.*)$")
    if k then opts[k] = v end
  end
  return opts
end

-- Entry point for animategif.sty under LuaTeX: `cmd` is frames or still,
-- `args` the space-separated key=value options. Errors become log messages;
-- the package then reports the missing cache file.
function M.tex_run(cmd, gif, dir, args)
  local list = {}
  for kv in args:gmatch("%S+") do list[#list + 1] = kv end
  local ok, err = pcall(cmd == "still" and M.still or M.frames, gif, dir, parse_options(list))
  if not ok then texio.write_nl("term and log", "animategif: " .. tostring(err)) end
end

local function cli(argv)
  local cmd, gif, dir = argv[1], argv[2], argv[3]
  local opts = parse_options(table.move(argv, 4, #argv, 1, {}))
  local t0 = clock()
  local ok, err = pcall(function()
    if cmd == "frames" and gif and dir then
      local r = M.frames(gif, dir, opts)
      print(string.format("animategif: %s: %d frames, %d images, %dx%d", gif, r.frames,
        r.images, r.width, r.height))
    elseif cmd == "still" and gif and dir then
      print("animategif: wrote " .. M.still(gif, dir, opts))
    elseif cmd == "info" and gif then
      local r = M.info(gif)
      print(string.format("%s: %dx%d, %d frames, %.2fs, %s", gif, r.width, r.height, r.frames,
        r.duration, r.loopcount == nil and "plays once"
          or r.loopcount == 0 and "loops forever" or ("plays " .. r.loopcount + 1 .. " times")))
    else
      io.stderr:write("usage: texlua animategif.lua frames|still <gif> <dir> [key=value ...]\n"
        .. "       texlua animategif.lua info <gif>\n")
      os.exit(2)
    end
  end)
  if not ok then
    io.stderr:write("animategif: " .. tostring(err) .. "\n")
    os.exit(1)
  end
  if profile then
    local parts = {}
    for k, v in pairs(profile) do parts[#parts + 1] = string.format("%s %.2fs", k, v) end
    table.sort(parts)
    io.stderr:write(string.format("animategif profile: total %.2fs; %s\n", clock() - t0,
      concat(parts, ", ")))
  end
end

if arg and arg[0] and arg[0]:match("animategif%.lua$") then cli(arg) end

return M
