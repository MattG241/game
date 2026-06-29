--!strict
--[[
	Cosmetics
	---------
	Catalogue of starter skins / outfits. Each entry is data-only so the same
	table drives the shop UI, the inventory, equip validation, and the visual
	applier on the character.

	`unlock`:
	  "default"  -> owned by everyone
	  "coins"    -> purchasable with Fight Coins (uses `price`)
	  "level"    -> auto-unlocks at `level`
	  "gamepass" -> requires owning the SkinPack gamepass
]]

export type Cosmetic = {
	id: string,
	name: string,
	description: string,
	bodyColor: Color3,
	accent: Color3, -- neon trim / particle tint
	material: Enum.Material,
	unlock: string,
	price: number?,
	level: number?,
	rarity: string,

	-- OPTIONAL catalog dressing (free way to make detailed skins without
	-- modelling). Paste catalog asset IDs (numbers). Applied via
	-- HumanoidDescription in PlayerService.applyCosmetic; leave nil for a pure
	-- recolor skin. Example:
	--   shirtId = 855314844, pantsId = 855316765,
	--   accessoryIds = { 1374269, 11748356 },  -- hats/masks/helmets
	shirtId: number?,
	pantsId: number?,
	accessoryIds: { number }?,
}

local Cosmetics = {}

Cosmetics.List = {
	{
		id = "street_rookie",
		name = "Street Rookie",
		description = "Where everyone starts. Scrappy and ready.",
		bodyColor = Color3.fromRGB(120, 120, 130),
		accent = Color3.fromRGB(200, 200, 210),
		material = Enum.Material.SmoothPlastic,
		unlock = "default",
		rarity = "Common",
	},
	{
		id = "crimson_brawler",
		name = "Crimson Brawler",
		description = "Blood-red wraps for the relentless.",
		bodyColor = Color3.fromRGB(150, 30, 40),
		accent = Color3.fromRGB(255, 70, 70),
		material = Enum.Material.SmoothPlastic,
		unlock = "coins",
		price = 750,
		rarity = "Uncommon",
	},
	{
		id = "toxic_runner",
		name = "Toxic Runner",
		description = "Acid-green and twice as fast on its feet.",
		bodyColor = Color3.fromRGB(40, 90, 40),
		accent = Color3.fromRGB(120, 255, 90),
		material = Enum.Material.Neon,
		unlock = "level",
		level = 8,
		rarity = "Rare",
	},
	{
		id = "voltage",
		name = "Voltage",
		description = "Crackling electric-blue circuitry.",
		bodyColor = Color3.fromRGB(20, 40, 90),
		accent = Color3.fromRGB(80, 180, 255),
		material = Enum.Material.Neon,
		unlock = "coins",
		price = 2000,
		rarity = "Rare",
	},
	{
		id = "neon_phantom",
		name = "Neon Phantom",
		description = "Premium magenta glow. The arena remembers you.",
		bodyColor = Color3.fromRGB(40, 0, 50),
		accent = Color3.fromRGB(220, 40, 255),
		material = Enum.Material.Neon,
		unlock = "gamepass",
		rarity = "Epic",
	},
	{
		id = "golden_legend",
		name = "Golden Legend",
		description = "Only the truly dedicated wear gold.",
		bodyColor = Color3.fromRGB(120, 90, 20),
		accent = Color3.fromRGB(255, 215, 60),
		material = Enum.Material.Neon,
		unlock = "level",
		level = 40,
		rarity = "Legendary",
	},
}

-- id -> cosmetic, built once.
local byId: { [string]: Cosmetic } = {}
for _, c in Cosmetics.List do
	byId[c.id] = c
end
Cosmetics.ById = byId

function Cosmetics.get(id: string): Cosmetic?
	return byId[id]
end

Cosmetics.DefaultId = "street_rookie"

-- The set of cosmetics a brand-new player owns.
function Cosmetics.defaultOwned(): { [string]: boolean }
	local owned = {}
	for _, c in Cosmetics.List do
		if c.unlock == "default" then
			owned[c.id] = true
		end
	end
	return owned
end

return Cosmetics
