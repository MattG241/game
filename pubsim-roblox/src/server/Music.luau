-- The pub's sound: rain on the street, the room's chatter, the fire, the background soundtrack
-- (chosen for the moment: opening up, a rainy night, a busy one, closing time), the jukebox, and
-- live music nights booked from the menu (musicians on the stage or by the fire, with a crowd).

local Shared = game:GetService("ReplicatedStorage").Shared
local Data = require(Shared.Data)
local Layout = require(Shared.Layout)
local Audio = require(script.Parent.Audio)
local Npc = require(script.Parent.Npc)

local Music = {}

local G
local rain, chatter, fire
local song, songEnds, songId = nil, 0, nil
local musicians = {}
local rng = Random.new()
local eventById = {}
for _, e in Data.events do
	eventById[e.id] = e
end
Music.events = Data.events
Music.eventById = eventById

local live = { playing = false, event = nil, songsLeft = 0, finished = false }
Music.live = live

function Music.init(context)
	G = context
	G.live = live
end

local function trackFor(role)
	for _, t in Data.music.tracks do
		if t.role == role then
			return t.id
		end
	end
	return nil
end

local function stopSong()
	if song then
		song:Stop()
		song:Destroy()
		song = nil
	end
end

local function playSong(id, parent)
	stopSong()
	if not id then
		return
	end
	local s, len = Audio.song(id, parent)
	song = s
	songId = id
	songEnds = os.clock() + (len or 180) + 4
end

