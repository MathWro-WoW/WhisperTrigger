local addonName, ns = ...

local UnitClass = UnitClass
local issecretvalue = issecretvalue

local playerSpellBank = Enum.SpellBookSpellBank.Player
local petSpellBank = Enum.SpellBookSpellBank.Pet
local IsSpellKnownOrInSpellBook = C_SpellBook.IsSpellKnownOrInSpellBook

local primaryInterrupts = {
	DEATHKNIGHT = { 47528 }, -- Mind Freeze
	DEMONHUNTER = { 183752 }, -- Disrupt, including Devourer
	DRUID = { 78675, 106839 }, -- Solar Beam, Skull Bash; Restoration has neither
	EVOKER = { 351338 }, -- Quell
	HUNTER = { 147362, 187707 }, -- Counter Shot, Muzzle
	MAGE = { 2139 }, -- Counterspell
	MONK = { 116705 }, -- Spear Hand Strike
	PALADIN = { 96231 }, -- Rebuke; routine Avenger's Shield casts must not dismiss
	PRIEST = { 15487 }, -- Silence, only if learned
	ROGUE = { 1766 }, -- Kick
	SHAMAN = { 57994 }, -- Wind Shear
	WARLOCK = { 119910, 19647, 119914, 89766 }, -- Spell Lock / Felguard Axe Toss
	WARRIOR = { 6552 }, -- Pummel
}

local castInterrupts = {
	DEATHKNIGHT = { [47528] = true },
	DEMONHUNTER = { [183752] = true },
	DRUID = { [78675] = true, [106839] = true },
	EVOKER = { [351338] = true },
	HUNTER = { [147362] = true, [187707] = true },
	MAGE = { [2139] = true },
	MONK = { [116705] = true },
	PALADIN = { [96231] = true },
	PRIEST = { [15487] = true },
	ROGUE = { [1766] = true },
	SHAMAN = { [57994] = true },
	WARLOCK = {
		[19647] = true, -- Spell Lock (Felhunter)
		[119910] = true, -- Command Demon: Spell Lock
		[89766] = true, -- Axe Toss (Felguard)
		[119914] = true, -- Command Demon: Axe Toss
	},
	WARRIOR = { [6552] = true, [386071] = true }, -- Pummel, Disrupting Shout
}

local function GetKnownInterrupt(spellIDs, spellBank)
	for index = 1, #spellIDs do
		local spellID = spellIDs[index]
		if IsSpellKnownOrInSpellBook(spellID, spellBank, true) then
			return spellID
		end
	end
end

function ns.GetInterruptSpellID()
	local _, class = UnitClass("player")
	local spellIDs = primaryInterrupts[class]
	if not spellIDs then
		return nil
	end

	local spellID = GetKnownInterrupt(spellIDs, playerSpellBank)
	if spellID or class ~= "WARLOCK" then
		return spellID
	end

	return GetKnownInterrupt(spellIDs, petSpellBank)
end

function ns.IsInterruptCast(unit, spellID)
	if issecretvalue(unit) or issecretvalue(spellID) then
		return false
	end
	if unit ~= "player" and unit ~= "pet" then
		return false
	end

	local _, class = UnitClass("player")
	local interrupts = castInterrupts[class]
	return interrupts and interrupts[spellID] or false
end
