-- Parkour Movement script by Kolphy_07 on Discord and Kolphy_07 on Roblox

-- defining basic variables like player  hrp char cam humanoid etc

local plr = game:GetService("Players").LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")
local hum: Humanoid = char:WaitForChild("Humanoid")
local animator = hum:WaitForChild("Animator")
local cam = workspace.CurrentCamera

-- Services needed 

local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local SFX = script:WaitForChild("SFX") -- sounds folder in script for sounds
local VFX = game:GetService("ReplicatedStorage"):WaitForChild("FX") -- folder in replicated storage for vfx

local moosic = workspace:WaitForChild("Speedrun (ver 2)") -- the track that plays when you go fast

-- Variables for movement 

local RunSpeed = 26  -- default run speed
local WalkSpeed = 12 -- default walk speed
local CrouchSpeed = 6 -- crouch speed
local CrouchSprint = 12 -- default crouch speed
local Disappating = false -- is stamina disapppating
local LastWPress = tick() -- tick when w was last pressed

local CurrentSpeed = WalkSpeed -- current speed
local WallRunRay = nil -- wall run raycast

local WallStickForce = 15 -- force the player goes into the wall at
local WallJumpUpForce = 45 -- force that makes you go up Y axis from wall
local WallJumpAwayForce = 125 -- force that makes you go away from the wall
local WallRunConnection -- rbx script connection for wall run

local cooldown = 2 -- cooldown for doubl ejump
local firstjump = true
local lastDoubleJump = os.clock()


local params = RaycastParams.new() -- one universal raycast params that exclude character that i can call whenever
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { char }
params.IgnoreWater = true

local ESpeed = Instance.new("NumberValue") -- extra speed value that will stack with base speeds

local function CTSpeed(spd)  -- change current speed 
	CurrentSpeed = spd -- set current base speed to spd
	hum.WalkSpeed = CurrentSpeed + ESpeed.Value -- set humanoid walk speed to current speed plus any extra speed
	return spd + ESpeed.Value -- return current speed plus any extra speed if needed
end

local function PlaySound(Sound) -- basic function to play sound
	local S = SFX:FindFirstChild(Sound):Clone() -- clones the sound from the SFX folder in the script
	S.PlaybackSpeed = S.PlaybackSpeed + math.random(-15,15)/100 -- randomize the pitch a bit for variation 
	S.Parent = game.SoundService  -- parent it to sound srvice so its a set volume 
	S:Play()   -- plays the sound
	
	-- add the sound to debris to destroy it after it ends after its timelength and addition time of 2 seconds to compensate  for pitch randomization
	game.Debris:AddItem(S,S.TimeLength + 2)
end

-- player stats variables like stamina, wall running, dashes, etc

local Stats = plr:WaitForChild("Junk")  -- main folder where everything is located
local Stamina,Sprinting,WallRunning = Stats:WaitForChild("Stamina"), Stats:WaitForChild("Sprinting"),Stats:WaitForChild("WallRunning")
local Dashes, Crouching, Sliding =  Stats:WaitForChild("Dashes"), Stats:WaitForChild("Crouching"), Stats:WaitForChild("Sliding")

-- tween infos for tweens

local Info = TweenInfo.new(.35, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, false, 0)
local Info2 = TweenInfo.new(.15, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, true, 0)

-- blur effect for sprinting dashes, etc

local Blur = game.Lighting:FindFirstChild("RunBlur") or Instance.new("BlurEffect")
Blur.Size = 5
Blur.Name = "RunBlur"
Blur.Enabled = false
Blur.Parent = game.Lighting

-- a variety of tweens I can call upon for various misc things for visual effects like blur increased FOV while running etc

local Tweens = {
	[1] = TS:Create(cam, Info, { FieldOfView = 90 }),
	[2] = TS:Create(cam, Info, { FieldOfView = 70 }),
	[3] = TS:Create(Blur, Info, { Size = 5 }),
	[4] = TS:Create(Blur, Info, { Size = 0 }),
	[5] = TS:Create(hum, Info, { CameraOffset = Vector3.new(0, -1, 0) }),
	[6] = TS:Create(hum, Info, { CameraOffset = Vector3.new(0, 0, 0) }),
	[7] = TS:Create(cam, Info, { FieldOfView = 55 }),
	[8] = TS:Create(hum, Info, { CameraOffset = Vector3.new(0, -1.4, 0) }),
	[9] = TS:Create(Blur, Info2, { Size = 7 }),
	[10] = TS:Create(cam, Info2, { FieldOfView = 95 }),
}

-- animation table that stores all the animations in one place for easy access 

local Anims = {
	Run = animator:LoadAnimation(script:WaitForChild("Run")),
	CrouchWalk = animator:LoadAnimation(script:WaitForChild("CrouchWalk")),
	Crouch = animator:LoadAnimation(script:WaitForChild("Crouch")),
	Dash = animator:LoadAnimation(script:WaitForChild("Dash")),
	Sliding = animator:LoadAnimation(script:WaitForChild("Sliding")),
	Vault = animator:LoadAnimation(script:WaitForChild("Vault")),
	Roll = animator:LoadAnimation(script:WaitForChild("Roll")),
	WallRunL = animator:LoadAnimation(script:WaitForChild("WallRunL")),
	DJ = animator:LoadAnimation(script:WaitForChild("DoubleJump")),
	LJ = animator:LoadAnimation(script:WaitForChild("LongJump")),
	WallRunR = animator:LoadAnimation(script:WaitForChild("WallRunR")),
}

