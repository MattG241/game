-- Re-saves a place file as a binary .rbxl through Lune's Roblox library (rbx-dom).
-- lune run tools/to_binary.luau in.rbxlx out.rbxl
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local input, output = process.args[1], process.args[2]
local game = roblox.deserializePlace(fs.readFile(input))
local count = #game:GetDescendants()
fs.writeFile(output, roblox.serializePlace(game))
print(string.format("%s -> %s (%d instances, %d KB)", input, output, count, math.floor(#fs.readFile(output) / 1024)))
