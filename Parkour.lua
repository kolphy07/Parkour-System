-- Parkour Movement script by Kolphy_07 on Discord and Kolphy_07 on Roblox(Refactored)

-- Services needed

local Players = game:GetService("Players")
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- defining basic variables like player hrp char cam humanoid etc
-- setting classes for the things like the rootpart humanoid so the script knows what they are classified as 

local plr = Players.LocalPlayer 
local char = plr.Character or plr.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart") :: BasePart 
local hum = char:WaitForChild("Humanoid") :: Humanoid
local animator = hum:WaitForChild("Animator") :: Animator
local cam = workspace.CurrentCamera :: Camera

local SFX = script:WaitForChild("SFX") -- sounds folder in script for sounds
local VFX = ReplicatedStorage:WaitForChild("FX") -- folder in replicated storage for vfx
local FXFolder = workspace:WaitForChild("FX") -- folder in workspace that holds afterimages and dash effects

local moosic = workspace:WaitForChild("Speedrun (ver 2)") :: Sound -- the track that plays when you go fast

-- type for raycast wallrun functions

--[[
	WallHit is a type that combine together everything the wall run needs to know about a wall that was found next to the player
	GetSideWall creates one of these when a side ray hits something then TtyWallRun or StartWallRun read from it
	so they dont have to work out which side the wall is on again (and dont need more return values like last time i did this)
	since its all in the one type 
]]--

type WallHit = {
	Ray: RaycastResult,
	Anim: AnimationTrack,
	Tag: string,
}

-- config tables for all the changable values

local SpeedConfig = {
	Run = 26, -- default run speed
	Walk = 12, -- default walk speed
	Crouch = 6, -- crouch speed
	CrouchSprint = 12, -- crouch sprint speed
	MoveThreshold = 0.5, -- how much move direction is needed to count as moving
}

local WallRunConfig = {
	StickForce = 15, -- force the player goes into the wall at
	JumpUpForce = 45, -- force that makes you go up Y axis from wall
	JumpAwayForce = 125, -- force that makes you go away from the wall
	HoldDistance = 2.5, -- studs between the root and the wall surface
	CheckDistance = 9, -- how far the side rays reach to find a wall
	CheckBackOffset = 3, -- how far behind the player the side rays start
	ReachDistance = 14, -- how far the ray reaches into the wall we are attached to
	MaxFacing = 0.65, -- the wall has to be less head on than this to be runnable
	Speed = 50, -- base speed along the wall walkspeed gets added on top
	FallSpeed = -17, -- slow slide down the wall so the player doesnt stay on one y level
	TurnSpeed = 12, -- how fast the character turns to face along the wall
}

local SlideConfig = {
	StartSpeed = 60, -- starting slide speed scales with current walking speed
	MinSpeed = 15, -- the minimum speed needed for slide
	MaxSpeed = 300, -- the maximum speed slide can go to
	MinSlopeAngle = 10, -- angle at which the ground counts as a slope
	Accel = 75, -- rate of acceleration for slide
	Decel = 60, -- rate of deceleration for slide
	GroundCheck = 9, -- how far down to look for the ground
	StickDown = -25, -- downward velocity that keeps the player on the ground
	SlopeStickDown = -105, -- increased stick down speed when sliding down a slope
}

local StaminaConfig = {
	Max = 100,
	MinToSprint = 3, -- not enough stamina under this so under 3 means they cant sprint
	SprintDrain = 0.45, -- how much stamina out of 100 is being drained by the tickrate
	CrouchSprintDrain = 0.35, -- smaller drain for crouching
	SlideDrain = 0.25, -- slide drain is smaller so sliding feels good
	DrainTick = 0.12, -- drain every .12 seconds
	Regen = 0.5, -- how much stamina is regenerated per tick
	RegenTick = 0.03, -- regen is faster than the drain because its waiting less
}

local DashConfig = {
	MaxCharges = 2, -- max dash charges
	Speed = 100, -- dash speed in the cam direction
	Duration = 0.2, -- how long the velocity is applied
	EffectDuration = 0.25, -- after this the dash is over and everything resets
	StateRestoreDelay = 0.35, -- wait before the humanoid states come back
	Cooldown = 2.75, -- dash charge cooldown
	SpeedBoost = 50, -- big extra speed boost for the dash
	SpeedRemoved = 35, -- most of the boost is taken away but 15 is kept as momentum
	RollHeight = 50, -- y offset so player can roll after a dash
}

local JumpConfig = {
	DebounceTime = 0.1, -- jump cant be spammed faster than this
	DoubleJumpCooldown = 2, -- cooldown for double jump
	BasePower = 50, -- normal jump strength
	DoubleJumpPower = 65, -- double jump is a bit stronger than first
	FallRollHeight = 10, -- how far the player has to fall to be allowed to roll
	RollStartHeight = 13, -- how many studs above the ground the roll will start
	RollFloorCheck = 60, -- how far down to look for a floor before queueing a roll
	DoubleTapWindow = 0.35, -- how fast the 2 W presses have to be
	SprintInputDelay = 0.07, -- tiny wait before sprinting so humanoid movement magnitude can kick in
}

local FXConfig = {
	SpeedLineThreshold = 25, -- speedlines only appear above this extra speed
	AfterImageThreshold = 55, -- only make afterimages when really fast
	DecayTick = 0.05, -- how often extra speed decays
	DecayFlat = 0.1, -- always decay .1 speed
	DecayPercent = 0.01, -- 1/100 fraction of current speed lost per second
}

-- player stats variables like stamina wall running dashes etc

local Stats = plr:WaitForChild("Junk") -- main folder where everything is located
local Stamina = Stats:WaitForChild("Stamina") :: NumberValue
local Sprinting = Stats:WaitForChild("Sprinting") :: BoolValue
local WallRunning = Stats:WaitForChild("WallRunning") :: BoolValue
local Dashes = Stats:WaitForChild("Dashes") :: NumberValue
local Crouching = Stats:WaitForChild("Crouching") :: BoolValue
local Sliding = Stats:WaitForChild("Sliding") :: BoolValue

--  variables for the states like wallrunning sliding double jumps sprint loops etc

local CurrentSpeed = SpeedConfig.Walk -- current base speed
local LastWPress  = os.clock() -- when w was last pressed
local Dissipating = false -- is extra speed dissipating
local sprintLoopActive = false
local regenLoopActive = false
local JumpDebounce = false
local firstjump = true
local lastDoubleJump = os.clock()
local Rolling = false
local YPos = 0 -- used to calculate player height when attempting a ground roll