-- setting the priority of certain animations greater than others so they dont interfere with eachother
Anims.CrouchWalk.Priority = Enum.AnimationPriority.Action2
Anims.Dash.Priority = Enum.AnimationPriority.Action2
Anims.Sliding.Priority = Enum.AnimationPriority.Action3
Anims.WallRunL.Priority = Enum.AnimationPriority.Action3
Anims.WallRunR.Priority = Enum.AnimationPriority.Action3
Anims.Sliding.Looped = true

-- variables for if certain loops are active and for double jumping

local sprintLoopActive = false 
local regenLoopActive = false
local JumpDebounce = false
local DoubleJump = false
local Rolling = false 
local YPos  = 0  -- used to calculate player height when attempting a ground roll

shared.Jump = function()  -- function for jumping used to calculate actions playre can take upon space input

	--[[
	If the player is already wallrunning, pressing jump launches them
	-- away from the wall, with more momentum when they are moving faster if
	sliding and not in the air it will performa  long jump animation giving them a burst of speed 
	these 2 stops
	any other actions from being taken during the jump function by returning end
	
	]]--
	
	if WallRunning.Value and WallRunRay then -- if player is wallrunning and there is a ray then
		local speed = hum.WalkSpeed -- get players speed
		local awayFromWall = WallRunRay.Normal -- get the normal direction away from the wall
		-- calculate the velocity to jump away from the wall based on root cframe look position, wall normal , jump force scaled with speed and wall jump up force scaled with speed
		local jumpVelocity = (root.CFrame.LookVector * (35 + (hum.WalkSpeed/4))) +  awayFromWall * (WallJumpAwayForce + (speed/4) * 0.35) + Vector3.yAxis * (WallJumpUpForce + speed * 0.1) 
		char:RemoveTag("L") -- remove the tag for other script detection
		PlaySound("Dash3") -- play wall jump away sound
		
		if root:FindFirstChild("WallRunSound") then -- if there is a wallrun sound playing stilll and not destroyed in the connection
			root.WallRunSound:Destroy() -- destroy wall run
		end
		
		if WallRunConnection then -- if there is a wall run connection
			WallRunConnection:Disconnect() -- disconnect it
			WallRunConnection = nil -- set it to nil
			Anims.WallRunL:Stop() -- stop wall run anims
			Anims.WallRunR:Stop()
		end

		WallRunning.Value = false -- set wall running to false
		WallRunRay = nil -- set the ray to nil
		
		hum.AutoRotate = true -- allow player to rotate again 
		root.AssemblyLinearVelocity += jumpVelocity -- add the calculated velocity to the players velocity
		JumpDebounce = false -- reset jump DB
		ESpeed.Value += 20 -- give player a bit of speed boost
		if Dashes.Value <= 0 then -- if player has no dashes
			Dashes.Value += 1 -- give player a dash
		end
		task.wait(.05)
		lastDoubleJump = -math.huge -- reset last double jump
		return
	elseif Sliding.Value and hum.FloorMaterial ~= Enum.Material.Air then -- prevent long jumping while in air by checking if humanod is on ground
		Sliding.Value = false
		Anims.LJ:Play() -- play slide jump cancel animation long jump thing
		Anims.DJ:Play() -- play double jump anim too so anims stack and cool
		PlaySound("Dash2") -- play dash sound
		ESpeed.Value += 7.5 -- give a bit of additional speed
		root.AssemblyLinearVelocity += (root.CFrame.LookVector * (60 + (hum.WalkSpeed/4) ) + Vector3.yAxis * 80) -- add a boost of speed to the player if on ground to create a long jump effect
		root:AddTag("CanRoll") -- allow for rolling after jump  but dont allow for double jumps immediately after by resetting dj cooldown
		lastDoubleJump = tick()
		JumpDebounce = false
		task.wait(1)
		root:RemoveTag("CanRoll")
		return
	end
	
	-- actions the player can take by jumping
	-- vaulting, wallrunning, rolling on landing from big jumps
	
	-- 2 rays to check for walls that go 9 studs left and right of the player positioned a bit behind  the player 
	local L =  workspace:Raycast(root.Position + Vector3.new(0,0,3),root.CFrame.RightVector * 9,params) 
	local R =  workspace:Raycast(root.Position + Vector3.new(0,0,3),root.CFrame.RightVector * -9,params)
	local ray = L or R -- sets the ray variale to the wall hit ray if one is valid
	local anim = L and Anims.WallRunL or Anims.WallRunR -- sets the animation to the one that matches the wall hit if valid
	local tag = L and "L" or "" -- set a tag for other script detection


	if ray and Sprinting.Value and not WallRunning.Value and hum.FloorMaterial == Enum.Material.Air then
		-- Only wall run if roughly not facing straight into it
	
		local facingWall = math.abs(root.CFrame.LookVector:Dot(ray.Normal))
		if facingWall < 0.65 then -- if wall is not facing enough
			WallRunning.Value = true -- set walling to true
			WallRunRay = ray -- set the ray to the current ray
			 
			char:AddTag(tag) -- tag for other scripts to detect
			anim:Play()
			anim:AdjustSpeed(1 + (hum.WalkSpeed/126)) -- adjust wall run speed depending on players speed
			
			local sound = SFX.Run:Clone() -- cloning instead of using function  because wall run duration isnt set and spede isnt set either
			sound.Parent = root
			sound.PlaybackSpeed = 1 + (hum.WalkSpeed/126) -- adjusting speed dpeneding on players speed
			sound.Looped = true
			sound.Name = "WallRunSound" -- name it so if not destroyed in the heartbeat it can be found in the other thing above
			sound:Play()
			
			hum.AutoRotate = false -- stop player from rotating while wall running just in case if they do it  breaks anything
			
			local function stop()
				anim:Stop() -- stop the animation
				char:RemoveTag("L") -- remove the tag if found
				WallRunning.Value = false -- stop wall running value
				WallRunRay = nil -- set ray to nil

				if WallRunConnection then -- stop the connection disconnect connection
					WallRunConnection:Disconnect()
					WallRunConnection = nil
				end

				hum.AutoRotate = true -- allow player to rotate again

				sound:Destroy() -- destory the sound
			end
		
			local holdDistance = 2.5 -- studs between the root and the wall surface
			local lastDirection = root.CFrame.LookVector -- previous run direction used to keep the flip consistent

			WallRunConnection = RS.Heartbeat:Connect(function(dt) -- runs every frame while wallrunning
				if hum.FloorMaterial ~= Enum.Material.Air then -- player touched the ground
					return stop() -- end the wallrun
				end

				local newRay = workspace:Raycast(root.Position, -WallRunRay.Normal * 14, params) -- recast into the wall we are attached to 14 studs

				if not newRay then -- wall is gone so nothing to run on
					return stop()
				end

				WallRunRay = newRay -- update the ray so the jump function uses the newest wall

				local wallDirection = Vector3.yAxis:Cross(newRay.Normal) -- cross with up gives the direction that points along the wall

				if wallDirection.Magnitude < 0.001 then -- wall is flat like a floor so theres no direction
					return stop()
				end

				wallDirection = wallDirection.Unit -- normalize so its just a direction and speed gets applied later

				if wallDirection:Dot(lastDirection) < 0 then -- compare to last frame instead of the starting look vector
					wallDirection = -wallDirection -- cross can point either way so flip it if its going backwards
				end

				lastDirection = wallDirection -- save it for the next frame check

				-- turn the character to face along the wall lerped smoothed so it doesnt snap
				local pos = root.Position -- current position so the turn doesnt move the player
				local targetCFrame = CFrame.lookAt(pos, pos + wallDirection) -- cframe at the same spot but looking down the wall
				root.CFrame = root.CFrame:Lerp(targetCFrame, math.min(dt * 12, 1)) -- lerp toward it and min stops it going past 1 on a laggy frame

				-- pull toward holdDistance instead of always pushing in and negative values push away if too close
				local stickSpeed = math.clamp((newRay.Distance - holdDistance) * 10, -20, WallStickForce) -- how far from the ideal distance times 10 clamped so it cant be too strong either way

				local wallSpeed = 50 + hum.WalkSpeed -- base run speed plus walkspeed so it follows speed changes live
				local downwardVelocity = -17 -- slow slide down the wall so the player doesnt stay on one y level

				root.AssemblyLinearVelocity = wallDirection * wallSpeed - newRay.Normal * stickSpeed + Vector3.new(0, downwardVelocity, 0) -- run along the wall plus the stick in or out plus the downward drift
			end)
			
			JumpDebounce = false
			return
		end

	
	elseif hum.FloorMaterial == Enum.Material.Air and ( (YPos - root.Position.Y) > 10 or root:HasTag("CanRoll") ) then -- if the humanoid is in the air and YHeight is greater than 10 allow them to roll
		local ray = workspace:Raycast(root.Position, root.CFrame.UpVector * -60, params) -- ray 60 studs downwards with params

		if ray and not Rolling then -- theres a floor below us and  arent already waiting to roll
			Rolling = true -- lock it so this cant stack multiple loops while were still falling if player keeps pressing jump

			local rollHeight = 13 -- how many studs above the ground the roll will start
			local rollConnection -- connection for loop

			rollConnection = RS.Heartbeat:Connect(function() -- check every frame so the roll triggers the moment were close enough, no waiting for floor material

				-- short ray straight down, as long rollheight so a hit means were close enough
				local groundRay = workspace:Raycast(root.Position, Vector3.new(0, -rollHeight, 0), params)

				if not groundRay then -- still too high up so keep waiting
					return
				end
				
				PlaySound("Roll") -- play roll sound
				Anims.Roll:Play() -- play roll animation
				Anims.Roll:AdjustSpeed(2) -- making it faster because 1 is too slow
				char:AddTag("Roll") -- tag for other scripts
				root.AssemblyLinearVelocity += (root.CFrame.LookVector * 65) -- push forward out of the roll
				ESpeed.Value += 7.5 -- extra speed boost from the roll

				task.delay(.3, function() -- after ,3s
					char:RemoveTag("Roll") -- remove roll tag for other scripts
					Rolling = false -- can roll again
				end)
				
				rollConnection:Disconnect() -- stop checking
				rollConnection = nil
				
			end)
		end
	else
		local forward = root.CFrame.LookVector -- vaulting logic this is forward look direction

		-- Check for an obstacle in front of the player
		local wallResult = workspace:Raycast(root.Position - Vector3.new(0, 3, 0),forward * 6,params)

		if wallResult then -- theres a wall
		
			-- Make sure theres  space above the wall that the player can go on 
			local cleard = workspace:Raycast(root.Position + Vector3.new(0, 3, 0),forward * 6,params)

			if not cleard then -- if there is no obstacle continue play vault sound and animation
				PlaySound("Vault")
				Anims.Vault:Play()

				-- Move the player over the obstacle by giving them small boost of speed
				root.AssemblyLinearVelocity += (forward *65 + Vector3.new(0, 70, 0))
				ESpeed.Value += 5
			
				return
			end

		end
	
	end	
	
