--[[ 
	https://www.roblox.com/games/86962201967541/Battlegrounds-test
	This script essentially deals with the combat systems, it also allows to scalably insert new styles by adding it in the combatStyles dictionary, 
	should be following the typeCombatStyles. Plus the animations must be placed into ReplicatedStorage.Anims.

	This script relies on client's input which are received from remotes Events. Based on which input, it will fire its correspondant remote event, which each of them
	has linked their specific function (for m1,m2,blocking attacks,skill1,skill2,skill3)

	NOTE: VFX hasn't been implemented yet. And some skills do not have animations, so they won't be executed in the game
]]
-- [SERVICES 
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
-- ]
-- [ Anims,Sounds and VFX. Those are used to automatically refer to their instances without needing to manually add each of them into the script
local Anims = ReplicatedStorage.Anims
local Sounds = ReplicatedStorage.Sounds
local VFX = ReplicatedStorage.VFX
-- ]
local combatStyles = {
	--["??"] = {
		--	Stats = {},
		--	Animations = {},
		--	VFX = {},
		--	Sounds = {},
		--},
	Boxing = {
		Stats = {
			m1 = {dmg = 7, cd = 0.5, comboCD = 3, guardBreak = false, HitboxSize = Vector3.new(4,4,4), KnockBack = 75, CombatSpeed = 3, WalkSpeed = 6},
			m2 = {dmg = 12, cd = 3, guardBreak = true, HitboxSize = Vector3.new(4,4,4), KnockBack = 75, CombatSpeed = 3, WalkSpeed = 6},
			Skill1 = {dmg = 5, cd = 5, guardBreak = false, HitboxSize = Vector3.new(4,4,4), Knockback = nil, CombatSpeed = 4, WalkSpeed = 6},
			Skill2 = {dmg = 10, cd = 15, guardBreak = false, HitboxSize = Vector3.new(4,4,4), Knockback = nil, CombatSpeed = 4, WalkSpeed = 6},
			Skill3 = {dmg = 12, cd = 25, guardBreak = true, HitboxSize = Vector3.new(4,4,4), Knockback = nil, CombatSpeed = 4, WalkSpeed = 6},
			block = {WalkSpeed = 6},
			stun = {stunTime = 0.65,enemyWalkSpeed = 6}
		},
	} :: typeCombatStyles,
	Karate = {
		Stats = {
			m1 = {dmg = 10, cd = 0.85, comboCD = 3, guardBreak = false, HitboxSize = Vector3.new(4,4,4.75), KnockBack = 75, CombatSpeed = 1, WalkSpeed = 6},
			m2 = {dmg = 12, cd = 3, guardBreak = true, HitboxSize = Vector3.new(4,4,4.75), KnockBack = 75, CombatSpeed = 1.25, WalkSpeed = 6},
			Skill1 = {dmg = 5, cd = 5, guardBreak = false, HitboxSize = Vector3.new(4,4,4.75), Knockback = nil, CombatSpeed = 1.25, WalkSpeed = 6},
			Skill2 = {dmg = 10, cd = 15, guardBreak = false, HitboxSize = Vector3.new(4,4,4.75), Knockback = nil, CombatSpeed = 1.25, WalkSpeed = 6},
			Skill3 = {dmg = 12, cd = 25, guardBreak = true, HitboxSize = Vector3.new(4,4,4.75), Knockback = nil, CombatSpeed = 1.25, WalkSpeed = 6},
			block = {WalkSpeed = 6},
			stun = {stunTime = 0.85,enemyWalkSpeed = 6}
		},
	} :: typeCombatStyles,
	
	PlayerStatus = {},
	AnimationsTable = {},
	SoundsTable = {},
}
combatStyles.__index = combatStyles

type typeCombatStyles = {
	Stats: { [string]: number },
	Animations: { [string]: string },
	VFX: { [string]: any },
	Sounds: { [string]: Sound? },
}

-- [ VARIABLES
local cdChangeStyle = 15
local debounceChangeStyle = {}
-- ]