local WallRunRay: RaycastResult = nil -- wall run raycast
local WallRunConnection: RBXScriptConnection = nil -- connection for wall run
local WallRunSound: Sound = nil
local WallRunDirection : Vector3 = Vector3.zero -- previous run direction used to keep the flip consistent

local SlideConnection: RBXScriptConnection = nil
local SlideAmbience: Sound = nil -- wind sound while sliding
local SlideScrape: Sound = nil -- actual slide sound
local slideSpeed : number = 0 
local slideAddedSpeed : number = 0 -- additional speed player gets from slide

-- jump strength is set through jumpheight jumppower is legacy now for some reason so convert the old power values

hum.UseJumpPower = false

-- set the variable : type variable inside each function so the function knows what its working with and set the function() : variable type so code calling it knows what type its returning
local function JumpHeightFromPower(power: number): number -- formula to convert jump power to height since jump power is old apparently
	return (power ^ 2) / (2 * workspace.Gravity)
end

local BaseJumpHeight = JumpHeightFromPower(JumpConfig.BasePower)
local DoubleJumpHeight = JumpHeightFromPower(JumpConfig.DoubleJumpPower)
hum.JumpHeight = BaseJumpHeight

-- one universal raycast params that exclude character that i can call whenever

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { char }
params.IgnoreWater = true

local ESpeed = Instance.new("NumberValue") -- extra speed value that will stack with the base speeds

-- tween infos for tweens

local Info = TweenInfo.new(.35, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, false, 0)
local Info2 = TweenInfo.new(.15, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, true, 0)

-- blur effect for sprinting dashes etc

local Blur = (Lighting:FindFirstChild("RunBlur") or Instance.new("BlurEffect")) :: BlurEffect
Blur.Size = 5
Blur.Name = "RunBlur"
Blur.Enabled = false
Blur.Parent = Lighting

-- a variety of tweens I can call upon for various misc things for visual effects like blur increased FOV while running etc
-- named to sprintfov normal fov etc so its easy to know what they are used for instead of them being called [1] [2] [3] etc
local Tweens = {
	SprintFOV = TS:Create(cam, Info, { FieldOfView = 90 }),
	NormalFOV = TS:Create(cam, Info, { FieldOfView = 70 }),
	BlurIn = TS:Create(Blur, Info, { Size = 5 }),
	BlurOut = TS:Create(Blur, Info, { Size = 0 }),
	CrouchOffset = TS:Create(hum, Info, { CameraOffset = Vector3.new(0, -1, 0) }),
	ResetOffset = TS:Create(hum, Info, { CameraOffset = Vector3.zero }),
	CrouchSprintFOV = TS:Create(cam, Info, { FieldOfView = 55 }),
	SlideOffset = TS:Create(hum, Info, { CameraOffset = Vector3.new(0, -1.4, 0) }),
	DashBlur = TS:Create(Blur, Info2, { Size = 7 }),
	DashFOV = TS:Create(cam, Info2, { FieldOfView = 95 }),
}

-- animation table that stores all the animations in one place for easy access

local function LoadAnim(name: string): AnimationTrack
	return animator:LoadAnimation(script:WaitForChild(name))
end

local Anims = {
	Run = LoadAnim("Run"),
	CrouchWalk = LoadAnim("CrouchWalk"),
	Crouch = LoadAnim("Crouch"),
	Dash = LoadAnim("Dash"),
	Sliding = LoadAnim("Sliding"),
	Vault = LoadAnim("Vault"),
	Roll = LoadAnim("Roll"),
	WallRunL = LoadAnim("WallRunL"),
	DJ = LoadAnim("DoubleJump"),
	LJ = LoadAnim("LongJump"),
	WallRunR = LoadAnim("WallRunR"),
}

-- setting the priority of certain animations greater than others so they dont interfere with eachother
Anims.CrouchWalk.Priority = Enum.AnimationPriority.Action2
Anims.Dash.Priority = Enum.AnimationPriority.Action2
Anims.Sliding.Priority = Enum.AnimationPriority.Action3
Anims.WallRunL.Priority = Enum.AnimationPriority.Action3
Anims.WallRunR.Priority = Enum.AnimationPriority.Action3
Anims.Sliding.Looped = true

-- effects that get cloned so each player gets their own

local DistortionTemplate = VFX:WaitForChild("Distortion") :: BasePart
local SpeedFXTemplate = VFX:WaitForChild("SpeedFX") :: BasePart

-- limbs that get copied for the afterimages stored in table  so as to do dont loop  through the whole character every time

local LimbParts: { BasePart } = {} -- set the type of the table to BasePart so script knows every value inside it is of the basepart type

for _, child in char:GetChildren() do
	if child:IsA("BasePart") and child.Name ~= "Head" and child.Name ~= "HumanoidRootPart" then
		table.insert(LimbParts, child)
	end
end

-- small helping functions  used all over the place so i dont keep repeating the same lines and can just call the function

local function IsAirborne(): boolean
	return hum.FloorMaterial == Enum.Material.Air
end

local function IsMoving(): boolean
	return hum.MoveDirection.Magnitude > SpeedConfig.MoveThreshold
end

local function CTSpeed(spd: number): number -- change current speed
	CurrentSpeed = spd -- set current base speed to spd
	hum.WalkSpeed = CurrentSpeed + ESpeed.Value -- set humanoid walk speed to current speed plus any extra speed
	return spd + ESpeed.Value -- return current speed plus any extra speed if needed
end

-- disable certain humanoid states so they dont interfere with the sliding / dash physics
local function SetPhysicsStatesEnabled(enabled: boolean)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, enabled)
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, enabled)
	hum:SetStateEnabled(Enum.HumanoidStateType.Physics, enabled)
end

local function CloneSound(soundName: string) : Sound -- clones the sound if in the sfx folder or warns if doesnt exist
	local template = SFX:FindFirstChild(soundName)

	if not template then -- sound doesnt exist in the SFX folder
		warn("Missing sound: " .. soundName)
		return nil
	end

	return template:Clone() 
end

local function DestroySound(sound: Sound)
	if sound then
		sound:Destroy()
	end
end

