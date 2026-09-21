--[[
	EnemyAwarenessConfig.lua
	Whether a raid enemy knows you're there yet — the user's design (DESIGN_NOTES, "The user's enemy
	AI design", 2026-09-21). Read by EnemyAwareness.lua.

	THE STATES. An enemy listed in Types below starts a Combat room UNAWARE: it idles, and now and
	then wanders to a nearby spot, until it SPOTS you (in range AND in line of sight), is SHOT, or
	answers a Raider's ALARM. From then on it is ALERTED for the rest of the room and fights exactly
	as before — the normal EnemyAI pattern takes over.

	WHERE IT APPLIES. Raids only (the user's call — a base-defense wave exists to attack the base, so
	those enemies stay aware from spawn), and only COMBAT rooms: an Ambush is by definition an enemy
	that already knows you're coming, and a Boss room shouldn't open on an idling boss. Types NOT
	listed below are always aware — today that's ScrapCrawler, SentinelDrone and VoidwakenHulk, which
	the user hasn't designed a behaviour for yet ("always know where you are" until then).

	DISTANCES are studs. For scale: the placeholder raid room is 260 across, and a player walks at 16
	studs a second.
]]

local EnemyAwarenessConfig = {}

EnemyAwarenessConfig.Types = {
	-- The user: "they see from far away and will go running to you."
	Scavenger = {
		SightRange = 110,
		WanderRadius = 20,
		AnswersAlarm = 1, -- the Raider's alarm "calls everybody"
	},

	-- The user: "a lower range of spotting you, but once they do they call everybody towards you".
	-- The one type that RAISES the alarm. It still answers another Raider's.
	Raider = {
		SightRange = 35,
		WanderRadius = 20,
		RaisesAlarm = true,
		AnswersAlarm = 1,
	},

	-- The user: "brutes will go around the map and if they spot you they behave like salvagers, and
	-- they can get called from a raider alarm". The roamer — hence the big WanderRadius.
	Brute = {
		SightRange = 60,
		WanderRadius = 90,
		AnswersAlarm = 1,
	},

	-- The user: "a way lower detection range, and has a 50% chance of picking up an alert call from
	-- raider". A guard, not a roamer — it mostly stands its ground.
	Siegebreaker = {
		SightRange = 20,
		WanderRadius = 8,
		AnswersAlarm = 0.5, -- rolled once per alarm it hears
	},
}

-- How often (seconds) an unaware enemy looks for the player. Each enemy's first look is offset by a
-- random fraction of this so a room doesn't raycast in lockstep.
EnemyAwarenessConfig.SightCheckInterval = 0.25

-- Idle for a random time in this range, then wander to a random point within the type's
-- WanderRadius of where it SPAWNED (so a roamer roams its patch and doesn't drift across the map).
EnemyAwarenessConfig.IdleSecondsMin = 2
EnemyAwarenessConfig.IdleSecondsMax = 5

-- Unaware enemies stroll rather than charge: this fraction of the type's MoveSpeed. Restored the
-- instant it's alerted (EnemyAI recomputes speed from the record's MoveSpeed every tick).
EnemyAwarenessConfig.WanderSpeedMultiplier = 0.45

-- A wander leg that hasn't arrived after this long is abandoned for a fresh idle, so an enemy that
-- picked an awkward spot doesn't stand grinding at it.
EnemyAwarenessConfig.WanderGiveUpSeconds = 8

-- THE ALARM. How long after one Raider raises it before ANY Raider in the same room can raise
-- another — two Raiders spotting you a second apart is one alarm, not two.
EnemyAwarenessConfig.AlarmCooldown = 6

-- What the player gets when caught (EnemyAlarm.client.lua): a sound, a "!" over the Raider that
-- called it, and a red flash at the screen edge. The sound is a built-in Roblox client sound so it
-- works with nothing uploaded; paste an rbxassetid:// here to replace it, or "" for silence.
EnemyAwarenessConfig.AlarmSound = "rbxasset://sounds/electronicpingshort.wav"
EnemyAwarenessConfig.AlarmSoundVolume = 0.8
EnemyAwarenessConfig.AlarmMarkerSeconds = 2.5

-- ANIMATION while unaware. The user asked for wandering to use "the default player walking
-- animation"; these are Roblox's own R15 defaults. They only move a rig whose joints use R15 names
-- — anything else plays nothing and stays in its rest pose, so if a type T-poses while wandering,
-- that's the reason, and the fix is its own Idle/Move animation in EnemyConfig. A type's own Idle in
-- EnemyConfig always wins over DefaultIdle.
EnemyAwarenessConfig.DefaultWalkAnimation = "rbxassetid://507777826"
EnemyAwarenessConfig.DefaultIdleAnimation = "rbxassetid://507766666"

function EnemyAwarenessConfig.Get(typeKey: string)
	return EnemyAwarenessConfig.Types[typeKey]
end

return EnemyAwarenessConfig
