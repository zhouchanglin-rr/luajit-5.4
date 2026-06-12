-- String processing: build, split, count, hash. Tests interned-string and
-- pattern-matching paths (LuaJIT does NOT JIT-compile string.* C fast paths,
-- so this is a more interpreter/library-bound workload).
local REPS = tonumber(arg and arg[1]) or 2000
local words = {"the","quick","brown","fox","jumps","over","the","lazy","dog"}
local total_len, token_count, checksum = 0, 0, 0
for _ = 1, REPS do
  -- build a line with table.concat
  local parts = {}
  for i = 1, 50 do parts[i] = words[(i % #words) + 1] end
  local line = table.concat(parts, " ")
  total_len = total_len + #line
  -- tokenize
  for w in line:gmatch("%a+") do
    token_count = token_count + 1
    -- djb2 over the token
    local h = 5381
    for k = 1, #w do h = (h * 33 + w:byte(k)) % 1000003 end
    checksum = (checksum + h) % 1000000007
  end
  -- gsub transform
  local _, n = line:gsub("o", "0")
  checksum = (checksum + n) % 1000000007
end
print(string.format("string_ops reps=%d len=%d tokens=%d checksum=%d",
  REPS, total_len, token_count, checksum))