end

shared.Slide = function() -- slide function
	Sliding.Value = true -- set sliding to true
	Anims.Sliding:Play() -- play sliding animation
	
	local UP = Vector3.new(0, 1, 0) -- what direction upwards is in a vector
	
	local S1,S2  = SFX.SlidingAmbience:Clone(),SFX.Sliding:Clone() -- same logic here as wall running sound but 2 sounds one is wind and actual slide
	S1.Parent = root S2.Parent = root
	S1:Play() S2:Play()
	
	local speed = 60 + hum.WalkSpeed -- starting slide speed scales with current walking speed
	local minSpeed = 15 -- the minimum speed needed for slide
	local maxSpeed = 300 -- the maximum speed slide can go to

	local maxSlopeAngle = 10 -- the maximum slope angle that can be slid down
	local accel = 75 -- rate of acceleration for slide
	local decel = 60 -- rate of deceleration for slide
	
	local addedspd = 0 -- additional speed player get from slide
	local connection
	
	-- disable certain humanoid states so they dont interfere with the sliding physics
	root.CanCollide =false
	Tweens[8]:Play()
	
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false)
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Physics,false)


	local function cleanup() 
		-- cleanup function that stops the slide, disconnects the slide connection so the sliding code stops working
		-- stops sliding animation and sets sliding to false to resume that the  other movement states are possible  and lets the disabled states become able to be switched to again
		-- because sliding isnt happening they can be enabled again 
		
		if connection then -- if connection is there still disconnect it
			connection:Disconnect()
			connection = nil
		end
		
		if S1.Parent or S2.Parent then -- if sound is playing still stop it
			S1:Destroy()
			S2:Destroy()
		end
		
		Tweens[6]:Play() -- smooth reset of camera offset
		Anims.Sliding:Stop() -- stop animation
		Sliding.Value = false -- set sliding to false
		
		-- reset humanoid states to allow for normal movement again
		
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,true)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown,true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Physics,true)
		hum:ChangeState(Enum.HumanoidStateType.Running)
		
		ESpeed.Value -= addedspd -- get rid of the added speed from sliding but still keep some additional speed due to the rate added speed is calculated in connection function thing
		root.CanCollide = true -- allow collisions on root for bigger hitbox since not sliding
	end

	connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not Sliding.Value then -- if not sliding then stop everything
			cleanup()
			return
		end

		local result = workspace:Raycast(root.Position, Vector3.new(0, -9, 0), params) -- cast a ray going 9 studs downwards from the players current position

		local moveDir = root.CFrame.LookVector -- what dir the player is moving
		local groundNormal -- the surface normal of the ground
		local slopefound = false -- s it a slope
		local goingUp = false -- is the player going up or down the slope
		
				local stickDown = -25
		
		if result then -- found ground
			groundNormal = result.Normal  -- the surface normal of the ground
			
			local slopeAngle = math.deg(math.acos(math.clamp(groundNormal:Dot(UP), -1, 1))) -- the angle of the slope  dot gives angle between the ground normal and UP vector
			-- acos converts that angle into radians measurement, deg converts radians to degrees so its easy to compare angles
			-- Clamp keeps the value between -1 and 1 to prevent errorsince cos cant exceed 1

			if slopeAngle >= maxSlopeAngle then -- if the slope angle is greater than the max slope angle then the player is on a slope
				slopefound = true

				-- Find the direction pointing downhill from the slope
				local downhill = UP - groundNormal * groundNormal:Dot(UP)

				if downhill.Magnitude > 0.001 then -- make direction is valid 
					downhill = downhill.Unit -- the normalize direction

					-- Compare the player's movement direction to downhill
					local dot = moveDir:Dot(downhill)

					if dot > 0.1 then -- if the player is moving in the downhill direction
						goingUp = false -- moving downhill
					elseif dot < -0.1 then
						goingUp = true -- moving uphill
					end
				end
				
			end
			
		end

		if slopefound and result then
			if goingUp == false then
				stickDown = -25
				speed -= accel * dt -- slow down while going downhill
			else
				stickDown = -105 -- increased stick down speed
				speed += accel * dt -- speed up while going uphill
				addedspd += (accel * dt)/8 -- increase total added speedby a smaller amount
				ESpeed.Value += (accel * dt)/1.25 -- increase extra speed  while going down
			end
		elseif result then
			stickDown = -25
			speed -= decel * dt -- slow down when not on a slope
			addedspd += (accel * dt)/2.6 -- increase total added speed
			ESpeed.Value += (accel * dt)/1.4  -- increase extra speed 
		else
			speed += (25 * dt) -- slow speed up if no grond
		end

		-- Keep speed within the allowed maxrange
		speed = math.clamp(speed, minSpeed, maxSpeed)

		local finalDir = moveDir

		if result and groundNormal then
			-- Project movement direction onto the slope so movement follows its surface
			local projected = moveDir - groundNormal * moveDir:Dot(groundNormal)

			if projected.Magnitude > 0.001 then -- make sure the direction is valid
				finalDir = projected.Unit
			end
		end

		local currentVel = root.AssemblyLinearVelocity	
		local horizontalVel = finalDir * speed -- Convert the movement direction and speed into horizontal velocity

		-- Force the player toward the ground to help keep them attached to slopes
		S1.PlaybackSpeed = (speed/60) S2.PlaybackSpeed  = (speed/90)
		-- preserve downward velocity thing from curernt velocity, but never allow it above -25
		root.AssemblyLinearVelocity = Vector3.new(horizontalVel.X,math.min(currentVel.Y, stickDown),horizontalVel.Z)

		-- Stop slide if too slow
		if speed <= minSpeed then
			cleanup()
			return
		end
	end)
