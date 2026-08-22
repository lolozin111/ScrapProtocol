--[[
	AutoMinerConfig.lua
	The "Mini Particle Accelerator" — a one-time-craftable structure that passively drips out a
	small amount of ore over time, so there's always SOME progress happening even when you're
	not actively mining. Deliberately modest on purpose: it should feel worth having, not like a
	reason to stop mining. The AutoMiner game pass (see ShopConfig.GamePasses.AutoMiner, already
	scaffolded there) doubles the rate — noticeably better, but still nowhere near what active
	mining nets you in the same stretch of time.
]]

local AutoMinerConfig = {}

AutoMinerConfig.Cost = { ScrapIron = 60, CopperWire = 15 } -- "built of scraps and iron"

AutoMinerConfig.OreKey = "ScrapIron"    -- what it produces — kept to the most basic ore on purpose, so it
                                         -- can't be used to skip past the tool-tier/wave-unlock gates on
                                         -- the rarer stuff.
AutoMinerConfig.TickSeconds = 60        -- how often it produces a batch
AutoMinerConfig.BaseYieldPerTick = 3    -- without the game pass: ~3 Scrap Iron/minute passively
AutoMinerConfig.GamePassMultiplier = 2  -- with the AutoMiner game pass: doubles the tick yield (mirrors
                                         -- this game's existing "DoubleScrap" 2x framing elsewhere)
AutoMinerConfig.MaxOwned = 1            -- MVP: one per player. Add a slot game pass later (mirroring
                                         -- ExtraRobotSlot) if you ever want to allow more than one.

return AutoMinerConfig
