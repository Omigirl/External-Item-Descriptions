local game = Game()
local level
local currentRoom
local blacklist
local holdMapDesc
local currentPlayer

-- Rainbow Worm's trinket IDs it grants, in order
local rainbowWormEffects = { [0] = 9, 11, 65, 27, 10, 12, 26, 66, 96, 144 }
-- Mysterious Paper does not play well with displaying Error 404's effect
local mysteriousPaperBlacklist = { [23] = true, [48] = true }

-- Simple function to help with adding properly formatted sections to the desc
local function append(icon, title, newDesc)
	holdMapDesc = holdMapDesc .. (icon or "{{Blank}}") .. " {{ColorEIDObjName}}" .. title .. "#" .. newDesc .. "#"
end

-- Helper function to easily add an item's stock description to the desc
-- Don't use if you need to customize the desc! (Like Sanguine Bond's result highlighting)
-- extraIcon is for when we want a special icon before the line (like {{Dice Bag Icon}} {{Dice Item Icon}})
local variantToName = { [70] = "Pill", [100] = "Collectible", [300] = "Card", [350] = "Trinket" }
local function addObjectDesc(type, variant, subtype, extraIcon)
	local objectID = type .. "." .. variant .. "." .. subtype
	if not blacklist[objectID] then
		blacklist[objectID] = true
		local demoDescObj = EID:getDescriptionObj(type, variant, subtype)
		local iconString = "{{" .. variantToName[variant] .. subtype .. "}}"
		if extraIcon then iconString = extraIcon .. " " .. iconString end
		append(iconString, demoDescObj.Name, demoDescObj.Description)
	end
end

-- Banned items: Metronome, Plan C, Glowing Hour Glass, Breath of Life, Clicker, R Key
-- Reduced chance: Death Certificate (15%), Genesis (25%)
-- I saw something in the code about rerolling Forget Me Now but not sure what the criteria was
local metronomeBlacklist = {[488] = 1, [475] = 1, [422] = 1} --AB+ can choose Clicker lol rip
if REPENTANCE then metronomeBlacklist = {[488] = 1, [475] = 1, [422] = 1, [326] = 1, [482] = 1, [636] = 1, [628] = 0.85, [622] = 0.75 } end

-- Should we account for Car Battery? (Both if we have it, and if it grants it which immediately uses it again)
function EID:MetronomePrediction()
	local itemConfig = Isaac.GetItemConfig()
	local numCollectibles = EID:GetMaxCollectibleID()
	local metronomeRNG = currentPlayer:GetCollectibleRNG(CollectibleType.COLLECTIBLE_METRONOME):GetSeed()
	local rerollChance = 0
	if REPENTANCE then
		metronomeRNG = EID:RNGNext(metronomeRNG)
		rerollChance = metronomeRNG
	end
	local attempts = 15
	while attempts > 0 do
		attempts = attempts - 1
		metronomeRNG = EID:RNGNext(metronomeRNG)
		local sel = metronomeRNG % numCollectibles + 1
		if itemConfig:GetCollectible(sel) ~= nil then
			if metronomeBlacklist[sel] then
				-- A few items have a reroll chance in Repentance
				if metronomeBlacklist[sel] < 1 then
					rerollChance = EID:RNGNext(rerollChance, 0x02, 0x0F, 0x11)
					local rerollFloat = EID:SeedToFloat(rerollChance)
					if rerollFloat < 1 - metronomeBlacklist[sel] then
						-- We succeeded the reroll chance
						return "{{Collectible" .. sel .. "}} {{ColorGray}}" .. EID:getObjectName(5,100,sel) .. "#" .. EID:getDescriptionObj(5,100,sel).Description
					end
				end
			else
				return "{{Collectible" .. sel .. "}} {{ColorGray}}" .. EID:getObjectName(5,100,sel) .. "#" .. EID:getDescriptionObj(5,100,sel).Description
			end
		end
	end
	-- as the code puts it, [warn] No Collectible found for Metronome!
	return "None"
end