-- [ REMOTE EVENTS
local Events = ReplicatedStorage.Events
local m1Event:RemoteEvent = Events.m1
local m2Event:RemoteEvent = Events.m2
local blockEvent:RemoteEvent = Events.block
local skillEvent = {
	Skill1 = Events.Skill1,
	Skill2 = Events.Skill2,
	Skill3 = Events.Skill3,
}
local changeStyleEvent = Events.changeStyle
local getFightingStylesEvent = Events.getFightingStyles
local canDashEvent = Events.canDash -- this event is fired form server to client
local canRunEvent = Events.canRun -- this as well
-- ]
-- [ COSTRUCTOR, applied to every player. Deals with his combat variables
function combatStyles:new(plr,styleName)
	local styleData = combatStyles[styleName]
	if not styleData then return nil end

	local self = setmetatable({}, combatStyles)

	self.PlayerStatus[plr] = {
		StyleName = styleName,
		Parameters = {
			canHit = true,
			canM2 = true,
			canSkill1 = true,
			canSkill2 = true,
			canSkill3 = true,
			isHitting = false,
			isBeingHit = false,
			isBlocking = false,
			isStunned = false,
			isDashing = false,
			inCombat = false,
			ComboIndex = 0,
			LastM1Time = 0,
			StunTick = 0,
			LastWalkSpeed = 16,
		}
	}
	self.AnimationsTable[plr] = {}
	self.SoundsTable[plr] = {}
	
	return self.PlayerStatus[plr]
end
--]

function combatStyles:checkStyle(plr)
	local plrStatus = self.PlayerStatus[plr]
	if plrStatus then
		local style = plrStatus.StyleName
		if style then
			local findStyle = combatStyles[style]
			if findStyle then
				return findStyle
			end
		end
	end
end

local function checksParameters(plr)
	local plrStatus = combatStyles.PlayerStatus[plr]
	local Parameters = plrStatus.Parameters
	if Parameters.canHit and not Parameters.isBlocking and not Parameters.isStunned then
		return true
	end
		return false
end

function combatStyles:createSounds(plr)
	local style = combatStyles:checkStyle(plr)
	if style then
		local char = plr.Character
		local soundStyle = style.Sounds
		if soundStyle then
			for name,sound in soundStyle do
				local newSound = sound:Clone()
				newSound.Parent = char.HumanoidRootPart
				newSound.Name = name 
				self.SoundsTable[plr][name] = newSound
			end
			print(plr.Name,self.SoundsTable[plr])
		end
	end
end
--[[
	CREATE ANIMATIONS WHENEVER THE CHARACTER RESPAWNS, OR WHEN THE PLAYER CHANGES STYLE. LOADS THE ANIMATIONS INTO A TABLE, SO IT'S EASIER TO REFER TO THE ANIMATION
  and also it's easier to stop/play/destroy the animations since it saves its instance  into the table.
]]
function combatStyles:createAnim(plr)
	local style = combatStyles:checkStyle(plr)
	if style then
		local char = plr.Character
		local humanoid = char:FindFirstChild("Humanoid")
		local animator = humanoid.Animator
			
		for name,anim in style.Animations do
			if anim then
				local animationObj = Instance.new("Animation")
				animationObj.Parent = animator
				animationObj.AnimationId = anim.AnimationId
				animationObj.Name = name
				
				local animTrack:AnimationTrack = animator:LoadAnimation(animationObj)
				
				if not self.AnimationsTable[plr][name] then
					self.AnimationsTable[plr][name] = animTrack
				end
			end
	end	
	print(plr.Name,self.AnimationsTable[plr])