end

shared.Crouch = function() -- crouch function also decides if the player should slide instead of crouch

	--[[
	if the player is wallrunning then stop because they cant crouch
	if theyre sprinting and moving it starts a slide instead of a crouch
	otherwise it toggles crouching pressing it while crouched stands them back up
	and pressing while standing crouches them slows them down and plays idle crouch animation
	]]--

	if WallRunning.Value then return end -- cant crouch while wallrunning so just stop
	if not Sliding.Value and Sprinting.Value and  hum.MoveDirection.Magnitude > .5 then -- not already sliding sprinting and actually moving .5 so tiny input dosnt count
		shared.Slide() -- start slide instead of crouching
		return -- stop here so it doesnt crouch aswell
	end

	if Crouching.Value == true then -- already crouching so this press means stand up
		Crouching.Value = false -- not crouching anymore
		CTSpeed(WalkSpeed) -- set speed back to normal walkspeed

		Anims.Run:Stop() -- stop run anim just incase its stilll playing
		Anims.CrouchWalk:Stop() -- stop the moving crouch anim
		Anims.Crouch:Stop() -- stop idle crouch anim

		root.CanCollide = true -- collisions back on for bigger hitbox since standing

		Tweens[4]:Play() -- play the tweens that smooth everything back to standing 
		Tweens[2]:Play()
		Tweens[6]:Play() -- smooth reset of camera offset
		return -- done standing up so end
	end

	Sprinting.Value = false -- crouching cancels sprint
	Crouching.Value = true -- now crouching

	root.CanCollide = false -- collisions off for smaller hitbox while crouched
	CTSpeed(CrouchSpeed) -- set speed to the slower crouch speed
	Tweens[4]:Play() -- tweens that smooth into the crouch
	Tweens[2]:Play()
	Tweens[5]:Play() -- crouch version of the camera offset tween
	Anims.Run:Stop() -- stop run anim cuz not running anymore
	Anims.Crouch:Play() -- play idle crouch anim

	if hum.MoveDirection.Magnitude > .5 then -- if player is moving while crouching aswell
		Anims.CrouchWalk:Play() -- play crouch walk anim on top so they walking
	end