-- The right song for the moment when the last one finishes.
local function background()
	local st = G.state
	if st.phase == "prep" then
		return trackFor("opening")
	elseif st.phase == "last_orders" or st.phase == "closing" then
		return trackFor("closing")
	end
	local pool = {}
	for _, t in Data.music.tracks do
		if t.category == "atmosphere" and t.role ~= "menu" and t.role ~= "closing" then
			table.insert(pool, t.id)
		end
	end
	if st.weather == "rain" or st.weather == "storm" then
		table.insert(pool, trackFor("rain"))
	end
	if #G.customers() >= 8 then
		table.insert(pool, trackFor("busy"))
	end
	local pick = pool[rng:NextInteger(1, #pool)]
	if pick == songId and #pool > 1 then
		pick = pool[((table.find(pool, pick) or 0) % #pool) + 1]
	end
	return pick
end

function Music.nextSong()
	playSong(background(), G.info.jukebox)
end

function Music.setupAmbience()
	local street = G.info.rain and G.info.rain.Parent
	rain = Audio.loop("sfx/rain_window_loop", street, 0.5) or Audio.loop("sfx/rain_loop", street, 0.5)
	chatter = Audio.loop("sfx/pub_busy_loop", nil, 0) or Audio.loop("sfx/crowd_loop", nil, 0)
	if G.info.fireLight then
		fire = Audio.loop("sfx/fire_loop", G.info.fireLight.Parent, 0.6)
	end
end

local function spawnMusicians(ev)
	local at = if ev.where == "stage" and G.state:hasUpgrade("snug_stage") then G.info.stage else Layout.FIREPLACE + Vector3.new(5.5, 0, 0)
	local n = #(ev.players or { "fiddle" })
	for i, inst in ev.players or { "fiddle" } do
		local offset = (i - (n + 1) / 2) * 2.4
		local p = at + Vector3.new(0, if ev.where == "stage" then 0.7 else 0, offset)
		local m = Npc.spawn("Musician", { gender = "m" }, rng, G.folder, CFrame.lookAt(p + Vector3.new(0, 3, 0), p + Vector3.new(-6, 3, 0)))
		if m then
			Npc.setTag(m, inst)
			-- a stool and an instrument
			local stool = Instance.new("Part")
			stool.Shape = Enum.PartType.Cylinder
			stool.Size = Vector3.new(0.3, 1.6, 1.6)
			stool.Anchored = true
			stool.Material = Enum.Material.Wood
			stool.Color = Color3.fromRGB(96, 58, 32)
			stool.CFrame = CFrame.new(p + Vector3.new(0, 1.45, 0)) * CFrame.Angles(0, 0, math.rad(90))
			stool.Parent = m.model
			Npc.sitOn(m, stool)
			local body = Instance.new("Part")
			body.Size = if inst == "bodhran" then Vector3.new(1.8, 1.8, 0.3) else Vector3.new(0.7, 1.4, 0.3)
			body.Shape = if inst == "bodhran" then Enum.PartType.Cylinder else Enum.PartType.Block
			body.Color = if inst == "accordion" then Color3.fromRGB(160, 30, 30) else Color3.fromRGB(150, 80, 30)
			body.Material = Enum.Material.Wood
			body.CanCollide = false
			body.Massless = true
			body.Anchored = true
			body.CFrame = m.root.CFrame * CFrame.new(0, 0.3, -0.9)
			body.Parent = m.model
			table.insert(musicians, m)
		end
	end
	return at
end

local function endLive()
	for _, m in musicians do
		if m.model then
			m.model:Destroy()
		end
	end
	table.clear(musicians)
	live.playing = false
	live.finished = true
	G.state.liveAtmosphere = 0
	G.state.liveTips = 0
end

-- Books an act for a day (the fee is paid now). Returns "" or why not.
function Music.book(day, id)
	local ev = eventById[id]
	local st = G.state
	if not ev then
		return "Unknown act"
	end
	if st.bookings[tostring(day)] then
		return "There's already music booked that night"
	end
	if (ev.requires or "") ~= "" and not st:hasUpgrade(ev.requires) then
		return "Needs " .. ev.requires
	end
	if st.reputation < (ev.min_rep or 0) then
		return string.format("Needs reputation %d", math.floor(ev.min_rep))
	end
	if not st:spend(ev.fee, "event_fees") then
		return "Not enough cash"
	end
	st.bookings[tostring(day)] = id
	return ""
end

function Music.tick(dt)
	local st = G.state
	-- the room fills with talk as it fills with people
	if chatter then
		chatter.Volume = math.clamp(#G.customers() / 14, 0, 1) * 0.5
	end
	if rain then
		rain.Volume = if st.weather == "rain" then 0.45 elseif st.weather == "storm" then 0.7 else 0
	end
	if fire then
		fire.Volume = if st:hasUpgrade("fireplace") then 0.6 else 0
	end
	if G.info.rain then
		G.info.rain.Enabled = st.weather == "rain" or st.weather == "storm"
	end
	-- tonight's booked act starts at eight
	local booked = st.bookings[tostring(st.day)]
	if booked and not live.playing and not live.finished and st.phase == "open" and st.hour >= 20 then
		local ev = eventById[booked]
		live.playing = true
		live.event = ev
		live.songsLeft = 2
		local at = spawnMusicians(ev)
		st.liveAtmosphere = ev.atmosphere or 10
		st.liveTips = ev.tips or 0
		G.notify(string.format("Tonight: %s!", ev.name), "good")
		st.stats.eventsHosted += 1
		playSong(ev.track, musicians[1] and musicians[1].head or nil)
		local _ = at
	end
	if os.clock() >= songEnds then
		if live.playing then
			live.songsLeft -= 1
			if live.songsLeft <= 0 or st.phase ~= "open" then
				G.notify("The band's finished. What a night!", "good")
				endLive()
				Music.nextSong()
			else
				local pool = {}
				for _, t in Data.music.tracks do
					if t.category == "live" then
						table.insert(pool, t.id)
					end
				end
				playSong(pool[rng:NextInteger(1, #pool)], musicians[1] and musicians[1].head or nil)
			end
		else
			Music.nextSong()
		end
	end
end

function Music.newDay()
	if live.playing then
		endLive()
	end
	live.finished = false
	Music.nextSong()
end

return Music