end
-- Plays the animation
local function loadAnimation(plr,animationToPlay,atkType,playAnim,keyFrame)
	local char = plr.Character
	if not char then return nil end
	
	local hum = char:FindFirstChild("Humanoid")
	local animator = hum and hum:FindFirstChild("Animator")
	if not animator then return nil end		
	local style = combatStyles:checkStyle(plr)
	local plrAnims = combatStyles.AnimationsTable[plr]
		
	local params = combatStyles.PlayerStatus[plr].Parameters
	if plrAnims and plrAnims[animationToPlay] then
		local animTrack:AnimationTrack = plrAnims[animationToPlay]
		if playAnim then
			local combatSpeed = nil
			if atkType then
				combatSpeed = style.Stats[atkType].CombatSpeed
			end			
			if keyFrame then
				animTrack:GetMarkerReachedSignal(keyFrame):Once(function()
					local dmg = style.Stats[atkType].dmg
					local guardBreak = style.Stats[atkType].guardBreak				
					combatStyles:Hitboxes(plr,dmg,atkType,guardBreak)
				end)
			end
			if combatSpeed then
				animTrack:Play(nil,nil,combatSpeed)
			else
				animTrack:Play()
			end

			if atkType == "m1" or atkType == "m2" or atkType == "Skill1" or atkType == "Skill2" or atkType == "Skill3" then
				animTrack.Stopped:Once(function()
					if combatStyles.PlayerStatus[plr] then
						combatStyles.PlayerStatus[plr].Parameters.isHitting = false
						hum.WalkSpeed = params.LastWalkSpeed
					end
				end)
			end
			return animTrack
	end
	return nil
end
-- USED TO ALLOW A PLAYER TO CHANGE HIS STYLE	
local function changeAllStyleAnimationID(plr,styleToChange)
	local findStyle = combatStyles[styleToChange]
	local plrAnimations = combatStyles.AnimationsTable[plr]
	local plrStatus = combatStyles.PlayerStatus[plr]
	local plrSound = combatStyles.SoundsTable[plr]
	
	if not findStyle or not plrAnimations or not plrStatus or debounceChangeStyle[plr] then return end

	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChild("Humanoid")
	local animator = hum and hum:FindFirstChild("Animator")

	if not animator then warn("No animator in Change Style") return end

	for name, track in pairs(plrAnimations) do
		track:Stop()
		track:Destroy()
	end

	table.clear(plrAnimations)
	plrStatus.StyleName = styleToChange

	for name, animObj in pairs(findStyle.Animations) do
		if animObj then
			local animTrack = animator:LoadAnimation(animObj)
			plrAnimations[name] = animTrack
		end
	end
	
	if plrAnimations["stance"] then
		plrAnimations["stance"]:Play()
	end	
	
	for i,sound in pairs(plrSound) do
		if sound then
			sound:Stop()
			sound.SoundId = findStyle.Sounds[i].SoundId
		end
	end
	
	debounceChangeStyle[plr] = true
	task.delay(cdChangeStyle,function()
		debounceChangeStyle[plr] = false
	end)
end	

local function stopAnim(plr,anim:string)
	local plrAnims = combatStyles.AnimationsTable[plr]
	if anim and plrAnims and plrAnims[anim] then
		local animTrack:AnimationTrack = plrAnims[anim]
		if animTrack then
			animTrack:Stop()
		end
	end
end	

-- STYLE FUNCTIONS, it checks if the player can hit, deals with his combo system and plays the animation and fire the hitbox
function combatStyles:HitM1(plr)
	local char = plr.Character
	local plrStatus = self.PlayerStatus[plr]
	if plrStatus and char then
		local hum = char:FindFirstChild("Humanoid")
		local style = plrStatus.StyleName
		local parameters = plrStatus.Parameters
		
		local currentTime = tick()
		
		if currentTime - parameters.LastM1Time >= 5 then
			parameters.ComboIndex = 0
		end
		
		if style and checksParameters(plr) and not parameters.isHitting  then
			local plrStyleAnim = self[style].Animations
			local cdM1 = self[style].Stats.m1.cd
			local comboCD = self[style].Stats.m1.comboCD
			local slowDown = combatStyles[style].Stats.m1.WalkSpeed
			
			parameters.ComboIndex =  (parameters.ComboIndex%4)+1
			
			hum.WalkSpeed = slowDown
			parameters.canHit = false
			parameters.isHitting = true
			parameters.LastM1Time = tick()
			
			local m1Animation = "m1_"..parameters.ComboIndex
			loadAnimation(plr,m1Animation,"m1",true,"Hit")
			combatStyles:PlaySound(plr,"m1Swing")
			
			if parameters.ComboIndex == 4 then
				m1Event:FireClient(plr,comboCD)
				parameters.canHit = false
				task.delay(comboCD,function()
					parameters.canHit = true
				end)
				return
			else
				m1Event:FireClient(plr,cdM1)
			end
			
			task.delay(cdM1,function()
				parameters.canHit = true
			end)
		end
	end