local function PlaySound(soundName: string) -- basic function to play sound
	local S = CloneSound(soundName) -- clones the sound from the SFX folder in the script
	if not S then return end

	S.PlaybackSpeed += math.random(-15, 15) / 100 -- randomize the pitch a bit for variation
	S.Parent = SoundService -- parent it to sound service so its a set volume
	S:Play()

	-- safety net in case the sound never ends like the timeLength can be 0 if the sound hasnt loaded yet so use a minimum of 2 just in case then an extra +2 delay for insurance
	Debris:AddItem(S, math.max(S.TimeLength, 2) + 2)
end

-- sound that follows the root [art and gets destroyed laterused for wall running and sliding
local function AttachSound(soundName: string): Sound
	local sound = CloneSound(soundName)

	if not sound then	return nil	end

	sound.Parent = root
	sound:Play()

	return sound
end

-- wall running functions

local function StopWallRun() -- stops everything wall running related and resets the player
	if WallRunConnection then -- stop the connection
		WallRunConnection:Disconnect()
		WallRunConnection = nil
	end

	Anims.WallRunL:Stop() -- stop wall run anims
	Anims.WallRunR:Stop()
	char:RemoveTag("L") -- remove the tag for other script detection

	DestroySound(WallRunSound) -- destroy the wall run sound
	WallRunSound = nil

	WallRunning.Value = false -- stop wall running value
	WallRunRay = nil -- set ray to nil
	hum.AutoRotate = true -- allow player to rotate again
end

-- cross with up gives the direction that points along the wall flipped to match the previous direction
local function GetWallDirection(wallNormal: Vector3, previousDirection: Vector3): Vector3
	local wallDirection = Vector3.yAxis:Cross(wallNormal)

	if wallDirection.Magnitude < 0.001 then -- wall is flat like a floor so theres no direction
		return nil
	end

	wallDirection = wallDirection.Unit -- normalize so its just a direction and speed gets applied later

	if wallDirection:Dot(previousDirection) < 0 then -- compare to last frame instead of the starting look vector
		wallDirection = -wallDirection -- cross can point either way so flip it if its going backwards
	end

	return wallDirection
end

local function UpdateWallRun(dt: number) -- runs every frame while wallrunning
	if not WallRunRay or not IsAirborne() then -- player touched the ground
		StopWallRun()
		return
	end

	local newRay = workspace:Raycast(root.Position, -WallRunRay.Normal * WallRunConfig.ReachDistance, params) -- recast into the wall we are attached to

	if not newRay then -- wall is gone so nothing to run on
		StopWallRun()
		return
	end

	WallRunRay = newRay -- update the ray so the jump function uses the newest wall

	local wallDirection = GetWallDirection(newRay.Normal, WallRunDirection)

	if not wallDirection then
		StopWallRun()
		return
	end

	WallRunDirection = wallDirection -- save it for the next frame check

	-- turn the character to face along the wall lerped smoothed so it doesnt snap
	local pos = root.Position -- current position so the turn doesnt move the player
	local targetCFrame = CFrame.lookAt(pos, pos + wallDirection) -- cframe at the same spot but looking down the wall
	root.CFrame = root.CFrame:Lerp(targetCFrame, math.min(dt * WallRunConfig.TurnSpeed, 1)) -- min stops it going past 1 on a laggy frame

	-- pull toward holdDistance instead of always pushing in and negative values push away if too close
	local stickSpeed = math.clamp((newRay.Distance - WallRunConfig.HoldDistance) * 10, -20, WallRunConfig.StickForce)
	local wallSpeed = WallRunConfig.Speed + hum.WalkSpeed -- base run speed plus walkspeed so it follows speed changes live

	-- run along the wall plus the stick in or out plus the downward drift
	root.AssemblyLinearVelocity = wallDirection * wallSpeed - newRay.Normal * stickSpeed	+ Vector3.new(0, WallRunConfig.FallSpeed, 0)
end

local function StartWallRunSound()
	local sound = CloneSound("Run") -- cloning instead of using function because wall run duration isnt set and speed isnt set either

	if not sound then
		return
	end

	sound.Parent = root
	sound.PlaybackSpeed = 1 + (hum.WalkSpeed / 126) -- adjusting speed depending on players speed
	sound.Looped = true
	sound.Name = "WallRunSound"
	sound:Play()

	WallRunSound = sound
end

local function StartWallRun(wall: WallHit)
	WallRunning.Value = true -- set wall running to true
	WallRunRay = wall.Ray -- set the ray to the current ray
	WallRunDirection = root.CFrame.LookVector

	if wall.Tag ~= "" then -- tag for other scripts to detect
		char:AddTag(wall.Tag)
	end

	wall.Anim:Play()
	wall.Anim:AdjustSpeed(1 + (hum.WalkSpeed / 126)) -- adjust wall run speed depending on players speed

	StartWallRunSound()
	hum.AutoRotate = false -- stop player from rotating while wall running just in case if they do it breaks anything

	WallRunConnection = RS.Heartbeat:Connect(UpdateWallRun)
end

-- 2 rays to check for walls that go out to the left and right of the player positioned a bit behind the player
-- (the ray on the positive rightvector side plays WallRunL and gets the "L" tag (other scripts rely on that so thats why the tag is there)
local function GetSideWall()
	local cf = root.CFrame
	local origin = cf:PointToWorldSpace(Vector3.new(0, 0, WallRunConfig.CheckBackOffset)) -- local space so its actually behind the player
	local reach = cf.RightVector * WallRunConfig.CheckDistance

	local hitL = workspace:Raycast(origin, reach, params) -- this is actually the right vector side however i mixed up left and right wall run animations so thats why  its called hitL
	local hitR = workspace:Raycast(origin, -reach, params)
	
	if hitL then return { Ray = hitL, Anim = Anims.WallRunL, Tag = "L" } end -- wallRunL is actually the right wall run animation  i mixedit up tho and not bothered to rename the two anims lol
	if hitR then return { Ray = hitR, Anim = Anims.WallRunR, Tag = "" }	end

	return nil
end

local function CanWallRun(): boolean
	return Sprinting.Value and not WallRunning.Value and IsAirborne()
end

-- returns true if the jump was used up by the wall run check
local function TryWallRun(): boolean
	if not CanWallRun() then	return false end

	local wall = GetSideWall()
	if not wall then	return false end

	-- Only wall run if roughly not facing straight into it
	local facingWall = math.abs(root.CFrame.LookVector:Dot(wall.Ray.Normal))

	if facingWall < WallRunConfig.MaxFacing then
		StartWallRun(wall)
		JumpDebounce = false
	end

	return true
end

local function WallJump(ray: RaycastResult) -- launches the player away from the wall
	local speed = hum.WalkSpeed -- get players speed
	local awayFromWall = ray.Normal -- the normal direction away from the wall

	-- calculate the velocity to jump away from the wall based on root look vector, wall normal, jump force scaled with speed and wall jump up force scaled with speed
	local jumpVelocity = root.CFrame.LookVector * (35 + (speed / 4))
		+ awayFromWall * (WallRunConfig.JumpAwayForce + (speed / 4) * 0.35)
		+ Vector3.yAxis * (WallRunConfig.JumpUpForce + speed * 0.1)

	PlaySound("Dash3") -- play wall jump away sound
	StopWallRun()

	root.AssemblyLinearVelocity += jumpVelocity -- add the calculated velocity to the players velocity
	JumpDebounce = false -- reset jump DB
	ESpeed.Value += 20 -- give player a bit of speed boost

	if Dashes.Value <= 0 then -- if player has no dashes give player a dash
		Dashes.Value += 1
	end

	task.delay(.05, function()
		lastDoubleJump = -math.huge -- reset last double jump
	end)
end

-- sliding functions

local function DestroySlideSounds()
	DestroySound(SlideAmbience)
	DestroySound(SlideScrape)
	SlideAmbience = nil
	SlideScrape = nil
end

local function CleanupSlide()
	-- cleanup function that stops the slide, disconnects the slide connection so the sliding code stops working
	-- stops sliding animation and sets sliding to false so the other movement states are possible
	-- and lets the disabled states become able to be switched to again

	if SlideConnection then -- if connection is there still disconnect it
		SlideConnection:Disconnect()
		SlideConnection = nil
	end

	DestroySlideSounds()

	Tweens.ResetOffset:Play() -- smooth reset of camera offset
	Anims.Sliding:Stop() -- stop animation
	Sliding.Value = false -- set sliding to false

	-- reset humanoid states to allow for normal movement again
	SetPhysicsStatesEnabled(true)
	hum:ChangeState(Enum.HumanoidStateType.Running)

	-- get rid of the added speed from sliding but never go negative, some of it may have already decayed
	ESpeed.Value = math.max(ESpeed.Value - slideAddedSpeed, 0)
	slideAddedSpeed = 0
	root.CanCollide = true -- allow collisions on root for bigger hitbox since not sliding
end

-- returns if the ground counts as a slope and if the player is sliding down it
local function GetSlopeInfo(groundNormal: Vector3, moveDir: Vector3): (boolean, boolean)
	-- dot gives angle between the ground normal and up, acos converts it to radians and deg makes it easy to compare
	-- clamp keeps the value between -1 and 1 to prevent errors since cos cant exceed 1
	local slopeAngle = math.deg(math.acos(math.clamp(groundNormal:Dot(Vector3.yAxis), -1, 1)))

	if slopeAngle < SlideConfig.MinSlopeAngle then -- flat enough to not be a slope
		return false, false
	end

	-- up projected onto the slope gives the direction pointing uphill
	local uphill = Vector3.yAxis - groundNormal * groundNormal:Dot(Vector3.yAxis)

	if uphill.Magnitude <= 0.001 then -- make sure direction is valid
		return true, false
	end

	return true, moveDir:Dot(uphill.Unit) < -0.1 -- moving against uphill means were going down
end

-- send movement direction onto the slope so movement follows its surface
local function MovementDirectionOntoGround(moveDir: Vector3, groundNormal: Vector3): Vector3
	if not groundNormal then
		return moveDir
	end

	local projected = moveDir - groundNormal * moveDir:Dot(groundNormal)

	if projected.Magnitude <= 0.001 then -- make sure the direction is valid
		return moveDir
	end

	return projected.Unit
end

-- changes the slide speed depending on the ground and returns how hard the player gets pushed into the ground
local function ApplySlideAcceleration(dt: number, onGround: boolean, onSlope: boolean, movingDownhill: boolean): number
	if not onGround then
		slideSpeed += 25 * dt -- slow speed up if no ground
		return SlideConfig.StickDown
	end

	if not onSlope then
		slideSpeed -= SlideConfig.Decel * dt -- slow down when not on a slope
		slideAddedSpeed += (SlideConfig.Accel * dt) / 2.6 -- increase total added speed
		ESpeed.Value += (SlideConfig.Accel * dt) / 1.4 -- increase extra speed
		return SlideConfig.StickDown
	end

	if not movingDownhill then
		slideSpeed -= SlideConfig.Accel * dt -- slow down while going uphill
		return SlideConfig.StickDown
	end

	slideSpeed += SlideConfig.Accel * dt -- speed up while going downhill
	slideAddedSpeed += (SlideConfig.Accel * dt) / 8 -- increase total added speed by a smaller amount
	ESpeed.Value += (SlideConfig.Accel * dt) / 1.25 -- increase extra speed while going down
	return SlideConfig.SlopeStickDown
end

local function UpdateSlideSounds()
	if SlideAmbience then
		SlideAmbience.PlaybackSpeed = slideSpeed / 60
	end

	if SlideScrape then
		SlideScrape.PlaybackSpeed = slideSpeed / 90
	end
end

local function UpdateSlide(dt: number) -- runs every frame while sliding
	if not Sliding.Value then -- if not sliding then stop everything
		CleanupSlide()
		return
	end

	local result = workspace:Raycast(root.Position, Vector3.new(0, -SlideConfig.GroundCheck, 0), params) -- ray going downwards from the players current position
	local moveDir = root.CFrame.LookVector -- what dir the player is moving
	local onSlope, movingDownhill = false, false

	if result then
		onSlope, movingDownhill = GetSlopeInfo(result.Normal, moveDir)
	end

	local stickDown = ApplySlideAcceleration(dt, result ~= nil, onSlope, movingDownhill)
	slideSpeed = math.clamp(slideSpeed, SlideConfig.MinSpeed, SlideConfig.MaxSpeed) -- keep speed within the allowed range

	local finalDir = MovementDirectionOntoGround(moveDir, if result then result.Normal else nil)
	local horizontalVel = finalDir * slideSpeed -- convert the movement direction and speed into horizontal velocity
	local currentVel = root.AssemblyLinearVelocity

	UpdateSlideSounds()

	-- preserve downward velocity from current velocity, but never allow it above the stick down speed
	root.AssemblyLinearVelocity = Vector3.new(horizontalVel.X, math.min(currentVel.Y, stickDown), horizontalVel.Z)

	if slideSpeed <= SlideConfig.MinSpeed then -- Stop slide if too slow
		CleanupSlide()
	end
end

local function Slide() -- slide function
	if SlideConnection then -- already sliding
		return
	end

	Sliding.Value = true -- set sliding to true
	Anims.Sliding:Play() -- play sliding animation

	SlideAmbience = AttachSound("SlidingAmbience") -- same logic as wall running sound but 2 sounds one is wind and actual slide
	SlideScrape = AttachSound("Sliding")

	slideSpeed = SlideConfig.StartSpeed + hum.WalkSpeed -- starting slide speed scales with current walking speed
	slideAddedSpeed = 0

	root.CanCollide = false
	Tweens.SlideOffset:Play()
	SetPhysicsStatesEnabled(false)

	SlideConnection = RS.Heartbeat:Connect(UpdateSlide)
end

-- jumping roll and vault functions

local function SlideJump() -- slide jump cancel that gives a long jump
	Sliding.Value = false
	Anims.LJ:Play() -- play slide jump cancel animation long jump thing
	Anims.DJ:Play() -- play double jump anim too so anims stack and cool
	PlaySound("Dash2") -- play dash sound
	ESpeed.Value += 7.5 -- give a bit of additional speed

	-- add a boost of speed to the player if on ground to create a long jump effect
	root.AssemblyLinearVelocity += root.CFrame.LookVector * (60 + (hum.WalkSpeed / 4)) + Vector3.yAxis * 80

	-- allow for rolling after jump but dont allow for double jumps immediately after by resetting dj cooldown
	root:AddTag("CanRoll")
	lastDoubleJump = os.clock()
	JumpDebounce = false

	task.delay(1, function()
		root:RemoveTag("CanRoll")
	end)
end

local function PerformRoll()
	PlaySound("Roll") -- play roll sound
	Anims.Roll:Play() -- play roll animation
	Anims.Roll:AdjustSpeed(2) -- making it faster because 1 is too slow
	char:AddTag("Roll") -- tag for other scripts
	root.AssemblyLinearVelocity += root.CFrame.LookVector * 65 -- push forward out of the roll
	ESpeed.Value += 7.5 -- extra speed boost from the roll

	task.delay(.3, function() -- after .3s
		char:RemoveTag("Roll") -- remove roll tag for other scripts
		Rolling = false -- can roll again
	end)
end

local function StartRoll()
	if Rolling then -- already waiting to roll
		return
	end

	local floorRay = workspace:Raycast(root.Position, root.CFrame.UpVector * -JumpConfig.RollFloorCheck, params)

	if not floorRay then -- no floor below us
		return
	end

	Rolling = true -- lock it so this cant stack multiple loops while were still falling if player keeps pressing jump

	local rollConnection: RBXScriptConnection

	rollConnection = RS.Heartbeat:Connect(function() -- check every frame so the roll triggers the moment were close enough
		-- short ray straight down, as long as rollheight so a hit means were close enough
		local groundRay = workspace:Raycast(root.Position, Vector3.new(0, -JumpConfig.RollStartHeight, 0), params)

		if not groundRay then -- still too high up so keep waiting
			return
		end

		rollConnection:Disconnect() -- stop checking
		PerformRoll()
	end)
end

-- returns true if the jump was used up by the roll check
local function TryRoll(): boolean
	if not IsAirborne() then
		return false
	end

	local fellFar = (YPos - root.Position.Y) > JumpConfig.FallRollHeight -- if YHeight is greater than 10 allow them to roll

	if not fellFar and not root:HasTag("CanRoll") then
		return false
	end

	StartRoll()
	return true
end

local function TryVault() -- vaulting logic
	local forward = root.CFrame.LookVector -- this is forward look direction

	-- Check for an obstacle in front of the player
	local wallResult = workspace:Raycast(root.Position - Vector3.new(0, 3, 0), forward * 6, params)

	if not wallResult then
		return
	end

	-- Make sure theres space above the wall that the player can go on
	local cleared = workspace:Raycast(root.Position + Vector3.new(0, 3, 0), forward * 6, params)

	if cleared then
		return
	end

	PlaySound("Vault")
	Anims.Vault:Play()

	-- Move the player over the obstacle by giving them small boost of speed
	root.AssemblyLinearVelocity += forward * 65 + Vector3.new(0, 70, 0)
	ESpeed.Value += 5
end

local function Jump() -- function for jumping used to calculate actions player can take upon space input
	--[[
	If the player is already wallrunning, pressing jump launches them
	away from the wall, with more momentum when they are moving faster if
	sliding and not in the air it will perform a long jump animation giving them a burst of speed
	these 2 stop any other actions from being taken during the jump function by returning early

	otherwise it tries wallrunning, rolling on landing from big jumps and then vaulting
	]]--

	if WallRunning.Value and WallRunRay then -- if player is wallrunning and there is a ray then
		WallJump(WallRunRay)
		return
	end

	if Sliding.Value and not IsAirborne() then -- prevent long jumping while in air by checking if humanoid is on ground
		SlideJump()
		return
	end

	if TryWallRun() then
		return
	end

	if TryRoll() then
		return
	end

	TryVault()
end

-- crouching functions

local function StandUp() -- already crouching so this press means stand up
	Crouching.Value = false -- not crouching anymore
	CTSpeed(SpeedConfig.Walk) -- set speed back to normal walkspeed

	Anims.Run:Stop() -- stop run anim just incase its still playing
	Anims.CrouchWalk:Stop() -- stop the moving crouch anim
	Anims.Crouch:Stop() -- stop idle crouch anim

	root.CanCollide = true -- collisions back on for bigger hitbox since standing

	Tweens.BlurOut:Play() -- play the tweens that smooth everything back to standing
	Tweens.NormalFOV:Play()
	Tweens.ResetOffset:Play() -- smooth reset of camera offset
end

local function StartCrouch()
	Sprinting.Value = false -- crouching cancels sprint
	Crouching.Value = true -- now crouching

	root.CanCollide = false -- collisions off for smaller hitbox while crouched
	CTSpeed(SpeedConfig.Crouch) -- set speed to the slower crouch speed

	Tweens.BlurOut:Play() -- tweens that smooth into the crouch
	Tweens.NormalFOV:Play()
	Tweens.CrouchOffset:Play() -- crouch version of the camera offset tween

	Anims.Run:Stop() -- stop run anim cuz not running anymore
	Anims.Crouch:Play() -- play idle crouch anim

	if IsMoving() then -- if player is moving while crouching as well
		Anims.CrouchWalk:Play() -- play crouch walk anim on top so they walking
	end
end

local function Crouch() -- crouch function also decides if the player should slide instead of crouch
	--[[
	if the player is wallrunning then stop because they cant crouch
	if theyre sprinting and moving it starts a slide instead of a crouch
	otherwise it toggles crouching pressing it while crouched stands them back up
	and pressing while standing crouches them slows them down and plays idle crouch animation
	]]--

	if WallRunning.Value then -- cant crouch while wallrunning so just stop
		return
	end

	if not Sliding.Value and Sprinting.Value and IsMoving() then -- not already sliding, sprinting and actually moving
		Slide() -- start slide instead of crouching
		return
	end

	if Crouching.Value then
		StandUp()
		return
	end

	StartCrouch()
end

-- sprinting functions

local function RegenStamina() -- regen until full or player starts sprinting again
	if regenLoopActive then -- regen already going so dont start another one
		return
	end

	regenLoopActive = true -- lock regen so it cant stack

	while not Sprinting.Value and Stamina.Value < StaminaConfig.Max do
		Stamina.Value = math.clamp(Stamina.Value + StaminaConfig.Regen, 0, StaminaConfig.Max) -- clamp so it stops at max
		task.wait(StaminaConfig.RegenTick)
	end

	regenLoopActive = false -- regen done so it can start again
end

local function StopSprint() -- stops the sprint and regens stamina after
	Sprinting.Value = false -- not sprinting anymore
	Tweens.NormalFOV:Play() -- tween that resets the sprint effects
	Anims.Run:Stop() -- stop run anim

	CTSpeed(if Crouching.Value then SpeedConfig.Crouch else SpeedConfig.Walk) -- crouch speed if crouching otherwise normal walkspeed

	Tweens.BlurOut:Play() -- tween that smooths back to normal
	RegenStamina()
end

local function StartSprintBlur()
	Blur.Size = 0 -- start the blur from nothing so it can tween in
	Blur.Enabled = true -- turn the blur on for the speed effect
	Tweens.BlurIn:Play() -- blur tween
end

local function StartSprintEffects() -- normal sprint
	CTSpeed(SpeedConfig.Run) -- set speed to the run speed
	StartSprintBlur()
	Tweens.SprintFOV:Play() -- normal sprint tween
	Anims.CrouchWalk:Stop() -- stop crouch anims incase they were playing
	Anims.Crouch:Stop()
	Anims.Run:Play() -- play the run anim
end

local function StartCrouchSprintEffects() -- sprinting while crouched
	CTSpeed(SpeedConfig.CrouchSprint) -- set base speed to crouch sprint speed
	StartSprintBlur()
	Tweens.CrouchSprintFOV:Play() -- the crouch sprint version of the FOV tween
end

local function GetStaminaDrain(isCrouchSprint: boolean): number
	if isCrouchSprint then
		return StaminaConfig.CrouchSprintDrain -- crouch sprint drains less than normal sprint
	end

	if Sliding.Value then
		return StaminaConfig.SlideDrain -- slide drain smaller so sliding feels good
	end

	return StaminaConfig.SprintDrain -- normal sprint drain
end

-- keep going while sprinting and moving and still got stamina
local function RunSprintLoop(isCrouchSprint: boolean)
	sprintLoopActive = true -- lock it so this cant stack loops

	while Sprinting.Value and IsMoving() and Stamina.Value > 0 do
		if not isCrouchSprint then
			Anims.Run:AdjustSpeed(hum.WalkSpeed / SpeedConfig.Run) -- if they going at 52 speed the animation will play 2x faster
		end

		Stamina.Value = math.clamp(Stamina.Value - GetStaminaDrain(isCrouchSprint), 0, StaminaConfig.Max) -- clamp so it dosnt go below 0 or over max
		task.wait(StaminaConfig.DrainTick) -- wait a bit so its not draining every frame
	end

	sprintLoopActive = false -- loop is done so it can be started again
end

local function Sprint()
	-- sprint function handles normal sprinting and sprinting while crouched also drains stamina and allows for wallrunning and stuff

	--[[
	if the player is already sprinting or the sprint loop is already running or theres barely any stamina
	nothing happens
	if crouching it does a crouch sprint which is slower otherwise a normal sprint
	both of them drain stamina in a loop until the player stops moving or runs out of stamina or stops sprinting
	then it calls stopsprint to reset everything
	]]--

	if Sprinting.Value or sprintLoopActive or Stamina.Value <= StaminaConfig.MinToSprint then
		return
	end

	local isCrouchSprint = Crouching.Value
	Sprinting.Value = true -- now sprinting

	if isCrouchSprint then
		StartCrouchSprintEffects()
	else
		StartSprintEffects()
	end

	RunSprintLoop(isCrouchSprint)

	if isCrouchSprint then -- go back to crouch speed if still crouching otherwise stood up so normal walkspeed
		CTSpeed(if Crouching.Value then SpeedConfig.Crouch else SpeedConfig.Walk)
	end

	if Sprinting.Value then -- if sprinting value is still true from running out of stamina or stopped moving
		StopSprint() -- stop the sprint properly
	end
end

-- dashing functions

local function DashDistortion()
	local distortion = DistortionTemplate:Clone() -- clone the distortion effect part so it can be used for the dash visual
	distortion.Size = Vector3.new(15, 15, 15) -- starting size
	distortion.Anchored = true -- anchored so it dosnt fall its moved by cframe below
	distortion.CanCollide = false -- no collision so it dosnt push anything
	distortion.CanQuery = false -- raycasts ignore it so it doesnt mess up wallrun or roll rays
	distortion.CanTouch = false
	distortion.CastShadow = false -- no shadow since its just an effect
	distortion.Transparency = 5 -- starts really transparent for greater distortion
	distortion.Parent = FXFolder

	Debris:AddItem(distortion, .16) -- destroy it after .16s

	TS:Create(distortion, TweenInfo.new(.15), {Size = Vector3.new(20, 20, 20),Transparency = 1}):Play()

	local follow = RS.RenderStepped:Connect(function() -- every frame so it follows the camera smoothly
		distortion.CFrame = cam.CFrame * CFrame.new(0, 0, -2) -- keep the distortion 2 studs infront of the camera
	end)

	distortion.Destroying:Once(function() -- stop following once the distortion is gone
		follow:Disconnect()
	end)
end

local function ApplyDashVelocity(direction: Vector3)
	local attachment = Instance.new("Attachment") -- attachment is needed for the linear velocity
	attachment.Parent = root

	local dashVelocity = Instance.new("LinearVelocity") -- linear velocity to actually push the player
	dashVelocity.Attachment0 = attachment -- connect it to the attachment
	dashVelocity.VectorVelocity = direction * DashConfig.Speed -- dash speed in the direction from above
	dashVelocity.MaxForce = math.huge -- infinite force so nothing stops the dash
	dashVelocity.Parent = root

	Debris:AddItem(dashVelocity, DashConfig.Duration) -- remove the velocity so the dash ends
	Debris:AddItem(attachment, DashConfig.Duration) -- and the attachment aswell
end

local function FinishDash() -- after the dash is over so reset everything
	ESpeed.Value = math.max(ESpeed.Value - DashConfig.SpeedRemoved, 0) -- take away most of the dash speed but keep some as extra momentum
	YPos = root.Position.Y + DashConfig.RollHeight -- set y pos so player can roll after dash

	task.wait(DashConfig.StateRestoreDelay)

	if not Sliding.Value then
		SetPhysicsStatesEnabled(true) -- turn the states back on
	end

	task.wait(DashConfig.Cooldown - DashConfig.StateRestoreDelay) -- dash cooldown

	if Dashes.Value < DashConfig.MaxCharges then -- make sure no wall jump dash was given
		Dashes.Value += 1 -- give the dash charge back
	end
end

local function Dash() -- dash function launches the player forward where the camera is looking
	--[[
	uses up a dash charge then plays the dash effects and adds a short burst of velocity in the cam direction
	while its happening the ragdoll type states are disabled so physics affect the dash less if they dash into the ground or smth
	after a short time they get turned back on and the dash charge comes back after a cooldown
	]]--

	if Dashes.Value <= 0 then -- no dashes left so stop
		return
	end

	Tweens.DashBlur:Play() -- dash tweens for the camera stuff
	Tweens.DashFOV:Play()

	Sliding.Value = false -- if sliding stop slide to allow for dash
	Dashes.Value -= 1 -- use up a dash charge

	PlaySound("Dash") -- play dash sound
	Anims.Dash:Play() -- play dash anim

	DashDistortion()
	ApplyDashVelocity(cam.CFrame.LookVector) -- direction the dash goes where the camera is looking

	ESpeed.Value += DashConfig.SpeedBoost -- big extra speed boost for the dash
	SetPhysicsStatesEnabled(false) -- disable these states so they dont interfere with the dash

	task.delay(DashConfig.EffectDuration, FinishDash)
end

-- extra speed  logic and the speed effects and music stuff

local SpeedFX = SpeedFXTemplate:Clone() -- clone the speed effect part 
SpeedFX.Anchored = false -- has to be unanchored or the weld would freeze the player
SpeedFX.Massless = true -- make sure it doesnt affect the players speed from weighing player down
SpeedFX.CanCollide = false
SpeedFX.CanQuery = false
SpeedFX.CanTouch = false
SpeedFX.CFrame = root.CFrame * CFrame.new(0, 0, -50) -- 50 studs infront so the lines come from a distance
SpeedFX.Parent = FXFolder

for _, emitter in SpeedFX:GetChildren() do -- turn every emitter on but with rate 0 so nothing shows until speed is high
	if not emitter:IsA("ParticleEmitter") then
		continue
	end

	emitter.Rate = 0
	emitter.Enabled = true
end

local SpeedLines = {
	SpeedFX:WaitForChild("Line1") :: ParticleEmitter, -- the 2 speed line emitters
	SpeedFX:WaitForChild("Line2") :: ParticleEmitter,
}

local speedFXWeld = Instance.new("WeldConstraint") -- weld to hold the speed effect infront of the player
speedFXWeld.Part0 = root -- stuck to the players root
speedFXWeld.Part1 = SpeedFX -- the effect part
speedFXWeld.Parent = root

local function SetSpeedLineRate(rate: number)
	for _, line in SpeedLines do
		line.Rate = rate
	end
end

local function UpdateMusic() -- music gets louder the faster the player is and clamped so its not too quiet or too loud
	moosic.Volume = math.clamp((hum.WalkSpeed / 100) - .3, 0, .6)
end

local function UpdateSpeedLines() -- speed lines get more the further past the threshold and none if under it
	local overThreshold = ESpeed.Value - FXConfig.SpeedLineThreshold
	SetSpeedLineRate(math.max(overThreshold, 0) * 1.5)
end

-- take away the flat decay plus the percent decay scaled by time passed and never go below 0
local function DecayExtraSpeed(elapsed: number)
	-- elapsed is the real time over the wait, task.wait can lag and end up being longer or shorter
	-- multiplying by elapsed * 20 gives the proper decay, if its exactly .05 it'll be the normal decay rate
	local scale = elapsed * 20
	local flatDecay = FXConfig.DecayFlat * scale
	local percentDecay = ESpeed.Value * FXConfig.DecayPercent * scale

	ESpeed.Value = math.clamp(ESpeed.Value - (flatDecay + percentDecay), 0, 1e9)
	hum.WalkSpeed = CurrentSpeed + ESpeed.Value -- walkspeed is the normal speed plus whatever extra is left
end

local function CreateGhostPart(limb: BasePart, parent: Instance, tweenInfo: TweenInfo)
	local p = limb:Clone() -- copy the part
	p:ClearAllChildren()

	p.Anchored = true -- stays where the player was
	p.CanCollide = false -- no collision so it doesnt push anything
	p.CanQuery = false -- raycasts ignore it so it doesnt mess up wallrun or roll rays
	p.CanTouch = false -- no touch events
	p.CastShadow = false -- glow shouldnt cast shadows
	p.Size *= 1.08 -- slightly bigger than the real part so it looks like a glow

	p.Material = Enum.Material.Neon -- neon so its glowy
	p.Color = Color3.fromRGB(120, 200, 255) -- light blue afterimage colour
	p.Transparency = 0.35
	p.Parent = parent -- set parent to folder for cleanup

	TS:Create(p, tweenInfo, { Transparency = 1 }):Play() -- fade out over its lifetime
end

local function SpawnAfterImage()
	local lifetime = 0.15 + (hum.WalkSpeed / 150) -- clone lifetime increases based on player speed
	local tweenInfo = TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local ghost = Instance.new("Folder") -- folder to hold all parts for cleanup

	for _, limb in LimbParts do
		CreateGhostPart(limb, ghost, tweenInfo)
	end

	ghost.Parent = FXFolder -- put the ghost in the workspace so player can see
	Debris:AddItem(ghost, lifetime + 0.1) -- destroy it a bit after it fades so nothing is left behind
end

local function OnExtraSpeedChanged() -- runs whenever the extra speed changes
	if Dissipating then return end
		-- decay loop already running so dont start another one


	Dissipating = true -- turn on the loop so it cant loop again

	while ESpeed.Value > 0 do -- while there is additional extra speed loop
		local elapsed = task.wait(FXConfig.DecayTick)

		UpdateMusic()
		DecayExtraSpeed(elapsed)
		UpdateSpeedLines()

		if ESpeed.Value > FXConfig.AfterImageThreshold then -- only make afterimages when really fast
			SpawnAfterImage()
		end
	end

	SetSpeedLineRate(0) -- extra speed is gone so turn the lines off
	hum.WalkSpeed = CurrentSpeed + ESpeed.Value -- make sure walkspeed ends on the right value
	Dissipating = false -- set to false so the loop can start again
end

-- input and humanoid event functions

local function OnWPressed() -- w for the double tap sprint
	local now = os.clock()
	local isDoubleTap = now - LastWPress < JumpConfig.DoubleTapWindow -- last w press was less than .35s ago so its a double tap

	LastWPress = now -- save the time of this press for the next check

	if not isDoubleTap then
		return
	end

	task.delay(JumpConfig.SprintInputDelay, Sprint) -- tiny wait before sprinting so humanoid movement magnitude can kick in
end

local function OnJumpPressed()
	if JumpDebounce then 	return 	end

	JumpDebounce = true -- turn debounce on then off so jump cant be spammed
	task.delay(JumpConfig.DebounceTime, function()
		JumpDebounce = false
	end)

	Jump()
end

local InputActions: { [Enum.KeyCode]: () -> () } = { -- classify the table that each thing a keybind that returns the  if  binded to a function that function returns nothing
	[Enum.KeyCode.C] = Crouch, -- c or left control crouches or slides
	[Enum.KeyCode.LeftControl] = Crouch,
	[Enum.KeyCode.W] = OnWPressed, -- double tapping w sprints
	[Enum.KeyCode.LeftShift] = Dash, -- left shift dashes
	[Enum.KeyCode.Space] = OnJumpPressed, -- space jumps which also does wallrun and vault and roll and long jump depending on whats happening
}

local CrouchKeys: { [Enum.KeyCode]: boolean } = { -- classify a table that each key is true if it is a crouch key
	[Enum.KeyCode.C] = true,
	[Enum.KeyCode.LeftControl] = true,
}

local function OnInputBegan(inp: InputObject, typing: boolean) -- input handler for all the movement keys
	if typing then return end -- if the game already used the input like typing in chat
	 -- stop so keys dont do stuff while typing

	local action = InputActions[inp.KeyCode]

	if action then
		action()
	end
end

local function OnInputEnded(inp: InputObject, typing: boolean) -- runs when a key is let go
	if typing then return end -- same as above ignore game processed input like typing
	if not CrouchKeys[inp.KeyCode] then 	return 	end

	if Sliding.Value then -- if sliding then letting go of crouch ends the slide
		Sliding.Value = false
	end
end

local function OnMoveDirectionChanged() -- lets the crouch walk anim follow the move direction
	if not Crouching.Value then return end -- not crouching	

	local walkAnim = Anims.CrouchWalk
	local moving = IsMoving()

	if moving and not walkAnim.IsPlaying then -- crouching and moving and the anim isnt already playing
		walkAnim:Play() -- start the crouch walk anim
	elseif not moving and walkAnim.IsPlaying then -- crouching but stopped moving and the anim is still playing
		walkAnim:Stop() -- stop it so they go back to the idle crouch
	end
end

local function CanDoubleJump(): boolean
	if os.clock() - lastDoubleJump < JumpConfig.DoubleJumpCooldown then	return false	end --  double jump still on cd
	if not IsAirborne() then  return false end-- on the ground

	return not Sliding.Value and not WallRunning.Value  -- see if not sliding or wall running 
end

local function PerformDoubleJump()
	lastDoubleJump = os.clock() -- save the time for the cooldown

	PlaySound("Dash2") -- play the dash sound

	hum.JumpHeight = DoubleJumpHeight -- set jump a bit stronger than first
	Anims.DJ:Play() -- play double jump anim
	char:AddTag("Roll") -- roll tag so other scripts know they can roll after this

	hum:ChangeState(Enum.HumanoidStateType.Jumping) -- change state to jumping to mimic a jump

	task.delay(0.15, function()
		char:RemoveTag("Roll") -- remove the roll tag
		hum.JumpHeight = BaseJumpHeight -- reset jump strength
		YPos = root.Position.Y -- set y pos again so the fall height starts from the double jump
	end)
end

local function OnJumpRequest() -- runs when the player presses jump
	-- track the first jump

	if not firstjump then -- the player hasnt attempted first jump yet
		task.delay(0.15, function()
			YPos = root.Position.Y -- set y pos a bit after jump is done
		end)
		task.delay(.06, function() -- let property changed signal thing fire
			firstjump = true
		end)
		return
	end

	-- first jump is already true so this is for the double jump
	if not CanDoubleJump() then 	return 	end

	PerformDoubleJump()
end

local function OnFloorMaterialChanged() -- when standing material of humanoid changes
	if not IsAirborne() then firstjump = false end -- if they arent in the air - reset the first jump
end

-- functions other scripts can call  for like mobile support if and stuff if i ever add that

shared.Jump = Jump
shared.Slide = Slide
shared.Crouch = Crouch
shared.Sprint = Sprint
shared.StopSprint = StopSprint
shared.Dash = Dash

-- connecting everything

ESpeed.Changed:Connect(OnExtraSpeedChanged)
UIS.InputBegan:Connect(OnInputBegan)
UIS.InputEnded:Connect(OnInputEnded)
UIS.JumpRequest:Connect(OnJumpRequest)
hum:GetPropertyChangedSignal("MoveDirection"):Connect(OnMoveDirectionChanged)
hum:GetPropertyChangedSignal("FloorMaterial"):Connect(OnFloorMaterialChanged)