end

shared.Sprint = function()
	-- sprint function handles normal sprinting and sprinting while crouched also drains stamina and allows for wallrunning and stuff

	--[[
	if the player is already sprinting or the sprint loop is already running or theres barely any stamina
	nothing happens
	if crouching it does a crouch sprint which is slower otherwise a normal sprint
	both of them drain stamina in a loop untill the player stops moving or runs out of stamina or stops sprinting
	then it calls stopsprint to reset everything
	]]--

	if Sprinting.Value or sprintLoopActive or Stamina.Value <= 3 then -- already sprinting or loop already going or not enough stamina so they cant sprint on nothing
		return -- stop here
	end

	if Crouching.Value then -- crouch sprint logic
		sprintLoopActive = true -- lock it so this cant stack loops
		Sprinting.Value  =true -- now sprinting
		CTSpeed(CrouchSprint) -- set base speed to crouch sprint speed
		Blur.Size = 0 -- start the blur from nothing so it can tween in
		Blur.Enabled = true -- turn the blur on for the speed effect
		Tweens[3]:Play() -- blur tween
		Tweens[7]:Play() -- the crouch sprint version of the other tween FOV

		while Sprinting.Value and hum.MoveDirection.Magnitude > .5 and Stamina.Value > 0 do -- keep going while sprinting and moving and still got stamina
			Stamina.Value = math.clamp(Stamina.Value - .35, 0, 100) -- drain stamina and clamp so it dosnt go below 0 or over 100
			task.wait(.12) -- wait a bit so its not draining every frame
		end
		sprintLoopActive = false -- loop is done so it can be started again


		if Crouching.Value then -- if still crouching after the sprint
			hum.WalkSpeed = CTSpeed(CrouchSpeed) -- go back to crouch speed
		else
			hum.WalkSpeed  = CTSpeed(WalkSpeed) -- otherwise stood up so normal walkspeed
		end

		if Sprinting.Value then -- if sprinting value is still true from running out of stamina or stopped moving
			shared.StopSprint() -- stop the sprint properly
		end

		return -- done so dont run the normal sprint below
	end

	Sprinting.Value = true -- normal sprint starts here now sprinting

	hum.WalkSpeed = CTSpeed(RunSpeed) -- set speed to the run speed
	Blur.Size = 0 -- blur starts at 0 same as crouch sprint
	Blur.Enabled = true -- turn blur on
	Tweens[3]:Play() -- blur tween
	Tweens[1]:Play() -- normal sprint tween
	Anims.CrouchWalk:Stop() -- stop crouch anims incase they were playing
	Anims.Crouch:Stop()
	Anims.Run:Play() -- play the run anim

	sprintLoopActive = true -- start the loop
	
	while Sprinting.Value and hum.MoveDirection.Magnitude > .5 and Stamina.Value > 0 do -- same conditions as the crouch one
		Anims.Run:AdjustSpeed(hum.WalkSpeed/RunSpeed) -- adjut run animation speed depending on how fast player going if they going at 52 speed the animation will play 2x faster
		if Sliding.Value then -- if sliding drain less stamina
			Stamina.Value = math.clamp(Stamina.Value + -.25, 0, 100) -- slide drain smaller so sliding feels good
		else
			Stamina.Value = math.clamp(Stamina.Value - .45, 0, 100) -- normal sprint drain bigger than crouch sprint
		end

		task.wait(.12) -- drain stamina every .12 seconds
	end
	
	sprintLoopActive = false -- loop finished

	if Sprinting.Value then -- if sprinting value is still true stop it
		shared.StopSprint()
	end
