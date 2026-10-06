-- animategif.lua: pure-Lua GIF decoder for animategif.sty.
-- Decodes an (animated) GIF into composited PNG frames plus an `animate`
-- timeline, using only libraries bundled with LuaTeX/texlua (zlib, md5, lfs).
-- Library: require("animategif").prepare(gif_path)
-- CLI (pdfLaTeX + -shell-escape): texlua animategif.lua <gif_path>

local M = {}

M.cachedir = "animategif-cache"

---------------------------------------------------------------- GIF parsing

local function lzw_decode(data, minsize, npix)
  local clear = 1 << minsize
  local eoi = clear + 1
  local prefix, suffix, first, len = {}, {}, {}, {}
  for i = 0, clear - 1 do suffix[i], first[i], len[i] = i, i, 1 end
  local out, op = {}, 0
  local codesize, nextcode, prev = minsize + 1, eoi + 1, nil
  local bitbuf, bitcnt, pos, n = 0, 0, 1, #data
  while op < npix do
    while bitcnt < codesize do
      if pos > n then return out, op end
      bitbuf = bitbuf | (data:byte(pos) << bitcnt)
      pos, bitcnt = pos + 1, bitcnt + 8
    end
    local code = bitbuf & ((1 << codesize) - 1)
    bitbuf, bitcnt = bitbuf >> codesize, bitcnt - codesize
    if code == clear then
      codesize, nextcode, prev = minsize + 1, eoi + 1, nil
    elseif code == eoi then
      break
    else
      if prev == nil then
        if code >= clear then return out, op end -- corrupt stream
      elseif nextcode < 4096 then
        if code < nextcode then
          suffix[nextcode] = first[code]
        elseif code == nextcode then
          suffix[nextcode] = first[prev]
        else
          return out, op -- corrupt stream
        end
        prefix[nextcode], first[nextcode], len[nextcode] = prev, first[prev], len[prev] + 1
        nextcode = nextcode + 1
        if nextcode == (1 << codesize) and codesize < 12 then codesize = codesize + 1 end
      end
      local l, k = len[code], code
      for j = op + l, op + 1, -1 do out[j] = suffix[k]; k = prefix[k] end
      op = op + l
      prev = code
    end
  end
  return out, op
end

-- Maps decoded row number -> image row for interlaced GIFs.
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
    local r, g, b = s:byte(pos + 3 * i, pos + 3 * i + 2)
    pal[i] = (r << 16) | (g << 8) | b
  end
  return pal, pos + 3 * size
end

