-- Mandelbrot: float-heavy inner loop. Prints a checksum of escape iterations.
local N = tonumber(arg and arg[1]) or 800
local limit2 = 4.0
local sum = 0
for y = 0, N - 1 do
  local ci = 2.0 * y / N - 1.0
  for x = 0, N - 1 do
    local cr = 2.0 * x / N - 1.5
    local zr, zi, i = 0.0, 0.0, 0
    while i < 100 do
      local zr2, zi2 = zr * zr, zi * zi
      if zr2 + zi2 > limit2 then break end
      zi = 2.0 * zr * zi + ci
      zr = zr2 - zi2 + cr
      i = i + 1
    end
    sum = sum + i
  end
end
print(string.format("mandelbrot N=%d checksum=%d", N, sum))
