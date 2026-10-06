-- Removes the NETSCAPE2.0 (loop) extension from a GIF, in place.
local f = assert(io.open(arg[1], "rb"))
local s = f:read("a")
f:close()
local i = s:find("\33\255\11NETSCAPE2.0", 1, true)
if i then
  f = assert(io.open(arg[1], "wb"))
  f:write(s:sub(1, i - 1), s:sub(i + 19))
  f:close()
end