end

shared.StopSprint = function() -- stops the sprint and regens stamina after

	Sprinting.Value = false -- not sprinting anymore
	Tweens[2]:Play() -- tween that resets the sprint effects
	Anims.Run:Stop() -- stop run anim
	if Crouching.Value then -- if crouching go back to crouch speed
		CTSpeed(CrouchSpeed) 
	else CTSpeed(WalkSpeed) -- otherwise normal walkspeed

	end
	Tweens[4]:Play() -- tween that smooths back to normal

	if regenLoopActive then -- regen already going so dont start another one
		return
	end

	regenLoopActive = true -- lock regen so it cant stack
	while Sprinting.Value == false and Stamina.Value < 100 do -- regen untill full or player starts sprinting again
		Stamina.Value = math.clamp(Stamina.Value + .5, 0, 100) -- add stamina clamp so it stops at 100
		task.wait(.03) -- regen is faster than the drain because its waiting less
	end
	regenLoopActive = false -- regen done so it can start again
end

shared.Dash = function() 
	-- dash function launches the player forward where the camera is looking

	--[[
	uses up a dash charge then plays the dash effects and adds a short burst of velocity in the cam direction
	while its happening the ragdoll type states are disabled so physics affect the dash less if they dash into the ground or smth
	after a short time they get turned back on and the dash charge comes back after a cooldown
	]]--

	if Dashes.Value <= 0 then return end -- no dashes left so stop
	Tweens[9]:Play() -- dash tweens for the camera stuff
	Tweens[10]:Play()

	Sliding.Value = false -- if sliding stop slide to allow for dash
	Dashes.Value -= 1 -- use up a dash charge

	PlaySound("Dash") -- play dash sound
	Anims.Dash:Play() -- play dash anim

	local Distortion = VFX.Distortion:Clone() -- clone the distortion effect part so it can be used for the dash visual
	Distortion.Size = Vector3.new(15,15,15) -- starting size
	Distortion.Anchored = true -- anchored so it dosnt fall its moved by cframe below
	Distortion.CanCollide = false -- no collision so it dosnt push anything
	Distortion.CastShadow = false -- no shadow since its just an effect
	Distortion.Parent = workspace -- put it in the workspace so its visible
	Distortion.Transparency = 5 -- starts really transparent for greater distortion

	game.Debris:AddItem(Distortion,.16) -- destroy it after .16s

	TS:Create(Distortion,TweenInfo.new(.15),{Size = Vector3.new(20,20,20);Transparency = 1;}):Play() -- tween it bigger and distortion becomes less

	local Direction = cam.CFrame.LookVector -- direction the dash goes where the camera is looking
	local temp -- connection for the distortion following the camera

	temp = RS.RenderStepped:Connect(function() -- every frame so it follows the camera smoothly
		Distortion.CFrame =cam.CFrame * CFrame.new(0,0,-2) -- keep the distortion 2 studs infront of the camera
	end)

	local attachment = Instance.new("Attachment") -- attachment is needed for the linear velocity
	attachment.Parent = root

	local DashVelocity = Instance.new("LinearVelocity") -- linear velocity to actually push the player
	DashVelocity.Attachment0 = attachment -- connect it to the attachment
	DashVelocity.VectorVelocity = Direction * 100 -- dash speed in the direction from above
	DashVelocity.MaxForce = math.huge -- infinite force so nothing stops the dash
	DashVelocity.Parent = root

	game.Debris:AddItem(DashVelocity,.2) -- remove the velocity after .2s so the dash ends
	game.Debris:AddItem(attachment,.2) -- and the attachment aswell
	ESpeed.Value += 50 -- big extra speed boost for the dash

	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false) -- disable these states so they dont interfere with the dash
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Physics,false)

	task.delay(.25,function() -- after .25s the dash is over so reset everything
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,true) -- turn the states back on
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown,true)
		hum:SetStateEnabled(Enum.HumanoidStateType.Physics,true)

		temp:Disconnect() -- stop the distortion following the camera
		temp = nil
		ESpeed.Value -= 35 -- take away most of the dash speed but keep 15 of it as extra momentum
		YPos = root.Position.Y + 50 -- set y pos so player can roll after dasj
		task.wait(2.75) -- dash cooldown
		if Dashes.Value < 2 then -- make sure no wall jump dash was given
			Dashes.Value += 1 -- give the dash charge back
		end
		
	end)


