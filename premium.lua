-- Premium modules for AetherCoreV2.
-- These modules are split out of games/6872274481.lua for premium-only delivery.

run(function()
    local TritonClutch
    local Legit
    local Back
    local LandCheck
    local BackDelay
    local Limit
    local Recall

    local rayCheck = RaycastParams.new()
    rayCheck.RespectCanCollide = true
    rayCheck.FilterType = Enum.RaycastFilterType.Include
    local projectileRemote = {InvokeServer = function() end}
    task.spawn(function()
	projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)

    local harpoonAbilities = {'harpoon', 'HARPOON', 'harpoon_throw', 'HARPOON_THROW', 'triton_harpoon', 'TRITON_HARPOON'}
    local virtualInputManager = cloneref(game:GetService('VirtualInputManager'))

    local function isHarpoonTool(tool)
	local name = tool and tool.Name and tool.Name:lower()
	return name == 'harpoon' or name == 'trident' or name == 'triton_harpoon'
    end

    local function clickHeldHarpoon(target)
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local before = #store.selfProjectiles
	local viewport = camera.ViewportSize
	local original = camera.CFrame
	pcall(function()
		camera.CFrame = CFrame.lookAt(original.Position, target)
	end)
	virtualInputManager:SendMouseButtonEvent(viewport.X / 2, viewport.Y / 2, 0, true, game, 0)
	task.wait()
	virtualInputManager:SendMouseButtonEvent(viewport.X / 2, viewport.Y / 2, 0, false, game, 0)

	local started = tick()
	repeat
		if #store.selfProjectiles > before then
			return true
		end
		task.wait()
	until tick() - started > 0.25
	return false
    end

    local function waitForHarpoonClutch()
	local started = tick()
	repeat
		task.wait()
		local root = entitylib.isAlive and entitylib.character.RootPart
		if root and root.Velocity.Y > -10 then
			return true
		end
	until not TritonClutch.Enabled or tick() - started > 3
	return false
    end

    task.spawn(function()
	local success, abilityIds = pcall(function()
		return require(replicatedStorage.TS.ability['ability-id']).AbilityId
	end)
	if success then
		for _, ability in abilityIds do
			local lowered = tostring(ability):lower()
			if lowered:find('harpoon', 1, true) then
				table.insert(harpoonAbilities, ability)
			end
		end
	end
    end)

    local function useAbility(list, payloads)
	for _, ability in list do
		local allowed = true
		pcall(function()
			allowed = not bedwars.AbilityController.canUseAbility or bedwars.AbilityController:canUseAbility(ability)
		end)

		if allowed then
			for _, data in payloads do
				local success, result = pcall(function()
					return bedwars.AbilityController:useAbility(ability, newproxy(true), data)
				end)
				if success and result ~= false then
					return true
				end

				success, result = pcall(function()
					return bedwars.AbilityController:useAbility(ability, data)
				end)
				if success and result ~= false then
					return true
				end

				pcall(function()
					bedwars.Client:Get(remotes.UseAbility).instance:FireServer(ability, data)
				end)
			end
		end
	end
	return false
    end

    local function fireHarpoonProjectile(pos, spot, item)
	local projectileType = 'harpoon_projectile'
	local meta = bedwars.ProjectileMeta[projectileType]
	if not meta then
		return false
	end

	local launchVelocity = meta.launchVelocity or 160
	local gravity = meta.gravitationalAcceleration or 0
	local calc = prediction.SolveTrajectory(pos, launchVelocity, gravity, spot, Vector3.zero, workspace.Gravity, 0, 0) or spot
	local dir = CFrame.lookAt(pos, calc).LookVector * launchVelocity
	local shotId = httpService:GenerateGUID(false)
	local landed = false
	local projectile

	pcall(function()
		projectile = bedwars.ProjectileController:createLocalProjectile(meta, projectileType, projectileType, pos, nil, dir, {drawDurationSeconds = 1})
	end)

	if projectile then
		task.spawn(function()
			repeat
				task.wait()
			until not projectile or not projectile.Parent
			landed = true
		end)
	end

	local success, result = pcall(function()
		return projectileRemote:InvokeServer(
			item.tool,
			projectileType,
			projectileType,
			pos,
			pos,
			dir,
			httpService:GenerateGUID(true),
			{
				drawDurationSeconds = 1,
				shotId = shotId
			},
			workspace:GetServerTimeNow() - 0.045
		)
	end)

	return success and result ~= nil, function()
		local started = tick()
		repeat
			task.wait()
		until landed or not TritonClutch.Enabled or tick() - started > 3
		return landed
	end
    end

    local function useHarpoon(pos, spot, item)
	local hotbar, old = getHotbar(item.tool), store.hand
	switchItem(item.tool)
	if Legit.Enabled and hotbar then
		hotbarSwitch(hotbar)
	end

	local used, clutchCheck
	if clickHeldHarpoon(spot) then
		clutchCheck = waitForHarpoonClutch
		used = true
	else
		used, clutchCheck = fireHarpoonProjectile(pos, spot, item)
	end

	if not used then
		used = useAbility(harpoonAbilities, {
			{target = spot, origin = pos},
			{targetPosition = spot, position = pos},
			{position = spot},
			spot
		})
		clutchCheck = waitForHarpoonClutch
	end
	if used and Recall.Enabled then
		task.spawn(function()
			task.wait(1.25)
			virtualInputManager:SendKeyEvent(true, Enum.KeyCode.C, false, game)
			task.wait()
			virtualInputManager:SendKeyEvent(false, Enum.KeyCode.C, false, game)
		end)
	end

	if Back.Enabled and LandCheck.Enabled and clutchCheck then
		clutchCheck()
	end
	if Back.Enabled and old and old.tool then
		if used and old.tool ~= item.tool then
			task.wait(10)
		end
		task.wait(BackDelay:GetRandomValue())
		switchItem(old.tool)
		if Legit.Enabled and getHotbar(old.tool) then
			hotbarSwitch(getHotbar(old.tool))
		end
	end
    end

    local function findNearGround(origin)
	for _, v in {Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1)} do
		for i = 1, 24 do
			local ray = workspace:Raycast((origin.Position + (Vector3.yAxis * 3)) + (v * i), Vector3.new(0, -60, 0), rayCheck)
			if ray then
				return ray.Position
			end
		end
	end
	return nil
    end

    TritonClutch = vape.Categories.Utility:CreateModule({
	Name = 'TritonClutch',
	Function = function(callback)
		if callback then
			local check, lasty
			repeat
				if entitylib.isAlive and (not Limit.Enabled or isHarpoonTool(store.hand.tool)) then
					local root = entitylib.character.RootPart
					local harpoon = getItem('harpoon')
					rayCheck.FilterDescendantsInstances = {store.map}
					rayCheck.CollisionGroup = root.CollisionGroup

					if entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air then
						lasty = root.CFrame
					end

					if harpoon and root.Velocity.Y < -100 and not workspace:Raycast(root.Position, Vector3.new(0, -200, 0), rayCheck) then
						if not check then
							check = true
							local ground = findNearGround(root.CFrame + Vector3.new(0, 40, 0)) or findNearGround(lasty and lasty + Vector3.new(0, 5, 0) or root.CFrame)
							if ground then
								useHarpoon(root.Position, ground, harpoon)
							end
						end
					else
						check = false
					end
				end
				task.wait(0.1)
			until not TritonClutch.Enabled
		end
	end,
	Tooltip = 'Automatically throws Triton\'s harpoon onto nearby ground after\nfalling a certain distance.'
    })

    Legit = TritonClutch:CreateToggle({
	Name = 'Legit Switch',
	Tooltip = 'Visualizes the switching clientside',
	Default = true
    })
    Back = TritonClutch:CreateToggle({
	Name = 'Switch back',
	Default = true,
	Function = function(callback)
		if BackDelay then
			BackDelay.Object.Visible = callback
		end
		if LandCheck then
			LandCheck.Object.Visible = callback
		end
	end,
	Tooltip = 'Switches back to the last slot before the harpoon clutch'
    })
    LandCheck = TritonClutch:CreateToggle({
	Name = 'Only after clutch',
	Tooltip = 'Only switches back after the harpoon clutch activates',
	Darker = true
    })
    BackDelay = TritonClutch:CreateTwoSlider({
	Name = 'Switch Back Delay',
	Min = 0,
	Max = 2,
	DefaultMin = 0.1,
	DefaultMax = 0.2,
	Darker = true
    })
    Limit = TritonClutch:CreateToggle({
	Name = 'Limit to items',
	Tooltip = "Only throws Triton's harpoon when holding the harpoon or trident"
    })
    Recall = TritonClutch:CreateToggle({
	Name = 'Recall',
	Tooltip = 'Presses C to activate Recall / Go to base after clutching'
    })