end

function combatStyles:HitM2(plr)
	local char = plr.Character
	local plrStatus = self.PlayerStatus[plr]
	if plrStatus and char then
		local style = plrStatus.StyleName
		local parameters = plrStatus.Parameters
		
		local hum = char:FindFirstChild("Humanoid")
		if style and parameters.canM2 and not parameters.isBlocking and not parameters.isHitting and not parameters.isStunned then
			local cdM2 = combatStyles[style].Stats.m2.cd
			local slowDown = combatStyles[style].Stats.m2.WalkSpeed
			
			parameters.canM2 = false
			parameters.isHitting = true
			hum.WalkSpeed = slowDown
			
			m2Event:FireClient(plr,cdM2)
			loadAnimation(plr,"m2","m2",true,"Hit")
			combatStyles:PlaySound(plr,"m2Swing")

			task.delay(cdM2,function()
				parameters.canM2 = true
			end)
		end
	end
end
-- block, it checks if the player can block, plays the animation
function combatStyles:Block(plr,isPressingKey)
	local plrStatus = self.PlayerStatus[plr]
	local params = plrStatus.Parameters
	
	local style = combatStyles:checkStyle(plr)
	local char = plr.Character
	local hum = char:FindFirstChild("Humanoid")
	
	if params.isHitting and isPressingKey and params.isStunned then return end
	
	params.isBlocking = isPressingKey
	if isPressingKey then
		loadAnimation(plr,"block",nil,true)
		canRunEvent:FireClient(plr,false)
		hum.WalkSpeed = style.Stats.block.WalkSpeed
	else
		stopAnim(plr,"block")
		canRunEvent:FireClient(plr,true)
		hum.WalkSpeed = params.LastWalkSpeed
	end
end

local function executeSkill(plr,self,skill)
	local plrStatus = self.PlayerStatus[plr]
	if plrStatus then
		local style = plrStatus.StyleName
		local parameters = plrStatus.Parameters
		if style and not parameters.isBlocking and not parameters.isHitting  and parameters["can"..skill] and not parameters.isStunned then
			local cdSkill = combatStyles[style].Stats[skill].cd

			parameters["can"..skill] = false
			parameters.isHitting = true
			local targetEvent = skillEvent[skill]
			if targetEvent then
				targetEvent:FireClient(plr, cdSkill)
			end
			loadAnimation(plr,skill,skill,true,"Hit")
			
			task.delay(cdSkill,function()
				parameters["can"..skill] =  true
			end)
		end
	end
end

function combatStyles:Skill1(plr)
	executeSkill(plr,self,"Skill1")
end

function combatStyles:Skill2(plr)
	executeSkill(plr,self,"Skill2")
end

function combatStyles:Skill3(plr)
	executeSkill(plr,self,"Skill3")
end

-- EVENTS THAT GET THE INPUT FROM THE CLIENT AND FIRE THE FUNCTION BASED ON THE INPUT
m1Event.OnServerEvent:Connect(function(plr)
	combatStyles:HitM1(plr)
end)

m2Event.OnServerEvent:Connect(function(plr)
	combatStyles:HitM2(plr)
end)

blockEvent.OnServerEvent:Connect(function(plr,isPressingKey)
	combatStyles:Block(plr,isPressingKey)
end)

skillEvent.Skill1.OnServerEvent:Connect(function(plr)
	combatStyles:Skill1(plr)
end)

skillEvent.Skill2.OnServerEvent:Connect(function(plr)
	combatStyles:Skill2(plr)
end)

skillEvent.Skill3.OnServerEvent:Connect(function(plr)
	combatStyles:Skill3(plr)
end)

getFightingStylesEvent.OnServerInvoke = function()
	return combatStyles:getCurrentFightingStyles()
end