end

hum:GetPropertyChangedSignal("MoveDirection"):Connect(function() -- runs whenever the players move direction changes so the crouch walk anim can follow it
	if Crouching.Value == true and hum.MoveDirection.Magnitude > .5 and not Anims.CrouchWalk.IsPlaying then -- crouching and moving and the anim isnt already playing
		Anims.CrouchWalk:Play() -- start the crouch walk anim
	elseif hum.MoveDirection.Magnitude < .5 and Crouching.Value == true and Anims.CrouchWalk.IsPlaying then -- crouching but stopped moving and the anim is still playing
		Anims.CrouchWalk:Stop() -- stop it so they go back to the idle crouch
	end
end)

UIS.InputBegan:Connect(function(inp, processed) 
	-- input handler for all the movement keys

	--[[
	c or left control crouches or slides
	double tapping w sprints
	left shift dashes
	space jumps which also does wallrun and vault and roll and long jump depending on whats happening
	]]--

	if processed then -- if the game already used the input like typing in chat
		return -- stop so keys dont do stuff while typing
	end

	if inp.KeyCode == Enum.KeyCode.C or inp.KeyCode == Enum.KeyCode.LeftControl then -- crouch keys
		shared.Crouch()
	elseif inp.KeyCode == Enum.KeyCode.W then -- w for the double tap sprint

		if tick() - LastWPress < .35 then -- last w press was less than .35s ago so its a double tap
			task.wait(.07) -- tiny wait before sprinting so humanoid movement magnitude can kick in
			shared.Sprint()
		end
		LastWPress = tick() -- save the time of this press for the next check

	elseif inp.KeyCode == Enum.KeyCode.LeftShift then -- dash key
		shared.Dash()
	elseif inp.KeyCode == Enum.KeyCode.Space and not JumpDebounce then -- jump key and only if the jump debounce isnt on
		JumpDebounce = true task.delay(.1,function() JumpDebounce = false end) -- turn debounce on then off after .1s so jump cant be spammed
		shared.Jump()
	end
end)

UIS.InputEnded:Connect(function(inp, processed) -- runs when a key is let go
	if processed then -- same as above ignore game processed input
		return
	end
	if inp.KeyCode == Enum.KeyCode.C or inp.KeyCode == Enum.KeyCode.LeftControl then -- crouch key was released
		if Sliding.Value then Sliding.Value = false return end -- if sliding then letting go ends the slide
	end

end)

local SpeedFX = VFX.SpeedFX:Clone() -- clone the speed effect part so each player gets their own
SpeedFX.Parent = workspace -- put it in the workspace so its visible
for i,v in pairs(SpeedFX:GetChildren()) do v.Rate = 0 v.Enabled = true end -- turn every emitter on but with rate 0 so nothing shows untill speed is high

local w  = Instance.new("Weld") -- weld to hold the speed effect infront of the player
w.Part0 = SpeedFX -- the effect part
w.Part1 = root -- stuck to the players root
w.C0 = CFrame.new(0,0,50) -- offset it 50 studs away so the lines come from a distance
w.Parent = root

local rate = .1 -- always decay .1 speed
local percent = 0.01 -- 1/100 fraction of current speed lost per second
local fxThreshold = 25   -- fx threshold so speedlines only appear above this
local clonetime = .15 -- how long clones will last


