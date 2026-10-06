-- Replays the frame list of an animategif info.tex like animate's timeline
-- does, printing for each frame: <delay> <image ids on the stack, bottom up>.
local f = assert(io.open(arg[1], "rb"))
local s = f:read("a")
f:close()
local seq = s:match("}%s*{(.*)}%s*$")
local stack = {} -- {id, frames left (math.huge = until cleared)}
for delay, spec in seq:gmatch("{(%d+)}{([^}]*)}") do
  local alive = {}
  for _, e in ipairs(stack) do
    e[2] = e[2] - 1
    if e[2] > 0 then alive[#alive + 1] = e end
  end
  stack = alive
  for item in spec:gmatch("[^,]+") do
    if item == "c" then
      stack = {}
    else
      local id, n = item:match("^(%d+)x?(%d*)$")
      n = tonumber(n)
      stack[#stack + 1] = { tonumber(id), (n == nil) and 1 or (n == 0 and math.huge or n) }
    end
  end
  local ids = {}
  for i, e in ipairs(stack) do ids[i] = e[1] end
  print(delay .. " " .. table.concat(ids, " "))
end
