--!strict
--[[
	Animations
	----------
	Central animation registry + a tiny player/cacher. Paste your (free) Roblox
	animation asset IDs into `Animations.Ids` as "rbxassetid://<number>" strings.

	WHERE TO GET FREE ANIMATIONS:
	  * Roblox Creator Store / Toolbox -> Animations (filter Free). Search
	    "punch", "combat", "block", "dodge roll".
	  * Or create your own in the Studio Animation Editor (free) and publish them.
	  * After publishing, copy the asset id and paste it below.

	Everything is a no-op while an id is "" — combat still works, it just won't
	play that motion. So you can ship without animations and add them later
	without touching any other file.

	Tracks are cached per-Animator so we never re-load the same animation twice.
	Played on the SERVER (from CombatService) so every client sees the same,
	authoritative motion.
]]

local Animations = {}

-- name -> "rbxassetid://<id>".  Leave "" to disable that animation.
Animations.Ids = {
	-- light attack chain (cycled by combo index)
	punch1 = "",
	punch2 = "",
	punch3 = "",
	-- 4th-hit finisher
	finisher = "",
	-- defense / mobility
	block = "", -- looped hold pose
	dodge = "",
	-- ultimate
	special = "",
	-- reactions
	hit = "", -- brief flinch when struck by a heavy hit
}

-- animator -> { name -> AnimationTrack }   (weak keys so GC'd characters clean up)
local trackCache: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any
-- id -> Animation instance (shared across all players)
local animObjects: { [string]: Animation } = {}

local function getAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator :: Animator
end

export type PlayOpts = {
	looped: boolean?,
	priority: Enum.AnimationPriority?,
	speed: number?,
	fade: number?,
}

-- Play a named animation on a humanoid. Returns the track (or nil if disabled).
function Animations.play(humanoid: Humanoid?, name: string, opts: PlayOpts?): AnimationTrack?
	if not humanoid then
		return nil
	end
	local id = Animations.Ids[name]
	if not id or id == "" then
		return nil
	end

	local animator = getAnimator(humanoid)
	local perAnimator = trackCache[animator]
	if not perAnimator then
		perAnimator = {}
		trackCache[animator] = perAnimator
	end

	local track = perAnimator[name]
	if not track then
		local anim = animObjects[id]
		if not anim then
			anim = Instance.new("Animation")
			anim.AnimationId = id
			animObjects[id] = anim
		end
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not loaded then
			return nil
		end
		track = loaded
		perAnimator[name] = track
	end

	track.Looped = opts and opts.looped or false
	if opts and opts.priority then
		track.Priority = opts.priority
	end
	track:Play(opts and opts.fade or 0.1)
	if opts and opts.speed then
		track:AdjustSpeed(opts.speed)
	end
	return track
end

-- Stop a named animation if it's playing.
function Animations.stop(humanoid: Humanoid?, name: string, fade: number?)
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local perAnimator = trackCache[animator :: Animator]
	local track = perAnimator and perAnimator[name]
	if track then
		track:Stop(fade or 0.1)
	end
end

-- HIT-STOP: briefly freeze every animation currently playing on the humanoid,
-- then restore. This is the classic fighting-game "impact freeze" and reads as
-- weighty, clip-worthy hits. No-op if nothing is animating yet.
function Animations.freeze(humanoid: Humanoid?, duration: number)
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local tracks = (animator :: Animator):GetPlayingAnimationTracks()
	if #tracks == 0 then
		return
	end
	local previous: { [AnimationTrack]: number } = {}
	for _, t in tracks do
		previous[t] = t.Speed
		t:AdjustSpeed(0)
	end
	task.delay(duration, function()
		for t, speed in previous do
			if t.IsPlaying then
				t:AdjustSpeed(speed == 0 and 1 or speed)
			end
		end
	end)
end

return Animations