ESpeed.Changed:Connect(function() -- runs whenever the extra speed changes
	if Disappating then return end -- decay loop already running so dont start another one
	Disappating = true -- lock loop

	local line1, line2 = SpeedFX.Line1, SpeedFX.Line2 -- the 2 speed line emitters

	while ESpeed.Value > 0 do -- while d there is additional extra speed loop
		local t = task.wait(0.05) -- returns the real elapsed time over 0.05 duration as task.wait()  can lag and end up being longer or shorter
		-- multiply by t * 20 to get the elapsed the proper decay if t is like .508 decay will be slightly more if its exactly .5 it'll be normal decay rate
		moosic.Volume = math.clamp( (hum.WalkSpeed/100) - .3,0,.6) -- music gets louder the faster the player is and clamped so its not too quiet or too loud

		ESpeed.Value = math.clamp(ESpeed.Value - ((rate * (t * 20)) + (ESpeed.Value * (percent * (t * 20)))),0,1e9)
		-- take away the flat decay plus the percent decay scaled by  time  passed and never go below 0
		hum.WalkSpeed = CurrentSpeed + ESpeed.Value -- walkspeed is the normal speed plus whatever extra is left

		local rate = ESpeed.Value > fxThreshold and (ESpeed.Value - fxThreshold) * 1.5 or 0 -- speed lines get more the further past the threshold and none if under it
		line1.Rate = rate -- apply it to both emitters
		line2.Rate = rate


		if  ESpeed.Value > 55 then -- only make afterimages when really fast
			local ghost = Instance.new("Folder") -- folder to hold all parts for cleanup

			for _, v in ipairs(char:GetChildren()) do -- loop through each character part
				if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then -- look for limbs but no root part
					local p = v:Clone() -- copy the part

					for _, c in ipairs(p:GetChildren()) do -- strip everything except the mesh
						if not c:IsA("SpecialMesh") then
							c:Destroy() --if not mesh then destroy it
						end
					end

					local mesh = p:FindFirstChildOfClass("SpecialMesh")
					if mesh then mesh.TextureId = "" end -- no texture so the neon colour shows properly
					if p:IsA("MeshPart") then p.TextureID = "" end

					p.Anchored = true -- stays where the player was
					p.CanCollide = false -- no collision so it doesnt push anything
					p.CanQuery = false -- raycasts ignore it so it doesnt mess up wallrun or roll rays
					p.CanTouch = false -- no touch events
					p.CastShadow = false -- glow shouldnt cast shadows
					p.Size *= 1.08 -- slightly bigger than the real part so it looks like a glow

					p.Material = Enum.Material.Neon -- neon so its glowy
					p.Color = Color3.fromRGB(120, 200, 255) -- light blue afterimage colour
					p.Transparency = 0.5 -- start at half transparency
					p.Parent = ghost -- set parent to folder for cleanup
					
					TS:Create(p,  TweenInfo.new(clonetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1}):Play() -- fade out over its lifetime
				end
			end
			
			clonetime = 0.15 + (hum.WalkSpeed/150) -- increase clone lifetime based on player speed
			ghost.Parent = workspace.FX -- put the ghost in the workspace so player can see
			game.Debris:AddItem(ghost, clonetime + 0.1) -- destroy it a bit after it fades so nothing is left behind
			
		end
	end

	line1.Rate = 0 -- extra speed is gone so turn the lines off
	line2.Rate = 0
	Disappating = false -- stop disappating so set to false so the loop can start again
end)

UIS.JumpRequest:Connect(function() -- runs when the player presses jump
	-- track the first jump

	if not firstjump then -- the player hasnt attempted first jump yet
		firstjump = true -- first jump is true
		task.delay(0.15, function()
			YPos = root.Position.Y -- set y pos a bit after jump is done
		end)
		return
	end

	-- first jump is already true so this is for the double jump 
	if os.clock() - lastDoubleJump < cooldown or hum.FloorMaterial ~= Enum.Material.Air or Sliding.Value or WallRunning.Value  then return end -- stop if double jump is on cooldown or on the ground or sliding or wallrunning
	lastDoubleJump = os.clock() -- save the time for the cooldown

	PlaySound("Dash2") -- play the dash sound

	hum.JumpPower = 65 -- set jump a bit stronger than first
	Anims.DJ:Play() -- play double jump anim(vault cuz it looks like a double jump)
	char:AddTag("Roll") -- roll tag so other scripts know they can roll after this

	hum:ChangeState(Enum.HumanoidStateType.Jumping) -- change state to jumping to mimic a jump 

	task.delay(0.15, function() 
		char:RemoveTag("Roll") -- remove the roll tag
		hum.JumpPower = 50 -- reset jump power
		YPos = root.Position.Y -- set y pos again so the fall height starts from the double jump
	end)
end)

hum:GetPropertyChangedSignal("FloorMaterial"):Connect(function() -- when standing material of humanoid changes
	if hum.FloorMaterial ~= Enum.Material.Air then -- if they arent in the air
		firstjump = false -- reset the first jump
	end
end)