-- Teleport! Destination Prediction --
local function teleport1Prediction()
	if REPENTANCE and currentPlayer:GetSprite():GetAnimation() == "TeleportUp" then return end
	local level = game:GetLevel()
	local currentRoomIndex = level:GetCurrentRoomDesc().SafeGridIndex
	local possibleRooms = {}
	for i = 0, 168 do
		local room = level:GetRoomByIdx(i)
		-- Currently, any non-red room on the grid that we aren't in is a valid choice
		-- Is there more criteria to look out for?
		if room.GridIndex >= 0 and room.SafeGridIndex ~= currentRoomIndex and room.Data.Type ~= 29 and (not REPENTANCE or room.Flags & 1024 ~= 1024) then
			table.insert(possibleRooms, i)
		end
	end
	local teleSeed = currentPlayer:GetCollectibleRNG(CollectibleType.COLLECTIBLE_TELEPORT):GetSeed()
	teleSeed = EID:RNGNext(teleSeed, 5, 9, 7)
	teleSeed = EID:RNGNext(teleSeed, 0x02, 0x0F, 0x19) -- magic disassembled numbers!
	
	local resultRoomIndex = possibleRooms[(teleSeed % #possibleRooms) + 1]
	local resultRoom = level:GetRoomByIdx(resultRoomIndex)
	local resultSafeIndex = resultRoom.SafeGridIndex
	
	local roomIcon = EID.RoomTypeToMarkup[resultRoom.Data.Type]
	if resultRoom.Data.Type == 1 then roomIcon = EID.RoomShapeToMarkup[resultRoom.Data.Shape] end
	local roomNames = EID:getDescriptionEntry("RoomTypeNames")
	local roomName = roomNames[resultRoom.Data.Type]
	-- Find our X/Y difference from the target location, if we're on the map
	local d = ""
	if currentRoomIndex >= 0 then
		local myPos = Vector(currentRoomIndex % 13, math.floor(currentRoomIndex / 13))
		local newPos = Vector(resultSafeIndex % 13, math.floor(resultSafeIndex / 13))
		local diffX = math.floor(newPos.X - myPos.X)
		local diffY = math.floor(newPos.Y - myPos.Y)

		if diffY > 0 then d = d .. "{{ArrowGrayDown}} " .. diffY
		elseif diffY < 0 then d = d .. "{{ArrowGrayUp}} " .. math.abs(diffY) end
		if d ~= "" and diffX ~= 0 then d = d .. "," end
		if diffX > 0 then d = d .. "{{ArrowGrayRight}} " .. diffX
		elseif diffX < 0 then d = d .. "{{ArrowGrayLeft}} " .. math.abs(diffX) end
	end
	if d ~= "" then d = "#{{Blank}} " .. d end

	append("{{Collectible44}}", EID:getObjectName(5, 100, 44) .. EID:getDescriptionEntry("HoldMapHeader"), roomIcon .. " " .. roomName .. d)
end

-- Teleport 2 Destination Prediction --
local teleport2Order = { 1,5,8,2,4,13,21,12,10,6,11,18,19,9,20,24,7,1025,666,3 }
local teleport2GreedOrder = { 1,5,2,4,10,23,8,666,3 }
local teleport2Icons = { [1025] = "{{RedRoom}}", [666] = "{{AngelDevilChance}}" }

local function teleport2Prediction()
	local level = game:GetLevel()
	local rooms = level:GetRooms()
	--I AM ERROR Room always considered uncleared
	local unclearedTypes = {[3] = true}
	for i = 0, rooms.Size - 1 do
		local room = rooms:Get(i)
		
		if not room.Clear then
			-- Check for Special Red Rooms, which get ordered differently than their non-red version
			if REPENTANCE and room.Data.Type ~= 1 and room.Flags & 1024 == 1024 then unclearedTypes[1025] = true
			else unclearedTypes[room.Data.Type] = true end
		end
	end
	--Angel/Devil Room check (it lives off the map)
	if not level:GetRoomByIdx(-1).Clear then unclearedTypes[666] = true end
	
	local greed = game:IsGreedMode()
	local roomOrder = (greed and teleport2GreedOrder) or teleport2Order
	local roomNames = EID:getDescriptionEntry("RoomTypeNames")
	
	for i,v in ipairs(roomOrder) do
		if unclearedTypes[v] then
			local descString = (teleport2Icons[v] or EID.RoomTypeToMarkup[v]) .. " " .. roomNames[v]
			-- Tall Vertical Main Greed Room exception, because why not, attention to detail
			if v == 1 and greed then descString = "{{RoomLongVertical}} " .. roomNames[v] end
			append("{{Collectible419}}", EID:getObjectName(5, 100, 419) .. EID:getDescriptionEntry("HoldMapHeader"), descString)
			return
		end
	end
end

-- Sanguine Bond Chance Display / Prediction --
--order of checking: 15% Pennies, 48% Damage, 58% Hearts, 63% Item, 65% Leviathan, 100% Nothing
local sanguineResults = { { 0.15, 3 }, { 0.48, 2 }, { 0.58, 4 }, { 0.63, 5 }, { 0.65, 6 }, { 1, 1 } }

-- this isn't even used in this file anymore, it's in main, but there isn't really a better place to put it yet
function EID:trimSanguineDesc(descObj)
	local currentRoom = game:GetLevel():GetCurrentRoom()
	local spikes = currentRoom:GetGridEntity(67)
	if not spikes then return "" end -- don't display anything if we can't find the spikes!
	local cheatResult = nil
	if spikes and EID.Config["PredictionSanguineBond"] then
		local spikeSeed = currentRoom:GetGridEntity(67):GetRNG():GetSeed()
		spikeSeed = EID:RNGNext(spikeSeed, 5, 9, 7)
		spikeSeed = EID:RNGNext(spikeSeed, 0x01, 0x05, 0x13) -- magic disassembled numbers!
		local nextFloat = EID:SeedToFloat(spikeSeed)
		
		for _,v in ipairs(sanguineResults) do
			if nextFloat < v[1] then cheatResult = v[2] break end
		end
	end

	local resultsDesc = ""

	local lineCount = 0
	-- separate sanguine's description by # or semicolons
	for w in string.gmatch(descObj.Description, "([^#;]+)") do
		-- we only care about groups that contain a percent sign
		if string.find(w,"%%") then
			lineCount = lineCount + 1
			if cheatResult == lineCount then resultsDesc = resultsDesc .. "{{ColorBagComplete}}" end
			resultsDesc = resultsDesc .. w .. "#"
		end
	end
	return resultsDesc
end

function EID:getHoldMapDescription(player, checkingTwin)
	-- Starting Blacklist: Recall, Hold
	blacklist = { ["5.100.714"] = true, ["5.100.715"] = true, }
	holdMapDesc = ""

	level = game:GetLevel()
	currentRoom = level:GetCurrentRoom()
	currentPlayer = player
	
	-- TODO:
	-- D1, crooked penny cheats. 404/liberty cap/etc. "what item is it"
	-- (Zodiac and Modeling Clay have functions for it?)
	-- pandora's box? it shows the whole desc which is kinda useful but too big
	-- Void's absorbed items list
	-- D Infinity current dice; track our Drop presses and resync it each time D Infinity is used by watching for the next dice effect triggered (Predict its next dice in AB+?)
	
	-- Tainted ??? Poop Descriptions
	if REPENTANCE and EID.Config["ItemReminderShowPoopDesc"] > 0 and player:GetPlayerType() == 25 then
		for i = 0, EID.Config["ItemReminderShowPoopDesc"]-1 do
			local poopInfo = EID:getDescriptionEntry("poopSpells")
			local nextPoop = player:GetPoopSpell(i)
			append("{{PoopSpell" .. nextPoop .. "}}", poopInfo[nextPoop][1], poopInfo[nextPoop][2])
		end
	end

	-- Metronome result
	if player:HasCollectible(CollectibleType.COLLECTIBLE_METRONOME) and EID.Config["ItemReminderShowRNGCheats"] then
		blacklist["5.100.488"] = true
		append("{{Collectible488}}", EID:getObjectName(5,100,488) .. EID:getDescriptionEntry("HoldMapHeader"), EID:MetronomePrediction())
	end

	-- Teleport! location
	if player:HasCollectible(CollectibleType.COLLECTIBLE_TELEPORT) and EID.Config["ItemReminderShowRNGCheats"] then
		blacklist["5.100.44"] = true
		teleport1Prediction()
	end
	
	-- Teleport 2.0 location
	if player:HasCollectible(CollectibleType.COLLECTIBLE_TELEPORT_2) and not EID.isMirrorRoom then
		blacklist["5.100.419"] = true
		teleport2Prediction()
	end
	
	-- Recently Acquired Item Descriptions
	if EID.Config["ItemReminderShowRecentItem"] > 0 then
		local printedItems = 0
		local playerNum = EID:getPlayerID(player)
		if EID.RecentlyTouchedItems[playerNum] then
			for i = #EID.RecentlyTouchedItems[playerNum], 1, -1 do
				if printedItems >= EID.Config["ItemReminderShowRecentItem"] then break end
				printedItems = printedItems + 1
				local recentID = EID.RecentlyTouchedItems[playerNum][i] % 4294967296
				addObjectDesc(5, 100, recentID)
			end
		end
	end
	
	-- Active Item Descriptions
	if EID.Config["ItemReminderShowActiveDesc"] > 0 then
		for i = 0, EID.Config["ItemReminderShowActiveDesc"]-1 do
			local heldActive = player:GetActiveItem(i) % 4294967296
			if heldActive > 0 then
				addObjectDesc(5, 100, heldActive)
			end
		end
	end
	
	-- Pocket Item Descriptions
	-- Annoying because there's no easy way to just get the info of a slot
	if EID.Config["ItemReminderShowPocketDesc"] > 0 then
		local numPrinted = 0
		-- I don't think we can actually know what slot the player is on, so, save these to display (if they exist) for when Card and Pill in a slot are both 0, to attempt to always show them in slot order
		local dicePrinted = false
		local diceBag = REPENTANCE and player:GetActiveItem(3) or 0
		local pocketPrinted = false
		local pocketActive = REPENTANCE and player:GetActiveItem(2) or 0
		for i = 0, EID.Config["ItemReminderShowPocketDesc"]-1 do
			local heldCard = player:GetCard(i)
			local heldPill = player:GetPill(i)
			if heldCard > 0 then
				addObjectDesc(5, 300, heldCard)
			elseif heldPill > 0 then
				-- Check if our held pill is identified
				EID.pillPlayer = player
				local identified = game:GetItemPool():IsPillIdentified(heldPill)
				if REPENTANCE and heldPill % PillColor.PILL_GIANT_FLAG == PillColor.PILL_GOLD then identified = true end
				if (identified or EID.Config["ShowUnidentifiedPillDescriptions"]) then
					addObjectDesc(5, 70, heldPill)
				end
				EID.pillPlayer = nil
			elseif diceBag > 0 and not dicePrinted then
				dicePrinted = true
				addObjectDesc(5, 100, diceBag, "{{Trinket154}}")
			elseif pocketActive > 0 and not pocketPrinted then
				pocketPrinted = true
				addObjectDesc(5, 100, pocketActive)
				-- we'll have to add tainted char specific text for their actives with unique effects for that character!
			end
		end
	end
	
	-- Trinket Descriptions
	if EID.Config["ItemReminderShowTrinketDesc"] > 0 then
		for t = 0, EID.Config["ItemReminderShowTrinketDesc"]-1 do
			local heldTrinket = player:GetTrinket(t)
			if heldTrinket > 0 and not blacklist["5.350." .. heldTrinket] then
				-- Rainbow Worm
				if EID.Config["ItemReminderShowHiddenInfo"] and heldTrinket == 64 then
					blacklist["5.350.64"] = true
					local rainbowWormEffect = rainbowWormEffects[math.floor(game.TimeCounter / 30 / 3) % (REPENTANCE and 10 or 8)]
					addObjectDesc(5, 350, rainbowWormEffect, "{{Trinket64}}")
				-- 404 Error
				-- Unfortunately, includes other temporary trinket givers, such as Glitched Items. We'd need to predict 404's result using RNG to actually know which it specifically is granting
				-- And unfortunately, HasTrinket can't differentiate between real and fake trinkets in AB+
				elseif EID.Config["ItemReminderShowHiddenInfo"] and REPENTANCE and heldTrinket == 75 then
					blacklist["5.350.75"] = true
					-- Don't display Mysterious Paper's 1-frame temporary trinket granting
					local hasPaper = player:HasTrinket(21)
					for i = 1, TrinketType.NUM_TRINKETS - 1 do
						local tempTrinketFound = EID.player:HasTrinket(i, true) ~= EID.player:HasTrinket(i, false)
						if tempTrinketFound and (not mysteriousPaperBlacklist[i] or not hasPaper) then
							addObjectDesc(5, 350, i, "{{Trinket75}}")
						end
					end
				else
					addObjectDesc(5, 350, heldTrinket)
				end
				
			end
		end
	end
	
	--
	
	-- Finally, check the twin player of this controller
	-- If both twins have a desc, show their player icon / name to separate the two descs
	if REPENTANCE and not checkingTwin then
		local twin = player:GetOtherTwin()
		local mainTwinDesc = holdMapDesc
		local otherTwinDesc = ""
		if twin then otherTwinDesc = EID:getHoldMapDescription(twin, true) end
		if otherTwinDesc ~= "" then
			-- Only the other twin had a desc
			if mainTwinDesc == "" then holdMapDesc = otherTwinDesc
			else
				-- Both twins had a desc; merge them with player icon headers
				holdMapDesc = (EID:getIcon("Player"..player:GetPlayerType()) ~= EID.InlineIcons["ERROR"] and "{{Player"..player:GetPlayerType().."}}" or "{{CustomTransformation}}") .. " {{ColorGray}}" .. player:GetName() .. "#" .. mainTwinDesc .. "#"
				holdMapDesc = holdMapDesc .. (EID:getIcon("Player"..twin:GetPlayerType()) ~= EID.InlineIcons["ERROR"] and "{{Player"..twin:GetPlayerType().."}}" or "{{CustomTransformation}}") .. " {{ColorGray}}" .. twin:GetName() .. "#" .. otherTwinDesc
			end
		else
			-- Only the main twin had a desc
			holdMapDesc = mainTwinDesc
		end
	end
	
	return holdMapDesc
end