end)

run(function()
    local InstantKill
    local Mode
    local Range
    local Place

    local function getTurret(localPosition)
        for _, v in store.blocks do
            if v.Name == 'camera_turret' and v:GetAttribute('PlacedByUserId') == lplr.UserId and (localPosition - v.Position).Magnitude <= 30 then
                return v
            end
        end
        return nil
    end

    local function getPlacedPosition(pos)
        for _, v in {Vector3.new(3, 0, 0), Vector3.new(0, 0, 3)} do
            for i = 1, 10 do
                local ray = workspace:Blockcast(CFrame.new(pos + (v * i)), Vector3.new(3, 3, 3), Vector3.new(0, -30, 0), store.airRay)
                if ray and not getPlacedBlock(ray.Position) then
                    return roundPos(ray.Position)
                end
            end
        end
        return
    end

    InstantKill = vape.Categories.Blatant:CreateModule({
        Name = 'InstantKill',
        Function = function(callback)
            if callback then
                repeat task.wait() until store.matchState ~= 0 or not InstantKill.Enabled
                if not InstantKill.Enabled then return end
                if store.equippedKit ~= 'vulcan' then
                    notif('InstantKill', 'You need vulcan equipped for this!', 8, 'warning')
                    return
                end

                local delay, pickups = 0, {}
                repeat
                    if entitylib.isAlive and tick() > delay then
                        local localPosition = entitylib.character.RootPart.Position
                        local ent = entitylib.EntityPosition({
                            Origin = localPosition,
                            Range = Range.Value,
                            Part = 'RootPart',
                            Players = true,
                            Wallcheck = true,
                            Sort = sortmethods.Health,
                        })
                        if ent then
                            local turret = getTurret(localPosition)
                            local tablet = getItem('tablet')
                            if not turret and Place.Enabled then
                                local pos = getPlacedPosition(localPosition)
                                local item = getItem('camera_turret')
                                if pos and item then
                                    bedwars.placeBlock(pos, 'camera_turret', false)
                                    turret = getPlacedPosition(pos)
                                    if turret then
                                        table.insert(pickups, turret)
                                    end
                                end
                            end
                            if turret and tablet then
                                switchItem(tablet.tool)
                                for i = 1, 12 do
                                    task.spawn(function()
                                        bedwars.Client:Get('VulcanArtilleryMark'):CallServer(ent.Player)
                                    end)
                                end
                                delay = tick() + 2
                            end
                        end
                    end
                    if Mode.Value == 'On bind' then
                        if #pickups > 0 then
                            task.wait(0.1)
                            for _, v in pickups do

                            end
                        end
                        InstantKill:Toggle()
                        break
                    end
                    task.wait(0.1)
                until not InstantKill.Enabled
            end
        end,
        Tooltip = 'Automatically uses turret to instant kill targets.'
    })

    Mode = InstantKill:CreateDropdown({
        Name = 'Mode',
        List = {'Toggle', 'On bind'},
        Default = 'Toggle'
    })
    Range = InstantKill:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 100,
        Default = 50,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end
    })
    Place = InstantKill:CreateToggle({
        Name = 'Auto place',
        Tooltip = 'Automatically places turrets if can\'t find any on ground.',
        Default = true
    })
end)

