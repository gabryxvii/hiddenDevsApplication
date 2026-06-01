--[[ 
	https://www.roblox.com/games/86962201967541/Battlegrounds-test
	This script essentially deals with the combat systems, it also allows to scalably insert new styles by adding it in the combatStyles dictionary, 
	should be following the typeCombatStyles. Plus the animations must be placed into ReplicatedStorage.Anims.

	This script relies on client's input which are received from remotes Events. Based on which input, it will fire its correspondant remote event, which each of them
	has linked their specific function (for m1,m2,blocking attacks,skill1,skill2,skill3)

	NOTE: VFX hasn't been implemented yet. And some skills do not have animations, so they won't be executed in the game
]]

-- This script is called through a Server Script which calls the function .Start()
-- [SERVICES 
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
-- ]

-- [ Anims,Sounds and VFX. Those are used to automatically refer to their instances without needing to manually add each of them into the script
local Anims = ReplicatedStorage.Anims
local Sounds = ReplicatedStorage.Sounds
local VFX = ReplicatedStorage.VFX
local Events = ReplicatedStorage.Events

local combatStyles = {
	Boxing = {
		Stats = {
			m1 = {dmg = 7, cd = 0.5, comboCD = 3, guardBreak = false, HitboxSize = Vector3.new(4,4,4), KnockBack = 75, CombatSpeed = 3, WalkSpeed = 6},
			m2 = {dmg = 12, cd = 3, guardBreak = true, HitboxSize = Vector3.new(4,4,4), KnockBack = 75, CombatSpeed = 3, WalkSpeed = 6},
			Skill1 = {dmg = 5, cd = 5, guardBreak = false, HitboxSize = Vector3.new(4,4,4), KnockBack = 0, CombatSpeed = 4, WalkSpeed = 6},
			Skill2 = {dmg = 10, cd = 15, guardBreak = false, HitboxSize = Vector3.new(4,4,4), KnockBack = 0, CombatSpeed = 4, WalkSpeed = 6},
			Skill3 = {dmg = 12, cd = 25, guardBreak = true, HitboxSize = Vector3.new(4,4,4), KnockBack = 0, CombatSpeed = 4, WalkSpeed = 6},
			block = {WalkSpeed = 6},
			stun = {stunTime = 0.65, enemyWalkSpeed = 6}
		},
		Animations = {},
		Sounds = {},
		VFX = {},
	} ::typeCombatStyles,
	Karate = {
		Stats = {
			m1 = {dmg = 10, cd = 0.85, comboCD = 3, guardBreak = false, HitboxSize = Vector3.new(4,4,4.75), KnockBack = 75, CombatSpeed = 1, WalkSpeed = 6},
			m2 = {dmg = 12, cd = 3, guardBreak = true, HitboxSize = Vector3.new(4,4,4.75), KnockBack = 75, CombatSpeed = 1.25, WalkSpeed = 6},
			Skill1 = {dmg = 5, cd = 5, guardBreak = false, HitboxSize = Vector3.new(4,4,4.75), KnockBack = 0, CombatSpeed = 1.25, WalkSpeed = 6},
			Skill2 = {dmg = 10, cd = 15, guardBreak = false, HitboxSize = Vector3.new(4,4,4.75), KnockBack = 0, CombatSpeed = 1.25, WalkSpeed = 6},
			Skill3 = {dmg = 12, cd = 25, guardBreak = true, HitboxSize = Vector3.new(4,4,4.75), KnockBack = 0, CombatSpeed = 1.25, WalkSpeed = 6},
			block = {WalkSpeed = 6},
			stun = {stunTime = 0.85, enemyWalkSpeed = 6}
		},
		Animations = {},
		Sounds = {},
		VFX = {},
	} ::typeCombatStyles,
}

combatStyles.__index = combatStyles

type typeCombatStyles = {
	Stats: { [string]: number },
	Animations: { [string]: string },
	VFX: { [string]: any },
	Sounds: { [string]: Sound? },
}

-- [ VARIABLES ]
local allPlayers = {}
local cdChangeStyle = 15
local debounceChangeStyle = {}

-- [ REMOTE EVENTS ]
local m1Event = Events.m1
local m2Event = Events.m2
local blockEvent = Events.block
local skillEvents = {
	Skill1 = Events.Skill1,
	Skill2 = Events.Skill2,
	Skill3 = Events.Skill3,
}

--[[
	It grabs the animations and sounds from the ReplicatedStorage insert the animations and sounds into the combatStyle table.
]]
local function automaticInserterOf_Anims_Sounds_VFX()
	for styleName, data in pairs(combatStyles) do
		if type(data) ~= "table" or not data.Stats then continue end

		local folders = {Animations = Anims, Sounds = Sounds, VFX = VFX}
		for key, rootFolder in pairs(folders) do
			local styleFolder = rootFolder:FindFirstChild(styleName)
			if styleFolder then
				for _, asset in ipairs(styleFolder:GetChildren()) do
					data[key][asset.Name] = asset
				end
			end
		end
	end
end

--[[ [ CONSTRUCTOR ]  
	
	An object is created for the player once the function is called and 
	it sets player's data and loads animation and sounds.
	
]]
function combatStyles.new(plr, styleName)
	local styleData = combatStyles[styleName]
	if not styleData then return nil end

	local self = setmetatable({}, combatStyles)

	self.Plr = plr
	self.Char = plr.Character or plr.CharacterAdded:Wait()
	self.Hum = self.Char:WaitForChild("Humanoid")
	self.Root = self.Char:WaitForChild("HumanoidRootPart")

	self.AnimsTable = {}
	self.SoundsTable_ = {}
	self.Style = styleName
	--self.State = "Idle"

	self.canM1 = true
	self.canM2 = true
	self.canSkill1 = true
	self.canSkill2 = true
	self.canSkill3 = true
	self.isHitting = false
	self.isBlocking = false
	self.isStunned = false
	self.isDashing = false
	self.inCombat = false
	self.ComboIndex = 0
	self.LastM1Time = 0
	self.StunTick = 0
	self.LastWalkSpeed = 16

	self:loadAnimations()
	self:createSounds()

	allPlayers[plr] = self
	return self
end

-- [ GET/SET ]
function combatStyles:Get(attribute: string)
	return self[attribute]
end

function combatStyles:Set(attribute: string, value)
	if self[attribute] ~= nil then
		self[attribute] = value
	end
end

-- [ ASSET LOADING ]
--[[
	combatStyles:loadAnimations()
	 We retrieve the player's style and and Animator inside of his Humanoid.
	 Then we make a foor loop to into the Style Animations and create and index into the player object which has the animation name and the animationTrack as value
	 making it easier to stop or play the animation.
	combatStyles:createSounds()
	 Same thing was done for the sounds, with the only difference that the sound is cloned into the HumanoidRootPart, so the sound can start from there and not be heard throught the whole map.
]]
function combatStyles:loadAnimations()
	local styleData = combatStyles[self.Style]
	local animator = self.Hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", self.Hum)

	for name, anim in pairs(styleData.Animations) do
		self.AnimsTable[name] = animator:LoadAnimation(anim)
	end
end

function combatStyles:createSounds()
	local styleData = combatStyles[self.Style]
	for name, soundTemplate in pairs(styleData.Sounds) do
		local s = soundTemplate:Clone()
		s.Parent = self.Root
		self.SoundsTable_[name] = s
	end
end

-- [ Anim/Sound/LOGIC METHODS ]

--[[
	--
	combatStyles:PlayAnim()
		Since we're storing animations into a table which is inside player's object, we search the animation name through the table
		if it exist we get the animation speed for the specific action (m1 or m2,skill etc...). If the keyframe argument is passed
		then we use :GetMarkerReachedSignal() and everytime the animation event is reached we perform the hitbox.
		Then we play the animation, if we pass atkType, once the animation stops it sets some parameters and slow down the playerr
	 combatStyles:StopAnim()
	 	We search the animation into the table which is inside the player's object. If it exist it stops.
	  combatStyles:PlaySound()
	  	Similar again, it searches the sounds into sound table inside player's object. If it exist it stops
	--
]]

function combatStyles:PlayAnim(name, atkType,keyFrame)
	local track = self.AnimsTable[name]
	if not track then return end

	local styleData = combatStyles[self.Style]
	local speed = atkType and styleData.Stats[atkType].CombatSpeed or 1

	if keyFrame then
		track:GetMarkerReachedSignal(keyFrame):Once(function()
			local stats = styleData.Stats[atkType]
			self:PerformHitbox(stats.dmg, atkType, stats.guardBreak)
		end)
	end

	track:Play(0.1, 1, speed)

	if atkType then
		track.Stopped:Once(function()
			self.isHitting = false
			self.Hum.WalkSpeed = self.LastWalkSpeed
		end)
	end
	return track
end

function combatStyles:StopAnim(name)
	if self.AnimsTable[name] then
		self.AnimsTable[name]:Stop()
	end
end

function combatStyles:PlaySound(name)
	if self.SoundsTable_[name] then
		self.SoundsTable_[name]:Play()
	end
end

--[[
	--
	combatStyles:PerformHitbox()
	it retrieves the attack and get the hitbox size, and calculate the position based on the root position and the hitbox size.
	Then OverlapParams are set, for the hitbox, where the character itself is excluded to not hit himself and then the hitbox is casted through :GetPartsBoundInBox()
	A table called hitHum is created to store the hit humanoids and avoid multiple hits.
	for each part detected it checks if the hit part has a model as parent and if it contains a Humanoid and that humanoid has not already been damaged, in that case it means we can damage it.
	We set the index as the humanoid and then we check it true, then we check if the target is blocking, if the hit comes from behind (we detect it through the dot product) the damage is applied, the sounds is played
	and the enemy is stunned. Knockback is applied based on the knockback value in the style data and if it's m2 or last m1 hit.
]]
function combatStyles:PerformHitbox(dmg, atkType, isGuardBreak)
	local statistics = combatStyles[self.Style].Stats[atkType]
	local size = statistics.HitboxSize
	local pos = self.Root.CFrame * CFrame.new(0, 0, -size.Z/2)

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = {self.Char}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local hits = workspace:GetPartBoundsInBox(pos, size, params)
	local hitHum = {}

	for _, part in ipairs(hits) do
		local model = part:FindFirstAncestorOfClass("Model")
		local targetHum = model and model:FindFirstChild("Humanoid")

		if targetHum and not hitHum[targetHum] and targetHum.Health > 0 then
			hitHum[targetHum] = true
			local targetPlr = Players:GetPlayerFromCharacter(model)
			local targetObj = targetPlr and allPlayers[targetPlr]

			if targetObj and targetObj.isBlocking and not isGuardBreak then
				local dot = self.Root.CFrame.LookVector:Dot(targetObj.Root.CFrame.LookVector)
				if dot < 0.2 then -- Not behind
					targetObj:PlaySound("blockingSound")
					continue
				end
				targetObj:StopAnim("block")
				targetObj.isBlocking = false
			end

			targetHum:TakeDamage(dmg)
			self:PlaySound("punchSound")

			if targetObj then
				targetObj:Stun(combatStyles[self.Style].Stats.stun)
			end

			if statistics.KnockBack > 0 and (atkType == "m2" or (atkType == "m1" and self.ComboIndex == 4)) then
				self:ApplyKnockback(model:FindFirstChild("HumanoidRootPart"), statistics.KnockBack)
			end
		end
	end
end

--[[
	combatStyles:Stun()
	we stun the player based on the stunStats in each attack. we use StunTuick and current to prevent from multiple hitstun stacking.
	then we slow down the player and use task.delay to unstun him after the stunTime is over
]]
function combatStyles:Stun(stunStats)
	self.StunTick += 1
	local current = self.StunTick
	self.isStunned = true
	self.Hum.WalkSpeed = stunStats.enemyWalkSpeed

	Events.canDash:FireClient(self.Plr, false)
	Events.canRun:FireClient(self.Plr, false)

	task.delay(stunStats.stunTime, function()
		if self.StunTick == current then
			self.isStunned = false
			self.Hum.WalkSpeed = self.LastWalkSpeed
			Events.canDash:FireClient(self.Plr, true)
			Events.canRun:FireClient(self.Plr, true)
		end
	end)
end

--[[
	combatStyles:ApplyKnockback()
	we create an attachment and a linear Velocity istance into the humanoidRootPart, then we set maxForce and we link the linearVelocity to the attachment. Lastly we set the VecotrVelocity making the enemy to
	get pushed based on where the attacker is loocking at. I sum the lookvector to a vector to make the enemy to get pushed up slightly so the floor friction isn't involved and doesn't mess up
	and then multiply it by the attack's knockback
	
]]
function combatStyles:ApplyKnockback(targetRoot, force)
	if not targetRoot then return end
	local att = Instance.new("Attachment", targetRoot)
	local vel = Instance.new("LinearVelocity", targetRoot)
	vel.MaxForce = 2500000
	vel.Attachment0 = att
	vel.VectorVelocity = (self.Root.CFrame.LookVector + Vector3.new(0, 0.25, 0)).Unit * force
	vel.Parent = targetRoot

	Debris:AddItem(vel, 0.2)
	Debris:AddItem(att, 0.2)
end

-- [ ATTACK METHODS ]

--[[
	combatStyles:M1()
	It checks if the user can M1 and other variables.
	Retrieves the m1 statistics of the player's style. If last time that the player landed a M1 was more than 5 seconds ago, it resets the combo index.
	it calculates the comboIndex and make it not surpass 4. It plays the animation, the :PlayAnim() will call the :PerformHitbox(). Furthermore it plays the sound of the M1 .
	It fires the event to tell the client to show the cooldown in the ui
	It retrieves the cooldown per M1 and uses task.delay and set the canM1 to true after the cd is over.
]]
function combatStyles:M1()
	if not self.canM1 or self.isBlocking or self.isStunned or self.isHitting then return end

	local statistic = combatStyles[self.Style].Stats.m1
	if tick() - self.LastM1Time >= 5 then self.ComboIndex = 0 end

	self.ComboIndex = (self.ComboIndex % 4) + 1
	self.isHitting = true
	self.canM1 = false
	self.LastM1Time = tick()
	self.Hum.WalkSpeed = statistic.WalkSpeed

	self:PlayAnim("m1_"..self.ComboIndex, "m1", "Hit")
	self:PlaySound("m1Swing")

	local cd = (self.ComboIndex == 4) and statistic.comboCD or statistic.cd
	m1Event:FireClient(self.Plr, cd)
	task.delay(cd, function() self.canM1 = true end)
end

--[[
	combatStyles:M2()
	It checks if the user can M1 and other variables.
	Retrieves the m1 statistics of the player's style. 
	It plays the animation, the :PlayAnim() will call the :PerformHitbox(). Furthermore it plays the sound of the M1 .
	It retrieves the cooldown per M1 and uses task.delay and set the canM1 to true after the cd is over.
	It fires the event to tell the client to show the cooldown in the ui
]]

function combatStyles:M2()
	if not self.canM2 or self.isBlocking or self.isStunned or self.isHitting then return end

	local statistic = combatStyles[self.Style].Stats.m2
	self.isHitting = true
	self.canM2 = false
	self.Hum.WalkSpeed = statistic.WalkSpeed

	self:PlayAnim("m2", "m2", "Hit")
	self:PlaySound("m2Swing")

	m2Event:FireClient(self.Plr, statistic.cd)
	task.delay(statistic.cd, function() self.canM2 = true end)
end

--[[ 
	combatStyles:Block()
	It checks if the user can block, then set the isBlocking, if it's true it plays the animation and slows Walkspeed else it stops and unslows Walkspeed. Fires the canRun remoteEvent and passes the opposite of the isBlocking.
	If the player is blocking it won't run. The run is client sided for performance reasons
]]
function combatStyles:Block(isPressing)
	if self.isStunned or (self.isHitting and isPressing) then return end

	local stats = combatStyles[self.Style].Stats.block
	self.isBlocking = isPressing

	if isPressing then
		self:PlayAnim("block", nil)
		self.Hum.WalkSpeed = stats.WalkSpeed
	else
		self:StopAnim("block")
		self.Hum.WalkSpeed = self.LastWalkSpeed
	end
	Events.canRun:FireClient(self.Plr,not self.isBlocking)
end

--[[
	combatStyles:ExecuteSkill()
	detect if the user can do the skill
	it grabs the skill from the combatStyle and get the cooldown,it plays the animation and fire the skillEvent to tell the client to show the cooldown in the ui
	It plays the animation and deals the cooldown, set the canSkill to true after the cd is over
]]

function combatStyles:ExecuteSkill(skill)
	if not self["can"..skill] or self.isBlocking or self.isStunned or self.isHitting then return end

	local statistic = combatStyles[self.Style].Stats[skill]
	self["can"..skill] = false
	self.isHitting = true

	skillEvents[skill]:FireClient(self.Plr, statistic.cd)
	self:PlayAnim(skill, skill, "Hit")

	task.delay(statistic.cd, function() self["can"..skill] = true end)
end

--[[
	combatStyles:ChangeStyle()
	Context: There's a ui in the client to select the style.
	It makes the user to swap combat Styles, all the animations and sound are stopped and replaced by setting the self.Style and recalling the :loadAnimations() and :createSounds()
	Plays the animation statce and deals with the cooldown to prevent the player from spamming the style change.
]]
function combatStyles:ChangeStyle(newStyle)
	if not combatStyles[newStyle] or debounceChangeStyle[self.Plr] then return end

	debounceChangeStyle[self.Plr] = true
	for _, track in pairs(self.AnimsTable) do track:Stop(); track:Destroy() end
	for _, sound in pairs(self.SoundsTable_) do sound:Destroy() end

	table.clear(self.AnimsTable)
	table.clear(self.SoundsTable_)

	self.Style = newStyle
	self:loadAnimations()
	self:createSounds()

	if self.AnimsTable["stance"] then self.AnimsTable["stance"]:Play() end

	task.delay(cdChangeStyle, function() debounceChangeStyle[self.Plr] = false end)
end

-- [ EVENT LISTENERS ] . Pretty simple, they just run the functions whenever from the client, the input is pressed (when the input is pressed the event is fired to the server).
m1Event.OnServerEvent:Connect(function(plr)
	if allPlayers[plr] then allPlayers[plr]:M1() end
end)

m2Event.OnServerEvent:Connect(function(plr)
	if allPlayers[plr] then allPlayers[plr]:M2() end
end)

blockEvent.OnServerEvent:Connect(function(plr, isPressing)
	if allPlayers[plr] then allPlayers[plr]:Block(isPressing) end
end)

for name, event in pairs(skillEvents) do
	event.OnServerEvent:Connect(function(plr)
		if allPlayers[plr] then allPlayers[plr]:ExecuteSkill(name) end
	end)
end

Events.changeStyle.OnServerEvent:Connect(function(plr, style)
	if allPlayers[plr] then allPlayers[plr]:ChangeStyle(style) end
end)

-- THIS remote function is used to grab all the existing fighting style and send it to the client automatically, without needing to update the client every time a new style is added.
Events.getFightingStyles.OnServerInvoke = function()
	local names = {}
	for name, data in pairs(combatStyles) do
		if type(data) == "table" and data.Stats then table.insert(names, name) end
	end
	return names
end

--[[
	[ STARTUP ]
	It calls the inserter of animation and Sounds. It grabs the animations and sounds from the ReplcStorage insert the animations and sounds into the combatStyle table.
	Once every player joins, it create an object and gives him the boxing style as default. Then it plays the stance animation
	Whenever a player leaves, his data gets cleared.
]] 
function combatStyles.Start()
	automaticInserterOf_Anims_Sounds_VFX()

	Players.PlayerAdded:Connect(function(plr)
		plr.CharacterAdded:Connect(function(char)
			local obj = combatStyles.new(plr, "Boxing")
			task.delay(1, function()
				if obj.AnimsTable["stance"] then obj.AnimsTable["stance"]:Play() end
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(function(plr)
		if allPlayers[plr] then
			allPlayers[plr] = nil
		end
	end)
end

return combatStyles