changeStyleEvent.OnServerEvent:Connect(function(plr,style)
	changeAllStyleAnimationID(plr,style)
end)

-- create an attachment and force to the humanoidRootPart, and applies the force on the character.
local function applyForceToChar(victim,hittingPlr,knockback)
	local hrp = hittingPlr.Character.HumanoidRootPart
	
	for _, child in victim.HRP:GetChildren() do
		if child.Name == "KnockbackForce" or child.Name == "KnockbackAttachment" then
			child:Destroy()
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	attachment.Parent = victim.HRP

	local linVel = Instance.new("LinearVelocity")
	linVel.Name = "KnockbackForce"
	linVel.Attachment0 = attachment
	linVel.MaxForce = 2500000

	local dir = (hrp.CFrame.LookVector + Vector3.new(0, 0.25, 0)).Unit
	linVel.VectorVelocity = dir * (knockback)
	linVel.Parent = victim.HRP

	local oldSpeed = victim.Hum.WalkSpeed
	victim.Hum.WalkSpeed = 0

	Debris:AddItem(linVel, 0.2)
	Debris:AddItem(attachment, 0.2)

	task.delay(0.2, function()
		if victim.Hum then
			victim.Hum.WalkSpeed = oldSpeed
		end
	end)
end

-- stun the player based on the style, make him to be slow and prevent the player from having multiple stuns at the same time
local function stunPlayer(stunTime, enemyWalkSpeed, plrToStun)
	local status = combatStyles.PlayerStatus[plrToStun]
	if not status then return end

	local char = plrToStun.Character
	local hum = char and char:FindFirstChild("Humanoid")
	if not hum then return end

	status.Parameters.StunTick += 1
	local currentTick = status.Parameters.StunTick

	status.Parameters.isStunned = true
	hum.WalkSpeed = enemyWalkSpeed
	canDashEvent:FireClient(plrToStun, false)
	canRunEvent:FireClient(plrToStun, false)

	task.delay(stunTime, function()
		if status.Parameters.StunTick == currentTick then
			status.Parameters.isStunned = false
			hum.WalkSpeed = status.Parameters.LastWalkSpeed
			canDashEvent:FireClient(plrToStun, true)
			canRunEvent:FireClient(plrToStun, true)
		end
	end)
end

-- fires hitbox and damage the player, break guard if the attack guard breaks, deals with the blocking system. If the enemy is behind the blocking player, the damage will happen. Then also applies force if needed
function combatStyles:Hitboxes(plr, dmg, currentAtk, isAtkGuardBreaking)
	local style = combatStyles:checkStyle(plr)
	local char = plr.Character
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local hitboxPos = (hrp.CFrame - hrp.Position + (hrp.Position + hrp.CFrame.LookVector * 1.5))
	local hitboxSize = style.Stats[currentAtk]["HitboxSize"]
	local knockback = style.Stats[currentAtk]["KnockBack"]

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char}

	local hitbox = workspace:GetPartBoundsInBox(hitboxPos, hitboxSize, params)
	local hitHumanoids = {}
	
	local plrParams = self.PlayerStatus[plr].Parameters
	
	for i, part in hitbox do
		local enemyModel = part:FindFirstAncestorOfClass("Model")
		if not enemyModel then continue end
		local enemy = {
			Hum = enemyModel:FindFirstChild("Humanoid"),
			HRP = enemyModel:FindFirstChild("HumanoidRootPart"),
			Plr = Players:GetPlayerFromCharacter(enemyModel),
			Params = nil,
		}
		if enemy.Plr then
			enemy.Params = self.PlayerStatus[enemy.Plr].Parameters
		end
		if enemy.Hum and not hitHumanoids[enemy.Hum] and enemy.Hum.Health > 0 then
			local isBlocking = false
			hitHumanoids[enemy.Hum] = true
			if enemy.Params and enemy.Params.isBlocking then
				isBlocking = enemy.Params.isBlocking
			end
			
			if isBlocking and not isAtkGuardBreaking then
				local attackerLookVector = hrp.CFrame.LookVector
				local victimLookVector = enemy.HRP.CFrame.LookVector
				local dotProduct = attackerLookVector:Dot(victimLookVector)
				
				local isBehind = dotProduct>0.2
				
				if not isBehind then
					combatStyles:PlaySound(enemy.Plr, "blockingSound")
					continue
				elseif isBehind or isAtkGuardBreaking then
					if enemy and enemy.Params then
						--print("removed block")
						enemy.Params.isBlocking = false
						stopAnim(enemy.Plr,"block")
					end
				end
			end
			
			enemy.Hum:TakeDamage(dmg)
			self:PlaySound(plr, "punchSound") 
			
			local isFinalHit = (currentAtk == "m1" and plrParams.ComboIndex == 4)
			local isM2 = (currentAtk == "m2") -- or currentAtk:match("skill")
			
			if enemy.HRP and isFinalHit or isM2 then
				applyForceToChar(enemy,plr,knockback)
			end
			
			if enemy.Plr then
				stunPlayer(style.Stats.stun.stunTime, style.Stats.stun.enemyWalkSpeed,enemy.Plr)
			end
		end
	end
