-- Sound: every clip lives somewhere inside one of a few long uploaded audio files (see
-- tools/pack_audio.py), so a clip plays as a region of its file. Without uploaded audio (before the
-- first upload, or a missing file) everything simply stays quiet.

local SoundService = game:GetService("SoundService")
local Shared = game:GetService("ReplicatedStorage").Shared
local AudioMap = require(Shared.AudioMap)
local Data = require(Shared.Data)

local Audio = {}

local groups = {}
local function group(name, volume)
	if not groups[name] then
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = volume
		g.Parent = SoundService
		groups[name] = g
	end
	return groups[name]
end

function Audio.setup()
	pcall(function()
		SoundService.AmbientReverb = Enum.ReverbType.LivingRoom
	end)
	group("Music", 0.5)
	group("Ambience", 0.45)
	group("Effects", 0.8)
	group("Voices", 1.0)
end

function Audio.has(key)
	return AudioMap[key] ~= nil
end

local function make(key, parent, volume, groupName)
	local c = AudioMap[key]
	if not c then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = "rbxassetid://" .. tostring(c.asset)
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(c.start, c.start + c.len)
	s.Volume = volume or 0.6
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 70
	s.SoundGroup = group(groupName or "Effects", 0.8)
	s.Parent = parent or SoundService
	return s, c.len
end

-- Plays a clip once (at a part for 3D sound, or everywhere); it tidies itself up.
function Audio.play(key, parent, volume, groupName)
	local s, len = make(key, parent, volume, groupName)
	if not s then
		return nil
	end
	s:Play()
	task.delay((len or 5) + 1, function()
		s:Destroy()
	end)
	return s
end

-- A looping clip (rain, the room's chatter, the fire). Returns the Sound to adjust or stop.
function Audio.loop(key, parent, volume, groupName)
	local s, len = make(key, parent, volume, groupName or "Ambience")
	if not s then
		return nil
	end
	local c = AudioMap[key]
	s.Looped = true
	s.LoopRegion = NumberRange.new(c.start, c.start + c.len)
	s:Play()
	local _ = len
	return s
end

-- A song by its track id (t01..t20), with its level from music.json.
function Audio.song(trackId, parent)
	local gain = 0
	for _, t in Data.music.tracks do
		if t.id == trackId then
			gain = t.gain_db or 0
		end
	end
	local s, len = make("music/" .. trackId, parent, 0.55 * 10 ^ (gain / 20), "Music")
	if s then
		s:Play()
	end
	return s, len
end

-- A recorded line for a speaker and a situation ("order_stout", "praise", "goodbye"...).
-- Returns the words spoken (for the speech bubble), or nil when there's no such line.
function Audio.voice(voice, tag, parent)
	if not voice then
		return nil
	end
	local options = {}
	for _, l in Data.voice_lines.lines do
		if l.voice == voice and l.tag == tag and AudioMap["voice/" .. l.id] then
			table.insert(options, l)
		end
	end
	if #options == 0 then
		return nil
	end
	local l = options[math.random(1, #options)]
	Audio.play("voice/" .. l.id, parent, 1.0, "Voices")
	return l.text
end

return Audio