local function read_subblocks(s, pos)
  local parts = {}
  while true do
    local size = s:byte(pos)
    if not size then error("animategif: truncated GIF") end
    pos = pos + 1
    if size == 0 then return table.concat(parts), pos end
    parts[#parts + 1] = s:sub(pos, pos + size - 1)
    pos = pos + size
  end
end

-- Calls emit(canvas, delay_cs) for every composited frame. Canvas pixels are
-- 0xRRGGBB integers, or -1 for transparent. Returns width, height, loops.
local function decode(s, emit)
  local sig = s:sub(1, 6)
  if sig ~= "GIF87a" and sig ~= "GIF89a" then error("animategif: not a GIF file") end
  local W, H, flags = string.unpack("<I2I2B", s, 7)
  local pos = 14
  local gpal
  if flags & 0x80 ~= 0 then gpal, pos = read_palette(s, pos, 1 << ((flags & 7) + 1)) end

  local canvas = {}
  for i = 1, W * H do canvas[i] = -1 end
  local loops = false
  local gce_delay, gce_disposal, gce_trans = 0, 0, nil
  local pending -- disposal of the previous frame: {method, x, y, w, h, saved}

  while true do
    local b = s:byte(pos)
    if b == nil or b == 0x3B then break end
    if b == 0x21 then
      local label = s:byte(pos + 1)
      local body
      body, pos = read_subblocks(s, pos + 2)
      if label == 0xF9 and #body >= 4 then
        local pf, delay, ti = string.unpack("<BI2B", body)
        gce_delay, gce_disposal = delay, (pf >> 2) & 7
        gce_trans = (pf & 1 ~= 0) and ti or nil
      elseif label == 0xFF and body:sub(1, 11) == "NETSCAPE2.0" then
        loops = true
      end
    elseif b == 0x2C then
      local fx, fy, fw, fh, ff = string.unpack("<I2I2I2I2B", s, pos + 1)
      pos = pos + 10
      local pal = gpal
      if ff & 0x80 ~= 0 then pal, pos = read_palette(s, pos, 1 << ((ff & 7) + 1)) end
      pal = pal or {}
      local minsize = s:byte(pos)
      local data
      data, pos = read_subblocks(s, pos + 1)

      -- apply the previous frame's disposal
      if pending then
        local m, px, py, pw, ph, saved = table.unpack(pending)
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
      if gce_disposal == 3 then
        saved = {}
        for y = fy, math.min(fy + fh, H) - 1 do
          for x = fx, math.min(fx + fw, W) - 1 do saved[#saved + 1] = canvas[y * W + x + 1] end
        end
      end

      local idx, count = lzw_decode(data, minsize, fw * fh)
      local rows = (ff & 0x40 ~= 0) and interlace_rows(fh) or nil
      for r = 0, fh - 1 do
        local y = fy + (rows and rows[r + 1] or r)
        if y < H then
          local base = r * fw
          for x = 0, math.min(fw, W - fx) - 1 do
            local i = base + x + 1
            if i > count then break end
            local ci = idx[i]
            if ci ~= gce_trans then canvas[y * W + fx + x + 1] = pal[ci] or 0 end
          end
        end
      end

      -- browsers play delays of 0-1 centiseconds at 10 cs; mirror that
      emit(canvas, gce_delay <= 1 and 10 or gce_delay, W, H)
      pending = { gce_disposal, fx, fy, fw, fh, saved }
      gce_delay, gce_disposal, gce_trans = 0, 0, nil
    else
      error(string.format("animategif: unexpected block 0x%02X at byte %d", b, pos))
    end
  end
  return W, H, loops
end

---------------------------------------------------------------- PNG output

local function png_chunk(kind, data)
  return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", zlib.crc32(0, kind .. data))
end

local function write_png(path, canvas, W, H)
  local alpha = false
  for i = 1, W * H do if canvas[i] == -1 then alpha = true; break end end
  local memo = {}
  local function px(c)
    local p = memo[c]
    if not p then
      if c == -1 then
        p = "\0\0\0\0"
      else
        p = string.char((c >> 16) & 255, (c >> 8) & 255, c & 255) .. (alpha and "\255" or "")
      end
      memo[c] = p
    end
    return p
  end
  local lines, row = {}, {}
  for y = 0, H - 1 do
    row[1] = "\0" -- filter type: none
    for x = 1, W do row[x + 1] = px(canvas[y * W + x]) end
    lines[y + 1] = table.concat(row, "", 1, W + 1)
  end
  local f = assert(io.open(path, "wb"))
  f:write("\137PNG\r\n\26\n",
    png_chunk("IHDR", string.pack(">I4I4BBBBB", W, H, 8, alpha and 6 or 2, 0, 0, 0)),
    png_chunk("IDAT", zlib.compress(table.concat(lines), 9)),
    png_chunk("IEND", ""))
  f:close()
end

---------------------------------------------------------------- cache + info

local function sanitize(path)
  return (path:gsub("%.[Gg][Ii][Ff]$", ""):gsub("[^%w%-]", "_"))
end

local function fmt_rate(cs)
  return (string.format("%.4f", 100 / cs):gsub("0+$", ""):gsub("%.$", ""))
end

local function mkdirs(path)
  local acc = ""
  for part in path:gmatch("[^/]+") do
    acc = (acc == "") and part or (acc .. "/" .. part)
    if not lfs.isdir(acc) then lfs.mkdir(acc) end
  end
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function write_file(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local function locate(path)
  if lfs.isfile(path) then return path end
  local found = kpse and kpse.find_file and kpse.find_file(path, "graphic/figure")
  if found then return found end
  error("animategif: cannot find `" .. path .. "'")
end

-- Decodes `gif` into <cachedir>/<name>/f-<n>.png (skipped when the cached
-- frames match the GIF's md5) and writes <cachedir>/last.tex for the .sty.
function M.prepare(gif)
  local s = read_file(locate(gif))
  local hash = md5.sumhexa(s)
  local dir = M.cachedir .. "/" .. sanitize(gif)
  local info_path = dir .. "/info.tex"
  local info = read_file(info_path)
  if not (info and info:find("% md5 " .. hash, 1, true)) then
    mkdirs(dir)
    for name in lfs.dir(dir) do
      if name:match("^f%-%d+%.png$") then os.remove(dir .. "/" .. name) end
    end
    local delays, n = {}, 0
    local _, _, loops = decode(s, function(canvas, delay, W, H)
      write_png(string.format("%s/f-%d.png", dir, n), canvas, W, H)
      n = n + 1
      delays[n] = delay
    end)
    if n == 0 then error("animategif: `" .. gif .. "' has no frames") end

    local uniform = true
    for i = 2, n do if delays[i] ~= delays[1] then uniform = false; break end end
    if not uniform then
      local tl, last = {}, nil
      for i = 1, n do
        tl[i] = string.format(":%s:%d", delays[i] ~= last and fmt_rate(delays[i]) or "", i - 1)
        last = delays[i]
      end
      write_file(dir .. "/timeline.tln", table.concat(tl, "\n") .. "\n")
    end
    info = table.concat({
      "% md5 " .. hash,
      "\\makeatletter",
      "\\def\\agif@src{" .. gif .. "}",
      "\\def\\agif@prefix{" .. dir .. "/f-}",
      "\\def\\agif@last{" .. (n - 1) .. "}",
      "\\def\\agif@fps{" .. fmt_rate(delays[1]) .. "}",
      "\\def\\agif@timeline{" .. (uniform and "" or (dir .. "/timeline.tln")) .. "}",
      "\\def\\agif@loop{" .. (loops and "true" or "false") .. "}",
      "",
    }, "\n")
    write_file(info_path, info)
  end
  write_file(M.cachedir .. "/last.tex", info)
end

if arg and arg[0] and arg[0]:match("animategif%.lua$") and arg[1] then
  M.prepare(arg[1])
end

return M