end

function combatStyles:PlaySound(plr,soundToPlay:string)
	local plrSounds = self.SoundsTable[plr]
	
	local sound = plrSounds[soundToPlay]
	if plrSounds and sound then
			sound:Play()
	end
end
-- used to retrieve all the fighting style. This was done because there's an interface that allows the player to swap styles. In this way it's automatic, the server tells all the existing styles once
function combatStyles:getCurrentFightingStyles()
	local fightingStyles = {}
	for styleName, data in pairs(self) do
		if type(data) == "table" and data.Stats then
			table.insert(fightingStyles, styleName)
		end
	end
	return fightingStyles
end

-- puts all the animations, sounds and vfx INTO the each fighting style
local function automaticInserterOf_Anims_Sounds_VFX()
	for style, data in pairs(combatStyles) do
		if type(data) == "table" and data.Stats then
			data.Animations = data.Animations or {}
			data.Sounds = data.Sounds or {}
			data.VFX = data.VFX or {}

			local styleAnims = Anims:FindFirstChild(style)
			if styleAnims then
				for _, anim in ipairs(styleAnims:GetChildren()) do
					data.Animations[anim.Name] = anim
				end
			end
			
			local styleSounds = Sounds:FindFirstChild(style)
			if styleSounds then
				for _, sound in ipairs(styleSounds:GetChildren()) do
					data.Sounds[sound.Name] = sound
				end
			end

			local styleVFX = VFX:FindFirstChild(style)
			if styleVFX then
				for _, vfx in ipairs(styleVFX:GetChildren()) do
					data.VFX[vfx.Name] = vfx
				end
			end
		end
	end
end

function combatStyles.Start()
	
	automaticInserterOf_Anims_Sounds_VFX()
	
	-- everytime a player joinds, he gets boxing, his stance is played and all the animations and sounds are created into him and into his tables and some parameters are set.
	Players.PlayerAdded:Connect(function(plr)
		combatStyles:new(plr,"Boxing")
		plr.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid")
			
			local status = combatStyles.PlayerStatus[plr]
			if status then
				status.Parameters.isHitting = false
				status.Parameters.canHit = true
				status.Parameters.LastWalkSpeed = hum.WalkSpeed
			end
			
			combatStyles.AnimationsTable[plr] = {}
			combatStyles.SoundsTable[plr] = {}
			
			combatStyles:createAnim(plr)
			combatStyles:createSounds(plr)
			
			local anims = combatStyles.AnimationsTable[plr]
			if anims and anims["stance"] then
				task.delay(5,function() 
					if anims["stance"] then anims["stance"]:Play() end
				end)
			end
			-- done for testing purpose
			if plr.Name == "Player2" then
				combatStyles:Block(plr,true)
			end
		end)
	end)
	-- when a player leave, his status is cleared, prevent from wasting memory
	Players.PlayerRemoving:Connect(function(plr)
		table.clear(combatStyles.PlayerStatus[plr])
		table.clear(combatStyles.AnimationsTable[plr])
		table.clear(combatStyles.SoundsTable[plr])
	end)
end
return combatStyles
