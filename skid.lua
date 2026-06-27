-- bedwars ingame

local run = function(func)
    local ok, err = pcall(func)
    if not ok then
        warn('[skidv4] module failed to load: ' .. tostring(err))
    end
end
local vapeEvents = setmetatable({}, {
	__index = function(self, index)
		self[index] = Instance.new('BindableEvent')
		return self[index]
	end
})
getgenv().vapeEvents = vapeEvents

local cloneref = cloneref or function(obj)
	return obj
end

local function safeGetProto(func, index)
    if not func then return nil end
    local success, proto = pcall(debug.getconstant, func, index)
    if success then
        return proto
    end
end

local inventoryDebounce = false
local function fireInventoryChanged()
    if inventoryDebounce then return end
    inventoryDebounce = true
    task.spawn(function()
        task.wait() 
        vapeEvents.InventoryChanged:Fire()
        inventoryDebounce = false
    end)
end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local inputService = cloneref(game:GetService('UserInputService'))
local tweenService = cloneref(game:GetService('TweenService'))
local httpService = cloneref(game:GetService('HttpService'))
local textChatService = cloneref(game:GetService('TextChatService'))
local collectionService = cloneref(game:GetService('CollectionService'))
local contextActionService = cloneref(game:GetService('ContextActionService'))
local guiService = cloneref(game:GetService('GuiService'))
local coreGui = cloneref(game:GetService('CoreGui'))
local starterGui = cloneref(game:GetService('StarterGui'))
local VirtualInputManager = game:GetService("VirtualInputManager")
local lightingService = cloneref(game:GetService('Lighting'))

local isnetworkowner = identifyexecutor and table.find({'Delta', 'Volt'}, ({identifyexecutor()})[1]) and isnetworkowner or function()
	return true
end
local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local assetfunction = getcustomasset

local vape = shared.vape
if vape and not vape.Clean then
	vape.Clean = function(self, conn)
		if not conn then return end
		
		if not vape.Connections then
			vape.Connections = {}
		end

		if self and self.Enabled then
			vape.Connections[conn] = true
			return conn
		else
			if vape.Connections[conn] then
				if typeof(conn) == "RBXScriptConnection" then
					pcall(conn.Disconnect, conn)
				end
				vape.Connections[conn] = nil
			end
		end
	end
end
if vape and not vape.Remove then
    vape.Remove = function(module) 
		return module 
	end
end
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo
local uipallet = vape.Libraries.uipallet
local tween = vape.Libraries.tween
local color = vape.Libraries.color
local whitelist = { get = function() return nil, true end, tag = function() return '' end, customtags = {} }
local prediction = vape.Libraries.prediction
local getfontsize = vape.Libraries.getfontsize
local getcustomasset = vape.Libraries.getcustomasset

local store = {
    attackReach = 0,
    attackReachUpdate = tick(),
    damageBlockFail = tick(),
    hand = {},
    inventory = {
        inventory = {
            items = {},
            armor = {}
        },
        hotbar = {}
    },
    inventories = setmetatable({}, { __mode = "k" }), 
    matchState = 0,
    queueType = 'bedwars_test',
    tools = {},
    lastToolUpdate = 0,
	lastKrystalUpdateCheck = 0,
	BedAlarmNotifyTick = 0,
	BedAlarmIsTrigged = false,
	BedAlarmHighlightedEnimes = {},
	BedAlarm = {},
	BedAlarmSoundTick = 0,
	silasAbilityTime = 0,
	terraStompTime = 0,
	terraKickTime = 0,
}
getgenv().store = store
local Reach = {}
local HitBoxes = {}
local TrapDisabler
local AntiFallPart
local bedwars, remotes, sides, oldinvrender, oldSwing = {}, {}, {}
local _missingRemotes = {}
setmetatable(remotes, {
	__index = function(_, key)
		if not _missingRemotes[key] then
			_missingRemotes[key] = true
			task.delay(10, function()
				if rawget(remotes, key) == nil then
					pcall(function()
						vape.Notify('[SkidV4] remote "' .. tostring(key) .. '" changed or removed some features may not work bru (dm @5qvx for fix)', 6)
					end)
				end
			end)
		end
		return nil
	end
})
local originalKnit

local function addBlur(parent)
	local blur = Instance.new('ImageLabel')
	blur.Name = 'Blur'
	blur.Size = UDim2.new(1, 89, 1, 52)
	blur.Position = UDim2.fromOffset(-48, -31)
	blur.BackgroundTransparency = 1
	blur.Image = getcustomasset('newvape/assets/new/blur.png')
	blur.ScaleType = Enum.ScaleType.Slice
	blur.SliceCenter = Rect.new(52, 31, 261, 502)
	blur.Parent = parent
	return blur
end

local function notif(...) return
	vape:CreateNotification(...)
end

local function collection(tags, module, customadd, customremove)
	tags = typeof(tags) ~= 'table' and {tags} or tags
	local objs, connections = {}, {}

	for _, tag in tags do
		table.insert(connections, collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			if customadd then
				customadd(objs, v, tag)
				return
			end
			table.insert(objs, v)
		end))
		table.insert(connections, collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if customremove then
				customremove(objs, v, tag)
				return
			end
			v = table.find(objs, v)
			if v then
				table.remove(objs, v)
			end
		end))

		for _, v in collectionService:GetTagged(tag) do
			if customadd then
				customadd(objs, v, tag)
				continue
			end
			table.insert(objs, v)
		end
	end

	local cleanFunc = function(self)
		for _, v in connections do
			v:Disconnect()
		end
		table.clear(connections)
		table.clear(objs)
		table.clear(self)
	end
	if module then
		module:Clean(cleanFunc)
	end
	return objs, cleanFunc
end

local function getBestArmor(slot)
	local closest, mag = nil, 0

	for _, item in store.inventory.inventory.items do
		local meta = item and bedwars.ItemMeta[item.itemType] or {}

		if meta.armor and meta.armor.slot == slot then
			local newmag = (meta.armor.damageReductionMultiplier or 0)

			if newmag > mag then
				closest, mag = item, newmag
			end
		end
	end

	return closest
end

local function getBow()
	local bestBow, bestBowSlot, bestBowDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local _bowItemMeta = bedwars.ItemMeta[item.itemType]
        local bowMeta = _bowItemMeta and _bowItemMeta.projectileSource
		if bowMeta and table.find(bowMeta.ammoItemTypes, 'arrow') then
			local bowDamage = bedwars.ProjectileMeta[bowMeta.projectileType('arrow')].combat.damage or 0
			if bowDamage > bestBowDamage then
				bestBow, bestBowSlot, bestBowDamage = item, slot, bowDamage
			end
		end
	end
	return bestBow, bestBowSlot
end

local function getItem(itemName, inv)
	for slot, item in (inv or store.inventory.inventory.items) do
		if item.itemType == itemName then
			return item, slot
		end
	end
	return nil
end

local function GetItems(item: string): table
	local Items: table = {};
	for _, v in next, Enum[item]:GetEnumItems() do 
		table.insert(Items, v["Name"]) ;
	end;
	return Items;
end;

local function getRoactRender(func)
	return debug.getupvalue(debug.getupvalue(debug.getupvalue(func, 3).render, 2).render, 1)
end

local function getSword()
	local bestSword, bestSwordSlot, bestSwordDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local _swordItemMeta = bedwars.ItemMeta[item.itemType]
        local swordMeta = _swordItemMeta and _swordItemMeta.sword
		if swordMeta then
			local swordDamage = swordMeta.damage or 0
			if swordDamage > bestSwordDamage then
				bestSword, bestSwordSlot, bestSwordDamage = item, slot, swordDamage
			end
		end
	end
	return bestSword, bestSwordSlot
end

local function getTool(breakType)
	local bestTool, bestToolSlot, bestToolDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local _toolItemMeta = bedwars.ItemMeta[item.itemType]
        local toolMeta = _toolItemMeta and _toolItemMeta.breakBlock
		if toolMeta then
			local toolDamage = toolMeta[breakType] or 0
			if toolDamage > bestToolDamage then
				bestTool, bestToolSlot, bestToolDamage = item, slot, toolDamage
			end
		end
	end
	return bestTool, bestToolSlot
end

local function getWool()
	for _, wool in store.inventory.inventory.items do
		if wool.itemType:find('wool') then
			return wool and wool.itemType, wool and wool.amount
		end
	end
end

local function getStrength(plr)
	if not plr or not plr.Player then
		return 0
	end

	local strength = 0
	for _, v in (store.inventories[plr.Player] or {items = {}}).items do
		local itemmeta = bedwars.ItemMeta[v.itemType]
		if itemmeta and itemmeta.sword and itemmeta.sword.damage > strength then
			strength = itemmeta.sword.damage
		end
	end

	return strength
end

local function getPlacedBlock(pos)
	if not pos then
		return
	end
	local roundedPosition = bedwars.BlockController:getBlockPosition(pos)
	return bedwars.BlockController:getStore():getBlockAt(roundedPosition), roundedPosition
end

local function getBlocksInPoints(s, e)
	local blocks, list = bedwars.BlockController:getStore(), {}
	for x = s.X, e.X do
		for y = s.Y, e.Y do
			for z = s.Z, e.Z do
				local vec = Vector3.new(x, y, z)
				if blocks:getBlockAt(vec) then
					table.insert(list, vec * 3)
				end
			end
		end
	end
	return list
end

local function getNearGround(range)
	range = Vector3.new(3, 3, 3) * (range or 10)
	local localPosition, mag, closest = entitylib.character.RootPart.Position, 60
	local blocks = getBlocksInPoints(bedwars.BlockController:getBlockPosition(localPosition - range), bedwars.BlockController:getBlockPosition(localPosition + range))

	for _, v in blocks do
		if not getPlacedBlock(v + Vector3.new(0, 3, 0)) then
			local newmag = (localPosition - v).Magnitude
			if newmag < mag then
				mag, closest = newmag, v + Vector3.new(0, 3, 0)
			end
		end
	end

	table.clear(blocks)
	return closest
end

local function getShieldAttribute(char)
	local returned = 0
	for name, val in char:GetAttributes() do
		if name:find('Shield') and type(val) == 'number' and val > 0 then
			returned += val
		end
	end
	return returned
end

local function getSpeed()
	local multi, increase, modifiers = 0, true, bedwars.SprintController:getMovementStatusModifier():getModifiers()

	local modifiers2 = bedwars.SprintController:getMovementStatusModifier():getModifiers()
	for v in modifiers do
		local val = v.constantSpeedMultiplier and v.constantSpeedMultiplier or 0
		if val and val > math.max(multi, 1) then
			increase = false
			multi = val - (0.06 * math.round(val))
		end
	end

	for v in modifiers2 do
		multi += math.max((v.moveSpeedMultiplier or 0) - 1, 0)
	end

	if multi > 0 and increase then
		multi += 0.16 + (0.02 * math.round(multi))
	end

	return 20 * (multi + 1)
end

local function getTableSize(tab)
	local ind = 0
	for _ in tab do
		ind += 1
	end
	return ind
end

local function hotbarSwitch(slot)
	if slot and store.inventory.hotbarSlot ~= slot then
		bedwars.Store:dispatch({
			type = 'InventorySelectHotbarSlot',
			slot = slot
		})
		vapeEvents.InventoryChanged.Event:Wait()
		return true
	end
	return false
end

local function isFriend(plr, recolor)
	if vape.Categories.Friends.Options['Use friends'].Enabled then
		local friend = table.find(vape.Categories.Friends.ListEnabled, plr.Name) and true
		if recolor then
			friend = friend and vape.Categories.Friends.Options['Recolor visuals'].Enabled
		end
		return friend
	end
	return nil
end

local function isTarget(plr)
	return table.find(vape.Categories.Targets.ListEnabled, plr.Name) and true
end

local function removeTags(str)
	str = str:gsub('<br%s*/>', '\n')
	return (str:gsub('<[^<>]->', ''))
end

local function roundPos(vec)
    return Vector3.new(
        math.round(vec.X / 3) * 3,
        math.round(vec.Y / 3) * 3,
        math.round(vec.Z / 3) * 3
    )
end

local function switchItem(tool, delayTime)
	delayTime = delayTime or 0.05
	local check = lplr.Character and lplr.Character:FindFirstChild('HandInvItem') or nil
	if check and check.Value ~= tool and tool.Parent ~= nil then
		task.spawn(function()
			bedwars.Client:Get(remotes.EquipItem):CallServerAsync({hand = tool})
		end)
		check.Value = tool
		if delayTime > 0 then
			task.wait(delayTime)
		end
		return true
	end
end

local function waitForChildOfType(obj, name, timeout, prop)
	local check, returned = tick() + timeout
	repeat
		returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
		if (returned and returned.Name ~= 'UpperTorso') or check < tick() then
			break
		end
		task.wait()
	until false
	return returned
end

local frictionTable, oldfrict = {}, {}
local frictionConnection
local frictionState

local function modifyVelocity(v)
	if v:IsA('BasePart') and v.Name ~= 'HumanoidRootPart' and not oldfrict[v] then
		oldfrict[v] = v.CustomPhysicalProperties or 'none'
		v.CustomPhysicalProperties = PhysicalProperties.new(0.0001, 0.2, 0.5, 1, 1)
	end
end

local function updateVelocity(force)
	local newState = getTableSize(frictionTable) > 0
	if frictionState ~= newState or force then
		if frictionConnection then
			frictionConnection:Disconnect()
		end
		if newState then
			if entitylib.isAlive then
				for _, v in entitylib.character.Character:GetDescendants() do
					modifyVelocity(v)
				end
				frictionConnection = entitylib.character.Character.DescendantAdded:Connect(modifyVelocity)
			end
		else
			for i, v in oldfrict do
				i.CustomPhysicalProperties = v ~= 'none' and v or nil
			end
			table.clear(oldfrict)
		end
	end
	frictionState = newState
end

local function isEveryoneDead()
	return #bedwars.Store:getState().Party.members <= 0
end
	
local function joinQueue()
	if not bedwars.Store:getState().Game.customMatch and bedwars.Store:getState().Party.leader.userId == lplr.UserId and bedwars.Store:getState().Party.queueState == 0 then
		bedwars.QueueController:joinQueue(store.queueType)
	end
end

local function lobby()
    bedwars.Client:Get(remotes.TeleportToLobby):FireServer()
end

local kitorder = {
	hannah = 5,
	spirit_assassin = 4,
	dasher = 3,
	jade = 2,
	regent = 1
}

local function HasSeed(character)
    if not character then return false end
    return character:FindFirstChild("Seed", true) ~= nil
end

local sortmethods = {
	Damage = function(a, b)
		if not a.Entity or not a.Entity.Character then return false end
		if not b.Entity or not b.Entity.Character then return true end
		return a.Entity.Character:GetAttribute('LastDamageTakenTime') < b.Entity.Character:GetAttribute('LastDamageTakenTime')
	end,
	Threat = function(a, b)
		if not a.Entity then return false end
		if not b.Entity then return true end
		return getStrength(a.Entity) > getStrength(b.Entity)
	end,
	Kit = function(a, b)
		return (a.Entity.Player and kitorder[a.Entity.Player:GetAttribute('PlayingAsKit')] or 0) > (b.Entity.Player and kitorder[b.Entity.Player:GetAttribute('PlayingAsKit')] or 0)
	end,
	Health = function(a, b)
		return a.Entity.Health < b.Entity.Health
	end,
	Angle = function(a, b)
		if not a.Entity or not a.Entity.RootPart then return false end
		if not b.Entity or not b.Entity.RootPart then return true end
		local selfrootpos = entitylib.character.RootPart.Position
		local localFacing = (ViewMode.Value == 'Third Person' and gameCamera.CFrame.LookVector or entitylib.character.RootPart.CFrame.LookVector) * Vector3.new(1, 0, 1)
		local angle = math.acos(localfacing:Dot(((a.Entity.RootPart.Position - selfrootpos) * Vector3.new(1, 0, 1)).Unit))
		local angle2 = math.acos(localfacing:Dot(((b.Entity.RootPart.Position - selfrootpos) * Vector3.new(1, 0, 1)).Unit))
		return angle < angle2
	end,
	Distance = function(a, b)
		if not a.Entity or not a.Entity.RootPart then return false end
		if not b.Entity or not b.Entity.RootPart then return true end
		local selfpos = entitylib.character.RootPart.Position
		local distA = (a.Entity.RootPart.Position - selfpos).Magnitude
		local distB = (b.Entity.RootPart.Position - selfpos).Magnitude
		return distA < distB
	end,
	Cursor = function(a, b)
		if not a.Entity or not a.Entity.RootPart then return false end
		if not b.Entity or not b.Entity.RootPart then return true end
		local camera = gameCamera
		local mousePos = inputService:GetMouseLocation()
		local function screenDist(ent)
			local rootPart = ent.RootPart
			if not rootPart then return math.huge end
			local screenPos, onScreen = camera:WorldToScreenPoint(rootPart.Position)
			if not onScreen then return math.huge end
			return (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
		end
		local distA = screenDist(a.Entity)
		local distB = screenDist(b.Entity)
		if distA == math.huge and distB == math.huge then
			local selfpos = entitylib.character.RootPart.Position
			local worldA = (a.Entity.RootPart.Position - selfpos).Magnitude
			local worldB = (b.Entity.RootPart.Position - selfpos).Magnitude
			return worldA < worldB
		end
		return distA < distB
	end,
	Forest = function(a, b)
		if not a.Entity then return false end
		if not b.Entity then return true end
		local aHasSeed = HasSeed(a.Entity.Character)
		local bHasSeed = HasSeed(b.Entity.Character)
		if aHasSeed and not bHasSeed then return true end
		if not aHasSeed and bHasSeed then return false end
		if not a.Entity.RootPart then return false end
		if not b.Entity.RootPart then return true end
		local selfpos = entitylib.character.RootPart.Position
		local distA = (a.Entity.RootPart.Position - selfpos).Magnitude
		local distB = (b.Entity.RootPart.Position - selfpos).Magnitude
		return distA < distB
	end
}

local function getSortList(priority)
	local methods = {}
	for _, v in ipairs(priority or {}) do
		table.insert(methods, v)
	end
	for i in sortmethods do
		if not table.find(methods, i) then
			table.insert(methods, i)
		end
	end
	return methods
end

run(function()
	local oldstart = entitylib.start
	local function customEntity(ent)
		if ent:HasTag('inventory-entity') and not ent:HasTag('Monster') then
			return
		end

		entitylib.addEntity(ent, nil, ent:HasTag('Drone') and function(self)
			local droneplr = playersService:GetPlayerByUserId(self.Character:GetAttribute('PlayerUserId'))
			return not droneplr or lplr:GetAttribute('Team') ~= droneplr:GetAttribute('Team')
		end or function(self)
			return lplr:GetAttribute('Team') ~= self.Character:GetAttribute('Team')
		end)
	end

	entitylib.start = function()
		if entitylib.Running then entitylib.stop() end

		local function customEntity(ent)
			if playersService:GetPlayerFromCharacter(ent) then return end
			if collectionService:HasTag(ent.Parent, 'entity') then return end
			local teamFunc = function(self)
				local npcTeam = self.Character:GetAttribute('Team')
				return lplr:GetAttribute('Team') ~= npcTeam
			end
			entitylib.addEntity(ent, nil, teamFunc)
		end

		table.insert(entitylib.Connections, playersService.PlayerAdded:Connect(function(v)
			entitylib.addPlayer(v)
		end))
		table.insert(entitylib.Connections, playersService.PlayerRemoving:Connect(function(v)
			entitylib.removePlayer(v)
		end))

		for _, v in playersService:GetPlayers() do
			entitylib.addPlayer(v)
		end

		for _, ent in collectionService:GetTagged('entity') do
			customEntity(ent)
		end

		table.insert(entitylib.Connections, collectionService:GetInstanceAddedSignal('entity'):Connect(customEntity))
		table.insert(entitylib.Connections, collectionService:GetInstanceRemovedSignal('entity'):Connect(function(ent)
			entitylib.removeEntity(ent)
		end))

		local function addDesertPot(pot)
			if not pot:IsA('Model') then return end
			entitylib.addEntity(pot, nil, function() return true end)
		end
		for _, v in collectionService:GetTagged('desert_pot') do
			addDesertPot(v)
		end
		table.insert(entitylib.Connections, collectionService:GetInstanceAddedSignal('desert_pot'):Connect(addDesertPot))
		table.insert(entitylib.Connections, collectionService:GetInstanceRemovedSignal('desert_pot'):Connect(function(v)
			entitylib.removeEntity(v)
		end))

		table.insert(entitylib.Connections, workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(function()
			gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA('Camera')
		end))

		entitylib.Running = true
	end

	entitylib.addPlayer = function(plr)
		if entitylib.PlayerConnections[plr] then
			for _, conn in ipairs(entitylib.PlayerConnections[plr]) do
				if conn and typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				end
			end
		end

		if plr.Character then
			entitylib.refreshEntity(plr.Character, plr)
		end
		entitylib.PlayerConnections[plr] = {
			plr.CharacterAdded:Connect(function(char)
				entitylib.refreshEntity(char, plr)
			end),
			plr.CharacterRemoving:Connect(function(char)
				entitylib.removeEntity(char, plr == lplr)
			end),
			plr:GetAttributeChangedSignal('Team'):Connect(function()
				if plr == lplr then
					for _, v in entitylib.List do
						local newTargetable = entitylib.targetCheck(v)
						if v.Targetable ~= newTargetable then
							v.Targetable = newTargetable
							entitylib.Events.EntityUpdated:Fire(v)
						end
					end
				else
					entitylib.refreshEntity(plr.Character, plr)
					for _, v in entitylib.List do
						if v.Player ~= plr and v.Targetable ~= entitylib.targetCheck(v) then
							local newTargetable = entitylib.targetCheck(v)
							v.Targetable = newTargetable
							entitylib.Events.EntityUpdated:Fire(v)
						end
					end
				end
			end)
		}
	end

	entitylib.addEntity = function(char, plr, teamfunc)
		if not char then return end
		entitylib.EntityThreads[char] = task.spawn(function()
			local hum, humrootpart, head
			if plr then
				hum = waitForChildOfType(char, 'Humanoid', 10)
				humrootpart = hum and waitForChildOfType(hum, 'RootPart', workspace.StreamingEnabled and 9e9 or 10, true)
				head = char:WaitForChild('Head', 10) or humrootpart
			else
				hum = {HipHeight = 0.5}
				humrootpart = waitForChildOfType(char, 'PrimaryPart', 10, true)
				head = humrootpart
			end
			local updateobjects = {}
			if plr and plr ~= lplr then
				local names = {'ArmorInvItem_0', 'ArmorInvItem_1', 'ArmorInvItem_2', 'HandInvItem'}
				for _, name in names do
					local found = char:FindFirstChild(name)
					if found then
						table.insert(updateobjects, found)
					end
				end
			end

			if hum and humrootpart then
				local entity = {
					Connections = {},
					Character = char,
					Health = (function()
						local hp = char:GetAttribute('Health') or 100
						local shield = 0
						for k, v in pairs(char:GetAttributes()) do
							if type(k) == 'string' and k:sub(1, 7) == 'Shield_' and type(v) == 'number' and v > 0 then
								shield = shield + v
							end
						end
						return hp + shield
					end)(),
					Head = head,
					Humanoid = hum,
					HumanoidRootPart = humrootpart,
					HipHeight = hum.HipHeight + (humrootpart.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
					Jumps = 0,
					JumpTick = tick(),
					Jumping = false,
					LandTick = tick(),
					MaxHealth = char:GetAttribute('MaxHealth') or 100,
					NPC = plr == nil,
					Player = plr,
					RootPart = humrootpart,
					TeamCheck = teamfunc
				}

				if plr == lplr then
					entity.AirTime = tick()
					entitylib.character = entity
					entitylib.isAlive = true
					entitylib.Events.LocalAdded:Fire(entity)
					table.insert(entity.Connections, char.AttributeChanged:Connect(function(attr)
						vapeEvents.AttributeChanged:Fire(attr)
					end))
				else
					entity.Targetable = entitylib.targetCheck(entity)

					if not plr then
						table.insert(entity.Connections, char.AttributeChanged:Connect(function(attr)
							if attr == 'Team' then
								entity.Targetable = entitylib.targetCheck(entity)
								entitylib.Events.EntityUpdated:Fire(entity)
							end
						end))
					end

					for _, v in entitylib.getUpdateConnections(entity) do
						table.insert(entity.Connections, v:Connect(function()
							entity.Health = (char:GetAttribute('Health') or 100) + getShieldAttribute(char)
							entity.MaxHealth = char:GetAttribute('MaxHealth') or 100
							entitylib.Events.EntityUpdated:Fire(entity)
						end))
					end

					local invUpdatePending = {}

					for _, v in updateobjects do
						table.insert(entity.Connections, v:GetPropertyChangedSignal('Value'):Connect(function()
							if invUpdatePending[entity] then return end
							invUpdatePending[entity] = true
							task.delay(0.1, function()
								invUpdatePending[entity] = nil
								if bedwars.getInventory then
									store.inventories[plr] = bedwars.getInventory(plr)
									entitylib.Events.EntityUpdated:Fire(entity)
								end
							end)
						end))
					end

					if plr then
						local anim = char:FindFirstChild('Animate')
						if anim then
							pcall(function()
								local jumpAnimId = anim.jump:FindFirstChildWhichIsA('Animation').AnimationId
								table.insert(entity.Connections, hum.StateChanged:Connect(function(old, new)
									if new == Enum.HumanoidStateType.Jumping then
										entity.JumpTick = tick()
										entity.Jumps += 1
										entity.LandTick = tick() + 1
										entity.Jumping = entity.Jumps > 1
									elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.Freefall then
										entity.Jumping = false
									end
								end))
							end)
						end

						task.delay(0.1, function()
							if bedwars.getInventory then
								store.inventories[plr] = bedwars.getInventory(plr)
							end
						end)
					end
					table.insert(entitylib.List, entity)
					entitylib.Events.EntityAdded:Fire(entity)
				end

				table.insert(entity.Connections, char.ChildRemoved:Connect(function(part)
					if part == humrootpart or part == hum or part == head then
						if part == humrootpart and hum.RootPart then
							humrootpart = hum.RootPart
							entity.RootPart = hum.RootPart
							entity.HumanoidRootPart = hum.RootPart
							return
						end
						entitylib.removeEntity(char, plr == lplr)
					end
				end))
			end
			entitylib.EntityThreads[char] = nil
		end)
	end

	entitylib.getUpdateConnections = function(ent)
		local char = ent.Character
		local tab = {
			char:GetAttributeChangedSignal('Health'),
			char:GetAttributeChangedSignal('MaxHealth'),
			{
				Connect = function()
					ent.Friend = ent.Player and isFriend(ent.Player) or nil
					ent.Target = ent.Player and isTarget(ent.Player) or nil
					return {Disconnect = function() end}
				end
			}
		}

		if ent.Player then
			table.insert(tab, ent.Player:GetAttributeChangedSignal('PlayingAsKit'))
			table.insert(tab, ent.Player:GetAttributeChangedSignal('PlayingAsKits'))

			local vkSignal = {
				Connect = function(_, func)
					local conn = ent.Player:GetAttributeChangedSignal('VoidKnightTier'):Connect(function()
						lastUpdate[ent] = 0
						func()
					end)
					return conn
				end
			}
			table.insert(tab, vkSignal)
		end

		local blockKickerSignal = {
			Connect = function(_, func)
				local conn = char.AttributeChanged:Connect(function(attr)
					if attr == 'BlockKickerKit_BlockCount' then
						lastUpdate[ent] = 0
						func()
					end
				end)
				return conn
			end
		}
		table.insert(tab, blockKickerSignal)

		local shieldSignal = {
			Connect = function(_, func)
				local conn = char.AttributeChanged:Connect(function(attr)
					if attr:find('Shield') then
						func()
					end
				end)
				return conn
			end
		}
		table.insert(tab, shieldSignal)

		return tab
	end

	entitylib.targetCheck = function(ent)
		if ent.Character and ent.Character:HasTag('petrified-player') then return false end
		if ent.TeamCheck then
			return ent:TeamCheck()
		end
		if ent.NPC then
			local npcTeam = ent.Character and ent.Character:GetAttribute('Team')
			return lplr:GetAttribute('Team') ~= npcTeam
		end
		if isFriend(ent.Player) then return false end
		return lplr:GetAttribute('Team') ~= ent.Player:GetAttribute('Team')
	end
	vape:Clean(entitylib.Events.LocalAdded:Connect(updateVelocity))
end)
entitylib.start()

run(function()
	local KnitInit, Knit
	repeat
		KnitInit, Knit = pcall(function()
			return debug.getupvalue(require(lplr.PlayerScripts.TS.knit).setup, 9)
		end)
		if KnitInit then break end
		task.wait()
	until KnitInit

	if not debug.getupvalue(Knit.Start, 1) then
		repeat task.wait() until debug.getupvalue(Knit.Start, 1)
	end

	local Flamework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
	local InventoryUtil = require(replicatedStorage.TS.inventory['inventory-util']).InventoryUtil
	local Client = require(replicatedStorage.TS.remotes).default.Client
	local OldGet, OldBreak = Client.Get

	local rakNet = false
	run(function()
		rakNet = typeof(raknet) == 'table'
	end)

	bedwars = setmetatable({
		RankMeta = require(replicatedStorage.TS.rank['rank-meta']).RankMeta,
        BalanceFile = require(replicatedStorage.TS.balance["balance-file"]).BalanceFile,
        ClientSyncEvents = require(lplr.PlayerScripts.TS['client-sync-events']).ClientSyncEvents,
        SyncEventPriority = require(replicatedStorage.rbxts_include.node_modules['@easy-games']['sync-event'].out),
		AbilityId = require(replicatedStorage.TS.ability['ability-id']).AbilityId,
        IdUtil = require(replicatedStorage.TS.util['id-util']).IdUtil,
		BlockSelector = require(game:GetService("ReplicatedStorage").rbxts_include.node_modules["@easy-games"]["block-engine"].out.client.select["block-selector"]).BlockSelector,
		KnockbackUtilInstance = replicatedStorage.TS.damage['knockback-util'],
		BedwarsKitSkin = require(replicatedStorage.TS.games.bedwars['kit-skin']['bedwars-kit-skin-meta']).BedwarsKitSkinMeta,
		KitController = Knit.Controllers.KitController,
		FishermanUtil = require(replicatedStorage.TS.games.bedwars.kit.kits.fisherman['fisherman-util']).FishermanUtil,
		FishMeta = require(replicatedStorage.TS.games.bedwars.kit.kits.fisherman['fish-meta']),
	 	MatchHistroyApp = require(lplr.PlayerScripts.TS.controllers.global["match-history"].ui["match-history-moderation-app"]).MatchHistoryModerationApp,
	 	MatchHistroyController = Knit.Controllers.MatchHistoryController,
		BlockEngine = require(game:GetService("ReplicatedStorage").rbxts_include.node_modules["@easy-games"]["block-engine"].out).BlockEngine,
		BlockSelectorMode = require(game:GetService("ReplicatedStorage").rbxts_include.node_modules["@easy-games"]["block-engine"].out.client.select["block-selector"]).BlockSelectorMode,
		EntityUtil = require(game:GetService("ReplicatedStorage").TS.entity["entity-util"]).EntityUtil,
		GamePlayer = require(replicatedStorage.TS.player['game-player']),
		OfflinePlayerUtil = require(replicatedStorage.TS.player['offline-player-util']),
		PlayerUtil = require(replicatedStorage.TS.player['player-util']),
		KKKnitController = require(lplr.PlayerScripts.TS.lib.knit['knit-controller']),
		AbilityController = Flamework.resolveDependency('@easy-games/game-core:client/controllers/ability/ability-controller@AbilityController'),
		CooldownController = Flamework.resolveDependency("@easy-games/game-core:client/controllers/cooldown/cooldown-controller@CooldownController"),
		CooldownIDS = require(replicatedStorage.TS.cooldown["cooldown-id"]).CooldownId,		
		AnimationType = require(replicatedStorage.TS.animation['animation-type']).AnimationType,
		AnimationUtil = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out['shared'].util['animation-util']).AnimationUtil,
		AppController = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.controllers['app-controller']).AppController,
		BedBreakEffectMeta = require(replicatedStorage.TS.locker['bed-break-effect']['bed-break-effect-meta']).BedBreakEffectMeta,
		BedwarsKitMeta = require(replicatedStorage.TS.games.bedwars.kit['bedwars-kit-meta']).BedwarsKitMeta,
		BlockBreaker = Knit.Controllers.BlockBreakController.blockBreaker,
		BlockController = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out).BlockEngine,
		BlockEngine = require(lplr.PlayerScripts.TS.lib['block-engine']['client-block-engine']).ClientBlockEngine,
		BlockPlacer = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.client.placement['block-placer']).BlockPlacer,
		BowConstantsTable = (Knit.Controllers.ProjectileController and Knit.Controllers.ProjectileController.enableBeam) and debug.getupvalue(Knit.Controllers.ProjectileController.enableBeam, 8) or {},
		ClickHold = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.ui.lib.util['click-hold']).ClickHold,
		Client = Client,
		ClientConstructor = require(replicatedStorage['rbxts_include']['node_modules']['@rbxts'].net.out.client),
		ClientDamageBlock = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.shared.remotes).BlockEngineRemotes.Client,
		CombatConstant = require(replicatedStorage.TS.combat['combat-constant']).CombatConstant,
		SharedConstants = require(replicatedStorage.TS['shared-constants']),
		DamageIndicator = Knit.Controllers.DamageIndicatorController.spawnDamageIndicator,
		DefaultKillEffect = require(lplr.PlayerScripts.TS.controllers.global.locker['kill-effect'].effects['default-kill-effect']),
		EmoteType = require(replicatedStorage.TS.locker.emote['emote-type']).EmoteType,
		GameAnimationUtil = require(replicatedStorage.TS.animation['animation-util']).GameAnimationUtil,
		NotificationController = Flamework.resolveDependency('@easy-games/game-core:client/controllers/notification-controller@NotificationController'),
		getIcon = function(item, showinv)
			local itemmeta = bedwars.ItemMeta[item.itemType]
			return itemmeta and showinv and itemmeta.image or ''
		end,
		getInventory = function(plr)
			local suc, res = pcall(function()
				return InventoryUtil.getInventory(plr)
			end)
			return suc and res or {
				items = {},
				armor = {}
			}
		end,
		MatchHistoryController = require(lplr.PlayerScripts.TS.controllers.global['match-history']['match-history-controller']),
		PlayerProfileUIController = require(lplr.PlayerScripts.TS.controllers.global['player-profile']['player-profile-ui-controller']),
		HudAliveCount = require(lplr.PlayerScripts.TS.controllers.global['top-bar'].ui.game['hud-alive-player-counts']).HudAlivePlayerCounts,
		ItemMeta = (function()
			local fn = require(replicatedStorage.TS.item['item-meta']).getItemMeta
			for i = 1, 6 do
				local v = debug.getupvalue(fn, i)
				if type(v) == 'table' and next(v) then return v end
			end
			return {}
		end)(),
		KillEffectMeta = require(replicatedStorage.TS.locker['kill-effect']['kill-effect-meta']).KillEffectMeta,
		KillFeedController = Flamework.resolveDependency('client/controllers/game/kill-feed/kill-feed-controller@KillFeedController'),
		Knit = Knit,
		KnockbackUtil = require(replicatedStorage.TS.damage['knockback-util']).KnockbackUtil,
		MageKitUtil = require(replicatedStorage.TS.games.bedwars.kit.kits.mage['mage-kit-util']).MageKitUtil,
		NametagController = Knit.Controllers.NametagController,
		PartyController = Flamework.resolveDependency("@easy-games/lobby:client/controllers/party-controller@PartyController"),
		ProjectileMeta = require(replicatedStorage.TS.projectile['projectile-meta']).ProjectileMeta,
		QueryUtil = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).GameQueryUtil,
		QueueCard = require(lplr.PlayerScripts.TS.controllers.global.queue.ui['queue-card']).QueueCard,
		QueueMeta = require(replicatedStorage.TS.game['queue-meta']).QueueMeta,
		Roact = require(replicatedStorage['rbxts_include']['node_modules']['@rbxts']['roact'].src),
		RuntimeLib = require(replicatedStorage['rbxts_include'].RuntimeLib),
		SoundList = require(replicatedStorage.TS.sound['game-sound']).GameSound,
		SoundManager = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.shared.sound['sound-manager']).SoundManager,
		Store = require(lplr.PlayerScripts.TS.ui.store).ClientStore,
		TeamUpgradeMeta = debug.getupvalue(require(replicatedStorage.TS.games.bedwars['team-upgrade']['team-upgrade-meta']).getTeamUpgradeMetaForQueue, 6),
		UILayers = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).UILayers,
		VisualizerUtils = require(lplr.PlayerScripts.TS.lib.visualizer['visualizer-utils']).VisualizerUtils,
		WeldTable = require(replicatedStorage.TS.util['weld-util']).WeldUtil,
		WinEffectMeta = require(replicatedStorage.TS.locker['win-effect']['win-effect-meta']).WinEffectMeta,
		ZapNetworking = require(lplr.PlayerScripts.TS.lib.network),
	}, {
		__index = function(self, ind)
			rawset(self, ind, Knit.Controllers[ind])
			return rawget(self, ind)
		end
	})

	getgenv().bedwars = bedwars

	local remoteNames = {
		AfkStatus = safeGetProto(Knit.Controllers.AfkController.KnitStart, 1),
		AttackEntity = Knit.Controllers.SwordController.sendServerRequest,
		BeePickup = Knit.Controllers.BeeNetController.trigger,
		CannonAim = safeGetProto(Knit.Controllers.CannonController.startAiming, 5),
		CannonLaunch = Knit.Controllers.CannonHandController.launchSelf,
		ConsumeBattery = safeGetProto(Knit.Controllers.BatteryController.onKitLocalActivated, 1),
		ConsumeItem = safeGetProto(Knit.Controllers.ConsumeController.onEnable, 1),
		ConsumeSoul = Knit.Controllers.GrimReaperController.consumeSoul,
		ConsumeTreeOrb = safeGetProto(Knit.Controllers.EldertreeController.createTreeOrbInteraction, 1),
		DepositPinata = safeGetProto(safeGetProto(Knit.Controllers.PiggyBankController.KnitStart, 2), 5),
		DragonBreath = safeGetProto(Knit.Controllers.VoidDragonController.onKitLocalActivated, 5),
		DragonEndFly = safeGetProto(Knit.Controllers.VoidDragonController.flapWings, 1),
		DragonFly = Knit.Controllers.VoidDragonController.flapWings,
		DropItem = Knit.Controllers.ItemDropController.dropItemInHand,
		EquipItem = safeGetProto(require(replicatedStorage.TS.entity.entities['inventory-entity']).InventoryEntity.equipItem, 3),
		FireProjectile = (Knit.Controllers.ProjectileController and Knit.Controllers.ProjectileController.launchProjectileWithValues) and debug.getupvalue(Knit.Controllers.ProjectileController.launchProjectileWithValues, 2) or nil,
		GroundHit = Knit.Controllers.FallDamageController.KnitStart,
		GuitarHeal = Knit.Controllers.GuitarController.performHeal,
		HannahKill = safeGetProto(Knit.Controllers.HannahController.registerExecuteInteractions, 1),
		HarvestCrop = safeGetProto(safeGetProto(Knit.Controllers.CropController.KnitStart, 4), 1),
		KaliyahPunch = safeGetProto(Knit.Controllers.DragonSlayerController.onKitLocalActivated, 1),
		MageSelect = safeGetProto(Knit.Controllers.MageController.registerTomeInteraction, 1),
		MinerDig = safeGetProto(Knit.Controllers.MinerController.setupMinerPrompts, 1),
		PickupItem = Knit.Controllers.ItemDropController.checkForPickup,
		PickupMetal = safeGetProto(Knit.Controllers.HiddenMetalController.onKitLocalActivated, 4),
		ReportPlayer = require(lplr.PlayerScripts.TS.controllers.global.report['report-controller']).default.reportPlayer,
		ResetCharacter = safeGetProto(Knit.Controllers.ResetController.createBindable, 1),
		SummonerClawAttack = Knit.Controllers.SummonerClawHandController.attack,
		WarlockTarget = safeGetProto(Knit.Controllers.WarlockStaffController.KnitStart, 2)
	}

	local function dumpRemote(tab)
		local ind
		for i, v in tab do
			if v == 'Client' then
				ind = i
				break
			end
		end
		return ind and tab[ind + 1] or ''
	end

	local preDumped = {
		EquipItem = 'SetInvItem',
		ActivateGravestone = 'ActivateGravestone',
		CollectCollectableEntity = 'CollectCollectableEntity',
		DefenderRequestPlaceBlock = 'DefenderRequestPlaceBlock',
		RequestDragonPunch = 'RequestDragonPunch',
		Harvest = 'CropHarvest',
		DepositCoins = 'DepositCoins',
		BedwarsPurchaseItem = 'BedwarsPurchaseItem',
		BedBreakEffectTriggered = 'BedBreakEffectTriggered',
		BloodAssassinSelectContract = 'BloodAssassinSelectContract',
		Mimic = 'MimicBlock',
		StyxPortal = 'UseStyxPortalFromClient',
		StyxExitPortal = 'StyxOpenExitPortalFromServer',
		StyxSpawnExitPortal = 'StyxSpawnExitPortalFromServer',
		StyxSpawnEntrancePortal = 'StyxSpawnEntrancePortalFromServer',
		TryOpenStyxPortalExit = 'StyxTryOpenExitPortalFromClient',
		TeleportToLobby = 'TeletoLobby',
		FishCaught = 'FishCaught',
		SpawnRaven = 'SpawnRaven',
		PaladinAbilityRequest = 'PaladinAbilityRequest',
		OwlActionAbilities = 'OwlActionAbilities',
		DrillAttack = 'DrillAttack',
		UpgradeFrostyHammer = 'UpgradeFrostyHammer',
		UpgradeFlamethrower = 'UpgradeFlamethrower',
		TryBlockKick = 'TryBlockKick',   
		Ranks = 'FetchRanks',
		ResearchEnchant = 'EnchantTableResearch',
		DropDroneItem = 'DropDroneItem',
		AttemptFireOasisProjectiles = 'AttemptFireOasisProjectiles',
		WinEffectTriggered = 'WinEffectTriggered',
		ExtractFromDrill = 'ExtractFromDrill',
		HannahPromptTrigger = 'HannahPromptTrigger',
		DragonFlap = 'DragonFlap',
		DragonBreath = 'DragonBreath',
		AttemptCardThrow = 'AttemptCardThrow',
		LearnElementTome = 'LearnElementTome',
		RequestMoveSlime = 'RequestMoveSlime',
		SummonOwl = 'SummonOwl',
		RemoveOwl = 'RemoveOwl',
		OwlFireProjectile = 'OwlFireProjectile',
		OwlAiming = 'OwlAiming',
		MimicBlockPickPocketPlayer = 'MimicBlockPickPocketPlayer',
		DestroyPetrifiedPlayer = 'DestroyPetrifiedPlayer',
		UseAbility = 'useAbility',
		FishFound = 'FishFound',
	}

	for k, v in pairs(preDumped) do
		if not remotes[k] then
			remotes[k] = v
		end
	end

	for i, v in remoteNames do
		local remote
		if type(v) == "string" then
			remote = v
		elseif type(v) == "function" then
			local consts = debug.getconstants(v)
			remote = dumpRemote(consts)
		else
			remote = ""
		end

		if remote == '' or remote == nil then
			if not preDumped[i] then
				notif('Vape', 'Failed to grab remote ('..tostring(i)..')', 10, 'alert')
			end
			remote = preDumped[i] or ''
		end
		remotes[i] = remote
	end

	getgenv().remotes = remotes

	OldBreak = bedwars.BlockController.isBlockBreakable

	Client.Get = function(self, remoteName)
		local call = OldGet(self, remoteName)

		if remoteName == remotes.AttackEntity then
			return {
				instance = call.instance,
				SendToServer = function(_, attackTable, ...)
					local suc, plr = pcall(function()
						return playersService:GetPlayerFromCharacter(attackTable.entityInstance)
					end)

					local selfpos = attackTable.validate.selfPosition.value
					local targetpos = attackTable.validate.targetPosition.value
					store.attackReach = ((selfpos - targetpos).Magnitude * 100) // 1 / 100
					store.attackReachUpdate = tick() + 1

					if Reach.Enabled or HitBoxes.Enabled then
						attackTable.validate.raycast = attackTable.validate.raycast or {}
						attackTable.validate.selfPosition.value += CFrame.lookAt(selfpos, targetpos).LookVector * math.max((selfpos - targetpos).Magnitude - 14.399, 0)
					end

					return call:SendToServer(attackTable, ...)
				end
			}
		elseif remoteName == 'StepOnSnapTrap' and TrapDisabler.Enabled then
			return {SendToServer = function() end}
		end

		return call
	end

	local bedtms = {}

	bedwars.BlockController.isBlockBreakable = function(self, breakTable, plr)
		return OldBreak(self, breakTable, plr)
	end

	local cache, blockhealthbar = {}, {blockHealth = -1, breakingBlockPosition = Vector3.zero}
	
	local cacheCleanThread = task.spawn(function()
		while vape.Loaded do
			task.wait(60)
			if vape.Loaded then
				table.clear(cache)
				table.clear(bedtms)
			end
		end
	end)
	vape:Clean(function() task.cancel(cacheCleanThread) end)

	store.blockPlacer = bedwars.BlockPlacer.new(bedwars.BlockEngine, 'wool_white')

	local function getBlockHealth(block, blockpos)
		local blockdata = bedwars.BlockController:getStore():getBlockData(blockpos)
		return (blockdata and (blockdata:GetAttribute('1') or blockdata:GetAttribute('Health')) or block:GetAttribute('Health'))
	end

	local function getBlockHits(block, blockpos)
		if not block then return 0 end
		local breaktype = bedwars.ItemMeta[block.Name].block.breakType
		local tool = store.tools[breaktype]
		tool = tool and bedwars.ItemMeta[tool.itemType].breakBlock[breaktype] or 2
		return getBlockHealth(block, bedwars.BlockController:getBlockPosition(blockpos)) / tool
	end

	local function calculatePath(target, blockpos, method, angle)
		if cache[blockpos] then
			if tick() - (cache[blockpos].timestamp or 0) < 1 then
				return unpack(cache[blockpos])
			else
				cache[blockpos] = nil
			end
		end
		angle = angle or 360
		local visited = {}
		local unvisited = {{0, blockpos}}
		local distances = {[blockpos] = 0}
		local air = {}
		local path = {}
		local unvisitedCount = 1

		for _ = 1, 600 do
			if unvisitedCount == 0 then break end
			local node = unvisited[1]
			unvisited[1] = unvisited[unvisitedCount]
			unvisited[unvisitedCount] = nil
			unvisitedCount = unvisitedCount - 1
			visited[node[2]] = true

			for _, side in sides do
				local neighbor = node[2] + side
				if visited[neighbor] then continue end

				local block = getPlacedBlock(neighbor)
				if not block or block:GetAttribute('NoBreak') or block == target then
					if not block then
						air[node[2]] = true
					end
					continue
				end

				if angle < 360 then
					local camFlat = gameCamera.CFrame.LookVector * Vector3.new(1, 0, 1)
					local blockFlat = (block.Position - entitylib.character.RootPart.Position) * Vector3.new(1, 0, 1)
					if camFlat.Magnitude > 0.01 and blockFlat.Magnitude > 0.01 then
						if math.acos(math.clamp(camFlat.Unit:Dot(blockFlat.Unit), -1, 1)) > math.rad(angle) / 2 then
							continue
						end
					end
				end

				local curdist = (method and method(block, neighbor) or getBlockHits(block, neighbor)) + node[1]
				if curdist < (distances[neighbor] or math.huge) then
					unvisitedCount = unvisitedCount + 1
					unvisited[unvisitedCount] = {curdist, neighbor}
					distances[neighbor] = curdist
					path[neighbor] = node[2]
				end
			end
		end

		local pos, cost = nil, math.huge
		for node in air do
			local d = distances[node]
			if d and d < cost then
				pos, cost = node, d
			end
		end

		if pos then
			local cacheEntry = {pos, cost, path, timestamp = tick()}
			cache[blockpos] = cacheEntry
			return pos, cost, path
		end
	end

	bedwars.placeBlock = function(pos, item)
		if getItem(item) then
			store.blockPlacer.blockType = item
			local ok, result = pcall(function()
				return store.blockPlacer:placeBlock(bedwars.BlockController:getBlockPosition(pos))
			end)
			if ok then return result end
		end
	end

	bedwars.breakBlock = function(block, effects, anim, customHealthbar, autotool, wallcheck, nobreak, useDistance)
		if lplr:GetAttribute('DenyBlockBreak') or not entitylib.isAlive then return end
		local handler = bedwars.BlockController:getHandlerRegistry():getHandler(block.Name)
		local cost, pos, target, path = math.huge, nil, nil, nil
		local playerPos = entitylib.character.RootPart.Position

		for _, v in (handler and handler:getContainedPositions(block) or {block.Position / 3}) do
			local costFunc = useDistance and function(block, pos) return 1 end or nil
			local dpos, dcost, dpath = calculatePath(block, v * 3, costFunc, BreakerAngle and BreakerAngle.Value or 360)
			if dpos then
				local selectCost = useDistance and (dpos - playerPos).Magnitude or dcost
				if selectCost < cost then
					cost, pos, target, path = selectCost, dpos, v * 3, dpath
				end
			end
		end

		if pos then
			if (entitylib.character.RootPart.Position - pos).Magnitude > 30 then return end
			local dblock, dpos = getPlacedBlock(pos)
			if not dblock then return end

			if not nobreak and (workspace:GetServerTimeNow() - bedwars.SwordController.lastAttack) > 0.4 then
				local breaktype = bedwars.ItemMeta[dblock.Name].block.breakType
				local tool = store.tools[breaktype]
				if tool then
					if autotool then
						local found = false
						for i, v in store.inventory.hotbar do
							if v.item and v.item.tool == tool.tool and i ~= (store.inventory.hotbarSlot + 1) then
								hotbarSwitch(i - 1)
								found = true
								break
							end
						end
						if not found then
							switchItem(tool.tool)
						end
					else
						switchItem(tool.tool)
					end
				end
			end

			if blockhealthbar.blockHealth == -1 or dpos ~= blockhealthbar.breakingBlockPosition then
				blockhealthbar.blockHealth = getBlockHealth(dblock, dpos)
				blockhealthbar.breakingBlockPosition = dpos
			end

			if not nobreak then
				bedwars.ClientDamageBlock:Get('DamageBlock'):CallServerAsync({
					blockRef = {blockPosition = dpos},
					hitPosition = pos,
					hitNormal = Vector3.FromNormalId(Enum.NormalId.Top)
				}):andThen(function(result)
					if result then
						if result == 'cancelled' then
							store.damageBlockFail = tick() + 1
							table.clear(cache)
							return
						end
						if result == 'destroyed' then
							table.clear(cache)
						end
						if effects then
							local blockdmg = (blockhealthbar.blockHealth - (result == 'destroyed' and 0 or getBlockHealth(dblock, dpos)))
							customHealthbar = customHealthbar or bedwars.BlockBreaker.updateHealthbar
							customHealthbar(bedwars.BlockBreaker, {blockPosition = dpos}, blockhealthbar.blockHealth, dblock:GetAttribute('MaxHealth'), blockdmg, dblock)
							blockhealthbar.blockHealth = math.max(blockhealthbar.blockHealth - blockdmg, 0)
							pcall(function()
								if blockhealthbar.blockHealth <= 0 then
									bedwars.BlockBreaker.breakEffect:playBreak(dblock.Name, dpos, lplr)
									bedwars.BlockBreaker.healthbarMaid:DoCleaning()
									blockhealthbar.breakingBlockPosition = Vector3.zero
								else
									bedwars.BlockBreaker.breakEffect:playHit(dblock.Name, dpos, lplr)
								end
							end)
						end
						if anim then
							local animation = bedwars.AnimationUtil:playAnimation(lplr, bedwars.BlockController:getAnimationController():getAssetId(1))
							bedwars.ViewmodelController:playAnimation(15)
							task.wait(0.3)
							animation:Stop()
							animation:Destroy()
						end
					end
				end)
			end

			if effects then
				return pos, path, target
			end
		end
	end

	for _, v in Enum.NormalId:GetEnumItems() do
		table.insert(sides, Vector3.FromNormalId(v) * 3)
	end

	local function updateStore(new, old)
		if new.Bedwars ~= old.Bedwars then
			store.equippedKit = new.Bedwars.kit ~= 'none' and new.Bedwars.kit or ''
		end

		if new.Game ~= old.Game then
			store.matchState = new.Game.matchState
			store.queueType = new.Game.queueType or 'bedwars_test'
		end

		if new.Inventory ~= old.Inventory then
			local newinv = (new.Inventory and new.Inventory.observedInventory or {inventory = {}})
			local oldinv = (old.Inventory and old.Inventory.observedInventory or {inventory = {}})
			store.inventory = newinv

			if newinv ~= oldinv then
				fireInventoryChanged()
			end

			if newinv.inventory.items ~= oldinv.inventory.items then
				vapeEvents.InventoryAmountChanged:Fire()
				local now = tick()
				if not store.lastToolUpdate or now - store.lastToolUpdate > 0.5 then
					store.lastToolUpdate = now
					store.tools.sword = getSword()
					for _, v in {'stone', 'wood', 'wool'} do
						store.tools[v] = getTool(v)
					end
				end
			end

			if newinv.inventory.hand ~= oldinv.inventory.hand then
				local currentHand, toolType = new.Inventory.observedInventory.inventory.hand, ''
				if currentHand then
					local handData = bedwars.ItemMeta[currentHand.itemType]
					toolType = handData.sword and 'sword' or handData.block and 'block' or currentHand.itemType:find('bow') and 'bow'
				end

				store.hand = {
					tool = currentHand and currentHand.tool,
					amount = currentHand and currentHand.amount or 0,
					toolType = toolType
				}
			end
		end
	end

	local storeChanged = bedwars.Store.changed:connect(updateStore)
	vape:Clean(function() storeChanged:disconnect() end)
	updateStore(bedwars.Store:getState(), {})

	for _, event in {'MatchEndEvent', 'EntityDeathEvent', 'BedwarsBedBreak', 'BalloonPopped', 'AngelProgress', 'GrapplingHookFunctions'} do
		if not vape.Connections then return end
		bedwars.Client:WaitFor(event):andThen(function(connection)
			vape:Clean(connection:Connect(function(...)
				vapeEvents[event]:Fire(...)
			end))
		end)
	end

	local _dmgEventData = {entityInstance=nil,damage=nil,damageType=nil,fromPosition=nil,fromEntity=nil,knockbackMultiplier=nil,knockbackId=nil,disableDamageHighlight=nil}
	vape:Clean(bedwars.ZapNetworking.EntityDamageEventZap.On(function(...)
		_dmgEventData.entityInstance = ...
		_dmgEventData.damage = select(2, ...)
		_dmgEventData.damageType = select(3, ...)
		_dmgEventData.fromPosition = select(4, ...)
		_dmgEventData.fromEntity = select(5, ...)
		_dmgEventData.knockbackMultiplier = select(6, ...)
		_dmgEventData.knockbackId = select(7, ...)
		_dmgEventData.disableDamageHighlight = select(13, ...)
		vapeEvents.EntityDamageEvent:Fire(_dmgEventData)
	end))

	vape:Clean(playersService.PlayerRemoving:Connect(function(plr)
		store.inventories[plr] = nil
	end))

	local _blockEventData = {blockRef = {blockPosition = nil}, player = nil}
	for _, event in {'PlaceBlockEvent', 'BreakBlockEvent'} do
		vape:Clean(bedwars.ZapNetworking[event..'Zap'].On(function(...)
			_blockEventData.blockRef.blockPosition = ...
			_blockEventData.player = select(5, ...)
			vapeEvents[event]:Fire(_blockEventData)
		end))
	end

	store.blocks = collection('block', vape)
	store.shop = collection({'BedwarsItemShop', 'TeamUpgradeShopkeeper'}, vape, function(tab, obj)
		table.insert(tab, {
			Id = obj.Name,
			RootPart = obj,
			Shop = obj:HasTag('BedwarsItemShop'),
			Upgrades = obj:HasTag('TeamUpgradeShopkeeper')
		})
	end)
	store.enchant = collection({'enchant-table', 'broken-enchant-table'}, vape, nil, function(tab, obj, tag)
		if obj:HasTag('enchant-table') and tag == 'broken-enchant-table' then return end
		obj = table.find(tab, obj)
		if obj then
			table.remove(tab, obj)
		end
	end)

	local kills = sessioninfo:AddItem('Kills')
	local beds = sessioninfo:AddItem('Beds')
	local wins = sessioninfo:AddItem('Wins')
	local games = sessioninfo:AddItem('Games')

	local mapname = 'Unknown'
	sessioninfo:AddItem('Map', 0, function()
		return mapname
	end, false)

	task.delay(1, function()
		games:Increment()
	end)

	task.spawn(function()
		pcall(function()
			repeat task.wait() until store.matchState ~= 0 or vape.Loaded == nil
			if vape.Loaded == nil then return end
			mapname = workspace:WaitForChild('Map', 5):WaitForChild('Worlds', 5):GetChildren()[1].Name
			mapname = string.gsub(string.split(mapname, '_')[2] or mapname, '-', '') or 'Blank'
		end)
	end)

	vape:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(bedTable)
		if bedTable.player and bedTable.player.UserId == lplr.UserId then
			beds:Increment()
		end
	end))

	vape:Clean(vapeEvents.MatchEndEvent.Event:Connect(function(winTable)
		if (bedwars.Store:getState().Game.myTeam or {}).id == winTable.winningTeamId or lplr.Neutral then
			wins:Increment()
		end
	end))

	vape:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
		local killer = playersService:GetPlayerFromCharacter(deathTable.fromEntity)
		local killed = playersService:GetPlayerFromCharacter(deathTable.entityInstance)
		if not killed or not killer then return end

		if killed ~= lplr and killer == lplr then
			kills:Increment()
		end
	end))

	pcall(function()
		bedwars.Shop = require(replicatedStorage.TS.games.bedwars.shop['bedwars-shop']).BedwarsShop
		bedwars.ShopItems = bedwars.Shop.ShopItems
		bedwars.Shop.getShopItem('iron_sword', lplr)
		store.shopLoaded = true
	end)

	vape:Clean(function()
		Client.Get = OldGet
		bedwars.BlockController.isBlockBreakable = OldBreak
		store.blockPlacer:disable()
		for _, v in vapeEvents do
			v:Destroy()
		end
		for _, v in cache do
			table.clear(v[3])
			table.clear(v)
		end
		table.clear(store.blockPlacer)
		table.clear(vapeEvents)
		table.clear(bedwars)
		table.clear(store)
		table.clear(cache)
		table.clear(sides)
		table.clear(remotes)
		storeChanged:disconnect()
		storeChanged = nil

		if entitylib.Connections then
			for _, conn in ipairs(entitylib.Connections) do
				if conn and type(conn) == "userdata" and conn.Connected then
					conn:Disconnect()
				end
			end
			table.clear(entitylib.Connections)
		end

		if entitylib.PlayerConnections then
			for _, plrConns in pairs(entitylib.PlayerConnections) do
				if type(plrConns) == "table" then
					for _, conn in ipairs(plrConns) do
						if conn and type(conn) == "userdata" and conn.Connected then
							conn:Disconnect()
						end
					end
				end
			end
			table.clear(entitylib.PlayerConnections)
		end

		if entitylib.EntityThreads then
			for char, thread in pairs(entitylib.EntityThreads) do
				if thread and task.cancel then
					task.cancel(thread)
				end
			end
			table.clear(entitylib.EntityThreads)
		end

		if entitylib.List then
			for _, ent in ipairs(entitylib.List) do
				if ent.Connections then
					for _, conn in ipairs(ent.Connections) do
						if conn and type(conn) == "userdata" and conn.Connected then
							conn:Disconnect()
						end
					end
					table.clear(ent.Connections)
				end
			end
			table.clear(entitylib.List)
		end
		if entitylib.stop then
			entitylib.stop()
		end
		for playerId, data in pairs(lagConnections) do
			if data and data.connection then
				pcall(function() data.connection:Disconnect() end)
			end
		end
		table.clear(lagConnections)
	end)
end)

for _, v in {'AntiRagdoll', 'TriggerBot', 'SilentAim', 'AutoRejoin', 'Rejoin', 'Disabler', 'Timer', 'ServerHop', 'MouseTP', 'MurderMystery', 'NameTags', 'Killaura', 'AimAssist', 'AutoClicker', 'Reach', 'AntiFall', 'Fly', 'HitBoxes', 'LongJump', 'Speed', 'Swim', 'PlayerModel', 'Search', 'Waypoints', 'Blink', 'StaffDetector', ''} do
	vape:Remove(v)
end

local kitImageIds = {
	['none'] = "rbxassetid://16493320215",
	["random"] = "rbxassetid://79773209697352",
	["cowgirl"] = "rbxassetid://9155462968",
	["davey"] = "rbxassetid://9155464612",
	["warlock"] = "rbxassetid://15186338366",
	["ember"] = "rbxassetid://9630017904",
	["black_market_trader"] = "rbxassetid://18922642482",
	["yeti"] = "rbxassetid://9166205917",
	["scarab"] = "rbxassetid://137137517627492",
	["defender"] = "rbxassetid://131690429591874",
	["cactus"] = "rbxassetid://104436517801089",
	["oasis"] = "rbxassetid://120283205213823",
	["berserker"] = "rbxassetid://90258047545241",
	["sword_shield"] = "rbxassetid://131690429591874",
	["airbender"] = "rbxassetid://74712750354593",
	["gun_blade"] = "rbxassetid://138231219644853",
	["frost_hammer_kit"] = "rbxassetid://11838567073",
	["spider_queen"] = "rbxassetid://95237509752482",
	["archer"] = "rbxassetid://9224796984",
	["axolotl"] = "rbxassetid://9155466713",
	["baker"] = "rbxassetid://9155463919",
	["barbarian"] = "rbxassetid://9166207628",
	["builder"] = "rbxassetid://9155463708",
	["necromancer"] = "rbxassetid://11343458097",
	["cyber"] = "rbxassetid://9507126891",
	["sorcerer"] = "rbxassetid://97940108361528",
	["bigman"] = "rbxassetid://9155467211",
	["spirit_assassin"] = "rbxassetid://10406002412",
	["farmer_cletus"] = "rbxassetid://9155466936",
	["ice_queen"] = "rbxassetid://9155466204",
	["grim_reaper"] = "rbxassetid://9155467410",
	["spirit_gardener"] = "rbxassetid://132108376114488",
	["hannah"] = "rbxassetid://10726577232",
	["shielder"] = "rbxassetid://9155464114",
	["summoner"] = "rbxassetid://18922378956",
	["glacial_skater"] = "rbxassetid://84628060516931",
	["dragon_sword"] = "rbxassetid://16215630104",
	["lumen"] = "rbxassetid://9630018371",
	["flower_bee"] = "rbxassetid://101569742252812",
	["jellyfish"] = "rbxassetid://18129974852",
	["melody"] = "rbxassetid://9155464915",
	["mimic"] = "rbxassetid://14783283296",
	["miner"] = "rbxassetid://9166208461",
	["nazar"] = "rbxassetid://18926951849",
	["seahorse"] = "rbxassetid://11902552560",
	["elk_master"] = "rbxassetid://15714972287",
	["rebellion_leader"] = "rbxassetid://18926409564",
	["void_hunter"] = "rbxassetid://122370766273698",
	["taliyah"] = "rbxassetid://13989437601",
	["angel"] = "rbxassetid://9166208240",
	["harpoon"] = "rbxassetid://18250634847",
	["void_walker"] = "rbxassetid://78915127961078",
	["spirit_summoner"] = "rbxassetid://95760990786863",
	["triple_shot"] = "rbxassetid://9166208149",
	["void_knight"] = "rbxassetid://73636326782144",
	["regent"] = "rbxassetid://9166208904",
	["vulcan"] = "rbxassetid://9155465543",
	["owl"] = "rbxassetid://12509401147",
	["dasher"] = "rbxassetid://9155467645",
	["disruptor"] = "rbxassetid://11596993583",
	["wizard"] = "rbxassetid://13353923546",
	["aery"] = "rbxassetid://9155463221",
	["agni"] = "rbxassetid://17024640133",
	["alchemist"] = "rbxassetid://9155462512",
	["spearman"] = "rbxassetid://9166207341",
	["beekeeper"] = "rbxassetid://9312831285",
	["falconer"] = "rbxassetid://17022941869",
	["bounty_hunter"] = "rbxassetid://9166208649",
	["blood_assassin"] = "rbxassetid://12520290159",
	["battery"] = "rbxassetid://10159166528",
	["steam_engineer"] = "rbxassetid://15380413567",
	["vesta"] = "rbxassetid://9568930198",
	["beast"] = "rbxassetid://9155465124",
	["dino_tamer"] = "rbxassetid://9872357009",
	["drill"] = "rbxassetid://12955100280",
	["elektra"] = "rbxassetid://13841413050",
	["fisherman"] = "rbxassetid://9166208359",
	["queen_bee"] = "rbxassetid://12671498918",
	["card"] = "rbxassetid://13841410580",
	["frosty"] = "rbxassetid://9166208762",
	["gingerbread_man"] = "rbxassetid://9155464364",
	["ghost_catcher"] = "rbxassetid://9224802656",
	["tinker"] = "rbxassetid://17025762404",
	["ignis"] = "rbxassetid://13835258938",
	["oil_man"] = "rbxassetid://9166206259",
	["jade"] = "rbxassetid://9166306816",
	["dragon_slayer"] = "rbxassetid://10982192175",
	["paladin"] = "rbxassetid://11202785737",
	["pinata"] = "rbxassetid://10011261147",
	["merchant"] = "rbxassetid://9872356790",
	["metal_detector"] = "rbxassetid://9378298061",
	["slime_tamer"] = "rbxassetid://15379766168",
	["nyoka"] = "rbxassetid://17022941410",
	["midnight"] = "rbxassetid://9155462763",
	["pyro"] = "rbxassetid://9155464770",
	["raven"] = "rbxassetid://9166206554",
	["santa"] = "rbxassetid://9166206101",
	["sheep_herder"] = "rbxassetid://9155465730",
	["smoke"] = "rbxassetid://9155462247",
	["spirit_catcher"] = "rbxassetid://9166207943",
	["star_collector"] = "rbxassetid://9872356516",
	["styx"] = "rbxassetid://17014536631",
	["block_kicker"] = "rbxassetid://15382536098",
	["trapper"] = "rbxassetid://9166206875",
	["hatter"] = "rbxassetid://12509388633",
	["ninja"] = "rbxassetid://15517037848",
	["jailor"] = "rbxassetid://11664116980",
	["warrior"] = "rbxassetid://9166207008",
	["mage"] = "rbxassetid://10982191792",
	["void_dragon"] = "rbxassetid://10982192753",
	["cat"] = "rbxassetid://15350740470",
	["wind_walker"] = "rbxassetid://9872355499",
	['skeleton'] = "rbxassetid://120123419412119",
	['winter_lady'] = "rbxassetid://83274578564074",
	['soul_broker'] = 'rbxassetid://130409166262430'
}

local function isFirstPerson()
    if not (lplr.Character and lplr.Character:FindFirstChild("Head")) then
        return false
    end
    return (lplr.Character.Head.Position - gameCamera.CFrame.Position).Magnitude < 2
end

local function isFrozen(entity, threshold)
    threshold = threshold or 10
    local char
    if type(entity) == "table" and entity.Character then
        char = entity.Character
    elseif type(entity) == "Instance" and entity:IsA("Model") then
        char = entity
    elseif entity == nil then
        if not entitylib.isAlive then return false end
        char = entitylib.character.Character
    else
        return false
    end

    local stacks = char:GetAttribute("ColdStacks") or char:GetAttribute("FrostStacks")
               or char:GetAttribute("FreezeStacks") or char:GetAttribute("FROZEN_STACKS")
    if stacks and stacks >= threshold then return true end

    local statusEffects = char:GetAttribute("StatusEffects")
    if type(statusEffects) == "table" then
        for effectName, stackCount in pairs(statusEffects) do
            local nameLower = tostring(effectName):lower()
            if nameLower:match("cold") or nameLower:match("frost") or nameLower:match("freeze") then
                if type(stackCount) == "number" then
                    if stackCount >= threshold then return true end
                elseif stackCount then
                    return true
                end
            end
        end
    end

    if char:FindFirstChild("IceBlock") or char:FindFirstChild("FrozenBlock") or char:FindFirstChild("IceShell") then
        return true
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.WalkSpeed <= 2 then
        return true
    end

    return false
end

local sharedRaycast = RaycastParams.new()
sharedRaycast.FilterType = Enum.RaycastFilterType.Include
sharedRaycast.FilterDescendantsInstances = {workspace:FindFirstChild('Map') or workspace}

local function cloneRaycast()
    local r = RaycastParams.new()
    r.FilterType = sharedRaycast.FilterType
    r.FilterDescendantsInstances = sharedRaycast.FilterDescendantsInstances
    r.RespectCanCollide = sharedRaycast.RespectCanCollide
    return r
end

local function isSword()
    return store.hand and store.hand.toolType == 'sword'
end

local function hasValidWeapon()
    if not store.hand or not store.hand.tool then return false end
    local toolType = store.hand.toolType
    local toolName = store.hand.tool.Name:lower()
    if toolName:find('headhunter') then return true end
    return toolType == 'sword' or toolType == 'bow' or toolType == 'crossbow'
end

local function fixPosition(pos)
    if bedwars and bedwars.BlockController and bedwars.BlockController.getBlockPosition then
        return bedwars.BlockController:getBlockPosition(pos) * 3
    end
    return pos * 3
end

local function getAmmoForProjectile(check)
    for _, item in store.inventory.inventory.items do
        if check.ammoItemTypes and table.find(check.ammoItemTypes, item.itemType) then
            return item.itemType
        end
    end
end

local function getProjectileItems(ammoFilter)
    local items = {}
    for _, item in store.inventory.inventory.items do
        local _itemMeta = bedwars.ItemMeta[item.itemType]
        local proj = _itemMeta and _itemMeta.projectileSource
        local ammo = proj and getAmmoForProjectile(proj)
        if ammo and table.find(ammoFilter, ammo) then
            table.insert(items, {item, ammo, proj.projectileType(ammo), proj})
        end
    end
    return items
end

local function isHoldingItem(keywords, includeProjectileSource)
    if not store.hand or not store.hand.tool then return false end
    local toolName = store.hand.tool.Name:lower()
    for _, kw in ipairs(keywords) do
        if toolName:find(kw) then return true end
    end
    if includeProjectileSource then
        return bedwars.ItemMeta[toolName] and bedwars.ItemMeta[toolName].projectileSource and true or false
    end
    return false
end

local function isHoldingBowCrossbow(includeProjectileSource)
    return isHoldingItem({'bow', 'crossbow', 'headhunter'}, includeProjectileSource)
end

local function isHoldingPickaxe()
    return isHoldingItem({'pickaxe'})
end

local function isEnemy(ent)
    if not ent then return false end
    if ent.Character and ent.Character:HasTag('petrified-player') then return false end
    if ent.Player then
        local myTeam = lplr:GetAttribute('Team')
        local theirTeam = ent.Player:GetAttribute('Team')
        if not myTeam or not theirTeam or myTeam == theirTeam then return false end
        return true
    elseif ent.NPC then
        local npcTeam = ent.Character:GetAttribute('Team')
        if npcTeam then return lplr:GetAttribute('Team') ~= npcTeam end
        return true
    end
    return false
end

local function getShopNPC()
    local shop, items, upgrades, newid = nil, false, false, nil
    if entitylib.isAlive then
        local localPosition = entitylib.character.RootPart.Position
        for _, v in store.shop do
            if (v.RootPart.Position - localPosition).Magnitude <= 20 then
                shop = v.Upgrades or v.Shop or nil
                upgrades = upgrades or v.Upgrades
                items = items or v.Shop
                newid = v.Shop and v.Id or newid
            end
        end
    end
    return shop, items, upgrades, newid
end

local function isTeammate(player)
    if not lplr or not player then return false end
    local myTeam = lplr:GetAttribute('Team')
    local theirTeam = player:GetAttribute('Team')
    return myTeam and theirTeam and myTeam == theirTeam
end

local function getPlayerName(player, useDisplayName)
    if not player then return '' end
    return (useDisplayName and player.DisplayName ~= "" and player.DisplayName) or player.Name
end

local armorTiers = {'none','leather_chestplate','iron_chestplate','diamond_chestplate','emerald_chestplate'}
local function getArmorTier(player)
    if not player or not store.inventories[player] then return 0 end
    local chest = store.inventories[player].armor and store.inventories[player].armor[5]
    if not chest or chest == 'empty' then return 1 end
    return table.find(armorTiers, chest.itemType) or 1
end

local function checkFaceAdjacent(pos, faces)
    faces = faces or {
        Vector3.new(3,0,0), Vector3.new(-3,0,0), Vector3.new(0,3,0),
        Vector3.new(0,-3,0), Vector3.new(0,0,3), Vector3.new(0,0,-3)
    }
    for _, v in ipairs(faces) do
        if getPlacedBlock(pos + v) then return true end
    end
    return false
end

local _isAboveVoidParams = RaycastParams.new()
_isAboveVoidParams.FilterType = Enum.RaycastFilterType.Exclude
local function isAboveVoid(position)
    _isAboveVoidParams.FilterDescendantsInstances = {entitylib.character.Character}
    local result = workspace:Raycast(position, Vector3.new(0, -500, 0), _isAboveVoidParams)
    return result == nil
end

local function hasFaceBelowOrSide(pos)
    if getPlacedBlock(pos - Vector3.new(0,3,0)) then return true end
    local sides = {Vector3.new(3,0,0), Vector3.new(-3,0,0), Vector3.new(0,0,3), Vector3.new(0,0,-3)}
    for _, v in ipairs(sides) do
        if getPlacedBlock(pos + v) then return true end
    end
    return false
end

local function nearCorner(poscheck, pos)
    local start = poscheck - Vector3.new(3,3,3)
    local fin = poscheck + Vector3.new(3,3,3)
    local dir = (pos - poscheck).Unit * 100
    local check = poscheck + dir
    return Vector3.new(
        math.clamp(check.X, start.X, fin.X),
        math.clamp(check.Y, start.Y, fin.Y),
        math.clamp(check.Z, start.Z, fin.Z)
    )
end

local function blockProximity(pos, rangeBlocks)
    rangeBlocks = rangeBlocks or 21
    local mag, best = 60, nil
    local blocks = getBlocksInPoints(
        bedwars.BlockController:getBlockPosition(pos - Vector3.new(rangeBlocks,rangeBlocks,rangeBlocks)),
        bedwars.BlockController:getBlockPosition(pos + Vector3.new(rangeBlocks,rangeBlocks,rangeBlocks))
    )
    for _, v in ipairs(blocks) do
        local bp = nearCorner(v, pos)
        local d = (pos - bp).Magnitude
        if hasFaceBelowOrSide(bp) and d < mag then
            mag, best = d, bp
        end
    end
    return best
end

local function isGUIOpen()
    return bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN)
        or bedwars.AppController:isLayerOpen(bedwars.UILayers.DIALOG)
        or bedwars.AppController:isLayerOpen(bedwars.UILayers.POPUP)
        or bedwars.AppController:isAppOpen('BedwarsItemShopApp')
        or (bedwars.Store:getState().Inventory and bedwars.Store:getState().Inventory.open)
end

local function isTargetValid(ent, maxDist, checkWalls)
    if not ent or not ent.RootPart or not ent.Character then return false end
    if not entitylib.isAlive then return false end
    local dist = (ent.RootPart.Position - entitylib.character.RootPart.Position).Magnitude
    if dist > maxDist then return false end
    if checkWalls then
        local ray = workspace:Raycast(
            entitylib.character.RootPart.Position,
            (ent.RootPart.Position - entitylib.character.RootPart.Position),
            sharedRaycast
        )
        if ray then return false end
    end
    local hum = ent.Character:FindFirstChild("Humanoid")
    return hum and hum.Health > 0
end

local function getTargetByPriority(originPos, range, opts)
    opts = opts or {}
    local players = opts.players == nil and true or opts.players
    local npcs = opts.npcs or false
    local walls = opts.walls or false
    local sort = opts.sort or 'distance' -- 'health','armor','damage'
    local damageTracker = opts.damageTracker 

    local valid = {}
    for _, ent in ipairs(entitylib.List) do
        if (players and ent.Player) or (npcs and ent.NPC) then
            if isEnemy(ent) and ent.RootPart then
                local dist = (ent.RootPart.Position - originPos).Magnitude
                if dist <= range then
                    if walls then
                        local ray = workspace:Raycast(originPos, (ent.RootPart.Position - originPos), sharedRaycast)
                        if not ray then
                            table.insert(valid, ent)
                        end
                    else
                        table.insert(valid, ent)
                    end
                end
            end
        end
    end
    if #valid == 0 then return nil end

    if sort == 'distance' then
        table.sort(valid, function(a,b)
            return (a.RootPart.Position - originPos).Magnitude < (b.RootPart.Position - originPos).Magnitude
        end)
    elseif sort == 'damage' and damageTracker then
        table.sort(valid, function(a,b)
            local keyA = a.Player and a.Player.UserId or tostring(a)
            local keyB = b.Player and b.Player.UserId or tostring(b)
            return (damageTracker[keyA] or 0) > (damageTracker[keyB] or 0)
        end)
    end
    return valid[1]
end

local isMobile = inputService.TouchEnabled and not inputService.KeyboardEnabled and not inputService.MouseEnabled

local function getTeammates(namesOnly)
    local result = {}
    local myTeam = lplr:GetAttribute('Team')
    if not myTeam then return result end
    for _, player in playersService:GetPlayers() do
        if player ~= lplr and player:GetAttribute('Team') == myTeam then
            if namesOnly then
                table.insert(result, player.Name)
            elseif player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
                table.insert(result, player)
            end
        end
    end
    if namesOnly then
        table.sort(result)
    end
    return result
end

local function getNearestTeammateInRange(range, condition)
    if not entitylib.isAlive then return nil end
    local myPos = entitylib.character.RootPart.Position
    local nearest = nil
    local nearestDist = math.huge
    for _, player in ipairs(getTeammates()) do
        if player.Character and player.Character.PrimaryPart then
            local dist = (player.Character.PrimaryPart.Position - myPos).Magnitude
            if dist <= range then
                if condition and not condition(player) then continue end
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = player
                end
            end
        end
    end
    return nearest
end

local function getPlayerHealth(player)
    if not player or not player.Character then return 0, 100 end
    local health = player.Character:GetAttribute('Health') or (player.Character:FindFirstChildOfClass('Humanoid') and player.Character.Humanoid.Health) or 0
    local maxHealth = player.Character:GetAttribute('MaxHealth') or (player.Character:FindFirstChildOfClass('Humanoid') and player.Character.Humanoid.MaxHealth) or 100
    return health, maxHealth
end

local function getPlayerHealthPercent(player)
    local health, maxHealth = getPlayerHealth(player)
    if maxHealth == 0 then return 0 end
    return (health / maxHealth) * 100
end

local function leftClick()
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
		task.wait(0.05)
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
	end)
end

local function getWorldFolder()
    local Map = workspace:FindFirstChild("Map")
    if not Map then return nil end
    local Worlds = Map:FindFirstChild("Worlds")
    if not Worlds then return nil end
    for _, world in Worlds:GetChildren() do
        return world
    end
    return nil
end

local function getPickaxeSlot()
	for i, v in store.inventory.hotbar do
		if v.item and bedwars.ItemMeta[v.item.itemType] then
			local meta = bedwars.ItemMeta[v.item.itemType]
			if meta.breakBlock then
				return i - 1
			end
		end
	end
	return nil
end

local function getScaffoldBlockForModule(limitItem)
	if limitItem.Enabled then
		if store.hand.toolType == 'block' then
			return store.hand.tool.Name
		end
		return nil
	else
		local wool = getWool()
		if wool then
			return wool
		else
			for _, item in store.inventory.inventory.items do
				if bedwars.ItemMeta[item.itemType].block then
					return item.itemType
				end
			end
		end
	end
	return nil
end
	
run(function()
    if isMobile then
        local AutoClicker
        local CPS
        local BlockCPS = {}
        local Thread

        local function getSafeCPS()
            if store.hand and store.hand.toolType == 'block' and BlockCPS and BlockCPS.GetRandomValue then
                return BlockCPS
            end
            if CPS and CPS.GetRandomValue then
                return CPS
            end
            return nil
        end

        local function AutoClick()
            if Thread then
                task.cancel(Thread)
                Thread = nil
            end

            local initialCPS = getSafeCPS()
            if not initialCPS then return end

            Thread = task.delay(1 / initialCPS.GetRandomValue(), function()
                repeat
                    if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
                        local blockPlacer = bedwars.BlockPlacementController and bedwars.BlockPlacementController.blockPlacer
                        local toolType = store.hand and store.hand.toolType

                        if toolType == 'block' and blockPlacer then
                            task.spawn(function()
                                blockPlacer:autoBridge(workspace:GetServerTimeNow() - bedwars.KnockbackController:getLastKnockbackTime() >= 0.2)
                            end)
                        elseif toolType == 'sword' then
                            bedwars.SwordController:swingSwordAtMouse(0.39)
                        end
                    end

                    local currentCPS = getSafeCPS()
                    if not currentCPS then
                        task.wait(0.1)
                    else
                        task.wait(1 / currentCPS.GetRandomValue())
                    end
                until not AutoClicker.Enabled
            end)
        end

        local function StopClick()
            if Thread then
                task.cancel(Thread)
                Thread = nil
            end
        end

        AutoClicker = vape.Categories.Combat:CreateModule({
            Name = 'AutoClicker',
            Function = function(callback)
                if callback then
                    AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            AutoClick()
                        end
                    end))

                    AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            StopClick()
                        end
                    end))

                    for _, v in {'2', '5'} do
                        pcall(function()
                            AutoClicker:Clean(lplr.PlayerGui.MobileUI[v].MouseButton1Down:Connect(AutoClick))
                            AutoClicker:Clean(lplr.PlayerGui.MobileUI[v].MouseButton1Up:Connect(StopClick))
                        end)
                    end
                else
                    StopClick()
                end
            end,
            Tooltip = 'clicks for you'
        })

        CPS = AutoClicker:CreateTwoSlider({
            Name = 'CPS',
            Min = 1,
            Max = 9,
            DefaultMin = 7,
            DefaultMax = 7
        })

        AutoClicker:CreateToggle({
            Name = 'Place Blocks',
            Default = true,
            Function = function(callback)
                if BlockCPS.Object then
                    BlockCPS.Object.Visible = callback
                end
            end
        })

        BlockCPS = AutoClicker:CreateTwoSlider({
            Name = 'Block CPS',
            Min = 1,
            Max = 20,
            DefaultMin = 12,
            DefaultMax = 12,
            Darker = true
        })

        task.defer(function()
            if BlockCPS and BlockCPS.Object then
                BlockCPS.Object.Visible = PlaceBlocksToggle and PlaceBlocksToggle.Enabled
            end
        end)

    else
        local AutoClicker
        local CPS
        local BlockCPS = {}
        local SwordCPS = {}
        local PlaceBlocksToggle
        local SwingSwordToggle
        local Thread

        local task_wait = task.wait
        local task_spawn = task.spawn
        local workspace_GetServerTimeNow = function() return workspace:GetServerTimeNow() end

        local function getSafeCPS()
            local toolType = store.hand and store.hand.toolType or nil
            if toolType == 'block' and PlaceBlocksToggle and PlaceBlocksToggle.Enabled and BlockCPS and BlockCPS.GetRandomValue then
                return BlockCPS
            elseif toolType == 'sword' and SwingSwordToggle and SwingSwordToggle.Enabled and SwordCPS and SwordCPS.GetRandomValue then
                return SwordCPS
            elseif CPS and CPS.GetRandomValue then
                return CPS
            end
            return nil
        end

        local function AutoClickskid()
            if Thread then task.cancel(Thread) end
            Thread = task_spawn(function()
                repeat
                    if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
                        local toolType = store.hand and store.hand.toolType
                        if PlaceBlocksToggle.Enabled and toolType == 'block' then
                            local blockPlacer = bedwars.BlockPlacementController and bedwars.BlockPlacementController.blockPlacer
                            if blockPlacer then
                                if (workspace_GetServerTimeNow() - bedwars.BlockCpsController.lastPlaceTimestamp) >= ((1 / 12) * 0.5) then
                                    local mouseinfo = blockPlacer.clientManager:getBlockSelector():getMouseInfo(0)
                                    if mouseinfo and mouseinfo.placementPosition == mouseinfo.placementPosition then
                                        task_spawn(blockPlacer.placeBlock, blockPlacer, mouseinfo.placementPosition)
                                    end
                                end
                            end
                        elseif SwingSwordToggle.Enabled and toolType == 'sword' then
                            bedwars.SwordController:swingSwordAtMouse(0.39)
                        end
                    end

                    local currentCPS = getSafeCPS()
                    task_wait(1 / (currentCPS and currentCPS.GetRandomValue() or 7))
                until not AutoClicker.Enabled
            end)
        end

        local function StopAutoClick()
            if Thread then
                task.cancel(Thread)
                Thread = nil
            end
        end

        local MIN_HOLD_TIME = 0.12
        local ActivationScheduled = nil

        AutoClicker = vape.Categories.Combat:CreateModule({
            Name = 'AutoClicker',
            Function = function(callback)
                if callback then
                    AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            ActivationScheduled = task.delay(MIN_HOLD_TIME, function()
                                ActivationScheduled = nil
                                if inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                                    AutoClickskid()
                                end
                            end)
                        end
                    end))
                    AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                            if ActivationScheduled then
                                task.cancel(ActivationScheduled)
                                ActivationScheduled = nil
                            end
                            if Thread then
                                task.cancel(Thread)
                                Thread = nil
                            end
                        end
                    end))
                else
                    StopAutoClick()
                end
            end,
            Tooltip = 'clicks for you'
        })

        PlaceBlocksToggle = AutoClicker:CreateToggle({
            Name = 'Place Blocks',
            Default = false,
            Function = function(callback)
                task.defer(function()
                    if BlockCPS and BlockCPS.Object then BlockCPS.Object.Visible = callback end
                end)
            end
        })

        BlockCPS = AutoClicker:CreateTwoSlider({
            Name = 'Block CPS',
            Min = 1,
            Max = 20,
            DefaultMin = 12,
            DefaultMax = 12,
            Darker = true
        })

        SwingSwordToggle = AutoClicker:CreateToggle({
            Name = 'Swing Sword',
            Default = false,
            Function = function(callback)
                if SwordCPS.Object then SwordCPS.Object.Visible = callback end
            end
        })

        SwordCPS = AutoClicker:CreateTwoSlider({
            Name = 'Sword CPS',
            Min = 1,
            Max = 9,
            DefaultMin = 7,
            DefaultMax = 7,
            Darker = true
        })

        task.defer(function()
            if BlockCPS and BlockCPS.Object then
                BlockCPS.Object.Visible = PlaceBlocksToggle and PlaceBlocksToggle.Enabled
            end
            if SwordCPS and SwordCPS.Object then
                SwordCPS.Object.Visible = SwingSwordToggle and SwingSwordToggle.Enabled
            end
        end)
    end
end)  

run(function()
    local KitRender
    local Players = playersService
    local player = Players.LocalPlayer
    local PlayerGui = player:WaitForChild("PlayerGui")

    local activeLoops = {}
    local updateDebounce = {}
    local retryThread = nil

    local function createkitrender(plr)
        local icon = Instance.new("ImageLabel")
        icon.Name = "SkidV4KitRender" 
        icon.AnchorPoint = Vector2.new(1, 0.5)
        icon.BackgroundTransparency = 1
        icon.Position = UDim2.new(1.05, 0, 0.5, 0)
        icon.Size = UDim2.new(1.5, 0, 1.5, 0)
        icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
        icon.ImageTransparency = 0.4
        icon.ScaleType = Enum.ScaleType.Crop
        local uar = Instance.new("UIAspectRatioConstraint")
        uar.AspectRatio = 1
        uar.AspectType = Enum.AspectType.FitWithinMaxSize
        uar.DominantAxis = Enum.DominantAxis.Width
        uar.Parent = icon
		local kit = plr:GetAttribute("PlayingAsKits")
		local meta = bedwars.BedwarsKitMeta and (bedwars.BedwarsKitMeta[kit] or bedwars.BedwarsKitMeta.none)
        local newImage = (meta and meta.renderImage) or kitImageIds[kit] or kitImageIds["none"]
		icon.Image = newImage
        return icon
    end

    local function removeallkitrenders()
        for key, _ in pairs(activeLoops) do
            activeLoops[key] = nil
        end
        table.clear(updateDebounce)
        
        if retryThread then
            task.cancel(retryThread)
            retryThread = nil
        end
        
        for _, v in ipairs(PlayerGui:GetDescendants()) do
            if v:IsA("ImageLabel") and v.Name == "SkidV4KitRender" then  
                v:Destroy()
            end
        end
    end

    local function refreshicon(icon, plr)
        if not icon or not icon.Parent then return end
        local kit = plr:GetAttribute("PlayingAsKits")
        local meta = bedwars.BedwarsKitMeta and (bedwars.BedwarsKitMeta[kit] or bedwars.BedwarsKitMeta.none)
        local newImage = (meta and meta.renderImage) or kitImageIds[kit] or kitImageIds["none"]
        if icon.Image ~= newImage then
            icon.Image = newImage
        end
    end

    local function findPlayer(label, container)
        local render = container:FindFirstChild("PlayerRender", true)
        if render and render:IsA("ImageLabel") and render.Image then
            local userId = string.match(render.Image, "id=(%d+)")
            if userId then
                local plr = Players:GetPlayerByUserId(tonumber(userId))
                if plr then return plr end
            end
        end
        local text = label.Text
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Name == text or plr.DisplayName == text or plr:GetAttribute("DisguiseDisplayName") == text then
                return plr
            end
            local smName = nil
            pcall(function()
                smName = bedwars.KnitClient.Controllers.StreamerModeController:getDisplayName(plr)
            end)
            if smName and smName == text then
                return plr
            end
        end
    end

    local function handleLabel(label)
        if not (label:IsA("TextLabel") and label.Name == "PlayerName") then return end
        task.spawn(function()
            local container = label.Parent
            for _ = 1, 3 do
                if container and container.Parent then
                    container = container.Parent
                end
            end
            if not container or not container:IsA("Frame") then return end
            
            local playerFound = findPlayer(label, container)
            if not playerFound then
                task.wait(0.5)
                playerFound = findPlayer(label, container)
            end
            if not playerFound then return end
            if not playerFound:GetAttribute("PlayingAsKits") then
                task.wait(1)
                if not playerFound:GetAttribute("PlayingAsKits") then return end
            end
            local myTeam = lplr:GetAttribute('Team')
            local theirTeam = playerFound:GetAttribute('Team')
            if not myTeam or not theirTeam or myTeam == theirTeam then return end
            
            container.Name = playerFound.Name
            local card = container:FindFirstChild("1") and container["1"]:FindFirstChild("MatchDraftPlayerCard")
            if not card then return end
            
            local icon = card:FindFirstChild("SkidV4KitRender")  
            if not icon then
                icon = createkitrender(playerFound)
                icon.Parent = card
            end
            
            local loopKey = playerFound.UserId
            if activeLoops[loopKey] then
                activeLoops[loopKey] = nil
            end
            activeLoops[loopKey] = true
			task.spawn(function()
				while activeLoops[loopKey] and KitRender.Enabled do
					if not container or not container.Parent then
						break
					end
					if playerFound and icon and icon.Parent then
						refreshicon(icon, playerFound)
					end
					task.wait(0.3)
				end
				activeLoops[loopKey] = nil
				updateDebounce[loopKey] = nil
			end)
        end)
    end

    local activeConnections = {}
    local kitLabels = {}
    local squadUpdateDebounce = {}
    local processedPlayers = {}

    local function createKitLabel(parent, kitImage)
        if kitLabels[parent] then kitLabels[parent]:Destroy() end
        local kitLabel = Instance.new("ImageLabel")
        kitLabel.Name = "SkidV4KitIcon"
        kitLabel.Size = UDim2.new(1, 0, 1, 0)
        kitLabel.Position = UDim2.new(1.1, 0, 0, 0)
        kitLabel.BackgroundTransparency = 1
        kitLabel.Image = kitImage
        kitLabel.Parent = parent
        kitLabels[parent] = kitLabel
        return kitLabel
    end

    local function setupSquadsKitRender(obj)
        if obj.Name == "PlayerRender" and obj.Parent and obj.Parent.Parent and obj.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Parent.Name == "MatchDraftTeamCardRow" then
            local Rank = obj.Parent:FindFirstChild('3')
            if not Rank then return end
            local userId = string.match(obj.Image, "id=(%d+)")
            if not userId then return end
            local plr = playersService:GetPlayerByUserId(tonumber(userId))
            if not plr then return end
            local myTeam = lplr:GetAttribute('Team')
            local theirTeam = plr:GetAttribute('Team')
            if not myTeam or not theirTeam or myTeam == theirTeam then return end
            local loopKey = plr.UserId
            processedPlayers[loopKey] = true
            if activeConnections[loopKey] then activeConnections[loopKey]:Disconnect() activeConnections[loopKey] = nil end
            local function updateKit()
                if not KitRender.Enabled then return end
                if not Rank or not Rank.Parent then
                    if activeConnections[loopKey] then activeConnections[loopKey]:Disconnect() activeConnections[loopKey] = nil end
                    if kitLabels[Rank] then kitLabels[Rank]:Destroy() kitLabels[Rank] = nil end
                    return
                end
                local kitName = plr:GetAttribute("PlayingAsKits") or "none"
                local render = bedwars.BedwarsKitMeta[kitName] or bedwars.BedwarsKitMeta.none
                if kitLabels[Rank] then kitLabels[Rank].Image = render.renderImage
                else createKitLabel(Rank, render.renderImage) end
            end
            updateKit()
            local connection = plr:GetAttributeChangedSignal("PlayingAsKits"):Connect(function()
                local t = tick()
                if not squadUpdateDebounce[loopKey] or (t - squadUpdateDebounce[loopKey]) >= 0.1 then
                    squadUpdateDebounce[loopKey] = t
                    updateKit()
                end
            end)
            activeConnections[loopKey] = connection
            KitRender:Clean(connection)
        end
    end

    local function setupSquadsRender()
        local teams = lplr.PlayerGui:FindFirstChild("MatchDraftApp")
        if not teams then return false end
        task.wait(0.5)
        for _, obj in teams:GetDescendants() do
            if KitRender.Enabled then task.spawn(function() setupSquadsKitRender(obj) end) end
        end
        KitRender:Clean(teams.DescendantAdded:Connect(function(obj)
            if KitRender.Enabled then task.wait(0.1) setupSquadsKitRender(obj) end
        end))
        return true
    end

    local function removeSquadsRender()
        for key, connection in pairs(activeConnections) do
            if connection then connection:Disconnect() end
            activeConnections[key] = nil
        end
        for parent, label in pairs(kitLabels) do
            if label then label:Destroy() end
            kitLabels[parent] = nil
        end
        table.clear(squadUpdateDebounce)
        table.clear(processedPlayers)
    end

    local function setupKitRender()
        local draftApp = PlayerGui:FindFirstChild("MatchDraftApp")
        if not draftApp then return false end

        for _, child in ipairs(draftApp:GetDescendants()) do
            if KitRender.Enabled then handleLabel(child) end
        end

        KitRender:Clean(draftApp.DescendantAdded:Connect(function(child)
            if KitRender.Enabled then handleLabel(child) end
        end))

        KitRender:Clean(draftApp.AncestryChanged:Connect(function()
            if not draftApp.Parent then
                removeallkitrenders()
            end
        end))

        return true
    end

    KitRender = vape.Categories.Utility:CreateModule({
        Name = "KitRender",
        Tooltip = "renders everyone kit during banning(for 5v5 or Squads)",
        Function = function(callback)
            if callback then
                local draftApp = lplr.PlayerGui:FindFirstChild("MatchDraftApp")
                local isSquads = draftApp and draftApp:FindFirstChild("MatchDraftTeamCardRow", true) ~= nil
                local setupFn = isSquads and setupSquadsRender or setupKitRender
				setupFn()
            else
                removeallkitrenders()
                removeSquadsRender()
            end
        end
    })
end)
	
run(function()
	local Attack
	local Mine
	local Place
	local oldAttackReach, oldMineReach, oldPlaceReach
	local SwordReach, MineReach

	Reach = vape.Categories.Combat:CreateModule({
		Name = 'Reach',
		Function = function(callback)
			if callback then
				if SwordReach and SwordReach.Enabled then
					oldAttackReach = bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE
					bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Attack.Value + 2
				end
				
				task.spawn(function()
					repeat task.wait(0.1) until bedwars.BlockBreakController or not Reach.Enabled
					if not Reach.Enabled or not MineReach or not MineReach.Enabled then return end
					
					pcall(function()
						local blockBreaker = bedwars.BlockBreakController:getBlockBreaker()
						if blockBreaker then
							oldMineReach = oldMineReach or blockBreaker:getRange()
							blockBreaker:setRange(Mine.Value)
						end
					end)
				end)
				
				local _reachLoopThread = task.spawn(function()
					while Reach.Enabled do
						task.wait(5)
						if not Reach.Enabled then break end
						if SwordReach.Enabled and bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE ~= Attack.Value + 2 then
							bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Attack.Value + 2
						end
						if MineReach.Enabled then
							pcall(function()
								local blockBreaker = bedwars.BlockBreakController:getBlockBreaker()
								if blockBreaker and blockBreaker:getRange() ~= Mine.Value then
									blockBreaker:setRange(Mine.Value)
								end
							end)
						end
					end
				end)
				Reach:Clean(function()
					if _reachLoopThread then
						pcall(task.cancel, _reachLoopThread)
						_reachLoopThread = nil
					end
				end)
			else
				if oldAttackReach then
					bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = oldAttackReach
				end
				
				if oldMineReach then
					pcall(function()
						local blockBreaker = bedwars.BlockBreakController:getBlockBreaker()
						if blockBreaker then
							blockBreaker:setRange(oldMineReach)
						end
					end)
				end

				oldAttackReach, oldMineReach = nil, nil
			end
		end,
		Tooltip = 'increases reach for attacking, mining'
	})
	
	SwordReach = Reach:CreateToggle({
		Name = 'Sword Reach',
		Default = true,
		Function = function(v)
			if Attack then Attack.Object.Visible = v end
			if Reach.Enabled then
				if v then
					bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Attack.Value + 2
				else
					bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = oldAttackReach or 14.4
				end
			end
		end
	})

	Attack = Reach:CreateSlider({
		Name = 'Attack Range',
		Darker = true,
		Visible = true,
		Min = 0,
		Max = 20,
		Default = 18,
		Function = function(val)
			if Reach.Enabled then
				bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = val + 2
			end
		end,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	
	MineReach = Reach:CreateToggle({
		Name = 'Mine Reach',
		Default = false,
		Function = function(v)
			if Mine then Mine.Object.Visible = v end
		end
	})

	Mine = Reach:CreateSlider({
		Name = 'Mine Range',
		Darker = true,
		Visible = false,
		Min = 0,
		Max = 30,
		Default = 18,
		Function = function(val)
			if Reach.Enabled then
				pcall(function()
					local blockBreaker = bedwars.BlockBreakController:getBlockBreaker()
					if blockBreaker then
						blockBreaker:setRange(val)
					end
				end)
			end
		end,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	local Sprint
	local old
	
	Sprint = vape.Categories.Combat:CreateModule({
		Name = 'Sprint',
		Function = function(callback)
			if callback then
				if inputService.TouchEnabled then 
					pcall(function() 
						lplr.PlayerGui.MobileUI['4'].Visible = false 
					end) 
				end
				old = bedwars.SprintController.stopSprinting
				bedwars.SprintController.stopSprinting = function(...)
					local call = old(...)
					bedwars.SprintController:startSprinting()
					return call
				end
				Sprint:Clean(entitylib.Events.LocalAdded:Connect(function() 
					task.delay(0.1, function() 
						bedwars.SprintController:stopSprinting() 
					end) 
				end))
				bedwars.SprintController:stopSprinting()
			else
				if inputService.TouchEnabled then 
					pcall(function() 
						lplr.PlayerGui.MobileUI['4'].Visible = true 
					end) 
				end
				bedwars.SprintController.stopSprinting = old
				bedwars.SprintController:stopSprinting()
			end
		end,
	})
end)
	
run(function()
	local TriggerBot
	local SwordToggle
	local SwordCPS 
	local ProjectileToggle
	local ProjectileFirerate
	local ProjectileLegitSwitch
	local ProjectileDelayShoot

	local rayparms = RaycastParams.new()
	rayparms.FilterType = sharedRaycast.FilterType
	rayparms.FilterDescendantsInstances = sharedRaycast.FilterDescendantsInstances
	rayparms.RespectCanCollide = sharedRaycast.RespectCanCollide
	rayparms.FilterDescendantsInstances = {lplr.Character}

	local lastCapture = 0
	local doAttack = false
	local lastShot = tick()
	local t = 0

	TriggerBot = vape.Categories.Combat:CreateModule({
		Name = 'TriggerBot',
		Disabled = canEngine,
		Function = function(callback)
			if callback then
				lastCapture = 0
				doAttack = false
				
				TriggerBot:Clean(lplr.CharacterAdded:Connect(function()
					rayparms.FilterDescendantsInstances = {lplr.Character}
				end))

				t = 0.016

				repeat
					if not entitylib.isAlive then
						t = 0.16
						task.wait(t)
						continue
					end

					if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then

						if SwordToggle.Enabled then
							if store.hand.toolType == 'sword' and bedwars.DaoController.chargingMaid == nil and not bedwars.SwordController.disableSwingState then
								local attackRange = bedwars.ItemMeta[store.hand.tool.Name].sword.attackRange
						
								local unit = lplr:GetMouse().UnitRay
								local localPos = entitylib.character.RootPart.Position
								local rayRange = (attackRange or 12.4)
								local ray = bedwars.QueryUtil:raycast(unit.Origin, unit.Direction * 200, rayparms)
								
								if ray and (localPos - ray.Instance.Position).Magnitude <= rayRange then
									for _, ent in entitylib.List do
										doAttack = ent.Targetable and ray.Instance:IsDescendantOf(ent.Character) and (localPos - ent.RootPart.Position).Magnitude <= rayRange
										if doAttack then
											break
										end
									end
								end
						
								doAttack = doAttack or bedwars.SwordController:getTargetInRegion(attackRange or 4.13 * 3, 0)
								
								if doAttack then
									t = (1 / SwordCPS.GetRandomValue())
									bedwars.SwordController:swingSwordAtMouse()
								else
									t = 0.028
								end

							elseif store.equippedKit == 'summoner' and store.hand.tool.Name:find('summoner_claw') then
								local unit = lplr:GetMouse().UnitRay
								local localPos = entitylib.character.RootPart.Position
								local rayRange = 14.4
								local ray = bedwars.QueryUtil:raycast(unit.Origin, unit.Direction * 200, rayparms)
								
								doAttack = false
								if ray and (localPos - ray.Instance.Position).Magnitude <= rayRange then
									for _, e in entitylib.List do
										if e.Targetable and ray.Instance:IsDescendantOf(e.Character) and (localPos - e.RootPart.Position).Magnitude <= rayRange then
											doAttack = true
											break
										end
									end
								end
								
								doAttack = doAttack or bedwars.SwordController:getTargetInRegion(4.8 * 3, 0)
								
								if doAttack then
									t = (1 / SwordCPS.GetRandomValue())
									bedwars.SummonerClawController:clawAttack(lplr, entitylib.character.RootPart.Position, gameCamera.CFrame.LookVector, store.hand.tool.Name or 'summoner_claw_1')
									bedwars.Client:Get(remotes.SummonerClawAttack):SendToServer({
										position = entitylib.character.RootPart.Position,
										direction = gameCamera.CFrame.LookVector,
										clientTime = workspace:GetServerTimeNow()
									})
								else
									t = 0.065
								end
							else
								t = 0.1
							end
						end
						if ProjectileToggle.Enabled then
							local toolName = store.hand.tool.Name:lower()
							local meta = bedwars.ItemMeta[toolName]

							if meta and meta.projectileSource then
								local ping = lplr:GetNetworkPing() or 0
								local fireDelay = 0.2 + ping + (ProjectileFirerate.Value or 0.2)

								if (tick() - lastShot) >= fireDelay then
									mouse1click()
									lastShot = tick()

									t = (ProjectileDelayShoot.Value or 0.1) + 0.015
									local itemType = nil
									local items = store.inventory.inventory.items
									for _, item in items do
										local _itemMeta = bedwars.ItemMeta[item.itemType]
										local proj = _itemMeta and _itemMeta.projectileSource
										if not proj then continue end
										if not proj.ammoItemTypes then continue end
										for _, inv in items do
											if table.find(proj.ammoItemTypes, inv.itemType) then
												itemType = item.itemType
												break
											end
										end
										if itemType then break end
									end
									if ProjectileLegitSwitch.Enabled then
										task.wait(t - 0.045)
										local holdingCrossbow = itemType and itemType:find('crossbow')
										local holdingBow = itemType and itemType:find('bow') and not holdingCrossbow

										if holdingCrossbow then
											pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_CROSSBOW_FIRE) end)
											bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.CROSSBOW_FIRE)
										elseif holdingBow then
											pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_CROSSBOW_FIRE) end)
											bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.BOW_FIRE)
										else
											local shootAnim = (bedwars.ItemMeta[toolName].thirdPerson) and (bedwars.ItemMeta[toolName].thirdPerson.shootAnimation)
											if shootAnim then
												bedwars.GameAnimationUtil:playAnimation(lplr, shootAnim)
											end
										end
									end
								else
									t = 0.03
								end
							else
								t = 0.12
							end
						end

					else
						t = 0.1
					end

					task.wait(t)
				until not TriggerBot.Enabled
			end
		end
	})

	SwordToggle = TriggerBot:CreateToggle({
		Name = 'Sword Toggle',
		Tooltip = 'enables the sword toggle',
		Default = true,
		Function = function(callback)
			if SwordCPS then SwordCPS.Object.Visible = callback end
		end
	})

	SwordCPS = TriggerBot:CreateTwoSlider({
		Name = "Sword CPS",
		Tooltip = 'swords cps',
		Min = 0,
		Max = 24,
		DefaultMax = 7,
		DefaultMin = 7,
		Darker = true,
		Visible = SwordToggle.Enabled
	})

	if not inputService.TouchEnabled then
		ProjectileToggle = TriggerBot:CreateToggle({
			Name = 'Projectile Toggle',
			Tooltip = 'enables the projectile toggle',
			Default = false,
			Function = function(callback)
				if ProjectileFirerate then ProjectileFirerate.Object.Visible = callback end
				if ProjectileDelayShoot then ProjectileDelayShoot.Object.Visible = callback end
				if ProjectileLegitSwitch then ProjectileLegitSwitch.Object.Visible = callback end
			end
		})

		ProjectileFirerate = TriggerBot:CreateSlider({
			Name = "Projectile Fire Rate",
			Tooltip = 'projectile fire rate',
			Min = 0,
			Max = 4,
			Default = 0.2,
			Decimal = 100,
			Darker = true,
			Visible = ProjectileToggle.Enabled
		})

		ProjectileDelayShoot = TriggerBot:CreateSlider({
			Name = "Projectile Delay Shoot",
			Tooltip = 'projectile delay in shooting',
			Min = 0,
			Max = 2,
			Default = 0.1,
			Decimal = 100,
			Darker = true,
			Visible = ProjectileToggle.Enabled
		})

		ProjectileLegitSwitch = TriggerBot:CreateToggle({
			Name = "Projectile Legit Switch",
			Tooltip = 'should switch to the projectile',
			Default = false,
			Darker = true,
			Visible = ProjectileToggle.Enabled
		})
	end
end)
	
run(function()
	local Velocity
	local Vertical
	local VerticalChance
	local Horizontal
	local HorizontalChance
	local Mode
	local DelayGround
	local DelayAir
	local Targetting
	local Chance

	local old = nil
	local rand = Random.new()

	Velocity = vape.Categories.Combat:CreateModule({
		Name = 'Velocity',
		Tooltip = 'allows you to edit ur velocity',
		Function = function(callback)
			if callback then
				old = bedwars.KnockbackUtil.applyKnockback
				Velocity:Clean(vapeEvents.TakeKnockback.Event:Connect(function(root, mass, dir, knockback, ...)
					local args = {...}
					local clone = table.clone(knockback)

					local air, ground = false, false
					task.delay(DelayAir.Value / 1000, function()
						clone.horizontal = knockback.horizontal or 1
						air = true
					end)
					task.delay(DelayGround.Value / 1000, function()
						clone.vertical = knockback.vertical or 1
						ground = true
					end)
					repeat task.wait(0.1) until air
					repeat task.wait(0.05) until ground
					old(root, mass, dir, clone, unpack(args))
				end))

				bedwars.KnockbackUtil.applyKnockback = function(root, mass, dir, knockback, ...)
					local chance = rand:NextNumber(0, 100)
					chance = math.floor(chance)
					if Mode.Value == 'Default' then
						if chance >= Chance.Value then return old(root, mass, dir, knockback, ...) end
					end
						
					local check = (not Targetting.Enabled) or entitylib.EntityPosition({
						Range = 20,
						Part = 'RootPart',
						Players = true
					})
		
					if check then
						knockback = knockback or {}
						if Mode.Value == 'Lag' then
							if chance < Chance.Value then
								return vapeEvents.TakeKnockback:Fire(root, mass, dir, knockback, ...)
							end
						else
							local horiz = (knockback.horizontal or 1) * (Horizontal.Value / 100)
							local vert = (knockback.vertical or 1) * (Vertical.Value / 100)
							chance = rand:NextNumber(0, 100)
							chance = math.floor(chance)
							if Horizontal.Value == 0 and Vertical.Value == 0 and HorizontalChance.Value == 100 and VerticalChance.Value == 100 then return end
							local horizChance = math.floor(rand:NextNumber(0, 100))
							local vertChance = math.floor(rand:NextNumber(0, 100))
							if horizChance >= HorizontalChance.Value then
								horiz = knockback.horizontal
							end
							if vertChance >= VerticalChance.Value then
								vert = knockback.vertical
							end
							knockback.horizontal = horiz
							knockback.vertical = vert
						end
					end
						
					return old(root, mass, dir, knockback, ...)
				end
			else
				bedwars.KnockbackUtil.applyKnockback = old
				old = nil
			end
		end
	})
	Mode = Velocity:CreateDropdown({
		Name = "Mode",
		List = {'Lag','Default'},
		Function = function(val)
			if val == 'Default' then
				if HorizontalChance then HorizontalChance.Object.Visible = true end
				if Horizontal then Horizontal.Object.Visible = true end
				if VerticalChance then VerticalChance.Object.Visible = true end
				if Vertical then Vertical.Object.Visible = true end
				if DelayGround then DelayGround.Object.Visible = false end
				if DelayAir then DelayAir.Object.Visible = false end
			elseif val == 'Lag' then
				if HorizontalChance then HorizontalChance.Object.Visible = false end
				if Horizontal then Horizontal.Object.Visible = false end
				if VerticalChance then VerticalChance.Object.Visible = false end
				if Vertical then Vertical.Object.Visible = false end
				if DelayGround then DelayGround.Object.Visible = true end
				if DelayAir then DelayAir.Object.Visible = true end
			else
				if HorizontalChance then HorizontalChance.Object.Visible = false end
				if Horizontal then Horizontal.Object.Visible = false end
				if VerticalChance then VerticalChance.Object.Visible = false end
				if Vertical then Vertical.Object.Visible = false end
				if DelayGround then DelayGround.Object.Visible = false end
				if DelayAir then DelayAir.Object.Visible = false end
				vape:CreateNotification('Velocity',`Storing packets... returned {val or Mode.Value} report ASAP`,16)
			end
		end
	})
	Vertical = Velocity:CreateSlider({
		Name = "Vertical",
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Visible = (Mode.Value == 'Default')
	})
	VerticalChance = Velocity:CreateSlider({
		Name = "Vertical Chance",
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Suffix = '%',
		Visible = (Mode.Value == 'Default')
	})
	Horizontal = Velocity:CreateSlider({
		Name = "Horizontal",
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Visible = (Mode.Value == 'Default')
	})
	HorizontalChance = Velocity:CreateSlider({
		Name = "Horizontal Chance",
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Suffix = '%',
		Visible = (Mode.Value == 'Default')
	})
	DelayGround = Velocity:CreateSlider({
		Name = "Delay Ground",
		Min = 0,
		Max = 3000,
		Default = 1000,
		Suffix = 'ms',
		Decimal = 1,
		Visible = (Mode.Value == 'Lag')
	})
	DelayAir = Velocity:CreateSlider({
		Name = "Delay Air",
		Min = 0,
		Max = 3000,
		Default = 1000,
		Suffix = 'ms',
		Decimal = 1,
		Visible = (Mode.Value == 'Lag')
	})
	Targetting = Velocity:CreateToggle({
		Name = 'Only when targetting',
		Default = false
	})
	Chance = Velocity:CreateSlider({
		Name = "Chance",
		Min = 0,
		Max = 100,
		Default = 100,
		Decimal = 1,
		Suffix = '%',
	})
end)
	
local AntiFallDirection
run(function()
    local AntiFall
    local Mode
    local Material
    local Color
	local rayCheck = cloneRaycast()
    rayCheck.RespectCanCollide = true

    local math_huge = math.huge
    local tick = tick
    local task_wait = task.wait
    local vector3new = Vector3.new
    local vector3zero = Vector3.zero
    
    local cachedLowGround = math_huge
    local lastGroundScan = 0
    local groundScanInterval = 2 
    
    local function getLowGround()
        local now = tick()
        if now - lastGroundScan < groundScanInterval and cachedLowGround ~= math_huge then
            return cachedLowGround
        end
        
        lastGroundScan = now
        local mag = math_huge
        local blockStore = bedwars.BlockController:getStore()
        local allPositions = blockStore:getAllBlockPositions()
        
        for i = 1, #allPositions do
            local pos = allPositions[i] * 3
            if pos.Y < mag and not getPlacedBlock(pos + vector3new(0, 3, 0)) then
                mag = pos.Y
            end
        end
        
        cachedLowGround = mag
        return mag
    end

    AntiFall = vape.Categories.Blatant:CreateModule({
        Name = 'AntiFall',
        Function = function(callback)
            if callback then
                repeat task_wait() until store.matchState ~= 0 or (not AntiFall.Enabled)
                if not AntiFall.Enabled then return end

                local pos, debounce = getLowGround(), tick()
                if pos ~= math_huge then
                    AntiFallPart = Instance.new('Part')
                    AntiFallPart.Size = vector3new(10000, 1, 10000)
                    AntiFallPart.Transparency = 1 - Color.Opacity
                    AntiFallPart.Material = Enum.Material[Material.Value]
                    AntiFallPart.Color = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
                    AntiFallPart.Position = vector3new(0, pos - 2, 0)
                    AntiFallPart.CanCollide = Mode.Value == 'Collide'
                    AntiFallPart.Anchored = true
                    AntiFallPart.CanQuery = false
                    AntiFallPart.Parent = workspace
                    AntiFall:Clean(AntiFallPart)
                    
                    AntiFall:Clean(AntiFallPart.Touched:Connect(function(touched)
                        if touched.Parent == lplr.Character and entitylib.isAlive and debounce < tick() then
                            debounce = tick() + 0.1
                            
                            if Mode.Value == 'Normal' then
                                local top = getNearGround()
                                if top then
                                    local lastTeleport = lplr:GetAttribute('LastTeleported')
                                    local connection
                                    local frameCounter = 0
                                    
                                    local vapeModules = vape.Modules
                                    local flyEnabled = vapeModules.Fly
                                    local infFlyEnabled = vapeModules.InfiniteFly
                                    local longJumpEnabled = vapeModules.LongJump
                                    
                                    local yMask = vector3new(1, 0, 1)
                                    local yOnly = vector3new(0, 1, 0)
                                    
                                    connection = runService.PreSimulation:Connect(function()
                                        frameCounter = frameCounter + 1
                                        
                                        if frameCounter % 5 == 0 then
                                            if flyEnabled.Enabled or infFlyEnabled.Enabled or longJumpEnabled.Enabled then
                                                connection:Disconnect()
                                                AntiFallDirection = nil
                                                return
                                            end
                                        end

                                        if entitylib.isAlive and lplr:GetAttribute('LastTeleported') == lastTeleport then
                                            local root = entitylib.character.RootPart
                                            local rootPos = root.Position
                                            local delta = (top - rootPos) * yMask
                                            
                                            AntiFallDirection = delta.Unit == delta.Unit and delta.Unit or vector3zero
                                            root.Velocity *= yMask
                                            
                                            if frameCounter % 3 == 0 then
                                                rayCheck.FilterDescendantsInstances = {gameCamera, lplr.Character}
                                                rayCheck.CollisionGroup = root.CollisionGroup

                                                local ray = workspace:Raycast(rootPos, AntiFallDirection, rayCheck)
                                                if ray then
                                                    for i = 1, 5 do
                                                        local dpos = roundPos(ray.Position + ray.Normal * 1.5) + vector3new(0, 3, 0)
                                                        if not getPlacedBlock(dpos) then
                                                            top = vector3new(top.X, pos.Y, top.Z)
                                                            break
                                                        end
                                                    end
                                                end
                                            end

                                            local yDiff = top.Y - rootPos.Y
                                            root.CFrame += vector3new(0, yDiff, 0)
                                            
                                            if not frictionTable.Speed then
                                                local speed = getSpeed()
                                                local newVelocity = (AntiFallDirection * speed) + vector3new(0, root.AssemblyLinearVelocity.Y, 0)
                                                root.AssemblyLinearVelocity = newVelocity
                                            end

                                            if delta.Magnitude < 1 then
                                                connection:Disconnect()
                                                AntiFallDirection = nil
                                            end
                                        else
                                            connection:Disconnect()
                                            AntiFallDirection = nil
                                        end
                                    end)
                                    AntiFall:Clean(connection)
                                end
                            elseif Mode.Value == 'Velocity' then
                                local rootVel = entitylib.character.RootPart.Velocity
                                entitylib.character.RootPart.Velocity = vector3new(rootVel.X, 100, rootVel.Z)
                            end
                        end
                    end))
                end
            else
                AntiFallDirection = nil
                cachedLowGround = math_huge
                lastGroundScan = 0
            end
        end,
        Tooltip = 'Help\'s you with your Parkinson\'s\nPrevents you from falling into the void.'
    })
    
    Mode = AntiFall:CreateDropdown({
        Name = 'Move Mode',
        List = {'Normal', 'Collide', 'Velocity'},
        Function = function(val)
            if AntiFallPart then
                AntiFallPart.CanCollide = val == 'Collide'
            end
        end,
        Tooltip = 'Normal - Smoothly moves you towards the nearest safe point\nVelocity - Launches you upward after touching\nCollide - Allows you to walk on the part'
    })
    
    local materials = {'ForceField'}
    for _, v in Enum.Material:GetEnumItems() do
        if v.Name ~= 'ForceField' then
            table.insert(materials, v.Name)
        end
    end
    
    Material = AntiFall:CreateDropdown({
        Name = 'Material',
        List = materials,
        Function = function(val)
            if AntiFallPart then
                AntiFallPart.Material = Enum.Material[val]
            end
        end
    })
    
    Color = AntiFall:CreateColorSlider({
        Name = 'Color',
        DefaultOpacity = 0.5,
        Function = function(h, s, v, o)
            if AntiFallPart then
                AntiFallPart.Color = Color3.fromHSV(h, s, v)
                AntiFallPart.Transparency = 1 - o
            end
        end
    })
end)
	
run(function()
    local _sharedHitBlock = nil
    local _hitBlockPatchers = {}

    getgenv().registerHitBlockPatch = function(key, fn)
        _hitBlockPatchers[key] = fn
        if not _sharedHitBlock and bedwars.BlockBreaker then
            _sharedHitBlock = bedwars.BlockBreaker.hitBlock
        end
        if not bedwars.BlockBreaker then return end
        bedwars.BlockBreaker.hitBlock = function(self, maid, raycastparams, ...)
            for _, patcher in _hitBlockPatchers do
                local result = patcher(self, maid, raycastparams, ...)
                if result ~= nil then return result end
            end
            if _sharedHitBlock then return _sharedHitBlock(self, maid, raycastparams, ...) end
        end
    end

    getgenv().unregisterHitBlockPatch = function(key)
        _hitBlockPatchers[key] = nil
        if not next(_hitBlockPatchers) then
            if bedwars.BlockBreaker then
                bedwars.BlockBreaker.hitBlock = _sharedHitBlock
            end
            _sharedHitBlock = nil
        end
    end

    local FastBreak
    local Time
    local BedCheck
    local Blacklist
    local blocks
    local string_lower = string.lower
    local string_find = string.find
    local task_wait = task.wait
    local currentBlock = nil
    local oldHitBlock = nil
    local lastHotbarSlot = nil
    local bedCache = {}
    local blacklistCache = {}
    local lastCacheClean = 0
    local cacheCleanInterval = 5 
    
    local function isBed(block)
        if not block then return false end
        local cached = bedCache[block]
        if cached ~= nil then return cached end
        
        local result = false
        pcall(function()
            if collectionService:HasTag(block, 'bed') or (block.Parent and collectionService:HasTag(block.Parent, 'bed')) then
                result = true
            elseif string_find(string_lower(block.Name), 'bed', 1, true) then
                result = true
            end
        end)
        
        if result then bedCache[block] = true end
        return result
    end
    
    local cachedBlacklistLower = {}
    local function updateBlacklistCache()
        if not blocks or not blocks.ListEnabled then return end
        
        cachedBlacklistLower = {}
        for _, v in pairs(blocks.ListEnabled) do
            table.insert(cachedBlacklistLower, string_lower(v))
        end
    end
    
    local function isBlacklisted(block)
        if not block or #cachedBlacklistLower == 0 then return false end
        local cached = blacklistCache[block]
        if cached ~= nil then return cached end
        
        local name = string_lower(block.Name)
        local result = false
        for i = 1, #cachedBlacklistLower do
            if string_find(name, cachedBlacklistLower[i], 1, true) then
                result = true
                break
            end
        end
        
        blacklistCache[block] = result
        return result
    end
    
    local function shouldSkip(block)
        if not block then return false end
        if BedCheck and BedCheck.Enabled and isBed(block) then return true end
        if Blacklist and Blacklist.Enabled and isBlacklisted(block) then return true end
        return false
    end
    
    local lastBreakUpdate = 0
    local breakUpdateCooldown = 0.05
    local pendingUpdate = false
    
    local function updateBreakSpeed()
        if not FastBreak or not FastBreak.Enabled then return end
        local now = tick()
        if now - lastBreakUpdate < breakUpdateCooldown then
            pendingUpdate = true
            return
        end
        lastBreakUpdate = now
        pendingUpdate = false
        
        pcall(function()
            local cooldown = (shouldSkip(currentBlock)) and 0.3 or Time.Value
            bedwars.BlockBreakController.blockBreaker:setCooldown(cooldown)
        end)
    end
    
    FastBreak = vape.Categories.Blatant:CreateModule({
        Name = 'FastBreak',
        Function = function(callback)
            if callback then
                lastHotbarSlot = nil

				registerHitBlockPatch('FastBreak', function(self, maid, raycastparams, ...)
					local block = nil
					pcall(function()
						local blockInfo = self.clientManager:getBlockSelector():getMouseInfo(1, {ray = raycastparams})
						if blockInfo and blockInfo.target and blockInfo.target.blockInstance then
							block = blockInfo.target.blockInstance
						end
					end)
					
					local currentSlot = store.inventory and store.inventory.hotbarSlot
					local slotChanged = currentSlot ~= lastHotbarSlot
					if slotChanged then
						lastHotbarSlot = currentSlot
					end

					if block ~= currentBlock or slotChanged then
						currentBlock = block
						updateBreakSpeed()
					end
					end)
                
                updateBlacklistCache()
                
                task.spawn(function()
                    while FastBreak.Enabled do
                        if tick() - lastCacheClean > cacheCleanInterval then
                            lastCacheClean = tick()
                            bedCache = {}
                            blacklistCache = {}
                        end
                        if pendingUpdate then updateBreakSpeed() end
                        task_wait(0.05) 
                    end
                end)
			else
				pcall(function() bedwars.BlockBreakController.blockBreaker:setCooldown(0.3) end)
				unregisterHitBlockPatch('FastBreak')
				currentBlock = nil
				lastHotbarSlot = nil
				bedCache, blacklistCache, cachedBlacklistLower = {}, {}, {}
			end
        end,
        Tooltip = 'mine faster'
    })
    
    Time = FastBreak:CreateSlider({
        Name = 'Break speed',
        Min = 0, Max = 0.3, Default = 0.25, Decimal = 100, Suffix = 'seconds',
        Function = function() updateBreakSpeed() end
    })
    
    BedCheck = FastBreak:CreateToggle({
        Name = 'Bed Check',
        Default = false,
        Tooltip = 'mining is normal when breaking beds',
        Function = function() bedCache = {}; updateBreakSpeed() end
    })
    
    Blacklist = FastBreak:CreateToggle({
        Name = 'Blacklist Blocks',
        Default = false,
        Tooltip = 'mining is normal for blacklisted blocks',
        Function = function(v)
            if blocks then blocks.Object.Visible = v end
            blacklistCache = {}
            if v then updateBlacklistCache() end
            updateBreakSpeed()
        end
    })
    
    blocks = FastBreak:CreateTextList({
        Name = 'Blacklisted Blocks',
        Placeholder = 'bed',
        Visible = false,
        Function = function()
            updateBlacklistCache()
            blacklistCache = {}
            updateBreakSpeed()
        end
    })
end)
	
local Fly
local LongJump
run(function()
    local Value
    local VerticalValue
    local WallCheck
    local PopBalloons
    local TP
    local lastonground = false
    local MobileButtons
    local FlyAnywayProgressBar = {Enabled = false}
    local FlyAnywayProgressBarFrame
    local BarColor
    local rayCheck = RaycastParams.new()
    rayCheck.RespectCanCollide = true
    local up, down, old = 0, 0
    local mobileControls = {}
    local groundtime = nil
    local onground = false
    local flyCooldownActive = false
    local lastGroundTouchTime = 0
    local MAX_FLY_TIME = 2.5
    local tick = tick
    local task_wait = task.wait
    local math_max = math.max
    local math_floor = math.floor
    local string_format = string.format
    local vector3new = Vector3.new
    local vector3zero = Vector3.zero
    local udim2new = UDim2.new
    local cframeLookAlong = CFrame.lookAlong
    local cachedBalloonCount = 0
    local lastBalloonCheck = 0
    local balloonCheckInterval = 0.2 
    local cachedMatchState = 0
    local lastMatchStateCheck = 0
    local lastGroundTime = tick()
    local airTime = 0
    
    local function createMobileButton(name, position, icon)
        local button = Instance.new("TextButton")
        button.Name = name
        button.Size = udim2new(0, 60, 0, 60)
        button.Position = position
        button.BackgroundTransparency = 0.2
        button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        button.BorderSizePixel = 0
        button.Text = icon
        button.TextScaled = true
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.Font = Enum.Font.SourceSansBold
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = button
        return button
    end

    local function cleanupMobileControls()
        for _, control in pairs(mobileControls) do
            if control then
                control:Destroy()
            end
        end
        mobileControls = {}
    end

    local progressBarFrameCounter = 0
    local MAX_FRAME_COUNTER = 600
    local function updateProgressBar()
        if not FlyAnywayProgressBarFrame then return end
        
        if not entitylib.isAlive then
            FlyAnywayProgressBarFrame.Visible = false
            return
        end
        
        local now = tick()
        if now - lastBalloonCheck > balloonCheckInterval then
            lastBalloonCheck = now
            cachedBalloonCount = lplr.Character:GetAttribute('InflatedBalloons') or 0
            cachedMatchState = store.matchState
        end
        
        local flyAllowed = cachedBalloonCount > 0 or cachedMatchState == 2
        
        if flyAllowed then
            FlyAnywayProgressBarFrame.Frame.Size = udim2new(1, 0, 0, 20)
            FlyAnywayProgressBarFrame.TextLabel.Text = "∞"
            FlyAnywayProgressBarFrame.Visible = FlyAnywayProgressBar.Enabled
            return
        end
        
        progressBarFrameCounter = (progressBarFrameCounter + 1) % MAX_FRAME_COUNTER
        if progressBarFrameCounter % 3 == 0 then
            local hipHeight = entitylib.character.Humanoid.HipHeight
            local checkPos = entitylib.character.HumanoidRootPart.Position + vector3new(0, (hipHeight * -2) - 1, 0)
            local newray = getPlacedBlock(checkPos)
            onground = newray ~= nil
        end
        
        if onground then
            groundtime = nil
            flyCooldownActive = false
            lastGroundTouchTime = now
            
            FlyAnywayProgressBarFrame.Frame.Size = udim2new(1, 0, 0, 20)
            FlyAnywayProgressBarFrame.TextLabel.Text = string_format("%.1fs", MAX_FLY_TIME)
            FlyAnywayProgressBarFrame.Visible = FlyAnywayProgressBar.Enabled and Fly.Enabled
            
            local tween = FlyAnywayProgressBarFrame.Frame:FindFirstChild("Tween")
            if tween then
                tween:Destroy()
            end
        else
            if not groundtime then
                groundtime = now + MAX_FLY_TIME
                flyCooldownActive = false
            end
            
            local timeLeft = math_max(0, groundtime - now)
            local progress = timeLeft / MAX_FLY_TIME
            
            FlyAnywayProgressBarFrame.Frame.Size = udim2new(progress, 0, 0, 20)
            FlyAnywayProgressBarFrame.TextLabel.Text = string_format("%.1fs", timeLeft)
            FlyAnywayProgressBarFrame.Visible = FlyAnywayProgressBar.Enabled and Fly.Enabled
            
            if timeLeft <= 0 and not flyCooldownActive then
                flyCooldownActive = true
            end
        end
        
        lastonground = onground
    end

    Fly = vape.Categories.Blatant:CreateModule({
        Name = 'Fly',
        Function = function(callback)
            frictionTable.Fly = callback or nil
            updateVelocity()
            if callback then
                up, down, old = 0, 0, bedwars.BalloonController.deflateBalloon
                bedwars.BalloonController.deflateBalloon = function() end
                local tpTick, tpToggle, oldy = tick(), true

                if lplr.Character and (lplr.Character:GetAttribute('InflatedBalloons') or 0) == 0 and getItem('balloon') then
                    bedwars.BalloonController:inflateBalloon()
                end

                Fly:Clean(vapeEvents.AttributeChanged.Event:Connect(function(changed)
                    if changed == 'InflatedBalloons' then
                        local char = lplr.Character
                        if not char then return end
                        cachedBalloonCount = char:GetAttribute('InflatedBalloons') or 0
                        if cachedBalloonCount == 0 and getItem('balloon') then
                            bedwars.BalloonController:inflateBalloon()
                        end
                    end
                end))

                local renderFrameCounter = 0
                Fly:Clean(runService.RenderStepped:Connect(function(delta)
                    if FlyAnywayProgressBar.Enabled and Fly.Enabled then
                        renderFrameCounter = renderFrameCounter + 1
                        if renderFrameCounter % 2 == 0 then
                            updateProgressBar()
                        end
                    end
                end))

                local preSimFrameCounter = 0
                local lastWallRaycast = 0
                local wallRaycastInterval = 0.05
                
                Fly:Clean(runService.PreSimulation:Connect(function(dt)
                    if entitylib.isAlive and isnetworkowner(entitylib.character.RootPart) then
                        preSimFrameCounter = preSimFrameCounter + 1
                        local now = tick()
                        
                        if preSimFrameCounter % 12 == 0 then
                            cachedBalloonCount = lplr.Character and lplr.Character:GetAttribute('InflatedBalloons') or 0
                            cachedMatchState = store.matchState
                        end

                        local humanoid = entitylib.character.Humanoid
                        if humanoid.FloorMaterial ~= Enum.Material.Air then
                            lastGroundTime = now
                        end
                        airTime = now - lastGroundTime
                        
                        local flyAllowed = cachedBalloonCount > 0 or cachedMatchState == 2
                        
                        local oscillation = (now % 0.4 < 0.2) and -1 or 1
                        local mass = (1.95 + (flyAllowed and 6 or 0) * oscillation) + ((up + down) * VerticalValue.Value)
                        
                        local root = entitylib.character.RootPart
                        local moveDirection = entitylib.character.Humanoid.MoveDirection
                        local velo = getSpeed()
                        local destination = (moveDirection * math_max(Value.Value - velo, 0) * dt)
                        
                        if WallCheck.Enabled and (now - lastWallRaycast) > wallRaycastInterval then
                            lastWallRaycast = now
                            local filterList = {lplr.Character, gameCamera}
                            if AntiVoidPart then table.insert(filterList, AntiVoidPart) end
                            rayCheck.FilterDescendantsInstances = filterList
                            rayCheck.CollisionGroup = root.CollisionGroup

                            if destination.Magnitude > 0.001 then
                                local ray = workspace:Raycast(root.Position, destination, rayCheck)
                                if ray then
                                    destination = ((ray.Position + ray.Normal) - root.Position)
                                end
                            end
                        end

                        if not flyAllowed then
                            if tpToggle then
                                if airTime > 2 then  
                                    if not oldy then
                                        rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera, AntiVoidPart}
                                        rayCheck.CollisionGroup = root.CollisionGroup
                                        local ray = workspace:Raycast(root.Position, vector3new(0, -1000, 0), rayCheck)
                                        if ray and TP.Enabled then
                                            tpToggle = false
                                            oldy = root.Position.Y
                                            tpTick = now + 0.11
                                            root.CFrame = cframeLookAlong(vector3new(root.Position.X, ray.Position.Y + entitylib.character.HipHeight, root.Position.Z), root.CFrame.LookVector)
                                        end
                                    end
                                end
                            else
                                if oldy then
                                    if tpTick < now then
                                        local newpos = vector3new(root.Position.X, oldy, root.Position.Z)
                                        root.CFrame = cframeLookAlong(newpos, root.CFrame.LookVector)
                                        tpToggle = true
                                        oldy = nil
                                    else
                                        mass = 0
                                    end
                                end
                            end
                        end

                        root.CFrame += destination
                        root.AssemblyLinearVelocity = (moveDirection * velo) + vector3new(0, mass, 0)
                    end
                end))

                local isMobile = inputService.TouchEnabled and not inputService.KeyboardEnabled and not inputService.MouseEnabled
                local MobileEnabled = MobileButtons.Enabled or isMobile
                if MobileEnabled then
                    local gui = Instance.new("ScreenGui")
                    gui.Name = "FlyControls"
                    gui.ResetOnSpawn = false
                    gui.Parent = lplr.PlayerGui

                    local upButton = createMobileButton("UpButton", udim2new(0.9, -70, 0.7, -140), "↑")
                    local downButton = createMobileButton("DownButton", udim2new(0.9, -70, 0.7, -70), "↓")

                    mobileControls.UpButton = upButton
                    mobileControls.DownButton = downButton
                    mobileControls.ScreenGui = gui

                    upButton.Parent = gui
                    downButton.Parent = gui

                    Fly:Clean(upButton.MouseButton1Down:Connect(function()
                        up = 1
                    end))
                    Fly:Clean(upButton.MouseButton1Up:Connect(function()
                        up = 0
                    end))
                    Fly:Clean(downButton.MouseButton1Down:Connect(function()
                        down = -1
                    end))
                    Fly:Clean(downButton.MouseButton1Up:Connect(function()
                        down = 0
                    end))
                end

                Fly:Clean(inputService.InputBegan:Connect(function(input)
                    if not inputService:GetFocusedTextBox() then
                        if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
                            up = 1
                        elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
                            down = -1
                        end
                    end
                end))
                Fly:Clean(inputService.InputEnded:Connect(function(input)
                    if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
                        up = 0
                    elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
                        down = 0
                    end
                end))
                if inputService.TouchEnabled then
                    pcall(function()
                        local jumpButton = lplr.PlayerGui.TouchGui.TouchControlFrame.JumpButton
                        Fly:Clean(jumpButton:GetPropertyChangedSignal('ImageRectOffset'):Connect(function()
                            if not mobileControls.UpButton then
                                up = jumpButton.ImageRectOffset.X == 146 and 1 or 0
                            end
                        end))
                    end)
                end
            else
                if FlyAnywayProgressBarFrame then
                    FlyAnywayProgressBarFrame.Visible = false
                end
                lastonground = nil
                groundtime = nil
                flyCooldownActive = false
                bedwars.BalloonController.deflateBalloon = old
                if PopBalloons.Enabled and entitylib.isAlive and (lplr.Character:GetAttribute('InflatedBalloons') or 0) > 0 then
                    for _ = 1, 3 do
                        bedwars.BalloonController:deflateBalloon()
                    end
                end
                cleanupMobileControls()
                cachedBalloonCount = 0
                lastBalloonCheck = 0
                cachedMatchState = 0
            end
        end,
        ExtraText = function()
            return 'Heatseeker'
        end,
        Tooltip = 'makes you go zoom!'
    })
    Value = Fly:CreateSlider({
        Name = 'Speed',
        Min = 1,
        Max = 23,
        Default = 23,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    VerticalValue = Fly:CreateSlider({
        Name = 'Vertical Speed',
        Min = 1,
        Max = 150,
        Default = 50,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    WallCheck = Fly:CreateToggle({
        Name = 'Wall Check',
        Default = true
    })
    PopBalloons = Fly:CreateToggle({
        Name = 'Pop Balloons',
        Default = true
    })
    FlyAnywayProgressBar = Fly:CreateToggle({
        Name = "Progress Bar",
        Function = function(callback)
            if callback then
                FlyAnywayProgressBarFrame = Instance.new("Frame")
                FlyAnywayProgressBarFrame.AnchorPoint = Vector2.new(0.5, 0)
                FlyAnywayProgressBarFrame.Position = udim2new(0.5, 0, 1, -200)
                FlyAnywayProgressBarFrame.Size = udim2new(0.2, 0, 0, 20)
                FlyAnywayProgressBarFrame.BackgroundTransparency = 0.5
                FlyAnywayProgressBarFrame.BorderSizePixel = 0
                FlyAnywayProgressBarFrame.BackgroundColor3 = Color3.new(0, 0, 0)
                FlyAnywayProgressBarFrame.Visible = false
                FlyAnywayProgressBarFrame.Parent = vape.gui
                
                local FlyAnywayProgressBarFrame2 = Instance.new("Frame")
                FlyAnywayProgressBarFrame2.Name = "Frame"
                FlyAnywayProgressBarFrame2.AnchorPoint = Vector2.new(0, 0)
                FlyAnywayProgressBarFrame2.Position = udim2new(0, 0, 0, 0)
                FlyAnywayProgressBarFrame2.Size = udim2new(1, 0, 0, 20)
                FlyAnywayProgressBarFrame2.BackgroundTransparency = 0
                FlyAnywayProgressBarFrame2.BorderSizePixel = 0
                FlyAnywayProgressBarFrame2.BackgroundColor3 = BarColor and Color3.fromHSV(BarColor.H, BarColor.S, BarColor.V) or Color3.fromHSV(vape.GUIColor.Hue, vape.GUIColor.Sat, vape.GUIColor.Value)
                FlyAnywayProgressBarFrame2.Visible = true
                FlyAnywayProgressBarFrame2.Parent = FlyAnywayProgressBarFrame
                
                local FlyAnywayProgressBartext = Instance.new("TextLabel")
                FlyAnywayProgressBartext.Name = "TextLabel"
                FlyAnywayProgressBartext.Text = "2.5s"
                FlyAnywayProgressBartext.Font = Enum.Font.Gotham
                FlyAnywayProgressBartext.TextStrokeTransparency = 0
                FlyAnywayProgressBartext.TextColor3 = Color3.new(0.9, 0.9, 0.9)
                FlyAnywayProgressBartext.TextSize = 20
                FlyAnywayProgressBartext.Size = udim2new(1, 0, 1, 0)
                FlyAnywayProgressBartext.BackgroundTransparency = 1
                FlyAnywayProgressBartext.Position = udim2new(0, 0, 0, 0)
                FlyAnywayProgressBartext.Parent = FlyAnywayProgressBarFrame
            else
                if FlyAnywayProgressBarFrame then 
                    FlyAnywayProgressBarFrame:Destroy() 
                    FlyAnywayProgressBarFrame = nil 
                end
            end
        end,
        Tooltip = "show amount of time for fly",
        Default = true
    })
    BarColor = Fly:CreateColorSlider({
        Name = 'Bar Color',
        Function = function(h, s, v, o)
            if FlyAnywayProgressBarFrame then
                FlyAnywayProgressBarFrame:FindFirstChild('Frame').BackgroundColor3 = Color3.fromHSV(h, s, v)
                FlyAnywayProgressBarFrame:FindFirstChild('Frame').BackgroundTransparency = 1 - o
            end
        end
    })

    TP = Fly:CreateToggle({
        Name = 'TP Down',
        Default = true
    })
    MobileButtons = Fly:CreateToggle({
        Name = "Mobile Buttons",
        Function = function() 
            if Fly.Enabled then
                Fly:Toggle()
                Fly:Toggle()
            end
        end
    })
end)
	
run(function()
    local Mode
    local Expand
    local AutoToggle
    local Visible
    local VisibleColor
    local Targets
    local objects = {}
    local set = false
    local hitboxesActive = false
    local autoToggleConnection = nil
    local autoToggleFrameCounter = 0

    local vector3new = Vector3.new
    local vector3one = Vector3.one

    local colorList = {
        Red = Color3.fromRGB(255, 0, 0),
        Blue = Color3.fromRGB(0, 100, 255),
        Green = Color3.fromRGB(0, 255, 0),
        Yellow = Color3.fromRGB(255, 255, 0),
        Orange = Color3.fromRGB(255, 140, 0),
        Purple = Color3.fromRGB(180, 0, 255),
        White = Color3.fromRGB(255, 255, 255),
        Cyan = Color3.fromRGB(0, 255, 255),
        Pink = Color3.fromRGB(255, 50, 150),
        Black = Color3.fromRGB(0, 0, 0)
    }

    local function shouldCreateHitbox(ent)
        if not ent.Targetable then return false end
        if ent.Player and Targets and Targets.Players and Targets.Players.Enabled then return true end
        if not ent.Player and Targets and Targets.NPCs and Targets.NPCs.Enabled then return true end
        return false
    end

    local _wallRayParams = RaycastParams.new()
    _wallRayParams.FilterType = Enum.RaycastFilterType.Exclude
    local function isTargetBehindWall(ent)
        if not Targets or not Targets.Walls or not Targets.Walls.Enabled then return false end
        if not ent.RootPart then return false end
        if not entitylib.isAlive or not entitylib.character or not entitylib.character.RootPart then return false end
        local origin = entitylib.character.RootPart.Position
        local target = ent.RootPart.Position
        local direction = target - origin
        _wallRayParams.FilterDescendantsInstances = {entitylib.character, ent.Character}
        local result = workspace:Raycast(origin, direction, _wallRayParams)
        if result then
            local hitDist = (result.Position - origin).Magnitude
            local targetDist = direction.Magnitude
            if hitDist < targetDist - 0.5 then return true end
        end
        return false
    end

    local cachedExpandSize = vector3new(3, 6, 3)
    local lastExpandValue = 0
    local function updateExpandSize(val)
        if val ~= lastExpandValue then
            lastExpandValue = val
            cachedExpandSize = vector3new(3, 6, 3) + vector3one * (val / 5)
        end
    end

    local function createHitbox(ent)
        if not shouldCreateHitbox(ent) then return end
        if isTargetBehindWall(ent) then return end
        if objects[ent] then return end
        local hitbox = Instance.new('Part')
        hitbox.Size = cachedExpandSize
        hitbox.Position = ent.RootPart.Position
        hitbox.CanCollide = false
        hitbox.Massless = true
        hitbox.Transparency = Visible and Visible.Enabled and 0.5 or 1
        if Visible and Visible.Enabled and VisibleColor then
            hitbox.Color = colorList[VisibleColor.Value] or colorList.Red
        end
        hitbox.Parent = ent.Character
        local weld = Instance.new('Motor6D')
        weld.Part0 = hitbox
        weld.Part1 = ent.RootPart
        weld.Parent = hitbox
        local ev = Instance.new('ObjectValue')
        ev.Name = 'EntityValue'
        ev.Value = ent.Character
        ev.Parent = hitbox
        game:GetService('CollectionService'):AddTag(hitbox, 'Hitbox')
        objects[ent] = hitbox
    end

    local function clearHitboxes()
        for _, part in pairs(objects) do part:Destroy() end
        table.clear(objects)
    end

    local function refreshAllHitboxes()
        clearHitboxes()
        local entityList = entitylib.List
        for i = 1, #entityList do
            createHitbox(entityList[i])
        end
    end

    local function handleAutoToggle()
        if not AutoToggle or not AutoToggle.Enabled then return end
        if not HitBoxes.Enabled or Mode.Value ~= 'Player' then return end
        local holdingSword = isSword()
        if holdingSword and not hitboxesActive then
            hitboxesActive = true
            refreshAllHitboxes()
        elseif not holdingSword and hitboxesActive then
            hitboxesActive = false
            clearHitboxes()
        end
    end

    HitBoxes = vape.Categories.Blatant:CreateModule({
        Name = 'HitBoxes',
        Function = function(callback)
            if callback then
                updateExpandSize(Expand.Value)
                if Mode.Value == 'Sword' then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, (Expand.Value / 3))
                    set = true
                else
                    HitBoxes:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
                        if AutoToggle and AutoToggle.Enabled then
                            if hitboxesActive then createHitbox(ent) end
                        else
                            createHitbox(ent)
                        end
                    end))
                    HitBoxes:Clean(entitylib.Events.EntityRemoving:Connect(function(ent)
                        local obj = objects[ent]
                        if obj then obj:Destroy() objects[ent] = nil end
                    end))
                    if AutoToggle and AutoToggle.Enabled then
                        handleAutoToggle()
                        if not autoToggleConnection or not autoToggleConnection.Connected then
                            autoToggleFrameCounter = 0
                            autoToggleConnection = runService.Heartbeat:Connect(function()
                                autoToggleFrameCounter = autoToggleFrameCounter + 1
                                if autoToggleFrameCounter % 5 == 0 then
                                    handleAutoToggle()
                                end
                            end)
                            HitBoxes:Clean(autoToggleConnection)
                        end
                    else
                        refreshAllHitboxes()
                    end
                    local hitboxThrottleCounter = 0
                    HitBoxes:Clean(runService.Heartbeat:Connect(function()
                        if not Targets or not Targets.Walls or not Targets.Walls.Enabled then return end
                        hitboxThrottleCounter = hitboxThrottleCounter + 1
                        if hitboxThrottleCounter % 20 ~= 0 then return end
                        for ent, part in pairs(objects) do
                            if isTargetBehindWall(ent) then
                                part:Destroy()
                                objects[ent] = nil
                            end
                        end
                        local entityList = entitylib.List
                        for i = 1, #entityList do
                            local ent = entityList[i]
                            if not objects[ent] then
                                if AutoToggle and AutoToggle.Enabled then
                                    if hitboxesActive then createHitbox(ent) end
                                else
                                    createHitbox(ent)
                                end
                            end
                        end
                    end))
                end
            else
                hitboxesActive = false
                if set then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, 3.8)
                    set = false
                end
                clearHitboxes()
            end
        end,
        Tooltip = 'increases attack hitbox'
    })

    Targets = HitBoxes:CreateTargets({
        Players = true,
        Walls = false,
        NPCs = false,
        Function = function()
            if HitBoxes.Enabled and Mode.Value == 'Player' then
                if AutoToggle and AutoToggle.Enabled then
                    if hitboxesActive then refreshAllHitboxes() end
                else
                    refreshAllHitboxes()
                end
            end
        end
    })

    Mode = HitBoxes:CreateDropdown({
        Name = 'Mode',
        List = {'Sword', 'Player'},
        Function = function(val)
            local isPlayer = val == 'Player'
            if AutoToggle then AutoToggle.Object.Visible = isPlayer end
            if Visible then Visible.Object.Visible = isPlayer end
            if VisibleColor then VisibleColor.Object.Visible = isPlayer and Visible.Enabled end
            if HitBoxes.Enabled then HitBoxes:Toggle() HitBoxes:Toggle() end
        end,
    })

    Expand = HitBoxes:CreateSlider({
        Name = 'Expand amount',
        Min = 0,
        Max = 50,
        Default = 14.4,
        Decimal = 10,
        Function = function(val)
            updateExpandSize(val)
            if HitBoxes.Enabled then
                if Mode.Value == 'Sword' then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, (val / 3))
                else
                    for _, part in pairs(objects) do part.Size = cachedExpandSize end
                end
            end
        end,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })

    AutoToggle = HitBoxes:CreateToggle({
        Name = 'Auto Toggle',
        Default = false,
        Tooltip = 'enables hitbox when holding sword, disable when not',
        Function = function(callback)
            if callback then
                if autoToggleConnection then autoToggleConnection:Disconnect() end
                hitboxesActive = false
                autoToggleFrameCounter = 0
                autoToggleConnection = runService.Heartbeat:Connect(function()
                    autoToggleFrameCounter = autoToggleFrameCounter + 1
                    if autoToggleFrameCounter % 5 == 0 then
                        handleAutoToggle()
                    end
                end)
                HitBoxes:Clean(autoToggleConnection)
                handleAutoToggle()
            else
                if autoToggleConnection then
                    autoToggleConnection:Disconnect()
                    autoToggleConnection = nil
                end
                hitboxesActive = false
                if HitBoxes.Enabled and Mode.Value == 'Player' then
                    refreshAllHitboxes()
                end
            end
        end
    })

    Visible = HitBoxes:CreateToggle({
        Name = 'Visible',
        Default = false,
        Function = function(callback)
            if VisibleColor then VisibleColor.Object.Visible = callback end
            if HitBoxes.Enabled and Mode.Value == 'Player' then
                local transparency = callback and 0.5 or 1
                local col = callback and VisibleColor and (colorList[VisibleColor.Value] or colorList.Red) or nil
                for _, part in pairs(objects) do
                    part.Transparency = transparency
                    if col then part.Color = col end
                end
            end
        end
    })

    VisibleColor = HitBoxes:CreateDropdown({
        Name = 'Hitbox Color',
        List = {'Red', 'Blue', 'Green', 'Yellow', 'Orange', 'Purple', 'White', 'Cyan', 'Pink', 'Black'},
        Default = 'Red',
        Visible = false,
        Function = function(val)
            if HitBoxes.Enabled and Mode.Value == 'Player' and Visible.Enabled then
                local col = colorList[val] or colorList.Red
                for _, part in pairs(objects) do part.Color = col end
            end
        end
    })

    task.spawn(function()
        repeat task.wait() until Mode and Mode.Value
        local isPlayer = Mode.Value == 'Player'
        AutoToggle.Object.Visible = isPlayer
        Visible.Object.Visible = isPlayer
    end)

    task.defer(function()
        if VisibleColor and VisibleColor.Object then
            VisibleColor.Object.Visible = false
        end
    end)
end)
	
run(function()
	vape.Categories.Blatant:CreateModule({
		Name = 'KeepSprint',
		Function = function(callback)
			debug.setconstant(bedwars.SprintController.startSprinting, 5, callback and 'blockSprinting' or 'blockSprint')
			bedwars.SprintController:stopSprinting()
		end,
		Tooltip = 'allows you to sprint with potions'
	})
end)

run(function()
    local moduleData = {
        Connection = nil,
        CurrentDuration = 1,
        CachedPrompts = {}
    }
    
    local function updatePrompt(prompt, duration)
        if prompt and prompt:IsA("ProximityPrompt") then
            prompt.HoldDuration = duration
        end
    end
    
    local function updateAllPrompts(duration)
        for prompt in pairs(moduleData.CachedPrompts) do
            if prompt and prompt.Parent then
                prompt.HoldDuration = duration
            else
                moduleData.CachedPrompts[prompt] = nil
            end
        end
    end
    
    local function cacheExistingPrompts()
        moduleData.CachedPrompts = {}
        
        for _, descendant in workspace:GetDescendants() do
            if descendant:IsA("ProximityPrompt") then
                moduleData.CachedPrompts[descendant] = true
                descendant.HoldDuration = moduleData.CurrentDuration
            end
        end
    end
    
	ProximityPromptDuration = vape.Categories.Utility:CreateModule({
		Name = 'ProximityPromptDuration',
		Function = function(callback)
			if callback then
				cacheExistingPrompts()
				ProximityPromptDuration:Clean(workspace.DescendantAdded:Connect(function(descendant)
					if descendant:IsA("ProximityPrompt") then
						moduleData.CachedPrompts[descendant] = true
						descendant.HoldDuration = moduleData.CurrentDuration
					end
				end))
			else
				moduleData.CachedPrompts = {}
			end
		end,
		Tooltip = 'customize proximity prompts'
	})
    
    local ProximityDurationSlider = ProximityPromptDuration:CreateSlider({
        Name = 'Duration',
        Min = 0,
        Max = 10,
        Default = 1,
        Decimal = 100,
        Suffix = 's',
        Function = function(value)
            moduleData.CurrentDuration = value
            if ProximityPromptDuration.Enabled then
                updateAllPrompts(value)
            end
        end
    })
end)
	
run(function()
    local old
    local SophiaCheck
    local FROZEN_THRESHOLD = 10

    local cachedModifier = nil
    local NoSlowdown = vape.Categories.Blatant:CreateModule({
        Name = 'NoSlowdown',
        Function = function(callback)
            if not cachedModifier then
                if not bedwars.SprintController then return end
                cachedModifier = bedwars.SprintController:getMovementStatusModifier()
            end
            local modifier = cachedModifier
            if callback then
                old = modifier.addModifier
                if not old then return end
                modifier.addModifier = function(self, tab)
                    if SophiaCheck and SophiaCheck.Enabled and isFrozen(nil, FROZEN_THRESHOLD) then
                        return old(self, tab)
                    end

                    if tab.moveSpeedMultiplier then
                        tab.moveSpeedMultiplier = math.max(tab.moveSpeedMultiplier, 1)
                    end
                    return old(self, tab)
                end

                for i in modifier.modifiers do
                    if (i.moveSpeedMultiplier or 1) < 1 then
                        modifier:removeModifier(i)
                    end
                end
            else
                if cachedModifier then
                    cachedModifier.addModifier = old
                    cachedModifier = nil
                end
                old = nil
            end
        end,
        Tooltip = 'prevents slowing down when using items.'
    })

    SophiaCheck = NoSlowdown:CreateToggle({
        Name = 'Sophia Check',
        Default = false
    })
end)

run(function()
	local shooting, old = false
	local AutoShootInterval
	local AutoShootSwitchSpeed
	local AutoShootRange
	local AutoShootFOV
	local AutoShootWaitDelay
	local lastAutoShootTime = 0
	local autoShootEnabled = false
	local KillauraTargetCheck
	local FirstPersonCheck
	_G.autoShootLock = false
	local cachedBows = {}
	local cachedSwordSlot = nil
	local cachedHasArrows = false
	local lastInventoryUpdate = 0
	local INVENTORY_CACHE_TIME = 0.5
	local lastTargetCheck = 0
	local lastTargetResult = false
	local TARGET_CHECK_INTERVAL = 0.15
	local math_acos = math.acos
	local math_rad = math.rad
	local tick = tick
	
	local function updateInventoryCache()
		local now = tick()
		if now - lastInventoryUpdate < INVENTORY_CACHE_TIME then
			return
		end
		lastInventoryUpdate = now
		
		local arrowItem = getItem('arrow')
		cachedHasArrows = arrowItem and arrowItem.amount > 0
		
		table.clear(cachedBows)
		cachedSwordSlot = nil
		
		local hotbar = store.inventory.hotbar
		for i = 1, #hotbar do
			local v = hotbar[i]
			if v and v.item and v.item.itemType then
				local itemMeta = bedwars.ItemMeta[v.item.itemType]
				if itemMeta then
					if itemMeta.projectileSource then
						local projectileSource = itemMeta.projectileSource
						if projectileSource.ammoItemTypes and table.find(projectileSource.ammoItemTypes, 'arrow') then
							table.insert(cachedBows, i - 1)
						end
					end
					if itemMeta.sword and not cachedSwordSlot then
						cachedSwordSlot = i - 1
					end
				end
			end
		end
	end
	
	local function hasArrows()
		updateInventoryCache()
		return cachedHasArrows
	end
	
	local function getBows()
		updateInventoryCache()
		return cachedBows
	end
	
	local function getSwordSlot()
		updateInventoryCache()
		return cachedSwordSlot
	end
	
	local function hasValidTarget()
		if store.KillauraTarget ~= nil then
			return true
		end
		if KillauraTargetCheck.Enabled then
			return false
		end
		
		local now = tick()
		if now - lastTargetCheck < TARGET_CHECK_INTERVAL then
			return lastTargetResult
		end
		lastTargetCheck = now
		
		if not entitylib.isAlive then 
			lastTargetResult = false
			return false 
		end
		
		local myPos = entitylib.character.RootPart.Position
		local myLook = gameCamera.CFrame.LookVector
		local rangeSquared = AutoShootRange.Value * AutoShootRange.Value
		local fovRad = math_rad(AutoShootFOV.Value)
		local myTeam = lplr:GetAttribute('Team')
		
		for _, entity in entitylib.List do
			if entity.Player == lplr then continue end
			if not entity.Character then continue end
			
			local rootPart = entity.RootPart
			if not rootPart then continue end
			
			if entity.Player then
				if myTeam == entity.Player:GetAttribute('Team') then
					continue
				end
			else
				if not entity.Targetable then
					continue
				end
			end
			
			local pos = rootPart.Position
			local dx = pos.X - myPos.X
			local dy = pos.Y - myPos.Y
			local dz = pos.Z - myPos.Z
			local distanceSquared = dx * dx + dy * dy + dz * dz
			
			if distanceSquared > rangeSquared then continue end
			
			local distance = math.sqrt(distanceSquared)
			if distance < 0.01 then 
				lastTargetResult = true
				return true 
			end
			
			local toTargetX = dx / distance
			local toTargetY = dy / distance
			local toTargetZ = dz / distance
			local dot = myLook.X * toTargetX + myLook.Y * toTargetY + myLook.Z * toTargetZ
			local angle = math_acos(math.max(-1, math.min(1, dot)))
			
			if angle <= fovRad then
				lastTargetResult = true
				return true
			end
		end
		
		lastTargetResult = false
		return false
	end
	
	local AutoShoot = vape.Categories.Utility:CreateModule({
		Name = 'AutoShoot',
		Function = function(callback)
			if callback then
				autoShootEnabled = true
				
				lastInventoryUpdate = 0
				updateInventoryCache()
				
				old = bedwars.ProjectileController.createLocalProjectile
				bedwars.ProjectileController.createLocalProjectile = function(...)
					local source, data, proj = ...
					local projType = select(4, ...)
					if source and proj and (proj == 'arrow' or (projType and bedwars.ProjectileMeta[projType] and bedwars.ProjectileMeta[projType].combat)) and not _G.autoShootLock then
						task.spawn(function()
							if not hasArrows() then
								return
							end
							
							if FirstPersonCheck.Enabled and not isFirstPerson() then
								return
							end
							
							if KillauraTargetCheck.Enabled then
								if not store.KillauraTarget then
									return
								end
							else
								if not hasValidTarget() then
									return
								end
							end
							
							local bows = getBows()
							if #bows > 0 then
								_G.autoShootLock = true
								local ok, err = pcall(function()
									task.wait(AutoShootWaitDelay.Value)
									local selected = store.inventory.hotbarSlot
									for i = 1, #bows do
										local v = bows[i]
										if hotbarSwitch(v) then
											task.wait(0.05)
											leftClick()
											task.wait(0.05)
										end
									end
									hotbarSwitch(selected)
								end)
								_G.autoShootLock = false
							end
						end)
					end
					return old(...)
				end
				
				task.spawn(function()
					repeat
						task.wait(0.15) 
						if autoShootEnabled and not _G.autoShootLock then
							if not hasArrows() then
								continue
							end
							
							if FirstPersonCheck.Enabled and not isFirstPerson() then
								continue
							end
							
							local hasTarget = false
							if KillauraTargetCheck.Enabled then
								hasTarget = store.KillauraTarget ~= nil
							else
								hasTarget = hasValidTarget()
							end
							
							if not hasTarget then
								continue
							end
							
							local currentTime = tick()
							if (currentTime - lastAutoShootTime) >= AutoShootInterval.Value then
								local bows = getBows()
								
								if #bows > 0 then
									_G.autoShootLock = true
									lastAutoShootTime = currentTime
									pcall(function()
										local originalSlot = store.inventory.hotbarSlot

										for i = 1, #bows do
											local bowSlot = bows[i]
											if hotbarSwitch(bowSlot) then
												task.wait(AutoShootSwitchSpeed.Value)
												leftClick()
												task.wait(0.05)
											end
										end

										local swordSlot = getSwordSlot()
										if swordSlot then
											hotbarSwitch(swordSlot)
										else
											hotbarSwitch(originalSlot)
										end
									end)
									_G.autoShootLock = false
								end
							end
						end
					until not autoShootEnabled
				end)
			else
				autoShootEnabled = false
				if old then
					bedwars.ProjectileController.createLocalProjectile = old
				end
				_G.autoShootLock = false
				
				table.clear(cachedBows)
				cachedSwordSlot = nil
				cachedHasArrows = false
				lastInventoryUpdate = 0
			end
		end,
		Tooltip = 'auto switch to bow/cb/hh and shoot'
	})
	
	AutoShootInterval = AutoShoot:CreateSlider({
		Name = 'Shoot Interval',
		Min = 0.1,
		Max = 3,
		Default = 0.5,
		Decimal = 10,
		Suffix = function(val)
			return val == 1 and 'second' or 'seconds'
		end,
	})
	
	AutoShootSwitchSpeed = AutoShoot:CreateSlider({
		Name = 'Switch Delay',
		Min = 0,
		Max = 0.2,
		Default = 0.05,
		Decimal = 100,
		Suffix = 's',
	})
	
	AutoShootWaitDelay = AutoShoot:CreateSlider({
		Name = 'Wait Delay',
		Min = 0,
		Max = 1,
		Default = 0,
		Decimal = 100,
		Suffix = 's',
	})
	
	AutoShootRange = AutoShoot:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 30,
		Default = 20,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end,
	})
	
	AutoShootFOV = AutoShoot:CreateSlider({
		Name = 'FOV',
		Min = 1,
		Max = 180,
		Default = 90,
	})
	
	KillauraTargetCheck = AutoShoot:CreateToggle({
		Name = 'Require Killaura Target',
		Default = false,
	})
	
	FirstPersonCheck = AutoShoot:CreateToggle({
		Name = 'First Person Only',
		Default = false,
	})
	
	vape:Clean(vapeEvents.InventoryChanged.Event:Connect(function()
		lastInventoryUpdate = 0
	end))
end)

run(function()
	local a = {Enabled = false}
	a = vape.Categories.World:CreateModule({
		Name = "Leave Party",
		Function = function(call)
			if call then
				a:Toggle(false)
				game:GetService("ReplicatedStorage"):WaitForChild("events-@easy-games/lobby:shared/event/lobby-events@getEvents.Events"):WaitForChild("leaveParty"):FireServer()
			end
		end
	})
end)
	
run(function()
	local BedESP
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	
	local function Added(bed)
		if not BedESP.Enabled then return end
		local BedFolder = Instance.new('Folder')
		BedFolder.Parent = Folder
		Reference[bed] = BedFolder
		local parts = bed:GetChildren()
		table.sort(parts, function(a, b)
			return a.Name > b.Name
		end)
	
		for _, part in parts do
			if part:IsA('BasePart') and part.Name ~= 'Blanket' then
				local handle = Instance.new('BoxHandleAdornment')
				handle.Size = part.Size + Vector3.new(.01, .01, .01)
				handle.AlwaysOnTop = true
				handle.ZIndex = 2
				handle.Visible = true
				handle.Adornee = part
				handle.Color3 = part.Color
				if part.Name == 'Legs' then
					handle.Color3 = Color3.fromRGB(167, 112, 64)
					handle.Size = part.Size + Vector3.new(.01, -1, .01)
					handle.CFrame = CFrame.new(0, -0.4, 0)
					handle.ZIndex = 0
				end
				handle.Parent = BedFolder
			end
		end
	
		table.clear(parts)
	end
	
	BedESP = vape.Categories.Render:CreateModule({
		Name = 'BedESP',
		Function = function(callback)
			if callback then
				BedESP:Clean(collectionService:GetInstanceAddedSignal('bed'):Connect(function(bed)
					task.delay(0.2, Added, bed)
				end))
				BedESP:Clean(collectionService:GetInstanceRemovedSignal('bed'):Connect(function(bed)
					if Reference[bed] then
						Reference[bed]:Destroy()
						Reference[bed] = nil
					end
				end))
				for _, bed in collectionService:GetTagged('bed') do
					Added(bed)
				end
			else
				Folder:ClearAllChildren()
				table.clear(Reference)
			end
		end,
		Tooltip = 'Render Beds through walls'
	})
end)
	
run(function()
	local KitESP
	local Notify
	local Background
	local Color = {}
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	
	local ESPKits = {
		alchemist = {'alchemist_ingedients', 'thorns'},
		beekeeper = {'bee', 'bee'},
		bigman = {'treeOrb', 'natures_essence_1'},
		ghost_catcher = {'ghost', 'ghost_orb'},
		metal_detector = {'hidden-metal', 'iron'},
		sheep_herder = {'SheepModel', 'purple_hay_bale'},
		sorcerer = {'alchemy_crystal', 'wild_flower'},
		star_collector = {'stars', 'crit_star'},
		black_market_trader = {'shadow_coin', 'shadow_coin'},
		miner = {'petrified-player', 'large_rock'},
		trapper = {'snap_trap', 'snap_trap'},
		mage = {'ElementTome', 'mage_spellbook'},
	}
	local NONTaggedKits = {
		necromancer = {'Gravestone', true},
		battery = {'Open', true},
	}
	local DescendantKits = {
		['farmer_cletus'] = {
			{'carrot', 'carrot_seeds'},
			{'melon', 'melon_seeds'},
			{'pumpkin', 'pumpkin_seeds'},
		},
	}

	local function getAlchemistImage(v)
		local name = v and v.Name or ''
		if name == 'Mushrooms' then
			return bedwars.getIcon({itemType = 'mushrooms'}, true)
		elseif name == 'Thorns' then
			return bedwars.getIcon({itemType = 'thorns'}, true)
		else
			return bedwars.getIcon({itemType = 'wild_flower'}, true)
		end
	end

	local function getStarImage(v)
		local parent = v and v.Parent
		if parent and parent:IsA("Model") then
			local modelName = parent.Name
			if modelName == "CritStar" or modelName:lower():find("crit") then
				return bedwars.getIcon({itemType = 'crit_star'}, true)
			elseif modelName == "VitalityStar" or modelName:lower():find("vitality") then
				return bedwars.getIcon({itemType = 'vitality_star'}, true)
			end
		end
		return bedwars.getIcon({itemType = 'crit_star'}, true)
	end

	local function Added(v, icon, non)
		if Reference[v] then return end
		if Notify.Enabled then
			vape:CreateNotification("KitESP", `New object is added {v.Name}`, 2)
		end
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = icon
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled
		local image = Instance.new('ImageLabel')
		image.Size = UDim2.fromOffset(36, 36)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		image.BorderSizePixel = 0
		if non then
			image.Image = icon
		else
			image.Image = bedwars.getIcon({itemType = icon}, true)
		end
		image.Parent = billboard
		local uicorner = Instance.new('UICorner')
		uicorner.CornerRadius = UDim.new(0, 4)
		uicorner.Parent = image
		Reference[v] = billboard
	end

	local function AddedStar(v)
		if not v or not v.Parent then return end
		if Reference[v] then return end

		if Notify.Enabled then
			vape:CreateNotification("KitESP", `New object is added {v.Name}`, 2)
		end
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = 'star'
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled
		local image = Instance.new('ImageLabel')
		image.Size = UDim2.fromOffset(36, 36)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		image.BorderSizePixel = 0
		image.Image = getStarImage(v)
		image.Parent = billboard
		local uicorner = Instance.new('UICorner')
		uicorner.CornerRadius = UDim.new(0, 4)
		uicorner.Parent = image
		Reference[v] = billboard
	end
	
	local currentConnections = {}
	local currentKit = nil

	local function disconnectAll()
		for _, conn in ipairs(currentConnections) do
			conn:Disconnect()
		end
		table.clear(currentConnections)
	end

	local function addKit(tag, icon)
		if tag == 'alchemist_ingedients' then
			local connAdded = collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
				if v.PrimaryPart then
					task.wait(0.1)
					if Reference[v.PrimaryPart] then return end
					local billboard = Instance.new('BillboardGui')
					billboard.Parent = Folder
					billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
					billboard.Size = UDim2.fromOffset(36, 36)
					billboard.AlwaysOnTop = true
					billboard.ClipsDescendants = false
					billboard.Adornee = v.PrimaryPart
					local blur = addBlur(billboard)
					blur.Visible = Background.Enabled
					local image = Instance.new('ImageLabel')
					image.Size = UDim2.fromOffset(36, 36)
					image.Position = UDim2.fromScale(0.5, 0.5)
					image.AnchorPoint = Vector2.new(0.5, 0.5)
					image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
					image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
					image.BorderSizePixel = 0
					image.Image = getAlchemistImage(v)
					image.Parent = billboard
					local uicorner = Instance.new('UICorner')
					uicorner.CornerRadius = UDim.new(0, 4)
					uicorner.Parent = image
					Reference[v.PrimaryPart] = billboard
				end
			end)
			table.insert(currentConnections, connAdded)
			local connRemoved = collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
				if v.PrimaryPart and Reference[v.PrimaryPart] then
					Reference[v.PrimaryPart]:Destroy()
					Reference[v.PrimaryPart] = nil
				end
			end)
			table.insert(currentConnections, connRemoved)
			for _, v in collectionService:GetTagged(tag) do
				if v.PrimaryPart and not Reference[v.PrimaryPart] then
					local billboard = Instance.new('BillboardGui')
					billboard.Parent = Folder
					billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
					billboard.Size = UDim2.fromOffset(36, 36)
					billboard.AlwaysOnTop = true
					billboard.ClipsDescendants = false
					billboard.Adornee = v.PrimaryPart
					local blur = addBlur(billboard)
					blur.Visible = Background.Enabled
					local image = Instance.new('ImageLabel')
					image.Size = UDim2.fromOffset(36, 36)
					image.Position = UDim2.fromScale(0.5, 0.5)
					image.AnchorPoint = Vector2.new(0.5, 0.5)
					image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
					image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
					image.BorderSizePixel = 0
					image.Image = getAlchemistImage(v)
					image.Parent = billboard
					local uicorner = Instance.new('UICorner')
					uicorner.CornerRadius = UDim.new(0, 4)
					uicorner.Parent = image
					Reference[v.PrimaryPart] = billboard
				end
			end
			return
		end
		if tag == 'stars' then
			local connAdded = collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
				if v:IsA("Model") and v.PrimaryPart then
					task.wait(0.1)
					AddedStar(v.PrimaryPart)
				end
			end)
			table.insert(currentConnections, connAdded)
			local connRemoved = collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
				if v.PrimaryPart and Reference[v.PrimaryPart] then
					Reference[v.PrimaryPart]:Destroy()
					Reference[v.PrimaryPart] = nil
				end
			end)
			table.insert(currentConnections, connRemoved)
			for _, v in collectionService:GetTagged(tag) do
				if v:IsA("Model") and v.PrimaryPart then
					AddedStar(v.PrimaryPart)
				end
			end
			return
		end

		local connAdded = collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			if tag == 'bee' and (v.Name:find('TamedBee') or v:FindFirstChild('TamedBee')) then return end
			Added(v.PrimaryPart, icon, false)
		end)
		table.insert(currentConnections, connAdded)
		local connRemoved = collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if Reference[v.PrimaryPart] then
				Reference[v.PrimaryPart]:Destroy()
				Reference[v.PrimaryPart] = nil
			end
		end)
		table.insert(currentConnections, connRemoved)
		for _, v in collectionService:GetTagged(tag) do
			if tag == 'bee' and (v.Name:find('TamedBee') or v:FindFirstChild('TamedBee')) then continue end
			Added(v.PrimaryPart, icon, false)
		end
	end

	local function addKitNon(objName, icon)
		if typeof(icon) == "boolean" then
			if objName == "Gravestone" then
				icon = "rbxassetid://6307844310"
			elseif objName == "Open" then
				icon = "rbxassetid://10159166528"
			else
				icon = bedwars.getIcon({itemType = icon}, true) or ''
			end
		else
			icon = bedwars.getIcon({itemType = icon}, true)
		end
		local connAdded = workspace.ChildAdded:Connect(function(child)
			if child:IsA("Model") and child.Name == objName then
				task.wait(0.1)
				if child.PrimaryPart then
					Added(child, icon, true)
				end
			end
		end)
		table.insert(currentConnections, connAdded)
		local connRemoved = workspace.ChildRemoved:Connect(function(child)
			if child:IsA("Model") and child.Name == objName then
				if Reference[child] then
					Reference[child]:Destroy()
					Reference[child] = nil
				end
			end
		end)
		table.insert(currentConnections, connRemoved)
	end

	local function addKitDescendant(partName, icon)
		local resolvedIcon = bedwars.getIcon({itemType = icon}, true)
		
		local function shouldSkip(obj)
			local p = obj.Parent
			while p and p ~= workspace do
				if p.Name == partName then return true end
				p = p.Parent
			end
			return false
		end

		for _, obj in workspace:GetDescendants() do
			if obj:IsA("BasePart") and obj.Name == partName and not shouldSkip(obj) then
				if not Reference[obj] then
					Added(obj, resolvedIcon, true)
				end
			end
		end
		local connAdded = workspace.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") and obj.Name == partName and not shouldSkip(obj) then
				task.wait(0.1)
				if not Reference[obj] then
					Added(obj, resolvedIcon, true)
				end
			end
		end)
		table.insert(currentConnections, connAdded)
		local connRemoved = workspace.DescendantRemoving:Connect(function(obj)
			if obj:IsA("BasePart") and obj.Name == partName and Reference[obj] then
				Reference[obj]:Destroy()
				Reference[obj] = nil
			end
		end)
		table.insert(currentConnections, connRemoved)
	end

	local function setupKit(kitName)
		local kit = ESPKits[kitName]
		local nontag = NONTaggedKits[kitName]
		local desctag = DescendantKits[kitName]
		if kit then
			addKit(kit[1], kit[2])
		end
		if nontag then
			addKitNon(nontag[1], nontag[2])
		end
		if desctag then
			for _, entry in ipairs(desctag) do
				addKitDescendant(entry[1], entry[2])
			end
		end
	end

	KitESP = vape.Categories.Kits:CreateModule({
		Name = 'KitESP',
		Function = function(callback)
			if callback then
				task.spawn(function()
					while KitESP.Enabled do
						if not currentKit then
							repeat
								task.wait()
							until store.equippedKit ~= '' or not KitESP.Enabled
							if not KitESP.Enabled then break end
						end
						local newKit = store.equippedKit
						if newKit ~= currentKit then
							disconnectAll()
							Folder:ClearAllChildren()
							table.clear(Reference)
							if newKit ~= '' then
								setupKit(newKit)
							end
							currentKit = newKit
						end
						task.wait(1)
					end
					disconnectAll()
					Folder:ClearAllChildren()
					table.clear(Reference)
					currentKit = nil
				end)
			else
				disconnectAll()
				Folder:ClearAllChildren()
				table.clear(Reference)
				currentKit = nil
			end
		end,
		Tooltip = 'esp for kits'
	})
	Notify = KitESP:CreateToggle({
		Name = "Notify",
		Default = false
	})
	Background = KitESP:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then Color.Object.Visible = callback end
			for _, v in Reference do
				v.ImageLabel.BackgroundTransparency = 1 - (callback and Color.Opacity or 0)
				v.Blur.Visible = callback
			end
		end,
		Default = true
	})
    Color = KitESP:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in Reference do
                v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                v.ImageLabel.BackgroundTransparency = 1 - opacity
            end
        end,
        Darker = true
    })

    task.defer(function()
        if Color and Color.Object then
            Color.Object.Visible = Background.Enabled  
        end
    end)
end)

run(function()
	local LootESP
	local IronToggle
	local DiamondToggle
	local EmeraldToggle
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	
	local CollectionService = collectionService
	
	local lootTypes = {
		iron = {
			keywords = {'iron'},
			color = Color3.fromRGB(200, 200, 200),
			icon = 'iron',
			displayName = 'IRON'
		},
		diamond = {
			keywords = {'diamond'},
			color = Color3.fromRGB(85, 200, 255),
			icon = 'diamond',
			displayName = 'DIAMOND'
		},
		emerald = {
			keywords = {'emerald'},
			color = Color3.fromRGB(0, 255, 100),
			icon = 'emerald',
			displayName = 'EMERALD'
		}
	}
	
	local function getLootType(itemName)
		local nameLower = itemName:lower()
		for lootType, config in pairs(lootTypes) do
			for _, keyword in ipairs(config.keywords) do
				if nameLower:find(keyword, 1, true) then 
					return lootType, config
				end
			end
		end
		return nil
	end
	
	local function isLootEnabled(lootType)
		if lootType == 'iron' then
			return IronToggle.Enabled
		elseif lootType == 'diamond' then
			return DiamondToggle.Enabled
		elseif lootType == 'emerald' then
			return EmeraldToggle.Enabled
		end
		return false
	end
	
	local function getProperIcon(lootType)
		local icon = bedwars.getIcon({itemType = lootType}, true)
		
		if not icon or icon == "" then
			return nil
		end
		
		return icon
	end
	
	local function Added(lootHandle, lootType, config)
		if not isLootEnabled(lootType) then return end
		if Reference[lootHandle] then return end 
		
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = lootType
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(40, 40)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = lootHandle
		
		local blur = addBlur(billboard)
		blur.Visible = true 
		
		local iconImage = getProperIcon(config.icon)
		
		if iconImage then
			local image = Instance.new('ImageLabel')
			image.Size = UDim2.fromOffset(40, 40)
			image.Position = UDim2.fromScale(0.5, 0.5)
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.BackgroundColor3 = Color3.new(0, 0, 0) 
			image.BackgroundTransparency = 0.3 
			image.BorderSizePixel = 0
			image.Image = iconImage
			image.Parent = billboard
			
			local uicorner = Instance.new('UICorner')
			uicorner.CornerRadius = UDim.new(0, 4)
			uicorner.Parent = image
		else
			local frame = Instance.new('Frame')
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundColor3 = Color3.new(0, 0, 0) 
			frame.BackgroundTransparency = 0.3 
			frame.BorderSizePixel = 0
			frame.Parent = billboard
			
			local uicorner = Instance.new('UICorner')
			uicorner.CornerRadius = UDim.new(0, 4)
			uicorner.Parent = frame
			
			local textLabel = Instance.new('TextLabel')
			textLabel.Size = UDim2.fromScale(1, 1)
			textLabel.Position = UDim2.fromScale(0.5, 0.5)
			textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			textLabel.BackgroundTransparency = 1
			textLabel.Text = config.displayName
			textLabel.TextColor3 = config.color
			textLabel.TextScaled = true
			textLabel.Font = Enum.Font.GothamBold
			textLabel.TextStrokeTransparency = 0.5
			textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			textLabel.Parent = frame
		end
		
		Reference[lootHandle] = billboard
	end
	
	local function Removed(lootHandle)
		if Reference[lootHandle] then
			Reference[lootHandle]:Destroy()
			Reference[lootHandle] = nil
		end
	end
	
	local function findExistingLoot()
		local tagged = CollectionService:GetTagged('ItemDrop')
		for _, drop in ipairs(tagged) do
			local handle = drop:FindFirstChild('Handle')
			if handle then
				local lootType, config = getLootType(drop.Name)
				if lootType and isLootEnabled(lootType) then
					if not Reference[handle] then
						Added(handle, lootType, config)
					end
				end
			end
		end
	end
	
	local function refreshLootType(lootType)
		if not LootESP.Enabled then return end
		
		local enabled = isLootEnabled(lootType)
		
		if not enabled then
			for handle, billboard in pairs(Reference) do
				if billboard.Name == lootType then
					billboard:Destroy()
					Reference[handle] = nil
				end
			end
		else
			local tagged = CollectionService:GetTagged('ItemDrop')
			for _, drop in ipairs(tagged) do
				local handle = drop:FindFirstChild('Handle')
				if handle then
					local dropLootType, config = getLootType(drop.Name)
					if dropLootType == lootType and not Reference[handle] then
						Added(handle, lootType, config)
					end
				end
			end
		end
	end
	
	LootESP = vape.Categories.Render:CreateModule({
		Name = 'LootESP',
		Function = function(callback)
			if callback then
				findExistingLoot()
				
				LootESP:Clean(CollectionService:GetInstanceAddedSignal('ItemDrop'):Connect(function(drop)
					if not LootESP.Enabled then return end
					
					task.defer(function()
						local handle = drop:FindFirstChild('Handle')
						if not handle then return end
						
						local lootType, config = getLootType(drop.Name)
						if lootType and isLootEnabled(lootType) then
							Added(handle, lootType, config)
						end
					end)
				end))
				
				LootESP:Clean(CollectionService:GetInstanceRemovedSignal('ItemDrop'):Connect(function(drop)
					local handle = drop:FindFirstChild('Handle')
					if handle then
						Removed(handle)
					end
				end))
				
			else
				for handle, billboard in pairs(Reference) do
					billboard:Destroy()
				end
				table.clear(Reference)
			end
		end,
		Tooltip = 'esp for loot (iron, emerald, diamonds)'
	})
	
	IronToggle = LootESP:CreateToggle({
		Name = 'Iron',
		Function = function(callback)
			refreshLootType('iron')
		end,
		Default = true
	})
	
	DiamondToggle = LootESP:CreateToggle({
		Name = 'Diamond',
		Function = function(callback)
			refreshLootType('diamond')
		end,
		Default = true
	})
	
	EmeraldToggle = LootESP:CreateToggle({
		Name = 'Emerald',
		Function = function(callback)
			refreshLootType('emerald')
		end,
		Default = true
	})
end)

run(function()
	local Value
	local CameraDir
	local start
	local JumpTick, JumpSpeed, Direction = tick(), 0
	local projectileRemote = {InvokeServer = function() end}
	task.spawn(function()
		projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
	end)
	
	local function launchProjectile(item, pos, proj, speed, dir)
		if not pos then return end
	
		pos = pos - dir * 0.1
		local shootPosition = (CFrame.lookAlong(pos, Vector3.new(0, -speed, 0)) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ)))
		switchItem(item.tool, 0)
		task.wait(0.1)
		bedwars.ProjectileController:createLocalProjectile(bedwars.ProjectileMeta[proj], proj, proj, shootPosition.Position, '', shootPosition.LookVector * speed, {drawDurationSeconds = 1})
		if projectileRemote:InvokeServer(item.tool, proj, proj, shootPosition.Position, pos, shootPosition.LookVector * speed, httpService:GenerateGUID(true), {drawDurationSeconds = 1}, workspace:GetServerTimeNow() - 0.045) then
			local shoot = bedwars.ItemMeta[item.itemType].projectileSource.launchSound
			shoot = shoot and shoot[math.random(1, #shoot)] or nil
			if shoot then
				bedwars.SoundManager:playSound(shoot)
			end
		end
	end
	
	local LongJumpMethods = {
		cannon = function(_, pos, dir)
			pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
			local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
			bedwars.placeBlock(rounded, 'cannon', false)
	
			task.delay(0, function()
				local block, blockpos = getPlacedBlock(rounded)
				if block and block.Name == 'cannon' and (entitylib.character.RootPart.Position - block.Position).Magnitude < 20 then
					local breaktype = bedwars.ItemMeta[block.Name].block.breakType
					local tool = store.tools[breaktype]
					if tool then
						switchItem(tool.tool)
					end
	
					bedwars.Client:Get(remotes.CannonAim):SendToServer({
						cannonBlockPos = blockpos,
						lookVector = dir
					})
	
					local broken = 0.1
					if bedwars.BlockController:calculateBlockDamage(lplr, {blockPosition = blockpos}) < block:GetAttribute('Health') then
						broken = 0.4
						bedwars.breakBlock(block, true, true)
					end
	
					task.delay(broken, function()
						for _ = 1, 3 do
							local call = bedwars.Client:Get(remotes.CannonLaunch):CallServer({cannonBlockPos = blockpos})
							if call then
								bedwars.breakBlock(block, true, true)
								JumpSpeed = 5.25 * Value.Value
								JumpTick = tick() + 2.3
								Direction = Vector3.new(dir.X, 0, dir.Z).Unit
								break
							end
							task.wait(0.1)
						end
					end)
				end
			end)
		end,
		cat = function(_, _, dir)
			LongJump:Clean(vapeEvents.CatPounce.Event:Connect(function()
				JumpSpeed = 4 * Value.Value
				JumpTick = tick() + 2.5
				Direction = Vector3.new(dir.X, 0, dir.Z).Unit
				entitylib.character.RootPart.Velocity = Vector3.zero
			end))
	
			if not bedwars.AbilityController:canUseAbility('CAT_POUNCE') then
				repeat task.wait() until bedwars.AbilityController:canUseAbility('CAT_POUNCE') or not LongJump.Enabled
			end
	
			if bedwars.AbilityController:canUseAbility('CAT_POUNCE') and LongJump.Enabled then
				bedwars.AbilityController:useAbility('CAT_POUNCE')
			end
		end,
		fireball = function(item, pos, dir)
			launchProjectile(item, pos, 'fireball', 60, dir)
		end,
		grappling_hook = function(item, pos, dir)
			launchProjectile(item, pos, 'grappling_hook_projectile', 140, dir)
		end,
		jade_hammer = function(item, _, dir)
			if not bedwars.AbilityController:canUseAbility(item.itemType..'_jump') then
				repeat task.wait() until bedwars.AbilityController:canUseAbility(item.itemType..'_jump') or not LongJump.Enabled
			end
	
			if bedwars.AbilityController:canUseAbility(item.itemType..'_jump') and LongJump.Enabled then
				bedwars.AbilityController:useAbility(item.itemType..'_jump')
				JumpSpeed = 1.4 * Value.Value
				JumpTick = tick() + 2.5
				Direction = Vector3.new(dir.X, 0, dir.Z).Unit
			end
		end,
		tnt = function(item, pos, dir)
			pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
			local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
			start = Vector3.new(rounded.X, start.Y, rounded.Z) + (dir * (item.itemType == 'pirate_gunpowder_barrel' and 2.6 or 0.2))
			bedwars.placeBlock(rounded, item.itemType, false)
		end,
		wood_dao = function(item, pos, dir)
			if (lplr.Character:GetAttribute('CanDashNext') or 0) > workspace:GetServerTimeNow() or not bedwars.AbilityController:canUseAbility('dash') then
				repeat task.wait() until (lplr.Character:GetAttribute('CanDashNext') or 0) < workspace:GetServerTimeNow() and bedwars.AbilityController:canUseAbility('dash') or not LongJump.Enabled
			end
	
			if LongJump.Enabled then
				bedwars.SwordController.lastAttack = workspace:GetServerTimeNow()
				switchItem(item.tool, 0.1)
				replicatedStorage['events-@easy-games/game-core:shared/game-core-networking@getEvents.Events'].useAbility:FireServer('dash', {
					direction = dir,
					origin = pos,
					weapon = item.itemType
				})
				JumpSpeed = 4.5 * Value.Value
				JumpTick = tick() + 2.4
				Direction = Vector3.new(dir.X, 0, dir.Z).Unit
			end
		end
	}
	for _, v in {'stone_dao', 'iron_dao', 'diamond_dao', 'emerald_dao'} do
		LongJumpMethods[v] = LongJumpMethods.wood_dao
	end
	LongJumpMethods.void_axe = LongJumpMethods.jade_hammer
	LongJumpMethods.siege_tnt = LongJumpMethods.tnt
	LongJumpMethods.pirate_gunpowder_barrel = LongJumpMethods.tnt
	
	LongJump = vape.Categories.Blatant:CreateModule({
		Name = 'LongJump',
		Function = function(callback)
			frictionTable.LongJump = callback or nil
			updateVelocity()
			if callback then
				LongJump:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
					if damageTable.entityInstance == lplr.Character and damageTable.fromEntity == lplr.Character and (not damageTable.knockbackMultiplier or not damageTable.knockbackMultiplier.disabled) then
						local knockbackBoost = bedwars.KnockbackUtil.calculateKnockbackVelocity(Vector3.one, 1, {
							vertical = 0,
							horizontal = (damageTable.knockbackMultiplier and damageTable.knockbackMultiplier.horizontal or 1)
						}).Magnitude * 1.1
	
						if knockbackBoost >= JumpSpeed then
							local pos = damageTable.fromPosition and Vector3.new(damageTable.fromPosition.X, damageTable.fromPosition.Y, damageTable.fromPosition.Z) or damageTable.fromEntity and damageTable.fromEntity.PrimaryPart.Position
							if not pos then return end
							local vec = (entitylib.character.RootPart.Position - pos)
							JumpSpeed = knockbackBoost
							JumpTick = tick() + 2.5
							Direction = Vector3.new(vec.X, 0, vec.Z).Unit
						end
					end
				end))
				LongJump:Clean(vapeEvents.GrapplingHookFunctions.Event:Connect(function(dataTable)
					if dataTable.hookFunction == 'PLAYER_IN_TRANSIT' then
						local vec = entitylib.character.RootPart.CFrame.LookVector
						JumpSpeed = 2.5 * Value.Value
						JumpTick = tick() + 2.5
						Direction = Vector3.new(vec.X, 0, vec.Z).Unit
					end
				end))
	
				start = entitylib.isAlive and entitylib.character.RootPart.Position or nil
				LongJump:Clean(runService.PreSimulation:Connect(function(dt)
					local root = entitylib.isAlive and entitylib.character.RootPart or nil
	
					if root and isnetworkowner(root) then
						if JumpTick > tick() then
							root.AssemblyLinearVelocity = Direction * (getSpeed() + ((JumpTick - tick()) > 1.1 and JumpSpeed or 0)) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
							if entitylib.character.Humanoid.FloorMaterial == Enum.Material.Air and not start then
								root.AssemblyLinearVelocity += Vector3.new(0, dt * (workspace.Gravity - 23), 0)
							else
								root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 15, root.AssemblyLinearVelocity.Z)
							end
							start = nil
						else
							if start then
								root.CFrame = CFrame.lookAlong(start, root.CFrame.LookVector)
							end
							root.AssemblyLinearVelocity = Vector3.zero
							JumpSpeed = 0
						end
					else
						start = nil
					end
				end))

				if store.hand and store.hand.tool and LongJumpMethods[store.hand.tool.Name] then
					task.spawn(LongJumpMethods[store.hand.tool.Name], getItem(store.hand.tool.Name), start, (CameraDir.Enabled and gameCamera or entitylib.character.RootPart).CFrame.LookVector)
					return
				end
				
				local foundItem = false
				for i, v in LongJumpMethods do
					local item = getItem(i)
					if item or store.equippedKit == i then
						foundItem = true
						task.spawn(v, item, start, (CameraDir.Enabled and gameCamera or entitylib.character.RootPart).CFrame.LookVector)
						break
					end
				end
				if not foundItem then
					notif("LongJump", "unable to find tool to use Long Jump with gng", 3)
					LongJump:Toggle()
					return
				end
			else
				JumpTick = tick()
				Direction = nil
				JumpSpeed = 0
			end
		end,
		ExtraText = function()
			return 'Heatseeker'
		end,
		Tooltip = 'lets you jump farther'
	})
	Value = LongJump:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 37,
		Default = 37,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	CameraDir = LongJump:CreateToggle({
		Name = 'Camera Direction'
	})
end)

run(function()
	local BedAlarm
	local Types
	local Distance
	local UpdateTick
	local HighlightEnemies
	local SoundVolume
	local ShowAlarm

	local function getBed()
		if not (entitylib.isAlive and lplr.Character) then return nil end
		local id = lplr.Character:GetAttribute('Team') or lplr.Character:GetAttribute('TeamId')
		for _, v in collectionService:GetTagged('bed') do
			if tonumber(id) == tonumber(v:GetAttribute('TeamId')) then
				return v
			end
		end
		return nil
	end

	local function createAlarm(bedpos)
		if not ShowAlarm.Enabled then return end
		if not bedpos then return end
		if store.BedAlarm[lplr] then return end

		if bedwars.BedAlarmController then
			local suc, res = pcall(function()
				local oldthread = 0
				if vape.ThreadFix then 
					oldthread = getthreadidentity()
					setthreadidentity(8) 
				end

				local myTeam = lplr.Character:GetAttribute('Team') or lplr.Character:GetAttribute('TeamId') or -1
				bedwars.BedAlarmController:getOrCreateBedAlarmModel(myTeam, bedpos)

				if vape.ThreadFix then 
					setthreadidentity(oldthread) 
				end
			end)

			if suc then
				store.BedAlarm[lplr] = true
			else
				vape:CreateNotification("BedAlarm", `Creating Alarm issue: {res}`, 16, 'alert')
			end
		end
	end

	local function AlarmAffects(bedpos)
		if not ShowAlarm.Enabled or not bedpos then return end
		if not store.BedAlarm[lplr] then return end

		local myTeam = lplr.Character:GetAttribute('Team') or lplr.Character:GetAttribute('TeamId') or -1
		pcall(function()
			bedwars.BedAlarmController:triggerBedAlarmModel({bedPosition = bedpos, teamId = myTeam})
		end)
	end

	local function removeAlarm()
		if not store.BedAlarm[lplr] then return end
		
		local myTeam = lplr.Character:GetAttribute('Team') or lplr.Character:GetAttribute('TeamId') or -1
		local alarm = bedwars.BedAlarmController.bedAlarmModelMap[myTeam]
		if alarm then
			alarm:Destroy()
			bedwars.BedAlarmController.bedAlarmModelMap[myTeam] = nil
		end
		store.BedAlarm[lplr] = nil
	end

	local function createHighlight(ent)
		if store.BedAlarmHighlightedEnimes[ent] then return end
		
		local character = ent.character or ent.Character
		if not character then return end

		local highlight = Instance.new("Highlight")
		highlight.Name = "BedAlarmHighlight"
		highlight.Adornee = character
		highlight.FillColor = Color3.fromRGB(255, 80, 80)
		highlight.OutlineColor = Color3.fromRGB(255, 100, 100)
		highlight.FillTransparency = 0.6
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = character
		
		store.BedAlarmHighlightedEnimes[ent] = highlight
	end

	local function clearAllHighlights()
		for _, highlight in pairs(store.BedAlarmHighlightedEnimes) do
			if highlight and highlight.Parent then highlight:Destroy() end
		end
		table.clear(store.BedAlarmHighlightedEnimes)
	end

	local function removeHighlight(ent)
		local hl = store.BedAlarmHighlightedEnimes[ent]
		if hl then
			hl:Destroy()
			store.BedAlarmHighlightedEnimes[ent] = nil
		end
	end

	BedAlarm = vape.Categories.Utility:CreateModule({
		Name = "BedAlarm",
		Function = function(callback)
			if callback then
				store.BedAlarmNotifyTick = 0
				store.BedAlarmSoundTick = 0
				store.BedAlarmIsTrigged = false

				local bed = getBed()
				local bedpos = bed and bed:GetPivot().Position or Vector3.zero

				if ShowAlarm.Enabled then
					createAlarm(bedpos)
				end

				local _bedAlarmSearch = {Origin = bedpos, Range = Distance.Value, Part = 'RootPart', Players = true, IgnoreLocal = true}
				repeat
					if bedpos then
						_bedAlarmSearch.Origin = bedpos
						_bedAlarmSearch.Range = Distance.Value
						local entity = entitylib.EntityPosition(_bedAlarmSearch)

						if entity then
							store.BedAlarmIsTrigged = true

							if ShowAlarm.Enabled then
								createAlarm(bedpos)
							end

							if os.time() >= store.BedAlarmNotifyTick then
								store.BedAlarmNotifyTick = os.time() + UpdateTick.Value

								AlarmAffects(bedpos)

								local msg = '[Bed Alarm]: An intruder is near your bed!'
								if Types.Value == 'Vape' then
									vape:CreateNotification("BedAlarm", msg, UpdateTick.Value + 1)
								else
									pcall(function()
										bedwars.NotificationController:sendInfoNotification({ message = msg })
									end)
								end
							end

							if os.time() >= store.BedAlarmSoundTick then
								store.BedAlarmSoundTick = os.time() + 1.2

								local distance = (bedpos - entity.RootPart.Position).Magnitude
								local soundId = distance >= 30 and bedwars.SoundList.BED_ALARM_TRIGGERED_FAR or bedwars.SoundList.BED_ALARM

								pcall(function()
									bedwars.SoundManager:playSound(soundId, {
										volumeMultiplier = SoundVolume.Value
									})
								end)
							end

							if HighlightEnemies.Enabled then
								createHighlight(entity)
							end
						else
							store.BedAlarmIsTrigged = false
						end
					end

					for ent, _ in pairs(store.BedAlarmHighlightedEnimes) do
						if not entity or ent ~= entity then
							removeHighlight(ent)
						end
					end

					task.wait(1/60)
				until not BedAlarm.Enabled

			else
				store.BedAlarmIsTrigged = false
				clearAllHighlights()
				removeAlarm()
			end
		end
	})

	Distance = BedAlarm:CreateSlider({Name = 'Distance', Min = 10, Max = 100, Default = 64, Suffix = " studs"})
	
	Types = BedAlarm:CreateDropdown({
		Name = 'Notification Type',
		List = {'Vape','Bedwars'},
		Default = 'Bedwars'
	})
	
	UpdateTick = BedAlarm:CreateSlider({
		Name = "Update Tick",
		Min = 0.5,
		Max = 8,
		Decimal = 5,
		Default = 3,
		Suffix = 's'
	})
	
	SoundVolume = BedAlarm:CreateSlider({
		Name = "Volume Multiplier",
		Min = 0.1,
		Max = 3,
		Default = 1.5,
		Decimal = 5,
	})
	
	HighlightEnemies = BedAlarm:CreateToggle({
		Name = 'Highlight Enemies',
		Default = true,
		Function = function(v)
			if not v then clearAllHighlights() end
		end
	})
	
	ShowAlarm = BedAlarm:CreateToggle({
		Name = "Show Alarm Model",
		Default = false,
		Function = function(v)
			local bed = getBed()
			local pos = bed and bed:GetPivot().Position or Vector3.zero
			if v then
				createAlarm(pos)
			else
				removeAlarm()
			end
		end
	})
end)

run(function()
	local StorageESP
	local List
	local Background
	local Color = {}
	local Reference = {}
	local ChestContents = {} 
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	
	local function getEnabledItemsSet()
		local set = {}
		for _, v in ipairs(List.ListEnabled) do
			set[v] = true
		end
		return set
	end
	
	local function nearStorageItem(item, enabledSet)
		for itemName in pairs(enabledSet) do
			if item:find(itemName, 1, true) then return itemName end
		end
		return nil
	end
	
	local function refreshAdornee(billboard)
		local chestPart = billboard.Adornee
		local folderValue = chestPart and chestPart:FindFirstChild('ChestFolderValue')
		local chest = folderValue and folderValue.Value or nil

		for _, obj in ipairs(billboard:GetChildren()) do
			if obj:IsA('ImageLabel') and obj.Name == 'Icon' then
				obj:Destroy()
			end
		end

		if not chest then
			billboard.Enabled = false
			return
		end

		local chestitems = chest:GetChildren()
		local enabledSet = getEnabledItemsSet()
		local listIsEmpty = next(enabledSet) == nil

		local matchedItems = {}
		for _, item in ipairs(chestitems) do
			if item:IsA('Accessory') then
				if listIsEmpty or enabledSet[item.Name] or nearStorageItem(item.Name, enabledSet) then
					if not matchedItems[item.Name] then
						matchedItems[item.Name] = true
						table.insert(matchedItems, item.Name)
					end
				end
			end
		end

		local count = #matchedItems
		if count == 0 then
			billboard.Enabled = false
			return
		end

		billboard.Enabled = true
		local iconSize = 36
		local padding = 2
		local totalWidth = count * iconSize + (count - 1) * padding
		billboard.Size = UDim2.fromOffset(totalWidth, iconSize)

		for i, itemName in ipairs(matchedItems) do
			local icon = Instance.new('ImageLabel')
			icon.Name = 'Icon'
			icon.Size = UDim2.fromOffset(iconSize, iconSize)
			icon.Position = UDim2.fromOffset((i - 1) * (iconSize + padding), 0)
			icon.AnchorPoint = Vector2.new(0, 0)
			icon.BackgroundColor3 = Color3.new(0, 0, 0)
			icon.BackgroundTransparency = 0.3
			icon.BorderSizePixel = 0
			icon.Image = bedwars.getIcon({itemType = itemName}, true)
			icon.Parent = billboard

			local uicorner = Instance.new('UICorner')
			uicorner.CornerRadius = UDim.new(0, 4)
			uicorner.Parent = icon
		end
	end
	
	local function Added(v)
		if Reference[v] then return end

		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = 'chest'
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		billboard.Enabled = false

		local blur = addBlur(billboard)

		Reference[v] = billboard

		refreshAdornee(billboard)

		task.defer(function()
			local folderValue = v:FindFirstChild('ChestFolderValue')
			local chest = folderValue and folderValue.Value or nil
			if chest and Reference[v] then
				local conn1 = chest.ChildAdded:Connect(function()
					if Reference[v] then refreshAdornee(Reference[v]) end
				end)
				local conn2 = chest.ChildRemoved:Connect(function()
					if Reference[v] then refreshAdornee(Reference[v]) end
				end)
				billboard.AncestryChanged:Connect(function()
					conn1:Disconnect()
					conn2:Disconnect()
				end)
			end
		end)
	end
	
	local function Removed(v)
		if Reference[v] then
			Reference[v]:Destroy()
			Reference[v] = nil
			ChestContents[v] = nil
		end
	end
	
	StorageESP = vape.Categories.Render:CreateModule({
		Name = 'StorageESP',
		Function = function(callback)
			if callback then
				local tagged = collectionService:GetTagged('chest')
				for _, v in ipairs(tagged) do
					Added(v)
				end
				
				StorageESP:Clean(collectionService:GetInstanceAddedSignal('chest'):Connect(Added))
				StorageESP:Clean(collectionService:GetInstanceRemovedSignal('chest'):Connect(Removed))
				StorageESP:Clean(task.spawn(function()
					while StorageESP.Enabled do
						task.wait(0.5)
						if not StorageESP.Enabled then break end
						for chest, billboard in pairs(Reference) do
							if not chest or not chest.Parent then
								Removed(chest)
							else
								refreshAdornee(billboard)
							end
						end
					end
				end))
			else
				for chest in pairs(Reference) do
					Removed(chest)
				end
			end
		end,
		Tooltip = 'shows what items are in a chest'
	})
	
	List = StorageESP:CreateTextList({
		Name = 'Item',
		Function = function()
			table.clear(ChestContents)
			for _, v in pairs(Reference) do
				refreshAdornee(v)
			end
		end
	})
	
	Background = StorageESP:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then Color.Object.Visible = callback end
			for _, v in pairs(Reference) do
				local icon = v:FindFirstChild('Icon')
				if icon then
					icon.BackgroundTransparency = callback and 0.3 or 1
				end
			end
		end,
		Default = true
	})
	
    Color = StorageESP:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in pairs(Reference) do
                v.Frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                v.Frame.BackgroundTransparency = 1 - opacity
            end
        end,
        Darker = true
    })

    task.defer(function()
        if Color and Color.Object then
            Color.Object.Visible = Background.Enabled  
        end
    end)
end)
	
run(function()
	local AutoKit
	local Legit
	local Sorts
	local Targets
	local Toggles = {}
	local AutoKitFunctions

	local function kitCollection(id, func, range, specific)
		repeat
			if entitylib.isAlive then
				local objs = type(id) == 'table' and id or collection(id, AutoKit)
				local localPosition = entitylib.character.RootPart.Position
				for _, v in objs do
					if not AutoKit.Enabled then break end
					local part = not v:IsA('Model') and v or v.PrimaryPart
					if part and (part.Position - localPosition).Magnitude <= range then
						local success, err = pcall(func, v)
						task.wait(0.02)
					end
				end
			end
			task.wait(0.05)
		until not AutoKit.Enabled
	end

	AutoKit = vape.Categories.Utility:CreateModule({
		Name = 'AutoKit',
		Function = function(callback)
			if callback then
				repeat task.wait() until store.equippedKit ~= '' and store.matchState ~= 0 or (not AutoKit.Enabled)
				if AutoKit.Enabled and AutoKitFunctions[store.equippedKit] and Toggles[store.equippedKit].Enabled then
					AutoKitFunctions[store.equippedKit]()
				end
			end
		end,
		Tooltip = 'auto use kit abilities'
	})

	Targets = AutoKit:CreateTargets({
		Players = true,
		NPCs = true,
		Walls = true
	})
	Sorts = AutoKit:CreateDropdown({
		Name = 'Sort',
		List = getSortList({'Damage', 'Distance'})
	})
	Legit = AutoKit:CreateToggle({Name = 'Legit'})

	AutoKitFunctions = {
		ghost_catcher = function()
			local collectRemote = replicatedStorage:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("net"):WaitForChild("out"):WaitForChild("_NetManaged"):WaitForChild("CollectCollectableEntity")
			local thread = task.spawn(function()
				repeat
					if not Legit.Enabled or isHoldingItem({'vacuum'}) then
						for _, obj in collectionService:GetTagged('ghost') do
							local id = obj:GetAttribute('Id')
							if id then
								collectRemote:FireServer({ id = id })
							end
						end
					end
					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		falconer = function()
			local canRecall = false
			local useAbilityRemote = replicatedStorage:WaitForChild("events-@easy-games/game-core:shared/game-core-networking@getEvents.Events"):WaitForChild("useAbility")
			local sendFalconRemote = replicatedStorage:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("net"):WaitForChild("out"):WaitForChild("_NetManaged"):WaitForChild("SendFalconRequested")
			local recallFalconRemote = replicatedStorage:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("net"):WaitForChild("out"):WaitForChild("_NetManaged"):WaitForChild("RecallFalconRequested")
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then task.wait(0.1); continue end

					local plr = entitylib.EntityPosition({
						Range = 125,
						Part = "RootPart",
						Players = true,
						Sort = sortmethods[Sorts.Value],
						Wallcheck = Legit.Enabled
					})

					if plr then
						local pos = plr.RootPart.Position
						useAbilityRemote:FireServer("ACTIVATE_FALCON_INDICATOR")
						task.wait(0.05)
						useAbilityRemote:FireServer("SEND_FALCON", { target = pos })
						sendFalconRemote:FireServer({ strikeZoneEpicenter = pos })
						canRecall = true
						task.wait(3)
					else
						if canRecall then
							canRecall = false
							useAbilityRemote:FireServer("RECALL_FALCON")
							recallFalconRemote:FireServer()
						end
					end

					task.wait(0.2)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		rebellion_leader = function()
			local useAbilityRemote = replicatedStorage:WaitForChild("events-@easy-games/game-core:shared/game-core-networking@getEvents.Events"):WaitForChild("useAbility")
			local function getCurrentAura()
				return lplr:GetAttribute("LeaderAuraType") 
			end
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then task.wait(0.1); continue end

					local health = lplr.Character:GetAttribute("Health") or 0
					local plr = entitylib.EntityPosition({
						Range = 14,
						Part = "RootPart",
						Players = true,
						Sort = sortmethods[Sorts.Value],
						Wallcheck = Legit.Enabled
					})

					if health <= 40 then
						useAbilityRemote:FireServer("rebellion_shield")
						task.wait(0.05)
						continue
					end
					if plr then
						if getCurrentAura() ~= "damage" then
							useAbilityRemote:FireServer("rebellion_aura_swap")
							task.wait(0.1)
						end
					else
						if getCurrentAura() ~= "healing" then
							useAbilityRemote:FireServer("rebellion_aura_swap")
							task.wait(0.1)
						end
					end

					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
        miner = function()
            kitCollection('petrified-player', function(v)
                bedwars.Client:Get(remotes.MinerDig):SendToServer({
                    petrifyId = v:GetAttribute('PetrifyId')
                })
            end, 6, true)
        end,
		styx = function()
			local exitPortalUUID = ""
			local entrancePortalData = nil
			local portalOpen = false

			local entranceConn = bedwars.Client:Get(remotes.StyxSpawnEntrancePortal):Connect(function(v1)
				if v1.entrancePortalData.player == lplr then
					entrancePortalData = v1.entrancePortalData
				end
			end)
			AutoKit:Clean(entranceConn)

			local spawnConn = bedwars.Client:Get(remotes.StyxSpawnExitPortal):Connect(function(v1)
				exitPortalUUID = v1.exitPortalData.uuid
				portalOpen = false
				task.spawn(function()
					task.wait(0.2)
					bedwars.Client:Get(remotes.TryOpenStyxPortalExit):CallServer(exitPortalUUID)
				end)
			end)
			AutoKit:Clean(spawnConn)

			local openConn = bedwars.Client:Get(remotes.StyxExitPortal):Connect(function(v1)
				portalOpen = true
				if entrancePortalData then
					task.wait(0.1)
					bedwars.Client:Get(remotes.StyxPortal):SendToServer({
						entrancePortalData = entrancePortalData
					})
				end
			end)
			AutoKit:Clean(openConn)
		end,
		sorcerer = function()
			local thread = task.spawn(function()
				kitCollection('alchemy_crystal', function(v)
					if not entitylib.character or not entitylib.character.RootPart then return end
					local part = v:IsA('Model') and v.PrimaryPart or v
					if not part then return end
					if (part.Position - entitylib.character.RootPart.Position).Magnitude > 12 then return end
					bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH)
					bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
					bedwars.Client:Get(remotes.CollectCollectableEntity):SendToServer({id = v:GetAttribute("Id"),collectableName = v.Name})
				end, Legit.Enabled and 8 or 15, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		hatter = function()
			local thread = task.spawn(function()
				local notifApp = lplr.PlayerGui:WaitForChild('NotificationApp', 10)
				if not notifApp then return end
				local conn = notifApp.DescendantAdded:Connect(function(desc)
					if not AutoKit.Enabled then return end
					if desc:IsA("TextLabel") then
						local txt = string.lower(desc.Text)
						if string.find(txt, "teleport") then
							task.spawn(function()
								for _ = 1, 10 do
									if not AutoKit.Enabled then break end
									if bedwars.AbilityController:canUseAbility('HATTER_TELEPORT') then
										bedwars.AbilityController:useAbility('HATTER_TELEPORT')
										break
									end
									task.wait(0.05)
								end
							end)
						end
					end
				end)
				AutoKit:Clean(conn)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		gingerbread_man = function()
			local old = bedwars.LaunchPadController.attemptLaunch
			bedwars.LaunchPadController.attemptLaunch = function(...)
				local res = {old(...)}
				local self, block = ...

				if (workspace:GetServerTimeNow() - self.lastLaunch) < 0.4 then
					if block:GetAttribute('PlacedByUserId') == lplr.UserId and (block.Position - entitylib.character.RootPart.Position).Magnitude < 30 then
						if not Legit.Enabled or isHoldingPickaxe() then
							task.spawn(bedwars.breakBlock, block, false, nil, true)
							task.spawn(bedwars.breakBlock, block, false, nil, true)
						end
					end
				end

				return unpack(res)
			end

			AutoKit:Clean(function()
				bedwars.LaunchPadController.attemptLaunch = old
			end)
		end,
		wizard = function()
			math.randomseed(os.clock() * 1e6)
			local roll = math.random(0, 100)
			local thread = task.spawn(function()
				repeat
					local ability = lplr:GetAttribute("WizardAbility")
					if not ability then
						task.wait(0.85)
						continue
					end

					local plr = entitylib.EntityPosition({
						Range = Legit.Enabled and 32 or 50,
						Part = "RootPart",
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled,
						Wallcheck = Targets.Walls.Enabled,
						Sort = sortmethods[Sorts.Value]
					})

					if not plr or not store.hand.tool then
						task.wait(0.85)
						continue
					end

					local itemType = store.hand.tooltype
					local targetPos = plr.RootPart.Position

					if bedwars.AbilityController:canUseAbility(ability) then
						bedwars.AbilityController:useAbility(ability, newproxy(true), {target = targetPos})
					end

					if itemType == "wizard_staff_2" or itemType == "wizard_staff_3" then
						local plr2 = entitylib.EntityPosition({
							Range = Legit.Enabled and 13 or 20,
							Part = "RootPart",
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled,
							Sort = sortmethods[Sorts.Value]
						})
						if plr2 then
							local targetPos2 = plr2.RootPart.Position
							if roll <= 50 then
								if bedwars.AbilityController:canUseAbility("SHOCKWAVE") then
									bedwars.AbilityController:useAbility("SHOCKWAVE", newproxy(true), {target = Vector3.zero})
									roll = math.random(0, 100)
								end
							else
								if bedwars.AbilityController:canUseAbility(ability) then
									bedwars.AbilityController:useAbility(ability, newproxy(true), {target = targetPos2})
									roll = math.random(0, 100)
								end
							end
						end
					end

					if itemType == "wizard_staff_3" then
						local plr3 = entitylib.EntityPosition({
							Range = Legit.Enabled and 12 or 18,
							Part = "RootPart",
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled,
							Sort = sortmethods[Sorts.Value]
						})
						if plr3 then
							local targetPos3 = plr3.RootPart.Position
							if roll <= 40 then
								if bedwars.AbilityController:canUseAbility(ability) then
									bedwars.AbilityController:useAbility(ability, newproxy(true), {target = targetPos3})
									roll = math.random(0, 100)
								end
							elseif roll <= 70 then
								if bedwars.AbilityController:canUseAbility("SHOCKWAVE") then
									bedwars.AbilityController:useAbility("SHOCKWAVE", newproxy(true), {target = Vector3.zero})
									roll = math.random(0, 100)
								end
							else
								if bedwars.AbilityController:canUseAbility("LIGHTNING_STORM") then
									bedwars.AbilityController:useAbility("LIGHTNING_STORM", newproxy(true), {target = targetPos3})
									roll = math.random(0, 100)
								end
							end
						end
					end

					task.wait(0.85)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		necromancer = function()
			local r = Legit.Enabled and 8 or 12
			local thread = task.spawn(function()
				kitCollection('Gravestone', function(v)
					local armorType              = v:GetAttribute('ArmorType')
					local weaponType             = v:GetAttribute('SwordType')
					local associatedPlayerUserId = v:GetAttribute('GravestonePlayerUserId')
					local secret                 = v:GetAttribute('GravestoneSecret')
					local position               = v:GetAttribute('GravestonePosition')

					local ok, result = pcall(function()
						return bedwars.Client:Get(remotes.ActivateGravestone).instance:InvokeServer({
							skeletonData = {
								armorType              = armorType,
								weaponType             = weaponType,
								associatedPlayerUserId = associatedPlayerUserId
							},
							secret   = secret,
							position = position
						})
					end)

					if ok and result and result.success then
						local NecroController = bedwars.Knit.Controllers.NecromancerController
						if NecroController then
							pcall(function()
								NecroController:useGravestone(lplr, v)
							end)
						end
					end
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		midnight = function()
			local lastSwing = 0
			AutoKit:Clean(runService.Heartbeat:Connect(function()
				if not entitylib.isAlive then return end
				if not bedwars.AbilityController:canUseAbility('midnight') then return end
				local sc = bedwars.SwordController
				if not sc or not sc.lastAttack then return end
				if sc.lastAttack == lastSwing then return end
				lastSwing = sc.lastAttack
				local plr = entitylib.EntityPosition({
					Range = Legit.Enabled and 6 or 20,
					Part = 'RootPart',
					Players = Targets.Players.Enabled,
					NPCs = Targets.NPCs.Enabled,
					Wallcheck = Targets.Walls.Enabled,
					Sort = sortmethods[Sorts.Value]
				})
				if plr or not Legit.Enabled then
					bedwars.AbilityController:useAbility('midnight')
				end
			end))
		end,
		fisherman = function()
			local thread = task.spawn(function()
				while not (bedwars and bedwars.FishingMinigameController and bedwars.FishingMinigameController.startMinigame) do
					task.wait(0.5)
				end
				local myHook
				local old = bedwars.FishingMinigameController.startMinigame
				myHook = function(self, dropData, result)
					if Legit.Enabled then
						task.spawn(function()
							local ok, track = pcall(function()
								return bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.FISHING_ROD_PULLING)
							end)
							task.wait(3.5)
							if ok and track then pcall(function() track:Stop() end) end
							pcall(function() result({win = true}) end)
						end)
					else
						pcall(function() result({win = true}) end)
					end
				end
				bedwars.FishingMinigameController.startMinigame = myHook
				AutoKit:Clean(function()
					if bedwars and bedwars.FishingMinigameController then
						if bedwars.FishingMinigameController.startMinigame == myHook then
							bedwars.FishingMinigameController.startMinigame = old
						end
					end
				end)
			end)
			AutoKit:Clean(function()ameController.startMinigame = old
			end)
		end,
		davey = function()
			local old = bedwars.CannonHandController.launchSelf
			bedwars.CannonHandController.launchSelf = function(...)
				local res = {old(...)}
				local self, block = ...
	
				if block:GetAttribute('PlacedByUserId') == lplr.UserId and (block.Position - entitylib.character.RootPart.Position).Magnitude < 30 then
					if not Legit.Enabled or isHoldingPickaxe() then
						task.spawn(bedwars.breakBlock, block, false, nil, true)
					end
				end
	
				return unpack(res)
			end
	
			AutoKit:Clean(function()
				bedwars.CannonHandController.launchSelf = old
			end)
		end,
		alchemist = function()
			local r = Legit.Enabled and 8 or 16
			local thread = task.spawn(function()
				 kitCollection('alchemist_ingedients', function(v)
					bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH)
					bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
					bedwars.Client:Get(remotes.CollectCollectableEntity):SendToServer({id = v:GetAttribute("Id"), collectableName = v.Name})
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		defender = function()
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then task.wait(0.1); continue end

					local hasScanner = false
					if Legit.Enabled then
						local handItem = lplr.Character:FindFirstChild('HandInvItem')
						hasScanner = handItem and handItem.Value and handItem.Value.Name:find('defense_scanner')
						if not hasScanner then task.wait(0.1); continue end
					end

					local DefenderController = bedwars.Knit.Controllers.DefenderKitController
					if not DefenderController then task.wait(0.1); continue end

					for blockPos, _ in DefenderController.currentSchematic do
						if not AutoKit.Enabled then break end
						if not entitylib.isAlive then break end

						if Legit.Enabled then
							local handItem = lplr.Character:FindFirstChild('HandInvItem')
							local stillHasScanner = handItem and handItem.Value and handItem.Value.Name:find('defense_scanner')
							if not stillHasScanner then break end
						end

						pcall(function()
							local activeMode = bedwars.Store:getState().Kit.defenderScannerMode
							local blockType = DefenderController.currentSchematic[blockPos]
							if activeMode == 'upgrade' then
								DefenderController:requestScannerAction(blockPos, 'upgrade', blockType)
							elseif activeMode == 'refund' then
								DefenderController:requestScannerAction(blockPos, 'refund')
							else
								DefenderController:requestPlaceDefenderBlock(blockPos)
							end
						end)

						task.wait(Legit.Enabled and 0.3 or 0.05)
					end

					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		block_kicker = function()
			local player = game.Players.LocalPlayer
			local thread = task.spawn(function()
				repeat
					if entitylib.isAlive and bedwars.AbilityController then
						local character = player.Character
						local blockCount = 0
						if character then
							blockCount = character:GetAttribute('BlockKickerKit_BlockCount') or player:GetAttribute('BlockKickerKit_BlockCount') or 0
						else
							blockCount = player:GetAttribute('BlockKickerKit_BlockCount') or 0
						end
						if blockCount <= 2 and bedwars.AbilityController:canUseAbility('BLOCK_STOMP') then
							bedwars.AbilityController:useAbility('BLOCK_STOMP')
							task.wait(0.8)
						end
					end
					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		dragon_slayer = function()
			local thread = task.spawn(function()
				kitCollection('KaliyahPunchInteraction', function(v)
					local character = playersService.LocalPlayer.Character
					if not character or not character.PrimaryPart then return end

					bedwars.DragonSlayerController:deleteEmblem(v)

					local playerPos = character:GetPrimaryPartCFrame().Position
					local targetPos = v:GetPrimaryPartCFrame().Position * Vector3.new(1, 0, 1) + Vector3.new(0, playerPos.Y, 0)
					local lookAtCFrame = CFrame.new(playerPos, targetPos)

					character:PivotTo(lookAtCFrame)
					bedwars.DragonSlayerController:playPunchAnimation(lookAtCFrame - lookAtCFrame.Position)
					bedwars.Client:Get(remotes.RequestDragonPunch):SendToServer({target = v})
				end, 18, true)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		drill = function()
			local userId = lplr.UserId
			local thread = task.spawn(function()
				repeat
					if entitylib.isAlive then
						local drills = collectionService:GetTagged("Drill")
						for _, drill in ipairs(drills) do
							if drill:GetAttribute("PlacedByUserId") == userId then
								pcall(function()
									bedwars.Client:Get(remotes.ExtractFromDrill).instance:FireServer({ drill = drill })
								end)
							end
						end
					end
					task.wait(0.5)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		hannah = function()
			local range = Legit.Enabled and 12 or 30
			local thread = task.spawn(function()
				kitCollection('HannahExecuteInteraction', function(victim)
					local success = bedwars.Client:Get(remotes.HannahPromptTrigger).instance:InvokeServer({
						user = lplr,
						victimEntity = victim
					})
					if success then
						local icon = victim:FindFirstChild('Hannah Execution Icon')
						if icon then
							icon:Destroy()
						end
					end
				end, range, true)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		jailor = function()
			local r = Legit.Enabled and 9 or 20
			local thread = task.spawn(function()
				kitCollection('jailor_soul', function(v)
					bedwars.JailorController:collectEntity(lplr, v, 'JailorSoul')
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		grim_reaper = function()
			local r = Legit.Enabled and 35 or 120
			local thread = task.spawn(function()
				kitCollection(bedwars.GrimReaperController.soulsByPosition, function(v)
					if entitylib.isAlive and lplr.Character:GetAttribute('Health') <= (lplr.Character:GetAttribute('MaxHealth') / 4) and (not lplr.Character:GetAttribute('GrimReaperChannel')) then
						bedwars.Client:Get(remotes.ConsumeSoul):CallServer({secret = v:GetAttribute('GrimReaperSoulSecret')})
					end
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		farmer_cletus = function(sets)
			local r = Legit.Enabled and 6 or 10
			local thread = task.spawn(function()
				kitCollection('HarvestableCrop', function(v)
					bedwars.Client:Get(remotes.Harvest):CallServer({position = bedwars.BlockController:getBlockPosition(v.Position)})
					bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH)
					bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
					bedwars.SoundManager:playSound(bedwars.SoundList.CROP_HARVEST)
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		taliyah = function(sets)
			local r = Legit.Enabled and 6 or 8
			local thread = task.spawn(function()
				kitCollection('HarvestableCrop', function(v)
					if v:FindFirstChild('carrot') or v:FindFirstChild('melon') or v:FindFirstChild('pumpkin') then return end
					bedwars.Client:Get(remotes.Harvest):CallServer({position = bedwars.BlockController:getBlockPosition(v.Position)})
					bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH)
					bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
					bedwars.SoundManager:playSound(bedwars.SoundList[currentsound] or bedwars.SoundList['CHICKEN_ATTACK_1'])
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		melody = function()
			local thread = task.spawn(function()
				repeat
					local mag, hp, ent = 30, math.huge
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position
						for _, v in entitylib.List do
							if v.Player and v.Player:GetAttribute('Team') == lplr:GetAttribute('Team') then
								local newmag = (localPosition - v.RootPart.Position).Magnitude
								if newmag <= mag and v.Health < hp and v.Health < v.MaxHealth then
									mag, hp, ent = newmag, v.Health, v
								end
							end
						end
					end

					if ent and getItem('guitar') then
						bedwars.Client:Get(remotes.GuitarHeal):SendToServer({healTarget = ent.Character})
					end

					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		mimic = function()
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then
						task.wait(0.1)
						continue
					end

					local localPosition = entitylib.character.RootPart.Position
					for _, v in entitylib.List do
						if v.Targetable and v.Character and v.Player then
							local distance = (v.RootPart.Position - localPosition).Magnitude
							if distance <= (Legit.Enabled and 12 or 30) then
								if collectionService:HasTag(v.Character, "MimicBLockPickPocketPlayer") then
									pcall(function()
										bedwars.Client:Get(remotes.MimicBlockPickPocketPlayer).instance:InvokeServer(v.Player)
									end)
									task.wait(0.5)
								end
							end
						end
					end

					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		pinata = function()
			local r = Legit.Enabled and 8 or 18
			local thread = task.spawn(function()
				kitCollection(lplr.Name..':pinata', function(v)
					if getItem('candy') then
						bedwars.Client:Get(remotes.DepositCoins):CallServer(v)
					end
				end, r, true)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		spirit_assassin = function()
			local r = Legit.Enabled and 35 or 120
			local thread = task.spawn(function()
				kitCollection('EvelynnSoul', function(v)
					bedwars.SpiritAssassinController:useSpirit(lplr, v)
				end, r, true)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		void_knight = function()
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then
						task.wait(0.1)
						continue
					end

					local currentTier = lplr:GetAttribute('VoidKnightTier') or 0
					local haltedProgress = lplr:GetAttribute('VoidKnightHaltedProgress')

					if haltedProgress then
						task.wait(0.5)
						continue
					end

					if currentTier < 4 then
						if currentTier < 3 then
							local ironAmount = getItem('iron')
							ironAmount = ironAmount and ironAmount.amount or 0
							if ironAmount >= 10 and bedwars.AbilityController:canUseAbility('void_knight_consume_iron') then
								bedwars.AbilityController:useAbility('void_knight_consume_iron')
								task.wait(0.5)
							end
						end

						if currentTier >= 2 and currentTier < 4 then
							local emeraldAmount = getItem('emerald')
							emeraldAmount = emeraldAmount and emeraldAmount.amount or 0
							if emeraldAmount >= 1 and bedwars.AbilityController:canUseAbility('void_knight_consume_emerald') then
								bedwars.AbilityController:useAbility('void_knight_consume_emerald')
								task.wait(0.5)
							end
						end
					end

					if currentTier >= 4 and bedwars.AbilityController:canUseAbility('void_knight_ascend') then
						local shouldAscend = false

						local health = lplr.Character:GetAttribute('Health') or 100
						local maxHealth = lplr.Character:GetAttribute('MaxHealth') or 100
						if health < (maxHealth * 0.5) then shouldAscend = true end

						if not shouldAscend then
							local plr = entitylib.EntityPosition({
								Range = Legit.Enabled and 30 or 50,
								Part = 'RootPart',
								Players = Targets.Players.Enabled,
								NPCs = Targets.NPCs.Enabled,
								Wallcheck = Targets.Walls.Enabled,
								Sort = sortmethods[Sorts.Value]
							})
							if plr then shouldAscend = true end
						end

						if shouldAscend then
							bedwars.AbilityController:useAbility('void_knight_ascend')
							task.wait(16)
						end
					end

					task.wait(0.5)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		void_dragon = function()
			local player = lplr

			local oldFlap = bedwars.VoidDragonController.flapWings
			bedwars.VoidDragonController.flapWings = function(self, ...)
				local result = oldFlap(self, ...)
				if result ~= false and self.inDragonForm then
					local modifier = bedwars.SprintController:getMovementStatusModifier():addModifier({
						blockSprint = true,
						constantSpeedMultiplier = 2
					})
					self.SpeedMaid:GiveTask(modifier)
				end
				return result
			end

			AutoKit:Clean(function()
				bedwars.VoidDragonController.flapWings = oldFlap
			end)

			local thread = task.spawn(function()
				repeat
					if entitylib.isAlive and bedwars.VoidDragonController and bedwars.VoidDragonController.inDragonForm then
						local target = entitylib.EntityPosition({
							Range = 30,
							Part = 'RootPart',
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled,
							Sort = sortmethods[Sorts.Value]
						})

						if target and target.RootPart then
							local shouldFire = true
							if Legit.Enabled then
								local myPos = entitylib.character.RootPart.Position
								local myForward = entitylib.character.RootPart.CFrame.LookVector
								local toTarget = (target.RootPart.Position - myPos).Unit
								local dot = myForward:Dot(toTarget)
								local angle = math.acos(dot) * (180 / math.pi) 

								if angle > 90 then
									shouldFire = false
								end
							end

							if shouldFire then
								replicatedStorage:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("net"):WaitForChild("out"):WaitForChild("_NetManaged"):WaitForChild("DragonBreath"):FireServer({
									player = player
								})
								task.wait(1) 
							end
						end
					end
					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		cactus = function()
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then
						task.wait(0.1)
						continue
					end

					if bedwars.AbilityController:canUseAbility('cactus_fire') then
						local plr = entitylib.EntityPosition({
							Range = Legit.Enabled and 8 or 18,
							Part = 'RootPart',
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled,
							Sort = sortmethods[Sorts.Value]
						})

						if plr then
							bedwars.AbilityController:useAbility('cactus_fire')
							task.wait(0.5)
						end
					end

					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		card = function()
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then
						task.wait(0.1)
						continue
					end

					if bedwars.AbilityController:canUseAbility('CARD_THROW') then
						local plr = entitylib.EntityPosition({
							Range = Legit.Enabled and 30 or 60,
							Part = 'RootPart',
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled,
							Sort = sortmethods[Sorts.Value]
						})

						if plr then
							bedwars.AbilityController:useAbility('CARD_THROW')
							task.wait(0.1)
							pcall(function()
								bedwars.Client:Get(remotes.AttemptCardThrow).instance:FireServer({targetEntityInstance = plr.Character})
							end)
							task.wait(0.5)
						end
					end

					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		beekeeper = function()
			local r = Legit.Enabled and 8 or 30
			local thread = task.spawn(function()
				kitCollection('bee', function(v)
					if Legit.Enabled and not isHoldingItem({'beekeeper_net'}) then return end
					bedwars.Client:Get(remotes.BeePickup):SendToServer({beeId = v:GetAttribute('BeeId')})
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		summoner = function()
			local lastAttackTime = 0
			local attackCooldown = 0.52

			local function getPlayerClawLevel()
				local handItem = lplr.Character and lplr.Character:FindFirstChild('HandInvItem')
				if handItem and handItem.Value then
					local itemType = handItem.Value.Name
					if itemType == 'summoner_claw_1' then return 1 end
					if itemType == 'summoner_claw_2' then return 2 end
					if itemType == 'summoner_claw_3' then return 3 end
					if itemType == 'summoner_claw_4' then return 4 end
				end

				if store and store.inventory and store.inventory.hotbar then
					for _, v in pairs(store.inventory.hotbar) do
						if v.item then
							local itemType = v.item.itemType
							if itemType == 'summoner_claw_1' then return 1 end
							if itemType == 'summoner_claw_2' then return 2 end
							if itemType == 'summoner_claw_3' then return 3 end
							if itemType == 'summoner_claw_4' then return 4 end
						end
					end
				end
				return 1 
			end

			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then
						task.wait(0.1)
						continue
					end

					local isCasting = false
					if Legit.Enabled then
						if lplr.Character:GetAttribute("Casting") or
						lplr.Character:GetAttribute("UsingAbility") or
						lplr.Character:GetAttribute("SummonerCasting") then
							isCasting = true
						end

						local humanoid = lplr.Character:FindFirstChildOfClass("Humanoid")
						if humanoid and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
							isCasting = true
						end
					end

					if Legit.Enabled and isCasting then task.wait(0.1); continue end
					if (workspace:GetServerTimeNow() - lastAttackTime) < attackCooldown then task.wait(0.1); continue end

					local handItem = lplr.Character:FindFirstChild('HandInvItem')
					local hasClaw = handItem and handItem.Value and handItem.Value.Name:find('summoner_claw')
					if not hasClaw then task.wait(0.1); continue end

					local plr = entitylib.EntityPosition({
						Range = Legit.Enabled and 23 or 35,
						Part = 'RootPart',
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled,
						Wallcheck = Targets.Walls.Enabled,
						Sort = sortmethods[Sorts.Value]
					})

					if plr and Legit.Enabled and (entitylib.character.RootPart.Position - plr.RootPart.Position).Magnitude > 23 then
						plr = nil
					end

					if plr and (not Legit.Enabled or (lplr.Character:GetAttribute('Health') or 0) > 0) then
						local localPosition = entitylib.character.RootPart.Position
						local targetPos = plr.RootPart.Position
						local targetVel = plr.RootPart.AssemblyLinearVelocity
						local dist = (localPosition - targetPos).Magnitude
						local travelTime = dist / 80
						local predictedPos = targetPos + targetVel * travelTime
						local shootDir = CFrame.lookAt(localPosition, predictedPos).LookVector
						localPosition += shootDir * math.max((localPosition - predictedPos).Magnitude - 16, 0)

						lastAttackTime = workspace:GetServerTimeNow()

						pcall(function()
							bedwars.AnimationUtil:playAnimation(lplr, bedwars.GameAnimationUtil:getAssetId(bedwars.AnimationType.SUMMONER_CHARACTER_SWIPE), {looped = false})
						end)

						task.spawn(function()
							pcall(function()
								local clawModel = replicatedStorage.Assets.Misc.Kaida.Summoner_DragonClaw:Clone()
								clawModel.Parent = workspace

								local clawLevel = getPlayerClawLevel()
								local clawColors = {
									Color3.fromRGB(75, 75, 75),    
									Color3.fromRGB(255, 255, 255),  
									Color3.fromRGB(43, 229, 229),   
									Color3.fromRGB(49, 229, 94)     
								}
								local nailMesh = clawModel:FindFirstChild("dragon_claw_nail_mesh")
								if nailMesh and nailMesh:IsA("MeshPart") then
									nailMesh.Color = clawColors[clawLevel] or clawColors[1]
								end

								if bedwars.KnightClient and bedwars.KnightClient.Controllers.SummonerKitSkinController then
									if bedwars.KnightClient.Controllers.SummonerKitSkinController:isPrismaticSkin(lplr) then
										bedwars.KnightClient.Controllers.SummonerKitSkinController:applyClawRGB(clawModel)
									end
								end

								if gameCamera.CFrame.Position and (gameCamera.CFrame.Position - entitylib.character.RootPart.Position).Magnitude < 1 then
									for _, part in clawModel:GetDescendants() do
										if part:IsA('MeshPart') then
											part.Transparency = 0.6
										end
									end
								end

								local rootPart = entitylib.character.RootPart
								local Unit = Vector3.new(shootDir.X, 0, shootDir.Z).Unit
								local startPos = rootPart.Position + Unit:Cross(Vector3.new(0, 1, 0)).Unit * -1 * 5 + Unit * 6
								local direction = (startPos + shootDir * 13 - startPos).Unit
								local cframe = CFrame.new(startPos, startPos + direction)
								clawModel:PivotTo(cframe)
								clawModel.PrimaryPart.Anchored = true
								local portalConn
								if clawModel:FindFirstChild("Portal1") then
									portalConn = game:GetService("RunService").Heartbeat:Connect(function()
										local foreArmCF = clawModel.RootPart.root.fore_arm.TransformedWorldCFrame
										if clawModel.Portal1 then
											clawModel.Portal1:PivotTo(foreArmCF)
										end
										if clawModel.Portal2 then
											clawModel.Portal2:PivotTo(foreArmCF * CFrame.Angles(math.pi, 0, 0))
										end
									end)
								end


								if clawModel:FindFirstChild('AnimationController') then
									local animator = clawModel.AnimationController:FindFirstChildOfClass('Animator')
									if animator then
										bedwars.AnimationUtil:playAnimation(animator, bedwars.GameAnimationUtil:getAssetId(bedwars.AnimationType.SUMMONER_CLAW_ATTACK), {looped = false, speed = 1})
									end
								end

								pcall(function()
									local sounds = {
										bedwars.SoundList.SUMMONER_CLAW_ATTACK_1,
										bedwars.SoundList.SUMMONER_CLAW_ATTACK_2,
										bedwars.SoundList.SUMMONER_CLAW_ATTACK_3,
										bedwars.SoundList.SUMMONER_CLAW_ATTACK_4
									}
									bedwars.SoundManager:playSound(sounds[math.random(1, #sounds)], {position = rootPart.Position})
								end)

								task.wait(0.5)
								if portalConn then portalConn:Disconnect() end
								clawModel:Destroy()
							end)
						end)

						bedwars.Client:Get(remotes.SummonerClawAttack):SendToServer({
							position = localPosition,
							direction = shootDir,
							clientTime = workspace:GetServerTimeNow()
						})
					end

					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		star_collector = function()
			local r = Legit.Enabled and 10 or 18
			local starCooldowns = {}
			local STAR_COOLDOWN = 0.5
			local thread = task.spawn(function()
				kitCollection('stars', function(v)
					if starCooldowns[v] and tick() - starCooldowns[v] < STAR_COOLDOWN then
						return
					end
					starCooldowns[v] = tick()

					bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.PUNCH)
					bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
					bedwars.StarCollectorController:collectEntity(lplr, v, v.Name)
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		spirit_summoner = function()
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then
						task.wait(0.1)
						continue
					end

					local hasStaff = false
					for _, item in store.inventory.inventory.items do
						if item.itemType == 'spirit_staff' then
							hasStaff = true
							break
						end
					end

					if hasStaff then
						local spiritCount = lplr:GetAttribute('ReadySummonedAttackSpirits') or 0
						if spiritCount < 10 then
							local hasStone = false
							for _, item in store.inventory.inventory.items do
								if item.itemType == 'summon_stone' then
									hasStone = true
									break
								end
							end

							if hasStone and bedwars.AbilityController:canUseAbility('summon_attack_spirit') then
								bedwars.AbilityController:useAbility('summon_attack_spirit')
								task.wait(0.5)
							end
						end
					end

					task.wait(0.2)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		metal_detector = function()
			local r = Legit.Enabled and 8 or 10
			local thread = task.spawn(function()
				kitCollection('hidden-metal', function(v)
					if Legit.Enabled and not isHoldingItem({'metal_detector'}) then return end
					if Legit.Enabled then
						bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.SHOVEL_DIG)
						bedwars.SoundManager:playSound(bedwars.SoundList.SNAP_TRAP_CONSUME_MARK)
					end
					bedwars.Client:Get('CollectCollectableEntity'):SendToServer({id = v:GetAttribute('Id'), collectableName = v.Name})
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		mage = function()
			local r = Legit.Enabled and 8 or 500
			local thread = task.spawn(function()
				kitCollection('ElementTome', function(v)
					local secret = v:GetAttribute('TomeSecret')
					if secret then
						bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.PUNCH)
						bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)

						local result = bedwars.Client:Get(remotes.LearnElementTome).instance:InvokeServer({secret = secret})

						if result and result.success then
							v:Destroy()
							task.wait(0.5)
						end
					end
				end, r, false)
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		 warlock = function()
			local lastTarget = nil
			local range = Legit.Enabled and 12 or 30
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then
						lastTarget = nil
						task.wait(0.1)
						continue
					end

					if store.hand.tool and store.hand.tool.Name == 'warlock_staff' then
						if lastTarget then
							local hum = lastTarget:FindFirstChildOfClass('Humanoid')
							local root = lastTarget:FindFirstChild('HumanoidRootPart')
							local inRange = root and (root.Position - entitylib.character.RootPart.Position).Magnitude <= range
							if not hum or hum.Health <= 0 or not lastTarget.Parent or not inRange then
								lastTarget = nil
							end
						end

						if not lastTarget then
							local plr = entitylib.EntityPosition({
								Range = range,
								Part = 'RootPart',
								Players = Targets.Players.Enabled,
								NPCs = Targets.NPCs.Enabled,
								Wallcheck = Targets.Walls.Enabled
							})
							if plr and plr.Character then
								lastTarget = plr.Character
								bedwars.AbilityController:useAbility("WARLOCK_LINK")
								task.wait(0.1)
								pcall(function()
									bedwars.Client:Get(remotes.WarlockTarget):CallServer({
										target = lastTarget
									})
								end)
							end
						end
					else
						lastTarget = nil
					end

					task.wait(0.3)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
        battery = function()
            repeat
                if entitylib.isAlive then
                    local localPosition = entitylib.character.RootPart.Position
                    for i, v in bedwars.BatteryEffectsController.liveBatteries do
                        if (v.position - localPosition).Magnitude <= 10 then
                            local BatteryInfo = bedwars.BatteryEffectsController:getBatteryInfo(i)
                            if not BatteryInfo or BatteryInfo.activateTime >= workspace:GetServerTimeNow() or BatteryInfo.consumeTime + 0.1 >= workspace:GetServerTimeNow() then continue end
                            BatteryInfo.consumeTime = workspace:GetServerTimeNow()
                            bedwars.Client:Get(remotes.ConsumeBattery):SendToServer({batteryId = i})
                        end
                    end
                end
                task.wait(0.1)
            until not AutoKit.Enabled
        end,
        cat = function()
            local old = bedwars.CatController.leap
            bedwars.CatController.leap = function(...)
                vapeEvents.CatPounce:Fire()
                return old(...)
            end
    
            AutoKit:Clean(function()
                bedwars.CatController.leap = old
            end)
        end,
		soul_broker = function()
			local soulLinkRemote = replicatedStorage:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("net"):WaitForChild("out"):WaitForChild("_NetManaged"):WaitForChild("AttemptSoulLink")
			local useAbilityRemote = replicatedStorage:WaitForChild("events-@easy-games/game-core:shared/game-core-networking@getEvents.Events"):WaitForChild("useAbility")
			local linkedTargets = {}
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then task.wait(0.1); continue end

					local plr = entitylib.EntityPosition({
						Range = 50,
						Part = "RootPart",
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled,
						Wallcheck = Targets.Walls.Enabled
					})

					local linkCount = 0
					for _ in linkedTargets do linkCount += 1 end

					if plr and plr.Character and linkCount < 8 then
						local char = plr.Character
						if not linkedTargets[char] then
							useAbilityRemote:FireServer("soul_link")
							task.wait(0.1)
							local ok, result = pcall(function()
								return soulLinkRemote:InvokeServer(char)
							end)
							if ok and result and result.result then
								linkedTargets[char] = true
								char.AncestryChanged:Connect(function()
									if not char.Parent then
										linkedTargets[char] = nil
									end
								end)
							end
						end
					end

					task.wait(0.3)
				until not AutoKit.Enabled
				linkedTargets = {}
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		warrior = function()
			local useAbilityRemote = replicatedStorage:WaitForChild("events-@easy-games/game-core:shared/game-core-networking@getEvents.Events"):WaitForChild("useAbility")
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then task.wait(0.1); continue end

					local plr = entitylib.EntityPosition({
						Range = Legit.Enabled and 8 or 20,
						Part = 'RootPart',
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled,
						Wallcheck = Targets.Walls.Enabled,
						Sort = sortmethods[Sorts.Value]
					})

					local grit = lplr:GetAttribute('Grit') or 0
					if plr and grit >= 100 then
						pcall(function() useAbilityRemote:FireServer('warrior_strike') end)
					end

					task.wait(Legit.Enabled and 0.6 or 0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
		gun_blade = function()
			local handGunRemote = game:GetService('ReplicatedStorage')
				:WaitForChild('rbxts_include'):WaitForChild('node_modules')
				:WaitForChild('@rbxts'):WaitForChild('net'):WaitForChild('out')
				:WaitForChild('_NetManaged'):WaitForChild('HandGunFireRequest')
			local thread = task.spawn(function()
				repeat
					if not entitylib.isAlive then task.wait(0.1); continue end
					local plr = entitylib.EntityPosition({
						Range = Legit.Enabled and 8 or 10,
						Part = 'RootPart',
						Players = Targets.Players.Enabled,
						NPCs = Targets.NPCs.Enabled,
						Wallcheck = Targets.Walls.Enabled,
						Sort = sortmethods[Sorts.Value]
					})
					if plr and plr.RootPart then
						local dir = (plr.RootPart.Position - entitylib.character.RootPart.Position).Unit
						local args = { { lookVector = dir } }
						handGunRemote:InvokeServer(unpack(args))
						task.wait(0.5)
					end
					task.wait(0.1)
				until not AutoKit.Enabled
			end)
			AutoKit:Clean(function() task.cancel(thread) end)
		end,
	}

	local sortTable = {}
	for i in AutoKitFunctions do
		table.insert(sortTable, i)
	end
	table.sort(sortTable, function(a, b)
		return bedwars.BedwarsKitMeta[a].name < bedwars.BedwarsKitMeta[b].name
	end)
	for _, v in sortTable do
		Toggles[v] = AutoKit:CreateToggle({
			Name = bedwars.BedwarsKitMeta[v].name,
			Default = true
		})
	end
end)

run(function()
	local CannonHandController = bedwars.CannonHandController
	local CannonController = bedwars.CannonController
	local oldLaunchSelf = CannonHandController.launchSelf
	local oldStopAiming = CannonController.stopAiming
	local oldStartAiming = CannonController.startAiming
	local AutoDavey
	local AutoDaveyAutojump
	local AutoDaveyAutoLaunch
	local AutoDaveyAutoBreak
	local AutoDaveyPickaxeCheck
	local AutoDaveyAutoSwitch
	local LaunchDelay
	local BreakDelay
	local isLaunching = false
	local didAutoLaunch = false

	local function getCannonSlot()
		for i, v in pairs(store.inventory.hotbar) do
			if v.item then
				local t = tostring(v.item.itemType):lower()
				if t:find("cannon") then
					return i - 1
				end
			end
		end
		return nil
	end

	local function hasWoodPickaxeOnly()
		local bestTier = 0
		for _, slot in pairs(store.inventory.hotbar) do
			if slot.item then
				local t = tostring(slot.item.itemType):lower()
				if t == "wood_pickaxe" and bestTier < 1 then
					bestTier = 1
				elseif (t:find("pickaxe") or t:find("drill")) and t ~= "wood_pickaxe" then
					bestTier = 2
				end
			end
		end
		return bestTier == 1
	end

	local function getNearestCannon()
		if not entitylib.isAlive then return nil end
		local nearest
		local nearestDist = math.huge
		for i, v in pairs(CannonController.getCannons()) do
			pcall(function()
				local dist = (v.Position - entitylib.character.RootPart.Position).Magnitude
				if dist < nearestDist and dist < 30 then
					nearestDist = dist
					nearest = v
				end
			end)
		end
		return nearest
	end

	local function findCannonModel(pos)
		local closest = nil
		local closestDist = 8
		for _, obj in store.blocks do
			if obj and obj:IsA("BasePart") and obj.Name == "cannon" then
				local dist = (obj.Position - pos).Magnitude
				if dist < closestDist then
					closestDist = dist
					closest = obj
				end
			end
		end
		return closest
	end

	local function doBreakCannon(cannon)
		if not entitylib.isAlive then return end
		if not cannon or not cannon.Parent then return end
		local block, blockpos = getPlacedBlock(cannon.Position)
		if block and block.Name == 'cannon' and
		   (entitylib.character.RootPart.Position - block.Position).Magnitude < 30 then
			pcall(bedwars.breakBlock, block, false, nil, true)
		else
			local directBlock = findCannonModel(cannon.Position)
			if directBlock and directBlock.Parent then
				pcall(bedwars.breakBlock, directBlock, false, nil, true)
			end
		end
	end

	local function firstHitCannon(cannon)
		if not entitylib.isAlive then return end
		if not cannon or not cannon.Parent then return end
		if hasWoodPickaxeOnly() then
			doBreakCannon(cannon)
		end
	end

	local function breakCannon(cannon, shootfunc)
		if not entitylib.isAlive then
			isLaunching = false
			return shootfunc()
		end

		local cannonSlot = nil

		if AutoDaveyAutoSwitch.Enabled and not isHoldingPickaxe() then
			local pickaxeSlot = getPickaxeSlot()
			if not pickaxeSlot then
				notif("AutoDavey", "No pickaxe found in hotbar!", 3)
				if AutoDaveyAutojump.Enabled and entitylib.isAlive and entitylib.character.Humanoid then
					entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				end
				isLaunching = false
				return shootfunc()
			end
			cannonSlot = getCannonSlot()
			if hotbarSwitch(pickaxeSlot) then
				task.wait(0.05)
			end
		end

		if AutoDaveyPickaxeCheck.Enabled and not isHoldingPickaxe() then
			notif("AutoDavey", "You need to HOLD a pickaxe to break cannons!", 3)
			if AutoDaveyAutojump.Enabled and entitylib.isAlive and entitylib.character.Humanoid then
				entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
			isLaunching = false
			return shootfunc()
		end

		if BreakDelay.Value > 0 then
			task.wait(BreakDelay.Value)
		end

		local cannonRef = cannon
		if AutoDaveyAutojump.Enabled and entitylib.isAlive and entitylib.character.Humanoid then
			entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		shootfunc()
		isLaunching = false

		task.spawn(function()
			task.wait(0.05)
			doBreakCannon(cannonRef)
			task.wait(0.35)
			if cannonRef and cannonRef.Parent then
				doBreakCannon(cannonRef)
			end
			if AutoDaveyAutoSwitch.Enabled and cannonSlot then
				task.wait(0.05)
				hotbarSwitch(cannonSlot)
			end
		end)
	end

	AutoDavey = vape.Categories.Kits:CreateModule({
		Name = 'AutoDavey',
		Function = function(callback)
			if callback then
				CannonHandController.launchSelf = function(...)
					if isLaunching then
						isLaunching = false
						return oldLaunchSelf(...)
					end
					isLaunching = true
					if LaunchDelay.Value > 0 then
						task.wait(LaunchDelay.Value)
					end
					if AutoDaveyAutoBreak.Enabled then
						local cannon = getNearestCannon()
						if cannon then
							local args = {...}
							breakCannon(cannon, function()
								oldLaunchSelf(unpack(args))
							end)
							return
						else
							if AutoDaveyAutojump.Enabled and entitylib.isAlive and entitylib.character.Humanoid then
								entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
							end
							local res = oldLaunchSelf(...)
							isLaunching = false
							return res
						end
					else
						if AutoDaveyAutojump.Enabled and entitylib.isAlive and entitylib.character.Humanoid then
							entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
						end
						local res = oldLaunchSelf(...)
						isLaunching = false
						return res
					end
				end

				local aimedCannon = nil
				CannonController.startAiming = function(...)
					didAutoLaunch = false
					isLaunching = false
					local result = oldStartAiming(...)
					aimedCannon = getNearestCannon()
					return result
				end

				CannonController.stopAiming = function(...)
					local cannon = aimedCannon or getNearestCannon()
					local result = oldStopAiming(...)
					aimedCannon = nil
					isLaunching = false
					if AutoDaveyAutoLaunch.Enabled and not didAutoLaunch then
						didAutoLaunch = true
						if AutoDaveyAutoBreak.Enabled and AutoDaveyPickaxeCheck.Enabled and not isHoldingPickaxe() and not AutoDaveyAutoSwitch.Enabled then
							notif("AutoDavey", "Hold a pickaxe to auto-break!", 3)
							return result
						end
						if cannon then
							task.spawn(function()
								pcall(CannonHandController.launchSelf, CannonHandController, cannon)
							end)
						end
					end
					return result
				end

				local firstHitDebounce = {}
				AutoDavey:Clean(workspace.DescendantAdded:Connect(function(obj)
					if not (obj:IsA("BasePart") and obj.Name == "cannon") then return end
					if firstHitDebounce[obj] then return end
					firstHitDebounce[obj] = true
					task.spawn(function()
						task.wait(0.5)
						if AutoDaveyAutoBreak.Enabled and hasWoodPickaxeOnly() then
							local dist = entitylib.isAlive
								and (entitylib.character.RootPart.Position - obj.Position).Magnitude
								or math.huge
							if dist < 20 and obj.Parent then
								firstHitCannon(obj)
							end
						end
						firstHitDebounce[obj] = nil
					end)
				end))
			else
				CannonHandController.launchSelf = oldLaunchSelf
				CannonController.stopAiming = oldStopAiming
				CannonController.startAiming = oldStartAiming
				isLaunching = false
				didAutoLaunch = false
			end
		end,
	})

	LaunchDelay = AutoDavey:CreateSlider({
		Name = 'Launch Delay',
		Min = 0,
		Max = 2,
		Default = 0,
		Decimal = 10,
		Suffix = 's',
	})
	BreakDelay = AutoDavey:CreateSlider({
		Name = 'Break Delay',
		Min = 0,
		Max = 2,
		Default = 0,
		Decimal = 10,
		Suffix = 's',
	})

	AutoDaveyAutojump = AutoDavey:CreateToggle({
		Name = 'Auto Jump',
		Default = true,
	})
	AutoDaveyAutoLaunch = AutoDavey:CreateToggle({
		Name = 'Auto Launch',
		Default = true,
		Tooltip = 'automatically lauches u after your done aiming'
	})
	AutoDaveyAutoBreak = AutoDavey:CreateToggle({
		Name = 'Auto Break',
		Default = true,
		Tooltip = 'auto breaks cannon when you lauch'
	})
	AutoDaveyPickaxeCheck = AutoDavey:CreateToggle({
		Name = 'Pickaxe Check',
		Default = true,
	})
	AutoDaveyAutoSwitch = AutoDavey:CreateToggle({
		Name = 'AutoSwitch Pickaxe',
		Default = false,
		Tooltip = 'switches to pickaxe when breaking thens switches back to cannon'
	})
end)

run(function()
    local anim
    local asset
    local trackingConnection
    local lastPosition
    local NightmareEmote
    local cachedRootPart
    local cachedHumanoid
    local lastValidationCheck = 0
    
    NightmareEmote = vape.Categories.World:CreateModule({
        Name = "NightmareEmote",
        Function = function(call)
            if call then
                local l__GameQueryUtil__8
                if (not shared.CheatEngineMode) then 
                    l__GameQueryUtil__8 = require(game:GetService("ReplicatedStorage")['rbxts_include']['node_modules']['@easy-games']['game-core'].out).GameQueryUtil 
                else
                    local backup = {}; function backup:setQueryIgnored() end; l__GameQueryUtil__8 = backup;
                end
                local l__TweenService__9 = tweenService
                local player = playersService.LocalPlayer
                local character = player.Character
                
                if not character then 
                    NightmareEmote:Toggle() 
                    return 
                end
                
                local humanoid = character:WaitForChild("Humanoid")
                local rootPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
                
                if not rootPart then 
                    NightmareEmote:Toggle() 
                    return 
                end
                
                cachedRootPart = rootPart
                cachedHumanoid = humanoid
                lastPosition = rootPart.Position
                lastValidationCheck = 0
                
                local v10 = game:GetService("ReplicatedStorage"):WaitForChild("Assets"):WaitForChild("Effects"):WaitForChild("NightmareEmote"):Clone()
                asset = v10
                v10.Parent = game.Workspace
                
                local descendants = v10:GetDescendants()
                for _, part in ipairs(descendants) do
                    if part:IsA("BasePart") then
                        l__GameQueryUtil__8:setQueryIgnored(part, true)
                        part.CanCollide = false
                        part.Anchored = true
                    end
                end
                
                local l__Outer__15 = v10:FindFirstChild("Outer")
                if l__Outer__15 then
                    l__TweenService__9:Create(l__Outer__15, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
                        Orientation = l__Outer__15.Orientation + Vector3.new(0, 360, 0)
                    }):Play()
                end
                
                local l__Middle__16 = v10:FindFirstChild("Middle")
                if l__Middle__16 then
                    l__TweenService__9:Create(l__Middle__16, TweenInfo.new(12.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
                        Orientation = l__Middle__16.Orientation + Vector3.new(0, -360, 0)
                    }):Play()
                end
                
                anim = Instance.new("Animation")
                anim.AnimationId = "rbxassetid://9191822700"
                anim = humanoid:LoadAnimation(anim)
                anim:Play()
                
                local movementThresholdSq = 0.1 * 0.1
                
                trackingConnection = runService.RenderStepped:Connect(function()
                    if not asset or not asset.Parent then 
                        if trackingConnection then
                            trackingConnection:Disconnect()
                        end
                        return 
                    end
                    
                    local currentTime = tick()
                    
                    if (currentTime - lastValidationCheck) > 0.5 then
                        if not character or not character.Parent then
                            asset:Destroy()
                            asset = nil
                            if trackingConnection then
                                trackingConnection:Disconnect()
                            end
                            NightmareEmote:Toggle()
                            return
                        end
                        
                        if not cachedRootPart or not cachedRootPart.Parent then
                            cachedRootPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
                        end
                        
                        if not cachedHumanoid or not cachedHumanoid.Parent then
                            cachedHumanoid = character:FindFirstChildOfClass("Humanoid")
                        end
                        
                        if not cachedRootPart or not cachedHumanoid or cachedHumanoid.Health <= 0 then
                            asset:Destroy()
                            asset = nil
                            if trackingConnection then
                                trackingConnection:Disconnect()
                            end
                            NightmareEmote:Toggle()
                            return
                        end
                        
                        lastValidationCheck = currentTime
                    end
                    
                    if lastPosition and cachedRootPart then
                        local currentPosition = cachedRootPart.Position
                        local dx = currentPosition.X - lastPosition.X
                        local dy = currentPosition.Y - lastPosition.Y
                        local dz = currentPosition.Z - lastPosition.Z
                        local distanceMovedSq = dx * dx + dy * dy + dz * dz
                        
                        if distanceMovedSq > movementThresholdSq then
                            asset:Destroy()
                            asset = nil
                            if trackingConnection then
                                trackingConnection:Disconnect()
                            end
                            NightmareEmote:Toggle()
                            return
                        end
                        
                        lastPosition = currentPosition
                    end
                    
                    if cachedRootPart then
                        v10:SetPrimaryPartCFrame(cachedRootPart.CFrame * CFrame.new(0, -3, 0))
                    end
                end)
                
                NightmareEmote:Clean(trackingConnection)
                
            else 
                if trackingConnection then
                    trackingConnection:Disconnect()
                    trackingConnection = nil
                end
                
                if anim then 
                    anim:Stop()
                    anim = nil
                end
                
                if asset then
                    asset:Destroy() 
                    asset = nil
                end
                
                lastPosition = nil
                cachedRootPart = nil
                cachedHumanoid = nil
                lastValidationCheck = 0
            end
        end
    })
end)

run(function()
    local AutoCounter
    local tntCount
    local LimitItem
    local AutoPlaceToggle
    local HighlightToggle

    local alltntBlocks = {}
    local counteredtnt = {}
    local tntHighlights = {}
    local autoCounterPlacing = false

    local function addHighlight(tntBlock)
        if tntHighlights[tntBlock] or not tntBlock.Parent then return end
        local h = Instance.new('SelectionBox')
        h.Adornee = tntBlock
        h.Color3 = Color3.fromRGB(255, 50, 50)
        h.LineThickness = 0.05
        h.SurfaceTransparency = 0.6
        h.SurfaceColor3 = Color3.fromRGB(255, 50, 50)
        h.Parent = coreGui
        tntHighlights[tntBlock] = h
    end

    local function removeHighlight(tntBlock)
        if tntHighlights[tntBlock] then
            tntHighlights[tntBlock]:Destroy()
            tntHighlights[tntBlock] = nil
        end
    end

    local function clearAllHighlights()
        for _, h in pairs(tntHighlights) do
            h:Destroy()
        end
        table.clear(tntHighlights)
    end

    local function isEnemytnt(tntBlock)
        if not tntBlock or not tntBlock.Parent then return false end
        if tntBlock:GetAttribute("AutoCountertnt") then return false end

        local placerId = tntBlock:GetAttribute("PlacedByUserId")
        if not placerId then
            return true
        end

        if placerId == lplr.UserId then
            return false
        end
        local myTeam = lplr:GetAttribute('Team')
        if myTeam then
            for _, player in playersService:GetPlayers() do
                if player.UserId == placerId and player:GetAttribute('Team') == myTeam then
                    return false
                end
            end
        end

        return true
    end

    local function isHoldingtnt()
        return isHoldingItem({'tnt'})
    end

    AutoCounter = vape.Categories.World:CreateModule({
        Name = 'AutoCounter',
        Function = function(callback)
            if callback then
                table.clear(counteredtnt)

                local tntAddedConnection = workspace.DescendantAdded:Connect(function(obj)
                    if obj.Name == "tnt" and obj:IsA("Part") then
                        if autoCounterPlacing then
                            obj:SetAttribute("AutoCountertnt", true)
                        end
                        alltntBlocks[obj] = true

                        task.defer(function()
                            if HighlightToggle and HighlightToggle.Enabled and isEnemytnt(obj) then
                                addHighlight(obj)
                            end
                        end)

                        local ancestryConnection
                        ancestryConnection = obj.AncestryChanged:Connect(function()
                            if not obj.Parent then
                                alltntBlocks[obj] = nil
                                counteredtnt[obj] = nil
                                removeHighlight(obj)
                                local fixedPos = fixPosition(obj.Position)
                                local posKey = string.format("%.0f,%.0f,%.0f", fixedPos.X, fixedPos.Y, fixedPos.Z)
                                autoCounterPositions[posKey] = nil
                                if ancestryConnection then
                                    ancestryConnection:Disconnect()
                                end
                            end
                        end)
                    end
                end)
                AutoCounter:Clean(tntAddedConnection)

                for _, obj in workspace:GetDescendants() do
                    if obj.Name == "tnt" and obj:IsA("Part") and not alltntBlocks[obj] then
                        alltntBlocks[obj] = true
                    end
                end

                local horizontalSides = {}
                for _, side in ipairs(Enum.NormalId:GetEnumItems()) do
                    local sideVec = Vector3.fromNormalId(side)
                    if sideVec.Y == 0 then
                        table.insert(horizontalSides, sideVec)
                    end
                end

                repeat
                    if not entitylib.isAlive then
                        task.wait(0.1)
                        continue
                    end

                    if HighlightToggle and HighlightToggle.Enabled then
                        for tntBlock in pairs(alltntBlocks) do
                            if tntBlock.Parent and isEnemytnt(tntBlock) then
                                addHighlight(tntBlock)
                            end
                        end
                    else
                        clearAllHighlights()
                    end

                    if AutoPlaceToggle and AutoPlaceToggle.Enabled then
                        if LimitItem.Enabled and not isHoldingtnt() then
                            task.wait(0.1)
                            continue
                        end

                        if not getItem("tnt") then
                            task.wait(0.1)
                            continue
                        end

                        local myPosition = entitylib.character.RootPart.Position
                        local maxDistanceSq = 30 * 30

                        for tntBlock in pairs(alltntBlocks) do
                            if tntBlock.Parent and not counteredtnt[tntBlock] and isEnemytnt(tntBlock) then
                                local offset = tntBlock.Position - myPosition
                                local distanceSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z

                                if distanceSq <= maxDistanceSq then
                                    local placedCount = 0
                                    local maxCount = tntCount.Value

                                    for _, sideVec in ipairs(horizontalSides) do
                                        if LimitItem.Enabled and not isHoldingtnt() then break end
                                        if placedCount >= maxCount then break end

                                        local placePos = fixPosition(tntBlock.Position + sideVec * 3.5)
                                        if not getPlacedBlock(placePos) and getItem("tnt") then
                                            if LimitItem.Enabled and not isHoldingtnt() then break end
                                            autoCounterPlacing = true
                                            bedwars.placeBlock(placePos, "tnt")
                                            autoCounterPlacing = false
                                            placedCount = placedCount + 1
                                            task.wait(0.05)
                                        end
                                    end

                                    counteredtnt[tntBlock] = true
                                    task.defer(function()
                                        if tntBlock.Parent then
                                            tntBlock.AncestryChanged:Wait()
                                        end
                                        counteredtnt[tntBlock] = nil
                                    end)
                                end
                            end
                        end
                    end

                    task.wait(0.1)
                until not AutoCounter.Enabled
            else
                table.clear(counteredtnt)
                clearAllHighlights()
            end
        end,
        Tooltip = 'Highlights and counters enemys tnt'
    })

    tntCount = AutoCounter:CreateSlider({
        Name = 'tnt Count',
        Min = 1,
        Max = 5,
        Default = 3
    })

    LimitItem = AutoCounter:CreateToggle({
        Name = 'Limit to tnt',
        Default = true,
    })

    AutoPlaceToggle = AutoCounter:CreateToggle({
        Name = 'AutoPlace',
        Default = true,
    })

    HighlightToggle = AutoCounter:CreateToggle({
        Name = 'Highlight',
        Default = true,
    })
end)
	
run(function()
	local AutoPlay
	local Random
	
	local function isEveryoneDead()
		return #bedwars.Store:getState().Party.members <= 0
	end
	
	local function joinQueue()
		if not bedwars.Store:getState().Game.customMatch and bedwars.Store:getState().Party.leader.userId == lplr.UserId and bedwars.Store:getState().Party.queueState == 0 then
			if Random.Enabled then
				local listofmodes = {}
				for i, v in bedwars.QueueMeta do
					if not v.disabled and not v.voiceChatOnly and not v.rankCategory then 
						table.insert(listofmodes, i) 
					end
				end
				bedwars.QueueController:joinQueue(listofmodes[math.random(1, #listofmodes)])
			else
				bedwars.QueueController:joinQueue(store.queueType)
			end
		end
	end
	
	AutoPlay = vape.Categories.Utility:CreateModule({
		Name = 'AutoPlay',
		Function = function(callback)
			if callback then
				AutoPlay:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
					if deathTable.finalKill and deathTable.entityInstance == lplr.Character and isEveryoneDead() and store.matchState ~= 2 then
						joinQueue()
					end
				end))
				AutoPlay:Clean(vapeEvents.MatchEndEvent.Event:Connect(function()
					task.wait(1)
					joinQueue()
				end))
			end
		end,
		Tooltip = 'auto queues after the match ends.'
	})
	Random = AutoPlay:CreateToggle({
		Name = 'Random',
	})
end)

run(function()
    local ProximityMaxDistance
    local MaxDistance
    local oldDistances = {}
    local addedConnection
    local removedConnection
    local trackedPrompts = {}
    
    ProximityMaxDistance = vape.Categories.Utility:CreateModule({
        Name = "ProximityExtender",
        Function = function(callback)
            
            if callback then
                table.clear(oldDistances)
                table.clear(trackedPrompts)
                
                local function applyToPrompt(prompt)
                    if not prompt:IsA("ProximityPrompt") then return end
                    if trackedPrompts[prompt] then return end 
                    
                    trackedPrompts[prompt] = true
                    oldDistances[prompt] = prompt.MaxActivationDistance
                    prompt.MaxActivationDistance = MaxDistance.Value
                end
                
                local function scanForPrompts(parent)
                    for _, obj in ipairs(parent:GetDescendants()) do
                        if obj:IsA("ProximityPrompt") then
                            applyToPrompt(obj)
                        end
                    end
                end
                
                scanForPrompts(workspace)
                
                addedConnection = workspace.DescendantAdded:Connect(function(obj)
                    if obj:IsA("ProximityPrompt") then
                        applyToPrompt(obj)
                    end
                end)
                
                removedConnection = workspace.DescendantRemoving:Connect(function(obj)
                    if obj:IsA("ProximityPrompt") then
                        oldDistances[obj] = nil
                        trackedPrompts[obj] = nil
                    end
                end)
                
                MaxDistance.Function = function(value)
                    for prompt in pairs(trackedPrompts) do
                        if prompt and prompt.Parent then
                            prompt.MaxActivationDistance = value
                        end
                    end
                end
            else
                if addedConnection then
                    addedConnection:Disconnect()
                    addedConnection = nil
                end
                
                if removedConnection then
                    removedConnection:Disconnect()
                    removedConnection = nil
                end
                
                for prompt, dist in pairs(oldDistances) do
                    if prompt and prompt.Parent then
                        pcall(function()
                            prompt.MaxActivationDistance = dist
                        end)
                    end
                end
                
                table.clear(oldDistances)
                table.clear(trackedPrompts)
                MaxDistance.Function = function() end
            end
        end,
        Tooltip = "increase the range of proximity"
    })
    
    MaxDistance = ProximityMaxDistance:CreateSlider({
        Name = 'Max Distance',
        Min = 10,
        Max = 20,
        Default = 20,
    })
end)
	
run(function()
	local AutoVoidDrop
	local OwlCheck
	local PearlCheck
	local pearlLastInHandTickVoid = 0
	local DropToggles = {
		iron = nil,
		diamond = nil,
		emerald = nil,
		gold = nil
	}
	local cachedLowestPoint
	
	AutoVoidDrop = vape.Categories.Utility:CreateModule({
		Name = 'AutoVoidDrop',
		Function = function(callback)
			if callback then
				repeat task.wait() until store.matchState ~= 0 or (not AutoVoidDrop.Enabled)
				if not AutoVoidDrop.Enabled then return end

				cachedLowestPoint = math.huge
				for _, v in pairs(store.blocks) do
					local point = (v.Position.Y - (v.Size.Y / 2)) - 75
					if point < cachedLowestPoint then
						cachedLowestPoint = point
					end
				end

				repeat
					if entitylib.isAlive then
						local root = entitylib.character.RootPart

						local handItem = store.inventory and store.inventory.inventory and store.inventory.inventory.hand
						if handItem and handItem.itemType == 'telepearl' then
							pearlLastInHandTickVoid = tick()
						end

						if root.Position.Y < cachedLowestPoint and (lplr.Character:GetAttribute('InflatedBalloons') or 0) <= 0 and not getItem('balloon') then
							local pearlBlock = PearlCheck.Enabled and (tick() - pearlLastInHandTickVoid) < 4
							if (not OwlCheck.Enabled or not root:FindFirstChild('OwlLiftForce')) and not pearlBlock then
								for _, item in pairs(store.inventory.inventory.items) do
									if item and item.tool then
										local dropped = bedwars.Client:Get(remotes.DropItem):CallServer({
											item = item.tool,
											amount = item.amount
										})
										if dropped then
											dropped:SetAttribute('ClientDropTime', tick() + 100)
										end
									end
								end
								break
							end
						end
					end

					task.wait(0.1)
				until not AutoVoidDrop.Enabled
			end
		end,
		Tooltip = 'drops resources when you fall into the void'
	})
	
	OwlCheck = AutoVoidDrop:CreateToggle({
		Name = 'Owl check',
		Default = true,
		Tooltip = 'doesnt drop items if being picked up by an owl'
	})
	PearlCheck = AutoVoidDrop:CreateToggle({
		Name = 'Pearl check',
		Default = false,
		Tooltip = 'does not drop if holding a pearl or recently threw one (4 sec cooldown)'
	})
	DropToggles.iron = AutoVoidDrop:CreateToggle({
		Name = 'Drop Iron',
		Default = true
	})
	DropToggles.diamond = AutoVoidDrop:CreateToggle({
		Name = 'Drop Diamond',
		Default = true
	})
	DropToggles.emerald = AutoVoidDrop:CreateToggle({
		Name = 'Drop Emerald',
		Default = true
	})
	DropToggles.gold = AutoVoidDrop:CreateToggle({
		Name = 'Drop Gold',
		Default = true
	})
end)
	
run(function()
	local PickupRange
	local Range
	local Lower
	local Network
	local PickupDelay
	local lastPickupTime = 0
	
	PickupRange = vape.Categories.Utility:CreateModule({
		Name = 'PickupRange',
		Function = function(callback)
			if callback then
				local items = collection('ItemDrop', PickupRange)
				local rangeSquared = Range.Value * Range.Value
				
				repeat
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position
						local humanoidHealth = entitylib.character.Humanoid.Health
						local currentTime = tick()
						local pickupDelaySeconds = PickupDelay.Value / 1000
						rangeSquared = Range.Value * Range.Value

						for _, v in pairs(items) do
							if (currentTime - (v:GetAttribute('ClientDropTime') or 0)) < 2 then continue end
							if (currentTime - lastPickupTime) < pickupDelaySeconds then continue end

							if isnetworkowner(v) and Network.Enabled and humanoidHealth > 0 then
								v.CFrame = CFrame.new(localPosition - Vector3.new(0, 3, 0))
							end

							local offset = v.Position - localPosition
							local distanceSquared = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z

							if distanceSquared <= rangeSquared then
								if Lower.Enabled and (localPosition.Y - v.Position.Y) < (entitylib.character.HipHeight - 1) then continue end

								bedwars.Client:Get(remotes.PickupItem):CallServerAsync({
									itemDrop = v
								}):andThen(function(suc)
									if suc then
										lastPickupTime = tick()
										if bedwars.SoundList then
											bedwars.SoundManager:playSound(bedwars.SoundList.PICKUP_ITEM_DROP)
											local itemMeta = bedwars.ItemMeta[v.Name]
											if itemMeta then
												local sound = itemMeta.pickUpOverlaySound
												if sound then
													bedwars.SoundManager:playSound(sound, {
														position = v.Position,
														volumeMultiplier = 0.9
													})
												end
											end
										end
									end
								end)
							end
						end
					end
					task.wait(0.1)
				until not PickupRange.Enabled
			else
				lastPickupTime = 0
			end
		end,
		Tooltip = 'Picks up items from a farther distance'
	})

	Range = PickupRange:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 10,
		Default = 10,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	PickupDelay = PickupRange:CreateSlider({
		Name = 'Pickup Delay',
		Min = 0,
		Max = 500,
		Default = 0,
		Suffix = 'ms'
	})
	Network = PickupRange:CreateToggle({
		Name = 'Network TP',
		Default = true
	})
	Lower = PickupRange:CreateToggle({
		Name = 'Feet Check'
	})
end)

run(function()
	local Scaffold
	local Expand
	local Tower
	local Downwards
	local Diagonal
	local LimitItem
	local Mouse
	local PlaceDelay
	local adjacent, lastpos = {}, Vector3.zero
	local lastPlaceTime = 0
	
	for x = -3, 3, 3 do
		for y = -3, 3, 3 do
			for z = -3, 3, 3 do
				local vec = Vector3.new(x, y, z)
				if vec ~= Vector3.zero then
					table.insert(adjacent, vec)
				end
			end
		end
	end
	
	local function checkAdjacent(pos)
		for _, v in adjacent do
			if getPlacedBlock(pos + v) then
				return true
			end
		end
		return false
	end
	
	local function getScaffoldBlock()
		if store.hand.toolType == 'block' then
			return store.hand.tool.Name, store.hand.amount
		elseif (not LimitItem.Enabled) then
			local isHoldingSwordOrTool = store.hand.toolType == 'sword' or (store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].sword)
			if not isHoldingSwordOrTool then
				local wool, amount = getWool()
				if wool then
					return wool, amount
				else
					for _, item in store.inventory.inventory.items do
						if bedwars.ItemMeta[item.itemType].block then
							return item.itemType, item.amount
						end
					end
				end
			end
		end
	
		return nil, 0
	end
	
	Scaffold = vape.Categories.Utility:CreateModule({
		Name = 'Scaffold',
		Function = function(callback)
			if callback then
				lastPlaceTime = 0
				repeat
					if entitylib.isAlive then
						local wool, amount = getScaffoldBlock()

						if Mouse.Enabled then
							if not inputService:IsMouseButtonPressed(0) then
								wool = nil
							end
						end

						if wool then
							local root = entitylib.character.RootPart
							if Tower.Enabled and inputService:IsKeyDown(Enum.KeyCode.Space) and (not inputService:GetFocusedTextBox()) then
								root.Velocity = Vector3.new(root.Velocity.X, 38, root.Velocity.Z)
							end

							for i = Expand.Value, 1, -1 do
								local currentpos = roundPos(root.Position - Vector3.new(0, entitylib.character.HipHeight + (Downwards.Enabled and inputService:IsKeyDown(Enum.KeyCode.LeftShift) and 4.5 or 1.5), 0) + entitylib.character.Humanoid.MoveDirection * (i * 3))
								if Diagonal.Enabled then
									if math.abs(math.round(math.deg(math.atan2(-entitylib.character.Humanoid.MoveDirection.X, -entitylib.character.Humanoid.MoveDirection.Z)) / 45) * 45) % 90 == 45 then
										local dt = (lastpos - currentpos)
										if ((dt.X == 0 and dt.Z ~= 0) or (dt.X ~= 0 and dt.Z == 0)) and ((lastpos - root.Position) * Vector3.new(1, 0, 1)).Magnitude < 2.5 then
											currentpos = lastpos
										end
									end
								end

								local block, blockpos = getPlacedBlock(currentpos)
								if not block then
									if tick() - lastPlaceTime >= (PlaceDelay.Value / 1000) then
										blockpos = checkAdjacent(blockpos * 3) and blockpos * 3 or blockProximity(currentpos)
										if blockpos then
											task.spawn(bedwars.placeBlock, blockpos, wool, false)
											lastPlaceTime = tick()
										end
									end
								end
								lastpos = currentpos
							end
						end
					end

					task.wait(0.03)
				until not Scaffold.Enabled
			else
				lastPlaceTime = 0
			end
		end,
		Tooltip = 'Helps you make bridges/scaffold walk.'
	})
	Expand = Scaffold:CreateSlider({
		Name = 'Expand',
		Min = 1,
		Max = 6
	})
	Tower = Scaffold:CreateToggle({
		Name = 'Tower',
		Default = true
	})
	Downwards = Scaffold:CreateToggle({
		Name = 'Downwards',
		Default = true
	})
	Diagonal = Scaffold:CreateToggle({
		Name = 'Diagonal',
		Default = true
	})
	LimitItem = Scaffold:CreateToggle({Name = 'Limit to items'})
	Mouse = Scaffold:CreateToggle({Name = 'Require mouse down'})
	PlaceDelay = Scaffold:CreateSlider({
		Name = 'Place Delay',
		Min = 0,
		Max = 200,
		Default = 0,
		Suffix = "ms"
	})
end)
	
run(function()
	local ShopTierBypass
	local tiered, nexttier = {}, {}
	local originalGetShop
	local shopItemsTracked = {}
	
	local function applyBypassToItem(item)
		if item and type(item) == "table" then
			if not tiered[item] then 
				tiered[item] = item.tiered 
			end
			if not nexttier[item] then 
				nexttier[item] = item.nextTier 
			end
			item.nextTier = nil
			item.tiered = nil
			shopItemsTracked[item] = true
		end
	end
	
	local function applyBypassToTable(tbl)
		if tbl and type(tbl) == "table" then
			for _, item in pairs(tbl) do
				if type(item) == "table" then
					applyBypassToItem(item)
				end
			end
		end
	end
	
	local function getShopController()
		local success, result = pcall(function()
			local RuntimeLib = require(game:GetService("ReplicatedStorage"):WaitForChild("rbxts_include"):WaitForChild("RuntimeLib"))
			if RuntimeLib then
				return RuntimeLib.import(script, game:GetService("ReplicatedStorage"), "TS", "games", "bedwars", "shop", "bedwars-shop")
			end
		end)
		
		if success then
			return result
		end
		
		local shopModule = game:GetService("ReplicatedStorage"):FindFirstChild("TS"):FindFirstChild("games"):FindFirstChild("bedwars"):FindFirstChild("shop"):FindFirstChild("bedwars-shop")
		if shopModule and shopModule:IsA("ModuleScript") then
			return require(shopModule)
		end
		
		return nil
	end
	
	ShopTierBypass = vape.Categories.Utility:CreateModule({
		Name = 'ShopTierBypass',
		Function = function(callback)
			if callback then
				local function collectAndBypass()
					local itemsSeen = {}
					if bedwars.Shop and bedwars.Shop.ShopItems then
						for _, v in pairs(bedwars.Shop.ShopItems) do
							itemsSeen[v] = true
						end
					end
					if bedwars.ShopItems then
						for _, v in pairs(bedwars.ShopItems) do
							itemsSeen[v] = true
						end
					end
					
					local shopController = getShopController()
					if shopController and shopController.BedwarsShop and shopController.BedwarsShop.getShop then
						local shopTable = shopController.BedwarsShop.getShop()
						if type(shopTable) == "table" then
							for _, v in pairs(shopTable) do
								itemsSeen[v] = true
							end
						end
					end
					for item, _ in pairs(itemsSeen) do
						applyBypassToItem(item)
					end
				end
				collectAndBypass()
				if bedwars.Shop and bedwars.Shop.getShop and not originalGetShop then
					originalGetShop = bedwars.Shop.getShop
					bedwars.Shop.getShop = function(...)
						local result = originalGetShop(...)
						if type(result) == "table" then
							applyBypassToTable(result)
						end
						return result
					end
				end
				
				local shopController = getShopController()
				if shopController and shopController.BedwarsShop and shopController.BedwarsShop.getShop then
					if not tiered["shopControllerHooked"] then
						tiered["shopControllerHooked"] = true
						local originalControllerGetShop = shopController.BedwarsShop.getShop
						shopController.BedwarsShop.getShop = function(...)
							local result = originalControllerGetShop(...)
							if type(result) == "table" then
								applyBypassToTable(result)
							end
							return result
						end
					end
				end
			else
				for item, _ in pairs(shopItemsTracked) do
					if item and type(item) == "table" then
						if tiered[item] ~= nil then
							item.tiered = tiered[item]
						end
						if nexttier[item] ~= nil then
							item.nextTier = nexttier[item]
						end
					end
				end
				
				if tiered["shopControllerHooked"] then
					tiered["shopControllerHooked"] = nil
				end
				
				if originalGetShop then
					bedwars.Shop.getShop = originalGetShop
					originalGetShop = nil
				end
				
				table.clear(tiered)
				table.clear(nexttier)
				table.clear(shopItemsTracked)
			end
		end,
		Tooltip = 'lets u buy shit without buying the other tiers'
	})
end)
	
run(function()
	vape.Categories.World:CreateModule({
		Name = 'AntiAFK',
		Function = function(callback)
			if callback then
				pcall(function()
					for _, v in getconnections(lplr.Idled) do
						v:Disconnect()
					end
				end)

				pcall(function()
					for _, v in getconnections(runService.Heartbeat) do
						if type(v.Function) == 'function' then
							local constants = debug.getconstants(v.Function)
							if constants and table.find(constants, remotes.AfkStatus) then
								v:Disconnect()
							end
						end
					end
				end)

				pcall(function()
					local afkRemote = bedwars.Client:Get(remotes.AfkStatus)
					if afkRemote then
						afkRemote:SendToServer({
							afk = false
						})
					end
				end)
			end
		end,
	})
end)

run(function()
    local AutoBuildUp
    local LimitItem
    
    local function getScaffoldBlock()
        return getScaffoldBlockForModule(LimitItem)
    end

    local function canPlaceAtPosition(blockpos)
        if not checkFaceAdjacent(blockpos) then
            return false
        end
        
        local checkBelow = blockpos - Vector3.new(0, 3, 0)
        local hasSupport = false
        
        for i = 1, 10 do
            if getPlacedBlock(checkBelow) then
                hasSupport = true
                break
            end
            checkBelow = checkBelow - Vector3.new(0, 3, 0)
        end
        
        return hasSupport or hasFaceBelowOrSide(blockpos)
    end
    
    AutoBuildUp = vape.Categories.World:CreateModule({
        Name = 'AutoBuildUp',
        Function = function(callback)
            
            if callback then
                repeat
                    if entitylib.isAlive then
                        local wool = getScaffoldBlock()
                        
                        if wool then
                            local root = entitylib.character.RootPart
                            
                            if inputService:IsKeyDown(Enum.KeyCode.Space) and (not inputService:GetFocusedTextBox()) then
                                local currentpos = roundPos(root.Position - Vector3.new(0, entitylib.character.HipHeight + 1.5, 0))
                                
                                local block, blockpos = getPlacedBlock(currentpos)
                                if not block then
                                    blockpos = blockpos * 3
                                    
                                    if hasFaceBelowOrSide(blockpos) then
                                        if canPlaceAtPosition(blockpos) then
                                            task.spawn(bedwars.placeBlock, blockpos, wool, false)
                                        end
                                    else
                                        local nearestBlock = blockProximity(currentpos)
                                        if nearestBlock and canPlaceAtPosition(nearestBlock) then
                                            task.spawn(bedwars.placeBlock, nearestBlock, wool, false)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    task.wait(0.03)
                until not AutoBuildUp.Enabled
            end
        end,
    })
    
    LimitItem = AutoBuildUp:CreateToggle({
        Name = 'Limit to items',
        Default = false,
    })
end)

run(function()
	local AutoTool

	AutoTool = vape.Categories.World:CreateModule({
		Name = 'AutoTool',
		Function = function(callback)
			if callback then
				registerHitBlockPatch('AutoTool', function(self, maid, raycastparams, ...)
					local ok, block = pcall(function()
						return self.clientManager:getBlockSelector():getMouseInfo(1, {ray = raycastparams})
					end)
					local targetBlock = ok and block and block.target and block.target.blockInstance or nil
					if not targetBlock then return end

					local _blockMeta = bedwars.ItemMeta and bedwars.ItemMeta[targetBlock.Name]
					if not _blockMeta or not _blockMeta.block then return end

					local tool = store.tools[_blockMeta.block.breakType]
					if not tool then return end

					local slot = nil
					for i, v in store.inventory.hotbar do
						if v.item and v.item.itemType == tool.itemType then
							slot = i - 1
							break
						end
					end
					if slot == nil then return end

					hotbarSwitch(slot)
					return
				end)
			else
				unregisterHitBlockPatch('AutoTool')
			end
		end,
		Tooltip = 'switches to the correct tool for the block ur lookin at'
	})
end)
	
run(function()
	local ChestSteal
	local Range
	local Open
	local Skywars
	local DelayToggle
	local DelaySlider
	local TeamFilter
	local Delays = {}
	
	local function isTeamChest(chest)
		if not TeamFilter.Enabled then return false end
		local myTeam = tostring(lplr:GetAttribute('Team') or '')
		local myBed = nil
		for _, bed in collectionService:GetTagged('bed') do
			if not bed:IsA('BasePart') then continue end
			local bedTeam = tostring(bed:GetAttribute('Team') or bed:GetAttribute('TeamId') or '')
			if bedTeam == myTeam then myBed = bed break end
		end
		if not myBed then return false end
		local dist = (chest.Position - myBed.Position).Magnitude
		return dist <= 60
	end
	
	local function lootChest(chest)
		chest = chest and chest.Value or nil
		if not chest then return end
		
		local chestitems = chest and chest:GetChildren() or {}
		if #chestitems > 1 and (Delays[chest] or 0) < tick() then
			Delays[chest] = tick() + (DelayToggle.Enabled and DelaySlider.Value or 0.2)
			bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(chest)
	
			for _, v in chestitems do
				if v:IsA('Accessory') then
					if DelayToggle.Enabled then
						task.wait(DelaySlider.Value / #chestitems) 
					end
					
					task.spawn(function()
						pcall(function()
							bedwars.Client:GetNamespace('Inventory'):Get('ChestGetItem'):CallServer(chest, v)
						end)
					end)
				end
			end
	
			bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(nil)
		end
	end
	
	ChestSteal = vape.Categories.World:CreateModule({
		Name = 'ChestSteal',
		Function = function(callback)
			if callback then
				local chests = collection('chest', ChestSteal)
				repeat task.wait() until store.queueType ~= 'bedwars_test'
				if (not Skywars.Enabled) or store.queueType:find('skywars') then
					repeat
						if entitylib.isAlive and store.matchState ~= 2 then
							if Open.Enabled then
								if bedwars.AppController:isAppOpen('ChestApp') then
									lootChest(lplr.Character:FindFirstChild('ObservedChestFolder'))
								end
							else
								local localPosition = entitylib.character.RootPart.Position
								for _, v in chests do
									if (localPosition - v.Position).Magnitude <= Range.Value then
										if isTeamChest(v) then continue end
										lootChest(v:FindFirstChild('ChestFolderValue'))
									end
								end
							end
						end
						task.wait(0.1)
					until not ChestSteal.Enabled
				end
			end
		end,
		Tooltip = 'takes items from near chests'
	})
	Range = ChestSteal:CreateSlider({
		Name = 'Range',
		Min = 0,
		Max = 18,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	Open = ChestSteal:CreateToggle({Name = 'GUI Check'})
	Skywars = ChestSteal:CreateToggle({
		Name = 'Only Skywars',
		Function = function()
			if ChestSteal.Enabled then
				ChestSteal:Toggle()
				ChestSteal:Toggle()
			end
		end,
		Default = true
	})
	TeamFilter = ChestSteal:CreateToggle({
		Name = 'Team Check',
		Default = false
	})
	DelayToggle = ChestSteal:CreateToggle({
		Name = 'Delay',
		Function = function(callback)
			DelaySlider.Object.Visible = callback
			if ChestSteal.Enabled then
				ChestSteal:Toggle()
				ChestSteal:Toggle()
			end
		end
	})
    DelaySlider = ChestSteal:CreateSlider({
        Name = 'Delay Time',
        Min = 0.1,
        Max = 5,
        Default = 1,
        Decimal = 10,
        Suffix = 's',
        Visible = false
    })

    task.defer(function()
        if DelaySlider and DelaySlider.Object then
            DelaySlider.Object.Visible = false  
        end
    end)
end)
	
run(function()
	local AutoBank
	local UIToggle
	local GUICheck
	local UI
	local Chests
	local Items = {}
	local BankToggles = {
		iron = nil,
		diamond = nil,
		emerald = nil
	}
	local cachedChest
	local lastChestCheck = 0
	local lastHotbarUpdate = 0

	local function addItem(itemType, shop)
		local item = Instance.new('ImageLabel')
		item.Image = bedwars.getIcon({itemType = itemType}, true)
		item.Size = UDim2.fromOffset(32, 32)
		item.Name = itemType
		item.BackgroundTransparency = 1
		item.LayoutOrder = #UI:GetChildren()
		item.Parent = UI
		local itemtext = Instance.new('TextLabel')
		itemtext.Name = 'Amount'
		itemtext.Size = UDim2.fromScale(1, 1)
		itemtext.BackgroundTransparency = 1
		itemtext.Text = ''
		itemtext.TextColor3 = Color3.new(1, 1, 1)
		itemtext.TextSize = 16
		itemtext.TextStrokeTransparency = 0.3
		itemtext.Font = Enum.Font.Arial
		itemtext.Parent = item
		Items[itemType] = {Object = itemtext, Type = shop}
	end

	local function refreshBank(echest)
		for i, v in pairs(Items) do
			local item = echest:FindFirstChild(i)
			v.Object.Text = item and item:GetAttribute('Amount') or ''
		end
	end

	local function nearChest()
		if not entitylib.isAlive then return false end

		local pos = entitylib.character.RootPart.Position
		local maxDistanceSq = 22 * 22

		for _, chest in pairs(Chests) do
			if chest.Parent then
				local offset = chest.Position - pos
				local distanceSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
				if distanceSq < maxDistanceSq then
					return true
				end
			end
		end

		return false
	end

	local function isNearOwnBase()
		if not entitylib.isAlive then return false end
		local myTeam = tostring(lplr:GetAttribute('Team') or '')
		if myTeam == '' then return false end
		local myBed = nil
		for _, bed in collectionService:GetTagged('bed') do
			if not bed:IsA('BasePart') then continue end
			local bedTeam = tostring(bed:GetAttribute('Team') or bed:GetAttribute('TeamId') or '')
			if bedTeam == myTeam then myBed = bed break end
		end
		if not myBed then return false end
		local bedPos = myBed.Position
		local closestChest, closestDist = nil, math.huge
		for _, chest in pairs(Chests) do
			if chest.Parent then
				local dist = (chest.Position - bedPos).Magnitude
				if dist < closestDist then closestChest = chest closestDist = dist end
			end
		end
		if not closestChest then return false end
		local myPos = entitylib.character.RootPart.Position
		return (myPos - closestChest.Position).Magnitude <= 60
	end

	local function handleState()
		local currentTime = tick()

		if not cachedChest or not cachedChest.Parent or (currentTime - lastChestCheck) > 1 then
			cachedChest = replicatedStorage.Inventories:FindFirstChild(lplr.Name..'_personal')
			lastChestCheck = currentTime
		end

		if not cachedChest then return end

		if not nearChest() and not GUICheck.Enabled then
			return
		end

		local itemsToDeposit = {}
		for _, v in ipairs(store.inventory.inventory.items) do
			local itemInfo = Items[v.itemType]
			if itemInfo and BankToggles[v.itemType] and BankToggles[v.itemType].Enabled then
				table.insert(itemsToDeposit, v)
			end
		end

		if #itemsToDeposit > 0 then
			for _, v in ipairs(itemsToDeposit) do
				bedwars.Client:GetNamespace('Inventory'):Get('ChestGiveItem'):CallServer(cachedChest, v.tool)
			end
			task.defer(function()
				if cachedChest and cachedChest.Parent then
					refreshBank(cachedChest)
				end
			end)
		end
	end


	AutoBank = vape.Categories.Inventory:CreateModule({
		Name = 'AutoBank',
		Function = function(callback)
			if callback then
				Chests = collection('chest', AutoBank)
				cachedChest = nil
				lastChestCheck = 0
				lastHotbarUpdate = 0
				UI = Instance.new('Frame')
				UI.Size = UDim2.new(1, 0, 0, 32)
				UI.Position = UDim2.fromOffset(0, -240)
				UI.BackgroundTransparency = 1
				UI.Visible = UIToggle.Enabled
				UI.Parent = vape.gui
				AutoBank:Clean(UI)

				local Sort = Instance.new('UIListLayout')
				Sort.FillDirection = Enum.FillDirection.Horizontal
				Sort.HorizontalAlignment = Enum.HorizontalAlignment.Center
				Sort.SortOrder = Enum.SortOrder.LayoutOrder
				Sort.Parent = UI

				addItem('iron', true)
				addItem('diamond', false)
				addItem('emerald', true)

				local cachedHotbar
				local guiInset = guiService:GetGuiInset().Y

				repeat
					local currentTime = tick()

					if (currentTime - lastHotbarUpdate) > 0.5 then
						local playerGui = lplr.PlayerGui
						if playerGui then
							local hotbar = playerGui:FindFirstChild('hotbar')
							if hotbar then
								local container = hotbar['1']:FindFirstChild('HotbarHealthbarContainer')
								if container then
									cachedHotbar = container
									UI.Position = UDim2.fromOffset(0, (container.AbsolutePosition.Y + guiInset) - 40)
									lastHotbarUpdate = currentTime
								end
							end
						end
					end

					local shouldBank = false

					if GUICheck.Enabled then
						shouldBank = bedwars.AppController:isAppOpen('ChestApp') or
						             bedwars.AppController:isAppOpen('BedwarsAppIds.CHEST_INVENTORY')
					else
						shouldBank = nearChest()
					end

					if shouldBank and not (TeamCheck and TeamCheck.Enabled and isNearOwnBase()) then
						handleState()
					end

					task.wait(0.1)
				until (not AutoBank.Enabled)
			else
				table.clear(Items)
				cachedChest = nil
			end
		end,
		Tooltip = 'automatically puts resources in pchest'
	})

	UIToggle = AutoBank:CreateToggle({
		Name = 'UI',
		Function = function(callback)
			if AutoBank.Enabled and UI then
				UI.Visible = callback
			end
		end,
		Default = true
	})

	GUICheck = AutoBank:CreateToggle({
		Name = 'GUI Check',
	})

	BankToggles.iron = AutoBank:CreateToggle({
		Name = 'Bank Iron',
		Default = true
	})

	BankToggles.diamond = AutoBank:CreateToggle({
		Name = 'Bank Diamond',
		Default = true
	})

	BankToggles.emerald = AutoBank:CreateToggle({
		Name = 'Bank Emerald',
		Default = true
	})

	TeamCheck = AutoBank:CreateToggle({
		Name = 'Team Check',
		Default = false
	})
end)
	
run(function()
	local AutoBuy
	local ShopType
	local GUICheck
	local KeepBuying
	local SmartCheck
	local KeepBuyingList
	local BuyArmorToggle
	local BuyAxeToggle
	local BuyPickaxeToggle
	local BuyProjectileToggle
	local BreakSpeedToggle
	local ArmorUpgradeToggle
	local DamageToggle
	local DiamondGenToggle
	local TeamGenToggle
	local BedBarrierToggle

	local purchaseRemote
	local function getPurchaseRemote()
		if not purchaseRemote then
			purchaseRemote = game:GetService("ReplicatedStorage").rbxts_include.node_modules["@rbxts"].net.out._NetManaged.BedwarsPurchaseItem
		end
		return purchaseRemote
	end

	local function getResourceCount(currency)
		local item = getItem(currency)
		return item and item.amount or 0
	end

	local function playerOwns(itemType)
		for _, item in store.inventory.inventory.items do
			if item.itemType == itemType then return true end
		end
		if store.inventory.inventory.armor then
			for _, v in pairs(store.inventory.inventory.armor) do
				if type(v) == 'table' and v.itemType == itemType then return true end
			end
		end
		return false
	end

	local function isNearShop(checkType)
		if not GUICheck.Enabled then return true end
		local _, items, upgrades = getShopNPC()
		if checkType == 'item' then return items end
		if checkType == 'upgrade' then return upgrades end
		return false
	end

	local function buyItem(shopItem, shopId)
		pcall(function()
			getPurchaseRemote():InvokeServer({shopItem = shopItem, shopId = shopId})
		end)
	end

	local function getShopData(itemType)
		if not bedwars.Shop then return nil end
		local ok, res = pcall(function()
			return bedwars.Shop.getShopItem(itemType, lplr)
		end)
		return ok and res or nil
	end

	local armorTiers = {
		'emerald_chestplate','emerald_leggings','emerald_boots',
		'diamond_chestplate','diamond_leggings','diamond_boots',
		'iron_chestplate','iron_leggings','iron_boots',
		'leather_chestplate',
	}
	local axeTiers = {'emerald_axe','diamond_axe','iron_axe','stone_axe','wood_axe'}
	local pickaxeTiers = {'emerald_pickaxe','diamond_pickaxe','iron_pickaxe','stone_pickaxe','wood_pickaxe'}

	local function buyBestTier(tierList, shopId)
		for _, itemType in ipairs(tierList) do
			if SmartCheck.Enabled and playerOwns(itemType) then break end
			local data = getShopData(itemType)
			if data then
				if getResourceCount(data.currency or 'iron') >= (data.price or math.huge) then
					buyItem(data, shopId)
					break
				end
			end
		end
	end

	local function buyProjectile(shopId)
		local em = getResourceCount('emerald')
		local ir = getResourceCount('iron')
		local ownsAny = SmartCheck.Enabled and (playerOwns('headhunter') or playerOwns('wood_crossbow') or playerOwns('wood_bow'))
		if ownsAny then return end

		if em >= 24 then
			buyItem({
				lockAfterPurchase = true, itemType = "headhunter", price = 24,
				currency = "emerald", amount = 1,
				disabledInQueue = {"tnt_wars","bedwars_og_to4"}, category = "Combat",
				spawnWithItems = {"headhunter"},
				ignoredByKit = {"archer","flower_bee","falconer","nazar"}
			}, shopId)
		elseif em >= 7 then
			buyItem({
				disabledInQueue = {"tnt_wars","bedwars_og_to4"},
				itemType = "wood_crossbow", price = 7,
				superiorItems = {"headhunter"}, currency = "emerald",
				category = "Combat", lockAfterPurchase = true,
				ignoredByKit = {"archer","flower_bee","falconer","nazar"},
				spawnWithItems = {"wood_crossbow"}, amount = 1
			}, shopId)
		elseif ir >= 24 then
			buyItem({
				ignoredByKit = {"flower_bee","falconer","nazar"},
				itemType = "wood_bow", price = 24,
				superiorItems = {"wood_crossbow","tactical_crossbow"},
				currency = "iron", category = "Combat", lockAfterPurchase = true,
				spawnWithItems = {"wood_bow"}, amount = 1
			}, shopId)
		end
	end

	local upgradeIds = {
		BreakSpeed = 'BREAK_SPEED',
		Armor      = 'ARMOR',
		Damage     = 'DAMAGE',
		DiamondGen = 'DIAMOND_GENERATOR',
		TeamGen    = 'TEAM_GENERATOR',
	}

	local upgradeRemote = replicatedStorage:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("net"):WaitForChild("out"):WaitForChild("_NetManaged"):WaitForChild("RequestPurchaseTeamUpgrade")

	local function buyTeamUpgrade(upgradeType)
		if not upgradeType then return end
		pcall(function()
			upgradeRemote:InvokeServer(upgradeType)
		end)
	end

	local lastBedBarrierBuy = 0
	local BED_BARRIER_DURATION = 180

	local bedUpgradeRemote = replicatedStorage:WaitForChild("rbxts_include"):WaitForChild("node_modules"):WaitForChild("@rbxts"):WaitForChild("net"):WaitForChild("out"):WaitForChild("_NetManaged"):WaitForChild("RequestPurchaseBedTeamUpgrade")

	local function buyBedBarrier()
		local now = tick()
		if now - lastBedBarrierBuy < BED_BARRIER_DURATION then return end
		local ok = pcall(function()
			bedUpgradeRemote:InvokeServer("bed_shield")
			bedUpgradeRemote:InvokeServer("bed_alarm")
		end)
		if ok then
			lastBedBarrierBuy = now
		end
	end

	AutoBuy = vape.Categories.Utility:CreateModule({
		Name = 'AutoBuy',
		Function = function(callback)
			if callback then
				task.spawn(function()
					repeat task.wait() until store.shopLoaded or not AutoBuy.Enabled
					if not AutoBuy.Enabled then return end
					repeat
						task.wait(0.5)
						if not entitylib.isAlive then continue end
						if ShopType.Value == 'Item Shop' then
							if not isNearShop('item') then continue end
							local sid = "1_item_shop"
							if BuyArmorToggle.Enabled then buyBestTier(armorTiers, sid) end
							if BuyAxeToggle.Enabled then buyBestTier(axeTiers, sid) end
							if BuyPickaxeToggle.Enabled then buyBestTier(pickaxeTiers, sid) end
							if BuyProjectileToggle.Enabled then buyProjectile(sid) end
							if KeepBuying.Enabled then
								for _, itemType in ipairs(KeepBuyingList.ListEnabled or {}) do
									local data = getShopData(itemType)
									if data then
										if getResourceCount(data.currency or 'iron') >= (data.price or math.huge) then
											if not SmartCheck.Enabled or not playerOwns(itemType) then
												buyItem(data, sid)
											end
										end
									end
								end
							end
						else
							if not isNearShop('upgrade') then continue end
							if BreakSpeedToggle.Enabled   then buyTeamUpgrade(upgradeIds.BreakSpeed) end
							if ArmorUpgradeToggle.Enabled then buyTeamUpgrade(upgradeIds.Armor) end
							if DamageToggle.Enabled        then buyTeamUpgrade(upgradeIds.Damage) end
							if DiamondGenToggle.Enabled    then buyTeamUpgrade(upgradeIds.DiamondGen) end
							if TeamGenToggle.Enabled       then buyTeamUpgrade(upgradeIds.TeamGen) end
							if BedBarrierToggle.Enabled then buyBedBarrier() end
						end
					until not AutoBuy.Enabled
				end)
			end
		end,
		Tooltip = 'auto buys from item shop or team upgrade shop'
	})

	ShopType = AutoBuy:CreateDropdown({
		Name = 'Shop Type',
		List = {'Item Shop', 'Team Upgrade Shop'},
		Function = function(val)
			local isItem = val == 'Item Shop'
			if BuyArmorToggle     then BuyArmorToggle.Object.Visible     = isItem end
			if BuyAxeToggle       then BuyAxeToggle.Object.Visible       = isItem end
			if BuyPickaxeToggle   then BuyPickaxeToggle.Object.Visible   = isItem end
			if BuyProjectileToggle then BuyProjectileToggle.Object.Visible = isItem end
			if BreakSpeedToggle   then BreakSpeedToggle.Object.Visible   = not isItem end
			if ArmorUpgradeToggle then ArmorUpgradeToggle.Object.Visible = not isItem end
			if DamageToggle       then DamageToggle.Object.Visible       = not isItem end
			if DiamondGenToggle   then DiamondGenToggle.Object.Visible   = not isItem end
			if TeamGenToggle      then TeamGenToggle.Object.Visible      = not isItem end
			if BedBarrierToggle   then BedBarrierToggle.Object.Visible   = not isItem end
		end
	})

	GUICheck = AutoBuy:CreateToggle({
		Name = 'GUI Check',
		Default = true,
		Tooltip = 'only buys when you are near the shop'
	})

	KeepBuying = AutoBuy:CreateToggle({
		Name = 'Keep Buying',
		Default = false,
		Tooltip = 'keeps re-buying items listed below (item shop only)',
		Function = function(v)
			if KeepBuyingList then KeepBuyingList.Object.Visible = v end
			if SmartCheck     then SmartCheck.Object.Visible     = v end
		end
	})

	SmartCheck = AutoBuy:CreateToggle({
		Name = 'Smart Check',
		Default = true,
		Darker = true,
		Tooltip = 'skips items you already own'
	})

	KeepBuyingList = AutoBuy:CreateTextList({
		Name = 'Keep Buying List',
		Placeholder = 'add item type e.g. iron_sword',
		Darker = true
	})

	BuyArmorToggle     = AutoBuy:CreateToggle({Name = 'Buy Armor',      Default = true})
	BuyAxeToggle       = AutoBuy:CreateToggle({Name = 'Buy Axe',        Default = false})
	BuyPickaxeToggle   = AutoBuy:CreateToggle({Name = 'Buy Pickaxe',    Default = false})
	BuyProjectileToggle = AutoBuy:CreateToggle({Name = 'Buy Projectile', Default = false})

	BreakSpeedToggle   = AutoBuy:CreateToggle({Name = 'Break Speed',  Default = false})
	ArmorUpgradeToggle = AutoBuy:CreateToggle({Name = 'Armor',        Default = false})
	DamageToggle       = AutoBuy:CreateToggle({Name = 'Damage',       Default = false})
	DiamondGenToggle   = AutoBuy:CreateToggle({Name = 'Diamond Gen',  Default = false})
	TeamGenToggle      = AutoBuy:CreateToggle({Name = 'Team Gen',     Default = false})
	BedBarrierToggle   = AutoBuy:CreateToggle({Name = 'Bed Barrier',  Default = false})

	task.defer(function()
		if BreakSpeedToggle   and BreakSpeedToggle.Object   then BreakSpeedToggle.Object.Visible   = false end
		if ArmorUpgradeToggle and ArmorUpgradeToggle.Object then ArmorUpgradeToggle.Object.Visible = false end
		if DamageToggle       and DamageToggle.Object       then DamageToggle.Object.Visible       = false end
		if DiamondGenToggle   and DiamondGenToggle.Object   then DiamondGenToggle.Object.Visible   = false end
		if TeamGenToggle      and TeamGenToggle.Object      then TeamGenToggle.Object.Visible      = false end
		if BedBarrierToggle   and BedBarrierToggle.Object   then BedBarrierToggle.Object.Visible   = false end
		if SmartCheck         and SmartCheck.Object         then SmartCheck.Object.Visible         = false end
		if KeepBuyingList     and KeepBuyingList.Object     then KeepBuyingList.Object.Visible     = false end
	end)
end)
	
run(function()
	local AutoConsume
	local Health
	local SpeedPotion
	local Apple
	local ShieldPotion
	local GoldenApple
	local GoldenAppleHealth
	local SpeedPie
	
	local function consumeCheck(attribute)
		if entitylib.isAlive then
			if SpeedPotion.Enabled and (not attribute or attribute == 'StatusEffect_speed') then
				local speedpotion = getItem('speed_potion')
				if speedpotion and (not lplr.Character:GetAttribute('StatusEffect_speed')) then
					task.spawn(function()
						for _ = 1, 4 do
							local result = false
							bedwars.Client:Get(remotes.ConsumeItem):CallServerAsync({item = speedpotion.tool}):andThen(function(r)
								result = r
							end):await()
							if result then break end
						end
					end)
				end
			end
	
			if Apple.Enabled and (not attribute or attribute:find('Health')) then
				if (lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) <= (Health.Value / 100) then
					local inv = replicatedStorage:FindFirstChild('Inventories') and replicatedStorage.Inventories:FindFirstChild(lplr.Name)
					local appleItem = inv and (inv:FindFirstChild('orange') or inv:FindFirstChild('apple'))
					if appleItem then
						replicatedStorage.rbxts_include.node_modules['@rbxts'].net.out._NetManaged.ConsumeItem:InvokeServer({item = appleItem})
					end
				end
			end

			if GoldenApple and GoldenApple.Enabled and (not attribute or attribute:find('Health')) then
				local gaHealth = GoldenAppleHealth and GoldenAppleHealth.Value or 50
				local currentHPPct = (lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth') * 100)
				local inv = replicatedStorage:FindFirstChild('Inventories') and replicatedStorage.Inventories:FindFirstChild(lplr.Name)
				local gaItem = inv and inv:FindFirstChild('golden_apple')
				if currentHPPct <= gaHealth and gaItem then
					replicatedStorage.rbxts_include.node_modules['@rbxts'].net.out._NetManaged.ConsumeItem:InvokeServer({item = gaItem})
				end
			end

			if SpeedPie and SpeedPie.Enabled then
				local speedPieActive = false
				local statusHud = lplr.PlayerGui:FindFirstChild('StatusEffectHudScreen')
				if statusHud then
					local hud = statusHud:FindFirstChild('StatusEffectHud')
					if hud then
						local speedPieFrame = hud:FindFirstChild('Speed Pie')
						if speedPieFrame then
							local timer = speedPieFrame:FindFirstChild('4')
							if timer and timer:IsA('TextLabel') then
								local val = tonumber(timer.Text)
								speedPieActive = val and val > 0
							end
						end
					end
				end
				if not speedPieActive then
					local inv = replicatedStorage:FindFirstChild('Inventories') and replicatedStorage.Inventories:FindFirstChild(lplr.Name)
					local pieItem = inv and inv:FindFirstChild('pie')
					if pieItem then
						replicatedStorage.rbxts_include.node_modules['@rbxts'].net.out._NetManaged.ConsumeItem:InvokeServer({item = pieItem})
					end
				end
			end

			if ShieldPotion.Enabled and (not attribute or attribute:find('Shield')) then
				if (lplr.Character:GetAttribute('Shield_POTION') or 0) == 0 then
					local shield = getItem('big_shield') or getItem('mini_shield')
	
					if shield then
						bedwars.Client:Get(remotes.ConsumeItem):CallServerAsync({
							item = shield.tool
						})
					end
				end
			end
		end
	end
	
	AutoConsume = vape.Categories.Inventory:CreateModule({
		Name = 'AutoConsume',
		Function = function(callback)
			if callback then
				local throttle = 0
				local throttledCheck = function()
					local now = tick()
					if now - throttle < 0.2 then return end
					throttle = now
					consumeCheck()
				end
				AutoConsume:Clean(vapeEvents.InventoryAmountChanged.Event:Connect(throttledCheck))
				AutoConsume:Clean(vapeEvents.AttributeChanged.Event:Connect(function(attribute)
					if attribute:find('Shield') or attribute:find('Health') then
						throttledCheck()
					end
				end))
				consumeCheck()
				task.spawn(function()
					while AutoConsume.Enabled do
						task.wait(0.5)
						if not SpeedPie or not SpeedPie.Enabled then continue end
						local speedPieActive = false
						local statusHud = lplr.PlayerGui:FindFirstChild('StatusEffectHudScreen')
						if statusHud then
							local hud = statusHud:FindFirstChild('StatusEffectHud')
							if hud then
								local speedPieFrame = hud:FindFirstChild('Speed Pie')
								if speedPieFrame then
									local timer = speedPieFrame:FindFirstChild('4')
									if timer and timer:IsA('TextLabel') then
										local val = tonumber(timer.Text)
										speedPieActive = val and val > 0
									end
								end
							end
						end
						if not speedPieActive then
							local inv = replicatedStorage:FindFirstChild('Inventories') and replicatedStorage.Inventories:FindFirstChild(lplr.Name)
							local pieItem = inv and inv:FindFirstChild('pie')
							if pieItem then
								replicatedStorage.rbxts_include.node_modules['@rbxts'].net.out._NetManaged.ConsumeItem:InvokeServer({item = pieItem})
							end
						end
					end
				end)
			end
		end,
		Tooltip = 'Automatically heals for you when health or shield is under threshold.'
	})
	SpeedPotion = AutoConsume:CreateToggle({
		Name = 'Speed Potions',
		Default = true
	})
	Apple = AutoConsume:CreateToggle({
		Name = 'Apple',
		Default = true,
		Function = function(callback)
			if Health then
				Health.Object.Visible = callback
			end
		end
	})
	Health = AutoConsume:CreateSlider({
		Name = 'Health Percent',
		Min = 1,
		Max = 99,
		Default = 70,
		Suffix = '%',
		Visible = false
	})
	ShieldPotion = AutoConsume:CreateToggle({
		Name = 'Shield Potions',
		Default = true
	})
	GoldenApple = AutoConsume:CreateToggle({
		Name = 'Golden Apple',
		Default = false,
		Function = function(callback)
			if GoldenAppleHealth then
				GoldenAppleHealth.Object.Visible = callback
			end
		end
	})
	GoldenAppleHealth = AutoConsume:CreateSlider({
		Name = 'Eat At HP%',
		Min = 1,
		Max = 99,
		Default = 50,
		Suffix = '%',
		Visible = false
	})
	SpeedPie = AutoConsume:CreateToggle({
		Name = 'Speed Pie',
		Default = false
	})
end)

run(function()
	local Value
	local oldclickhold, oldshowprogress
	
	local FastConsume = vape.Categories.Inventory:CreateModule({
		Name = 'FastConsume',
		Function = function(callback)
			if callback then
				oldclickhold = bedwars.ClickHold.startClick
				oldshowprogress = bedwars.ClickHold.showProgress
				bedwars.ClickHold.startClick = function(self)
					self.startedClickTime = tick()
					local handle = self:showProgress()
					local clicktime = self.startedClickTime
					bedwars.RuntimeLib.Promise.defer(function()
						task.wait(self.durationSeconds * (Value.Value / 40))
						if handle == self.handle and clicktime == self.startedClickTime and self.closeOnComplete then
							self:hideProgress()
							if self.onComplete then self.onComplete() end
							if self.onPartialComplete then self.onPartialComplete(1) end
							self.startedClickTime = -1
						end
					end)
				end
	
				bedwars.ClickHold.showProgress = function(self)
					local roact = debug.getupvalue(oldshowprogress, 1)
					local countdown = roact.mount(roact.createElement('ScreenGui', {}, { roact.createElement('Frame', {
						[roact.Ref] = self.wrapperRef,
						Size = UDim2.new(),
						Position = UDim2.fromScale(0.5, 0.55),
						AnchorPoint = Vector2.new(0.5, 0),
						BackgroundColor3 = Color3.fromRGB(0, 0, 0),
						BackgroundTransparency = 0.8
					}, { roact.createElement('Frame', {
						[roact.Ref] = self.progressRef,
						Size = UDim2.fromScale(0, 1),
						BackgroundColor3 = Color3.new(1, 1, 1),
						BackgroundTransparency = 0.5
					}) }) }), lplr:FindFirstChild('PlayerGui'))
	
					self.handle = countdown
					local sizetween = tweenService:Create(self.wrapperRef:getValue(), TweenInfo.new(0.1), {
						Size = UDim2.fromScale(0.11, 0.005)
					})
					local countdowntween = tweenService:Create(self.progressRef:getValue(), TweenInfo.new(self.durationSeconds * (Value.Value / 40), Enum.EasingStyle.Linear), {
						Size = UDim2.fromScale(1, 1)
					})
	
					sizetween:Play()
					countdowntween:Play()
					table.insert(self.tweens, countdowntween)
					table.insert(self.tweens, sizetween)
					
					return countdown
				end
			else
				bedwars.ClickHold.startClick = oldclickhold
				bedwars.ClickHold.showProgress = oldshowprogress
				oldclickhold = nil
				oldshowprogress = nil
			end
		end,
		Tooltip = 'Use/Consume items quicker.'
	})
	Value = FastConsume:CreateSlider({
		Name = 'Multiplier',
		Min = 0,
		Max = 100
	})
end)
	
run(function()
	local FastDrop
	local DropDelay
	local ItemList
	local UseBind
	local BBind
	local CurrentBind = Enum.KeyCode.H

	local function getInputEnum(inputName)
		if string.find(inputName, "MouseButton") then
			return Enum.UserInputType[inputName]
		else
			return Enum.KeyCode[inputName]
		end
	end

	local function isInputDown(input)
		if typeof(input) == "EnumItem" then
			if input.EnumType == Enum.KeyCode then
				return inputService:IsKeyDown(input)
			elseif input.EnumType == Enum.UserInputType then
				return inputService:IsMouseButtonPressed(input)
			end
		end
		return false
	end

	FastDrop = vape.Categories.Inventory:CreateModule({
		Name = 'FastDrop',
		Function = function(callback)
			if callback then

				repeat
					if entitylib.isAlive and (not store.inventory.opened) and (isInputDown(CurrentBind)) and inputService:GetFocusedTextBox() == nil then
						if tick() - store.lastDropTime >= (DropDelay.Value / 1000) then
							local handItem = store.hand and store.hand.tool
							if handItem then
								local itemType = handItem.Name
								local listEnabled = ItemList.ListEnabled
								
								local shouldDrop = true
								if #listEnabled > 0 then
									shouldDrop = table.find(listEnabled, itemType) ~= nil
								end
								
								if shouldDrop then
									task.spawn(bedwars.ItemDropController.dropItemInHand)
									store.lastDropTime = tick()
								end
							end
							task.wait()
						else
							task.wait(0.01)
						end
					else
						task.wait(0.1)
					end
				until not FastDrop.Enabled
			else
				store.lastDropTime = tick() + DropDelay.Value
			end
		end,
		Tooltip = 'Drops items fast'
	})

	DropDelay = FastDrop:CreateSlider({
		Name = 'Drop Delay',
		Min = 0,
		Max = 500,
		Default = 0,
		Suffix = 'ms'
	})
	
	ItemList = FastDrop:CreateTextList({
		Name = 'Item Whitelist',
		Placeholder = 'Item name (e.g., wool_blue)',
	})
end)
	
run(function()
    local BedPlates
    local Background
    local TeamColor
    local Color = {}
    local Reference = {}
    local BlockCache = {}
	local LayerCounter
	local LayerColor
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    
	local teamColors = {
		[1] = {name = "Blue",   color = Color3.fromRGB(85, 150, 255)},
		[2] = {name = "Orange", color = Color3.fromRGB(255, 150, 50)},
		[3] = {name = "Pink",   color = Color3.fromRGB(255, 100, 200)},
		[4] = {name = "Yellow", color = Color3.fromRGB(255, 255, 50)}
	}
    
    local function getBedTeamColor(bed)
        local teamId = bed:GetAttribute('TeamID')
        if teamId and teamColors[teamId] then
            return teamColors[teamId]
        end
        return Color3.new(1, 1, 1)
    end
    
    local function updateLayerTextColor()
		for _, billboard in pairs(Reference) do
			for _, img in billboard.Frame:GetChildren() do
				if img:IsA('ImageLabel') then
					local txt = img:FindFirstChild('Amount')
					if txt then
						txt.TextColor3 = LayerColor and Color3.fromHSV(LayerColor.Hue, LayerColor.Sat, LayerColor.Value) or Color3.fromRGB(250,250,250)
					end
				end
			end
		end
	end

    local function scanSide(self, start, tab)
		local checkDirs = {
			Vector3.new(3,0,0), Vector3.new(-3,0,0),
			Vector3.new(0,0,3), Vector3.new(0,0,-3),
			Vector3.new(0,3,0),
		}
		for _, side in ipairs(checkDirs) do
			for i = 1, 15 do
				local block = getPlacedBlock(start + (side * i))
				if not block or block == self or block.Name == 'bed' then break end
				if not block:GetAttribute('NoBreak') then
					tab[block.Name] = (tab[block.Name] or 0) + 1
				end
			end
		end
    end

	local function getBlockHealth(blck)
		local meta = bedwars.ItemMeta[blck]
		if not meta then  return 0 end
		local blockmeta = meta.block
		if not blockmeta then  return 0 end
		return blockmeta.health or 0
	end
    
    local function refreshAdornee(v)
		for _, obj in v.Frame:GetChildren() do
			if obj and (obj:IsA("ImageLabel") and obj.Name ~= 'Blur') then
				obj:Destroy()
			end
		end
		local start = v.Adornee.Position
		local layers = {}
		local founded = {}
		scanSide(v.Adornee, start, layers)
		scanSide(v.Adornee, start + Vector3.new(0,0,3), layers)
		for blocks, amount in layers do 
			table.insert(founded, {blocks, amount})
		end
		table.sort(founded, function(a,b)
			local healthA, healthB = getBlockHealth(a[1]), getBlockHealth(b[1])			
			return healthA == healthB and a[1] < b[1] or healthA > healthB
		end)
		v.Enabled = #founded > 0

		for _, data in founded do
			local block, amt = data[1], data[2]
			local image = Instance.new('ImageLabel')
			image.Size = UDim2.fromOffset(32,32)
			image.BackgroundTransparency = 1
			image.Image = bedwars.getIcon({itemType=block}, true)
			image.Parent = v.Frame
			if amt >= 8 and (not LayerCounter or LayerCounter.Enabled) then
				local txt = Instance.new('TextLabel')
				txt.Name = 'Amount'
				txt.Size = UDim2.fromScale(1,1)
				txt.BackgroundTransparency = 1
				local newamt = math.floor(amt / 6)
				txt.Text = tostring(newamt)
				txt.TextColor3 = LayerColor and Color3.fromHSV(LayerColor.Hue, LayerColor.Sat, LayerColor.Value) or Color3.fromRGB(250,250,250)
				txt.TextSize = 24
				txt.TextStrokeTransparency = 0.3
				txt.Font = Enum.Font.Arial
				txt.Parent = image
			end
		end
    end
    
    local function Added(v)
        if Reference[v] then return end
        local _bpUserId = v:GetAttribute('PlacedByUserId')
        if _bpUserId then
            local _bpOk, _bpOwner = pcall(function() return playersService:GetPlayerByUserId(_bpUserId) end)
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'bed'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        
        local blur = addBlur(billboard)
        blur.Visible = Background.Enabled
        
        local frame = Instance.new('Frame')
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = TeamColor.Enabled and getBedTeamColor(v) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
        frame.BackgroundTransparency = 1 - (Background.Enabled and (TeamColor.Enabled and 0.5 or Color.Opacity) or 0)
        frame.Parent = billboard
        
        local layout = Instance.new('UIListLayout')
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.Padding = UDim.new(0, 4)
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            billboard.Size = UDim2.fromOffset(math.max(layout.AbsoluteContentSize.X + 4, 36), 36)
        end)
        layout.Parent = frame
        
        local corner = Instance.new('UICorner')
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = frame
        
        Reference[v] = billboard
        BlockCache[v] = ""
        refreshAdornee(billboard)
    end
    
    local _refreshNearPending = false
    local function refreshNear(data)
        if _refreshNearPending then return end
        _refreshNearPending = true
        task.defer(function()
            _refreshNearPending = false
            local blockPos = data.blockRef.blockPosition * 3
            local maxDistanceSq = 30 * 30
            for bed, billboard in pairs(Reference) do
                if bed.Parent then
                    local offset = blockPos - bed.Position
                    local distanceSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
                    if distanceSq <= maxDistanceSq then
                        refreshAdornee(billboard)
                    end
                end
            end
        end)
    end
    
    BedPlates = vape.Categories.Minigames:CreateModule({
        Name = 'BedPlates',
        Function = function(callback)
            if callback then
                table.clear(BlockCache)
                
                local tagged = collectionService:GetTagged('bed')
                for _, v in ipairs(tagged) do 
                    Added(v)
                end
                
                BedPlates:Clean(vapeEvents.PlaceBlockEvent.Event:Connect(refreshNear))
                BedPlates:Clean(vapeEvents.BreakBlockEvent.Event:Connect(refreshNear))
                BedPlates:Clean(collectionService:GetInstanceAddedSignal('bed'):Connect(Added))
                BedPlates:Clean(collectionService:GetInstanceRemovedSignal('bed'):Connect(function(v)
                    if Reference[v] then
                        Reference[v]:Destroy()
                        Reference[v] = nil
                        BlockCache[v] = nil
                    end
                end))
            else
                for _, v in pairs(Reference) do
                    v:Destroy()
                end
                table.clear(Reference)
                table.clear(BlockCache)
            end
        end,
        Tooltip = 'shows enemys bed defence'
    })
    
    Background = BedPlates:CreateToggle({
        Name = 'Background',
        Function = function(callback)
            if Color.Object then 
                Color.Object.Visible = callback and not TeamColor.Enabled
            end
            for _, v in pairs(Reference) do
                v.Frame.BackgroundTransparency = 1 - (callback and (TeamColor.Enabled and 0.5 or Color.Opacity) or 0)
                local blur = v:FindFirstChild('Blur')
                if blur then
                    blur.Visible = callback
                end
            end
        end,
        Default = true
    })
    
    TeamColor = BedPlates:CreateToggle({
        Name = 'Team Color',
        Default = true,
        Function = function(callback)
            if Color.Object then
                Color.Object.Visible = Background.Enabled and not callback
            end
            for bed, billboard in pairs(Reference) do
                billboard.Frame.BackgroundColor3 = callback and getBedTeamColor(bed) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
                billboard.Frame.BackgroundTransparency = 1 - (Background.Enabled and (callback and 0.5 or Color.Opacity) or 0)
            end
        end
    })
    
    Color = BedPlates:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for bed, v in pairs(Reference) do
                if not TeamColor.Enabled then
                    v.Frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                end
                if Background.Enabled and not TeamColor.Enabled then
                    v.Frame.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Visible = false,
        Darker = true
    })

	LayerCounter = BedPlates:CreateToggle({
		Name = 'Layer Counter',
		Function = function(callback)
			if LayerColor and LayerColor.Object then
				LayerColor.Object.Visible = callback
			end
			for _, billboard in pairs(Reference) do
				refreshAdornee(billboard)
			end
		end,
		Default = true
	})
	LayerColor = BedPlates:CreateColorSlider({
		Name = 'Counter Text Color',
		DefaultSat = 0,
		DefaultValue = 1,
		Function = function()
			updateLayerTextColor()
		end,
		Visible = LayerCounter.Enabled
	})	
end)

run(function()
	local Headless
	local headlessLoop = nil

	local headAttachments = {HatAttachment=true,HairAttachment=true,FaceFrontAttachment=true,FaceCenterAttachment=true,FaceBackAttachment=true}
	local removeAccs = false

	local function applyHeadless(char)
		if not char then return end
		local head = char:FindFirstChild("Head")
		if not head then return end
		head.Transparency = 1
		local face = head:FindFirstChild('face')
		if face and face:IsA("Decal") then
			face.Transparency = 1
		end
		if removeAccs then
			for _, acc in ipairs(char:GetChildren()) do
				if acc:IsA("Accessory") then
					local handle = acc:FindFirstChild("Handle")
					if handle then
						for _, att in ipairs(handle:GetChildren()) do
							if att:IsA("Attachment") and headAttachments[att.Name] then
								handle.Transparency = 1
								for _, d in ipairs(handle:GetChildren()) do
									if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
								end
								break
							end
						end
					end
				end
			end
		end
	end

	Headless = vape.Categories.Utility:CreateModule({
		PerformanceModeBlacklisted = true,
		Name = 'Headless',
		Tooltip = 'free headless 2026!!',
		Function = function(callback)
			if callback then
				if headlessLoop then task.cancel(headlessLoop) end
				headlessLoop = task.spawn(function()
					while Headless.Enabled do
						applyHeadless(lplr.Character)
						task.wait(0.1)
					end
				end)
				Headless:Clean(lplr.CharacterAdded:Connect(function(char)
					applyHeadless(char)
				end))
			else
				if headlessLoop then
					task.cancel(headlessLoop)
					headlessLoop = nil
				end
				local char = lplr.Character
				if char then
					local head = char:FindFirstChild("Head")
					if head then
						head.Transparency = 0
						local face = head:FindFirstChild('face')
						if face and face:IsA("Decal") then
							face.Transparency = 0
						end
					end
					for _, acc in ipairs(char:GetChildren()) do
						if acc:IsA("Accessory") then
							local handle = acc:FindFirstChild("Handle")
							if handle then
								handle.Transparency = 0
								for _, d in ipairs(handle:GetChildren()) do
									if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 0 end
								end
							end
						end
					end
				end
			end
		end,
		Default = false
	})

	Headless:CreateToggle({
		Name = "Remove Accessories",
		Default = false,
		Function = function(state)
			removeAccs = state
			if Headless.Enabled then
				applyHeadless(lplr.Character)
			end
		end
	})
end)

local function safeIsBreakable(pos)
    if not bedwars.BlockController then return false end
    local ok, result = pcall(function()
        return bedwars.BlockController:isBlockBreakable({blockPosition = pos / 3}, lplr)
    end)
    return ok and result
end
	
run(function()
	local FPSBoost
	local Kill
	local Visualizer
	local effects, util = {}, {}
	local originalAddGameNametag
	local nametagHooked = false
	
	FPSBoost = vape.Categories.World:CreateModule({
		Name = 'FPSBoost',
		Function = function(callback)
			if callback then
				if Kill.Enabled then
					for i, v in bedwars.KillEffectController.killEffects do
						if not i:find('Custom') then
							effects[i] = v
							bedwars.KillEffectController.killEffects[i] = {
								new = function() 
									return {
										onKill = function() end, 
										isPlayDefaultKillEffect = function() 
											return true 
										end
									} 
								end
							}
						end
					end
				end

			if Visualizer.Enabled then
				local keepKeys = {'beam', 'Beam', 'projectile', 'Projectile', 'draw', 'Draw', 'line', 'Line', 'ray', 'Ray', 'arc', 'Arc'}
				for i, v in bedwars.VisualizerUtils do
					local keep = false
					for _, k in keepKeys do
						if tostring(i):lower():find(k:lower()) then
							keep = true
							break
						end
					end
					if not keep then
						util[i] = v
						bedwars.VisualizerUtils[i] = function() end
					end
				end
			end

			else
				for i, v in effects do 
					bedwars.KillEffectController.killEffects[i] = v 
				end
				
				for i, v in util do 
					bedwars.VisualizerUtils[i] = v 
				end
				
				if nametagHooked and originalAddGameNametag then
					bedwars.NametagController.addGameNametag = originalAddGameNametag
					nametagHooked = false
				end
				
				table.clear(effects)
				table.clear(util)
			end
		end,
		Tooltip = 'improves fps - well tries'
	})
	
	Kill = FPSBoost:CreateToggle({
		Name = 'Kill Effects',
		Function = function()
			if FPSBoost.Enabled then
				FPSBoost:Toggle()
				FPSBoost:Toggle()
			end
		end,
		Default = true
	})
	
	Visualizer = FPSBoost:CreateToggle({
		Name = 'Visualizer',
		Function = function()
			if FPSBoost.Enabled then
				FPSBoost:Toggle()
				FPSBoost:Toggle()
			end
		end,
		Default = true
	})
end)
	
run(function()
	local HitColor
	local Color
	local done = {}
	
	HitColor = vape.Categories.Legit:CreateModule({
		Name = 'HitColor',
		Function = function(callback)
			if callback then
				local function hookHighlight(v)
					local highlight = v.Character and v.Character:FindFirstChild('_DamageHighlight_')
					if highlight and not done[highlight] then
						highlight.FillColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
						highlight.FillTransparency = Color.Opacity
						done[highlight] = true
					end
				end
				for _, v in entitylib.List do hookHighlight(v) end
				HitColor:Clean(entitylib.Events.EntityAdded:Connect(hookHighlight))
			else
				for highlight in pairs(done) do
					if highlight and highlight.Parent then
						pcall(function()
							highlight.FillColor = Color3.new(1, 0, 0)
							highlight.FillTransparency = 0.4
						end)
					end
				end
				table.clear(done)
			end
		end,
		Tooltip = 'customize hit color'
	})
	Color = HitColor:CreateColorSlider({
		Name = 'Color',
		DefaultOpacity = 0.4
	})
end)

run(function()
    HitFix = vape.Categories.Legit:CreateModule({
        Name = 'HitFix',
		Function = function(callback)
			debug.setconstant(bedwars.SwordController.swingSwordAtMouse, 23, callback and 'raycast' or 'Raycast')
			debug.setupvalue(bedwars.SwordController.swingSwordAtMouse, 4, callback and bedwars.QueryUtil or workspace)
		end,
	})
end)

run(function()
	local Interface
	local HotbarOpenInventory = require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-open-inventory']).HotbarOpenInventory
	local HotbarHealthbar = require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui.healthbar['hotbar-healthbar']).HotbarHealthbar
	local HotbarApp = getRoactRender(require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-app']).HotbarApp.render)
	local old, new = {}, {}
	
	vape:Clean(function()
		for _, v in new do
			table.clear(v)
		end
		for _, v in old do
			table.clear(v)
		end
		table.clear(new)
		table.clear(old)
	end)
	
	local function modifyconstant(func, ind, val)
		if not func then return end
		if not old[func] then old[func] = {} end
		if not new[func] then new[func] = {} end
		if not old[func][ind] then
			old[func][ind] = debug.getconstant(func, ind)
		end
		if typeof(old[func][ind]) ~= typeof(val) then return end
		new[func][ind] = val
	
		if Interface.Enabled then
			if val then
				debug.setconstant(func, ind, val)
			else
				debug.setconstant(func, ind, old[func][ind])
				old[func][ind] = nil
			end
		end
	end
	
	Interface = vape.Categories.Legit:CreateModule({
		Name = 'Interface',
		Function = function(callback)
			for i, v in (callback and new or old) do
				for i2, v2 in v do
					debug.setconstant(i, i2, v2)
				end
			end
		end,
		Tooltip = 'Customize bedwars UI'
	})
	local fontitems = {'LuckiestGuy'}
	for _, v in Enum.Font:GetEnumItems() do
		if v.Name ~= 'LuckiestGuy' then
			table.insert(fontitems, v.Name)
		end
	end
	Interface:CreateDropdown({
		Name = 'Health Font',
		List = fontitems,
		Function = function(val)
			modifyconstant(HotbarHealthbar.render, 77, val)
		end
	})
	Interface:CreateColorSlider({
		Name = 'Health Color',
		Function = function(hue, sat, val)
			modifyconstant(HotbarHealthbar.render, 16, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
			if Interface.Enabled then
				local hotbar = lplr.PlayerGui:FindFirstChild('hotbar')
				hotbar = hotbar and hotbar:FindFirstChild('HealthbarProgressWrapper', true)
				if hotbar then
					hotbar['1'].BackgroundColor3 = Color3.fromHSV(hue, sat, val)
				end
			end
		end
	})
	Interface:CreateColorSlider({
		Name = 'Hotbar Color',
		DefaultOpacity = 0.8,
		Function = function(hue, sat, val, opacity)
			local func = oldinvrender or HotbarOpenInventory.render
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 51, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 58, tonumber(Color3.fromHSV(hue, sat, math.clamp(val > 0.5 and val - 0.2 or val + 0.2, 0, 1)):ToHex(), 16))
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 54, 1 - opacity)
			modifyconstant(debug.getupvalue(HotbarApp, 23).render, 55, math.clamp(1.2 - opacity, 0, 1))
			modifyconstant(func, 31, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
			modifyconstant(func, 32, math.clamp(1.2 - opacity, 0, 1))
			modifyconstant(func, 34, tonumber(Color3.fromHSV(hue, sat, math.clamp(val > 0.5 and val - 0.2 or val + 0.2, 0, 1)):ToHex(), 16))
		end
	})
end)
	
run(function()
	local KillEffect
	local Mode
	local List
	local NameToId = {}
	
	local killeffects = {
		Gravity = function(_, _, char, _)
			char:BreakJoints()
			local highlight = char:FindFirstChildWhichIsA('Highlight')
			local nametag = char:FindFirstChild('Nametag', true)
			if highlight then
				highlight:Destroy()
			end
			if nametag then
				nametag:Destroy()
			end
	
			task.spawn(function()
				local partvelo = {}
				for _, v in char:GetDescendants() do
					if v:IsA('BasePart') then
						partvelo[v.Name] = v.Velocity
					end
				end
				char.Archivable = true
				local clone = char:Clone()
				clone.Humanoid.Health = 100
				clone.Parent = workspace
				game:GetService('Debris'):AddItem(clone, 30)
				char:Destroy()
				task.wait(0.01)
				clone.Humanoid:ChangeState(Enum.HumanoidStateType.Dead)
				clone:BreakJoints()
				task.wait(0.01)
				for _, v in clone:GetDescendants() do
					if v:IsA('BasePart') then
						local bodyforce = Instance.new('BodyForce')
						bodyforce.Force = Vector3.new(0, (workspace.Gravity - 10) * v:GetMass(), 0)
						bodyforce.Parent = v
						v.CanCollide = true
						v.Velocity = partvelo[v.Name] or Vector3.zero
					end
				end
			end)
		end,
		Lightning = function(_, _, char, _)
			char:BreakJoints()
			local highlight = char:FindFirstChildWhichIsA('Highlight')
			if highlight then
				highlight:Destroy()
			end
			local startpos = 1125
			local startcf = char.PrimaryPart.CFrame.p - Vector3.new(0, 8, 0)
			local newpos = Vector3.new((math.random(1, 10) - 5) * 2, startpos, (math.random(1, 10) - 5) * 2)
	
			for i = startpos - 75, 0, -75 do
				local newpos2 = Vector3.new((math.random(1, 10) - 5) * 2, i, (math.random(1, 10) - 5) * 2)
				if i == 0 then
					newpos2 = Vector3.zero
				end
				local part = Instance.new('Part')
				part.Size = Vector3.new(1.5, 1.5, 77)
				part.Material = Enum.Material.SmoothPlastic
				part.Anchored = true
				part.Material = Enum.Material.Neon
				part.CanCollide = false
				part.CFrame = CFrame.new(startcf + newpos + ((newpos2 - newpos) * 0.5), startcf + newpos2)
				part.Parent = workspace
				local part2 = part:Clone()
				part2.Size = Vector3.new(3, 3, 78)
				part2.Color = Color3.new(0.7, 0.7, 0.7)
				part2.Transparency = 0.7
				part2.Material = Enum.Material.SmoothPlastic
				part2.Parent = workspace
				game:GetService('Debris'):AddItem(part, 0.5)
				game:GetService('Debris'):AddItem(part2, 0.5)
				bedwars.QueryUtil:setQueryIgnored(part, true)
				bedwars.QueryUtil:setQueryIgnored(part2, true)
				if i == 0 then
					local soundpart = Instance.new('Part')
					soundpart.Transparency = 1
					soundpart.Anchored = true
					soundpart.Size = Vector3.zero
					soundpart.Position = startcf
					soundpart.Parent = workspace
					bedwars.QueryUtil:setQueryIgnored(soundpart, true)
					local sound = Instance.new('Sound')
					sound.SoundId = 'rbxassetid://6993372814'
					sound.Volume = 2
					sound.Pitch = 0.5 + (math.random(1, 3) / 10)
					sound.Parent = soundpart
					sound:Play()
					sound.Ended:Connect(function()
						soundpart:Destroy()
					end)
				end
				newpos = newpos2
			end
		end,
		Delete = function(_, _, char, _)
			char:Destroy()
		end
	}
	
	KillEffect = vape.Categories.Legit:CreateModule({
		Name = 'KillEffect',
		Function = function(callback)
			if callback then
				for i, v in killeffects do
					bedwars.KillEffectController.killEffects['Custom'..i] = {
						new = function()
							return {
								onKill = v,
								isPlayDefaultKillEffect = function()
									return false
								end
							}
						end
					}
				end
				KillEffect:Clean(lplr:GetAttributeChangedSignal('KillEffectType'):Connect(function()
					lplr:SetAttribute('KillEffectType', Mode.Value == 'Bedwars' and NameToId[List.Value] or 'Custom'..Mode.Value)
				end))
				lplr:SetAttribute('KillEffectType', Mode.Value == 'Bedwars' and NameToId[List.Value] or 'Custom'..Mode.Value)
			else
				for i in killeffects do
					bedwars.KillEffectController.killEffects['Custom'..i] = nil
				end
				lplr:SetAttribute('KillEffectType', 'default')
			end
		end,
		Tooltip = 'Custom final kill effects'
	})
	local modes = {'Bedwars'}
	for i in killeffects do
		table.insert(modes, i)
	end
	Mode = KillEffect:CreateDropdown({
		Name = 'Mode',
		List = modes,
		Function = function(val)
			List.Object.Visible = val == 'Bedwars'
			if KillEffect.Enabled then
				lplr:SetAttribute('KillEffectType', val == 'Bedwars' and NameToId[List.Value] or 'Custom'..val)
			end
		end
	})
	local KillEffectName = {}
	for i, v in bedwars.KillEffectMeta do
		table.insert(KillEffectName, v.name)
		NameToId[v.name] = i
	end
	table.sort(KillEffectName)
    List = KillEffect:CreateDropdown({
        Name = 'Bedwars',
        List = KillEffectName,
        Function = function(val)
            if KillEffect.Enabled then
                lplr:SetAttribute('KillEffectType', NameToId[val])
            end
        end,
        Darker = true
    })

    task.defer(function()
        if List and List.Object then
            List.Object.Visible = (Mode.Value == 'Bedwars')
        end
    end)
end)
	
run(function()
    local WinEffect
    local List
    local NameToId = {}
    
    WinEffect = vape.Categories.Legit:CreateModule({
        Name = "WinEffect",
        Function = function(callback)
            if callback then
                WinEffect:Clean(vapeEvents.MatchEndEvent.Event:Connect(function()
                    local remote = bedwars.Client:Get(remotes.WinEffectTriggered).instance
                    local payload = {
                        winEffectType = NameToId[List.Value],
                        winningPlayer = lplr
                    }
                    local ok = pcall(function()
                        remote.OnClientEvent:Fire(payload)
                    end)
                    if not ok then
                        for _, v in getconnections(remote.OnClientEvent) do
                            local fn = v.Function or v.Callback or v[1]
                            if fn then pcall(fn, payload) end
                        end
                    end
                end))
            end
        end,
        Tooltip = "select any clientside win effect"
    })
    
    local WinEffectName = {}
    for i, v in bedwars.WinEffectMeta do
        table.insert(WinEffectName, v.name)
        NameToId[v.name] = i
    end
    table.sort(WinEffectName)
    
    List = WinEffect:CreateDropdown({
        Name = "Effects",
        List = WinEffectName
    })
end)

run(function()
	local EmptyGameTP
	EmptyGameTP = vape.Categories.Utility:CreateModule({
		Name = "EmptyGameTP",
		Function = function(callback)
			if callback then
				EmptyGameTP:Toggle(false)
				local TeleportService = game:GetService("TeleportService")
				TeleportService:Teleport(game.PlaceId, lplr)
			end
		end,
	})
end)

run(function()
	local ViewMatchHistory
	ViewMatchHistory = vape.Categories.Utility:CreateModule({
		Name = "ViewMatchHistory",
		Function = function(callback)
			if callback then
				ViewMatchHistory:Toggle(false)
				local d = nil
				bedwars.MatchHistroyController:requestMatchHistory(lplr.Name):andThen(function(Data)
					if Data then
						bedwars.AppController:openApp({app = bedwars.MatchHistroyApp,appId = "MatchHistoryApp",},Data)
					end
				end)
			else
				return
			end
		end,
	})																								
end)

run(function()
	local AutoHotbar
	local Mode
	local Clear
	local List
	local Active
	
	local function CreateWindow(self)
		local selectedslot = 1
		local window = Instance.new('Frame')
		window.Name = 'HotbarGUI'
		window.Size = UDim2.fromOffset(660, 465)
		window.Position = UDim2.fromScale(0.5, 0.5)
		window.BackgroundColor3 = uipallet.Main
		window.AnchorPoint = Vector2.new(0.5, 0.5)
		window.Visible = false
		window.Parent = vape.gui.ScaledGui
		local title = Instance.new('TextLabel')
		title.Name = 'Title'
		title.Size = UDim2.new(1, -10, 0, 20)
		title.Position = UDim2.fromOffset(math.abs(title.Size.X.Offset), 12)
		title.BackgroundTransparency = 1
		title.Text = 'AutoHotbar'
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = uipallet.Text
		title.TextSize = 13
		title.FontFace = uipallet.Font
		title.Parent = window
		local divider = Instance.new('Frame')
		divider.Name = 'Divider'
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.Position = UDim2.fromOffset(0, 40)
		divider.BackgroundColor3 = color.Light(uipallet.Main, 0.04)
		divider.BorderSizePixel = 0
		divider.Parent = window
		addBlur(window)
		local modal = Instance.new('TextButton')
		modal.Text = ''
		modal.BackgroundTransparency = 1
		modal.Modal = true
		modal.Parent = window
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = window
		local close = Instance.new('ImageButton')
		close.Name = 'Close'
		close.Size = UDim2.fromOffset(24, 24)
		close.Position = UDim2.new(1, -35, 0, 9)
		close.BackgroundColor3 = Color3.new(1, 1, 1)
		close.BackgroundTransparency = 1
		close.Image = getcustomasset('newvape/assets/new/close.png')
		close.ImageColor3 = color.Light(uipallet.Text, 0.2)
		close.ImageTransparency = 0.5
		close.AutoButtonColor = false
		close.Parent = window
		close.MouseEnter:Connect(function()
			close.ImageTransparency = 0.3
			tween:Tween(close, TweenInfo.new(0.2), {
				BackgroundTransparency = 0.6
			})
		end)
		close.MouseLeave:Connect(function()
			close.ImageTransparency = 0.5
			tween:Tween(close, TweenInfo.new(0.2), {
				BackgroundTransparency = 1
			})
		end)
		close.MouseButton1Click:Connect(function()
			window.Visible = false
			vape.gui.ScaledGui.ClickGui.Visible = true
		end)
		local closecorner = Instance.new('UICorner')
		closecorner.CornerRadius = UDim.new(1, 0)
		closecorner.Parent = close
		local bigslot = Instance.new('Frame')
		bigslot.Size = UDim2.fromOffset(110, 111)
		bigslot.Position = UDim2.fromOffset(11, 71)
		bigslot.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
		bigslot.Parent = window
		local bigslotcorner = Instance.new('UICorner')
		bigslotcorner.CornerRadius = UDim.new(0, 4)
		bigslotcorner.Parent = bigslot
		local bigslotstroke = Instance.new('UIStroke')
		bigslotstroke.Color = color.Light(uipallet.Main, 0.034)
		bigslotstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bigslotstroke.Parent = bigslot
		local slotnum = Instance.new('TextLabel')
		slotnum.Size = UDim2.fromOffset(80, 20)
		slotnum.Position = UDim2.fromOffset(25, 200)
		slotnum.BackgroundTransparency = 1
		slotnum.Name = 'SlotNum'
		slotnum.Text = 'SLOT 1'
		slotnum.TextColor3 = color.Dark(uipallet.Text, 0.1)
		slotnum.TextSize = 12
		slotnum.FontFace = uipallet.Font
		slotnum.Parent = window
		for i = 1, 9 do
			local slotbkg = Instance.new('TextButton')
			slotbkg.Name = 'Slot'..i
			slotbkg.Size = UDim2.fromOffset(51, 52)
			slotbkg.Position = UDim2.fromOffset(89 + (i * 55), 382)
			slotbkg.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
			slotbkg.Text = ''
			slotbkg.AutoButtonColor = false
			slotbkg.Parent = window
			local slotimage = Instance.new('ImageLabel')
			slotimage.Size = UDim2.fromOffset(32, 32)
			slotimage.Position = UDim2.new(0.5, -16, 0.5, -16)
			slotimage.BackgroundTransparency = 1
			slotimage.Image = ''
			slotimage.Parent = slotbkg
			local slotcorner = Instance.new('UICorner')
			slotcorner.CornerRadius = UDim.new(0, 4)
			slotcorner.Parent = slotbkg
			local slotstroke = Instance.new('UIStroke')
			slotstroke.Color = color.Light(uipallet.Main, 0.04)
			slotstroke.Thickness = 2
			slotstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			slotstroke.Enabled = i == selectedslot
			slotstroke.Parent = slotbkg
			slotbkg.MouseEnter:Connect(function()
				slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
			end)
			slotbkg.MouseLeave:Connect(function()
				slotbkg.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
			end)
			slotbkg.MouseButton1Click:Connect(function()
				window['Slot'..selectedslot].UIStroke.Enabled = false
				selectedslot = i
				slotstroke.Enabled = true
				slotnum.Text = 'SLOT '..selectedslot
			end)
			slotbkg.MouseButton2Click:Connect(function()
				local obj = self.Hotbars[self.Selected]
				if obj then
					window['Slot'..i].ImageLabel.Image = ''
					obj.Hotbar[tostring(i)] = nil
					obj.Object['Slot'..i].Image = '	'
				end
			end)
		end
		local searchbkg = Instance.new('Frame')
		searchbkg.Size = UDim2.fromOffset(496, 31)
		searchbkg.Position = UDim2.fromOffset(142, 80)
		searchbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
		searchbkg.Parent = window
		local search = Instance.new('TextBox')
		search.Size = UDim2.new(1, -10, 0, 31)
		search.Position = UDim2.fromOffset(10, 0)
		search.BackgroundTransparency = 1
		search.Text = ''
		search.PlaceholderText = ''
		search.TextXAlignment = Enum.TextXAlignment.Left
		search.TextColor3 = uipallet.Text
		search.TextSize = 12
		search.FontFace = uipallet.Font
		search.ClearTextOnFocus = false
		search.Parent = searchbkg
		local searchcorner = Instance.new('UICorner')
		searchcorner.CornerRadius = UDim.new(0, 4)
		searchcorner.Parent = searchbkg
		local searchicon = Instance.new('ImageLabel')
		searchicon.Size = UDim2.fromOffset(14, 14)
		searchicon.Position = UDim2.new(1, -26, 0, 8)
		searchicon.BackgroundTransparency = 1
		searchicon.Image = getcustomasset('newvape/assets/new/search.png')
		searchicon.ImageColor3 = color.Light(uipallet.Main, 0.37)
		searchicon.Parent = searchbkg
		local children = Instance.new('ScrollingFrame')
		children.Name = 'Children'
		children.Size = UDim2.fromOffset(500, 240)
		children.Position = UDim2.fromOffset(144, 122)
		children.BackgroundTransparency = 1
		children.BorderSizePixel = 0
		children.ScrollBarThickness = 2
		children.ScrollBarImageTransparency = 0.75
		children.CanvasSize = UDim2.new()
		children.Parent = window
		local windowlist = Instance.new('UIGridLayout')
		windowlist.SortOrder = Enum.SortOrder.LayoutOrder
		windowlist.FillDirectionMaxCells = 9
		windowlist.CellSize = UDim2.fromOffset(51, 52)
		windowlist.CellPadding = UDim2.fromOffset(4, 3)
		windowlist.Parent = children
		windowlist:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			children.CanvasSize = UDim2.fromOffset(0, windowlist.AbsoluteContentSize.Y / vape.guiscale.Scale)
		end)
		table.insert(vape.Windows, window)
	
		local function createitem(id, image)
			local slotbkg = Instance.new('TextButton')
			slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.02)
			slotbkg.Text = ''
			slotbkg.AutoButtonColor = false
			slotbkg.Parent = children
			local slotimage = Instance.new('ImageLabel')
			slotimage.Size = UDim2.fromOffset(32, 32)
			slotimage.Position = UDim2.new(0.5, -16, 0.5, -16)
			slotimage.BackgroundTransparency = 1
			slotimage.Image = image
			slotimage.Parent = slotbkg
			local slotcorner = Instance.new('UICorner')
			slotcorner.CornerRadius = UDim.new(0, 4)
			slotcorner.Parent = slotbkg
			slotbkg.MouseEnter:Connect(function()
				slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.04)
			end)
			slotbkg.MouseLeave:Connect(function()
				slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.02)
			end)
			slotbkg.MouseButton1Click:Connect(function()
				local obj = self.Hotbars[self.Selected]
				if obj then
					window['Slot'..selectedslot].ImageLabel.Image = image
					obj.Hotbar[tostring(selectedslot)] = id
					obj.Object['Slot'..selectedslot].Image = image
				end
			end)
		end
	
		local function indexSearch(text)
			for _, v in children:GetChildren() do
				if v:IsA('TextButton') then
					v:ClearAllChildren()
					v:Destroy()
				end
			end
	
			if text == '' then
				for _, v in {'diamond_sword', 'diamond_pickaxe', 'diamond_axe', 'shears', 'wood_bow', 'wool_white', 'fireball', 'apple', 'iron', 'gold', 'diamond', 'emerald'} do
					createitem(v, bedwars.ItemMeta[v].image)
				end
				return
			end
	
			for i, v in bedwars.ItemMeta do
				if text:lower() == i:lower():sub(1, text:len()) then
					if not v.image then continue end
					createitem(i, v.image)
				end
			end
		end
	
		search:GetPropertyChangedSignal('Text'):Connect(function()
			indexSearch(search.Text)
		end)
		indexSearch('')
	
		return window
	end
	
	vape.Components.HotbarList = function(optionsettings, children, api)
		if vape.ThreadFix then
			setthreadidentity(8)
		end
		local optionapi = {
			Type = 'HotbarList',
			Hotbars = {},
			Selected = 1
		}
		local hotbarlist = Instance.new('TextButton')
		hotbarlist.Name = 'HotbarList'
		hotbarlist.Size = UDim2.fromOffset(220, 40)
		hotbarlist.BackgroundColor3 = optionsettings.Darker and (children.BackgroundColor3 == color.Dark(uipallet.Main, 0.02) and color.Dark(uipallet.Main, 0.04) or color.Dark(uipallet.Main, 0.02)) or children.BackgroundColor3
		hotbarlist.Text = ''
		hotbarlist.BorderSizePixel = 0
		hotbarlist.AutoButtonColor = false
		hotbarlist.Parent = children
		local textbkg = Instance.new('Frame')
		textbkg.Name = 'BKG'
		textbkg.Size = UDim2.new(1, -20, 0, 31)
		textbkg.Position = UDim2.fromOffset(10, 4)
		textbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
		textbkg.Parent = hotbarlist
		local textbkgcorner = Instance.new('UICorner')
		textbkgcorner.CornerRadius = UDim.new(0, 4)
		textbkgcorner.Parent = textbkg
		local textbutton = Instance.new('TextButton')
		textbutton.Name = 'HotbarList'
		textbutton.Size = UDim2.new(1, -2, 1, -2)
		textbutton.Position = UDim2.fromOffset(1, 1)
		textbutton.BackgroundColor3 = uipallet.Main
		textbutton.Text = ''
		textbutton.AutoButtonColor = false
		textbutton.Parent = textbkg
		textbutton.MouseEnter:Connect(function()
			tween:Tween(textbkg, TweenInfo.new(0.2), {
				BackgroundColor3 = color.Light(uipallet.Main, 0.14)
			})
		end)
		textbutton.MouseLeave:Connect(function()
			tween:Tween(textbkg, TweenInfo.new(0.2), {
				BackgroundColor3 = color.Light(uipallet.Main, 0.034)
			})
		end)
		local textbuttoncorner = Instance.new('UICorner')
		textbuttoncorner.CornerRadius = UDim.new(0, 4)
		textbuttoncorner.Parent = textbutton
		local textbuttonicon = Instance.new('ImageLabel')
		textbuttonicon.Size = UDim2.fromOffset(12, 12)
		textbuttonicon.Position = UDim2.fromScale(0.5, 0.5)
		textbuttonicon.AnchorPoint = Vector2.new(0.5, 0.5)
		textbuttonicon.BackgroundTransparency = 1
		textbuttonicon.Image = getcustomasset('newvape/assets/new/add.png')
		textbuttonicon.ImageColor3 = Color3.fromHSV(0.46, 0.96, 0.52)
		textbuttonicon.Parent = textbutton
		local childrenlist = Instance.new('Frame')
		childrenlist.Size = UDim2.new(1, 0, 1, -40)
		childrenlist.Position = UDim2.fromOffset(0, 40)
		childrenlist.BackgroundTransparency = 1
		childrenlist.Parent = hotbarlist
		local windowlist = Instance.new('UIListLayout')
		windowlist.SortOrder = Enum.SortOrder.LayoutOrder
		windowlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
		windowlist.Padding = UDim.new(0, 3)
		windowlist.Parent = childrenlist
		windowlist:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			if vape.ThreadFix then
				setthreadidentity(8)
			end
			hotbarlist.Size = UDim2.fromOffset(220, math.min(43 + windowlist.AbsoluteContentSize.Y / vape.guiscale.Scale, 603))
		end)
		optionapi.Window = CreateWindow(optionapi)
	
		function optionapi:Save(savetab)
			local hotbars = {}
			for _, v in self.Hotbars do
				table.insert(hotbars, v.Hotbar)
			end
			savetab.HotbarList = {
				Selected = self.Selected,
				Hotbars = hotbars
			}
		end
	
		function optionapi:Load(savetab)
			for _, v in self.Hotbars do
				v.Object:ClearAllChildren()
				v.Object:Destroy()
				table.clear(v.Hotbar)
			end
			table.clear(self.Hotbars)
			for _, v in savetab.Hotbars do
				self:AddHotbar(v)
			end
			self.Selected = savetab.Selected or 1
		end
	
		textbutton.MouseButton1Click:Connect(function()
		optionapi:AddHotbar()
	end)
	function optionapi:AddHotbar(data)
		local hotbardata = {Hotbar = data or {}}
			table.insert(self.Hotbars, hotbardata)
			local hotbar = Instance.new('TextButton')
			hotbar.Size = UDim2.fromOffset(200, 27)
			hotbar.BackgroundColor3 = table.find(self.Hotbars, hotbardata) == self.Selected and color.Light(uipallet.Main, 0.034) or uipallet.Main
			hotbar.Text = ''
			hotbar.AutoButtonColor = false
			hotbar.Parent = childrenlist
			hotbardata.Object = hotbar
			local hotbarcorner = Instance.new('UICorner')
			hotbarcorner.CornerRadius = UDim.new(0, 4)
			hotbarcorner.Parent = hotbar
			for i = 1, 9 do
				local slot = Instance.new('ImageLabel')
				slot.Name = 'Slot'..i
				slot.Size = UDim2.fromOffset(17, 18)
				slot.Position = UDim2.fromOffset(-7 + (i * 18), 5)
				slot.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
				slot.Image = hotbardata.Hotbar[tostring(i)] and bedwars.getIcon({itemType = hotbardata.Hotbar[tostring(i)]}, true) or ''
				slot.BorderSizePixel = 0
				slot.Parent = hotbar
			end
			hotbar.MouseButton1Click:Connect(function()
				local ind = table.find(optionapi.Hotbars, hotbardata)
				if ind == optionapi.Selected then
					vape.gui.ScaledGui.ClickGui.Visible = false
					optionapi.Window.Visible = true
					for i = 1, 9 do
						optionapi.Window['Slot'..i].ImageLabel.Image = hotbardata.Hotbar[tostring(i)] and bedwars.getIcon({itemType = hotbardata.Hotbar[tostring(i)]}, true) or ''
					end
				else
					if optionapi.Hotbars[optionapi.Selected] then
						optionapi.Hotbars[optionapi.Selected].Object.BackgroundColor3 = uipallet.Main
					end
					hotbar.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
					optionapi.Selected = ind
				end
			end)
			local close = Instance.new('ImageButton')
			close.Name = 'Close'
			close.Size = UDim2.fromOffset(16, 16)
			close.Position = UDim2.new(1, -23, 0, 6)
			close.BackgroundColor3 = Color3.new(1, 1, 1)
			close.BackgroundTransparency = 1
			close.Image = getcustomasset('newvape/assets/new/closemini.png')
			close.ImageColor3 = color.Light(uipallet.Text, 0.2)
			close.ImageTransparency = 0.5
			close.AutoButtonColor = false
			close.Parent = hotbar
			local closecorner = Instance.new('UICorner')
			closecorner.CornerRadius = UDim.new(1, 0)
			closecorner.Parent = close
			close.MouseEnter:Connect(function()
				close.ImageTransparency = 0.3
				tween:Tween(close, TweenInfo.new(0.2), {
					BackgroundTransparency = 0.6
				})
			end)
			close.MouseLeave:Connect(function()
				close.ImageTransparency = 0.5
				tween:Tween(close, TweenInfo.new(0.2), {
					BackgroundTransparency = 1
				})
			end)
			close.MouseButton1Click:Connect(function()
				local ind = table.find(self.Hotbars, hotbardata)
				local obj = self.Hotbars[self.Selected]
				local obj2 = self.Hotbars[ind]
				if obj and obj2 then
					obj2.Object:ClearAllChildren()
					obj2.Object:Destroy()
					table.remove(self.Hotbars, ind)
					ind = table.find(self.Hotbars, obj)
					self.Selected = table.find(self.Hotbars, obj) or 1
				end
			end)
		end
	
		api.Options.HotbarList = optionapi
	
		return optionapi
	end
	
	local function getBlock()
		local clone = table.clone(store.inventory.inventory.items)
		table.sort(clone, function(a, b)
			return a.amount < b.amount
		end)
	
		for _, item in clone do
			local block = bedwars.ItemMeta[item.itemType].block
			if block and not block.seeThrough then
				return item
			end
		end
	end
	
	local function getCustomItem(v)
		if v == 'diamond_sword' then
			local sword = store.tools.sword
			v = sword and sword.itemType or 'wood_sword'
		elseif v == 'diamond_pickaxe' then
			local pickaxe = store.tools.stone
			v = pickaxe and pickaxe.itemType or 'wood_pickaxe'
		elseif v == 'diamond_axe' then
			local axe = store.tools.wood
			v = axe and axe.itemType or 'wood_axe'
		elseif v == 'wood_bow' then
			local bow = getBow()
			v = bow and bow.itemType or 'wood_bow'
		elseif v == 'wool_white' then
			local block = getBlock()
			v = block and block.itemType or 'wool_white'
		end
	
		return v
	end
	
	local function findItemInTable(tab, item)
		for slot, v in tab do
			if item.itemType == getCustomItem(v) then
				return tonumber(slot)
			end
		end
	end
	
	local function findInHotbar(item)
		for i, v in store.inventory.hotbar do
			if v.item and v.item.itemType == item.itemType then
				return i - 1, v.item
			end
		end
	end
	
	local function findInInventory(item)
		for _, v in store.inventory.inventory.items do
			if v.itemType == item.itemType then
				return v
			end
		end
	end
	
	local function dispatch(...)
		bedwars.Store:dispatch(...)
		vapeEvents.InventoryChanged.Event:Wait()
	end
	
	local function sortCallback()
		if Active then return end
		Active = true
		local items = (List.Hotbars[List.Selected] and List.Hotbars[List.Selected].Hotbar or {})
	
		for _, v in store.inventory.inventory.items do
			local slot = findItemInTable(items, v)
			if slot then
				local olditem = store.inventory.hotbar[slot]
				if olditem.item and olditem.item.itemType == v.itemType then continue end
				if olditem.item then
					dispatch({
						type = 'InventoryRemoveFromHotbar',
						slot = slot - 1
					})
				end
	
				local newslot = findInHotbar(v)
				if newslot then
					dispatch({
						type = 'InventoryRemoveFromHotbar',
						slot = newslot
					})
					if olditem.item then
						dispatch({
							type = 'InventoryAddToHotbar',
							item = findInInventory(olditem.item),
							slot = newslot
						})
					end
				end
	
				dispatch({
					type = 'InventoryAddToHotbar',
					item = findInInventory(v),
					slot = slot - 1
				})
			elseif Clear.Enabled then
				local newslot = findInHotbar(v)
				if newslot then
				   	dispatch({
						type = 'InventoryRemoveFromHotbar',
						slot = newslot
					})
				end
			end
		end
	
		Active = false
	end
	
	AutoHotbar = vape.Categories.Inventory:CreateModule({
		Name = 'AutoHotbar',
		Function = function(callback)
			if callback then
				task.spawn(sortCallback)
				if Mode.Value == 'On Key' then
					AutoHotbar:Toggle()
					return
				end
	
				AutoHotbar:Clean(vapeEvents.InventoryAmountChanged.Event:Connect(sortCallback))
			end
		end,
		Tooltip = 'arranges your hotbar based off what u want'
	})
	Mode = AutoHotbar:CreateDropdown({
		Name = 'Activation',
		List = {'Toggle', 'On Key'},
		Function = function()
			if AutoHotbar.Enabled then
				AutoHotbar:Toggle()
				AutoHotbar:Toggle()
			end
		end
	})
	Clear = AutoHotbar:CreateToggle({Name = 'Clear Hotbar'})
	List = AutoHotbar:CreateHotbarList({})
end)

run(function()
    local BCR
    local Value
    local CpsConstants = nil
    
    BCR = vape.Categories.Blatant:CreateModule({
        Name = "BlockCPSRemover",
        Function = function(callback)
            
            if callback then
                task.wait(1)
                
                pcall(function()
                    CpsConstants = require(replicatedStorage.TS['shared-constants']).CpsConstants
                end)
                
                if not CpsConstants then
                    pcall(function()
                        CpsConstants = bedwars.CpsConstants
                    end)
                end
                
                if CpsConstants then
                    local newCPS = Value.Value == 0 and 1000 or Value.Value
                    CpsConstants.BLOCK_PLACE_CPS = newCPS
                    
                    if isMobile then
                        for _, v in {'2', '5'} do
                            pcall(function()
                                BCR:Clean(lplr.PlayerGui.MobileUI[v].MouseButton1Down:Connect(function()
                                    if CpsConstants then
                                        local currentValue = Value.Value == 0 and 1000 or Value.Value
                                        CpsConstants.BLOCK_PLACE_CPS = currentValue
                                    end
                                end))
                            end)
                        end
                    end
                    
                    task.spawn(function()
                        while BCR.Enabled do
                            local currentValue = Value.Value == 0 and 1000 or Value.Value
                            if CpsConstants.BLOCK_PLACE_CPS ~= currentValue then
                                CpsConstants.BLOCK_PLACE_CPS = currentValue
                            end
                            task.wait(0.3)
                        end
                    end)
                end
                
            else
                if CpsConstants then
                    CpsConstants.BLOCK_PLACE_CPS = 12
                end
            end
        end,
        Tooltip = 'place blocks faster'
    })
    
    Value = BCR:CreateSlider({
        Name = "CPS Limit",
        Suffix = "CPS",
        Default = 12,
        Min = 12,
        Max = 20,
        Function = function()
            if BCR.Enabled and CpsConstants then
                local newCPS = Value.Value == 0 and 1000 or Value.Value
                CpsConstants.BLOCK_PLACE_CPS = newCPS
            end
        end,
    })
end)

run(function()
    local KitRender
    local Players = playersService
    local player = Players.LocalPlayer
    local PlayerGui = player:WaitForChild("PlayerGui")

    local activeLoops = {}
    local updateDebounce = {}
    local retryThread = nil

    local function createkitrender(plr)
        local icon = Instance.new("ImageLabel")
        icon.Name = "SkidV4KitRender" 
        icon.AnchorPoint = Vector2.new(1, 0.5)
        icon.BackgroundTransparency = 1
        icon.Position = UDim2.new(1.05, 0, 0.5, 0)
        icon.Size = UDim2.new(1.5, 0, 1.5, 0)
        icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
        icon.ImageTransparency = 0.4
        icon.ScaleType = Enum.ScaleType.Crop
        local uar = Instance.new("UIAspectRatioConstraint")
        uar.AspectRatio = 1
        uar.AspectType = Enum.AspectType.FitWithinMaxSize
        uar.DominantAxis = Enum.DominantAxis.Width
        uar.Parent = icon
        local kit = plr:GetAttribute("PlayingAsKits")
        local meta = bedwars.BedwarsKitMeta and (bedwars.BedwarsKitMeta[kit] or bedwars.BedwarsKitMeta.none)
        local newImage = (meta and meta.renderImage) or kitImageIds[kit] or kitImageIds["none"]
        icon.Image = newImage
        local levelLabel = Instance.new("TextLabel")
        levelLabel.Name = "SkidV4KitLevel"
        levelLabel.AnchorPoint = Vector2.new(1, 1)
        levelLabel.Position = UDim2.new(1, -2, 1, -2)
        levelLabel.Size = UDim2.new(0.5, 0, 0.5, 0)
        levelLabel.BackgroundTransparency = 1
        levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        levelLabel.TextSize = 14
        levelLabel.Font = Enum.Font.GothamBold
        levelLabel.TextStrokeTransparency = 0.2
        levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        levelLabel.TextXAlignment = Enum.TextXAlignment.Right
        levelLabel.TextYAlignment = Enum.TextYAlignment.Bottom
        local level = plr:GetAttribute("PlayerLevel") or 0
        levelLabel.Text = "[" .. tostring(level) .. "]"
        levelLabel.Parent = icon

        return {icon = icon, levelLabel = levelLabel}
    end

    local function removeallkitrenders()
        for key, _ in pairs(activeLoops) do
            activeLoops[key] = nil
        end
        table.clear(updateDebounce)
        
        if retryThread then
            task.cancel(retryThread)
            retryThread = nil
        end
        
        for _, v in ipairs(PlayerGui:GetDescendants()) do
            if v:IsA("ImageLabel") and v.Name == "SkidV4KitRender" then  
                v:Destroy()
            end
        end
    end

    local function refreshicon(data, plr)
        if not data or not data.icon or not data.icon.Parent then return end
        local kit = plr:GetAttribute("PlayingAsKits")
        local meta = bedwars.BedwarsKitMeta and (bedwars.BedwarsKitMeta[kit] or bedwars.BedwarsKitMeta.none)
        local newImage = (meta and meta.renderImage) or kitImageIds[kit] or kitImageIds["none"]
        if data.icon.Image ~= newImage then
            data.icon.Image = newImage
        end

        if data.levelLabel and data.levelLabel.Parent then
            local level = plr:GetAttribute("PlayerLevel") or 0
            local newText = "[" .. tostring(level) .. "]"
            if data.levelLabel.Text ~= newText then
                data.levelLabel.Text = newText
            end
        end
    end

    local function findPlayer(label, container)
        local render = container:FindFirstChild("PlayerRender", true)
        if render and render:IsA("ImageLabel") and render.Image then
            local userId = string.match(render.Image, "id=(%d+)")
            if userId then
                local plr = Players:GetPlayerByUserId(tonumber(userId))
                if plr then return plr end
            end
        end
        local text = label.Text
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Name == text or plr.DisplayName == text or plr:GetAttribute("DisguiseDisplayName") == text then
                return plr
            end
            local smName = nil
            pcall(function()
                smName = bedwars.KnitClient.Controllers.StreamerModeController:getDisplayName(plr)
            end)
            if smName and smName == text then
                return plr
            end
        end
    end

    local function handleLabel(label)
        if not (label:IsA("TextLabel") and label.Name == "PlayerName") then return end
        task.spawn(function()
            local container = label.Parent
            for _ = 1, 3 do
                if container and container.Parent then
                    container = container.Parent
                end
            end
            if not container or not container:IsA("Frame") then return end
            
            local playerFound = findPlayer(label, container)
            if not playerFound then
                task.wait(0.5)
                playerFound = findPlayer(label, container)
            end
            if not playerFound then return end
            if not playerFound:GetAttribute("PlayingAsKits") then
                task.wait(1)
                if not playerFound:GetAttribute("PlayingAsKits") then return end
            end
            local myTeam = lplr:GetAttribute('Team')
            local theirTeam = playerFound:GetAttribute('Team')
            if not myTeam or not theirTeam or myTeam == theirTeam then return end
            
            container.Name = playerFound.Name
            local card = container:FindFirstChild("1") and container["1"]:FindFirstChild("MatchDraftPlayerCard")
            if not card then return end
            
            local data = card:FindFirstChild("SkidV4KitRender") and {icon = card:FindFirstChild("SkidV4KitRender"), levelLabel = card:FindFirstChild("SkidV4KitRender"):FindFirstChild("SkidV4KitLevel")}
            if not data or not data.icon then
                data = createkitrender(playerFound)
                data.icon.Parent = card
            end
            
            local loopKey = playerFound.UserId
            if activeLoops[loopKey] then
                activeLoops[loopKey] = nil
            end
            activeLoops[loopKey] = data
            task.spawn(function()
                while activeLoops[loopKey] and KitRender.Enabled do
                    if not container or not container.Parent then
                        break
                    end
                    if playerFound and data.icon and data.icon.Parent then
                        refreshicon(data, playerFound)
                    end
                    task.wait(0.3)
                end
                activeLoops[loopKey] = nil
                updateDebounce[loopKey] = nil
            end)
        end)
    end

    local activeConnections = {}
    local kitLabels = {}
    local squadUpdateDebounce = {}
    local processedPlayers = {}

    local function createKitLabel(parent, kitImage, plr)
        if kitLabels[parent] then kitLabels[parent]:Destroy() end
        local kitLabel = Instance.new("ImageLabel")
        kitLabel.Name = "SkidV4KitIcon"
        kitLabel.Size = UDim2.new(1, 0, 1, 0)
        kitLabel.Position = UDim2.new(1.1, 0, 0, 0)
        kitLabel.BackgroundTransparency = 1
        kitLabel.Image = kitImage
        kitLabel.Parent = parent
        local levelLabel = Instance.new("TextLabel")
        levelLabel.Name = "SkidV4KitLevel"
        levelLabel.AnchorPoint = Vector2.new(1, 1)
        levelLabel.Position = UDim2.new(1, -2, 1, -2)
        levelLabel.Size = UDim2.new(0.5, 0, 0.5, 0)
        levelLabel.BackgroundTransparency = 1
        levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        levelLabel.TextSize = 12
        levelLabel.Font = Enum.Font.GothamBold
        levelLabel.TextStrokeTransparency = 0.2
        levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        levelLabel.TextXAlignment = Enum.TextXAlignment.Right
        levelLabel.TextYAlignment = Enum.TextYAlignment.Bottom
        local level = plr and plr:GetAttribute("PlayerLevel") or 0
        levelLabel.Text = "[" .. tostring(level) .. "]"
        levelLabel.Parent = kitLabel
        kitLabels[parent] = {icon = kitLabel, levelLabel = levelLabel}
        return kitLabels[parent]
    end

    local function setupSquadsKitRender(obj)
        if obj.Name == "PlayerRender" and obj.Parent and obj.Parent.Parent and obj.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Parent and obj.Parent.Parent.Parent.Parent.Parent.Name == "MatchDraftTeamCardRow" then
            local Rank = obj.Parent:FindFirstChild('3')
            if not Rank then return end
            local userId = string.match(obj.Image, "id=(%d+)")
            if not userId then return end
            local plr = playersService:GetPlayerByUserId(tonumber(userId))
            if not plr then return end
            local myTeam = lplr:GetAttribute('Team')
            local theirTeam = plr:GetAttribute('Team')
            if not myTeam or not theirTeam or myTeam == theirTeam then return end
            local loopKey = plr.UserId
            processedPlayers[loopKey] = true
            if activeConnections[loopKey] then activeConnections[loopKey]:Disconnect() activeConnections[loopKey] = nil end
            local function updateKit()
                if not KitRender.Enabled then return end
                if not Rank or not Rank.Parent then
                    if activeConnections[loopKey] then activeConnections[loopKey]:Disconnect() activeConnections[loopKey] = nil end
                    if kitLabels[Rank] then kitLabels[Rank] = nil end
                    return
                end
                local kitName = plr:GetAttribute("PlayingAsKits") or "none"
                local render = bedwars.BedwarsKitMeta[kitName] or bedwars.BedwarsKitMeta.none
                local data = kitLabels[Rank]
                if data then
                    if data.icon then data.icon.Image = render.renderImage end
                    if data.levelLabel then
                        local level = plr:GetAttribute("PlayerLevel") or 0
                        data.levelLabel.Text = "[" .. tostring(level) .. "]"
                    end
                else
                    data = createKitLabel(Rank, render.renderImage, plr)
                end
            end
            updateKit()
            local connection = plr:GetAttributeChangedSignal("PlayingAsKits"):Connect(function()
                local t = tick()
                if not squadUpdateDebounce[loopKey] or (t - squadUpdateDebounce[loopKey]) >= 0.1 then
                    squadUpdateDebounce[loopKey] = t
                    updateKit()
                end
            end)
            local levelConn = plr:GetAttributeChangedSignal("PlayerLevel"):Connect(function()
                updateKit()
            end)
            activeConnections[loopKey] = connection
            KitRender:Clean(connection)
            KitRender:Clean(levelConn)
        end
    end

    local function setupSquadsRender()
        local teams = lplr.PlayerGui:FindFirstChild("MatchDraftApp")
        if not teams then return false end
        task.wait(0.5)
        for _, obj in teams:GetDescendants() do
            if KitRender.Enabled then task.spawn(function() setupSquadsKitRender(obj) end) end
        end
        KitRender:Clean(teams.DescendantAdded:Connect(function(obj)
            if KitRender.Enabled then task.wait(0.1) setupSquadsKitRender(obj) end
        end))
        return true
    end

    local function removeSquadsRender()
        for key, connection in pairs(activeConnections) do
            if connection then connection:Disconnect() end
            activeConnections[key] = nil
        end
        for parent, data in pairs(kitLabels) do
            if data and data.icon then data.icon:Destroy() end
            kitLabels[parent] = nil
        end
        table.clear(squadUpdateDebounce)
        table.clear(processedPlayers)
    end

    local function setupKitRender()
        local draftApp = PlayerGui:FindFirstChild("MatchDraftApp")
        if not draftApp then return false end

        for _, child in ipairs(draftApp:GetDescendants()) do
            if KitRender.Enabled then handleLabel(child) end
        end

        KitRender:Clean(draftApp.DescendantAdded:Connect(function(child)
            if KitRender.Enabled then handleLabel(child) end
        end))

        KitRender:Clean(draftApp.AncestryChanged:Connect(function()
            if not draftApp.Parent then
                removeallkitrenders()
            end
        end))

        return true
    end

    KitRender = vape.Categories.Utility:CreateModule({
        Name = "KitRender",
        Tooltip = "renders everyone kit during banning(for 5v5 or Squads) with player level display",
        Function = function(callback)
            if callback then
                local draftApp = lplr.PlayerGui:FindFirstChild("MatchDraftApp")
                local isSquads = draftApp and draftApp:FindFirstChild("MatchDraftTeamCardRow", true) ~= nil
                local setupFn = isSquads and setupSquadsRender or setupKitRender
                setupFn()
            else
                removeallkitrenders()
                removeSquadsRender()
            end
        end
    })
end)

run(function()
	local StaffDetector
	local Mode
	local Clans
	local Party
	local Profile
	local Users
	local AlertDuration
	local ClosetDetect

	local blacklistedclans = {'gg', 'gg2', 'DV', 'DV2', 'nwr'}
	local blacklisteduserids = {1502104539, 3826146717, 4531785383, 1049767300, 4926350670, 653085195, 184655415, 2752307430, 5087196317, 5744061325, 1536265275}

	local blacklistedusernames = {}
	local apiModNames = {}

	local teamNameMap = { [1] = 'Blue', [2] = 'Orange', [3] = 'Pink', [4] = 'Yellow' }
	local joined = {}
	local detectedPlayers = {}
	local processing = {}

	for _, name in ipairs({'gavin2015shadow','clocksurge','amcoolll3','zorflow','dreamingnostaigia','featheredtwilight','hobyboynum','imabot122356','10_lyz','Pluhmb','sopiapla1','5xGzt','M1D_XxdemonasxX','AraStxr','soyleyenda84','Zeverlast','onlyluis20','leodragonfuerte','Zubeknakov','generalcyans','nightnm14','kuberxsaikrish','zikomnontop','Byte_RIFT30','DJ_hustIenomics','soryedd','PISTONWAREINDUSTRIES','AnybodySky','HarryPairsOfNUTS','Real_Shane','voljr1','mybrotherhasgyaat','Rivalspro3076','ILoveLatxinxaAss','LeOnlyFat','IlIIIlllIIlIlIIlI','LoganW564','Number1OPPofMexico','panduvvs'}) do
		blacklistedusernames[name:lower()] = true
	end
	for _, name in ipairs({'chasemaser','IllIlllIIIllllIIIll','7SlyR','DoordashRP','OrionYeets','lIllllllllllIllIIlll','AUW345678','the2ndtestaccount','IllIIIIlllIlllIIIIIl','IllIIIIlllIlllIlIIII','ProSurferGamer1','22willow_place','celisnix','G_TP56','celisnix_3','nwrkr','lIIlIlIllllllIIlI','IllIIIIIIlllllIIlIlI','GorillaWithASuit','liilliilliiiliill','IllIllIllllIIIIIIlIl','Typhoon_Kang','VictoryForLife2468','IlIIIlllllIIIIlIIIIl','Erin_Ireland22','IIIIllIIIIIIlllIlIII','IIIIIlllIlllllIlII','Ghostwxstaken','wvwvwvwwvwvvwvw','lllIIllIllIIllIllII','TheAwkwardSponge','TotallyKoaIa','YT_GoraPlays','LegendaryToragon','appleapplelllllll','Yo_johnny67','llIIllIIllllIlIl','PoopFarm_1','llIIIllIIIIIllllIII','Lemon01204','HugeMudOtter','AGameMasterHD','krustykrab204','kevinchuey','IllIIIIlIllIlIIIlI','YoZevStar','pzlican','Deevicus','Blackprincess1','yhpro1230','eple_147','whoisdv2_erin','whoisdv4_erin','whoisdv3_erin','VicForLife14','SleeplessSoulmate','Jsquire07','DVwastaken','pxIican','devzebu','FunFamilyKids177','Artan3333','3MEWMTS5LJCB','Zengoulen','GloriousConfigB2','heywasupsir','c6chisa'}) do
		apiModNames[name:lower()] = true
	end
	local listsLoaded = true

	getgenv()._onnation_staffCounts = {spec=0, closet=0, mod=0, impossible=0}
	local function refreshStaffCounts()
		local c = {spec=0, closet=0, mod=0, impossible=0}
		for _, data in pairs(detectedPlayers) do
			local ct = data.checktype
			if ct == 'spectator' then c.spec += 1
			elseif ct == 'closet' then c.closet += 1
			elseif ct == 'impossible_join' then c.impossible += 1
			else c.mod += 1 end
		end
		getgenv()._skidv4_staffCounts = c
		vapeEvents.StaffCountUpdate:Fire()
	end

	local function staffFunction(plr, checktype)
		if detectedPlayers[plr.UserId] then return end
		if not vape.Loaded then repeat task.wait() until vape.Loaded end
		local duration = AlertDuration.Value
		local playerName = plr.Name
		local playerId = plr.UserId
		detectedPlayers[playerId] = {name=playerName, checktype=checktype, detectedTime=tick()}
		notif('StaffDetector', 'Staff Detected (' .. checktype .. '): ' .. playerName .. ' (' .. playerId .. ')', duration, 'alert')
		whitelist.customtags[playerName] = {{text='GAME STAFF', color=Color3.new(1,0,0)}}
		local isClanCheck = checktype:find('clan')
		if Party.Enabled and not isClanCheck then pcall(bedwars.PartyController.leaveParty) end
		local modeValue = Mode.Value
		if modeValue == 'Uninject' then
			task.spawn(function() vape:Uninject() end)
			game:GetService('StarterGui'):SetCore('SendNotification', {Title='StaffDetector',Text='Staff Detected ('..checktype..')\n'..playerName..' ('..playerId..')',Duration=duration})
		elseif modeValue == 'Requeue' then
			pcall(bedwars.QueueController.leaveQueue)
			bedwars.QueueController:joinQueue(store.queueType)
		elseif modeValue == 'Profile' then
			if checktype == 'known_mod' or checktype == 'blacklisted_user' then
				vape.Save = function() end
				if vape.Profile ~= Profile.Value then vape:Load(true, Profile.Value) end
			end
		elseif modeValue == 'AutoConfig' then
			local safe = {AutoClicker=true,Reach=true,Sprint=true,HitFix=true,StaffDetector=true}
			vape.Save = function() end
			for i, v in vape.Modules do
				if not (safe[i] or v.Category == 'Render') then
					if v.Enabled then v:Toggle() end
					v:SetBind('')
				end
			end
		end
		refreshStaffCounts()
	end

	local function closetFunction(plr)
		if detectedPlayers[plr.UserId] then return end
		if not vape.Loaded then repeat task.wait() until vape.Loaded end
		local teamNum = tonumber(plr:GetAttribute('Team'))
		local team = teamNum and teamNameMap[teamNum] or 'Unknown'
		detectedPlayers[plr.UserId] = {name=plr.Name, checktype='closet', detectedTime=tick()}
		notif('StaffDetector', 'KNOWN CLOSETCHEATER: ' .. plr.Name .. ' | Team: ' .. team, AlertDuration.Value, 'alert')
		whitelist.customtags[plr.Name] = {{text='CHEATER', color=Color3.fromRGB(255,140,0)}}
		refreshStaffCounts()
	end

	local function checkCloset(plr)
		if not ClosetDetect or not ClosetDetect.Enabled then return false end
		if plr == lplr then return false end
		if blacklistedusernames[plr.Name:lower()] then
			task.spawn(function()
				local waited = 0
				while not plr:GetAttribute('Team') and waited < 10 do
					task.wait(0.5) waited += 0.5
				end
				closetFunction(plr)
			end)
			return true
		end
		return false
	end

	local function playerAdded(plr)
		joined[plr.UserId] = plr.Name
		if plr == lplr then return end
		if processing[plr.UserId] then return end
		processing[plr.UserId] = true

		if not listsLoaded then
			local t = tick()
			repeat task.wait(0.1) until listsLoaded or (tick()-t > 3)
		end

		if checkCloset(plr) then processing[plr.UserId] = nil return end

		if table.find(blacklisteduserids, plr.UserId) or (Users and table.find(Users.ListEnabled, tostring(plr.UserId))) then
			staffFunction(plr, 'blacklisted_user')
			processing[plr.UserId] = nil
			return
		end

		if apiModNames[plr.Name:lower()] then
			staffFunction(plr, 'known_mod')
			processing[plr.UserId] = nil
			return
		end

		local function spectatorFunction(plr)
			if detectedPlayers[plr.UserId] then return end
			if not vape.Loaded then repeat task.wait() until vape.Loaded end
			detectedPlayers[plr.UserId] = {name=plr.Name, checktype='spectator', detectedTime=tick()}
			notif('StaffDetector', 'Spectator: '..plr.Name..' ('..tostring(plr.UserId)..') [has friend(s) in server]', AlertDuration.Value, 'warning')
			refreshStaffCounts()
		end

		local function checkJoin()
			if not plr:GetAttribute('Team') and plr:GetAttribute('Spectator') then
				local hasFriend = false
				for _, sp in ipairs(playersService:GetPlayers()) do
					if sp ~= plr then
						local ok, res = pcall(function() return plr:IsFriendsWith(sp.UserId) end)
						if ok and res then hasFriend = true break end
					end
				end
				if hasFriend then spectatorFunction(plr) else staffFunction(plr, 'impossible_join') end
				return true
			end
			return false
		end

		local spectatorConnection
		spectatorConnection = plr:GetAttributeChangedSignal('Spectator'):Connect(function()
			if checkJoin() then spectatorConnection:Disconnect() processing[plr.UserId] = nil end
		end)
		StaffDetector:Clean(spectatorConnection)

		if checkJoin() then processing[plr.UserId] = nil return end

		if Clans.Enabled then
			local function checkClanTag()
				local clanTag = plr:GetAttribute('ClanTag')
				if clanTag and table.find(blacklistedclans, clanTag) then
					staffFunction(plr, 'blacklisted_clan_' .. clanTag:lower())
				end
			end
			if plr:GetAttribute('ClanTag') then
				checkClanTag()
			else
				local clanConnection
				clanConnection = plr:GetAttributeChangedSignal('ClanTag'):Connect(function()
					clanConnection:Disconnect()
					checkClanTag()
				end)
				StaffDetector:Clean(clanConnection)
				task.delay(5, function() if clanConnection then clanConnection:Disconnect() end end)
			end
		end

		processing[plr.UserId] = nil
	end

	local function playerRemoving(plr)
		local userId = plr.UserId
		joined[userId] = nil
		processing[userId] = nil
		if detectedPlayers[userId] then
			local data = detectedPlayers[userId]
			notif('StaffDetector', data.name .. ' (' .. data.checktype .. ') has left the server', AlertDuration.Value, 'warning')
			if whitelist.customtags[data.name] then whitelist.customtags[data.name] = nil end
			detectedPlayers[userId] = nil
			refreshStaffCounts()
		end
	end

	StaffDetector = vape.Categories.Utility:CreateModule({
		Name = 'StaffDetector',
		Function = function(callback)
			if callback then
				StaffDetector:Clean(playersService.PlayerAdded:Connect(playerAdded))
				StaffDetector:Clean(playersService.PlayerRemoving:Connect(playerRemoving))
				for _, v in playersService:GetPlayers() do task.spawn(playerAdded, v) end
			else
				table.clear(joined) table.clear(processing) table.clear(detectedPlayers)
				refreshStaffCounts()
			end
		end,
		Tooltip = 'detects people with staff role and etc'
	})

	Mode = StaffDetector:CreateDropdown({Name='Mode',List={'Uninject','Profile','Requeue','AutoConfig','Notify'},Function=function(val) if Profile.Object then Profile.Object.Visible = val=='Profile' end end})
	AlertDuration = StaffDetector:CreateSlider({Name='Alert Duration',Min=5,Max=120,Default=60,Suffix='s',})
	Clans = StaffDetector:CreateToggle({Name='Blacklist clans',Default=true})
	Party = StaffDetector:CreateToggle({Name='Leave party'})
	ClosetDetect = StaffDetector:CreateToggle({Name='Known Cheaters',Default=true,})
	Profile = StaffDetector:CreateTextBox({Name='Profile',Default='default',Darker=true,Visible=false})
	Users = StaffDetector:CreateTextList({Name='Users',Placeholder='player (userid)',Function=function() end})
	task.defer(function() if Profile and Profile.Object then Profile.Object.Visible = (Mode.Value=='Profile') end end)
end)

run(function()
    local MetalDetector
    local CollectionToggle
    local LimitToItem
    local Animation
    local CollectionDelay
    local DelaySlider
    local RangeSlider
    local ESPToggle
    local ESPNotify
    local ESPBackground
    local ESPColor
    local HoldingCheck
    local DistanceCheck
    local DistanceLimit
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local Reference = {}
    local lastNotification = 0
    local notificationPending = false
    local spawnQueue = {}
    local notificationCooldown = 1
    local collectionActive = false
    local collectedMetals = {}
    local animationDebounce = {}

    local function isHoldingMetalDetector()
        if not store.hand or not store.hand.tool then return false end
        return store.hand.tool.Name == 'metal_detector'
    end

    local function sendNotification(count)
        notif("Metal ESP", string.format("%d metals spawned", count), 3)
    end

    local function processSpawnQueue()
        if #spawnQueue == 0 then return end
        local currentTime = tick()
        local remaining = notificationCooldown - (currentTime - lastNotification)
        if remaining <= 0 then
            sendNotification(#spawnQueue)
            lastNotification = currentTime
            spawnQueue = {}
            notificationPending = false
        elseif not notificationPending then
            notificationPending = true
            task.delay(remaining, function()
                if #spawnQueue > 0 then
                    sendNotification(#spawnQueue)
                    lastNotification = tick()
                    spawnQueue = {}
                end
                notificationPending = false
            end)
        end
    end

    local function getProperImage()
        return bedwars.getIcon({itemType = 'iron'}, true)
    end

    local function Added(v)
        if Reference[v] then return end
        local _bpUserId = v:GetAttribute('PlacedByUserId')
        if _bpUserId then
            local _bpOk, _bpOwner = pcall(function() return playersService:GetPlayerByUserId(_bpUserId) end)
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'hidden-metal'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        
        local blur = addBlur(billboard)
        blur.Visible = ESPBackground.Enabled
        
        local image = Instance.new('ImageLabel')
        image.Size = UDim2.fromOffset(36, 36)
        image.Position = UDim2.fromScale(0.5, 0.5)
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.BackgroundColor3 = Color3.fromHSV(ESPColor.Hue, ESPColor.Sat, ESPColor.Value)
        image.BackgroundTransparency = 1 - (ESPBackground.Enabled and ESPColor.Opacity or 0)
        image.BorderSizePixel = 0
        image.Image = getProperImage()
        image.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 4)
        uicorner.Parent = image
        
        Reference[v] = billboard
        
        if ESPNotify.Enabled then
            table.insert(spawnQueue, {item = 'metal', time = tick()})
            processSpawnQueue()
        end
    end

    local function Removed(v)
        if Reference[v] then
            Reference[v]:Destroy()
            Reference[v] = nil
        end
    end

    local function setupESP()
        for _, v in collectionService:GetTagged('hidden-metal') do
            if v:IsA("Model") and v.PrimaryPart then
                Added(v.PrimaryPart)
            end
        end

        MetalDetector:Clean(collectionService:GetInstanceAddedSignal('hidden-metal'):Connect(function(v)
            if v:IsA("Model") and v.PrimaryPart then
                Added(v.PrimaryPart)
            end
        end))

        MetalDetector:Clean(collectionService:GetInstanceRemovedSignal('hidden-metal'):Connect(function(v)
            if v.PrimaryPart then
                Removed(v.PrimaryPart)
            end
        end))

        local _mdLastUpdate = 0
        MetalDetector:Clean(runService.RenderStepped:Connect(function()
            if not ESPToggle.Enabled then return end
            local _now = tick()
            if _now - _mdLastUpdate < 0.1 then return end
            _mdLastUpdate = _now
            
            for v, billboard in pairs(Reference) do
                if not v or not v.Parent then
                    Removed(v)
                    continue
                end

                local shouldShow = true

                if HoldingCheck.Enabled and not isHoldingMetalDetector() then
                    shouldShow = false
                end

                if shouldShow and DistanceCheck.Enabled and entitylib.isAlive then
                    local distance = (entitylib.character.RootPart.Position - v.Position).Magnitude
                    if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
                        shouldShow = false
                    end
                end

                billboard.Enabled = shouldShow
            end
        end))
    end

    local function collectMetal(metalModel)
        local metalId = metalModel:GetAttribute('Id')
        if not metalId then return false end
        if collectedMetals[metalId] then return false end

        collectedMetals[metalId] = true

        local success = pcall(function()
            bedwars.Client:Get(remotes.CollectCollectableEntity).instance:FireServer({ id = metalId })
        end)

        if Animation.Enabled then
            local currentTick = tick()
            if not animationDebounce[metalId] or (currentTick - animationDebounce[metalId]) >= 0.5 then
                animationDebounce[metalId] = currentTick
                pcall(function()
                    bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.SHOVEL_DIG)
                    bedwars.SoundManager:playSound(bedwars.SoundList.SNAP_TRAP_CONSUME_MARK)
                end)
            end
        end

        task.delay(2, function()
            collectedMetals[metalId] = nil
            animationDebounce[metalId] = nil
        end)
        
        return success
    end

    local function startAutoCollect()
        if collectionActive then return end
        collectionActive = true
        
        task.spawn(function()
            while MetalDetector.Enabled and CollectionToggle.Enabled and collectionActive do
                if not entitylib.isAlive then 
                    task.wait(0.5)
                    continue 
                end
                
                if LimitToItem.Enabled and not isHoldingMetalDetector() then 
                    task.wait(0.5)
                    continue 
                end
                
                local localPosition = entitylib.character.RootPart.Position
                local range = RangeSlider.Value
                local collectedThisCycle = false
								
				for _, v in collectionService:GetTagged('hidden-metal') do
					if not MetalDetector.Enabled or not CollectionToggle.Enabled or not collectionActive then 
						break 
					end
					
					if v:IsA("Model") and v.PrimaryPart then
						local distance = (localPosition - v.PrimaryPart.Position).Magnitude
						
						if distance <= range then
							if collectMetal(v) then
								collectedThisCycle = true
								if CollectionDelay.Enabled and DelaySlider.Value > 0 then
									task.wait(DelaySlider.Value)
								else
									task.wait(0.15)
								end
							end
						end
					end
				end
                
                task.wait(collectedThisCycle and 0.3 or 0.5)
            end
            
            collectionActive = false
        end)
    end

    local function stopAutoCollect()
        collectionActive = false
        table.clear(collectedMetals)
        table.clear(animationDebounce)
    end

    MetalDetector = vape.Categories.Kits:CreateModule({
        Name = 'AutoMetal',
        Function = function(callback)
            if callback then
                if ESPToggle.Enabled then 
                    setupESP() 
                end
                if CollectionToggle.Enabled then
                    startAutoCollect()
                end
            else
                stopAutoCollect()
                Folder:ClearAllChildren()
                table.clear(Reference)
                spawnQueue = {}
                lastNotification = 0
                notificationPending = false
            end
        end,
        Tooltip = 'automatically collects metal loot and esp'
    })
    
    CollectionToggle = MetalDetector:CreateToggle({
        Name = 'Auto Collect',
        Default = true,
        Function = function(callback)
            if LimitToItem and LimitToItem.Object then LimitToItem.Object.Visible = callback end
            if Animation and Animation.Object then Animation.Object.Visible = callback end
            if CollectionDelay and CollectionDelay.Object then CollectionDelay.Object.Visible = callback end
            if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = callback end
            if DelaySlider and DelaySlider.Object then
                DelaySlider.Object.Visible = callback and CollectionDelay and CollectionDelay.Enabled
            end
            
            if MetalDetector.Enabled then
                if callback then
                    startAutoCollect()
                else
                    stopAutoCollect()
                end
            end
        end
    })
    
    LimitToItem = MetalDetector:CreateToggle({
        Name = 'Limit to Items',
        Default = true,
    })
    
    Animation = MetalDetector:CreateToggle({
        Name = 'Animation',
        Default = true,
    })
    
    CollectionDelay = MetalDetector:CreateToggle({
        Name = 'Collection Delay',
        Default = false,
        Function = function(callback)
            if DelaySlider and DelaySlider.Object then
                DelaySlider.Object.Visible = callback
            end
        end
    })
    
    DelaySlider = MetalDetector:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
        Visible = false,
    })
    
    RangeSlider = MetalDetector:CreateSlider({
        Name = 'Range',
        Min = 1, 
        Max = 10,
        Default = 10,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    ESPToggle = MetalDetector:CreateToggle({
        Name = 'Metal ESP',
        Default = false,
        Function = function(callback)
            if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = callback end
            if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = callback end
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            if HoldingCheck and HoldingCheck.Object then HoldingCheck.Object.Visible = callback end
            if DistanceCheck and DistanceCheck.Object then DistanceCheck.Object.Visible = callback end
            if DistanceLimit and DistanceLimit.Object then
                DistanceLimit.Object.Visible = (callback and DistanceCheck.Enabled)
            end

            if not callback then
                if ESPColor and ESPColor.Object then
                    ESPColor.Object.Visible = false
                end
                if DistanceLimit and DistanceLimit.Object then
                    DistanceLimit.Object.Visible = false
                end
            else
                if ESPBackground and ESPBackground.Enabled then
                    if ESPColor and ESPColor.Object then
                        ESPColor.Object.Visible = true
                    end
                end
                if DistanceCheck and DistanceCheck.Enabled then
                    if DistanceLimit and DistanceLimit.Object then
                        DistanceLimit.Object.Visible = true
                    end
                end
            end
            
            if MetalDetector.Enabled then
                if callback then setupESP() else
                    Folder:ClearAllChildren()
                    table.clear(Reference)
                end
            end
        end
    })
    
    ESPNotify = MetalDetector:CreateToggle({
        Name = 'Notify',
        Default = false,
    })
    
    ESPBackground = MetalDetector:CreateToggle({
        Name = 'Background',
        Default = true,
        Function = function(callback)
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    local blur = v:FindFirstChild("BlurEffect")
                    if blur then blur.Visible = callback end
                    v.ImageLabel.BackgroundTransparency = 1 - (callback and ESPColor.Opacity or 0)
                end
            end
        end
    })
    
    ESPColor = MetalDetector:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    v.ImageLabel.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Darker = true
    })
    
    HoldingCheck = MetalDetector:CreateToggle({
        Name = 'Holding Detector',
        Default = false,
    })
    
    DistanceCheck = MetalDetector:CreateToggle({
        Name = 'Distance Check',
        Default = false,
        Function = function(callback)
            if DistanceLimit and DistanceLimit.Object then
                DistanceLimit.Object.Visible = callback
            end
        end
    })
    
    DistanceLimit = MetalDetector:CreateTwoSlider({
        Name = 'Metal Distance',
        Min = 0,
        Max = 256,
        DefaultMin = 0,
        DefaultMax = 64,
        Darker = true,
    })

    task.defer(function()
        if DelaySlider and DelaySlider.Object then
            DelaySlider.Object.Visible = CollectionDelay.Enabled  
        end
        if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = false end
        if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = false end
        if ESPColor and ESPColor.Object then ESPColor.Object.Visible = false end
        if HoldingCheck and HoldingCheck.Object then HoldingCheck.Object.Visible = false end
        if DistanceCheck and DistanceCheck.Object then DistanceCheck.Object.Visible = false end
        if DistanceLimit and DistanceLimit.Object then DistanceLimit.Object.Visible = false end
    end)
end)

run(function()
    local PromptUnlock
    local savedPromptStates = {}

    PromptUnlock = vape.Categories.Kits:CreateModule({
        Name = 'PromptUnlock',
        Tooltip = 'makes all proximity prompts visibile - no matter what (no tool check and etc)',
        Function = function(callback)
            if callback then
                savedPromptStates = {}

                local function hookPrompt(v)
                    if not v:IsA('ProximityPrompt') then return end
                    if savedPromptStates[v] then return end
                    savedPromptStates[v] = v.Enabled
                    v.Enabled = true
                    PromptUnlock:Clean(v:GetPropertyChangedSignal('Enabled'):Connect(function()
                        if not PromptUnlock.Enabled then return end
                        if not v.Enabled then
                            v.Enabled = true
                        end
                    end))
                end

                for _, v in workspace:GetDescendants() do
                    hookPrompt(v)
                end

                PromptUnlock:Clean(workspace.DescendantAdded:Connect(function(v)
                    if not PromptUnlock.Enabled then return end
                    hookPrompt(v)
                end))
            else
                for prompt, state in savedPromptStates do
                    if prompt and prompt.Parent then
                        prompt.Enabled = state
                    end
                end
                savedPromptStates = {}
            end
        end
    })
end)

run(function()
	local ShadowRemover
	local connections = {}
	local originalShadows = {}
	local processedShadows = {}
	
	local function removeShadow(obj)
		if obj:IsA("BasePart") and not processedShadows[obj] then
			if not originalShadows[obj] then
				originalShadows[obj] = obj.CastShadow
			end
			obj.CastShadow = false
			processedShadows[obj] = true
		end
	end
	
	ShadowRemover = vape.Categories.World:CreateModule({
		Name = 'ShadowRemover',
		Function = function(callback)
			if callback then
				local descendants = workspace:GetDescendants()
				
				task.spawn(function()
					for i, obj in descendants do
						removeShadow(obj)
						if i % 100 == 0 then
							task.wait()
						end
					end
				end)
				
				local conn = workspace.DescendantAdded:Connect(function(obj)
					if ShadowRemover.Enabled then
						removeShadow(obj)
					end
				end)
				table.insert(connections, conn)
			else
				for obj, shadow in pairs(originalShadows) do
					if obj and obj.Parent then
						pcall(function()
							obj.CastShadow = shadow
						end)
					end
				end
				
				for _, conn in connections do
					conn:Disconnect()
				end
				table.clear(connections)
				table.clear(originalShadows)
				table.clear(processedShadows)
			end
		end,
	})
end)

run(function()
	local WhiteHits
	WhiteHits = vape.Categories.Legit:CreateModule({
		Name = "WhiteHits",
		Function = function(callback)
			if callback then
				repeat
					for i, v in entitylib.List do 
						local highlight = v.Character and v.Character:FindFirstChild('_DamageHighlight_')
						if highlight then
							highlight:Destroy()
						end
					end
					task.wait(0.1)
				until not WhiteHits.Enabled
			end
		end
	})
end)

run(function()
	local RemoveNeon = {Enabled = false}
	local neonConnection
	local safetyLoop
	local originalMaterials = {}
	local processedParts = {}
	local lastCleanup = 0
	
	local function cleanupDeadReferences()
		local count = 0
		for obj, _ in pairs(originalMaterials) do
			if not obj or not obj.Parent then
				originalMaterials[obj] = nil
				processedParts[obj] = nil
			end
			count = count + 1
			if count % 100 == 0 then
				task.wait()
			end
		end
	end
	
	local function removeNeonFromPart(obj)
		if obj:IsA("BasePart") then
			if obj.Material == Enum.Material.Neon then
				if not originalMaterials[obj] then
					originalMaterials[obj] = {
						Material = obj.Material,
						Reflectance = obj.Reflectance
					}
				end
				pcall(function()
					obj.Material = Enum.Material.Plastic
					obj.Reflectance = 0
				end)
			end
		end
	end
	
	local function restoreNeon()
		for obj, data in pairs(originalMaterials) do
			if obj and obj.Parent then
				pcall(function()
					obj.Material = data.Material
					obj.Reflectance = data.Reflectance
				end)
			end
		end
		table.clear(originalMaterials)
		table.clear(processedParts)
	end
	
	local function batchProcessParts(parts, batchSize)
		local count = 0
		for i, part in ipairs(parts) do
			if part and part.Parent then
				removeNeonFromPart(part)
				count = count + 1
			end
			if i % batchSize == 0 then
				task.wait()
			end
		end
		return count
	end
	
	RemoveNeon = vape.Categories.World:CreateModule({
		Name = 'RemoveNeon',
		Function = function(callback)
			if callback then
				task.spawn(function()
					local allParts = {}
					for _, v in pairs(workspace:GetDescendants()) do
						if v:IsA("BasePart") then
							table.insert(allParts, v)
						end
					end
					
					batchProcessParts(allParts, 200)
				end)
				
				neonConnection = workspace.DescendantAdded:Connect(function(obj)
					if RemoveNeon.Enabled then
						removeNeonFromPart(obj)
					end
				end)
				
				safetyLoop = task.spawn(function()
					while RemoveNeon.Enabled do
						task.wait(30)
						if RemoveNeon.Enabled then
							cleanupDeadReferences()
						end
					end
				end)
			else
				if neonConnection then
					neonConnection:Disconnect()
					neonConnection = nil
				end
				if safetyLoop then
					task.cancel(safetyLoop)
					safetyLoop = nil
				end
				restoreNeon()
			end
		end,
	})
end)

run(function()
	local MiloDisguse
	local Blocks
	local old
	MiloDisguse = vape.Categories.Kits:CreateModule({
		Name = "MiloDisguise",
		Tooltip = 'allows you to change to any block u want to hide as',
		Function = function(callback)
			if not callback then
				return
			end
			MiloDisguse:Toggle(false)
			local v88 = {
				["data"] = {
					["blockType"] = Blocks.Value or 'wool_red'
				}
			}

			bedwars.Client:Get(remotes.Mimic):SendToServer(v88)
		end
	})
	Blocks = MiloDisguse:CreateTextBox({
		Name = "Blocks",
		Default = 'wool_brown',
		Visible = true
	})
	
end)

run(function()
    local Fisherman
    local AutoMinigameToggle
    local CompleteDelaySlider
    local PullAnimationToggle
    local MinigameAnimationToggle
    local BlacklistOption
    local Blacklist
    local ESPToggle
	local AutoCastDelay
	local AutoCast
    local ESPNotifyToggle
    local Players = playersService
	local RunService = runService
	local lplr = Players.LocalPlayer
	local RandomizeToggle
    local RandomRange
	local waitTime
    local fishNames = {
		fish_iron = "Iron Fish",
		fish_diamond = "Diamond Fish",
		fish_gold = "Gold Fish",
		fish_special = "Special Fish",
		fish_emerald = "Emerald Fish",
	}

    local function buildMessage(fishModel, drops)
        local fishName = fishNames[fishModel] or fishModel

        if fishModel == "fish_special" then
            if drops and drops[1] then
                return "You caught a " .. fishName .. "! You will receive a " .. tostring(drops[1].itemType)
            else
                return "You caught a " .. fishName .. "! (special item incoming)"
            end
        end

        if drops and drops[1] then
            local drop = drops[1]
            return "You caught a " .. fishName .. "! Receiving " ..
                   tostring(drop.amount) .. "x " .. tostring(drop.itemType)
        end

        return "You caught a " .. fishName .. "!"
    end

    local notifQueue = {}
	local function safeNotif(title, msg, dur)
		table.insert(notifQueue, {title=title, message=msg, duration=dur or 5})
	end
	local heartbeatConn = nil

    local autoMinigameActive    = false
    local pullAnimationTrack    = nil
    local successAnimationTrack = nil
    local espOld                = nil

	local function getBait()
		for _, v in workspace:GetChildren() do
			if v.Name == "fisherman_bobber" and v:GetAttribute("ProjectileShooter") == lplr.UserId then
				return v
			end
		end

		return
	end

    local function stopAllAnimations()
        if pullAnimationTrack then
            pcall(function() pullAnimationTrack:Stop() end)
            pullAnimationTrack = nil
        end
        if successAnimationTrack then
            pcall(function() successAnimationTrack:Stop() end)
            successAnimationTrack = nil
        end
    end

    local function setupESP()
        if not bedwars or not bedwars.FishingMinigameController then
            warn("[AutoFisher] FishingMinigameController not found")
            return
        end
        if espOld then return end 
        espOld = bedwars.FishingMinigameController.startMinigame

        bedwars.FishingMinigameController.startMinigame = function(self, dropData, result)
            if ESPToggle.Enabled and ESPNotifyToggle.Enabled and dropData and dropData.fishModel then
                safeNotif("Fisherman ESP", buildMessage(dropData.fishModel, dropData.drops), 8)
            end
            return espOld(self, dropData, result)
        end

        Fisherman:Clean(function()
            if espOld then
                bedwars.FishingMinigameController.startMinigame = espOld
                espOld = nil
            end
        end)
    end

    local function cleanupESP()
        if espOld then
            bedwars.FishingMinigameController.startMinigame = espOld
            espOld = nil
        end
    end

    local function setupAutoMinigame()
        if not bedwars or not bedwars.FishingMinigameController then
            warn("[AutoFisher] FishingMinigameController not found")
            return
        end

        local old = bedwars.FishingMinigameController.startMinigame

        bedwars.FishingMinigameController.startMinigame = function(self, dropData, result)
            if not AutoMinigameToggle.Enabled then
                return old(self, dropData, result)
            end

            if BlacklistOption.Enabled and dropData and dropData.fishModel then
                if table.find(Blacklist.ListEnabled, dropData.fishModel) then
                    local hum = lplr.Character and lplr.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum:GetState() ~= Enum.HumanoidStateType.Jumping then
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                    return old(self, dropData, result)
                end
            end

            autoMinigameActive = true
            stopAllAnimations()

            local waitTime = 0
            if RandomizeToggle and RandomizeToggle.Enabled then
                local min = RandomRange.ValueMin
                local max = RandomRange.ValueMax
                waitTime = min + (max - min) * math.random()
            else
                waitTime = CompleteDelaySlider.Value
            end

            task.spawn(function()
                if PullAnimationToggle.Enabled and waitTime > 0 then
                    local ok, track = pcall(function()
                        return bedwars.GameAnimationUtil:playAnimation(
                            lplr, bedwars.AnimationType.FISHING_ROD_PULLING
                        )
                    end)
                    if ok and track then pullAnimationTrack = track end
                end

                if waitTime > 0 then
                    task.wait(waitTime)
                end

                if pullAnimationTrack then
                    pcall(function() pullAnimationTrack:Stop() end)
                    pullAnimationTrack = nil
                end

                if MinigameAnimationToggle.Enabled then
                    local ok, track = pcall(function()
                        return bedwars.GameAnimationUtil:playAnimation(
                            lplr, bedwars.AnimationType.FISHING_ROD_CATCH_SUCCESS
                        )
                    end)
                    if ok and track then successAnimationTrack = track end
                end

                if result then
                    pcall(function() result({ win = true }) end)
                end

                task.wait(0.5)

                if successAnimationTrack then
                    pcall(function() successAnimationTrack:Stop() end)
                    successAnimationTrack = nil
                end

                autoMinigameActive = false
            end)
        end

        Fisherman:Clean(function()
            bedwars.FishingMinigameController.startMinigame = old
            stopAllAnimations()
        end)
    end

	local function setupAutoCast()
		task.spawn(function()
			repeat
				if entitylib.isAlive and AutoCast.Enabled and (store.hand.tool and store.hand.tool.Name == 'fishing_rod') then
					local position = workspace.CurrentCamera.ViewportSize / 2
					local ray = cloneref(lplr:GetMouse()).UnitRay

					if not getBait() and not workspace:Raycast(entitylib.character.Head.Position + (ray.Direction * 6), Vector3.new(0, -20, 0)) then
						task.wait(AutoCastDelay:GetRandomValue())

						for _, v in {true, false} do
							VirtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, v, game, 1)
							task.wait()
						end
						task.wait(0.5)
					end
				end
				task.wait(0.1)
			until not Fisherman.Enabled
		end)
	end

    Fisherman = vape.Categories.Kits:CreateModule({
		Name = "AutoFisher",
		Function = function(callback)
            if callback then
                if ESPToggle.Enabled           then setupESP()          end
                if AutoMinigameToggle.Enabled  then setupAutoMinigame() end
                setupAutoCast()

                heartbeatConn = RunService.Heartbeat:Connect(function()
                    if #notifQueue == 0 then return end
                    local entry = table.remove(notifQueue, 1)
                    pcall(notif, entry.title, entry.message, entry.duration)
                end)
                Fisherman:Clean(heartbeatConn)

            else
                autoMinigameActive = false
                stopAllAnimations()
                cleanupESP()
                notifQueue = {} 
            end
        end
    })

    AutoMinigameToggle = Fisherman:CreateToggle({
		Name = "Auto Minigame",
		Default = false,
		Function = function(cv)
			if CompleteDelaySlider and CompleteDelaySlider.Object then
				CompleteDelaySlider.Object.Visible = cv and not (RandomizeToggle and RandomizeToggle.Enabled)
			end
			if PullAnimationToggle and PullAnimationToggle.Object then PullAnimationToggle.Object.Visible = cv end
			if MinigameAnimationToggle and MinigameAnimationToggle.Object then MinigameAnimationToggle.Object.Visible = cv end
			if RandomizeToggle and RandomizeToggle.Object then RandomizeToggle.Object.Visible = cv end
			if RandomRange and RandomRange.Object then RandomRange.Object.Visible = cv and RandomizeToggle.Enabled end
			if Fisherman.Enabled and cv then setupAutoMinigame() end
		end
	})

	CompleteDelaySlider = Fisherman:CreateSlider({
		Name = "Complete Delay",
		Min = 0,
		Max = 5,
		Default = 1,
		Decimal = 10,
		Suffix = "s",
		Visible = false,
	})

	RandomizeToggle = Fisherman:CreateToggle({
		Name = "Randomize Timing",
		Default = false,
		Function = function(cv)
			if RandomRange and RandomRange.Object then RandomRange.Object.Visible = cv end
			if CompleteDelaySlider and CompleteDelaySlider.Object then CompleteDelaySlider.Object.Visible = not cv end
		end
	})

	RandomRange = Fisherman:CreateTwoSlider({
		Name = "Random Delay Range",
		Min = 0.1,
		Max = 5,
		DefaultMin = 0.5,
		DefaultMax = 2,
		Decimal = 10,
		Visible = false,
	})

	PullAnimationToggle = Fisherman:CreateToggle({
		Name = "Pull Animation",
		Default = true,
		Visible = false,
	})

	MinigameAnimationToggle = Fisherman:CreateToggle({
		Name = "Success Animation",
		Default = true,
		Visible = false,
	})

	BlacklistOption = Fisherman:CreateToggle({
		Name = "Blacklist",
		Default = false,
		Function = function(cv)
			if Blacklist and Blacklist.Object then Blacklist.Object.Visible = cv end
		end
	})

	Blacklist = Fisherman:CreateTextList({
		Name = "Blacklist Fish",
		Default = {"fish_iron"}
	})

	AutoCast = Fisherman:CreateToggle({
		Name 	= "AutoCast",
		Default = false,
		Function = function(callback)
			if callback then
				if AutoCastDelay and AutoCastDelay.Object then AutoCastDelay.Object.Visible = callback end
				if AutoCast.Enabled and callback then setupAutoCast() end
			end
		end
	})

	AutoCastDelay = Fisherman:CreateTwoSlider({
		Name 	= "Cast Delay",
		Min 	= 0,
		Max 	= 5,
		Decimal = 5,
		DefaultMin = 0.3,
		DefaultMax = 1.2,
		Darker 	= true,
		Visible = AutoCast.Enabled
	})	

    ESPToggle = Fisherman:CreateToggle({
		Name = "Fisherman ESP",
		Default = false,
		Function = function(cv)
			if ESPNotifyToggle and ESPNotifyToggle.Object then ESPNotifyToggle.Object.Visible = cv end
			if Fisherman.Enabled then
				if cv then setupESP() else cleanupESP() end
			end
		end
	})

	ESPNotifyToggle = Fisherman:CreateToggle({
		Name = "Notify Loot",
		Default = true,
		Visible = false,
	})
end)

run(function()
    local AutoWhisper
    local PlayerDropdown
    local AutoHeal
    local AutoHealSlider
    local AutoFly
    local LimitToItem
    local RefreshButton
    local running = false
    local healRunning = false
    local flyRunning = false
    local currentTarget = nil
    local currentMountedPlayer = nil
    local fallCheckTimer = 0
    local hasActivatedFly = false
    
    local function isHoldingOwlOrb()
        if not entitylib.isAlive then return false end
        
        local inventory = store.inventory
        if inventory and inventory.inventory and inventory.inventory.hand then
            local handItem = inventory.inventory.hand
            if handItem and handItem.itemType == "owl_orb" then
                return true
            end
        end
        return false
    end
    
    local function getMountedPlayer()
        local owlTarget = lplr:GetAttribute('OwlTarget')
        if owlTarget then
            return playersService:GetPlayerByUserId(owlTarget)
        end
        return nil
    end
    
    local function mountBirdToPlayer(targetPlayer)
        if not targetPlayer or not targetPlayer.Character then return false end
        
        if LimitToItem.Enabled and not isHoldingOwlOrb() then
            return false
        end
        
        local success = false
        pcall(function()
            local result = bedwars.Client:Get(remotes.SummonOwl).instance:InvokeServer(targetPlayer)
            
            if result then
            task.wait(0.05)
            
            pcall(function()
    			bedwars.Client:Get(remotes.UseAbility).instance:FireServer("SUMMON_OWL")
			end)
                
                currentMountedPlayer = targetPlayer
                success = true
            end
        end)
        
        return success
    end
    
    local function demountOwl()
        pcall(function()
            bedwars.Client:Get(remotes.UseAbility).instance:FireServer("DEACTIVE_OWL")
            
            task.wait(0.05)
            
            bedwars.Client:Get(remotes.RemoveOwl).instance:FireServer()
        end)
        
        currentMountedPlayer = nil
    end
    
    local function healTarget()
        pcall(function()
            replicatedStorage:WaitForChild("events-@easy-games/game-core:shared/game-core-networking@getEvents.Events"):WaitForChild("useAbility"):FireServer("OWL_HEAL")
        end)
    end
    
    local function isFalling(player)
        if not player or not player.Character or not player.Character.PrimaryPart then
            return false
        end
        
        local velocity = player.Character.PrimaryPart.AssemblyLinearVelocity.Y
        return velocity < -20
    end
    
	local voidRayParams = RaycastParams.new()
	voidRayParams.FilterType = Enum.RaycastFilterType.Blacklist
	voidRayParams.RespectCanCollide = true

	local function isAboveVoid(player)
		if not player or not player.Character or not player.Character.PrimaryPart then
			return false
		end
		
		local rayOrigin = player.Character.PrimaryPart.Position
		local rayDirection = Vector3.new(0, -1000, 0)
		
		voidRayParams.FilterDescendantsInstances = {player.Character, gameCamera}
		
		local rayResult = workspace:Raycast(rayOrigin, rayDirection, voidRayParams)
		
		if not rayResult then
			return true
		end
		
		return rayResult.Distance > 200
	end
    
    local function activateFly()
        pcall(function()
            replicatedStorage:WaitForChild("events-@easy-games/game-core:shared/game-core-networking@getEvents.Events"):WaitForChild("useAbility"):FireServer("OWL_LIFT")
            
            hasActivatedFly = true
            task.spawn(function()
                task.wait(85)
                hasActivatedFly = false
            end)
        end)
    end
    
    AutoWhisper = vape.Categories.Kits:CreateModule({
        Name = "AutoWhisper",
        Function = function(callback)
            running = callback
            healRunning = callback
            flyRunning = callback
            
            if callback then
                task.spawn(function()
                    while running do
                        if LimitToItem.Enabled and not isHoldingOwlOrb() then
                            task.wait(0.2)
                            continue
                        end
                        
                        local targetPlayer = playersService:FindFirstChild(PlayerDropdown.Value)
                        if targetPlayer then
                            currentTarget = targetPlayer
                            
                            local mountedTo = getMountedPlayer()
                            
                            if mountedTo ~= targetPlayer then
                                if mountedTo and mountedTo ~= targetPlayer then
                                    demountOwl()
                                    task.wait(0.3)
                                end
                                
                                if not mountedTo or mountedTo ~= targetPlayer then
                                    local success = mountBirdToPlayer(targetPlayer)
                                    if not success then
                                        task.wait(0.5)
                                    else
                                        task.wait(1)
                                    end
                                end
                            else
                                task.wait(0.5)
                            end
                        else
                            task.wait(0.5)
                        end
                    end
                end)
                
                if AutoHeal.Enabled then
                    task.spawn(function()
                        while healRunning and AutoHeal.Enabled do
                            if currentTarget then
                                local health, maxHealth = getPlayerHealth(currentTarget)
                                if health and maxHealth and maxHealth > 0 then
                                    local healthPercent = (health / maxHealth) * 100
                                    if healthPercent < AutoHealSlider.Value and healthPercent < 90 then
                                        healTarget()
                                        task.wait(8.5)
                                    end
                                end
                            end
                            
                            task.wait(0.5)
                        end
                    end)
                end
                
                if AutoFly.Enabled then
                    task.spawn(function()
                        while flyRunning and AutoFly.Enabled do
                            if currentTarget and not hasActivatedFly then
                                if isFalling(currentTarget) and isAboveVoid(currentTarget) then
                                    fallCheckTimer = fallCheckTimer + 0.1
                                    
                                    if fallCheckTimer >= 0.5 then
                                        activateFly()
                                        fallCheckTimer = 0
                                    end
                                else
                                    fallCheckTimer = 0
                                end
                            else
                                fallCheckTimer = 0
                            end
                            
                            task.wait(0.1)
                        end
                    end)
                end
                
                AutoWhisper:Clean(playersService.PlayerAdded:Connect(function()
                    task.wait(0.5)
                    local newList = getTeammates(true)
                    if PlayerDropdown then
                        PlayerDropdown:Change(newList)
                        
                        if #newList > 0 then
                            if not PlayerDropdown.Value or PlayerDropdown.Value == "" or not table.find(newList, PlayerDropdown.Value) then
                                PlayerDropdown:SetValue(newList[1])
                            end
                        end
                    end
                end))
                
                AutoWhisper:Clean(playersService.PlayerRemoving:Connect(function(player)
                    task.wait(0.5)
                    local newList = getTeammates(true)
                    if PlayerDropdown then
                        PlayerDropdown:Change(newList)
                        
                        if #newList > 0 then
                            if not PlayerDropdown.Value or PlayerDropdown.Value == "" or not table.find(newList, PlayerDropdown.Value) then
                                PlayerDropdown:SetValue(newList[1])
                            end
                        end
                    end
                    
                    if currentTarget == player then
                        currentTarget = nil
                        currentMountedPlayer = nil
                    end
                end))
                
                AutoWhisper:Clean(lplr:GetAttributeChangedSignal('Team'):Connect(function()
                    task.wait(0.5)
                    local newList = getTeammates(true)
                    if PlayerDropdown then
                        PlayerDropdown:Change(newList)
                        
                        if #newList > 0 then
                            if not PlayerDropdown.Value or PlayerDropdown.Value == "" or not table.find(newList, PlayerDropdown.Value) then
                                PlayerDropdown:SetValue(newList[1])
                            end
                        end
                    end
                    currentTarget = nil
                    currentMountedPlayer = nil
                    hasActivatedFly = false
                end))
                
            else
                running = false
                healRunning = false
                flyRunning = false
                currentTarget = nil
                currentMountedPlayer = nil
                hasActivatedFly = false
                fallCheckTimer = 0
            end
        end,
    })
    
    PlayerDropdown = AutoWhisper:CreateDropdown({
        Name = "Bird Target",
        List = {},
        Function = function(val)
            if val then
                local targetPlayer = playersService:FindFirstChild(val)
                if targetPlayer then
                    currentTarget = targetPlayer
                end
            end
        end,
    })
    RefreshButton = AutoWhisper:CreateButton({
        Name = "Refresh Teammates",
        Function = function()
            task.spawn(function()
                local newList = getTeammates(true)
                
                if PlayerDropdown then
                    pcall(function()
                        PlayerDropdown:Change(newList)
                        
                        if #newList > 0 then
                            if not PlayerDropdown.Value or PlayerDropdown.Value == "" or not table.find(newList, PlayerDropdown.Value) then
                                PlayerDropdown:SetValue(newList[1])
                            else
                                PlayerDropdown:SetValue(PlayerDropdown.Value)
                            end
                        end
                    end)
                end
                
                notif("AutoWhisper", string.format("teammate list (%d teammates)", #newList), 2)
            end)
        end,
    })
    
    LimitToItem = AutoWhisper:CreateToggle({
        Name = "Limit to Owl Orb",
        Default = true,
        Function = function(val)
        end,
    })

    AutoFly = AutoWhisper:CreateToggle({
        Name = "Auto Fly",
        Default = true,
        Function = function(val)
            if AutoWhisper.Enabled then
                if val then
                    flyRunning = true
                    hasActivatedFly = false
                    fallCheckTimer = 0
                    
                    task.spawn(function()
                        while flyRunning and AutoFly.Enabled do
                            if currentTarget and not hasActivatedFly then
                                if isFalling(currentTarget) and isAboveVoid(currentTarget) then
                                    fallCheckTimer = fallCheckTimer + 0.1
                                    
                                    if fallCheckTimer >= 0.5 then
                                        activateFly()
                                        fallCheckTimer = 0
                                    end
                                else
                                    fallCheckTimer = 0
                                end
                            else
                                fallCheckTimer = 0
                            end
                            
                            task.wait(0.1)
                        end
                    end)
                else
                    flyRunning = false
                    hasActivatedFly = false
                    fallCheckTimer = 0
                end
            end
        end,
    })
    
    AutoHeal = AutoWhisper:CreateToggle({
        Name = "Auto Heal",
        Default = true,
        Function = function(val)
            if AutoHealSlider and AutoHealSlider.Object then
                AutoHealSlider.Object.Visible = val
            end
            
            if AutoWhisper.Enabled then
                if val then
                    healRunning = true
                    task.spawn(function()
                        while healRunning and AutoHeal.Enabled do
                            if currentTarget then
                                local health, maxHealth = getPlayerHealth(currentTarget)
                                if not (health and maxHealth and maxHealth > 0) then task.wait(0.5) continue end
                                local healthPercent = (health / maxHealth) * 100
                                if healthPercent < AutoHealSlider.Value and healthPercent < 90 then
                                    healTarget()
                                    task.wait(8.5)
                                end
                            end
                            
                            task.wait(0.5)
                        end
                    end)
                else
                    healRunning = false
                end
            end
        end,
    })
    
    AutoHealSlider = AutoWhisper:CreateSlider({
        Name = "Heal Threshold",
        Min = 1,
        Max = 100,
        Default = 50,
        Suffix = "%",
    })
end)

run(function()
    local StarCollector
    local CollectionToggle
    local Animation
    local RangeSlider
    local ESPToggle
    local ESPNotify
    local ESPBackground
    local ESPColor
    local SwordCheck
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local Reference = {}
    local starCooldowns = {}
    local COOLDOWN_TIME = 0.5
    local lastNotification = 0
    local spawnQueue = {}
    local notificationCooldown = 1
    local collectionRunning = false

    local function sendNotification(count)
        notif("Star ESP", string.format("%d stars spawned", count), 3)
    end

    local function processSpawnQueue()
        if #spawnQueue > 0 then
            local currentTime = tick()
            if currentTime - lastNotification >= notificationCooldown then
                sendNotification(#spawnQueue)
                lastNotification = currentTime
                spawnQueue = {}
            else
                task.delay(notificationCooldown - (currentTime - lastNotification), function()
                    if #spawnQueue > 0 then
                        sendNotification(#spawnQueue)
                        spawnQueue = {}
                    end
                end)
            end
        end
    end

    local function getProperImage(v)
        local parent = v.Parent
        if parent and parent:IsA("Model") then
            local modelName = parent.Name
            if modelName == "CritStar" then
                return bedwars.getIcon({itemType = 'crit_star'}, true)
            elseif modelName == "VitalityStar" then
                return bedwars.getIcon({itemType = 'vitality_star'}, true)
            elseif modelName:find("vitality") or modelName:lower():find("vitality") then
                return bedwars.getIcon({itemType = 'vitality_star'}, true)
            elseif modelName:find("crit") or modelName:lower():find("crit") then
                return bedwars.getIcon({itemType = 'crit_star'}, true)
            end
        end
        return bedwars.getIcon({itemType = 'crit_star'}, true)
    end

    local function Added(v)
        if Reference[v] then return end
        local _bpUserId = v:GetAttribute('PlacedByUserId')
        if _bpUserId then
            local _bpOk, _bpOwner = pcall(function() return playersService:GetPlayerByUserId(_bpUserId) end)
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'stars'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        
        local blur = addBlur(billboard)
        blur.Visible = ESPBackground.Enabled
        
        local image = Instance.new('ImageLabel')
        image.Size = UDim2.fromOffset(36, 36)
        image.Position = UDim2.fromScale(0.5, 0.5)
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.BackgroundColor3 = Color3.fromHSV(ESPColor.Hue, ESPColor.Sat, ESPColor.Value)
        image.BackgroundTransparency = 1 - (ESPBackground.Enabled and ESPColor.Opacity or 0)
        image.BorderSizePixel = 0
        image.Image = getProperImage(v)
        image.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 4)
        uicorner.Parent = image
        
        Reference[v] = billboard
        
        if ESPNotify.Enabled then
            table.insert(spawnQueue, {item = 'star', time = tick()})
            processSpawnQueue()
        end
    end

    local function Removed(v)
        if Reference[v] then
            Reference[v]:Destroy()
            Reference[v] = nil
        end
        starCooldowns[v] = nil
    end

    local function setupESP()
        for _, v in collectionService:GetTagged('stars') do
            if v:IsA("Model") and v.PrimaryPart then
                Added(v.PrimaryPart)
            end
        end

        StarCollector:Clean(collectionService:GetInstanceAddedSignal('stars'):Connect(function(v)
            if v:IsA("Model") and v.PrimaryPart then
                task.wait(0.1)
                Added(v.PrimaryPart)
            end
        end))

        StarCollector:Clean(collectionService:GetInstanceRemovedSignal('stars'):Connect(function(v)
            if v.PrimaryPart then
                Removed(v.PrimaryPart)
            end
        end))
        
        local _scLastUpdate = 0
        StarCollector:Clean(runService.RenderStepped:Connect(function()
            if not ESPToggle.Enabled then return end
            local _now = tick()
            if _now - _scLastUpdate < 0.1 then return end
            _scLastUpdate = _now
            
            for v, billboard in pairs(Reference) do
                if not v or not v.Parent then
                    Removed(v)
                    continue
                end

                local shouldShow = true

                if SwordCheck.Enabled and isSword() then
                    shouldShow = false
                end

                billboard.Enabled = shouldShow
            end
        end))
    end

    local function collectStar(star)
        if not star or not star.Parent then return end
        
        if Animation.Enabled and entitylib.isAlive then
            bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.PUNCH)
            bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
        end
        
        bedwars.StarCollectorController:collectEntity(lplr, star, star.Name)
    end

	local function startCollection()
		collectionRunning = true
		task.spawn(function()
			while collectionRunning and StarCollector.Enabled and CollectionToggle.Enabled do
				if not entitylib.isAlive then
					task.wait(0.1)
					continue
				end

				local localPosition = entitylib.character.RootPart.Position
				local range = RangeSlider.Value
				local collected = false

				for _, v in collectionService:GetTagged('stars') do
					if not collectionRunning or not StarCollector.Enabled or not CollectionToggle.Enabled then
						break
					end

					if v:IsA("Model") and v.PrimaryPart then
						local starPos = v.PrimaryPart.Position
						local distance = (localPosition - starPos).Magnitude

						if distance <= range then
							local lastAttempt = starCooldowns[v]
							if lastAttempt and tick() - lastAttempt < COOLDOWN_TIME then
								continue
							end
							starCooldowns[v] = tick()
							collectStar(v)
							collected = true
							break
						end
					end
				end

				task.wait(collected and 0.1 or 0.2)
			end
			collectionRunning = false
		end)
	end

    StarCollector = vape.Categories.Kits:CreateModule({
        Name = 'AutoStar',
        Function = function(callback)
            if callback then
                if ESPToggle.Enabled then 
                    setupESP() 
                end
                
                if CollectionToggle.Enabled then
                    startCollection()
                end
            else
                collectionRunning = false
                Folder:ClearAllChildren()
                table.clear(Reference)
                table.clear(spawnQueue)
                table.clear(starCooldowns)
                lastNotification = 0
            end
        end,
    })
    
    CollectionToggle = StarCollector:CreateToggle({
        Name = 'Auto Collect',
        Default = true,
        Function = function(callback)
            if Animation and Animation.Object then Animation.Object.Visible = callback end
            if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = callback end
            
            if callback and StarCollector.Enabled then
                startCollection()
            else
                collectionRunning = false
            end
        end
    })
    
    Animation = StarCollector:CreateToggle({
        Name = 'Animation',
        Default = true,
    })
    
    RangeSlider = StarCollector:CreateSlider({
        Name = 'Range',
        Min = 1, 
        Max = 18,
        Default = 10,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    ESPToggle = StarCollector:CreateToggle({
        Name = 'Star ESP',
        Default = false,
        Function = function(callback)
            if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = callback end
            if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = callback end
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            if SwordCheck and SwordCheck.Object then SwordCheck.Object.Visible = callback end
            
            if StarCollector.Enabled then
                if callback then 
                    setupESP() 
                else
                    Folder:ClearAllChildren()
                    table.clear(Reference)
                end
            end
        end
    })
    
    ESPNotify = StarCollector:CreateToggle({
        Name = 'Notify',
        Default = false,
    })
    
    ESPBackground = StarCollector:CreateToggle({
        Name = 'Background',
        Default = true,
        Function = function(callback)
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundTransparency = 1 - (callback and ESPColor.Opacity or 0)
                    if v:FindFirstChild("Blur") then
                        v.Blur.Visible = callback
                    end
                end
            end
        end
    })
    
    ESPColor = StarCollector:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    v.ImageLabel.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Darker = true
    })
    SwordCheck = StarCollector:CreateToggle({
        Name = 'Sword Check',
        Default = false,
    })

    task.defer(function()
        local espOn = ESPToggle and ESPToggle.Enabled
        if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = espOn end
        if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = espOn end
        if ESPColor and ESPColor.Object then ESPColor.Object.Visible = espOn end
        if SwordCheck and SwordCheck.Object then SwordCheck.Object.Visible = espOn end
    end)
end)

run(function()
    local Melody
    local SelfHeal
    local TeammateHeal
    local RangeSlider
    local healRunning = false
    local lastHealTime = 0
    local healCooldown = 1

    local function getItem(itemName)
        if not entitylib.isAlive then return false end
        
        local inventory = store.inventory
        if inventory and inventory.inventory and inventory.inventory.hand then
            local handItem = inventory.inventory.hand
            if handItem and handItem.itemType == itemName then
                return true
            end
        end
        return false
    end

    local function getLowestHealthTeammate()
        if not entitylib.isAlive then return nil end
        
        local localPosition = entitylib.character.RootPart.Position
        local range = RangeSlider.Value
        local lowestHp = math.huge
        local targetEntity = nil
        
        for _, v in entitylib.List do
            if v.Player and v.Player ~= lplr and v.Player:GetAttribute('Team') == lplr:GetAttribute('Team') then
                local distance = (localPosition - v.RootPart.Position).Magnitude
                
                if distance <= range and v.Health < lowestHp and v.Health < v.MaxHealth then
                    lowestHp = v.Health
                    targetEntity = v
                end
            end
        end
        
        return targetEntity
    end

    local function shouldSelfHeal()
        if not entitylib.isAlive then return false end
        
        local currentHealth = lplr.Character:GetAttribute('Health') or 0
        local maxHealth = lplr.Character:GetAttribute('MaxHealth') or 100
        
        return currentHealth < maxHealth
    end

    local function performHeal(target)
        local currentTime = tick()
        if currentTime - lastHealTime < healCooldown then
            return false
        end
        
        if not getItem('guitar') then
            return false
        end
        
        bedwars.Client:Get(remotes.GuitarHeal):SendToServer({
            healTarget = target
        })
        
        lastHealTime = currentTime
        return true
    end

    local function startHealing()
        healRunning = true
        task.spawn(function()
            while healRunning and Melody.Enabled do
                if not entitylib.isAlive then
                    task.wait(0.1)
                    continue
                end
                
                if not getItem('guitar') then
                    task.wait(0.2)
                    continue
                end
                
                local healed = false
                
                if SelfHeal.Enabled and shouldSelfHeal() then
                    if performHeal(lplr.Character) then
                        healed = true
                    end
                end
                
                if not healed and TeammateHeal.Enabled then
                    local teammate = getLowestHealthTeammate()
                    if teammate then
                        if performHeal(teammate.Character) then
                            healed = true
                        end
                    end
                end
                
                task.wait(0.1)
            end
            healRunning = false
        end)
    end

    Melody = vape.Categories.Kits:CreateModule({
        Name = 'AutoMelody',
        Function = function(callback)
            if callback then
                lastHealTime = 0
                startHealing()
            else
                healRunning = false
                lastHealTime = 0
            end
        end,
        Tooltip = 'auto heal yourself and teammates with guitar'
    })
    
    SelfHeal = Melody:CreateToggle({
        Name = 'Self Heal',
        Default = true,
    })
    
    TeammateHeal = Melody:CreateToggle({
        Name = 'Teammate Heal',
        Default = true,
        Function = function(callback)
            if RangeSlider and RangeSlider.Object then
                RangeSlider.Object.Visible = callback
            end
        end
    })
    
    RangeSlider = Melody:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 51,
        Default = 30,
        Decimal = 1,
        Suffix = ' studs',
    })
end)

run(function()
    local autoZenoModule
    local targetSettings
    local targetSelectionMode
    local itemLimitToggle
    local shockwaveToggle
    local shockwaveRadius
    local lightningStrikeToggle
    local lightningStormToggle
    local attackRange
    local actionDelay

    local function fetchAttackItem()
        if itemLimitToggle.Enabled then
            local wizardStaff = (store.hand.tool and store.hand.tool.Name:find('wizard_staff')) and store.hand.tool or nil
            return wizardStaff, wizardStaff and getHotbar(wizardStaff) or nil, wizardStaff and (tonumber(wizardStaff.Name:sub(#wizardStaff.Name, #wizardStaff.Name)) or 1) or nil
        end

        if store.hand.tool and store.hand.tool.Name:find('wizard_staff') then
            local item = store.hand.tool
            return item, getHotbar(item), tonumber(item.Name:sub(#item.Name, #item.Name)) or 1
        end

        for index, item in pairs(store.inventory.inventory.items) do
            if item.itemType:find('wizard_staff') then
                switchItem(item, 0)
                return item, index, tonumber(item.itemType:sub(#item.itemType, #item.itemType)) or 1
            end
        end

        return nil
    end

    autoZenoModule = vape.Categories.Kits:CreateModule({
        Name = 'AutoZeno',
        Function = function(callback)
            if callback then
                repeat
                    if entitylib.isAlive then
                        local staff, _, level = fetchAttackItem()

                        if staff then
                            local playerPosition = entitylib.character.RootPart.Position
                            local nearestEntity = entitylib.EntityPosition({
                                Origin = playerPosition,
                                Range = (attackRange.Value < 6 and shockwaveToggle.Enabled and 7) or attackRange.Value,
                                Part = 'RootPart',
                                Players = targetSettings.Players.Enabled,
                                NPCs = targetSettings.NPCs.Enabled,
                                Sort = sortmethods[Sorts.Value]
                            })

                            if nearestEntity then
                                if shockwaveToggle.Enabled and level > 2 then
                                    if bedwars.AbilityController:canUseAbility('SHOCKWAVE') and (playerPosition - nearestEntity.RootPart.Position).Magnitude <= shockwaveRadius.Value then
                                        bedwars.AbilityController:useAbility('SHOCKWAVE', newproxy(true), {
                                            target = CFrame.lookAt(playerPosition, nearestEntity.RootPart.Position).LookVector
                                        })
                                        task.wait(actionDelay.Value)
                                    end
                                end

                                if lightningStrikeToggle.Enabled and bedwars.AbilityController:canUseAbility('LIGHTNING_STRIKE') then
                                    bedwars.AbilityController:useAbility('LIGHTNING_STRIKE', newproxy(true), {
                                        target = nearestEntity.RootPart.Position + ((nearestEntity.Humanoid.MoveDirection or Vector3.zero) * (1 + lplr:GetNetworkPing()))
                                    })
                                    task.wait(actionDelay.Value)
                                end

                                if lightningStormToggle.Enabled and level > 1 then
                                    if bedwars.AbilityController:canUseAbility('LIGHTNING_STORM') then
                                        bedwars.AbilityController:useAbility('LIGHTNING_STORM', newproxy(true), {
                                            target = nearestEntity.RootPart.Position + ((nearestEntity.Humanoid.MoveDirection or Vector3.zero) * (1 + lplr:GetNetworkPing()))
                                        })
                                        task.wait(actionDelay.Value)
                                    end
                                end
                            end
                        end
                    end
                    task.wait(0.1)
                until not autoZenoModule.Enabled
            end
        end,
    })

    targetSettings = autoZenoModule:CreateTargets({
        Players = true,
        NPCs = false
    })

    local availableSortingMethods = {'Damage', 'Distance'}
    for method in sortmethods do
        if not table.find(availableSortingMethods, method) then
            table.insert(availableSortingMethods, method)
        end
    end

    targetSelectionMode = autoZenoModule:CreateDropdown({
        Name = 'Target Mode',
        List = availableSortingMethods,
        Default = 'Distance'
    })

    itemLimitToggle = autoZenoModule:CreateToggle({
        Name = 'Limit to item',
        Default = true
    })

    lightningStrikeToggle = autoZenoModule:CreateToggle({
        Name = 'Use Lightning Strike',
        Default = true
    })

    lightningStormToggle = autoZenoModule:CreateToggle({
        Name = 'Use Lightning Storm'
    })

    shockwaveToggle = autoZenoModule:CreateToggle({
        Name = 'Auto Shockwave',
        Function = function(enabled)
            pcall(function()
                shockwaveRadius.Object.Visible = enabled
            end)
        end
    })

    shockwaveRadius = autoZenoModule:CreateSlider({
        Name = 'Shockwave Range',
        Visible = false,
        Darker = true,
        Min = 1,
        Max = 12,
        Suffix = function(value)
            return value > 1 and 'studs' or 'stud'
        end,
        Decimal = 5,
        Default = 12
    })

    attackRange = autoZenoModule:CreateSlider({
        Name = 'Attack Range',
        Min = 1,
        Max = 60,
        Default = 35,
        Suffix = function(value)
            return value > 1 and 'studs' or 'stud'
        end,
        Decimal = 5
    })

    actionDelay = autoZenoModule:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 10,
        Default = 0.5,
        Decimal = 5,
        Suffix = function(value)
            return value > 1 and 'secs' or 'sec'
        end
    })
end)

run(function()
    local Gingerbread
    local LimitToItem
    local BreakDelay
    local BreakDelaySlider
    local AutoSwitch
    local SwitchMode
    
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local lastBreakTime = 0
    local lastPlaceTime = 0
    local placeCheckConnection
    local justPlacedGumdrop = false
    local lastPlacedPosition = nil
    
    _G.gingerLock = _G.gingerLock or false
    
    local function getGumdropSlot()
        for i, v in store.inventory.hotbar do
            if v.item and v.item.itemType == "gumdrop_bounce_pad" then
                return i - 1
            end
        end
        return nil
    end
    
    local function getPredictedPosition()
        if not (lplr.Character and lplr.Character.PrimaryPart) then return nil end
        local root = lplr.Character.PrimaryPart
        local velocity = root.AssemblyLinearVelocity
        local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
        local speed = horizontalVelocity.Magnitude
        if speed < 1 then return root.Position end
        local predictionTime = math.clamp(speed / 40, 0.15, 0.35)
        return root.Position + (horizontalVelocity * predictionTime)
    end
    
    local function tryPlaceGumdrop()
        if not AutoSwitch.Enabled or _G.gingerLock then return end
        if not (lplr.Character and lplr.Character.PrimaryPart) then return end
        
        local inFirstPerson = isFirstPerson()
        if SwitchMode.Value == 'First Person' and not inFirstPerson then return end
        if SwitchMode.Value == 'Third Person' and inFirstPerson then return end
        
        local velocity = lplr.Character.PrimaryPart.AssemblyLinearVelocity.Y
        if velocity >= -5 then return end
        
        local gumdropSlot = getGumdropSlot()
        if not gumdropSlot then return end
        
        local root = lplr.Character.PrimaryPart
        local targetPos = getPredictedPosition() or root.Position
        local checkPos = targetPos - Vector3.new(0, 3, 0)
        local groundBlockPos = nil
        
        for i = 1, 16 do
            local testPos = checkPos - Vector3.new(0, 3 * (i - 1), 0)
            local block, blockpos = getPlacedBlock(roundPos(testPos))
            if block then
                groundBlockPos = blockpos * 3
                break
            end
        end
        
        if not groundBlockPos then return end
        
        local distanceToGround = root.Position.Y - groundBlockPos.Y
        if distanceToGround < 9 or distanceToGround > 18 then return end
        
        local placePos = groundBlockPos + Vector3.new(0, 3, 0)
        if lastPlacedPosition and (lastPlacedPosition - placePos).Magnitude < 1 then return end
        if getPlacedBlock(placePos) then return end
        
        _G.gingerLock = true
        
        if hotbarSwitch(gumdropSlot) then
            task.wait(0.03)
            local success = pcall(function()
                bedwars.placeBlock(placePos, "gumdrop_bounce_pad", false)
            end)
            
            if success then
                lastPlaceTime = tick()
                justPlacedGumdrop = true
                lastPlacedPosition = placePos
                
                task.wait(0.03)
                local pickaxeSlot = getPickaxeSlot()
                if pickaxeSlot then
                    hotbarSwitch(pickaxeSlot)
                    task.wait(0.08)
                    local placedBlock = getPlacedBlock(placePos)
                    if placedBlock and placedBlock.Name == "gumdrop_bounce_pad" then
                        task.spawn(bedwars.breakBlock, placedBlock, false, nil, true)
                        lastBreakTime = tick()
                    end
                end
            end
        end
        
        _G.gingerLock = false
    end
    
    Gingerbread = vape.Categories.Kits:CreateModule({
        Name = 'AutoGinger',
        Function = function(callback)
            if callback then
                local old = bedwars.LaunchPadController.attemptLaunch
                bedwars.LaunchPadController.attemptLaunch = function(...)
                    local res = {old(...)}
                    local self, block = ...
                    
                    if block:GetAttribute('PlacedByUserId') == lplr.UserId and
                       (block.Position - entitylib.character.RootPart.Position).Magnitude < 30 then

                        if LimitToItem.Enabled and not isHoldingPickaxe() then
                            return unpack(res)
                        end

                        local inFP = isFirstPerson()
					local cameraAllowed = not AutoSwitch.Enabled or (SwitchMode.Value ~= 'First Person' or inFP) and (SwitchMode.Value ~= 'Third Person' or not inFP)
					local shouldAutoSwitch = AutoSwitch.Enabled and not isHoldingPickaxe() and cameraAllowed and not _G.gingerLock

                        if shouldAutoSwitch then
                            local pickaxeSlot = getPickaxeSlot()
                            if pickaxeSlot then
                                _G.gingerLock = true
                                task.spawn(function()
                                    if hotbarSwitch(pickaxeSlot) then
                                        task.wait(0.03)
                                        task.spawn(bedwars.breakBlock, block, false, nil, true)
                                        task.spawn(bedwars.breakBlock, block, false, nil, true)
                                        lastBreakTime = tick()
                                        justPlacedGumdrop = false
                                    end
                                    _G.gingerLock = false
                                end)
                            end
                        else
                            local currentTime = tick()
                            local shouldBreak = true
                            if not AutoSwitch.Enabled and BreakDelay.Enabled and not justPlacedGumdrop then
                                if (currentTime - lastBreakTime) < BreakDelaySlider.Value then
                                    shouldBreak = false
                                end
                            end
                            if shouldBreak then
                                task.spawn(bedwars.breakBlock, block, false, nil, true)
                                task.spawn(bedwars.breakBlock, block, false, nil, true)
                                lastBreakTime = currentTime
                                justPlacedGumdrop = false
                            end
                        end

                        local cameraAllowed = true
                        if AutoSwitch.Enabled then
                            local inFirstPerson = isFirstPerson()
                            if SwitchMode.Value == 'First Person' and not inFirstPerson then
                                cameraAllowed = false
                            elseif SwitchMode.Value == 'Third Person' and inFirstPerson then
                                cameraAllowed = false
                            end
                        end

                        if isHoldingPickaxe() then
                            local currentTime = tick()
                            local shouldBreak = true
                            
                            if not AutoSwitch.Enabled and BreakDelay.Enabled and not justPlacedGumdrop then
                                if (currentTime - lastBreakTime) < BreakDelaySlider.Value then
                                    shouldBreak = false
                                end
                            end
                            
                            if shouldBreak then
                                task.spawn(bedwars.breakBlock, block, false, nil, true)
                                task.spawn(bedwars.breakBlock, block, false, nil, true)
                                lastBreakTime = currentTime
                                justPlacedGumdrop = false
                            end
                        elseif AutoSwitch.Enabled and cameraAllowed and not _G.gingerLock then
                            local pickaxeSlot = getPickaxeSlot()
                            if pickaxeSlot then
                                _G.gingerLock = true
                                task.spawn(function()
                                    if hotbarSwitch(pickaxeSlot) then
                                        task.wait(0.03)
                                        task.spawn(bedwars.breakBlock, block, false, nil, true)
                                        task.spawn(bedwars.breakBlock, block, false, nil, true)
                                        lastBreakTime = tick()
                                        justPlacedGumdrop = false
                                    end
                                    _G.gingerLock = false
                                end)
                            end
                        end
                    end
                    
                    return unpack(res)
                end
                
				if AutoSwitch.Enabled then
                    if placeCheckConnection then
                        placeCheckConnection:Disconnect()
                        placeCheckConnection = nil
                    end
                    placeCheckConnection = runService.RenderStepped:Connect(function()
                        if not _G.gingerLock and entitylib.isAlive and tick() - lastPlaceTime > 0.15 then
                            tryPlaceGumdrop()
                        end
                    end)
                end
                
                Gingerbread:Clean(function()
                    bedwars.LaunchPadController.attemptLaunch = old
                    if placeCheckConnection then
                        placeCheckConnection:Disconnect()
                        placeCheckConnection = nil
                    end
                end)
            else
                lastBreakTime = 0
                lastPlaceTime = 0
                justPlacedGumdrop = false
                lastPlacedPosition = nil
                _G.gingerLock = false
                if placeCheckConnection then
                    placeCheckConnection:Disconnect()
                    placeCheckConnection = nil
                end
            end
        end,
        Tooltip = 'really just advanced autokit'
    })

    LimitToItem = Gingerbread:CreateToggle({
        Name = 'Limit to Pickaxe',
        Default = true,
    })
    
    BreakDelay = Gingerbread:CreateToggle({
        Name = 'Break Delay',
        Default = false,
        Function = function(callback)
            if BreakDelaySlider and BreakDelaySlider.Object then
                BreakDelaySlider.Object.Visible = callback and not AutoSwitch.Enabled
            end
        end,
    })
    
    BreakDelaySlider = Gingerbread:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
        Visible = false,
    })
    
	AutoSwitch = Gingerbread:CreateToggle({
        Name = 'Auto-Switch',
        Default = false,
        Function = function(callback)
            if SwitchMode and SwitchMode.Object then SwitchMode.Object.Visible = callback end
            if BreakDelay and BreakDelay.Object then BreakDelay.Object.Visible = not callback end
            if BreakDelaySlider and BreakDelaySlider.Object then
                BreakDelaySlider.Object.Visible = (not callback) and BreakDelay.Enabled
            end
            if LimitToItem and LimitToItem.Object then LimitToItem.Object.Visible = not callback end

            if placeCheckConnection then
                placeCheckConnection:Disconnect()
                placeCheckConnection = nil
            end

            if callback and Gingerbread.Enabled then
                placeCheckConnection = runService.RenderStepped:Connect(function()
                    if not _G.gingerLock and entitylib.isAlive and tick() - lastPlaceTime > 0.15 then
                        tryPlaceGumdrop()
                    end
                end)
            end
        end,
    })
    
    SwitchMode = Gingerbread:CreateDropdown({
        Name = 'Camera Mode',
        List = {'Both', 'First Person', 'Third Person'},
        Default = 'Both',
        Visible = false,
    })
end)

run(function()
    local Beekeeper
    local CollectionToggle
	local LimitToNet
	local maxBeehiveLevel = 10
    local maxedBeehives = {}
    local maxedNotificationSent = {}
    local CollectionDelay
    local DelaySlider
    local RangeSlider
    local ESPToggle
    local BeesESP
    local BeesNotify
    local BeesBackground
    local BeesColor
    local BeehiveESP
    local ShowOtherBeehives
    local BeehiveBackground
    local BeehiveColor
    local AutoDeposit
    local DepositDelay
    local DepositDelaySlider
    local DepositRange
    local ESPLimitToNet  
    local collectionRunning = false
    local depositRunning = false
    local BeesFolder = Instance.new('Folder')
    BeesFolder.Parent = vape.gui
    local BeehiveFolder = Instance.new('Folder')
    BeehiveFolder.Parent = vape.gui
    local BeesReference = {}
    local BeehiveReference = {}
    local lastNotification = 0
    local spawnQueue = {}
    local notificationCooldown = 1

    local function sendNotification(count)
        notif("Bee ESP", string.format("%d bees spawned", count), 3)
    end

    local function processSpawnQueue()
        if #spawnQueue > 0 then
            local currentTime = tick()
            if currentTime - lastNotification >= notificationCooldown then
                sendNotification(#spawnQueue)
                lastNotification = currentTime
                spawnQueue = {}
            else
                task.delay(notificationCooldown - (currentTime - lastNotification), function()
                    if #spawnQueue > 0 then
                        sendNotification(#spawnQueue)
                        spawnQueue = {}
                    end
                end)
            end
        end
    end

    local function getBeeIcon()
        return bedwars.getIcon({itemType = 'bee'}, true)
    end

    local function AddedBee(v)
        if BeesReference[v] then return end
        local model = v.Parent
        if model then
            if model.Name:find("TamedBee") or model:FindFirstChild("TamedBee") then
                return 
            end
            
            if model:GetAttribute("IsTamed") or model:GetAttribute("Tamed") then
                return 
            end
            
            for _, tag in pairs(collectionService:GetTags(model)) do
                if tag:lower():find("tamed") then
                    return 
                end
            end
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = BeesFolder
        billboard.Name = 'bee'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        
        local blur = addBlur(billboard)
        blur.Visible = BeesBackground.Enabled
        
        local image = Instance.new('ImageLabel')
        image.Size = UDim2.fromOffset(36, 36)
        image.Position = UDim2.fromScale(0.5, 0.5)
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.BackgroundColor3 = Color3.fromHSV(BeesColor.Hue, BeesColor.Sat, BeesColor.Value)
        image.BackgroundTransparency = 1 - (BeesBackground.Enabled and BeesColor.Opacity or 0)
        image.BorderSizePixel = 0
        image.Image = getBeeIcon()
        image.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 4)
        uicorner.Parent = image
        
        BeesReference[v] = billboard
        
        if BeesNotify.Enabled then
            table.insert(spawnQueue, {item = 'bee', time = tick()})
            processSpawnQueue()
        end
    end

    local function RemovedBee(v)
        if BeesReference[v] then
            BeesReference[v]:Destroy()
            BeesReference[v] = nil
        end
    end

    local function isMyBeehive(beehive)
        if not beehive then return false end
        local placedBy = beehive:GetAttribute("PlacedByUserId")
        return placedBy and placedBy == lplr.UserId
    end
    
    local function getBeehiveOwnerName(beehive)
        if not beehive then return "Unknown" end
        local placedBy = beehive:GetAttribute("PlacedByUserId")
        if not placedBy then return "Unknown" end
        
        local player = game.Players:GetPlayerByUserId(placedBy)
        if player then
            return player.Name
        end
        
        return "Player"
    end

    local function AddedBeehive(beehive)
        local isOwn = isMyBeehive(beehive)
        
        if not isOwn and not (ShowOtherBeehives and ShowOtherBeehives.Enabled) then 
            return 
        end
        
        if BeehiveReference[beehive] then return end
        
        local level = beehive:GetAttribute("Level") or 0
        local isMaxed = level >= maxBeehiveLevel and isOwn
        
        if isMaxed and isOwn then
            maxedBeehives[beehive] = true
        end
        
        local ownerName = isOwn and nil or getBeehiveOwnerName(beehive)
        local hasOwnerName = ownerName ~= nil
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = BeehiveFolder
        billboard.Name = 'beehive-esp'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
        billboard.Size = isMaxed and UDim2.fromOffset(90, 40) or (hasOwnerName and UDim2.fromOffset(120, 40) or UDim2.fromOffset(80, 30))
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = beehive
        
        local blur = addBlur(billboard)
        blur.Visible = BeehiveBackground.Enabled
        
        local frame = Instance.new('Frame')
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = isMaxed and Color3.fromRGB(255, 50, 50) or Color3.fromHSV(BeehiveColor.Hue, BeehiveColor.Sat, BeehiveColor.Value)
        frame.BackgroundTransparency = 1 - (BeehiveBackground.Enabled and (isMaxed and 0.5 or BeehiveColor.Opacity) or 0)
        frame.BorderSizePixel = 0
        frame.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 6)
        uicorner.Parent = frame
        
        if hasOwnerName then
            local nameLabel = Instance.new('TextLabel')
            nameLabel.Name = 'OwnerName'
            nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
            nameLabel.Position = UDim2.new(0, 0, 0, -20)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = ownerName
            nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameLabel.TextSize = 12
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextStrokeTransparency = 0.5
            nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            nameLabel.Parent = billboard
        end
        
        local homeImage = Instance.new('TextLabel')
        homeImage.Size = UDim2.fromOffset(20, 20)
        homeImage.Position = UDim2.new(0, 5, 0.5, 0)
        homeImage.AnchorPoint = Vector2.new(0, 0.5)
        homeImage.BackgroundTransparency = 1
        homeImage.Text = isOwn and "🏠" or "🏘️"
        homeImage.TextSize = 16
        homeImage.Parent = frame
        
        local beeImage = Instance.new('ImageLabel')
        beeImage.Size = UDim2.fromOffset(18, 18)
        beeImage.Position = UDim2.new(0.5, -5, 0.5, 0)
        beeImage.AnchorPoint = Vector2.new(0, 0.5)
        beeImage.BackgroundTransparency = 1
        beeImage.Image = getBeeIcon()
        beeImage.Parent = frame
        
        local levelLabel = Instance.new('TextLabel')
        levelLabel.Name = 'Level'
        levelLabel.Size = UDim2.new(0, 25, 1, 0)
        levelLabel.Position = UDim2.new(1, -30, 0, 0)
        levelLabel.BackgroundTransparency = 1
        levelLabel.Text = tostring(level)
        levelLabel.TextColor3 = isMaxed and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 255, 255)
        levelLabel.TextSize = 16
        levelLabel.Font = Enum.Font.GothamBold
        levelLabel.TextStrokeTransparency = 0.5
        levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        levelLabel.Parent = frame
        
        if isMaxed and isOwn then
            local maxText = Instance.new('TextLabel')
            maxText.Name = 'MaxText'
            maxText.Size = UDim2.new(1, 0, 0.4, 0)
            maxText.Position = UDim2.new(0, 0, 0, hasOwnerName and -40 or -20)
            maxText.BackgroundTransparency = 1
            maxText.Text = "MAX"
            maxText.TextColor3 = Color3.fromRGB(255, 50, 50)
            maxText.TextSize = 12
            maxText.Font = Enum.Font.GothamBold
            maxText.TextStrokeTransparency = 0.5
            maxText.TextStrokeColor3 = Color3.new(0, 0, 0)
            maxText.Parent = billboard
        end
        
        BeehiveReference[beehive] = {
            billboard = billboard,
            levelLabel = levelLabel,
            beehive = beehive,
            isMaxed = isMaxed,
            isOwn = isOwn
        }
        
        local function updateLevel()
            local level = beehive:GetAttribute("Level") or 0
            local isMaxed = level >= maxBeehiveLevel and isOwn
            
            if isMaxed and isOwn then
                maxedBeehives[beehive] = true
                
                if not maxedNotificationSent[beehive] then
                    notif("Bee Keeper", "Beehive is full (MAX)", 3)
                    maxedNotificationSent[beehive] = true
                end
                
                if BeehiveReference[beehive] and BeehiveReference[beehive].billboard then
                    local maxText = BeehiveReference[beehive].billboard:FindFirstChild("MaxText")
                    if not maxText then
                        maxText = Instance.new('TextLabel')
                        maxText.Name = 'MaxText'
                        maxText.Size = UDim2.new(1, 0, 0.4, 0)
                        maxText.Position = UDim2.new(0, 0, 0, hasOwnerName and -40 or -20)
                        maxText.BackgroundTransparency = 1
                        maxText.Text = "MAX"
                        maxText.TextColor3 = Color3.fromRGB(255, 50, 50)
                        maxText.TextSize = 12
                        maxText.Font = Enum.Font.GothamBold
                        maxText.TextStrokeTransparency = 0.5
                        maxText.TextStrokeColor3 = Color3.new(0, 0, 0)
                        maxText.Parent = BeehiveReference[beehive].billboard
                    end
                    
                    local frame = BeehiveReference[beehive].billboard:FindFirstChild("Frame")
                    if frame then
                        frame.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
                        frame.BackgroundTransparency = 1 - (BeehiveBackground.Enabled and 0.5 or 0)
                    end
                end
            else
                if isOwn then
                    maxedBeehives[beehive] = nil
                    maxedNotificationSent[beehive] = nil
                end
                
                if BeehiveReference[beehive] and BeehiveReference[beehive].billboard then
                    local maxText = BeehiveReference[beehive].billboard:FindFirstChild("MaxText")
                    if maxText then
                        maxText:Destroy()
                    end
                    
                    local frame = BeehiveReference[beehive].billboard:FindFirstChild("Frame")
                    if frame then
                        frame.BackgroundColor3 = Color3.fromHSV(BeehiveColor.Hue, BeehiveColor.Sat, BeehiveColor.Value)
                        frame.BackgroundTransparency = 1 - (BeehiveBackground.Enabled and BeehiveColor.Opacity or 0)
                    end
                end
            end
            
            if BeehiveReference[beehive] and BeehiveReference[beehive].levelLabel then
                BeehiveReference[beehive].levelLabel.Text = tostring(level)
            end
            
            if BeehiveReference[beehive] then
                BeehiveReference[beehive].isMaxed = isMaxed
            end
        end
        
        updateLevel()
        
        if isOwn then
            Beekeeper:Clean(beehive:GetAttributeChangedSignal("Level"):Connect(updateLevel))
        else
            Beekeeper:Clean(beehive:GetAttributeChangedSignal("Level"):Connect(function()
                local level = beehive:GetAttribute("Level") or 0
                if BeehiveReference[beehive] and BeehiveReference[beehive].levelLabel then
                    BeehiveReference[beehive].levelLabel.Text = tostring(level)
                end
            end))
        end
    end


    local function RemovedBeehive(beehive)
        if BeehiveReference[beehive] then
            BeehiveReference[beehive].billboard:Destroy()
            BeehiveReference[beehive] = nil
        end
    end

    local function setupBeesESP()
        for _, v in collectionService:GetTagged('bee') do
            if v:IsA("Model") and v.PrimaryPart then
                if not v.Name:find("TamedBee") and not v:FindFirstChild("TamedBee") then
                    AddedBee(v.PrimaryPart)
                end
            end
        end

        Beekeeper:Clean(collectionService:GetInstanceAddedSignal('bee'):Connect(function(v)
            if v:IsA("Model") and v.PrimaryPart then
                task.wait(0.1)
                if not v.Name:find("TamedBee") and not v:FindFirstChild("TamedBee") then
                    AddedBee(v.PrimaryPart)
                end
            end
        end))

        Beekeeper:Clean(collectionService:GetInstanceRemovedSignal('bee'):Connect(function(v)
            if v.PrimaryPart then
                RemovedBee(v.PrimaryPart)
            end
        end))
        

    end

    local function setupBeehiveESP()
        for _, beehive in collectionService:GetTagged('beehive') do
            AddedBeehive(beehive)
        end

        Beekeeper:Clean(collectionService:GetInstanceAddedSignal('beehive'):Connect(function(beehive)
            task.wait(0.1)
            AddedBeehive(beehive)
        end))

        Beekeeper:Clean(collectionService:GetInstanceRemovedSignal('beehive'):Connect(function(beehive)
            RemovedBeehive(beehive)
        end))
    end

    local function isHoldingBeeNet()
        if not store.hand or not store.hand.tool then return false end
        return store.hand.tool.Name == 'bee_net' or store.hand.tool.Name == 'bee-net'
    end

    local function startCollection()
        collectionRunning = true
        task.spawn(function()
            while collectionRunning and Beekeeper.Enabled and CollectionToggle.Enabled do
                if not entitylib.isAlive then 
                    task.wait(0.1) 
                    continue 
                end
                
                if LimitToNet.Enabled and not isHoldingBeeNet() then
                    task.wait(0.5)
                    continue
                end
                
                local localPosition = entitylib.character.RootPart.Position
                local range = RangeSlider.Value
                local beesFound = false
                
                for _, v in collectionService:GetTagged('bee') do
                    if not collectionRunning or not Beekeeper.Enabled or not CollectionToggle.Enabled then 
                        break 
                    end
                    
                    if LimitToNet.Enabled and not isHoldingBeeNet() then
                        break
                    end
                    
                    if v:IsA("Model") and v.PrimaryPart then
                        local beePos = v.PrimaryPart.Position
                        local distance = (localPosition - beePos).Magnitude
                        
                        if distance <= range then
                            beesFound = true
                            
                            if CollectionDelay.Enabled and DelaySlider.Value > 0 then
                                task.wait(DelaySlider.Value)
                            end
                            
                            if LimitToNet.Enabled and not isHoldingBeeNet() then
                                break
                            end
                            
                            local beeId = v:GetAttribute('BeeId')
                            if beeId then
                                bedwars.Client:Get(remotes.BeePickup):SendToServer({beeId = beeId})
                                task.wait(0.1)
                            end
                        end
                    end
                end
                
                if not beesFound then
                    task.wait(0.2)
                else
                    task.wait(0.1)
                end
            end
            collectionRunning = false
        end)
    end

    local function startDeposit()
        depositRunning = true
        task.spawn(function()
            while depositRunning and Beekeeper.Enabled and AutoDeposit.Enabled do
                if not entitylib.isAlive then 
                    task.wait(0.1) 
                    continue 
                end
                
                local currentTool = store.hand and store.hand.tool
                if not currentTool or currentTool.Name ~= 'bee' then
                    task.wait(0.1)
                    continue
                end
                
                local localPosition = entitylib.character.RootPart.Position
                local range = DepositRange.Value
                local depositedThisCycle = false
                
                local availableBeehives = {}
                for _, beehive in collectionService:GetTagged('beehive') do
                    if isMyBeehive(beehive) and not maxedBeehives[beehive] then
                        local beehivePos = beehive.Position
                        local distance = (localPosition - beehivePos).Magnitude
                        
                        if distance <= range then
                            table.insert(availableBeehives, {
                                beehive = beehive,
                                distance = distance
                            })
                        end
                    end
                end
                
                table.sort(availableBeehives, function(a, b)
                    return a.distance < b.distance
                end)
                
                for _, beehiveData in ipairs(availableBeehives) do
                    if not depositRunning or not Beekeeper.Enabled or not AutoDeposit.Enabled then 
                        break 
                    end
                    local beehive = beehiveData.beehive
                    if maxedBeehives[beehive] then
                        continue
                    end
                    
                    local prompt = beehive:FindFirstChildOfClass("ProximityPrompt")
                    
                    if prompt and prompt.Enabled then
                        if DepositDelay.Enabled and DepositDelaySlider.Value > 0 then
                            local originalDuration = prompt.HoldDuration
                            prompt.HoldDuration = DepositDelaySlider.Value
                            
                            if fireproximityprompt then
                                fireproximityprompt(prompt)
                            else
                                prompt:InputHoldBegin()
                                task.wait(DepositDelaySlider.Value)
                                prompt:InputHoldEnd()
                            end
                            
                            task.wait(DepositDelaySlider.Value + 0.1)
                            prompt.HoldDuration = originalDuration
                        else
                            if fireproximityprompt then
                                fireproximityprompt(prompt)
                            else
                                prompt:InputHoldBegin()
                                prompt:InputHoldEnd()
                            end
                            task.wait(0.1)
                        end
                        
                        depositedThisCycle = true
                        break 
                    end
                end
                
                if not depositedThisCycle and #availableBeehives > 0 then
                    local allMaxed = true
                    for _, beehiveData in ipairs(availableBeehives) do
                        if not maxedBeehives[beehiveData.beehive] then
                            allMaxed = false
                            break
                        end
                    end
                    
                    if allMaxed then
                        notif("Bee Keeper", "All nearby beehives are full", 3)
                    end
                end
                
                task.wait(depositedThisCycle and 0.3 or 0.2)
            end
            depositRunning = false
        end)
    end

    Beekeeper = vape.Categories.Kits:CreateModule({
        Name = 'AutoBeekeeper',
        Function = function(callback)
            if callback then
                if ESPToggle.Enabled then
                    if BeesESP.Enabled then
                        setupBeesESP()
                    end
                    if BeehiveESP.Enabled then
                        setupBeehiveESP()
                    end
                end
                
                if CollectionToggle.Enabled then
                    startCollection()
                end
                
                if AutoDeposit.Enabled then
                    startDeposit()
                end
                
                local _bkLastUpdate = 0
                Beekeeper:Clean(runService.RenderStepped:Connect(function()
                    if not ESPToggle.Enabled then return end
                    local _now = tick()
                    if _now - _bkLastUpdate < 0.1 then return end
                    _bkLastUpdate = _now
                    
                    for v, billboard in pairs(BeesReference) do
                        if not v or not v.Parent then
                            RemovedBee(v)
                            continue
                        end

                        local shouldShow = true

                        if ESPLimitToNet.Enabled and not isHoldingBeeNet() then
                            shouldShow = false
                        end

                        billboard.Enabled = shouldShow
                    end
                    
                    for beehive, ref in pairs(BeehiveReference) do
                        if not beehive or not beehive.Parent then
                            RemovedBeehive(beehive)
                            continue
                        end

                        local shouldShow = true

                        if ESPLimitToNet.Enabled and not isHoldingBeeNet() then
                            shouldShow = false
                        end

                        if ref.billboard then
                            ref.billboard.Enabled = shouldShow
                        end
                    end
                end))
            else
                collectionRunning = false
                depositRunning = false
                BeesFolder:ClearAllChildren()
                BeehiveFolder:ClearAllChildren()
                table.clear(BeesReference)
                table.clear(BeehiveReference)
                table.clear(spawnQueue)
                lastNotification = 0
            end
        end,
    })
    
    CollectionToggle = Beekeeper:CreateToggle({
        Name = 'Auto Collect',
        Default = true,
        Function = function(callback)
            if LimitToNet and LimitToNet.Object then LimitToNet.Object.Visible = callback end
            if CollectionDelay and CollectionDelay.Object then CollectionDelay.Object.Visible = callback end
            if DelaySlider and DelaySlider.Object then DelaySlider.Object.Visible = (callback and CollectionDelay.Enabled) end
            if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = callback end
            
            if callback and Beekeeper.Enabled then
                startCollection()
            else
                collectionRunning = false
            end
        end
    })
    
    LimitToNet = Beekeeper:CreateToggle({
        Name = 'Limit to Net',
        Default = false,
    })
    
    CollectionDelay = Beekeeper:CreateToggle({
        Name = 'Collection Delay',
        Default = false,
        Function = function(callback)
            if DelaySlider and DelaySlider.Object then
                DelaySlider.Object.Visible = callback
            end
        end
    })
    
    DelaySlider = Beekeeper:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
    })
    
    RangeSlider = Beekeeper:CreateSlider({
        Name = 'Range',
        Min = 1, 
        Max = 30,
        Default = 18,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    ESPToggle = Beekeeper:CreateToggle({
        Name = 'ESP',
        Default = true,
		Function = function(callback)
			if BeesESP and BeesESP.Object then BeesESP.Object.Visible = callback end
			if BeehiveESP and BeehiveESP.Object then BeehiveESP.Object.Visible = callback end
			if ESPLimitToNet and ESPLimitToNet.Object then ESPLimitToNet.Object.Visible = callback end

			if not callback then
				if BeesNotify and BeesNotify.Object then BeesNotify.Object.Visible = false end
				if BeesBackground and BeesBackground.Object then BeesBackground.Object.Visible = false end
				if BeesColor and BeesColor.Object then BeesColor.Object.Visible = false end
				if ShowOtherBeehives and ShowOtherBeehives.Object then ShowOtherBeehives.Object.Visible = false end
				if BeehiveBackground and BeehiveBackground.Object then BeehiveBackground.Object.Visible = false end
				if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = false end
			else
				if BeesESP and BeesESP.Enabled then
					if BeesNotify and BeesNotify.Object then BeesNotify.Object.Visible = true end
					if BeesBackground and BeesBackground.Object then BeesBackground.Object.Visible = true end
					if BeesColor and BeesColor.Object then BeesColor.Object.Visible = BeesBackground.Enabled end
				end
				if BeehiveESP and BeehiveESP.Enabled then
					if ShowOtherBeehives and ShowOtherBeehives.Object then ShowOtherBeehives.Object.Visible = true end
					if BeehiveBackground and BeehiveBackground.Object then BeehiveBackground.Object.Visible = true end
					if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = BeehiveBackground.Enabled end
				end
			end

			if Beekeeper.Enabled then
				if callback then
					if BeesESP.Enabled then setupBeesESP() end
					if BeehiveESP.Enabled then setupBeehiveESP() end
				else
					BeesFolder:ClearAllChildren()
					BeehiveFolder:ClearAllChildren()
					table.clear(BeesReference)
					table.clear(BeehiveReference)
				end
			end
		end
    })
    
    ESPLimitToNet = Beekeeper:CreateToggle({
        Name = 'Limit to Net',
        Default = false,
    })
    
    BeesESP = Beekeeper:CreateToggle({
        Name = 'Bees',
        Default = false,
        Function = function(callback)
            if BeesNotify and BeesNotify.Object then BeesNotify.Object.Visible = callback end
            if BeesBackground and BeesBackground.Object then BeesBackground.Object.Visible = callback end
            if BeesColor and BeesColor.Object then BeesColor.Object.Visible = callback end
            
            if Beekeeper.Enabled and ESPToggle.Enabled then
                if callback then setupBeesESP() else
                    BeesFolder:ClearAllChildren()
                    table.clear(BeesReference)
                end
            end
        end
    })
    
    BeesNotify = Beekeeper:CreateToggle({
        Name = 'Notify',
        Default = false,
    })
    
    BeesBackground = Beekeeper:CreateToggle({
        Name = 'Background',
        Default = true,
        Function = function(callback)
            if BeesColor and BeesColor.Object then BeesColor.Object.Visible = callback end
            for _, v in BeesReference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundTransparency = 1 - (callback and BeesColor.Opacity or 0)
                    if v:FindFirstChild("Blur") then
                        v.Blur.Visible = callback
                    end
                end
            end
        end
    })
    
	BeesColor = Beekeeper:CreateColorSlider({
		Name = 'Background Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			for _, v in BeesReference do
				if v and v:FindFirstChild("ImageLabel") then
					v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
					v.ImageLabel.BackgroundTransparency = 1 - opacity
				end
			end
		end,
		Darker = true
	})
    
    BeehiveESP = Beekeeper:CreateToggle({
        Name = 'Beehives',
        Default = false,
        Function = function(callback)
            if ShowOtherBeehives and ShowOtherBeehives.Object then ShowOtherBeehives.Object.Visible = callback end
            if BeehiveBackground and BeehiveBackground.Object then BeehiveBackground.Object.Visible = callback end
            if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = callback end
            
            if Beekeeper.Enabled and ESPToggle.Enabled then
                if callback then setupBeehiveESP() else
                    BeehiveFolder:ClearAllChildren()
                    table.clear(BeehiveReference)
                end
            end
        end
    })
    
    ShowOtherBeehives = Beekeeper:CreateToggle({
        Name = 'Show Others',
        Default = false,
        Function = function(callback)
            if Beekeeper.Enabled and ESPToggle.Enabled and BeehiveESP.Enabled then
                BeehiveFolder:ClearAllChildren()
                table.clear(BeehiveReference)
                setupBeehiveESP()
            end
        end
    })
    
    BeehiveBackground = Beekeeper:CreateToggle({
        Name = 'Beehive Background',
        Default = true,
        Function = function(callback)
            if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = callback end
            for _, ref in BeehiveReference do
                if ref and ref.billboard then
                    local frame = ref.billboard:FindFirstChild("Frame")
                    if frame then
                        if ref.isMaxed and ref.isOwn then
                            frame.BackgroundTransparency = 1 - (callback and 0.5 or 0)
                        else
                            frame.BackgroundTransparency = 1 - (callback and BeehiveColor.Opacity or 0)
                        end
                    end
                    if ref.billboard:FindFirstChild("Blur") then
                        ref.billboard.Blur.Visible = callback
                    end
                end
            end
        end
    })
    
    BeehiveColor = Beekeeper:CreateColorSlider({
        Name = 'Beehive Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, ref in BeehiveReference do
                if ref and ref.billboard then
                    local frame = ref.billboard:FindFirstChild("Frame")
                    if frame and not (ref.isMaxed and ref.isOwn) then
                        frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                        frame.BackgroundTransparency = 1 - opacity
                    end
                end
            end
        end,
        Darker = true
    })
    
    AutoDeposit = Beekeeper:CreateToggle({
        Name = 'Auto Deposit',
        Default = false,
		Function = function(callback)
			if DepositDelay and DepositDelay.Object then DepositDelay.Object.Visible = callback end
			if DepositDelaySlider and DepositDelaySlider.Object then DepositDelaySlider.Object.Visible = (callback and DepositDelay.Enabled) end
			if DepositRange and DepositRange.Object then DepositRange.Object.Visible = callback end
			
			if not callback then
				if DepositDelaySlider and DepositDelaySlider.Object then DepositDelaySlider.Object.Visible = false end
			end

			if callback and Beekeeper.Enabled then
				startDeposit()
			else
				depositRunning = false
			end
		end
    })
    
    DepositDelay = Beekeeper:CreateToggle({
        Name = 'Deposit Delay',
        Default = false,
        Function = function(callback)
            if DepositDelaySlider and DepositDelaySlider.Object then
                DepositDelaySlider.Object.Visible = callback
            end
        end
    })
    
    DepositDelaySlider = Beekeeper:CreateSlider({
        Name = 'Deposit Delay',
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
    })
    
    DepositRange = Beekeeper:CreateSlider({
        Name = 'Deposit Range',
        Min = 1,
        Max = 15,
        Default = 10,
        Decimal = 1,
        Suffix = ' studs',
    })
	task.defer(function()
		if DelaySlider and DelaySlider.Object then DelaySlider.Object.Visible = CollectionDelay.Enabled end
		if not ESPToggle.Enabled or not BeesESP.Enabled then
			if BeesNotify and BeesNotify.Object then BeesNotify.Object.Visible = false end
			if BeesBackground and BeesBackground.Object then BeesBackground.Object.Visible = false end
			if BeesColor and BeesColor.Object then BeesColor.Object.Visible = false end
		else
			if BeesColor and BeesColor.Object then BeesColor.Object.Visible = BeesBackground.Enabled end
		end

		if not ESPToggle.Enabled or not BeehiveESP.Enabled then
			if ShowOtherBeehives and ShowOtherBeehives.Object then ShowOtherBeehives.Object.Visible = false end
			if BeehiveBackground and BeehiveBackground.Object then BeehiveBackground.Object.Visible = false end
			if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = false end
		else
			if BeehiveColor and BeehiveColor.Object then BeehiveColor.Object.Visible = BeehiveBackground.Enabled end
		end

		if AutoDeposit and not AutoDeposit.Enabled then
			if DepositDelay and DepositDelay.Object then DepositDelay.Object.Visible = false end
			if DepositDelaySlider and DepositDelaySlider.Object then DepositDelaySlider.Object.Visible = false end
			if DepositRange and DepositRange.Object then DepositRange.Object.Visible = false end
		end

		if DepositDelaySlider and DepositDelaySlider.Object then
			DepositDelaySlider.Object.Visible = (AutoDeposit.Enabled and DepositDelay.Enabled)
		end
	end)
end)

run(function()
    local AutoDrill
    local DrillESP
    local TeamCheck
    local Background
    local Color = {}
    local Reference = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local AutoAttack
    local AttackRange
    local attackRunning = false
    local lastAttackTime = 0
    local espConnections = {}
    local Players = playersService
    local lplr = Players.LocalPlayer
    local RunService = runService
    local Workspace = game:GetService("Workspace")
    
    local function isMyDrill(drill)
        if not drill then return false end
        local placerId = drill:GetAttribute("PlacedByUserId")
        return placerId and placerId == lplr.UserId
    end
    
    local function isTeammate(drill)
        if not TeamCheck.Enabled then return false end
        local placerId = drill:GetAttribute("PlacedByUserId")
        if placerId then
            local placer = playersService:GetPlayerByUserId(placerId)
            if placer and placer.Team == lplr.Team then
                return true
            end
        end
        return false
    end
    
    local function getDrillInfo(drill)
        local itemType = drill:GetAttribute("ItemType")
        local health = drill:GetAttribute("Health") or 0
        local maxHealth = drill:GetAttribute("MaxHealth") or 750
        local amount = 0
        if itemType then
            amount = drill:GetAttribute(itemType) or 0
        end
        return itemType, amount, health, maxHealth
    end
    
    local function getProperIcon(iconType)
        if not iconType then return nil end
        if not bedwars or not bedwars.getIcon then
            return "rbxasset://textures/ui/GuiImagePlaceholder.png"
        end
        local success, icon = pcall(function()
            return bedwars.getIcon({itemType = iconType}, true)
        end)
        if not success or not icon or icon == "" then
            return "rbxasset://textures/ui/GuiImagePlaceholder.png"
        end
        return icon
    end
    
    local function createESP(drill)
        if isTeammate(drill) then return end
        if Reference[drill] then return end
        local head = drill:FindFirstChild("Head")
        if not head then return end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'drill-esp'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(110, 26)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = head
        
        local blur = addBlur(billboard)
        blur.Visible = Background.Enabled
        
        local frame = Instance.new('Frame')
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
        frame.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0.3)
        frame.BorderSizePixel = 0
        frame.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 6)
        uicorner.Parent = frame
        
        local drillIcon = getProperIcon('drill')
        if drillIcon then
            local drillImage = Instance.new('ImageLabel')
            drillImage.Name = 'DrillIcon'
            drillImage.Size = UDim2.fromOffset(18, 18)
            drillImage.Position = UDim2.new(0, 4, 0.5, 0)
            drillImage.AnchorPoint = Vector2.new(0, 0.5)
            drillImage.BackgroundTransparency = 1
            drillImage.Image = drillIcon
            drillImage.Parent = frame
        end
        
        local healthLabel = Instance.new('TextLabel')
        healthLabel.Name = 'Health'
        healthLabel.Size = UDim2.new(0, 32, 1, 0)
        healthLabel.Position = UDim2.new(0, 25, 0, 0)
        healthLabel.BackgroundTransparency = 1
        healthLabel.Text = "750"
        healthLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        healthLabel.TextSize = 12
        healthLabel.Font = Enum.Font.GothamBold
        healthLabel.TextStrokeTransparency = 0.5
        healthLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        healthLabel.TextXAlignment = Enum.TextXAlignment.Left
        healthLabel.Parent = frame
        
        local resourceImage = Instance.new('ImageLabel')
        resourceImage.Name = 'ResourceIcon'
        resourceImage.Size = UDim2.fromOffset(16, 16)
        resourceImage.Position = UDim2.new(0, 62, 0.5, 0)
        resourceImage.AnchorPoint = Vector2.new(0, 0.5)
        resourceImage.BackgroundTransparency = 1
        resourceImage.Image = ""
        resourceImage.Parent = frame
        
        local amountLabel = Instance.new('TextLabel')
        amountLabel.Name = 'Amount'
        amountLabel.Size = UDim2.new(0, 28, 1, 0)
        amountLabel.Position = UDim2.new(1, -30, 0, 0)
        amountLabel.BackgroundTransparency = 1
        amountLabel.Text = "0"
        amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        amountLabel.TextSize = 12
        amountLabel.Font = Enum.Font.GothamBold
        amountLabel.TextStrokeTransparency = 0.5
        amountLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        amountLabel.TextXAlignment = Enum.TextXAlignment.Left
        amountLabel.Parent = frame
        
        Reference[drill] = {
            billboard = billboard,
            frame = frame,
            healthLabel = healthLabel,
            resourceImage = resourceImage,
            amountLabel = amountLabel
        }
    end
    
    local function updateESP(drill)
        local ref = Reference[drill]
        if not ref then return end
        local itemType, amount, health, maxHealth = getDrillInfo(drill)
        
        if ref.healthLabel then
            ref.healthLabel.Text = tostring(math.floor(health))
            local healthPercent = health / maxHealth
            if healthPercent > 0.6 then
                ref.healthLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
            elseif healthPercent > 0.3 then
                ref.healthLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
            else
                ref.healthLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
            end
        end
        
        if itemType then
            if ref.resourceImage then
                local resourceIcon = getProperIcon(itemType)
                if resourceIcon then
                    ref.resourceImage.Image = resourceIcon
                end
            end
            if ref.amountLabel then
                ref.amountLabel.Text = tostring(math.floor(amount))
            end
        else
            if ref.resourceImage then
                ref.resourceImage.Image = ""
            end
            if ref.amountLabel then
                ref.amountLabel.Text = "0"
            end
        end
    end
    
    local function findAllDrills()
        local drillGroup = Workspace:FindFirstChild("Drill")
        if drillGroup and drillGroup:IsA("Model") then
            if not isTeammate(drillGroup) then
                createESP(drillGroup)
            end
        end
        
        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name == "Drill" and obj ~= drillGroup then
                if not isTeammate(obj) then
                    createESP(obj)
                end
            end
        end
    end
    
    local function refreshESP()
        Folder:ClearAllChildren()
        table.clear(Reference)
        if DrillESP.Enabled then
            findAllDrills()
        end
    end
    
    local function setupESPConnections()
        for _, conn in pairs(espConnections) do
            if conn and conn.Disconnect then
                conn:Disconnect()
            end
        end
        table.clear(espConnections)
        
        table.insert(espConnections, Workspace.DescendantAdded:Connect(function(obj)
            if not DrillESP.Enabled then return end
            if obj:IsA("Model") and obj.Name == "Drill" then
                task.wait(0.1)
                if not isTeammate(obj) then
                    createESP(obj)
                end
            end
        end))
        
        table.insert(espConnections, Workspace.DescendantRemoving:Connect(function(obj)
            if obj:IsA("Model") and obj.Name == "Drill" and Reference[obj] then
                if Reference[obj].billboard then
                    Reference[obj].billboard:Destroy()
                end
                Reference[obj] = nil
            end
        end))
        
		local drillLastUpdate = 0
		table.insert(espConnections, RunService.Heartbeat:Connect(function()
			if not DrillESP.Enabled then return end
			local now = tick()
			if now - drillLastUpdate < 0.1 then return end
			drillLastUpdate = now
			for drill, ref in pairs(Reference) do
				if drill and drill.Parent then
					updateESP(drill)
				else
					if ref.billboard then
						ref.billboard:Destroy()
					end
					Reference[drill] = nil
				end
			end
		end))
    end
    
    local function disconnectESP()
        for _, conn in pairs(espConnections) do
            if conn and conn.Disconnect then
                conn:Disconnect()
            end
        end
        table.clear(espConnections)
    end
    
    local function getAttackData()
        if not entitylib.isAlive then return false end
        local hand = store.hand
        if not hand or not hand.tool then return false end
        if hand.tool.Name ~= "drill_controller" and hand.itemType ~= "drill_controller" then
            return false
        end
        return true
    end
    
    local function getEnemiesNearDrill(drill)
        local enemies = {}
        local head = drill:FindFirstChild("Head")
        if not head then return enemies end
        
        for _, player in Players:GetPlayers() do
            if player ~= lplr and player.Team ~= lplr.Team then
                local char = player.Character
                if char then
                    local humanoid = char:FindFirstChild("Humanoid")
                    local rootPart = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("RootPart")
                    if humanoid and humanoid.Health > 0 and rootPart then
                        local distance = (head.Position - rootPart.Position).Magnitude
                        if distance <= AttackRange.Value then
                            table.insert(enemies, {
                                player = player,
                                character = char,
                                position = rootPart.Position,
                                distance = distance
                            })
                        end
                    end
                end
            end
        end
        return enemies
    end
    
    local function startAutoAttack()
        attackRunning = true
        task.spawn(function()
            while attackRunning and AutoDrill.Enabled and AutoAttack.Enabled do
                if not entitylib.isAlive then
                    task.wait(0.1)
                    continue
                end
                
                local canAttack = getAttackData()
                if not canAttack then
                    task.wait(0.1)
                    continue
                end
                
                if (tick() - lastAttackTime) < 0.3 then
                    task.wait(0.05)
                    continue
                end
                
                local attacked = false
                local drill = Workspace:FindFirstChild("Drill")
                if drill and drill:IsA("Model") and isMyDrill(drill) then
                    local enemies = getEnemiesNearDrill(drill)
                    if #enemies > 0 then
                        table.sort(enemies, function(a, b)
                            return a.distance < b.distance
                        end)
                        local target = enemies[1]
                        pcall(function()
                            bedwars.Client:Get(remotes.DrillAttack):FireServer({
                                targetPosition = target.position
                            })
                        end)
                        lastAttackTime = tick()
                        attacked = true
                    end
                end
                
				if not attacked then
					local drillFolder = Workspace:FindFirstChild("Drills") or Workspace
					for _, obj in pairs(drillFolder:GetChildren()) do
						if attacked then break end
						if obj:IsA("Model") and obj.Name == "Drill" and isMyDrill(obj) then
							local enemies = getEnemiesNearDrill(obj)
							if #enemies > 0 then
								table.sort(enemies, function(a, b)
									return a.distance < b.distance
								end)
								local target = enemies[1]
								pcall(function()
									bedwars.Client:Get(remotes.DrillAttack).instance:FireServer({
										targetPosition = target.position
									})
								end)
								lastAttackTime = tick()
								attacked = true
								break
							end
						end
					end
				end
                
                if not attacked then
                    task.wait(0.1)
                else
                    task.wait(0.3)
                end
            end
            attackRunning = false
        end)
    end
    
    AutoDrill = vape.Categories.Kits:CreateModule({
        Name = 'AutoDrill',
        Function = function(callback)
            if callback then
                if AutoAttack.Enabled then
                    startAutoAttack()
                end
            else
                attackRunning = false
                disconnectESP()
                Folder:ClearAllChildren()
                table.clear(Reference)
            end
        end,
    })
    
    DrillESP = AutoDrill:CreateToggle({
        Name = 'Drill ESP',
        Default = false,
        Function = function(callback)
            if TeamCheck.Object then TeamCheck.Object.Visible = callback end
            if Background.Object then Background.Object.Visible = callback end
            if Color.Object then Color.Object.Visible = callback end
            if callback then
                setupESPConnections()
                findAllDrills()
            else
                disconnectESP()
                Folder:ClearAllChildren()
                table.clear(Reference)
            end
        end
    })
    
    TeamCheck = AutoDrill:CreateToggle({
        Name = 'Team Check',
        Default = true,
        Function = function(callback)
            if DrillESP.Enabled then
                refreshESP()
            end
        end
    })
    TeamCheck.Object.Visible = false
    
    Background = AutoDrill:CreateToggle({
        Name = 'Background',
        Default = true,
        Function = function(callback)
            if Color.Object then Color.Object.Visible = callback end
            for _, ref in pairs(Reference) do
                if ref.frame then
                    ref.frame.BackgroundTransparency = 1 - (callback and Color.Opacity or 0.3)
                    if ref.billboard and ref.billboard.Blur then
                        ref.billboard.Blur.Visible = callback
                    end
                end
            end
        end
    })
    Background.Object.Visible = false
    
    Color = AutoDrill:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.3,
        Function = function(hue, sat, val, opacity)
            Color.Hue = hue
            Color.Sat = sat
            Color.Value = val
            Color.Opacity = opacity
            for _, ref in pairs(Reference) do
                if ref.frame then
                    ref.frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    ref.frame.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Darker = true
    })
    Color.Object.Visible = false
    
    AutoAttack = AutoDrill:CreateToggle({
        Name = 'Auto Attack',
        Default = false,
        Function = function(callback)
            if AttackRange.Object then AttackRange.Object.Visible = callback end
            if callback and AutoDrill.Enabled then
                startAutoAttack()
            else
                attackRunning = false
            end
        end
    })
    
    AttackRange = AutoDrill:CreateSlider({
        Name = 'Attack Range',
        Min = 10,
        Max = 20,
        Default = 20,
        Suffix = ' studs',
    })
    AttackRange.Object.Visible = false
end)

run(function()
    local DisableStreamer
    local old = {}
    local oldLevels = {}
    local oldUsernames = {}
    local levelMap = {}
    local updaterThread = nil

    DisableStreamer = vape.Categories.Legit:CreateModule({
        Name = 'DisableStreamer',
        Function = function(callback)
            if callback then
                for _, plrs in playersService:GetPlayers() do
                    if plrs == lplr then continue end
                    
                    local disguiseName = plrs:GetAttribute("DisguiseDisplayName")
                    if disguiseName and disguiseName ~= "" then
                        old[plrs] = disguiseName
                        plrs:SetAttribute("DisguiseDisplayName", "")
                    end

                    local disguiseUsername = plrs:GetAttribute("DisguiseUsername")
                    if disguiseUsername and disguiseUsername ~= "" then
                        oldUsernames[plrs] = disguiseUsername
                        plrs:SetAttribute("DisguiseUsername", "")
                    end

                    local playerLevel = plrs:GetAttribute("PlayerLevel")
                    if playerLevel then
                        oldLevels[plrs] = playerLevel
                        levelMap[plrs.Name] = playerLevel
                    end
                end

                pcall(function()
                    bedwars.StreamerModeController:updateNametags(true)
                end)

                local running = true
                updaterThread = task.spawn(function()
                    while running do
                        local tabList = lplr.PlayerGui:FindFirstChild("TabListScreenGui")
                        if tabList then
                            for _, desc in tabList:GetDescendants() do
                                if desc:IsA("TextLabel") and desc.Name == "PlayerLevel" then
                                    local text = desc.Text
                                    if text:find("%[%?%]") then
                                        local siblingName = desc.Parent:FindFirstChild("PlayerName")
                                        if siblingName then
                                            local currentNameText = siblingName.Text
                                            local cleanName = currentNameText:gsub("^@", ""):match("^%s*(.-)%s*$")
                                            
                                            local matchedPlayer = nil
                                            for _, plr in playersService:GetPlayers() do
                                                if plr == lplr then continue end
                                                if cleanName == plr.Name or cleanName == plr.DisplayName then
                                                    matchedPlayer = plr
                                                    break
                                                end
                                            end
                                            
                                            if matchedPlayer then
                                                local realLevel = levelMap[matchedPlayer.Name]
                                                if realLevel then
                                                    desc.Text = '<font color="rgb(255,255,255)">[' .. tostring(realLevel) .. ']</font>'
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        task.wait(0.3)
                    end
                end)

            else
                if updaterThread then
                    task.cancel(updaterThread)
                    updaterThread = nil
                end
                
                for _, plrs in playersService:GetPlayers() do
                    if plrs == lplr then continue end
                    
                    if old[plrs] then
                        plrs:SetAttribute("DisguiseDisplayName", old[plrs])
                        old[plrs] = nil
                    end
                    
                    if oldUsernames[plrs] then
                        plrs:SetAttribute("DisguiseUsername", oldUsernames[plrs])
                        oldUsernames[plrs] = nil
                    end
                    
                    if oldLevels[plrs] then
                        plrs:SetAttribute("PlayerLevel", oldLevels[plrs])
                        oldLevels[plrs] = nil
                    end
                end
                
                pcall(function()
                    bedwars.StreamerModeController:updateNametags(true)
                end)
                
                task.spawn(function()
                    local tabList = lplr.PlayerGui:FindFirstChild("TabListScreenGui")
                    if tabList then
                        tabList.Enabled = false
                        task.wait()
                        tabList.Enabled = true
                    end
                end)
            end
        end,
        Tooltip = 'sisable people streamer mode'
    })
end)

run(function()
	TrapDisabler = vape.Categories.Utility:CreateModule({
		Name = 'TrapDisabler',
		Tooltip = 'disables Snap Traps'
	})
end)

run(function()
	local RavenTP
	
	RavenTP = vape.Categories.Utility:CreateModule({
		Name = 'RavenTP',
		Function = function(callback)
			if callback then
				RavenTP:Toggle()
				local plr = entitylib.EntityMouse({
					Range = 1000,
					Players = true,
					Part = 'RootPart'
				})
	
				if getItem('raven') and plr then
					bedwars.Client:Get(remotes.SpawnRaven):CallServerAsync():andThen(function(projectile)
						if projectile then
							local ravenPart = projectile:FindFirstChild("Root") or projectile:FindFirstChildWhichIsA("BasePart")
							
							if ravenPart then
								local bodyforce = Instance.new('BodyForce')
								bodyforce.Force = Vector3.new(0, ravenPart.AssemblyMass * workspace.Gravity, 0)
								bodyforce.Parent = ravenPart
		
								if plr then
									task.spawn(function()
										for _ = 1, 20 do
											if plr.RootPart and ravenPart then
												ravenPart.CFrame = CFrame.lookAlong(plr.RootPart.Position, gameCamera.CFrame.LookVector)
											end
											task.wait(0.05)
										end
									end)
									task.wait(0.3)
									bedwars.RavenController:detonateRaven()
								end
							end
						end
					end)
				end
			end
		end,
		Tooltip = 'spawns and teleports a raven to a player\nnear your mouse'
	})
end)

run(function()
    local Kaliyah
    local AutoPunch
    local RangeSlider
    local PunchDelay
    local DelaySlider
    local NoSlow
    local punchActive = false
    local punchDebounce = {}

    local function getKaliyahTargets()
        local targets = {}
        if not entitylib.isAlive then return targets end
        
        local localPosition = entitylib.character.RootPart.Position
        local range = RangeSlider.Value
        
        for _, v in collectionService:GetTagged('KaliyahPunchInteraction') do
            if v:IsA("Model") and v.PrimaryPart then
                local distance = (localPosition - v.PrimaryPart.Position).Magnitude
                if distance <= range then
                    table.insert(targets, v)
                end
            end
        end
        
        return targets
    end

    local function punchTarget(target)
        local targetId = target:GetAttribute('Id') or tostring(target)
        
        if punchDebounce[targetId] then return false end
        punchDebounce[targetId] = true
        
        local character = lplr.Character
        if not character or not character.PrimaryPart then 
            punchDebounce[targetId] = nil
            return false 
        end
        
        pcall(function()
            bedwars.DragonSlayerController:deleteEmblem(target)
        end)
        
        local playerPos = character:GetPrimaryPartCFrame().Position
        local targetPos = target:GetPrimaryPartCFrame().Position * Vector3.new(1, 0, 1) + Vector3.new(0, playerPos.Y, 0)
        local lookAtCFrame = CFrame.new(playerPos, targetPos)
        
        character:PivotTo(lookAtCFrame)
        
        pcall(function()
            bedwars.DragonSlayerController:playPunchAnimation(lookAtCFrame - lookAtCFrame.Position)
        end)
        
        local success = pcall(function()
            bedwars.Client:Get(remotes.RequestDragonPunch):SendToServer({
                target = target
            })
        end)
        
        task.delay(3, function()
            punchDebounce[targetId] = nil
        end)
        
        return success
    end

    local function startAutoPunch()
        if punchActive then return end
        punchActive = true
        
        task.spawn(function()
            while Kaliyah.Enabled and AutoPunch.Enabled and punchActive do
                if not entitylib.isAlive then 
                    task.wait(0.5)
                    continue 
                end
                
                local targets = getKaliyahTargets()
                local punchedThisCycle = false
                
                for _, target in targets do
                    if not Kaliyah.Enabled or not AutoPunch.Enabled or not punchActive then 
                        break 
                    end
                    
                    if PunchDelay.Enabled and DelaySlider.Value > 0 then
                        task.wait(DelaySlider.Value)
                    end
                    
                    if punchTarget(target) then
                        punchedThisCycle = true
                        task.wait(0.2)
                    end
                end
                
                task.wait(punchedThisCycle and 0.5 or 0.3)
            end
            
            punchActive = false
        end)
    end

    local function stopAutoPunch()
        punchActive = false
        table.clear(punchDebounce)
    end

    local originalPlayPunchAnimation
    local function hookNoSlow()
        if not bedwars.DragonSlayerController then return end
        
        originalPlayPunchAnimation = bedwars.DragonSlayerController.playPunchAnimation
        
        bedwars.DragonSlayerController.playPunchAnimation = function(self, arg2)
            if NoSlow.Enabled then
                local any_import_result1_6_upvr = debug.getupvalue(originalPlayPunchAnimation, 1)
                local GameAnimationUtil_upvr = debug.getupvalue(originalPlayPunchAnimation, 2)
                local Players_upvr = debug.getupvalue(originalPlayPunchAnimation, 3)
                local AnimationType_upvr = debug.getupvalue(originalPlayPunchAnimation, 4)
                local KnitClient_upvr = debug.getupvalue(originalPlayPunchAnimation, 5)
                local RunService_upvr = debug.getupvalue(originalPlayPunchAnimation, 6)
                
                local any_new_result1_upvr_2 = any_import_result1_6_upvr.new()
                local any_playAnimation_result1_upvr_2 = GameAnimationUtil_upvr:playAnimation(Players_upvr.LocalPlayer, AnimationType_upvr.DRAGON_SLAYER_PUNCH)
                any_new_result1_upvr_2:GiveTask(function()
                    local var137 = any_playAnimation_result1_upvr_2
                    if var137 ~= nil then
                        var137:Stop()
                    end
                end)
                
                any_new_result1_upvr_2:GiveTask(RunService_upvr.Heartbeat:Connect(function()
                    local Character = Players_upvr.LocalPlayer.Character
                    local var141 = Character
                    if var141 ~= nil then
                        var141 = var141.PrimaryPart
                    end
                    if not var141 then
                        any_new_result1_upvr_2:DoCleaning()
                        return nil
                    end
                    Character:PivotTo(CFrame.new(Character:GetPrimaryPartCFrame().Position) * arg2)
                end))
                
                task.delay(0.46, function()
                    any_new_result1_upvr_2:DoCleaning()
                end)
                
                return any_new_result1_upvr_2
            else
                return originalPlayPunchAnimation(self, arg2)
            end
        end
    end

    local function unhookNoSlow()
        if originalPlayPunchAnimation and bedwars.DragonSlayerController then
            bedwars.DragonSlayerController.playPunchAnimation = originalPlayPunchAnimation
        end
    end

    Kaliyah = vape.Categories.Kits:CreateModule({
        Name = 'AutoKaliyah',
        Function = function(callback)
            if callback then
                if AutoPunch.Enabled then
                    startAutoPunch()
                end
                if NoSlow.Enabled then
                    hookNoSlow()
                end
            else
                stopAutoPunch()
                unhookNoSlow()
            end
        end,
        Tooltip = 'autokit with more features lmao'
    })
    
    AutoPunch = Kaliyah:CreateToggle({
        Name = 'Auto Punch',
        Default = false,
        Function = function(callback)
            if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = callback end
            if PunchDelay and PunchDelay.Object then PunchDelay.Object.Visible = callback end
            if DelaySlider and DelaySlider.Object then DelaySlider.Object.Visible = (callback and PunchDelay.Enabled) end
            if not callback then
                if DelaySlider and DelaySlider.Object then
                    DelaySlider.Object.Visible = false
                end
            else
                if PunchDelay and PunchDelay.Enabled then
                    if DelaySlider and DelaySlider.Object then
                        DelaySlider.Object.Visible = true
                    end
                end
            end
            
            if Kaliyah.Enabled then
                if callback then
                    startAutoPunch()
                else
                    stopAutoPunch()
                end
            end
        end
    })
    
    RangeSlider = Kaliyah:CreateSlider({
        Name = 'Range',
        Min = 1, 
        Max = 100,
        Default = 18,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    PunchDelay = Kaliyah:CreateToggle({
        Name = 'Punch Delay',
        Default = false,
        Function = function(callback)
            if DelaySlider and DelaySlider.Object then
                DelaySlider.Object.Visible = callback
            end
        end
    })
    
    DelaySlider = Kaliyah:CreateSlider({
        Name = 'Delay',
        Min = 1,
        Max = 3,
        Default = 1,
        Decimal = 10,
        Suffix = 's',
    })
    
    NoSlow = Kaliyah:CreateToggle({
        Name = 'No Slow',
        Default = false,
        Function = function(callback)
            if Kaliyah.Enabled then
                if callback then
                    hookNoSlow()
                else
                    unhookNoSlow()
                end
            end
        end
    })

    task.defer(function()
        if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = false end
        if PunchDelay and PunchDelay.Object then PunchDelay.Object.Visible = false end
        if DelaySlider and DelaySlider.Object then DelaySlider.Object.Visible = false end
    end)
end)

run(function()
    local Grove
    local NoSlow
    local NoSlowOnAbility
    local AutoWater
    local AutoWaterRange
    local AutoCollect
    local CollectRange
    local SpiritESP
    local ESPNotify
    local ESPBackground
    local ESPColor
    local DistanceCheck
    local DistanceLimit
    
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local Reference = {}
    local lastNotification = 0
    local spawnQueue = {}
    local notificationCooldown = 1
    local noSlowActive = false
    local autoWaterActive = false
    local autoCollectActive = false
    local originalDisableActionsOnCharge
    local originalCheckForPickup
    
    local function sendNotification(count)
        notif("Spirit ESP", string.format("%d spirit orbs spawned", count), 3)
    end

    local function processSpawnQueue()
        if #spawnQueue > 0 then
            local currentTime = tick()
            if currentTime - lastNotification >= notificationCooldown then
                sendNotification(#spawnQueue)
                lastNotification = currentTime
                spawnQueue = {}
            else
                task.delay(notificationCooldown - (currentTime - lastNotification), function()
                    if #spawnQueue > 0 then
                        sendNotification(#spawnQueue)
                        spawnQueue = {}
                    end
                end)
            end
        end
    end

    local function getProperImage()
        return bedwars.getIcon({itemType = 'spirit'}, true)
    end

    local function Added(v)
        if Reference[v] then return end
        local _bpUserId = v:GetAttribute('PlacedByUserId')
        if _bpUserId then
            local _bpOk, _bpOwner = pcall(function() return playersService:GetPlayerByUserId(_bpUserId) end)
        end
        
        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'spirit-energy'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = v
        
        local blur = addBlur(billboard)
        blur.Visible = ESPBackground.Enabled
        
        local image = Instance.new('ImageLabel')
        image.Size = UDim2.fromOffset(36, 36)
        image.Position = UDim2.fromScale(0.5, 0.5)
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.BackgroundColor3 = Color3.fromHSV(ESPColor.Hue, ESPColor.Sat, ESPColor.Value)
        image.BackgroundTransparency = 1 - (ESPBackground.Enabled and ESPColor.Opacity or 0)
        image.BorderSizePixel = 0
        image.Image = getProperImage()
        image.Parent = billboard
        
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 4)
        uicorner.Parent = image
        
        Reference[v] = billboard
        
        if ESPNotify.Enabled then
            table.insert(spawnQueue, {item = 'spirit', time = tick()})
            processSpawnQueue()
        end
    end

    local function Removed(v)
        if Reference[v] then
            Reference[v]:Destroy()
            Reference[v] = nil
        end
    end

    local function setupESP()
        for _, v in workspace:GetChildren() do
            if v.Name == "SpiritGardenerEnergy" and v:IsA("Model") and v.PrimaryPart then
                Added(v.PrimaryPart)
            end
        end

        Grove:Clean(workspace.ChildAdded:Connect(function(v)
            if v.Name == "SpiritGardenerEnergy" and v:IsA("Model") then
                task.wait(0.1)
                if v.PrimaryPart then
                    Added(v.PrimaryPart)
                end
            end
        end))

        Grove:Clean(workspace.ChildRemoved:Connect(function(v)
            if v.Name == "SpiritGardenerEnergy" and v.PrimaryPart then
                Removed(v.PrimaryPart)
            end
        end))

        Grove:Clean(runService.RenderStepped:Connect(function()
            if not SpiritESP.Enabled then return end
            
            for v, billboard in pairs(Reference) do
                if not v or not v.Parent then
                    Removed(v)
                    continue
                end

                local shouldShow = true

                if shouldShow and DistanceCheck.Enabled and entitylib.isAlive then
                    local distance = (entitylib.character.RootPart.Position - v.Position).Magnitude
                    if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
                        shouldShow = false
                    end
                end

                billboard.Enabled = shouldShow
            end
        end))
    end

    local function getNearbyFlowers()
        local flowers = {}
        if not entitylib.isAlive then return flowers end
        
        local localPosition = entitylib.character.RootPart.Position
        local range = AutoWaterRange.Value
        
        for _, v in collectionService:GetTagged('SpiritGardenerFlower') do
            if v:IsA("Model") and v.PrimaryPart then
                if v:GetAttribute("PlacedByUserId") == lplr.UserId then
                    local needsEnergy = not v:GetAttribute("HasFullyGrown")
                    if needsEnergy then
                        local distance = (localPosition - v.PrimaryPart.Position).Magnitude
                        if distance <= range then
                            table.insert(flowers, v)
                        end
                    end
                end
            end
        end
        
        return flowers
    end

    local function useWaterAbility()
        local success = pcall(function()
            game:GetService("ReplicatedStorage"):WaitForChild("events-@easy-games/game-core:shared/game-core-networking@getEvents.Events"):WaitForChild("useAbility"):FireServer("spirit_gardener_water")
        end)
        return success
    end

    local function startAutoWater()
        if autoWaterActive then return end
        autoWaterActive = true
        
        task.spawn(function()
            while Grove.Enabled and AutoWater.Enabled and autoWaterActive do
                if not entitylib.isAlive then 
                    task.wait(0.5)
                    continue 
                end
                
                local flowers = getNearbyFlowers()
                
                if #flowers > 0 then
                    if useWaterAbility() then
                        task.wait(0.6) 
                    else
                        task.wait(0.3)
                    end
                else
                    task.wait(0.5)
                end
            end
            
            autoWaterActive = false
        end)
    end

    local function stopAutoWater()
        autoWaterActive = false
    end

    local function hookAutoCollect()
        if not bedwars.SpiritGardenerSeedController then return end
        
        originalCheckForPickup = bedwars.SpiritGardenerSeedController.checkForPickup
        
        bedwars.SpiritGardenerSeedController.checkForPickup = function(self)
            if not AutoCollect.Enabled then
                return originalCheckForPickup(self)
            end
            
            local Players = playersService
            local CollectionService = collectionService
            local Workspace = game:GetService("Workspace")
            
            local Character = Players.LocalPlayer.Character
            if not Character or not Character.PrimaryPart then
                return nil
            end
            
            local localPosition = Character.PrimaryPart.Position
            local range = CollectRange.Value
            
            local validTypes = self:validCollectableEntityTypes()
            
            for _, collectableType in validTypes do
                local tagged = CollectionService:GetTagged(collectableType)
                
                for _, orb in tagged do
                    local spawnTime = orb:GetAttribute("SpawnTime")
                    if spawnTime and (Workspace:GetServerTimeNow() - spawnTime) >= 1 then
                        local orbPosition = orb:GetPivot().Position
                        local distance = (localPosition - orbPosition).Magnitude
                        
                        if distance <= range then
                            self:collectEntity(Players.LocalPlayer, orb, collectableType)
                        end
                    end
                end
            end
        end
    end

    local function unhookAutoCollect()
        if originalCheckForPickup and bedwars.SpiritGardenerSeedController then
            bedwars.SpiritGardenerSeedController.checkForPickup = originalCheckForPickup
        end
    end

    local function startAutoCollect()
        if autoCollectActive then return end
        autoCollectActive = true
        
        hookAutoCollect()
        
        if bedwars.SpiritGardenerSeedController then
            pcall(function()
                bedwars.SpiritGardenerSeedController:listenToPickup()
            end)
        end
    end

    local function stopAutoCollect()
        autoCollectActive = false
        unhookAutoCollect()
    end

    local function hookNoSlow()
        if not bedwars.SpiritGardenerController then return end
        
        originalDisableActionsOnCharge = bedwars.SpiritGardenerController.disableActionsOnCharge
        
        bedwars.SpiritGardenerController.disableActionsOnCharge = function(self, maid, character)
            if not NoSlow.Enabled then
                return originalDisableActionsOnCharge(self, maid, character)
            end
            
            if NoSlowOnAbility.Enabled then
                local isLocalPlayer = character == lplr.Character
                if not isLocalPlayer then
                    return originalDisableActionsOnCharge(self, maid, character)
                end
            end
            
            if character == lplr.Character then
                local KnitClient = bedwars.KnitClient
                
                KnitClient.Controllers.SwordController:toggleSwordSwing(true)
                KnitClient.Controllers.BlockPlacementController:disableBlockPlacer()
                
                local ClientSyncEvents = debug.getupvalue(originalDisableActionsOnCharge, 3)
                local projectileConnection = ClientSyncEvents.BeginProjectileTargeting:connect(function(event)
                    event:setCancelled(true)
                    return nil
                end)
                
                local jumpModifier = KnitClient.Controllers.JumpHeightController:getJumpModifier():addModifier({
                    jumpHeightMultiplier = 0;
                })
                
                maid:GiveTask(function()
                    KnitClient.Controllers.SwordController:toggleSwordSwing(false)
                    KnitClient.Controllers.BlockPlacementController:enableBlockPlacer()
                    projectileConnection:Destroy()
                    jumpModifier.Destroy()
                end)
            end
        end
    end

    local function unhookNoSlow()
        if originalDisableActionsOnCharge and bedwars.SpiritGardenerController then
            bedwars.SpiritGardenerController.disableActionsOnCharge = originalDisableActionsOnCharge
        end
    end

    Grove = vape.Categories.Kits:CreateModule({
        Name = 'AutoGrove',
        Function = function(callback)
            if callback then
                if SpiritESP.Enabled then 
                    setupESP() 
                end
                
                if NoSlow.Enabled then
                    hookNoSlow()
                end
                
                if AutoWater.Enabled then
                    startAutoWater()
                end
                
                if AutoCollect.Enabled then
                    startAutoCollect()
                end
            else
                stopAutoWater()
                stopAutoCollect()
                unhookNoSlow()
                Folder:ClearAllChildren()
                table.clear(Reference)
                table.clear(spawnQueue)
                lastNotification = 0
            end
        end,
        Tooltip = 'cool features for grove '
    })
    
    NoSlow = Grove:CreateToggle({
        Name = 'No Slow',
        Default = false,
        Tooltip = 'Remove movement lock when using water ability',
        Function = function(callback)
            if NoSlowOnAbility and NoSlowOnAbility.Object then 
                NoSlowOnAbility.Object.Visible = callback 
            end
            
            if Grove.Enabled then
                if callback then
                    hookNoSlow()
                else
                    unhookNoSlow()
                end
            end
        end
    })
    
    NoSlowOnAbility = Grove:CreateToggle({
        Name = 'Only On Ability Use',
        Default = false,
        Tooltip = 'noslow down only works when u manually use the ability'
    })
    
    AutoWater = Grove:CreateToggle({
        Name = 'Auto Water',
        Default = false,
        Tooltip = 'uses water ability on nearby flowers',
        Function = function(callback)
            if AutoWaterRange and AutoWaterRange.Object then 
                AutoWaterRange.Object.Visible = callback 
            end
            
            if Grove.Enabled then
                if callback then
                    startAutoWater()
                else
                    stopAutoWater()
                end
            end
        end
    })
    
    AutoWaterRange = Grove:CreateSlider({
        Name = 'Water Range',
        Min = 1, 
        Max = 30,
        Default = 20,
        Decimal = 1,
        Suffix = ' studs',
    })
    
    AutoCollect = Grove:CreateToggle({
        Name = 'Auto Collect',
        Default = false,
        Function = function(callback)
            if CollectRange and CollectRange.Object then 
                CollectRange.Object.Visible = callback 
            end
            
            if Grove.Enabled then
                if callback then
                    startAutoCollect()
                else
                    stopAutoCollect()
                end
            end
        end
    })
    
    CollectRange = Grove:CreateSlider({
        Name = 'Collect Range',
        Min = 5, 
        Max = 12,
        Default = 12,
        Decimal = 10,
        Suffix = ' studs',
    })
    
    SpiritESP = Grove:CreateToggle({
        Name = 'Spirit ESP',
        Default = false,
        Function = function(callback)
            if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = callback end
            if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = callback end
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            if DistanceCheck and DistanceCheck.Object then DistanceCheck.Object.Visible = callback end
            if DistanceLimit and DistanceLimit.Object then
                DistanceLimit.Object.Visible = (callback and DistanceCheck.Enabled)
            end

            if not callback then
                if ESPColor and ESPColor.Object then
                    ESPColor.Object.Visible = false
                end
                if DistanceLimit and DistanceLimit.Object then
                    DistanceLimit.Object.Visible = false
                end
            else
                if ESPBackground and ESPBackground.Enabled then
                    if ESPColor and ESPColor.Object then
                        ESPColor.Object.Visible = true
                    end
                end
                if DistanceCheck and DistanceCheck.Enabled then
                    if DistanceLimit and DistanceLimit.Object then
                        DistanceLimit.Object.Visible = true
                    end
                end
            end
            
            if Grove.Enabled then
                if callback then 
                    setupESP() 
                else
                    Folder:ClearAllChildren()
                    table.clear(Reference)
                end
            end
        end
    })
    
    ESPNotify = Grove:CreateToggle({
        Name = 'Notify',
        Default = false,
    })
    
    ESPBackground = Grove:CreateToggle({
        Name = 'Background',
        Default = true,
        Function = function(callback)
            if ESPColor and ESPColor.Object then ESPColor.Object.Visible = callback end
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    local blur = v:FindFirstChild("BlurEffect")
                    if blur then blur.Visible = callback end
                    v.ImageLabel.BackgroundTransparency = 1 - (callback and ESPColor.Opacity or 0)
                end
            end
        end
    })
    
    ESPColor = Grove:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0.5,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, v in Reference do
                if v and v:FindFirstChild("ImageLabel") then
                    v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    v.ImageLabel.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Darker = true
    })
    
    DistanceCheck = Grove:CreateToggle({
        Name = 'Distance Check',
        Default = false,
        Function = function(callback)
            if DistanceLimit and DistanceLimit.Object then
                DistanceLimit.Object.Visible = callback
            end
        end
    })
    
    DistanceLimit = Grove:CreateTwoSlider({
        Name = 'Spirit Distance',
        Min = 0,
        Max = 256,
        DefaultMin = 0,
        DefaultMax = 64,
        Darker = true,
    })

    task.defer(function()
        if ESPNotify and ESPNotify.Object then ESPNotify.Object.Visible = false end
        if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = false end
        if ESPColor and ESPColor.Object then ESPColor.Object.Visible = false end
        if DistanceCheck and DistanceCheck.Object then DistanceCheck.Object.Visible = false end
        if DistanceLimit and DistanceLimit.Object then DistanceLimit.Object.Visible = false end
        if AutoWaterRange and AutoWaterRange.Object then
            AutoWaterRange.Object.Visible = false
        end
        if CollectRange and CollectRange.Object then
            CollectRange.Object.Visible = false
        end
        if NoSlowOnAbility and NoSlowOnAbility.Object then
            NoSlowOnAbility.Object.Visible = false
        end
    end)
end)

run(function()
    local Lucia
    local AutoDepositToggle
    local RangeSlider
    local DelayToggle
    local DelaySlider
    local LuciaESPToggle
    local CandyESPToggle
    local IgnoreTeammatesESP
    local ESPBackground
    local ESPColor = {}
    local LuciaSpyToggle
    local IgnoreTeammatesSpy
    local DisplayNameToggle
    local Players = playersService
    local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui
	local Reference = {}
	local collectedPinatas = {}
	local trackedPinatas = {}

    local function kitCollection(id, func, range, specific)
        repeat
            if entitylib.isAlive then
                local objs = type(id) == 'table' and id or collection(id, Lucia)
                local localPosition = entitylib.character.RootPart.Position
                for _, v in objs do
                    if not Lucia.Enabled then break end
                    local part = not v:IsA('Model') and v or v.PrimaryPart
                    if part and (part.Position - localPosition).Magnitude <= range then
                        local success, err = pcall(func, v)
                        if not success then
                            warn("lucia deposit error:", err)
                        end
                        if DelayToggle.Enabled then
                            task.wait(DelaySlider.Value)
                        else
                            task.wait(0.05)
                        end
                    end
                end
            end
            task.wait(0.1)
        until not Lucia.Enabled
    end

    local function isTeammateESP(pinataPart)
        if not IgnoreTeammatesESP.Enabled then return false end

        local placerId = pinataPart:GetAttribute("PlacedByUserId") or pinataPart:GetAttribute("PlacerId")
        if not placerId then
            local parent = pinataPart.Parent
            if parent then
                placerId = parent:GetAttribute("PlacedByUserId") or parent:GetAttribute("PlacerId")
            end
        end

        if placerId then
            if placerId == lplr.UserId then
                return true
            end

            local placer = playersService:GetPlayerByUserId(placerId)
            if placer and placer.Team == lplr.Team then
                return true
            end
        end

        return false
    end

    local function isTeammateSpy(pinataPart)
        if not IgnoreTeammatesSpy.Enabled then return false end

        local placerId = pinataPart:GetAttribute("PlacedByUserId") or pinataPart:GetAttribute("PlacerId")
        if not placerId then
            local parent = pinataPart.Parent
            if parent then
                placerId = parent:GetAttribute("PlacedByUserId") or parent:GetAttribute("PlacerId")
            end
        end

        if placerId then
            if placerId == lplr.UserId then
                return true
            end

            local placer = playersService:GetPlayerByUserId(placerId)
            if placer and placer.Team == lplr.Team then
                return true
            end
        end

        return false
    end

    local function getCandyAmount(pinataPart)
        local coins = pinataPart:GetAttribute("Coin")
        return coins or 0
    end

    local function getProperIcon(iconType)
        local icon = bedwars.getIcon({itemType = iconType}, true)
        if not icon or icon == "" then
            return nil
        end
        return icon
    end

    local function Added(pinataPart)
        if isTeammateESP(pinataPart) then
            return
        end

        if Reference[pinataPart] then return end

        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'pinata'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.Size = UDim2.fromOffset(CandyESPToggle.Enabled and 80 or 36, 36)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = pinataPart

        local blur = addBlur(billboard)
        blur.Visible = ESPBackground.Enabled

        local frame = Instance.new('Frame')
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = Color3.fromHSV(ESPColor.Hue, ESPColor.Sat, ESPColor.Value)
        frame.BackgroundTransparency = 1 - (ESPBackground.Enabled and ESPColor.Opacity or 0)
        frame.BorderSizePixel = 0
        frame.Parent = billboard

        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 4)
        uicorner.Parent = frame

        local pinataIcon = getProperIcon('pinata')
        if pinataIcon then
            local image = Instance.new('ImageLabel')
            image.Name = 'PinataIcon'
            image.Size = UDim2.fromOffset(36, 36)
            image.Position = UDim2.new(0, 0, 0.5, 0)
            image.AnchorPoint = Vector2.new(0, 0.5)
            image.BackgroundTransparency = 1
            image.Image = pinataIcon
            image.Parent = frame
        end

        local candyAmount = nil
        local candyIcon = nil

        if CandyESPToggle.Enabled then
            candyAmount = Instance.new('TextLabel')
            candyAmount.Name = 'CandyAmount'
            candyAmount.Size = UDim2.fromOffset(25, 20)
            candyAmount.Position = UDim2.new(0, 40, 0.5, 0)
            candyAmount.AnchorPoint = Vector2.new(0, 0.5)
            candyAmount.BackgroundTransparency = 1
            candyAmount.Text = tostring(getCandyAmount(pinataPart))
            candyAmount.TextColor3 = Color3.fromRGB(255, 255, 255)
            candyAmount.TextSize = 16
            candyAmount.Font = Enum.Font.GothamBold
            candyAmount.TextStrokeTransparency = 0.5
            candyAmount.TextStrokeColor3 = Color3.new(0, 0, 0)
            candyAmount.Parent = frame

            local candyIconImage = getProperIcon('candy')
            if candyIconImage then
                candyIcon = Instance.new('ImageLabel')
                candyIcon.Name = 'CandyIcon'
                candyIcon.Size = UDim2.fromOffset(18, 18)
                candyIcon.Position = UDim2.new(0, 65, 0.5, 0)
                candyIcon.AnchorPoint = Vector2.new(0, 0.5)
                candyIcon.BackgroundTransparency = 1
                candyIcon.Image = candyIconImage
                candyIcon.Parent = frame
            end
        end

        Reference[pinataPart] = {
            billboard = billboard,
            frame = frame,
            candyAmount = candyAmount,
            candyIcon = candyIcon
        }
    end

    local function Removed(pinataPart)
        if Reference[pinataPart] then
            Reference[pinataPart].billboard:Destroy()
            Reference[pinataPart] = nil
        end
    end

    local function updateCandyDisplay(pinataPart)
        local ref = Reference[pinataPart]
        if not ref then return end

        if CandyESPToggle.Enabled then
            if not ref.candyAmount then
                ref.candyAmount = Instance.new('TextLabel')
                ref.candyAmount.Name = 'CandyAmount'
                ref.candyAmount.Size = UDim2.fromOffset(25, 20)
                ref.candyAmount.Position = UDim2.new(0, 40, 0.5, 0)
                ref.candyAmount.AnchorPoint = Vector2.new(0, 0.5)
                ref.candyAmount.BackgroundTransparency = 1
                ref.candyAmount.TextColor3 = Color3.fromRGB(255, 255, 255)
                ref.candyAmount.TextSize = 16
                ref.candyAmount.Font = Enum.Font.GothamBold
                ref.candyAmount.TextStrokeTransparency = 0.5
                ref.candyAmount.TextStrokeColor3 = Color3.new(0, 0, 0)
                ref.candyAmount.Parent = ref.frame

                local candyIconImage = getProperIcon('candy')
                if candyIconImage and not ref.candyIcon then
                    ref.candyIcon = Instance.new('ImageLabel')
                    ref.candyIcon.Name = 'CandyIcon'
                    ref.candyIcon.Size = UDim2.fromOffset(18, 18)
                    ref.candyIcon.Position = UDim2.new(0, 65, 0.5, 0)
                    ref.candyIcon.AnchorPoint = Vector2.new(0, 0.5)
                    ref.candyIcon.BackgroundTransparency = 1
                    ref.candyIcon.Image = candyIconImage
                    ref.candyIcon.Parent = ref.frame
                end

                ref.billboard.Size = UDim2.fromOffset(80, 36)
            end

            if ref.candyAmount then
                ref.candyAmount.Text = tostring(getCandyAmount(pinataPart))
            end
        else
            if ref.candyAmount then
                ref.candyAmount:Destroy()
                ref.candyAmount = nil
            end
            if ref.candyIcon then
                ref.candyIcon:Destroy()
                ref.candyIcon = nil
            end
            ref.billboard.Size = UDim2.fromOffset(36, 36)
        end
    end

    local function findExistingPinatas()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name == "pinata" then
                if not Reference[obj] and not isTeammateESP(obj) then
                    Added(obj)
                end
            end
        end
    end

    local function refreshESP()
        Folder:ClearAllChildren()
        table.clear(Reference)
        findExistingPinatas()
    end

    local function getLuciaPlayerName(player)
		return getPlayerName(player, DisplayNameToggle and DisplayNameToggle.Enabled)
	end

    local function getTeamName(player)
		return player.Team and player.Team.Name or "Unknown"
	end

    local function setupLuciaSpy()
        local util = require(game:GetService("ReplicatedStorage").TS.games.bedwars.kit.kits['piggy-bank']['piggy-bank-util']).PiggyBankUtil

        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name == "pinata" then
                if not isTeammateSpy(obj) then
                    local placerId = obj:GetAttribute("PlacedByUserId") or obj:GetAttribute("PlacerId")

                    if placerId then
                        local placer = playersService:GetPlayerByUserId(placerId)
                        local initialCandy = getCandyAmount(obj)

                        trackedPinatas[obj] = {
                            player = placer,
                            lastCandy = initialCandy,
                            exists = true,
                            placedTime = tick()
                        }
                    end
                end
            end
        end

        Lucia:Clean(workspace.DescendantAdded:Connect(function(obj)
            if not LuciaSpyToggle.Enabled then return end

            if obj:IsA("BasePart") and obj.Name == "pinata" then
                task.wait(0.2)

                if not isTeammateSpy(obj) then
                    local placerId = obj:GetAttribute("PlacedByUserId") or obj:GetAttribute("PlacerId")

                    if placerId then
                        local placer = playersService:GetPlayerByUserId(placerId)
                        local initialCandy = getCandyAmount(obj)

                        trackedPinatas[obj] = {
                            player = placer,
                            lastCandy = initialCandy,
                            exists = true,
                            placedTime = tick()
                        }
                    end
                end
            end
        end))

        Lucia:Clean(bedwars.Client:Get("PiggyBankPop"):Connect(function(self)
            if not LuciaSpyToggle.Enabled then return end
            local plr = self.awardedPlayer
            if not plr then return end
            if IgnoreTeammatesSpy.Enabled then
                if plr == lplr or (plr.Team and plr.Team == lplr.Team) then
                    return
                end
            end

            local rewards = util:getRewardsFromCoins(self.coins)
            local I, D, E = 0, 0, 0
            for _, reward in ipairs(rewards) do
                if reward.itemType == "iron" then
                    I = I + (reward.amount or 0)
                elseif reward.itemType == "diamond" then
                    D = D + (reward.amount or 0)
                elseif reward.itemType == "emerald" then
                    E = E + (reward.amount or 0)
                end
            end

            local playerName = getPlayerName(plr)
            local teamName = getTeamName(plr)
            local loot = string.format("%d irons, %d diamonds, %d emeralds", I, D, E)

            vape:CreateNotification(
                "Lucia Spy",
                string.format("%s (%s) opened their pinata and got %s", playerName, teamName, loot),
                8
            )

            for pinataPart, data in pairs(trackedPinatas) do
                if data.player and data.player.UserId == plr.UserId then
                    trackedPinatas[pinataPart] = nil
                end
            end
        end))

        local luciaSpyCounter = 0
        Lucia:Clean(RunService.Heartbeat:Connect(function()
            if not LuciaSpyToggle.Enabled then return end
            luciaSpyCounter = luciaSpyCounter + 1
            if luciaSpyCounter % 6 ~= 0 then return end
            local toRemove = {}
            for pinataPart, data in pairs(trackedPinatas) do
                if pinataPart and pinataPart.Parent then
                    local currentCandy = getCandyAmount(pinataPart)

                    if currentCandy ~= data.lastCandy then
                        local difference = currentCandy - data.lastCandy

                        if difference > 0 and data.player then
                                local playerName = getPlayerName(data.player)
                                local teamName = getTeamName(data.player)

                                vape:CreateNotification(
                                    "Lucia Spy",
                                    string.format("%s (%s) has just deposited %d candy and now has %d candy",
                                        playerName, teamName, difference, currentCandy),
                                    5
                                )
                            end
                            data.lastCandy = currentCandy
                        end
                else
                    if data.exists and data.player then
                        local timeSincePlaced = tick() - (data.placedTime or tick())

                        if timeSincePlaced > 2 then
                                local playerName = getPlayerName(data.player)
                                local teamName = getTeamName(data.player)

                                vape:CreateNotification(
                                    "Lucia Spy",
                                    string.format("%s (%s) has just broken their pinata with %d candy",
                                        playerName, teamName, data.lastCandy),
                                    5
                                )
                            end
                        end

                    table.insert(toRemove, pinataPart)
                end
            end

            for _, pinataPart in ipairs(toRemove) do
                trackedPinatas[pinataPart] = nil
            end
        end))
    end

    Lucia = vape.Categories.Kits:CreateModule({
        Name = 'AutoLucia',
        Function = function(callback)
            if callback then
                if LuciaESPToggle.Enabled then
                    findExistingPinatas()

                    Lucia:Clean(workspace.DescendantAdded:Connect(function(obj)
                        if Lucia.Enabled and obj:IsA("BasePart") and obj.Name == "pinata" then
                            task.wait(0.1)
                            if not isTeammateESP(obj) then
                                Added(obj)
                            end
                        end
                    end))

                    Lucia:Clean(workspace.DescendantRemoving:Connect(function(obj)
                        if obj:IsA("BasePart") and obj.Name == "pinata" and Reference[obj] then
                            Removed(obj)
                        end
                    end))

                    local luciaESPCounter = 0
                    Lucia:Clean(RunService.Heartbeat:Connect(function()
                        if not Lucia.Enabled or not LuciaESPToggle.Enabled then return end
                        luciaESPCounter = luciaESPCounter + 1
                        if luciaESPCounter % 6 ~= 0 then return end
                        for pinataPart, ref in pairs(Reference) do
                            if pinataPart and pinataPart.Parent then
                                updateCandyDisplay(pinataPart)
                            else
                                if ref.billboard then
                                    ref.billboard:Destroy()
                                end
                                Reference[pinataPart] = nil
                            end
                        end
                    end))
                end

                if AutoDepositToggle.Enabled then
                    task.spawn(function()
                        local r = RangeSlider.Value
                        kitCollection(lplr.Name .. ':pinata', function(v)
                            if getItem('candy') then
                                bedwars.Client:Get(remotes.DepositCoins):CallServer(v)
                            end
                        end, r, true)
                    end)
                end

                if LuciaSpyToggle.Enabled then
                    setupLuciaSpy()
                end
            else
                Folder:ClearAllChildren()
                table.clear(Reference)
                table.clear(collectedPinatas)
                table.clear(trackedPinatas)
            end
        end,
    })

    AutoDepositToggle = Lucia:CreateToggle({
        Name = 'Auto Deposit',
        Default = false,
        Function = function(callback)
            if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = callback end
            if DelayToggle and DelayToggle.Object then DelayToggle.Object.Visible = callback end
            if DelaySlider and DelaySlider.Object then DelaySlider.Object.Visible = (callback and DelayToggle.Enabled) end

            if not callback then
                if DelaySlider and DelaySlider.Object then
                    DelaySlider.Object.Visible = false
                end
            else
                if DelayToggle and DelayToggle.Enabled then
                    if DelaySlider and DelaySlider.Object then
                        DelaySlider.Object.Visible = true
                    end
                end
            end
        end
    })

    RangeSlider = Lucia:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 18,
        Default = 8,
        Suffix = ' studs',
        Visible = false
    })

    DelayToggle = Lucia:CreateToggle({
        Name = 'Delay',
        Default = false,
        Visible = false,
        Function = function(callback)
            if DelaySlider and DelaySlider.Object then
                DelaySlider.Object.Visible = callback
            end
        end
    })

    DelaySlider = Lucia:CreateSlider({
        Name = 'Delay Amount',
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
        Visible = false
    })

    LuciaESPToggle = Lucia:CreateToggle({
        Name = 'Pinata ESP',
        Function = function(callback)
            if CandyESPToggle and CandyESPToggle.Object then
                CandyESPToggle.Object.Visible = callback
            end
            if IgnoreTeammatesESP and IgnoreTeammatesESP.Object then
                IgnoreTeammatesESP.Object.Visible = callback
            end
            if ESPBackground and ESPBackground.Object then
                ESPBackground.Object.Visible = callback
            end
            if ESPColor and ESPColor.Object then
                ESPColor.Object.Visible = callback
            end

            if not callback then
                if ESPColor and ESPColor.Object then
                    ESPColor.Object.Visible = false
                end
            else
                if ESPBackground and ESPBackground.Enabled then
                    if ESPColor and ESPColor.Object then
                        ESPColor.Object.Visible = true
                    end
                end
            end

            if Lucia.Enabled then
                if callback then
                    findExistingPinatas()
                else
                    Folder:ClearAllChildren()
                    table.clear(Reference)
                end
            end
        end
    })

    CandyESPToggle = Lucia:CreateToggle({
        Name = 'Candy ESP',
        Visible = false,
        Tooltip = 'show amount of candy in pinatas',
        Function = function(callback)
            for pinataPart in pairs(Reference) do
                updateCandyDisplay(pinataPart)
            end
        end
    })

    IgnoreTeammatesESP = Lucia:CreateToggle({
        Name = 'Ignore Teammates',
        Visible = false,
        Function = function(callback)
            if Lucia.Enabled and LuciaESPToggle.Enabled then
                refreshESP()
            end
        end
    })

    ESPBackground = Lucia:CreateToggle({
        Name = 'Background',
        Visible = false,
        Function = function(callback)
            if ESPColor and ESPColor.Object then
                ESPColor.Object.Visible = callback
            end
            for _, ref in pairs(Reference) do
                if ref.frame then
                    ref.frame.BackgroundTransparency = 1 - (callback and ESPColor.Opacity or 0)
                    if ref.billboard.Blur then
                        ref.billboard.Blur.Visible = callback
                    end
                end
            end
        end
    })

    ESPColor = Lucia:CreateColorSlider({
        Name = 'Background Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Visible = false,
        Function = function(hue, sat, val, opacity)
            ESPColor.Hue = hue
            ESPColor.Sat = sat
            ESPColor.Value = val
            ESPColor.Opacity = opacity

            for _, ref in pairs(Reference) do
                if ref.frame then
                    ref.frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    ref.frame.BackgroundTransparency = 1 - opacity
                end
            end
        end,
        Darker = true
    })

    LuciaSpyToggle = Lucia:CreateToggle({
        Name = 'Lucia Spy',
        Default = false,
        Tooltip = 'notifies you varius info for lucia kits for players (amount of loot and etc)',
        Function = function(callback)
            if IgnoreTeammatesSpy and IgnoreTeammatesSpy.Object then
                IgnoreTeammatesSpy.Object.Visible = callback
            end
            if DisplayNameToggle and DisplayNameToggle.Object then
                DisplayNameToggle.Object.Visible = callback
            end

            if Lucia.Enabled and callback then
                setupLuciaSpy()
            else
                table.clear(trackedPinatas)
            end
        end
    })

    IgnoreTeammatesSpy = Lucia:CreateToggle({
        Name = 'Ignore Teammates',
        Default = true,
        Visible = false
    })

    DisplayNameToggle = Lucia:CreateToggle({
        Name = 'Display Name',
        Default = false,
        Visible = false,
    })

    task.defer(function()
        if RangeSlider and RangeSlider.Object then RangeSlider.Object.Visible = false end
        if DelayToggle and DelayToggle.Object then DelayToggle.Object.Visible = false end
        if DelaySlider and DelaySlider.Object then DelaySlider.Object.Visible = false end
        if CandyESPToggle and CandyESPToggle.Object then CandyESPToggle.Object.Visible = false end
        if IgnoreTeammatesESP and IgnoreTeammatesESP.Object then IgnoreTeammatesESP.Object.Visible = false end
        if ESPBackground and ESPBackground.Object then ESPBackground.Object.Visible = false end
        if ESPColor and ESPColor.Object then ESPColor.Object.Visible = false end
        if IgnoreTeammatesSpy and IgnoreTeammatesSpy.Object then IgnoreTeammatesSpy.Object.Visible = false end
        if DisplayNameToggle and DisplayNameToggle.Object then DisplayNameToggle.Object.Visible = false end
    end)
end)

run(function()
	local AutoHannah
	local Targets
	local Sort
	local Distance
	local Void
	local KATarget 

	AutoHannah = vape.Categories.Kits:CreateModule({
		Name = "AutoHannah",
		Tooltip = 'autokit with more features!!',
		Function = function(callback)
			if callback then
				task.spawn(function()
					local objs = collection('HannahExecuteInteraction', AutoHannah)

					while AutoHannah.Enabled do
						task.wait(0.1)
						if not entitylib.isAlive then continue end

						local localPosition = entitylib.character.RootPart.Position

						for _, v in objs do
							if not AutoHannah.Enabled then break end
							local part = not v:IsA('Model') and v or v.PrimaryPart
							if not part then continue end
							if (part.Position - localPosition).Magnitude > Distance.Value then continue end
							if Void.Enabled and isAboveVoid(part.Position) then continue end
							local success = bedwars.Client:Get(remotes.HannahPromptTrigger).instance:InvokeServer({
								user = lplr,
								victimEntity = v
							})
							if success then
								local icon = v:FindFirstChild('Hannah Execution Icon')
								if icon then icon:Destroy() end
							end
							task.wait(0.05)
						end
					end
				end)
			end
		end
	})

	Targets = AutoHannah:CreateTargets({
		Players = true,
		Walls = false,
		NPCs = false
	})
	local methods = {'Damage', 'Distance'}
	for i in sortmethods do
		if not table.find(methods, i) then
			table.insert(methods, i)
		end
	end
	Sort = AutoHannah:CreateDropdown({Name = 'Sort', List = methods})
	Distance = AutoHannah:CreateSlider({
		Name = "Distance",
		Min = 0,
		Max = 16,
		Default = 12,
		Suffix = 'studs'
	})
	Void = AutoHannah:CreateToggle({
		Name = 'Void',
		Tooltip = 'doesnt use ability if player is falling in the void',
		Default = true,
	})
	KATarget = AutoHannah:CreateToggle({
		Name = 'Use KA Target',
		Default = false,
	})
end)

run(function()
	local FishermanSpy
	local IgnoreTeammates

	local FishNames = {
		fish_iron = "Iron Fish",
		fish_diamond = "Diamond Fish",
		fish_emerald = "Emerald Fish",
		fish_special = "Special Fish",
		fish_gold = "Gold Fish",
	}	
	
	FishermanSpy = vape.Categories.Kits:CreateModule({
		Name = "FishermanSpy",
		Tooltip = 'notifys whenever a fisher has caught something',
		Function = function(callback)
			if callback then
				bedwars.Client:WaitFor(remotes.FishCaught):andThen(function(rbx)
					FishermanSpy:Clean(rbx:Connect(function(tbl)
						local char = tbl.catchingPlayer and tbl.catchingPlayer.Character
						if not char then return end
						local fish = tbl.dropData and tbl.dropData.fishModel
						local allDrops = tbl.dropData and tbl.dropData.drops
						local plrName = char.Name
						local str = plrName:sub(1, 1):upper()..plrName:sub(2)
						local strfish = FishNames[tostring(fish)] or 'Unknown Fish'
						local lootText = ''
						if allDrops then
							local totals = {}
							local order = {}
							for _, drop in ipairs(allDrops) do
								local item = tostring(drop.itemType) or 'unknown'
								local amount = tonumber(drop.amount) or 0
								if not totals[item] then
									totals[item] = 0
									table.insert(order, item)
								end
								totals[item] = totals[item] + amount
							end
							local parts = {}
							for _, item in ipairs(order) do
								table.insert(parts, item .. ' x' .. math.ceil(totals[item] * 1.4))
							end
							if #parts > 0 then
								lootText = ' | Loot: ' .. table.concat(parts, ', ')
							end
						end
						if IgnoreTeammates.Enabled then
							local currentplr = playersService:GetPlayerFromCharacter(char)
							if currentplr and currentplr.Team == lplr.Team then return end
						end
						local _fishChar = playersService:GetPlayerFromCharacter(char)
						notif("FishermanSpy", str .. " caught a " .. strfish .. lootText, 8)
					end))
				end)
			end
		end
	})
	IgnoreTeammates = FishermanSpy:CreateToggle({Name='Ignore Teammates',Default=true})
end)

run(function()
    local BeehiveSpy
    local BackgroundToggle
    local ColorSlider

    local cloneref = cloneref or function(obj) return obj end
    local collectionService = cloneref(game:GetService('CollectionService'))
    local runService        = cloneref(game:GetService('RunService'))
    local playersService    = cloneref(game:GetService('Players'))
    local lplr              = playersService.LocalPlayer

    local vape      = shared.vape
    local getcustomasset = vape.Libraries.getcustomasset

    local BeehiveFolder = Instance.new('Folder')
    BeehiveFolder.Parent = vape.gui
    local BeehiveReference = {}

    local function addBlur(parent)
        local blur = Instance.new('ImageLabel')
        blur.Name = 'Blur'
        blur.Size = UDim2.new(1, 89, 1, 52)
        blur.Position = UDim2.fromOffset(-48, -31)
        blur.BackgroundTransparency = 1
        blur.Image = getcustomasset('newvape/assets/new/blur.png')
        blur.ScaleType = Enum.ScaleType.Slice
        blur.SliceCenter = Rect.new(52, 31, 261, 502)
        blur.Parent = parent
        return blur
    end

    local function isMyBeehive(beehive)
        if not beehive then return false end
        local placedBy = beehive:GetAttribute("PlacedByUserId")
        return placedBy and placedBy == lplr.UserId
    end

    local function getBeehiveOwnerName(beehive)
        if not beehive then return "Unknown" end
        local placedBy = beehive:GetAttribute("PlacedByUserId")
        if not placedBy then return "Unknown" end
        local player = playersService:GetPlayerByUserId(placedBy)
        if player then return player.Name end
        return "Player"
    end

	local function getBeehiveOwner(beehive)
		if not beehive then return nil end
		local placedBy = beehive:GetAttribute("PlacedByUserId")
		if not placedBy then return nil end
        local player = playersService:GetPlayerByUserId(placedBy)
        if player then return player end
        return nil
	end

    local function AddedBeehive(beehive)
        if isMyBeehive(beehive) then return end
        if BeehiveReference[beehive] then return end

        local level     = beehive:GetAttribute("Level") or 0
        local ownerName = getBeehiveOwnerName(beehive)
		local owner = getBeehiveOwner(beehive)
		if not owner then return end

        local billboard = Instance.new('BillboardGui')
        billboard.Parent = BeehiveFolder
        billboard.Name   = 'beehive-spy'
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
        billboard.Size   = UDim2.fromOffset(120, 40)
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = beehive

        local blur = addBlur(billboard)
        blur.Visible = BackgroundToggle and BackgroundToggle.Enabled or true

        local hue, sat, val, opacity = 0, 0, 1, 0.5
        if ColorSlider then
            hue, sat, val, opacity = ColorSlider.Hue, ColorSlider.Sat, ColorSlider.Value, ColorSlider.Opacity
        end

        local frame = Instance.new('Frame')
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
        frame.BackgroundTransparency = 1 - ((BackgroundToggle and BackgroundToggle.Enabled or true) and opacity or 0)
        frame.BorderSizePixel = 0
        frame.Parent = billboard
        local uicorner = Instance.new('UICorner')
        uicorner.CornerRadius = UDim.new(0, 6)
        uicorner.Parent = frame
        local nameLabel = Instance.new('TextLabel')
        nameLabel.Name = 'OwnerName'
        nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
        nameLabel.Position = UDim2.new(0, 0, 0, -20)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = ownerName
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize = 12
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextStrokeTransparency = 0.5
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.Parent = billboard
        local homeLabel = Instance.new('TextLabel')
        homeLabel.Size = UDim2.fromOffset(20, 20)
        homeLabel.Position = UDim2.new(0, 5, 0.5, 0)
        homeLabel.AnchorPoint = Vector2.new(0, 0.5)
        homeLabel.BackgroundTransparency = 1
        homeLabel.Text = "🏘️"
        homeLabel.TextSize = 16
        homeLabel.Parent = frame
        local levelLabel = Instance.new('TextLabel')
        levelLabel.Name = 'Level'
        levelLabel.Size = UDim2.new(0, 25, 1, 0)
        levelLabel.Position = UDim2.new(1, -30, 0, 0)
        levelLabel.BackgroundTransparency = 1
        levelLabel.Text = tostring(level)
        levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        levelLabel.TextSize = 16
        levelLabel.Font = Enum.Font.GothamBold
        levelLabel.TextStrokeTransparency = 0.5
        levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        levelLabel.Parent = frame

        BeehiveReference[beehive] = {
            billboard  = billboard,
            levelLabel = levelLabel,
            frame      = frame,
        }

        BeehiveSpy:Clean(beehive:GetAttributeChangedSignal("Level"):Connect(function()
            local ref = BeehiveReference[beehive]
            if ref and ref.levelLabel then
                ref.levelLabel.Text = tostring(beehive:GetAttribute("Level") or 0)
            end
        end))
    end

    local function RemovedBeehive(beehive)
        if BeehiveReference[beehive] then
            BeehiveReference[beehive].billboard:Destroy()
            BeehiveReference[beehive] = nil
        end
    end

    local function setupBeehiveSpy()
        for _, beehive in collectionService:GetTagged('beehive') do
            AddedBeehive(beehive)
        end

        BeehiveSpy:Clean(collectionService:GetInstanceAddedSignal('beehive'):Connect(function(beehive)
            task.wait(0.1)
            AddedBeehive(beehive)
        end))

        BeehiveSpy:Clean(collectionService:GetInstanceRemovedSignal('beehive'):Connect(function(beehive)
            RemovedBeehive(beehive)
        end))
    end

    BeehiveSpy = vape.Categories.Kits:CreateModule({
        Name    = "BeehiveSpy",
        Function = function(callback)
            if callback then
                setupBeehiveSpy()
            else
                BeehiveFolder:ClearAllChildren()
                table.clear(BeehiveReference)
            end
        end
    })

    BackgroundToggle = BeehiveSpy:CreateToggle({
        Name    = "Background",
        Default = true,
        Function = function(callback)
            if ColorSlider and ColorSlider.Object then ColorSlider.Object.Visible = callback end
            for _, ref in BeehiveReference do
                if ref and ref.billboard then
                    local frame = ref.billboard:FindFirstChild("Frame")
                    local blur  = ref.billboard:FindFirstChild("Blur")
                    if frame then
                        local opacity = ColorSlider and ColorSlider.Opacity or 0.5
                        frame.BackgroundTransparency = 1 - (callback and opacity or 0)
                    end
                    if blur then blur.Visible = callback end
                end
            end
        end
    })

    ColorSlider = BeehiveSpy:CreateColorSlider({
        Name         = "Color",
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            for _, ref in BeehiveReference do
                if ref and ref.frame then
                    ref.frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    ref.frame.BackgroundTransparency = 1 - (BackgroundToggle.Enabled and opacity or 0)
                end
            end
        end,
        Darker = true
    })

    task.defer(function()
        if ColorSlider and ColorSlider.Object then
            ColorSlider.Object.Visible = BackgroundToggle and BackgroundToggle.Enabled or true
        end
    end)
end)

run(function()
    local LuciaSpy
    local IgnoreTeammatesSpy
    local DisplayNameToggle

    local runService = game:GetService('RunService')
    local playersService = game:GetService('Players')
    local lplr = playersService.LocalPlayer

    local vape = shared.vape
    local bedwars = shared.bedwars or getgenv().bedwars

    local trackedPinatas = {}

    local function getPlayerName(player)
        if DisplayNameToggle and DisplayNameToggle.Enabled then
            return player.DisplayName ~= "" and player.DisplayName or player.Name
        end
        return player.Name
    end

    local function getTeamName(player)
        if player.Team then return player.Team.Name end
        return "Unknown"
    end

    local function getCandyAmount(pinataPart)
        return pinataPart:GetAttribute("Coin") or 0
    end

    local function isTeammateSpy(pinataPart)
        if not IgnoreTeammatesSpy or not IgnoreTeammatesSpy.Enabled then return false end
        local placerId = pinataPart:GetAttribute("PlacedByUserId") or pinataPart:GetAttribute("PlacerId")
        if not placerId then
            local parent = pinataPart.Parent
            if parent then
                placerId = parent:GetAttribute("PlacedByUserId") or parent:GetAttribute("PlacerId")
            end
        end
        if placerId then
            if placerId == lplr.UserId then return true end
            local placer = playersService:GetPlayerByUserId(placerId)
            if placer and placer.Team == lplr.Team then return true end
        end
        return false
    end

    local function setupLuciaSpy()
        local util = require(game:GetService("ReplicatedStorage").TS.games.bedwars.kit.kits['piggy-bank']['piggy-bank-util']).PiggyBankUtil
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Name == "pinata" then
                if not isTeammateSpy(obj) then
                    local placerId = obj:GetAttribute("PlacedByUserId") or obj:GetAttribute("PlacerId")
                    if placerId then
                        local placer = playersService:GetPlayerByUserId(placerId)
                        local initialCandy = getCandyAmount(obj)
                        trackedPinatas[obj] = {
                            player = placer,
                            lastCandy = initialCandy,
                            exists = true,
                            placedTime = tick()
                        }
                    end
                end
            end
        end

        LuciaSpy:Clean(workspace.DescendantAdded:Connect(function(obj)
            if not LuciaSpy.Enabled then return end
            if obj:IsA("BasePart") and obj.Name == "pinata" then
                task.wait(0.2)
                if not isTeammateSpy(obj) then
                    local placerId = obj:GetAttribute("PlacedByUserId") or obj:GetAttribute("PlacerId")
                    if placerId then
                        local placer = playersService:GetPlayerByUserId(placerId)
                        trackedPinatas[obj] = {
                            player = placer,
                            lastCandy = getCandyAmount(obj),
                            exists = true,
                            placedTime = tick()
                        }
                    end
                end
            end
        end))

        LuciaSpy:Clean(bedwars.Client:Get("PiggyBankPop"):Connect(function(self)
            if not LuciaSpy.Enabled then return end
            local plr = self.awardedPlayer
            if not plr then return end
            if IgnoreTeammatesSpy and IgnoreTeammatesSpy.Enabled then
                if plr == lplr or (plr.Team and plr.Team == lplr.Team) then return end
            end

            local rewards = util:getRewardsFromCoins(self.coins)
            local I, D, E = 0, 0, 0
            for _, reward in ipairs(rewards) do
                if reward.itemType == "iron" then
                    I = I + (reward.amount or 0)
                elseif reward.itemType == "diamond" then
                    D = D + (reward.amount or 0)
                elseif reward.itemType == "emerald" then
                    E = E + (reward.amount or 0)
                end
            end

            local playerName = getPlayerName(plr)
            local teamName = getTeamName(plr)
            local loot = string.format("%d irons, %d diamonds, %d emeralds", I, D, E)

            vape:CreateNotification(
                "Lucia Spy",
                string.format("%s (%s) opened their pinata and got %s", playerName, teamName, loot),
                8
            )

            for pinataPart, data in pairs(trackedPinatas) do
                if data.player and data.player.UserId == plr.UserId then
                    trackedPinatas[pinataPart] = nil
                end
            end
        end))

        local counter = 0
        LuciaSpy:Clean(runService.Heartbeat:Connect(function()
            if not LuciaSpy.Enabled then return end
            counter = counter + 1
            if counter % 6 ~= 0 then return end

            local toRemove = {}
            for pinataPart, data in pairs(trackedPinatas) do
                if pinataPart and pinataPart.Parent then
                    local currentCandy = getCandyAmount(pinataPart)
                    if currentCandy ~= data.lastCandy then
                        local difference = currentCandy - data.lastCandy
                        if difference > 0 and data.player then
                            local playerName = getPlayerName(data.player)
                            local teamName = getTeamName(data.player)
                            vape:CreateNotification(
                                "Lucia Spy",
                                string.format("%s (%s) deposited %d candy (now %d)", playerName, teamName, difference, currentCandy),
                                5
                            )
                        end
                        data.lastCandy = currentCandy
                    end
                else
                    if data.exists and data.player then
                        local timeSincePlaced = tick() - (data.placedTime or tick())
                        if timeSincePlaced > 2 then
                            local playerName = getPlayerName(data.player)
                            local teamName   = getTeamName(data.player)
                            vape:CreateNotification(
                                "Lucia Spy",
                                string.format("%s (%s) broke their pinata (had %d candy)", playerName, teamName, data.lastCandy),
                                5
                            )
                        end
                    end
                    table.insert(toRemove, pinataPart)
                end
            end

            for _, pinataPart in ipairs(toRemove) do
                trackedPinatas[pinataPart] = nil
            end
        end))
    end

    LuciaSpy = vape.Categories.Kits:CreateModule({
        Name = "LuciaSpy",
        Tooltip = 'notifies you varius info for lucia kits for players (amount of loot and etc)',
        Function = function(callback)
            if callback then
                setupLuciaSpy()
            else
                table.clear(trackedPinatas)
            end
        end
    })

    IgnoreTeammatesSpy = LuciaSpy:CreateToggle({
        Name = "Ignore Teammates",
        Default = true,
    })

    DisplayNameToggle = LuciaSpy:CreateToggle({
        Name = "Display Name",
        Default = false,
    })
end)

run(function()
	local AutoHonor
	local Delay
	local honoredusers = {}
	local maxhonors = 2
	
	local function getTeammates()
		local teammates = {}
		local nonteammates = {}
		local myTeam = lplr.Team
		
		for i, plr in playersService:GetPlayers() do
			if plr ~= lplr then
				if plr.Team == myTeam then
					table.insert(teammates, plr)
				else
					table.insert(nonteammates, plr)
				end
			end
		end
		return teammates, nonteammates
	end
	
	local function honorPlayers()
		if #honoredusers >= maxhonors then return end
		
		local teammates, nonteammates = getTeammates()
		
		if #teammates > 0 and #honoredusers < maxhonors then
			local randomTeammate = teammates[math.random(1, #teammates)]
			if not honoredusers[randomTeammate.UserId] then
				task.wait(Delay.Value)
				bedwars.HonorController:honorPlayer(randomTeammate.UserId)
				honoredusers[randomTeammate.UserId] = true
			end
		end
		
		if #nonteammates > 0 and #honoredusers < maxhonors then
			local randomEnemy = nonteammates[math.random(1, #nonteammates)]
			if not honoredusers[randomEnemy.UserId] then
				task.wait(Delay.Value)
				bedwars.HonorController:honorPlayer(randomEnemy.UserId)
				honoredusers[randomEnemy.UserId] = true
			end
		end
	end
	
	AutoHonor = vape.Categories.Minigames:CreateModule({
		Name = "AutoHonor",
		Function = function(callback)
			if callback then
				AutoHonor:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
					if deathTable.finalKill and deathTable.entityInstance == lplr.Character and isEveryoneDead() and store.matchState ~= 2 then
						honorPlayers()
					end
				end))
				AutoHonor:Clean(vapeEvents.MatchEndEvent.Event:Connect(function(...)
					honorPlayers()
				end))
			else
				table.clear(honoredusers)
			end
		end
	})
	Delay = AutoHonor:CreateSlider({
		Name = 'Delay',
		Min = 0,
		Max = 1,
		Decimal = 100,
		Default = 0.05
	})
end)

run(function()
	local PotatoMode
	local originalProperties = {}
	local blockMonitorConnections = {}
	local processedBlocks = {}
	
	local blockColors = {
		["clay_white"] = Color3.fromRGB(255, 255, 255),
		["wool_white"] = Color3.fromRGB(255, 255, 255),
		["wool_red"] = Color3.fromRGB(255, 50, 50),
		["wool_green"] = Color3.fromRGB(50, 255, 50),
		["grass"] = Color3.fromRGB(50, 255, 50),
		["moss_block"] = Color3.fromRGB(50, 255, 50),
		["wool_blue"] = Color3.fromRGB(50, 100, 255),
		["wool_yellow"] = Color3.fromRGB(255, 255, 50),
		["wool_orange"] = Color3.fromRGB(255, 150, 50),
		["clay_orange"] = Color3.fromRGB(255, 150, 50),
		["wool_purple"] = Color3.fromRGB(180, 50, 255),
		["clay_light_brown"] = Color3.fromRGB(200, 170, 120),
		["wool_pink"] = Color3.fromRGB(255, 100, 200),
		["wool_black"] = Color3.fromRGB(50, 50, 50),
		["wool_cyan"] = Color3.fromRGB(50, 255, 255),
		["wool_magenta"] = Color3.fromRGB(255, 50, 150),
		["wool_lime"] = Color3.fromRGB(150, 255, 50),
		["wool_brown"] = Color3.fromRGB(150, 75, 0),
		["wood_plank_spruce"] = Color3.fromRGB(222, 184, 135),
		["wool_light_blue"] = Color3.fromRGB(100, 200, 255),
		["wool_gray"] = Color3.fromRGB(150, 150, 150),
		["clay"] = Color3.fromRGB(220, 180, 140),
		["wood"] = Color3.fromRGB(180, 140, 100),
		["stone"] = Color3.fromRGB(150, 150, 150),
		["andesite"] = Color3.fromRGB(150, 150, 150),
		["cobblestone"] = Color3.fromRGB(150, 150, 150),
		["obsidian"] = Color3.fromRGB(50, 30, 80),
		["bedrock"] = Color3.fromRGB(80, 80, 80),
		["tnt"] = Color3.fromRGB(255, 50, 50),
		["sandstone"] = Color3.fromRGB(220, 200, 150),
		["sand"] = Color3.fromRGB(220, 200, 150),
		["wool"] = Color3.fromRGB(200, 200, 200),
		["bed"] = Color3.fromRGB(200, 50, 50),
		["concrete"] = Color3.fromRGB(180, 180, 180),
	}
	
	local cachedColors = {}
	
	local function getBlockColor(blockName)
		if cachedColors[blockName] then
			return cachedColors[blockName]
		end
		
		if blockColors[blockName] then
			cachedColors[blockName] = blockColors[blockName]
			return blockColors[blockName]
		end
		
		local lowerName = blockName:lower()
		
		if blockColors[lowerName] then
			cachedColors[blockName] = blockColors[lowerName]
			return blockColors[lowerName]
		end
		
		if lowerName:find("wool", 1, true) then 
			for key, color in pairs(blockColors) do
				if key:find("wool", 1, true) and lowerName:find(key, 1, true) then
					cachedColors[blockName] = color
					return color
				end
			end
			cachedColors[blockName] = blockColors["wool"]
			return blockColors["wool"]
		end
		
		for name, color in pairs(blockColors) do
			if lowerName:find(name, 1, true) then
				cachedColors[blockName] = color
				return color
			end
		end
		
		local defaultColor = Color3.fromRGB(150, 150, 150)
		cachedColors[blockName] = defaultColor
		return defaultColor
	end
	
	local function cleanupDeadReferences()
		for block, _ in pairs(originalProperties) do
			if not block or not block.Parent then
				originalProperties[block] = nil
				processedBlocks[block] = nil
			end
		end
	end
	
	local function simplifyBlock(block)
		if not block or not block.Parent or processedBlocks[block] then return end
		
		if not originalProperties[block] then
			originalProperties[block] = {
				Material = block.Material,
				Color = block.Color,
				TextureID = block:IsA("MeshPart") and block.TextureID or nil,
				Textures = {}
			}
			
			for _, child in block:GetChildren() do
				if child:IsA("Texture") or child:IsA("Decal") then
					table.insert(originalProperties[block].Textures, {
						Class = child.ClassName,
						Texture = child.Texture,
						StudsPerTileU = child.StudsPerTileU,
						StudsPerTileV = child.StudsPerTileV,
						Face = child.Face,
						Transparency = child.Transparency,
						Color3 = child:IsA("Decal") and child.Color3 or nil
					})
				end
			end
		end
		
		block.Material = Enum.Material.SmoothPlastic
		block.Color = getBlockColor(block.Name)
		
		for _, child in block:GetChildren() do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:Destroy()
			end
		end
		
		if block:IsA("MeshPart") and block.TextureID ~= "" then
			block.TextureID = ""
		end
		
		processedBlocks[block] = true
	end
	
	local function restoreBlock(block)
		if not block or not block.Parent then 
			originalProperties[block] = nil
			processedBlocks[block] = nil
			return 
		end
		
		local props = originalProperties[block]
		if not props then return end
		
		block.Material = props.Material or Enum.Material.Plastic
		block.Color = props.Color or Color3.fromRGB(255, 255, 255)
		
		if props.TextureID and block:IsA("MeshPart") then
			block.TextureID = props.TextureID
		end
		
		for _, textureProps in props.Textures do
			local newTexture
			if textureProps.Class == "Texture" then
				newTexture = Instance.new("Texture")
				newTexture.StudsPerTileU = textureProps.StudsPerTileU or 1
				newTexture.StudsPerTileV = textureProps.StudsPerTileV or 1
			else
				newTexture = Instance.new("Decal")
				newTexture.Color3 = textureProps.Color3 or Color3.fromRGB(255, 255, 255)
			end
			
			newTexture.Texture = textureProps.Texture or ""
			newTexture.Face = textureProps.Face or Enum.NormalId.Front
			newTexture.Transparency = textureProps.Transparency or 0
			newTexture.Parent = block
		end
		
		originalProperties[block] = nil
		processedBlocks[block] = nil
	end
	
	local function isTargetBlock(obj)
		if not obj:IsA("BasePart") then return false end
		
		local name = obj.Name
		
		if blockColors[name] then return true end
		
		local lowerName = name:lower()
		return lowerName:find("wool", 1, true) or 
		       lowerName:find("clay", 1, true) or
		       lowerName:find("wood", 1, true) or 
		       lowerName:find("stone", 1, true) or 
		       lowerName:find("glass", 1, true) or
		       lowerName:find("plank", 1, true) or 
		       lowerName:find("bed", 1, true) or 
		       lowerName:find("obsidian", 1, true) or
		       lowerName:find("sand", 1, true) or 
		       lowerName:find("end", 1, true) or 
		       lowerName:find("tnt", 1, true) or
		       lowerName:find("barrier", 1, true) or 
		       lowerName:find("magic", 1, true) or 
		       lowerName:find("concrete", 1, true) or
		       lowerName:find("_block", 1, true) or 
		       obj:IsA("Seat")
	end
	
	local function processExistingBlocks(simplify)
		local descendants = workspace:GetDescendants()
		
		task.spawn(function()
			for i, obj in descendants do
				if isTargetBlock(obj) then
					if simplify then
						simplifyBlock(obj)
					else
						restoreBlock(obj)
					end
				end
			end
			
			if not simplify then
				cleanupDeadReferences()
			end
		end)
	end
	
	local function setupBlockMonitor(simplify)
		for _, conn in blockMonitorConnections do
			conn:Disconnect()
		end
		table.clear(blockMonitorConnections)
		
		if not simplify then return end
		
		local mainConn = workspace.DescendantAdded:Connect(function(descendant)
			if isTargetBlock(descendant) then
				task.defer(function()
					if descendant and descendant.Parent then
						simplifyBlock(descendant)
					end
				end)
			end
		end)
		
		table.insert(blockMonitorConnections, mainConn)
		
		local lastCleanup = 0
		local cleanupConn = runService.Heartbeat:Connect(function()
			local now = tick()
			if now - lastCleanup >= 5 then
				lastCleanup = now
				cleanupDeadReferences()
			end
		end)
		
		table.insert(blockMonitorConnections, cleanupConn)
	end
	
	PotatoMode = vape.Categories.World:CreateModule({
		Name = 'PotatoMode',
		Function = function(callback)
			if callback then
				processExistingBlocks(true)
				setupBlockMonitor(true)
			else
				processExistingBlocks(false)
				for _, conn in blockMonitorConnections do
					conn:Disconnect()
				end
				table.clear(blockMonitorConnections)
				table.clear(cachedColors)
				cleanupDeadReferences()
			end
		end,
	})
end)

run(function()
	local FishermanESP
	local FishNames = {
		fish_iron = "Iron Fish",
		fish_diamond = "Diamond Fish",
		fish_emerald = "Emerald Fish",
		fish_special = "Special Fish",
		fish_gold = "Gold Fish",
	}
	
	FishermanESP = vape.Categories.Kits:CreateModule({
		Name = "FishermanESP",
		Tooltip = 'shows what fish you are catching before the minigame starts',
		Function = function(callback)		
			if callback then		
				local exp = bedwars.Client:WaitFor(remotes.FishFound):expect()
				FishermanESP:Clean(exp:Connect(function(p24)
					local scl = p24.dropData
					if scl and scl.fishModel then
						local ftype = tostring(scl.fishModel) or 'fish_iron'
						local allDrops = scl.drops
						local lootParts = {}
						if allDrops then
							local totals = {}
							local order = {}
							for _, drop in ipairs(allDrops) do
								local item = tostring(drop.itemType) or 'unknown'
								local amount = tonumber(drop.amount) or 0
								if not totals[item] then
									totals[item] = 0
									table.insert(order, item)
								end
								totals[item] = totals[item] + amount
							end
							for _, item in ipairs(order) do
								table.insert(lootParts, item .. ' x' .. math.ceil(totals[item] * 1.4))
							end
						end
						local lootText = #lootParts > 0 and table.concat(lootParts, ', ') or 'unknown'
						notif('FishermanESP', 'Your fish will be ' .. FishNames[ftype] .. ' | Loot: ' .. lootText, 12)
					end
				end))
			else
			end
		end
	})
end)

run(function()
	local TrapESP
	local Background = {}
	local Color = {}
	local Reference = {}
	local Folder = Instance.new('Folder')
	Folder.Parent = vape.gui

	local function Added(v, icon)
		local billboard = Instance.new('BillboardGui')
		billboard.Parent = Folder
		billboard.Name = icon
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Size = UDim2.fromOffset(36, 36)
		billboard.AlwaysOnTop = true
		billboard.ClipsDescendants = false
		billboard.Adornee = v
		local blur = addBlur(billboard)
		blur.Visible = Background.Enabled
		local image = Instance.new('ImageLabel')
		image.Size = UDim2.fromOffset(36, 36)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
		image.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
		image.BorderSizePixel = 0
		local result = bedwars.getIcon({itemType = icon}, true)
		image.Image = result		
		image.Image = result
		image.Parent = billboard
		local uicorner = Instance.new('UICorner')
		uicorner.CornerRadius = UDim.new(0, 4)
		uicorner.Parent = image
		Reference[v] = billboard
	end
	


	TrapESP = vape.Categories.Render:CreateModule({
		Name = 'TrapESP',
		Function = function(callback)
			if callback then
				TrapESP:Clean(collectionService:GetInstanceAddedSignal('snap_trap'):Connect(function(v)
					if tostring(v:GetAttribute("SnapTrapTeamId")) == lplr.Team.Name then
						return
					end
					Added(v, 'snap_trap')
				end))
				TrapESP:Clean(collectionService:GetInstanceRemovedSignal('snap_trap'):Connect(function(v)
					if tostring(v:GetAttribute("SnapTrapTeamId")) == lplr.Team.Name then
						return
					end
					if Reference[v] then
						Reference[v]:Destroy()
						Reference[v] = nil
					end
				end))
				for _, v in collectionService:GetTagged('snap_trap') do
					if tostring(v:GetAttribute("SnapTrapTeamId")) == lplr.Team.Name then
						return
					end
					Added(v, 'snap_trap')
				end
			else
				Folder:ClearAllChildren()
				table.clear(Reference)
			end
		end,
		Tooltip = 'allows you to see invisible traps'
	})
	Background = TrapESP:CreateToggle({
		Name = 'Background',
		Function = function(callback)
			if Color.Object then Color.Object.Visible = callback end
			for _, v in Reference do
				v.ImageLabel.BackgroundTransparency = 1 - (callback and Color.Opacity or 0)
				v.Blur.Visible = callback
			end
		end,
		Default = true,
				Visible = true
	})
	Color = TrapESP:CreateColorSlider({
		Name = 'Background Color',
		DefaultValue = 0,
		DefaultOpacity = 0.5,
		Function = function(hue, sat, val, opacity)
			for _, v in Reference do
				v.ImageLabel.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
				v.ImageLabel.BackgroundTransparency = 1 - opacity
			end
		end,
		Darker = true
	})
end)

run(function()
	local MouseTP
	local Mode
	local Movement

	local projectileRemote = {InvokeServer = function() end}
	task.spawn(function()
		projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
	end)


	local function getNearestPlayer(selfpos)
		if not selfpos or not entitylib.isAlive then return nil end
		local nearestPlayer, nearestDistance = nil, math.huge

		for _, plr in ipairs(playersService:GetPlayers()) do
			if plr ~= lplr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
				local dist = (plr.Character.HumanoidRootPart.Position - selfpos).Magnitude
				if dist < nearestDistance then
					nearestDistance = dist
					nearestPlayer = plr
				end
			end
		end
		return nearestPlayer
	end

	local function aimCannon(cannon, targetPos)
		if not cannon or not targetPos then return end
		
		local cannonPos = cannon.Position
		local dist = (targetPos - cannonPos).Magnitude
		
		local heightOffset = (dist * 0.095) + (dist * dist * 0.0011)
		local aimPoint = targetPos + Vector3.new(0, heightOffset, 0)
		
		local Delta = CFrame.lookAt(cannonPos, aimPoint)
		local playerDist = (targetPos - lplr.Character.HumanoidRootPart.Position).Magnitude
		
		local lookVector = Delta.LookVector * (1 + playerDist * 0.007) / math.pi
		
		bedwars.Client:Get('AimCannon'):SendToServer({
			cannonBlockPos = bedwars.BlockController:getBlockPosition(cannonPos),
			lookVector = lookVector
		})
	end

	local function getCannonNear(pos)
		local worldFolder = getWorldFolder()
		if not worldFolder then return end
		local blocks = worldFolder:WaitForChild("Blocks", 1)
		if not blocks then return end

		for _, v in blocks:GetChildren() do
			if v.Name == "cannon" and v:IsA("BasePart") then
				if (v.Position - pos).Magnitude <= 12 then
					return v
				end
			end
		end
		return nil
	end


	local function doTeleport()
		local targetPos = nil

		if Mode.Value == 'Players' then
			local plr = getNearestPlayer(lplr.Character.HumanoidRootPart.Position)
			if not plr then
				vape:CreateNotification("MouseTP", "No nearest players near Me.", 6)
				return
			end
			targetPos = plr.Character.HumanoidRootPart.Position

		elseif Mode.Value == 'Mouse' then
			local rayCheck = RaycastParams.new()
			rayCheck.RespectCanCollide = true
			rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}

			local mouse = cloneref(lplr:GetMouse())
			local result = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 10000, rayCheck)

			if result then
				targetPos = result.Position + Vector3.new(0, entitylib.character.HipHeight or 2, 0)
			else
				vape:CreateNotification('MouseTP', 'No position found.', 6)
				return
			end

		elseif Mode.Value == 'Camera' then
			targetPos = gameCamera.CFrame.Position + gameCamera.CFrame.LookVector * 200
		else
			vape:CreateNotification('MouseTP', 'Mode is currently nil. Report to aero or soryed', 6, 'warning')
			return
		end

		if Movement.Value == 'Me' then
			local root = entitylib.character.RootPart
			if root then
				local lookVec = root.CFrame.LookVector
				root.CFrame = CFrame.lookAt(targetPos, targetPos + lookVec)
			end

		elseif Movement.Value == 'Kits' and store.equippedKit == 'davey' then
			local cannon = getCannonNear(lplr.Character.HumanoidRootPart.Position)
			if cannon then
				aimCannon(cannon, targetPos)
			end

		elseif Movement.Value == 'Items' then
			local pearl = getItem('telepearl')
			local fireball = getItem('fireball')
			local tool = store.hand.tool

			if pearl and tool and tool.Name == 'telepearl' then
				local meta = bedwars.ProjectileMeta.telepearl
				local dir = CFrame.lookAt(lplr.Character.HumanoidRootPart.Position, targetPos).LookVector * meta.launchVelocity

				projectileRemote:InvokeServer(
					tool, 'telepearl', 'telepearl',
					lplr.Character.HumanoidRootPart.Position,
					lplr.Character.HumanoidRootPart.Position,
					dir,
					httpService:GenerateGUID(true),
					{drawDurationSeconds = 1, shotId = httpService:GenerateGUID(false)},
					workspace:GetServerTimeNow() - 0.045
				)

			elseif fireball and tool and tool.Name == 'fireball' then
				local meta = bedwars.ProjectileMeta.fireball 
				local dir = CFrame.lookAt(lplr.Character.HumanoidRootPart.Position, targetPos).LookVector * meta.launchVelocity

				projectileRemote:InvokeServer(
					tool, 'fireball', 'fireball',
					lplr.Character.HumanoidRootPart.Position,
					lplr.Character.HumanoidRootPart.Position,
					dir,
					httpService:GenerateGUID(true),
					{drawDurationSeconds = 1, shotId = httpService:GenerateGUID(false)},
					workspace:GetServerTimeNow() - 0.045
				)
			end
		else
			vape:CreateNotification('MouseTP', 'Movement is currently nil. Report to aero or soryed', 6, 'warning')
			return
		end
	end

	MouseTP = vape.Categories.Blatant:CreateModule({
		Name = "MouseTP",
		Tooltip = 'allows you to teleport with various methods',
		Function = function(callback)
			if callback then
				doTeleport()
			end
		end
	})

	Mode = MouseTP:CreateDropdown({
		Name = 'Mode',
		List = {'Players', 'Mouse', 'Camera'},
		Default = 'Players'
	})

	Movement = MouseTP:CreateDropdown({
		Name = "Movement",
		List = {'Me', 'Kits', 'Items'},
		Default = 'Me',
		Tooltip = 'Me-uses you to teleport\nKits-uses kits abilities to tp\nitems-uses items to telport'
	})
end)

run(function()
	local Viewmodel
	local Depth
	local Horizontal
	local Vertical
	local NoBob
	local Rots = {}
	local old, oldc1
	
	Viewmodel = vape.Categories.Combat:CreateModule({
		Name = 'Viewmodel',
		Function = function(callback)
			local viewmodel = gameCamera:FindFirstChild('Viewmodel')
			if callback then
				old = bedwars.ViewmodelController.playAnimation
				oldc1 = viewmodel and viewmodel.RightHand.RightWrist.C1 or CFrame.identity
				if NoBob.Enabled then
					bedwars.ViewmodelController.playAnimation = function(self, animtype, ...)
						if bedwars.AnimationType and animtype == bedwars.AnimationType.FP_WALK then return end
						return old(self, animtype, ...)
					end
				end
	
				bedwars.InventoryViewmodelController:handleStore(bedwars.Store:getState())
				if viewmodel then
					gameCamera.Viewmodel.RightHand.RightWrist.C1 = oldc1 * CFrame.Angles(math.rad(Rots[1].Value), math.rad(Rots[2].Value), math.rad(Rots[3].Value))
				end
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', -Depth.Value)
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', Horizontal.Value)
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', Vertical.Value)
			else
				bedwars.ViewmodelController.playAnimation = old
				if viewmodel then
					viewmodel.RightHand.RightWrist.C1 = oldc1
				end
	
				bedwars.InventoryViewmodelController:handleStore(bedwars.Store:getState())
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', 0)
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', 0)
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', 0)
				old = nil
			end
		end,
		Tooltip = 'change viewmodel animations'
	})
	Depth = Viewmodel:CreateSlider({
		Name = 'Depth',
		Min = 0,
		Max = 2,
		Default = 0.8,
		Decimal = 10,
		Function = function(val)
			if Viewmodel.Enabled then
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', -val)
			end
		end
	})
	Horizontal = Viewmodel:CreateSlider({
		Name = 'Horizontal',
		Min = 0,
		Max = 2,
		Default = 0.8,
		Decimal = 10,
		Function = function(val)
			if Viewmodel.Enabled then
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', val)
			end
		end
	})
	Vertical = Viewmodel:CreateSlider({
		Name = 'Vertical',
		Min = -0.2,
		Max = 2,
		Default = -0.2,
		Decimal = 10,
		Function = function(val)
			if Viewmodel.Enabled then
				lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', val)
			end
		end
	})
	for _, name in {'Rotation X', 'Rotation Y', 'Rotation Z'} do
		table.insert(Rots, Viewmodel:CreateSlider({
			Name = name,
			Min = 0,
			Max = 360,
			Function = function(val)
				if Viewmodel.Enabled then
					gameCamera.Viewmodel.RightHand.RightWrist.C1 = oldc1 * CFrame.Angles(math.rad(Rots[1].Value), math.rad(Rots[2].Value), math.rad(Rots[3].Value))
				end
			end
		}))
	end
	NoBob = Viewmodel:CreateToggle({
		Name = 'No Bobbing',
		Default = true,
		Function = function()
			if Viewmodel.Enabled then
				Viewmodel:Toggle()
				Viewmodel:Toggle()
			end
		end
	})
end)

run(function()
	local MotionBlur
	local MotionBlurStrength
	local motionBlurEffect = nil
	local lastLookVector = gameCamera.CFrame.LookVector
	local motionBlurConn = nil

	MotionBlur = vape.Categories.Legit:CreateModule({
		Name = 'MotionBlur',
		Function = function(callback)
			if callback then
				motionBlurEffect = Instance.new('BlurEffect')
				motionBlurEffect.Size = 0
				motionBlurEffect.Parent = gameCamera
				motionBlurConn = runService.RenderStepped:Connect(function()
					local currentLook = gameCamera.CFrame.LookVector
					local delta = (currentLook - lastLookVector).Magnitude
					lastLookVector = currentLook
					local targetSize = math.clamp(delta * (MotionBlurStrength.Value * 20), 0, 24)
					motionBlurEffect.Size = motionBlurEffect.Size + (targetSize - motionBlurEffect.Size) * 0.3 
				end)
			else
				if motionBlurConn then
					motionBlurConn:Disconnect()
					motionBlurConn = nil
				end
				if motionBlurEffect then
					motionBlurEffect:Destroy()
					motionBlurEffect = nil
				end
			end
		end,
	})

	MotionBlurStrength = MotionBlur:CreateSlider({
		Name = 'Strength',
		Min = 0,
		Max = 10,
		Default = 3,
		Decimal = 10,
	})
end)

run(function()
    local Caitlyn
    local MethodDropdown
    local LowHealthSlider
    local ExecuteRangeSlider
    local HitRangeSlider
    local ProximityRangeSlider
    local connections = {}
    local Players = playersService
    local lplr = Players.LocalPlayer
    local currentTarget = nil
    local lastHitTime = 0
    local lastContractSelect = 0
    
    local function selectContract(targetPlayer)
        if not entitylib.isAlive then return false end
        if tick() - lastContractSelect < 0.1 then return false end
        
        local storeState = bedwars.Store:getState()
        local activeContract = storeState.Kit.activeContract
        local availableContracts = storeState.Kit.availableContracts or {}
        
        if activeContract then return false end
        if #availableContracts == 0 then return false end
        
        for _, contract in pairs(availableContracts) do
            if contract.target == targetPlayer then
                bedwars.Client:Get(remotes.BloodAssassinSelectContract):SendToServer({
                    contractId = contract.id
                })
                lastContractSelect = tick()
                return true
            end
        end
        return false
    end
    
    local function executeOnLowHealth()
        if not currentTarget or tick() - lastHitTime > 3 then
            currentTarget = nil
            return
        end
        
        if not currentTarget.Character then return end
        
        local humanoid = currentTarget.Character:FindFirstChild("Humanoid")
        local rootPart = currentTarget.Character:FindFirstChild("HumanoidRootPart")
        
        if humanoid and rootPart and lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart") then
            local health = humanoid.Health
            local distance = (lplr.Character.HumanoidRootPart.Position - rootPart.Position).Magnitude
            
            if health > 0 and health <= LowHealthSlider.Value and distance <= ExecuteRangeSlider.Value then
                selectContract(currentTarget)
            end
        end
    end
    
    local function contractOnHit()
        if not currentTarget or tick() - lastHitTime > 0.5 then
            currentTarget = nil
            return
        end
        
        if not currentTarget.Character then return end
        
        local rootPart = currentTarget.Character:FindFirstChild("HumanoidRootPart")
        
        if rootPart and lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart") then
            local distance = (lplr.Character.HumanoidRootPart.Position - rootPart.Position).Magnitude
            
            if distance <= HitRangeSlider.Value then
                selectContract(currentTarget)
            end
        end
    end
    
    local function proximityContract()
        if not entitylib.isAlive then return end
        
        local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end
        
        local closestPlayer = nil
        local closestDistance = ProximityRangeSlider.Value
        
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= lplr and player.Character then
                local theirRoot = player.Character:FindFirstChild("HumanoidRootPart")
                local humanoid = player.Character:FindFirstChild("Humanoid")
                
                if theirRoot and humanoid and humanoid.Health > 0 then
                    local distance = (myRoot.Position - theirRoot.Position).Magnitude
                    
                    if distance < closestDistance then
                        closestDistance = distance
                        closestPlayer = player
                    end
                end
            end
        end
        
        if closestPlayer then
            selectContract(closestPlayer)
        end
    end
    
    Caitlyn = vape.Categories.Kits:CreateModule({
        Name = 'AutoCaitlyn',
        Function = function(callback)
            if callback then
                local damageConnection = vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
                    if not entitylib.isAlive then return end
                    
                    local attacker = playersService:GetPlayerFromCharacter(damageTable.fromEntity)
                    local victim = playersService:GetPlayerFromCharacter(damageTable.entityInstance)
                
                    if attacker == lplr and victim and victim ~= lplr then
                        currentTarget = victim
                        lastHitTime = tick()
                    end
                end)
                table.insert(connections, damageConnection)
                
                task.spawn(function()
                    repeat
                        if entitylib.isAlive then
                            local method = MethodDropdown.Value
                            
                            if method == "Low HP" then
                                executeOnLowHealth()
                            elseif method == "Contract on Hit" then
                                contractOnHit()
                            elseif method == "Proximity Select" then
                                proximityContract()
                            end
                        end
                        task.wait(0.1)
                    until not Caitlyn.Enabled
                end)
            else
                for _, conn in pairs(connections) do
                    if typeof(conn) == "RBXScriptConnection" then
                        conn:Disconnect()
                    end
                end
                table.clear(connections)
                
                currentTarget = nil
                lastHitTime = 0
            end
        end,
        Tooltip = 'auto select contracts for cait based off varius situation'
    })
    
    MethodDropdown = Caitlyn:CreateDropdown({
        Name = 'Method',
        List = {"Low HP", "Contract on Hit", "Proximity Select"},
        Default = "Low HP",
        Tooltip = 'selection methods',
        Function = function(value)
            LowHealthSlider.Object.Visible = (value == "Low HP")
            ExecuteRangeSlider.Object.Visible = (value == "Low HP")
            HitRangeSlider.Object.Visible = (value == "Contract on Hit")
            ProximityRangeSlider.Object.Visible = (value == "Proximity Select")
        end
    })
    
    LowHealthSlider = Caitlyn:CreateSlider({
        Name = 'Select HP',
        Min = 10,
        Max = 100,
        Default = 30,
    })
    
    ExecuteRangeSlider = Caitlyn:CreateSlider({
        Name = 'Select Range',
        Min = 5,
        Max = 50,
        Default = 20,
        Suffix = ' studs',
    })
    
    HitRangeSlider = Caitlyn:CreateSlider({
        Name = 'Hit Range',
        Min = 10,
        Max = 200,
        Default = 100,
        Suffix = ' studs',
    })
    
    ProximityRangeSlider = Caitlyn:CreateSlider({
        Name = 'Proximity Range',
        Min = 10,
        Max = 200,
        Default = 50,
        Suffix = ' studs',
    })
    
    LowHealthSlider.Object.Visible = true
    ExecuteRangeSlider.Object.Visible = true
    HitRangeSlider.Object.Visible = false
    ProximityRangeSlider.Object.Visible = false
end)

run(function()
	local GrimReaperFix
	GrimReaperFix = vape.Categories.Utility:CreateModule({
		Name = 'GrimReaperFix',
		Function = function(callback)
			if callback then
				GrimReaperFix:Clean(runService.Heartbeat:Connect(function()
					if not entitylib.isAlive then return end
					local humanoid = entitylib.character.Humanoid
					if humanoid.HipHeight > 2.1 then
						humanoid.HipHeight = 2.05
					end
				end))
			end
		end,
		Tooltip = 'fixes grim height (prevents being too tall)'
	})
end)

run(function()
	local AutoEmber
	local Targets
	local Range
	local SpinCooldown
	local Limit
	local old = os.clock()+ 0.00000000000000000000013
	local isCharging = false
	local chargeAnim, FpChargeAnim = nil,nil
	AutoEmber = vape.Categories.Kits:CreateModule({
		Name = 'AutoEmber',
		Tooltip = 'automatically uses the ember ability',
		Function = function(call)
			if call then
				repeat
					if entitylib.isAlive then 
						local tool = getItem('infernal_saber') 
						if tool and (not Limit.Enabled or store.hand.tool and store.hand.tool.Name == 'infernal_saber') then
							local ent = entitylib.EntityPosition({
								Range = HoldRange.Value,
								Players = Targets.Players.Enabled,
								NPCs = Targets.NPCs.Enabled,
								Part = 'RootPart'
							}) 

							if not ent then
								if isCharging then
									isCharging = false
									bedwars.HellSaberController.animationMaid:DoCleaning()
									chargeAnim = nil
									FpChargeAnim = nil
									task.wait(0.3)
									continue
								end
							end

							if ent then
								if not isCharging then
									isCharging = true
									bedwars.HellSaberController:playChargeSound(lplr)
									local animer = lplr.Character
									if animer ~= nil then
										animer = animer:FindFirstChild("Humanoid")
										if animer ~= nil then
											animer = animer:FindFirstChild("Animator")
										end
									end
									if not animer then
										return nil
									end
									chargeAnim = animer:LoadAnimation(bedwars.GameAnimationUtil:getAnimation(bedwars.AnimationType.INFERNO_SWORD_CHARGE))
									chargeAnim:Play()
									chargeAnim:AdjustSpeed(1.83)
									chargeAnim:GetMarkerReachedSignal("end"):Connect(function()
										local newChargeAnim = chargeAnim
										if newChargeAnim ~= nil then
											newChargeAnim:AdjustSpeed(0)
										end
									end)
									FpChargeAnim = bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_INFERNO_SWORD_CHARGE)
									if FpChargeAnim then
										FpChargeAnim:GetMarkerReachedSignal("end"):Connect(function()
											local newFpChargeAnim = FpChargeAnim
											if newFpChargeAnim ~= nil then
												newFpChargeAnim:AdjustSpeed(0)
											end
										end)
									end
									bedwars.HellSaberController.animationMaid:GiveTask(function()
										local MaidCA1 = chargeAnim
										if MaidCA1 ~= nil then
											MaidCA1:Stop()
										end
										local MaidCA2 = chargeAnim
										if MaidCA2 ~= nil then
											MaidCA2:Destroy()
										end
										local MaidFCA1 = FpChargeAnim
										if MaidFCA1 ~= nil then
											MaidFCA1:Stop()
										end
										local MaidFCA2 = FpChargeAnim
										if MaidFCA2 ~= nil then
											MaidFCA2:Destroy()
										end
									end)
								end
								local DeltaPos = (ent.RootPart.Position - lplr.Character.HumanoidRootPart.Position).Magnitude
								if DeltaPos <= Range.Value then
									local now = os.clock() + 0.00000000000000000000013
									if (now - old) >= SpinCooldown.Value then
										bedwars.HellSaberController.animationMaid:DoCleaning()
										if not Limit.Enabled then
											switchItem(tool)
										end
										bedwars.Client:Get('HellBladeRelease'):SendToServer({
											chargeTime = 1 + tick() - (0.045 + (math.random() - math.random())), 
											weapon = tool,
											player = lplr
										})
										old = os.clock() + 0.00000000000000000000013
										bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_INFERNO_SWORD_SPIN)										
										isCharging = false
										
									end
								end
							end
						end
					end
					task.wait(0.1)
				until not AutoEmber.Enabled 
			end
		end
	})
	Targets = AutoEmber:CreateTargets({
		Players = true,
		NPCs = false
	})
	SpinCooldown = AutoEmber:CreateSlider({
		Name = 'Spin Cooldown',
		Min = 0,
		Max = 4,
		Default = 1.12,
		Decimal = 100,
		Tooltip = 'becareful anything below 0.2 is bannable'
	})
	Range = AutoEmber:CreateSlider({
		Name = 'Release Range',
		Min = 1,
		Max = 22,
		Default = 22,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
	HoldRange = AutoEmber:CreateSlider({
		Name = 'Hold Range',
		Min = 1,
		Max = 48,
		Default = 32,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
	Limit = AutoEmber:CreateToggle({Name = 'Limit to item'})
end)

run(function()
    local AutoUma
    local rangeSlider
    local limitToStaff
    local playAnim
    local autoSummon
    local useHeal
    local useAttack
    local targetDrops
    local allowDiamond
    local allowEmerald

    local function findStaff()
        if limitToStaff.Enabled then
            local held = store.hand.tool
            if held and held.Name == 'spirit_staff' then
                return held, getHotbar(held)
            end
            return nil
        end

        for slot, item in pairs(store.inventory.inventory.items) do
            if item.itemType == 'spirit_staff' then
                switchItem(item, 0)
                return item, slot
            end
        end
    end

    local function getClosestDrop(origin, drops)
        local closest, shortest = nil, rangeSlider.Value + 1

        for _, drop in pairs(drops) do
            local valid = (drop.Name == 'emerald' and allowEmerald.Enabled) or (drop.Name == 'diamond' and allowDiamond.Enabled)

            if valid then
                local dist = (origin - drop.Position).Magnitude

                if dist <= shortest and not entitylib.Wallcheck(origin, drop.Position, {gameCamera, lplr.Character, drop}) then
                    closest = drop
                    shortest = dist
                end
            end
        end

        return closest
    end

    local function fireSpirit(staff, origin, targetPos, hasAttackSpirit)
        local shootFrom = origin + Vector3.new(0, 2, 0)

        local predicted = targetPos + Vector3.new(0,(origin - targetPos).Magnitude / 5, 0)

        local direction = CFrame.lookAt(origin, predicted).LookVector * 100

        local _spiritRemote = bedwars.Client:Get(remotes.FireProjectile).instance
        if _spiritRemote then
            _spiritRemote:InvokeServer(staff, nil, hasAttackSpirit and 'attack_spirit' or 'heal_spirit',shootFrom,origin,direction,httpService:GenerateGUID(),{drawDurationSeconds = 1, shotId = httpService:GenerateGUID(false)},workspace:GetServerTimeNow() - 0.045)
        end

        if playAnim.Enabled then
            bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.WIZARD_BALL_CAST )
            bedwars.SoundManager:playSound(bedwars.SoundList.SPIRIT_SUMMONER_CHANGE_AFFINITY,{})
        end
    end

	AutoUma = vape.Categories.Kits:CreateModule({
        Name = 'AutoUma',
        Tooltip = 'auto uses spirit staff usage for drops',
        Function = function(enabled)
            if not enabled then return end
            repeat
                local drops = collection('ItemDrop', AutoUma)
                local staff = findStaff()

                if staff and targetDrops.Enabled then
                    local atkCount = lplr:GetAttribute('ReadySummonedAttackSpirits') or 0
                    local healCount = lplr:GetAttribute('ReadySummonedHealSpirits') or 0

                    if autoSummon.Enabled and getItem('summon_stone') then
                        if useAttack.Enabled and atkCount < 1 then
                            bedwars.AbilityController:useAbility('summon_attack_spirit')
                        end

                        if useHeal.Enabled and healCount < 1 then
                            bedwars.AbilityController:useAbility('summon_heal_spirit')
                        end
                    end

                    if (atkCount + healCount) > 0 then
                        local root = entitylib.character.RootPart
                        if root then
                            local pos = root.Position
                            local target = getClosestDrop(pos, drops)

                            if target then
                                fireSpirit(staff, pos, target.Position, atkCount > 0)
                                task.wait(1.5)
                            end
                        end
                    end
                end

                task.wait(0.1)
            until not AutoUma.Enabled
        end
    })

    rangeSlider = AutoUma:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 80,
        Default = 50,
        Decimal = 5,
        Suffix = function(v)
            return v == 1 and 'stud' or 'studs'
        end
    })

    playAnim = AutoUma:CreateToggle({
        Name = 'Play Animation',
        Default = true
    })

    limitToStaff = AutoUma:CreateToggle({
        Name = 'Only When Holding Staff',
        Default = true
    })

    autoSummon = AutoUma:CreateToggle({
        Name = 'Auto Summon',
        Function = function(state)
            pcall(function()
                useAttack.Object.Visible = state
                useHeal.Object.Visible = state
            end)
        end
    })

    useHeal = AutoUma:CreateToggle({
        Name = 'Heal Spirit',
        Default = true,
        Visible = false,
        Darker = true
    })

    useAttack = AutoUma:CreateToggle({
        Name = 'Attack Spirit',
        Default = true,
        Visible = false,
        Darker = true
    })

    targetDrops = AutoUma:CreateToggle({
        Name = 'Target Drops',
        Default = true,
        Function = function(state)
            pcall(function()
                allowEmerald.Object.Visible = state
                allowDiamond.Object.Visible = state
            end)
        end
    })

    allowEmerald = AutoUma:CreateToggle({
        Name = 'Emerald',
        Default = true,
        Darker = true
    })

    allowDiamond = AutoUma:CreateToggle({
        Name = 'Diamond',
        Default = true,
        Darker = true
    })
end)

run(function()
    local BedAssist = {Enabled = false}
    local bedassistrange = {Value = 30}
    local bedassistsmoothness = {Value = 6}
    local bedassistangle = {Value = 70}
    local bedassistfirstperson = {Enabled = false}
    local bedassistshopcheck = {Enabled = false}
	local bedassisthandcheck = {Enabled = false}
	local bedassistlowestblock = {Enabled = false}
	local function getBedAimSpeed(speedVal, dt)
		local baseSpeed = 0.01
		local multiplier = 1.35
		local speed = baseSpeed * (multiplier ^ speedVal)
		return math.min(speed, 0.95) * (dt * 60)
	end

	local function checkHand()
		return isHoldingPickaxe() or isHoldingItem({'axe'})
	end

    local function shouldAimAtBed(bed)
        if not bed then return false end
        local tier = getBedPlacerTier(bed)
        return true
    end

    local camera = gameCamera

    local beds = {}
    local Connections = {}

    local function isFirstPerson()
        if not (lplr.Character and lplr.Character:FindFirstChild("Head")) then return false end
        return (lplr.Character.Head.Position - camera.CFrame.Position).Magnitude < 2
    end

    local function getClosestEnemyBed(playerPos)
        local closestBed = nil
        local closestDistance = bedassistrange.Value
        local lowestY = math.huge

        for _, bed in pairs(beds) do
            if not bed.Parent then continue end

            if tostring(bed:GetAttribute("TeamId")) == tostring(lplr:GetAttribute("Team")) then
                continue
            end

            if bed:GetAttribute("BedShieldEndTime") and bed:GetAttribute("BedShieldEndTime") > workspace:GetServerTimeNow() then
                continue
            end

            if not shouldAimAtBed(bed) then
                continue
            end

            local distance = (playerPos - bed.Position).Magnitude
            if distance > bedassistrange.Value then continue end

            local delta = (bed.Position - playerPos)
            local localfacing = (lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart") and lplr.Character.HumanoidRootPart.CFrame.LookVector * Vector3.new(1, 0, 1)) or Vector3.new(1, 0, 0)
            local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))

            if angle <= math.rad(bedassistangle.Value) / 2 then
                if bedassistlowestblock.Enabled then
                    if bed.Position.Y < lowestY then
                        lowestY = bed.Position.Y
                        closestBed = bed
                    end
                else
                    if distance < closestDistance then
                        closestDistance = distance
                        closestBed = bed
                    end
                end
            end
        end

        return closestBed
    end


    BedAssist = vape.Categories.Utility:CreateModule({
        Name = "BedAssist",
        Function = function(callback)
            if callback then
                beds = collectionService:GetTagged("bed")
                local connection
                connection = runService.Heartbeat:Connect(function(dt)
                    if not BedAssist.Enabled then
                        connection:Disconnect()
                        camera.CameraType = Enum.CameraType.Custom
                        return
                    end
                    if not entitylib.isAlive then
                        return
                    end
					if bedassisthandcheck.Enabled and not checkHand() then 
						return
					end
                    if bedassistfirstperson.Enabled and not isFirstPerson() then
                        return
                    end
                    if bedassistshopcheck.Enabled then
                        local isShop = lplr:FindFirstChild("PlayerGui") and lplr.PlayerGui:FindFirstChild("ItemShop")
                        if isShop then return end
                    end

                    local playerPos = entitylib.LocalPosition or entitylib.character.HumanoidRootPart.Position
                    local closestBed = getClosestEnemyBed(playerPos)

                    if closestBed then
                        local bedPos = closestBed.Position
                        local currentCFrame = camera.CFrame
                        local targetCFrame = CFrame.lookAt(currentCFrame.Position, bedPos)
                        local lerpAmount = bedassistsmoothness.Value / 15
                        camera.CFrame = currentCFrame:Lerp(targetCFrame, math.min(getBedAimSpeed(bedassistsmoothness.Value, dt), 0.95))
                    end
                end)
                table.insert(Connections, connection)
            else
                for _, v in pairs(Connections) do
                    pcall(function()
                        v:Disconnect()
                    end)
                end
                Connections = {}
                table.clear(beds)
                camera.CameraType = Enum.CameraType.Custom
            end
        end,
        Tooltip = "aa for beds lol"
    })

    bedassistrange = BedAssist:CreateSlider({
        Name = "Assist Range",
        Min = 10,
        Max = 100,
        Function = function(val) end,
        Default = 30,
        Suffix = function(val) 
            return val == 1 and "stud" or "studs" 
        end
    })

    bedassistsmoothness = BedAssist:CreateSlider({
        Name = "Aim Speed",
        Min = 1,
        Max = 20,
        Function = function(val) end,
        Default = 6
    })

    bedassistangle = BedAssist:CreateSlider({
        Name = "Max Angle",
        Min = 10,
        Max = 360,
        Function = function(val) end,
        Default = 70
    })

    bedassistfirstperson = BedAssist:CreateToggle({
        Name = "First Person Only",
        Function = function() end,
        Default = false,
    })

    bedassistshopcheck = BedAssist:CreateToggle({
        Name = "Shop Check",
        Function = function() end,
        Default = false,
    })

	bedassisthandcheck = BedAssist:CreateToggle({
		Name = "Hand Check",
		Function = function() end,
		Default = true,
	})

	bedassistlowestblock = BedAssist:CreateToggle({
		Name = "Target Lowest Block",
		Function = function() end,
		Default = false,
	})

    table.insert(Connections, collectionService:GetInstanceAddedSignal("bed"):Connect(function(bed)
        table.insert(beds, bed)
    end))

    table.insert(Connections, collectionService:GetInstanceRemovedSignal("bed"):Connect(function(bed)
        local i = table.find(beds, bed)
        if i then
            table.remove(beds, i)
        end
    end))
end)

run(function()
	local DamageIndicator
	local FontOption
	local Color
	local Size
	local Anchor
	local Stroke
	local suc, tab = pcall(function()
		return debug.getupvalue(bedwars.DamageIndicator, 2)
	end)
	tab = suc and tab or {}
	local oldvalues, oldfont = {}
	
	DamageIndicator = vape.Categories.Legit:CreateModule({
		Name = 'DamageIndicator',
		Function = function(callback)
			if callback then
				oldvalues = table.clone(tab)
				oldfont = debug.getconstant(bedwars.DamageIndicator, 86)
				debug.setconstant(bedwars.DamageIndicator, 86, Enum.Font[FontOption.Value])
				debug.setconstant(bedwars.DamageIndicator, 119, Stroke.Enabled and 'Thickness' or 'Enabled')
				tab.strokeThickness = Stroke.Enabled and 1 or false
				tab.textSize = Size.Value
				tab.blowUpSize = Size.Value
				tab.blowUpDuration = 0
				tab.baseColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
				tab.blowUpCompleteDuration = 0
				tab.anchoredDuration = Anchor.Value
			else
				for i, v in oldvalues do
					tab[i] = v
				end
				debug.setconstant(bedwars.DamageIndicator, 86, oldfont)
				debug.setconstant(bedwars.DamageIndicator, 119, 'Thickness')
			end
		end,
		Tooltip = 'customize the damage indicator'
	})
	local fontitems = {'GothamBlack'}
	for _, v in Enum.Font:GetEnumItems() do
		if v.Name ~= 'GothamBlack' then
			table.insert(fontitems, v.Name)
		end
	end
	FontOption = DamageIndicator:CreateDropdown({
		Name = 'Font',
		List = fontitems,
		Function = function(val)
			if DamageIndicator.Enabled then
				debug.setconstant(bedwars.DamageIndicator, 86, Enum.Font[val])
			end
		end
	})
	Color = DamageIndicator:CreateColorSlider({
		Name = 'Color',
		DefaultHue = 0,
		Function = function(hue, sat, val)
			if DamageIndicator.Enabled then
				tab.baseColor = Color3.fromHSV(hue, sat, val)
			end
		end
	})
	Size = DamageIndicator:CreateSlider({
		Name = 'Size',
		Min = 1,
		Max = 32,
		Default = 32,
		Function = function(val)
			if DamageIndicator.Enabled then
				tab.textSize = val
				tab.blowUpSize = val
			end
		end
	})
	Anchor = DamageIndicator:CreateSlider({
		Name = 'Anchor',
		Min = 0,
		Max = 1,
		Decimal = 10,
		Function = function(val)
			if DamageIndicator.Enabled then
				tab.anchoredDuration = val
			end
		end
	})
	Stroke = DamageIndicator:CreateToggle({
		Name = 'Stroke',
		Function = function(callback)
			if DamageIndicator.Enabled then
				debug.setconstant(bedwars.DamageIndicator, 119, callback and 'Thickness' or 'Enabled')
				tab.strokeThickness = callback and 1 or false
			end
		end
	})
end)

run(function()
	local UIS = game:GetService('UserInputService')
	local CustomCursor = {Enabled = false}
	local mouseDropdown = {Value = 'Arrow'}
	local mouseIcons = {
		['CS:GO'] = 'rbxassetid://14789879068',
		['Old Roblox Mouse'] = 'rbxassetid://13546344315',
		['dx9ware'] = 'rbxassetid://12233942144',
		['Aimbot'] = 'rbxassetid://8680062686',
		['Triangle'] = 'rbxassetid://14790304072',
		['Arrow'] = 'rbxassetid://14790316561'
	}
	local customMouseIcon = {Enabled = false}
	local customIcon = {Value = ''}
	CustomCursor = vape.Categories.Utility:CreateModule({
		Name = 'CustomCursor',
		Tooltip = 'changes your cursor\'s image.',
		Function = function(callback)
			if callback then
				task.spawn(function()
					repeat task.wait()
						if customMouseIcon.Enabled then
							UIS.MouseIcon = 'rbxassetid://' .. customIcon.Value
						else
							UIS.MouseIcon = mouseIcons[mouseDropdown.Value]
						end
					until not CustomCursor.Enabled
				end)
			else
				UIS.MouseIcon = ''
				task.wait()
				UIS.MouseIcon = ''
			end
		end
	})
	mouseDropdown = CustomCursor:CreateDropdown({
		Name = 'Mouse Icon',
		List = {
			'CS:GO',
			'Old Roblox Mouse',
			'dx9ware',
			'Aimbot',
			'Triangle',
			'Arrow'
		},
		Function = function() end
	})
	customMouseIcon = CustomCursor:CreateToggle({
		Name = 'Custom Icon',
		Function = function(callback) end
	})
	customIcon = CustomCursor:CreateTextBox({
		Name = 'Custom Mouse Icon',
		TempText = 'Image ID (not decal)',
		FocusLost = function(enter) 
			if CustomCursor.Enabled then 
				CustomCursor:Toggle(false)
				CustomCursor:Toggle(false)
			end
		end
	})
end)

run(function()
	local AutoEmote
	if not remotes.Emote then remotes.Emote = "Emote" end
	AutoEmote = vape.Categories.Utility:CreateModule({
		Name = "AutoEmote",
		Function = function(callback) end,
		Tooltip = "only plays bed break emote on kill"
	})
	AutoEmote:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
		local killer = playersService:GetPlayerFromCharacter(deathTable.fromEntity)
		local killed = playersService:GetPlayerFromCharacter(deathTable.entityInstance)
		if killer == lplr and killed and killed ~= lplr then
			if not AutoEmote.Enabled then return end
			if not entitylib.isAlive then return end
			pcall(function()
				bedwars.Client:Get(remotes.Emote):CallServer({ emoteType = 'bed_break' })
			end)
		end
	end))
end)


run(function()
	local DRBedAlarm
	local DetectionRange
	local RepeatNotifications
	local NotificationDelay
	local UseDisplayName
	local NotifyKits
	local TepearlCheck
	local TepearlRange
	local HighlightEnemies
	local HighlightColor
	local PlayAlarmSound
	local UseCustomSound
	local AlarmSoundId
	local AlarmVolume
	local customAlarmSound = nil
	local AlarmActive = false
	local PlayersNearBed = {}
	local LastNotificationTime = {}
	local CachedBed = nil
	local CachedBedPosition = nil
	local LastBedCheck = 0
	local PearlCache = {} 
	local LastPearlCheck = {}
	local ActiveHighlights = {}
	local LastAlarmSoundTick = 0
	
	local function getKitName(kitId)
		if bedwars.BedwarsKitMeta[kitId] then
			return bedwars.BedwarsKitMeta[kitId].name
		end
		return kitId:gsub("_", " "):gsub("^%l", string.upper)
	end
	
	local function getOwnBed()
		local currentTime = tick()
		
		if CachedBed and CachedBed.Parent and (currentTime - LastBedCheck) < 2 then
			return CachedBed, CachedBedPosition
		end
		
		if not entitylib.isAlive then 
			CachedBed = nil
			CachedBedPosition = nil
			return nil 
		end
		
		local playerTeam = lplr:GetAttribute('Team')
		if not playerTeam then 
			CachedBed = nil
			CachedBedPosition = nil
			return nil 
		end
		
		local tagged = collectionService:GetTagged('bed')
		for _, bed in ipairs(tagged) do
			if bed:GetAttribute('Team'..playerTeam..'NoBreak') then
				CachedBed = bed
				CachedBedPosition = bed.Position
				LastBedCheck = currentTime
				return bed, CachedBedPosition
			end
		end
		
		CachedBed = nil
		CachedBedPosition = nil
		return nil
	end
	
	local function getPlayerName(ent)
		if not ent.Player then return ent.Character.Name end
		return UseDisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name
	end
	
	local function getPlayerKit(ent)
		if not ent.Player then return nil end
		local kit = ent.Player:GetAttribute('PlayingAsKits')
		if kit and kit ~= 'none' then
			return getKitName(kit)
		end
		return nil
	end
	
	local function isHoldingPearl(ent, currentTime)
		if not ent.Player then return false end
		
		local lastCheck = LastPearlCheck[ent] or 0
		if (currentTime - lastCheck) < 0.5 and PearlCache[ent] ~= nil then
			return PearlCache[ent]
		end
		
		local inventory = store.inventories[ent.Player]
		if not inventory then 
			PearlCache[ent] = false
			LastPearlCheck[ent] = currentTime
			return false 
		end
		
		local handItem = inventory.hand
		
		if handItem and handItem.itemType then
			local itemType = handItem.itemType:lower()
			local hasPearl = itemType == 'telepearl' or itemType == 'teleport_pearl' or itemType:find('pearl', 1, true)
			PearlCache[ent] = hasPearl
			LastPearlCheck[ent] = currentTime
			return hasPearl
		end
		
		PearlCache[ent] = false
		LastPearlCheck[ent] = currentTime
		return false
	end
	
	local function createHighlight(ent)
		if not HighlightEnemies.Enabled then return end
		if ActiveHighlights[ent] then return end
		
		local character = ent.Character
		if not character then return end
		
		local highlight = Instance.new("Highlight")
		highlight.Name = "DRBedAlarmHighlight"
		highlight.Adornee = character
		local hue, sat, val = HighlightColor.Hue, HighlightColor.Sat, HighlightColor.Value
		local color = Color3.fromHSV(hue, sat, val)
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.FillTransparency = 0.5
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = character
		
		ActiveHighlights[ent] = highlight
	end
	
	local function removeHighlight(ent)
		if ActiveHighlights[ent] then
			ActiveHighlights[ent]:Destroy()
			ActiveHighlights[ent] = nil
		end
	end
	
	local function playAlarm(bedPosition, entPosition)
		if not PlayAlarmSound.Enabled then return end
		if os.time() < AlarmSoundTick then return end
		AlarmSoundTick = os.time() + 1.2

		if UseCustomSound and UseCustomSound.Enabled and AlarmSoundId and AlarmSoundId.Value and AlarmSoundId.Value ~= '' then
			pcall(function()
				if not customAlarmSound or not customAlarmSound.Parent then
					customAlarmSound = Instance.new('Sound')
					customAlarmSound.Parent = workspace
				end
				customAlarmSound.SoundId = 'rbxassetid://' .. AlarmSoundId.Value
				customAlarmSound.Volume = AlarmVolume.Value
				customAlarmSound:Play()
			end)
			return
		end

		local distance = entPosition and (bedPosition - entPosition).Magnitude or 0
		local soundId = distance >= 30 and bedwars.SoundList.BED_ALARM_TRIGGERED_FAR or bedwars.SoundList.BED_ALARM
		pcall(function()
			bedwars.SoundManager:playSound(soundId, {
				volumeMultiplier = AlarmVolume.Value
			})
		end)
	end
	
	local function stopAlarm()
	end
	
	local function createNotification(ent, hasPearl)
		local playerName = getPlayerName(ent)
		local message = playerName..' is near your bed!'
		
		if hasPearl then
			message = playerName..' is near your bed WITH A PEARL!'
		end
		
		if NotifyKits.Enabled then
			local kit = getPlayerKit(ent)
			if kit then
				if hasPearl then
					message = playerName..' is near your bed WITH A PEARL! (Kit: '..kit..')'
				else
					message = playerName..' is near your bed! (Kit: '..kit..')'
				end
			end
		end
		
		notif('Bed Alarm', message, 3)
	end
	
	local lastCheckTime = 0
	local function checkPlayers()
		if not DRBedAlarm.Enabled then return end
		if not entitylib.isAlive then return end
		
		local currentTime = tick()
		
		if (currentTime - lastCheckTime) < 0.1 then
			return
		end
		lastCheckTime = currentTime
		
		local bed, bedPosition = getOwnBed()
		if not bed or not bedPosition then return end
		
		local currentPlayersNear = {}
		local normalRange = DetectionRange.Value
		local pearlRangeEnabled = TepearlCheck.Enabled
		local pearlRange = pearlRangeEnabled and TepearlRange.Value or normalRange
		
		local normalRangeSq = normalRange * normalRange
		local pearlRangeSq = pearlRange * pearlRange
		
		local anyoneNear = false
		local lastNearEnt = nil
		
		for _, ent in ipairs(entitylib.List) do
			if not ent.Targetable then continue end
			if not ent.Player then continue end


			local distanceVector = ent.RootPart.Position - bedPosition
			local distanceSq = distanceVector.X * distanceVector.X + distanceVector.Y * distanceVector.Y + distanceVector.Z * distanceVector.Z
			
			local hasPearl = false
			local inRange = false
			
			if pearlRangeEnabled and distanceSq <= pearlRangeSq then
				hasPearl = isHoldingPearl(ent, currentTime)
				if hasPearl then
					inRange = true
				end
			end
			
			if not inRange and distanceSq <= normalRangeSq then
				inRange = true
			end
			
			if inRange then
				currentPlayersNear[ent] = true
				anyoneNear = true
				lastNearEnt = ent
				
				createHighlight(ent)
				
				local shouldNotify = false
				
				if not PlayersNearBed[ent] then
					shouldNotify = true
				elseif RepeatNotifications.Enabled then
					local lastTime = LastNotificationTime[ent] or 0
					if currentTime - lastTime >= NotificationDelay.Value then
						shouldNotify = true
					end
				end
				
				if shouldNotify then
					createNotification(ent, hasPearl)
					LastNotificationTime[ent] = currentTime
					if PlayAlarmSound.Enabled and tick() - LastAlarmSoundTick >= NotificationDelay.Value then
						LastAlarmSoundTick = tick()
						local distance = (bedPosition - ent.RootPart.Position).Magnitude
						local soundId = distance >= 30 and bedwars.SoundList.BED_ALARM_TRIGGERED_FAR or bedwars.SoundList.BED_ALARM
						pcall(function()
							bedwars.SoundManager:playSound(soundId, {
								volumeMultiplier = AlarmVolume.Value
							})
						end)
					end
				end
			else
				removeHighlight(ent)
			end
		end
		
		for ent, _ in pairs(ActiveHighlights) do
			if not currentPlayersNear[ent] then
				removeHighlight(ent)
			end
		end
		
		PlayersNearBed = currentPlayersNear
	end
	
	DRBedAlarm = vape.Categories.Utility:CreateModule({
		Name = 'DRBedAlarm',
		Function = function(callback)
			if callback then
				local bed = getOwnBed()
				if not bed then
					notif('DRBedAlarm', 'cant locate your bed', 3)
					DRBedAlarm:Toggle()
					return
				end
				
				AlarmActive = true
				PlayersNearBed = {}
				LastNotificationTime = {}
				PearlCache = {}
				LastPearlCheck = {}
				ActiveHighlights = {}
				lastCheckTime = 0
				
				DRBedAlarm:Clean(task.spawn(function()
					while DRBedAlarm.Enabled do
						checkPlayers()
						task.wait(0.1)
					end
				end))
			else
				AlarmActive = false
				
				stopAlarm()
				AlarmSoundTick = 0
				
				for ent, highlight in pairs(ActiveHighlights) do
					if highlight then
						highlight:Destroy()
					end
				end
				
				table.clear(PlayersNearBed)
				table.clear(LastNotificationTime)
				table.clear(PearlCache)
				table.clear(LastPearlCheck)
				table.clear(ActiveHighlights)
				CachedBed = nil
				CachedBedPosition = nil
			end
		end,
		Tooltip = 'bedalarm that dr likes :sob:'
	})
	
	DetectionRange = DRBedAlarm:CreateSlider({
		Name = 'Detection Range',
		Function = function() end,
		Default = 30,
		Min = 10,
		Max = 100,
	})
	
	TepearlCheck = DRBedAlarm:CreateToggle({
		Name = 'Telepearl Check',
		Function = function(callback)
			if TepearlRange and TepearlRange.Object then
				TepearlRange.Object.Visible = callback
			end
		end,
		Default = false,
	})
	
	TepearlRange = DRBedAlarm:CreateSlider({
		Name = 'Pearl Range',
		Function = function() end,
		Default = 250,
		Min = 100,
		Max = 500,
		Visible = false,
	})
	
	RepeatNotifications = DRBedAlarm:CreateToggle({
		Name = 'Repeat Notifications',
		Function = function(callback)
			if NotificationDelay and NotificationDelay.Object then
				NotificationDelay.Object.Visible = callback
			end
		end,
		Default = false,
	})
	
	NotificationDelay = DRBedAlarm:CreateSlider({
		Name = 'Notification Delay',
		Function = function() end,
		Default = 5,
		Min = 1,
		Max = 10,
		Visible = false,
	})
	
	UseDisplayName = DRBedAlarm:CreateToggle({
		Name = 'Show Display Name',
		Function = function() end,
		Default = true,
	})
	
	NotifyKits = DRBedAlarm:CreateToggle({
		Name = 'Notify Kits',
		Function = function() end,
		Default = true,
	})
	
	HighlightEnemies = DRBedAlarm:CreateToggle({
		Name = 'Highlight Enemies',
		Function = function(callback)
			if HighlightColor and HighlightColor.Object then
				HighlightColor.Object.Visible = callback
			end
			
			if not callback then
				for ent, highlight in pairs(ActiveHighlights) do
					if highlight then
						highlight:Destroy()
					end
				end
				table.clear(ActiveHighlights)
			end
		end,
		Default = false,
	})
	
	HighlightColor = DRBedAlarm:CreateColorSlider({
		Name = 'Highlight Color',
		Function = function(hue, sat, val)
			local newColor = Color3.fromHSV(hue, sat, val)
			for ent, highlight in pairs(ActiveHighlights) do
				if highlight then
					highlight.FillColor = newColor
					highlight.OutlineColor = newColor
				end
			end
		end,
		Default = 1,
		Visible = false,
	})
	
	PlayAlarmSound = DRBedAlarm:CreateToggle({
		Name = 'Play Alarm Sound',
		Function = function(callback)
			if AlarmVolume and AlarmVolume.Object then
				AlarmVolume.Object.Visible = callback
			end
			if UseCustomSound and UseCustomSound.Object then
				UseCustomSound.Object.Visible = callback
			end
			if not callback then
				stopAlarm()
				if customAlarmSound and customAlarmSound.Parent then
					customAlarmSound:Stop()
				end
			end
		end,
		Default = false,
	})
	
	AlarmVolume = DRBedAlarm:CreateSlider({
		Name = 'Alarm Volume',
		Function = function() end,
		Default = 1.5,
		Min = 0.1,
		Max = 3,
		Decimal = 5,
		Visible = false,
	})

	UseCustomSound = DRBedAlarm:CreateToggle({
		Name = 'Use Custom Sound',
		Function = function(callback)
			if AlarmSoundId and AlarmSoundId.Object then
				AlarmSoundId.Object.Visible = callback
			end
			if not callback and customAlarmSound and customAlarmSound.Parent then
				customAlarmSound:Stop()
			end
		end,
		Default = false,
		Visible = false,
	})

	AlarmSoundId = DRBedAlarm:CreateTextBox({
		Name = 'Custom Sound ID',
		Default = '131961136',
		Visible = false,
	})
end)

run(function()
	local KnockbackDisplace
	local KBDirection
	local originalApplyKnockback
	local hooked = false

	local _cachedKnockbackUtil = nil
	local function findKnockbackUtil()
		if _cachedKnockbackUtil and rawget(_cachedKnockbackUtil, 'applyKnockback') then
			return _cachedKnockbackUtil
		end
		for _, v in getgc(true) do
			if type(v) == 'table' and rawget(v, 'applyKnockback') and rawget(v, 'getDirection') and rawget(v, 'applyKnockbackDirection') then
				_cachedKnockbackUtil = v
				return v
			end
		end
	end

	KnockbackDisplace = vape.Categories.Combat:CreateModule({
		Name = 'KnockbackDisplace',
		Function = function(callback)
			if callback then
				local util = findKnockbackUtil()
				if not util then
					notif('KnockbackDisplace', 'Failed to hook knockback!', 3)
					KnockbackDisplace:Toggle()
					return
				end
				originalApplyKnockback = util.applyKnockback
				util.applyKnockback = function(hrp, mass, sourcePos, modifier)
					local dir = KBDirection.Value
					if dir == 'Default' then
						return originalApplyKnockback(hrp, mass, sourcePos, modifier)
					elseif dir == 'Void' then
						hrp:ApplyImpulse(Vector3.new(0, -mass * 60, 0))
						return
					elseif dir == 'Up' then
						hrp:ApplyImpulse(Vector3.new(0, mass * 120, 0))
						return
					else
						local hrpPos = hrp.Position
						local cf = hrp.CFrame
						local fakeSource
						if dir == 'Left' then
							fakeSource = hrpPos + cf.RightVector * 10
						elseif dir == 'Right' then
							fakeSource = hrpPos - cf.RightVector * 10
						elseif dir == 'Reverse' then
							if sourcePos then
								fakeSource = Vector3.new(2 * hrpPos.X - sourcePos.X, sourcePos.Y, 2 * hrpPos.Z - sourcePos.Z)
							end
						end
						return originalApplyKnockback(hrp, mass, fakeSource or sourcePos, modifier)
					end
				end
				hooked = true
			else
				if hooked then
					local util = findKnockbackUtil()
					if util and originalApplyKnockback then
						util.applyKnockback = originalApplyKnockback
					end
					hooked = false
					originalApplyKnockback = nil
				end
			end
		end,
		Tooltip = 'changes your knockback direction'
	})

	KBDirection = KnockbackDisplace:CreateDropdown({
		Name = 'KBDirection',
		List = {'Default', 'Backwards', 'Up', 'Left', 'Right', 'Reverse'},
		Default = 'Default',
		Tooltip = 'Choose which direction to redirect your knockback'
	})
end)

run(function()
	local Mode
	local Value
	local WallCheck
	local AutoJump
	local AlwaysJump
	local rayCheck = cloneRaycast()
	rayCheck.RespectCanCollide = true
	rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
	
	Speed = vape.Categories.Blatant:CreateModule({
		Name = 'Speed',
		Function = function(callback)
			frictionTable.Speed = callback or nil
			updateVelocity()
			pcall(function()
				debug.setconstant(bedwars.WindWalkerController.updateSpeed, 7, callback and 'constantSpeedMultiplier' or 'moveSpeedMultiplier')
			end)
	
			if callback then
				Speed:Clean(runService.PreSimulation:Connect(function(dt)
					bedwars.StatefulEntityKnockbackController.lastImpulseTime = callback and math.huge or time()
					if entitylib.isAlive then
						if not (Fly and Fly.Enabled) and not (LongJump and LongJump.Enabled) then
							bedwars.SprintController:setSpeed(Mode.Value == 'CFrame' and 20 or Value.Value)
							if Mode.Value == 'CFrame' then
								local state = entitylib.character.Humanoid:GetState()
								if state == Enum.HumanoidStateType.Climbing then return end
			
								local root, velo = entitylib.character.RootPart, getSpeed()
								local moveDirection = AntiFallDirection or entitylib.character.Humanoid.MoveDirection
								local destination = (moveDirection * math.max(Value.Value - velo, 0) * dt)
			
								if WallCheck.Enabled then
									rayCheck.CollisionGroup = root.CollisionGroup
									local ray = workspace:Raycast(root.Position, destination, rayCheck)
									if ray then
										destination = ((ray.Position + ray.Normal) - root.Position)
									end
								end
			
								root.CFrame += destination
								root.AssemblyLinearVelocity = (moveDirection * velo) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
								if AutoJump.Enabled and (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed) and moveDirection ~= Vector3.zero and (Attacking or AlwaysJump.Enabled) then
									entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
								end
							end
						end
					end
				end))
			else
				bedwars.SprintController:setSpeed(bedwars.SprintController:isSprinting() and 20 or 14)
			end
		end,
		ExtraText = function()
			return 'Heatseeker'
		end,
		Tooltip = 'increases your movement with various methods.'
	})
	Mode = Speed:CreateDropdown({
		Name = 'Method',
		List = {'Bedwars', 'CFrame'},
		Default = 'CFrame'
	})
	Value = Speed:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 23,
		Default = 23,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	WallCheck = Speed:CreateToggle({
		Name = 'Wall Check',
		Default = true
	})
	AutoJump = Speed:CreateToggle({
		Name = 'AutoJump',
		Function = function(callback)
			AlwaysJump.Object.Visible = callback
		end
	})
	AlwaysJump = Speed:CreateToggle({
		Name = 'Always Jump',
		Visible = false,
		Darker = true
	})
end)

run(function()
	local NameTagSpoofer
	local CustomNameBox
	local nametagConnection = nil
	local trackedElements = {}
	local fakeLabels = {}

	local function getCustomName()
		if CustomNameBox and type(CustomNameBox.Value) == "string" and CustomNameBox.Value ~= "" then
			return CustomNameBox.Value
		end
		return "Me"
	end

	local function trackElement(element)
		if not element then return end
		if not element:IsA("TextLabel") then return end
		if element.Name ~= "PlayerName" and element.Name ~= "EntityName" then return end
		if trackedElements[element] then
			pcall(function() element.Text = getCustomName() end)
			return
		end
		pcall(function()
			local t = element.Text
			if type(t) ~= "string" then return end
			if t:find(lplr.Name, 1, true) or t:find(lplr.DisplayName, 1, true) then
				trackedElements[element] = t
				element.Text = getCustomName()
			end
		end)
	end

	local function handlePlayerUsername(element)
		if not element or not element:IsA("TextBox") then return end
		if element.Name ~= "PlayerUsername" then return end
		if fakeLabels[element] then
			fakeLabels[element].Text = "@" .. getCustomName()
			return
		end
		pcall(function()
			local t = element.Text
			if type(t) ~= "string" then return end
			if t:find(lplr.Name, 1, true) or t:find(lplr.DisplayName, 1, true) then
				element.Visible = false
				element.TextTransparency = 1
				element.TextStrokeTransparency = 1
				local fake = Instance.new("TextLabel")
				fake.Name = "FakeUsername"
				fake.Size = element.Size
				fake.Position = element.Position
				fake.BackgroundTransparency = 1
				fake.TextColor3 = element.TextColor3
				fake.TextScaled = element.TextScaled
				fake.Font = element.Font
				fake.TextXAlignment = element.TextXAlignment
				fake.TextYAlignment = element.TextYAlignment
				fake.Text = "@" .. getCustomName()
				fake.ZIndex = element.ZIndex + 1
				fake.Parent = element.Parent
				fakeLabels[element] = fake
			end
		end)
	end

	local function hideAtLabel(element)
		if not element then return end
		if not element:IsA("TextLabel") then return end
		if element.Name ~= "@" then return end
		pcall(function()
			local parent = element.Parent
			if parent and parent.Name == "PlayerUsername" then
				element.Visible = false
			end
		end)
	end

	local function processGui(gui)
		if not gui then return end
		pcall(function()
			for _, desc in pairs(gui:GetDescendants()) do
				trackElement(desc)
				handlePlayerUsername(desc)
				hideAtLabel(desc)
			end
		end)
	end

	NameTagSpoofer = vape.Categories.Render:CreateModule({
		Name = 'NameTagSpoofer',
		Tooltip = 'script made by sleepvs w mans',
		Function = function(callback)
			if callback then
				NameTagSpoofer:Clean(lplr.PlayerGui.ChildAdded:Connect(function(gui)
					if gui.Name == "TabListScreenGui" then
						task.wait(0.3)
						processGui(gui)
						NameTagSpoofer:Clean(gui.DescendantAdded:Connect(function(desc)
							task.wait()
							trackElement(desc)
							handlePlayerUsername(desc)
							hideAtLabel(desc)
						end))
					end
					if gui.Name == "KillFeedGui" then
						processGui(gui)
						NameTagSpoofer:Clean(gui.DescendantAdded:Connect(function(desc)
							task.wait()
							trackElement(desc)
						end))
					end
				end))

				local killFeed = lplr.PlayerGui:FindFirstChild("KillFeedGui")
				if killFeed then
					processGui(killFeed)
					NameTagSpoofer:Clean(killFeed.DescendantAdded:Connect(function(desc)
						task.wait()
						trackElement(desc)
					end))
				end

				nametagConnection = runService.RenderStepped:Connect(function()
					if not NameTagSpoofer.Enabled then return end
					pcall(function()
						local customName = getCustomName()

						for element, original in pairs(trackedElements) do
							if not element or not element.Parent then
								trackedElements[element] = nil
							else
								pcall(function() element.Text = customName end)
							end
						end

						for element, fake in pairs(fakeLabels) do
							if not element or not element.Parent then
								if fake then fake:Destroy() end
								fakeLabels[element] = nil
							else
								pcall(function() fake.Text = "@" .. customName end)
							end
						end

						local tl = lplr.PlayerGui:FindFirstChild("TabListScreenGui")
						if tl then processGui(tl) end

						local kf = lplr.PlayerGui:FindFirstChild("KillFeedGui")
						if kf then processGui(kf) end

						if lplr.Character then
							local head = lplr.Character:FindFirstChild("Head")
							if not head then return end
							local nametag = head:FindFirstChild("Nametag")
							if not nametag then return end
							local dc = nametag:FindFirstChild("DisplayNameContainer")
							if not dc then return end
							local dn = dc:FindFirstChild("DisplayName")
							if not dn or not dn:IsA("TextLabel") then return end
							pcall(function() dn.Text = customName end)
						end
					end)
				end)

			else
				if nametagConnection then
					nametagConnection:Disconnect()
					nametagConnection = nil
				end
				for element, original in pairs(trackedElements) do
					if element and element.Parent then
						pcall(function() element.Text = original end)
					end
				end
				table.clear(trackedElements)
				for element, fake in pairs(fakeLabels) do
					if fake then pcall(function() fake:Destroy() end) end
					if element and element.Parent then
						pcall(function()
							element.Visible = true
							element.TextTransparency = 0
							element.TextStrokeTransparency = 0
						end)
					end
				end
				table.clear(fakeLabels)
				local tl = lplr.PlayerGui:FindFirstChild("TabListScreenGui")
				if tl then
					for _, desc in pairs(tl:GetDescendants()) do
						if desc:IsA("TextLabel") and desc.Name == "@" then
							pcall(function() desc.Visible = true end)
						end
					end
				end
			end
		end,
		Tooltip = 'customize ur name in varius places'
	})

	CustomNameBox = NameTagSpoofer:CreateTextBox({
		Name = 'Custom Name',
		Default = 'Me',
		Placeholder = 'Enter name...',
		Function = function(value)
		end
	})
end)

run(function()
	local HealthFX
	local playerGui = lplr:WaitForChild('PlayerGui')

	local glowH, glowS, glowV = 0.33, 1, 1
	local glowSize
	local fontIndex = 1
	local fonts = {Enum.Font.GothamBold, Enum.Font.Gotham, Enum.Font.Arial, Enum.Font.ArialBold, Enum.Font.Code, Enum.Font.RobotoMono, Enum.Font.Fantasy, Enum.Font.Arcade, Enum.Font.Bangers, Enum.Font.PermanentMarker, Enum.Font.Antique, Enum.Font.Cartoon, Enum.Font.SciFi}
	local fontNames = {'GothamBold', 'Gotham', 'Arial', 'ArialBold', 'Code', 'RobotoMono', 'Fantasy', 'Arcade', 'Bangers', 'PermanentMarker', 'Antique', 'Cartoon', 'SciFi'}
	local heartbeat
	local effectFolder

	local originalBarColor = nil
	local originalLabelColor = nil
	local originalLabelFont = nil

	local function removeEffects()
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
		if effectFolder then
			pcall(function() effectFolder:Destroy() end)
			effectFolder = nil
		end
		local hotbar = playerGui:FindFirstChild('hotbar')
		if not hotbar then return end
		local container = hotbar:FindFirstChild('HotbarHealthbarContainer', true)
		local hpWrapper = hotbar:FindFirstChild('HealthbarProgressWrapper', true)
		if hpWrapper then
			local bar = hpWrapper:FindFirstChild('1')
			if bar and originalBarColor then
				pcall(function() bar.BackgroundColor3 = originalBarColor end)
			end
		end
		if container then
			local hpLabel = container:FindFirstChildWhichIsA('TextLabel')
			if hpLabel then
				pcall(function()
					if originalLabelColor then hpLabel.TextColor3 = originalLabelColor end
					if originalLabelFont then hpLabel.Font = originalLabelFont end
					local stroke = hpLabel:FindFirstChildWhichIsA('UIStroke')
					if stroke and stroke.Name == 'skidStroke' then stroke:Destroy() end
				end)
			end
		end
	end

	local function applyHealthFX()
		removeEffects()

		local hotbar = playerGui:FindFirstChild('hotbar')
		if not hotbar then return end
		local container = hotbar:FindFirstChild('HotbarHealthbarContainer', true)
		if not container then return end
		local hpWrapper = container:FindFirstChild('HealthbarProgressWrapper')
		if not hpWrapper then return end

		local bar = hpWrapper:FindFirstChild('1')
		if bar then originalBarColor = bar.BackgroundColor3 end

		local hpLabel = container:FindFirstChildWhichIsA('TextLabel')
		if hpLabel then
			originalLabelColor = hpLabel.TextColor3
			originalLabelFont = hpLabel.Font
		end
		local cachedBar = nil
		local cachedStroke = nil
		local function refreshCachedBar()
			cachedBar = nil
			local hotbarNow = playerGui:FindFirstChild('hotbar')
			if not hotbarNow then return end
			local wrapperNow = hotbarNow:FindFirstChild('HealthbarProgressWrapper', true)
			if not wrapperNow then return end
			cachedBar = wrapperNow:FindFirstChild('1')
		end
		local function ensureStroke()
			if cachedStroke and cachedStroke.Parent then return end
			if not hpLabel then return end
			cachedStroke = hpLabel:FindFirstChild('skidStroke')
			if not cachedStroke then
				cachedStroke = Instance.new('UIStroke')
				cachedStroke.Name = 'skidStroke'
				cachedStroke.Color = Color3.new(0, 0, 0)
				cachedStroke.Thickness = 2
				cachedStroke.Parent = hpLabel
			end
		end
		refreshCachedBar()
		ensureStroke()
		local t = 0
		heartbeat = game:GetService('RunService').RenderStepped:Connect(function(dt)
			if not HealthFX or not HealthFX.Enabled then return end
			t = t + dt

			local color = Color3.fromHSV(glowH, glowS, glowV)

			if not cachedBar or not cachedBar.Parent then
				refreshCachedBar()
			end
			if cachedBar then
				pcall(function() cachedBar.BackgroundColor3 = color end)
			end

			if hpLabel then
				pcall(function()
					hpLabel.TextColor3 = color
					hpLabel.Font = fonts[fontIndex] or Enum.Font.GothamBold
					ensureStroke()
				end)
			end
		end)
	end

	HealthFX = vape.Categories.Render:CreateModule({
		Name = 'HealthFX',
		Function = function(callback)
			if callback then
				applyHealthFX()
			else
				removeEffects()
			end
		end
	})

	HealthFX:CreateColorSlider({
		Name = 'Glow Color',
		Function = function(h, s, v)
			glowH, glowS, glowV = h, s, v
			if HealthFX.Enabled then applyHealthFX() end
		end
	})

	HealthFX:CreateDropdown({
		Name = 'Font',
		List = fontNames,
		Default = 'GothamBold',
		Function = function(val)
			for i, name in ipairs(fontNames) do
				if name == val then fontIndex = i break end
			end
		end
	})
end)

run(function()
	local Aura
	local nimConnections = {}
	local nimFolder = nil
	local nimHighlight = nil
	local nimParts = {}
	local nimExtra = {}
	local nimH, nimS, nimV = 0.65, 1, 1
	local nimSpeed = 1.5
	local nimStyle = 'randomshi'
	local nimOrbCount = 8
	local nimMode = 'Solid'
	local nimOrbCountSlider = nil

	local function removeAura()
		for _, conn in nimConnections do
			pcall(function() conn:Disconnect() end)
		end
		table.clear(nimConnections)
		table.clear(nimParts)
		table.clear(nimExtra)
		if nimFolder then
			pcall(function() nimFolder:Destroy() end)
			nimFolder = nil
		end
		if nimHighlight then
			pcall(function() nimHighlight:Destroy() end)
			nimHighlight = nil
		end
	end

	local function makePart(size, shape)
		local p = Instance.new('Part')
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Size = size or Vector3.new(0.45, 0.45, 0.45)
		if shape then p.Shape = shape end
		p.Parent = nimFolder
		return p
	end

	local function makeHighlight(character, fillTrans)
		local hl = Instance.new('Highlight')
		hl.Adornee = character
		hl.OutlineTransparency = 0
		hl.FillTransparency = fillTrans or 0.78
		hl.OutlineColor = Color3.fromHSV(nimH, nimS, nimV)
		hl.FillColor = Color3.fromHSV(nimH, nimS, nimV)
		hl.Parent = nimFolder
		return hl
	end

	local setups = {
		['randomshi'] = function(character)
			nimHighlight = makeHighlight(character, 0.75)
			for i = 1, nimOrbCount do
				local orb = makePart(Vector3.new(0.5, 0.5, 0.5), Enum.PartType.Ball)
				orb:SetAttribute('I', i)
				orb:SetAttribute('TIER', 1)
				table.insert(nimParts, orb)
			end
			local innerCount = math.max(3, math.floor(nimOrbCount * 0.6))
			for i = 1, innerCount do
				local orb = makePart(Vector3.new(0.28, 0.28, 0.28), Enum.PartType.Ball)
				orb:SetAttribute('I', i)
				orb:SetAttribute('TIER', 2)
				orb:SetAttribute('COUNT', innerCount)
				table.insert(nimExtra, orb)
			end
		end,
		['Saiyan'] = function(character)
			nimHighlight = makeHighlight(character, 0.55)
			nimHighlight.OutlineTransparency = 0.1
			for i = 1, 32 do
				local fl = makePart(Vector3.new(0.13, 0.8 + math.random() * 0.7, 0.13))
				fl:SetAttribute('TYPE', 'flame')
				fl:SetAttribute('AO', (i / 32) * math.pi * 2 + math.random() * 0.3)
				fl:SetAttribute('RO', 0.6 + math.random() * 0.8)
				fl:SetAttribute('SP', 2.5 + math.random() * 3.5)
				fl:SetAttribute('YO', math.random() * 5)
				fl:SetAttribute('LN', 0.5 + math.random() * 1.1)
				table.insert(nimParts, fl)
			end
			for i = 1, 18 do
				local ember = makePart(Vector3.new(0.1, 0.1, 0.1), Enum.PartType.Ball)
				ember:SetAttribute('TYPE', 'ember')
				ember:SetAttribute('AO', (i / 18) * math.pi * 2)
				ember:SetAttribute('RO', 0.4 + math.random() * 1.6)
				ember:SetAttribute('SP', 3 + math.random() * 4)
				ember:SetAttribute('YO', math.random() * 4)
				table.insert(nimExtra, ember)
			end
		end,
		['Storm'] = function(character)
			nimHighlight = makeHighlight(character, 0.94)
			nimHighlight.OutlineTransparency = 0.65
			local cloudOffsets = {
				Vector3.new(-2.2,5.2,0.3),Vector3.new(-1.1,5.6,-0.2),Vector3.new(0,5.9,0.4),
				Vector3.new(1.1,5.6,-0.3),Vector3.new(2.2,5.2,0.2),Vector3.new(-1.7,6.1,0.5),
				Vector3.new(-0.6,6.5,-0.3),Vector3.new(0.5,6.7,0.4),Vector3.new(1.6,6.2,-0.2),
				Vector3.new(-1.0,7.0,0.3),Vector3.new(0.0,7.3,-0.4),Vector3.new(1.0,6.9,0.2),
				Vector3.new(-2.0,5.3,-0.6),Vector3.new(0.1,5.4,-0.7),Vector3.new(1.9,5.3,-0.5),
				Vector3.new(-0.4,6.3,0.7),Vector3.new(0.5,6.0,-0.6),Vector3.new(0,5.7,0),
				Vector3.new(-1.5,5.0,0.8),Vector3.new(1.5,5.0,-0.8),Vector3.new(0,4.8,0.6),
			}
			for _, offset in cloudOffsets do
				local cloud = makePart(Vector3.new(1.3 + math.random()*0.8, 1.1 + math.random()*0.6, 1.2 + math.random()*0.7), Enum.PartType.Ball)
				cloud.Color = Color3.new(0.28, 0.28, 0.38)
				cloud.Material = Enum.Material.SmoothPlastic
				cloud.Transparency = 0.1 + math.random() * 0.18
				cloud:SetAttribute('TYPE', 'cloud')
				cloud:SetAttribute('OX', offset.X)
				cloud:SetAttribute('OY', offset.Y)
				cloud:SetAttribute('OZ', offset.Z)
				cloud:SetAttribute('BOB', math.random() * math.pi * 2)
				table.insert(nimParts, cloud)
			end
			for i = 1, 55 do
				local rain = makePart(Vector3.new(0.03, 0.45, 0.03))
				rain.Color = Color3.new(0.65, 0.82, 1)
				rain.Transparency = 0.28
				rain:SetAttribute('TYPE', 'rain')
				rain:SetAttribute('RX', (math.random() - 0.5) * 6.5)
				rain:SetAttribute('RZ', (math.random() - 0.5) * 6.5)
				rain:SetAttribute('RY', math.random() * 7)
				rain:SetAttribute('SPD', 6 + math.random() * 6)
				rain:SetAttribute('DRIFT', (math.random() - 0.5) * 0.5)
				table.insert(nimParts, rain)
			end
			for i = 1, 5 do
				local bolt = makePart(Vector3.new(0.05, 4.5, 0.05))
				bolt.Color = Color3.new(0.88, 0.88, 1)
				bolt.Transparency = 1
				bolt:SetAttribute('TYPE', 'lightning')
				bolt:SetAttribute('LX', (math.random() - 0.5) * 3)
				bolt:SetAttribute('LZ', (math.random() - 0.5) * 3)
				bolt:SetAttribute('NEXT', math.random() * 3 + 0.5)
				bolt:SetAttribute('FLASH', 0)
				table.insert(nimExtra, bolt)
			end
		end,
		['Sakura'] = function(character)
			nimHighlight = makeHighlight(character, 0.86)
			for i = 1, 24 do
				local petal = makePart(Vector3.new(0.32, 0.06, 0.28))
				petal.Color = Color3.fromHSV(0.92, 0.55, 1)
				petal:SetAttribute('TYPE', 'drift')
				petal:SetAttribute('AO', (i / 24) * math.pi * 2 + math.random() * 0.5)
				petal:SetAttribute('RD', 1.2 + math.random() * 2.0)
				petal:SetAttribute('YO', (math.random() - 0.3) * 6)
				petal:SetAttribute('DS', 0.4 + math.random() * 0.7)
				petal:SetAttribute('SW', math.random() * math.pi * 2)
				table.insert(nimParts, petal)
			end
			for i = 1, 14 do
				local petal = makePart(Vector3.new(0.28, 0.06, 0.24))
				petal.Color = Color3.fromHSV(0.93, 0.6, 1)
				petal:SetAttribute('TYPE', 'burst')
				local angle = math.random() * math.pi * 2
				local elev = (math.random() - 0.3) * math.pi * 0.6
				petal:SetAttribute('DX', math.cos(elev) * math.cos(angle))
				petal:SetAttribute('DY', math.sin(elev) * 0.6 + 0.25)
				petal:SetAttribute('DZ', math.cos(elev) * math.sin(angle))
				petal:SetAttribute('DIST', math.random() * 4)
				petal:SetAttribute('SPD', 1.2 + math.random() * 1.5)
				petal:SetAttribute('PHASE', math.random() * math.pi * 2)
				table.insert(nimExtra, petal)
			end
		end,
		['randomshi2'] = function(character)
			nimHighlight = makeHighlight(character, 0.45)
			nimHighlight.OutlineTransparency = 0.05
			for i = 1, 28 do
				local node = makePart(Vector3.new(0.28, 0.28, 0.28), Enum.PartType.Ball)
				node:SetAttribute('TYPE', 'ring')
				node:SetAttribute('I', i)
				node:SetAttribute('PH', (i / 28) * math.pi * 2)
				table.insert(nimParts, node)
			end
			for i = 1, 20 do
				local particle = makePart(Vector3.new(0.18, 0.18, 0.18), Enum.PartType.Ball)
				particle:SetAttribute('TYPE', 'spiral')
				particle:SetAttribute('ANGLE', (i / 20) * math.pi * 2)
				particle:SetAttribute('RADIUS', 2 + math.random() * 2)
				particle:SetAttribute('YO', (math.random() - 0.5) * 4)
				particle:SetAttribute('SPD', 0.5 + math.random() * 0.8)
				table.insert(nimParts, particle)
			end
			for i = 1, 16 do
				local frag = makePart(Vector3.new(0.15, 0.15, 0.15))
				frag:SetAttribute('TYPE', 'debris')
				frag:SetAttribute('AO', (i / 16) * math.pi * 2)
				frag:SetAttribute('RD', 2.5 + math.random() * 1.5)
				frag:SetAttribute('YO', (math.random() - 0.5) * 4)
				frag:SetAttribute('SP', 0.4 + math.random() * 0.6)
				table.insert(nimExtra, frag)
			end
		end,
		['Seraph'] = function(character)
			nimHighlight = makeHighlight(character, 0.8)
			local cometTilts = {0, math.pi / 3, math.pi * 2 / 3, math.pi / 5}
			local cometPhases = {0, math.pi / 2, math.pi, math.pi * 3 / 2}
			for c = 1, 4 do
				for j = 0, 8 do
					local sz = math.max(0.08, 0.5 - j * 0.045)
					local part = makePart(Vector3.new(sz, sz, sz), Enum.PartType.Ball)
					part:SetAttribute('COMET', c)
					part:SetAttribute('TRAIL', j)
					part:SetAttribute('TILT', cometTilts[c])
					part:SetAttribute('PHASE', cometPhases[c])
					table.insert(nimParts, part)
				end
			end
		end,
		['randomshi3'] = function(character)
			nimHighlight = makeHighlight(character, 0.42)
			nimHighlight.OutlineTransparency = 0.0
			for i = 1, 22 do
				local wisp = makePart(Vector3.new(0.18, 0.55, 0.18), Enum.PartType.Ball)
				wisp:SetAttribute('TYPE', 'wisp')
				wisp:SetAttribute('AO', (i / 22) * math.pi * 2 + math.random() * 0.4)
				wisp:SetAttribute('RO', 0.5 + math.random() * 1.2)
				wisp:SetAttribute('SP', 1.2 + math.random() * 2)
				wisp:SetAttribute('YO', math.random() * 6)
				table.insert(nimParts, wisp)
			end
			for i = 1, 14 do
				local frag = makePart(Vector3.new(0.25, 0.06, 0.2))
				frag:SetAttribute('TYPE', 'fragment')
				frag:SetAttribute('AO', (i / 14) * math.pi * 2)
				frag:SetAttribute('RD', 1.8 + math.random() * 1.4)
				frag:SetAttribute('YO', (math.random() - 0.5) * 2.5)
				frag:SetAttribute('SP', 0.6 + math.random() * 0.8)
				table.insert(nimExtra, frag)
			end
			local ring = makePart(Vector3.new(0.08, 0.08, 0.08))
			ring:SetAttribute('TYPE', 'deathring')
			ring:SetAttribute('RAD', 0)
			table.insert(nimExtra, ring)
		end,
		['snakers'] = function(character)
			nimHighlight = makeHighlight(character, 0.6)
			nimHighlight.OutlineTransparency = 0.05
			for i = 1, 36 do
				local scale = makePart(Vector3.new(0.35, 0.2, 0.25))
				scale:SetAttribute('TYPE', 'scale')
				scale:SetAttribute('I', i)
				scale:SetAttribute('TOTAL', 36)
				table.insert(nimParts, scale)
			end
			for i = 1, 20 do
				local ember = makePart(Vector3.new(0.12, 0.12, 0.12), Enum.PartType.Ball)
				ember:SetAttribute('TYPE', 'breath')
				ember:SetAttribute('AO', (i / 20) * math.pi * 2)
				ember:SetAttribute('DIST', math.random() * 5)
				ember:SetAttribute('SPD', 1.5 + math.random() * 2)
				ember:SetAttribute('YO', (math.random() - 0.5) * 3)
				table.insert(nimExtra, ember)
			end
		end,
	}

	local animators = {
		['randomshi'] = function(t, dt, base, col)
			local count = nimOrbCount
			local radius = 3.5
			for _, orb in nimParts do
				local i = orb:GetAttribute('I')
				local angle = (i / count) * math.pi * 2 + t * nimSpeed
				local x = math.cos(angle) * radius
				local z = math.sin(angle) * radius
				local y = math.sin(t * 2.5 + i * 0.8) * 0.5
				local pulse = 0.42 + math.abs(math.sin(t * 3 + i)) * 0.3
				local sz = 0.35 + pulse * 0.25
				local h = (i / count + t * 0.08) % 1
				pcall(function()
					orb.CFrame = CFrame.new(base + Vector3.new(x, y, z))
					orb.Color = Color3.fromHSV(h, 1, 1)
					orb.Size = Vector3.new(sz, sz, sz)
				end)
			end
			for _, orb in nimExtra do
				local i = orb:GetAttribute('I')
				local cnt = orb:GetAttribute('COUNT') or math.max(3, math.floor(nimOrbCount * 0.6))
				local angle = (i / cnt) * math.pi * 2 - t * nimSpeed * 1.4
				local r2 = 1.8
				local x = math.cos(angle) * r2
				local z = math.sin(angle) * r2
				local y = math.sin(t * 3.5 + i * 1.2) * 0.3
				local h = (i / cnt + t * 0.12) % 1
				pcall(function()
					orb.CFrame = CFrame.new(base + Vector3.new(x, y, z))
					orb.Color = Color3.fromHSV(h, 1, 1)
				end)
			end
		end,
		['Saiyan'] = function(t, dt, base, col)
			for _, p in nimParts do
				local typ = p:GetAttribute('TYPE')
				if typ == 'flame' then
					local ao = p:GetAttribute('AO')
					local ro = p:GetAttribute('RO')
					local sp = p:GetAttribute('SP')
					local yo = p:GetAttribute('YO')
					local ln = p:GetAttribute('LN')
					yo = yo + dt * sp * nimSpeed
					if yo > 5 then yo = 0 end
					p:SetAttribute('YO', yo)
					local wobble = math.sin(t * 3.5 + ao) * 0.22
					local flicker = math.sin(t * 8 + ao * 2) * 0.06
					local rx = math.cos(ao + wobble) * (ro + flicker)
					local rz = math.sin(ao + wobble) * (ro + flicker)
					local fade = yo / 5
					local fireH = 0.04 - (1 - fade) * 0.04
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(rx, yo - 1.8, rz))
						p.Color = Color3.fromHSV(fireH, 1, 0.7 + fade * 0.3)
						p.Transparency = math.clamp(fade * 1.1, 0, 0.92)
						p.Size = Vector3.new(0.09 + (1 - fade) * 0.1, ln * (1 - fade * 0.4), 0.09 + (1 - fade) * 0.1)
					end)
				end
			end
			for _, p in nimExtra do
				local typ = p:GetAttribute('TYPE')
				if typ == 'ember' then
					local ao = p:GetAttribute('AO')
					local ro = p:GetAttribute('RO')
					local sp = p:GetAttribute('SP')
					local yo = p:GetAttribute('YO')
					yo = yo + dt * sp * nimSpeed * 0.7
					if yo > 4 then yo = 0 end
					p:SetAttribute('YO', yo)
					local drift = math.sin(t * 2 + ao) * 0.3
					local rx = math.cos(ao + drift) * ro
					local rz = math.sin(ao + drift) * ro
					local fade = yo / 4
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(rx, yo - 1.5, rz))
						p.Color = Color3.fromHSV(0.06 + fade * 0.05, 1, 1)
						p.Transparency = math.clamp(fade * 1.3, 0, 1)
					end)
				end
			end
		end,
		['Storm'] = function(t, dt, base, col)
			for _, p in nimParts do
				local typ = p:GetAttribute('TYPE')
				if typ == 'cloud' then
					local ox = p:GetAttribute('OX')
					local oy = p:GetAttribute('OY')
					local oz = p:GetAttribute('OZ')
					local bob = p:GetAttribute('BOB')
					local drift = math.sin(t * 0.3 + bob) * 0.18
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(ox + drift * 0.3, oy + math.sin(t * 0.6 + bob) * 0.14, oz + drift * 0.15))
					end)
				elseif typ == 'rain' then
					local rx = p:GetAttribute('RX')
					local rz = p:GetAttribute('RZ')
					local ry = p:GetAttribute('RY')
					local spd = p:GetAttribute('SPD')
					local driftV = p:GetAttribute('DRIFT')
					ry = ry - dt * spd * nimSpeed
					if ry < -1.5 then ry = 7 end
					p:SetAttribute('RY', ry)
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(rx + driftV * t * 0.1, ry, rz)) * CFrame.Angles(0.08, 0, 0)
					end)
				end
			end
			for _, bolt in nimExtra do
				local flash = bolt:GetAttribute('FLASH')
				local nextTime = bolt:GetAttribute('NEXT')
				if flash > 0 then
					flash = flash - dt
					if flash <= 0 then
						flash = 0
						bolt:SetAttribute('NEXT', 1.5 + math.random() * 4)
					end
					pcall(function() bolt.Transparency = math.clamp(flash * 7, 0, 1) end)
					bolt:SetAttribute('FLASH', flash)
				else
					nextTime = nextTime - dt
					bolt:SetAttribute('NEXT', nextTime)
					if nextTime <= 0 then
						for _, b in nimExtra do
							local lx = (math.random() - 0.5) * 3.5
							local lz = (math.random() - 0.5) * 3.5
							b:SetAttribute('FLASH', 0.18 + math.random() * 0.12)
							b:SetAttribute('LX', lx)
							b:SetAttribute('LZ', lz)
							pcall(function()
								b.CFrame = CFrame.new(base + Vector3.new(lx, 2.25, lz))
								b.Transparency = 0
							end)
						end
						break
					else
						pcall(function() bolt.Transparency = 1 end)
					end
				end
			end
		end,
		['Sakura'] = function(t, dt, base, col)
			for _, petal in nimParts do
				local typ = petal:GetAttribute('TYPE')
				if typ == 'drift' then
					local ao = petal:GetAttribute('AO')
					local rd = petal:GetAttribute('RD')
					local yo = petal:GetAttribute('YO')
					local ds = petal:GetAttribute('DS')
					local sw = petal:GetAttribute('SW')
					yo = yo + dt * ds * nimSpeed
					if yo > 5.5 then yo = -1.5 end
					petal:SetAttribute('YO', yo)
					local sway = math.sin(t * 1.8 + sw) * 0.7
					local rx = math.cos(ao + sway * 0.25) * (rd + sway * 0.15)
					local rz = math.sin(ao + sway * 0.25) * (rd + sway * 0.15)
					local normalizedY = (yo + 1.5) / 7
					local fade = math.clamp(normalizedY * 1.3, 0, 0.85)
					pcall(function()
						petal.CFrame = CFrame.new(base + Vector3.new(rx, yo, rz)) * CFrame.Angles(math.sin(t + sw) * 0.6, ao + t * 0.4, math.cos(t * 0.8 + sw) * 0.6)
						petal.Color = Color3.fromHSV(0.92, 0.55 + math.sin(t * 0.5 + ao) * 0.08, 1)
						petal.Transparency = fade
					end)
				end
			end
			for _, petal in nimExtra do
				local typ = petal:GetAttribute('TYPE')
				if typ == 'burst' then
					local dx = petal:GetAttribute('DX')
					local dy = petal:GetAttribute('DY')
					local dz = petal:GetAttribute('DZ')
					local dist = petal:GetAttribute('DIST')
					local spd = petal:GetAttribute('SPD')
					dist = dist + dt * spd * nimSpeed
					if dist > 4.5 then
						dist = 0
						local angle = math.random() * math.pi * 2
						local elev = (math.random() - 0.3) * math.pi * 0.5
						petal:SetAttribute('DX', math.cos(elev) * math.cos(angle))
						petal:SetAttribute('DY', math.sin(elev) * 0.55 + 0.28)
						petal:SetAttribute('DZ', math.cos(elev) * math.sin(angle))
					end
					petal:SetAttribute('DIST', dist)
					local fade = dist / 4.5
					pcall(function()
						petal.CFrame = CFrame.new(base + Vector3.new(dx * dist, dy * dist, dz * dist)) * CFrame.Angles(t * spd, t * spd * 0.8, 0)
						petal.Color = Color3.fromHSV(0.92, 0.58, 1)
						petal.Transparency = math.clamp(fade * 1.3, 0, 1)
					end)
				end
			end
		end,
		['randomshi2'] = function(t, dt, base, col)
			for _, node in nimParts do
				local typ = node:GetAttribute('TYPE')
				if typ == 'ring' then
					local ph = node:GetAttribute('PH')
					local portalRadius = 2.8
					local ringX = math.cos(ph) * portalRadius
					local ringY = math.sin(ph) * portalRadius
					local pulse = 0.3 + math.abs(math.sin(t * 1.5 + ph)) * 0.4
					local darkH = (0.75 + (ph / (math.pi * 2)) * 0.15 + t * 0.03) % 1
					pcall(function()
						node.CFrame = CFrame.new(base + Vector3.new(ringX, ringY + 1, -3.5))
						node.Color = Color3.fromHSV(darkH, 1, pulse)
						node.Size = Vector3.new(0.22 + pulse * 0.12, 0.22 + pulse * 0.12, 0.22 + pulse * 0.12)
					end)
				elseif typ == 'spiral' then
					local angle = node:GetAttribute('ANGLE')
					local radius = node:GetAttribute('RADIUS')
					local yo = node:GetAttribute('YO')
					local spd = node:GetAttribute('SPD')
					radius = radius - dt * spd * nimSpeed * 0.4
					if radius < 0.3 then
						radius = 2 + math.random() * 2
						angle = math.random() * math.pi * 2
						yo = (math.random() - 0.5) * 4
						node:SetAttribute('YO', yo)
						node:SetAttribute('ANGLE', angle)
					end
					angle = angle + dt * nimSpeed * (1.5 / math.max(radius, 0.3))
					node:SetAttribute('RADIUS', radius)
					node:SetAttribute('ANGLE', angle)
					local fade = 1 - (radius / 4)
					local h = (0.75 + t * 0.05) % 1
					pcall(function()
						node.CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * radius, yo, math.sin(angle) * radius))
						node.Color = Color3.fromHSV(h, 1, 0.6 + fade * 0.4)
						node.Transparency = math.clamp(fade * 0.7, 0, 0.9)
					end)
				end
			end
			for _, node in nimExtra do
				local typ = node:GetAttribute('TYPE')
				if typ == 'debris' then
					local ao = node:GetAttribute('AO')
					local rd = node:GetAttribute('RD')
					local yo = node:GetAttribute('YO')
					local sp = node:GetAttribute('SP')
					local angle = ao + t * sp * nimSpeed
					local wobble = math.sin(t * 1.8 + ao) * 0.5
					local h = (0.78 + ao * 0.03 + t * 0.03) % 1
					pcall(function()
						node.CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * rd, yo + wobble, math.sin(angle) * rd)) * CFrame.Angles(t * sp * 2, t * sp, 0)
						node.Color = Color3.fromHSV(h, 1, 0.5 + math.abs(math.sin(t * 2 + ao)) * 0.4)
					end)
				end
			end
		end,
		['Seraph'] = function(t, dt, base, col)
			for _, part in nimParts do
				local c = part:GetAttribute('COMET')
				local j = part:GetAttribute('TRAIL')
				local tilt = part:GetAttribute('TILT')
				local phase = part:GetAttribute('PHASE')
				local angle = phase + t * nimSpeed * 1.4 - j * 0.18
				local radius = 3.2
				local fx = math.cos(angle) * radius
				local fy = math.sin(angle) * radius * math.sin(tilt)
				local fz = math.sin(angle) * radius * math.cos(tilt)
				local h = (c / 4 + t * 0.1) % 1
				local fade = j / 8
				pcall(function()
					part.CFrame = CFrame.new(base + Vector3.new(fx, fy, fz))
					part.Color = Color3.fromHSV(h, 1, 1 - fade * 0.3)
					part.Transparency = fade * 0.9
				end)
			end
		end,
		['randomshi3'] = function(t, dt, base, col)
			for _, p in nimParts do
				local typ = p:GetAttribute('TYPE')
				if typ == 'wisp' then
					local ao = p:GetAttribute('AO')
					local ro = p:GetAttribute('RO')
					local sp = p:GetAttribute('SP')
					local yo = p:GetAttribute('YO')
					yo = yo + dt * sp * nimSpeed * 0.55
					if yo > 6 then yo = 0 end
					p:SetAttribute('YO', yo)
					local sway = math.sin(t * 1.4 + ao) * 0.35
					local rx = math.cos(ao + sway * 0.2) * (ro + sway * 0.12)
					local rz = math.sin(ao + sway * 0.2) * (ro + sway * 0.12)
					local fade = yo / 6
					local h = (0.72 + fade * 0.1) % 1
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(rx, yo - 2, rz))
						p.Color = Color3.fromHSV(h, 0.7 + fade * 0.2, 0.5 + (1 - fade) * 0.4)
						p.Transparency = math.clamp(fade * 1.2, 0, 0.95)
						p.Size = Vector3.new(0.12 + (1 - fade) * 0.1, 0.45 + (1 - fade) * 0.2, 0.12 + (1 - fade) * 0.1)
					end)
				end
			end
			for _, p in nimExtra do
				local typ = p:GetAttribute('TYPE')
				if typ == 'fragment' then
					local ao = p:GetAttribute('AO')
					local rd = p:GetAttribute('RD')
					local yo = p:GetAttribute('YO')
					local sp = p:GetAttribute('SP')
					local angle = ao + t * sp * nimSpeed * 1.2
					local bob = math.sin(t * 2.5 + ao) * 0.4
					local h = (0.75 + t * 0.04 + ao * 0.02) % 1
					local pulse = 0.4 + math.abs(math.sin(t * 2 + ao)) * 0.4
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * rd, yo + bob, math.sin(angle) * rd)) * CFrame.Angles(t * sp * 3, t * sp * 2, math.sin(t + ao))
						p.Color = Color3.fromHSV(h, 0.6, pulse)
						p.Transparency = 0.1 + (1 - pulse) * 0.5
					end)
				elseif typ == 'deathring' then
					local rad = p:GetAttribute('RAD')
					rad = rad + dt * nimSpeed * 1.8
					if rad > 5 then rad = 0 end
					p:SetAttribute('RAD', rad)
					local fade = rad / 5
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(0, -2.2, 0))
						p.Size = Vector3.new(rad * 2, 0.05, rad * 2)
						p.Color = Color3.fromHSV(0.76, 0.8, 0.7)
						p.Transparency = math.clamp(fade, 0.05, 0.97)
					end)
				end
			end
		end,
		['snakers'] = function(t, dt, base, col)
			for _, p in nimParts do
				local typ = p:GetAttribute('TYPE')
				if typ == 'scale' then
					local i = p:GetAttribute('I')
					local total = p:GetAttribute('TOTAL')
					local progress = i / total
					local angle = progress * math.pi * 4 + t * nimSpeed * 0.8
					local helixRadius = 1.5 + math.sin(progress * math.pi) * 0.8
					local helixY = (progress - 0.5) * 6 + math.sin(t * 1.5 + progress * math.pi * 2) * 0.2
					local scaleX = math.cos(angle) * helixRadius
					local scaleZ = math.sin(angle) * helixRadius
					local fireH = math.clamp(0.02 + math.sin(t * 2 + progress * 4) * 0.04, 0, 0.12)
					local fireV = 0.8 + math.sin(t * 4 + i) * 0.2
					local pulse = 0.5 + math.sin(t * 3 + progress * math.pi * 2) * 0.3
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(scaleX, helixY, scaleZ)) * CFrame.Angles(0, angle + math.pi / 2, math.sin(t * 2 + progress) * 0.3)
						p.Color = Color3.fromHSV(fireH, 1, fireV)
						p.Size = Vector3.new(0.25 + pulse * 0.15, 0.14, 0.2 + pulse * 0.1)
						p.Transparency = math.clamp((1 - pulse) * 0.5, 0, 0.6)
					end)
				end
			end
			for _, p in nimExtra do
				local typ = p:GetAttribute('TYPE')
				if typ == 'breath' then
					local ao = p:GetAttribute('AO')
					local dist = p:GetAttribute('DIST')
					local spd = p:GetAttribute('SPD')
					local yo = p:GetAttribute('YO')
					dist = dist + dt * spd * nimSpeed
					if dist > 5.5 then
						dist = 0
						ao = math.random() * math.pi * 2
						yo = (math.random() - 0.5) * 3
						p:SetAttribute('AO', ao)
						p:SetAttribute('YO', yo)
					end
					p:SetAttribute('DIST', dist)
					local fade = dist / 5.5
					local sz = 0.12 + (1 - fade) * 0.12
					pcall(function()
						p.CFrame = CFrame.new(base + Vector3.new(math.cos(ao) * dist, yo, math.sin(ao) * dist))
						p.Color = Color3.fromHSV(0.02 + fade * 0.1, 1, 1)
						p.Size = Vector3.new(sz, sz, sz)
						p.Transparency = math.clamp(fade * 1.2, 0, 1)
					end)
				end
			end
		end,
	}
	
	local function applyAura()
		removeAura()
		local character = lplr.Character
		if not character then return end
		if not character:FindFirstChild('HumanoidRootPart') then return end

		nimFolder = Instance.new('Folder')
		nimFolder.Name = 'skidAura'
		nimFolder.Parent = workspace

		local setup = setups[nimStyle]
		if setup then setup(character) end

		local t = 0
		local conn = runService.RenderStepped:Connect(function(dt)
			if not Aura or not Aura.Enabled then return end
			t = t + dt

			local char = lplr.Character
			local hrp = char and char:FindFirstChild('HumanoidRootPart')
			if not hrp then return end
			local base = hrp.Position

			local baseColor
			if nimMode == 'Rainbow' then
				baseColor = Color3.fromHSV((t * 0.15) % 1, 1, 1)
			elseif nimMode == 'Pulse' then
				baseColor = Color3.fromHSV(nimH, nimS, 0.5 + math.abs(math.sin(t * 2)) * 0.5)
			else
				baseColor = Color3.fromHSV(nimH, nimS, nimV)
			end

			if nimHighlight then
				pcall(function()
					nimHighlight.OutlineColor = baseColor
					nimHighlight.FillColor = baseColor
				end)
			end

			local anim = animators[nimStyle]
			if anim then anim(t, dt, base, baseColor) end
		end)
		table.insert(nimConnections, conn)

		local charConn = character.AncestryChanged:Connect(function(_, parent)
			if not parent then removeAura() end
		end)
		table.insert(nimConnections, charConn)
	end

	local _auraCharConn
	_auraCharConn = lplr.CharacterAdded:Connect(function()
		if Aura and Aura.Enabled then
			task.wait(1)
			if Aura and Aura.Enabled then
				applyAura()
			end
		end
	end)

	Aura = vape.Categories.Render:CreateModule({
		Name = 'Aura',
		Tooltip = 'skid = aura !! i love this module',
		Function = function(callback)
			if callback then
				applyAura()
			else
				removeAura()
				if _auraCharConn then
					_auraCharConn:Disconnect()
					_auraCharConn = nil
				end
			end
		end
	})

	Aura:CreateDropdown({
		Name = 'Style',
		List = {'randomshi', 'Saiyan', 'Storm', 'Sakura', 'randomshi2', 'Seraph', 'randomshi3', 'snakers'},
		Default = 'randomshi',
		Function = function(val)
			nimStyle = val
			if nimOrbCountSlider then
				nimOrbCountSlider.Visible = (val == 'randomshi')
			end
			if Aura.Enabled then applyAura() end
		end
	})

	Aura:CreateColorSlider({
		Name = 'Color',
		Function = function(h, s, v)
			nimH, nimS, nimV = h, s, v
		end
	})

	Aura:CreateSlider({
		Name = 'Speed',
		Min = 0.5,
		Max = 5,
		Default = 1.5,
		Function = function(val)
			nimSpeed = val
		end
	})

	nimOrbCountSlider = Aura:CreateSlider({
		Name = 'Orb Count',
		Min = 3,
		Max = 20,
		Default = 8,
		Function = function(val)
			nimOrbCount = math.floor(val)
			if Aura.Enabled and nimStyle == 'randomshi' then applyAura() end
		end
	})
end)

run(function()
    local blockSelectorColor = Color3.fromRGB(255, 255, 255)
    local conn

    local BlockColor = vape.Categories.Render:CreateModule({
        Name = 'BlockSelectorColor',
        Tooltip = 'change your block placement outline color',
        Function = function(enabled)
            if enabled then
                local lastCheck = 0
                conn = workspace.DescendantAdded:Connect(function(v)
                    if not (v:IsA('SelectionBox') or v:IsA('Highlight')) then return end
                    local now = tick()
                    if now - lastCheck < 0.05 then return end
                    lastCheck = now
                    pcall(function()
                        v.Color3 = blockSelectorColor
                    end)
                end)
            else
                if conn then conn:Disconnect() conn = nil end
            end
        end
    })

    BlockColor:CreateColorSlider({
        Name = 'Color',
        Function = function(h, s, v)
            blockSelectorColor = Color3.fromHSV(h, s, v)
        end
    })
end)

run(function()
    local BlockSelectorColor
    local Fill
    local Outline
    local RunService = game:GetService("RunService")
    local updateConnection

    local function UpdateAllBoxes()
        local fillColor = Color3.fromHSV(Fill.Hue, Fill.Sat, Fill.Value)
        local outlineColor = Color3.fromHSV(Outline.Hue, Outline.Sat, Outline.Value)
        local fillTrans = 1 - Fill.Opacity
        local outlineTrans = 1 - Outline.Opacity
        for _, box in ipairs(workspace:GetDescendants()) do
            if box:IsA("SelectionBox") then
                box.Color3 = outlineColor
                box.Transparency = outlineTrans
                box.SurfaceColor3 = fillColor
                box.SurfaceTransparency = fillTrans
            end
        end
    end

    BlockSelectorColor = vape.Categories.Render:CreateModule({
        Name = 'BlockSelectorColor',
        Function = function(callback)
            if callback then
                updateConnection = RunService.RenderStepped:Connect(UpdateAllBoxes)
                BlockSelectorColor:Clean(workspace.ChildAdded:Connect(function(v)
                    local selector = v:FindFirstChild('SelectionBox') or v:WaitForChild('SelectionBox', 1)
                    if selector then
                        selector.Color3 = Color3.fromHSV(Outline.Hue, Outline.Sat, Outline.Value)
                        selector.Transparency = 1 - Outline.Opacity
                        selector.SurfaceColor3 = Color3.fromHSV(Fill.Hue, Fill.Sat, Fill.Value)
                        selector.SurfaceTransparency = 1 - Fill.Opacity
                    end
                end))
            else
                if updateConnection then
                    updateConnection:Disconnect()
                    updateConnection = nil
                end
            end
        end,
        Tooltip = 'change your block placement outline color'
    })

    Fill = BlockSelectorColor:CreateColorSlider({
        Name = 'Overlay Color',
        DefaultOpacity = 0.5
    })
    Outline = BlockSelectorColor:CreateColorSlider({
        Name = 'Outline Color',
        DefaultOpacity = 1
    })
end)

run(function()
    local trimType = 'trim_1'
    local trimColor = Color3.new(1,1,1)
    local trimCharConn
    local trimEnabled = false

    local function applyTrims()
        if not trimEnabled then return end
        lplr:SetAttribute('ArmorTrimType', trimType)
        lplr:SetAttribute('ArmorTrimColor', trimColor)
    end

    local ArmorTrims = vape.Categories.Render:CreateModule({
        Name = 'ArmorTrims',
        Tooltip = 'customize your armor trim (client sided) - must own a armor trim tho',
        Function = function(enabled)
            trimEnabled = enabled
            if enabled then
                applyTrims()
                trimCharConn = lplr.CharacterAdded:Connect(function()
                    task.wait(1)
                    applyTrims()
                end)
            else
                if trimCharConn then trimCharConn:Disconnect() trimCharConn = nil end
            end
        end
    })

    ArmorTrims:CreateDropdown({
        Name = 'Trim Type',
        List = {'trim_1','trim_2','trim_3','trim_4','trim_5','trim_6','trim_7','trim_8','trim_9','trim_10','trim_11','trim_12'},
        Default = 'trim_1',
        Function = function(val)
            trimType = val
            applyTrims()
        end
    })

    ArmorTrims:CreateColorSlider({
        Name = 'Trim Color',
		Function = function(h, s, v)
            trimColor = Color3.fromHSV(h, s, v)
            applyTrims()
        end
    })
end)

run(function()
    local ChatNameColor = vape.Categories.Render:CreateModule({
        Name = 'ChatNameColor',
        Tooltip = 'change your chat name color',
        Function = function(enabled) end
    })

    ChatNameColor:CreateColorSlider({
        Name = 'Color',
        Function = function(h, s, v)
			if not ChatNameColor.Enabled then return false end
            lplr:SetAttribute('ChatNameColor', Color3.fromHSV(h, s, v))
        end
    })
end)

run(function()
    local outlineColor = Color3.new(1, 1, 1)
    local outlines = {}
    local connections = {}

    local OutlineTargets

    local function shouldOutline(ent)
        if not OutlineTargets then return true end
        if ent.Player and not OutlineTargets.Players.Enabled then return false end
        if ent.NPC and not OutlineTargets.NPCs.Enabled then return false end
        return true
    end

    local function removeOutline(ent)
        if outlines[ent] then
            outlines[ent]:Destroy()
            outlines[ent] = nil
        end
    end

    local function addOutline(ent)
        if not shouldOutline(ent) then return end
        if outlines[ent] then return end
        local char = ent.Character
        if not char then return end
        local h = Instance.new('Highlight')
        h.OutlineColor = outlineColor
        h.FillTransparency = 1
        h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Adornee = char
        h.Parent = coreGui
        outlines[ent] = h
    end

    local function refreshAll()
        for ent in outlines do
            if not shouldOutline(ent) then removeOutline(ent) end
        end
        for _, ent in entitylib.List do
            addOutline(ent)
        end
    end

    local PlayerOutline = vape.Categories.Render:CreateModule({
        Name = 'PlayerOutline',
        Tooltip = 'adds outline to all players',
        Function = function(enabled)
            if enabled then
                for _, ent in entitylib.List do
                    addOutline(ent)
                end

                connections[1] = entitylib.Events.EntityAdded:Connect(function(ent)
                    task.wait(0.5)
                    if not PlayerOutline.Enabled then return end
                    addOutline(ent)
                end)

                connections[2] = entitylib.Events.EntityRemoved:Connect(removeOutline)
            else
                for _, c in connections do c:Disconnect() end
                table.clear(connections)
                for _, h in outlines do h:Destroy() end
                table.clear(outlines)
            end
        end
    })

    OutlineTargets = PlayerOutline:CreateTargets({
        Players = true,
        NPCs = true,
        Function = function()
            if PlayerOutline.Enabled then refreshAll() end
        end
    })

    PlayerOutline:CreateColorSlider({
        Name = 'Outline Color',
        Function = function(h, s, v)
            outlineColor = Color3.fromHSV(h, s, v)
            for _, outline in outlines do
                outline.OutlineColor = outlineColor
            end
        end
    })
end)

run(function()
    local AutoBuyBlocks
    local GUICheck
    local DelaySlider
    local running = false

    local function getShopNPC()
        local shopFound = false
        if entitylib.isAlive then
            local localPosition = entitylib.character.RootPart.Position
            for _, v in store.shop do
                if (v.RootPart.Position - localPosition).Magnitude <= 20 then
                    shopFound = true
                    break
                end
            end
        end
        return shopFound
    end

    AutoBuyBlocks = vape.Categories.Inventory:CreateModule({
        Name = "AutoBuyBlocks",
        Tooltip = "auto buy blocks",
        Function = function(enabled)
            running = enabled
            if enabled then
                task.spawn(function()
                    while running do
                        local canBuy = true
                        if GUICheck.Enabled then
                            if bedwars.AppController:isAppOpen('BedwarsItemShopApp') then
                                canBuy = true
                            else
                                canBuy = false
                            end
                        else
                            canBuy = getShopNPC()
                        end
                        if canBuy then
                            local args = {
                                {
                                    shopItem = {
                                        currency = "iron",
                                        itemType = "wool_white",
                                        amount = 16,
                                        price = 8,
                                        disabledInQueue = {"mine_wars"},
                                        category = "Blocks"
                                    },
                                    shopId = "1_item_shop"
                                }
                            }
                            pcall(function()
                                bedwars.Client:Get(remotes.BedwarsPurchaseItem).instance:InvokeServer(unpack(args))
                            end)
                        end
                        task.wait(DelaySlider.Value)
                    end
                end)
            end
        end
    })

    GUICheck = AutoBuyBlocks:CreateToggle({
        Name = "GUI Check",
        Default = false
    })

    DelaySlider = AutoBuyBlocks:CreateSlider({
        Name = "Delay",
        Min = 0,
        Max = 2,
        Default = 0.1,
        Decimal = 10,
    })
end)

run(function()
	local ProjectileAura
	local Targets
	local Range
	local List
	local rayCheck = RaycastParams.new()
	rayCheck.FilterType = Enum.RaycastFilterType.Include
	local projectileRemote = {InvokeServer = function() end}
	local FireDelays = {}
	task.spawn(function()
		projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
	end)
	
	local function getAmmo(check)
		for _, item in store.inventory.inventory.items do
			if check.ammoItemTypes and table.find(check.ammoItemTypes, item.itemType) then
				return item.itemType
			end
		end
	end
	
	local function getProjectiles()
		local items = {}
		for _, item in store.inventory.inventory.items do
			local proj = bedwars.ItemMeta[item.itemType].projectileSource
			local ammo = proj and getAmmo(proj)
			if ammo and table.find(List.ListEnabled, ammo) then
				table.insert(items, {
					item,
					ammo,
					proj.projectileType(ammo),
					proj
				})
			end
		end
		return items
	end
	
	ProjectileAura = vape.Categories.Blatant:CreateModule({
		Name = 'ProjectileAura',
		Function = function(callback)
			if callback then
				repeat
					if (workspace:GetServerTimeNow() - bedwars.SwordController.lastAttack) > 0.5 then
						local ent = entitylib.EntityPosition({
							Part = 'RootPart',
							Range = Range.Value,
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Wallcheck = Targets.Walls.Enabled
						})
	
						if ent then
							local pos = entitylib.character.RootPart.Position
							for _, data in getProjectiles() do
								local item, ammo, projectile, itemMeta = unpack(data)
								if (FireDelays[item.itemType] or 0) < tick() then
									rayCheck.FilterDescendantsInstances = {workspace.Map}
									local meta = bedwars.ProjectileMeta[projectile]
									local projSpeed, gravity = meta.launchVelocity, meta.gravitationalAcceleration or 196.2
									local calc = prediction.SolveTrajectory(pos, projSpeed, gravity, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, ent.Jumping and 42.6 or nil, rayCheck)
									if calc then
										targetinfo.Targets[ent] = tick() + 1
										local switched = switchItem(item.tool)
	
										task.spawn(function()
											local dir, id = CFrame.lookAt(pos, calc).LookVector, httpService:GenerateGUID(true)
											local shootPosition = (CFrame.new(pos, calc) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ))).Position
											bedwars.ProjectileController:createLocalProjectile(meta, ammo, projectile, shootPosition, id, dir * projSpeed, {drawDurationSeconds = 1})
											local res = PR:InvokeServer(item.tool, meta, shootPosition, dir * projSpeed)
											if not res then
												FireDelays[item.itemType] = tick()
											else
												local shoot = itemMeta.launchSound
												shoot = shoot and shoot[math.random(1, #shoot)] or nil
												if shoot then
													bedwars.SoundManager:playSound(shoot)
												end
											end
										end)
	
										FireDelays[item.itemType] = tick() + itemMeta.fireDelaySec
										if switched then
											task.wait(0.05)
										end
									end
								end
							end
						end
					end
					task.wait(0.1)
				until not ProjectileAura.Enabled
			end
		end,
		Tooltip = 'Shoots people around you'
	})
	Targets = ProjectileAura:CreateTargets({
		Players = true,
		Walls = true
	})
	List = ProjectileAura:CreateTextList({
		Name = 'Projectiles',
		Default = {'arrow', 'snowball'}
	})
	Range = ProjectileAura:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 50,
		Default = 50,
				Visible = true,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
    local AutoLani
    local PlayerDropdown
    local RefreshButton
    local DelaySlider
    local AutoBuyToggle
    local GUICheck
    local DelayBuySlider
    local LimitItems
	local HandCheck
    local TargetModeDropdown
    local HealthActivationToggle
    local HealthThresholdSlider
    local TeammateHealthToggle
    local TeammateHealthSlider
    local running = false
    local buyRunning = false
    local buyLoopThread = nil

    local function isHoldingScepter()
        if not entitylib.isAlive then return false end
        local inventory = store.inventory
        if inventory and inventory.inventory and inventory.inventory.hand then
            local handItem = inventory.inventory.hand
            if handItem and handItem.itemType == "scepter" then
                return true
            end
        end
        return false
    end

    local function isPlayerAlive(player)
        if not player or not player.Character then return false end
        local humanoid = player.Character:FindFirstChild("Humanoid")
        return humanoid and humanoid.Health > 0
    end

    local function isPlayerInVoid(player)
        if not player or not player.Character then return true end
        local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
        if rootPart then return rootPart.Position.Y < 0 end
        return true
    end

    local function getTargetPlayer()
        local myTeam = lplr:GetAttribute('Team')
        if not myTeam then return nil end
        local mode = TargetModeDropdown.Value

        if mode == "Specific Player" then
            local targetName = PlayerDropdown.Value
            if not targetName or targetName == "" then return nil end
            local targetPlayer = playersService:FindFirstChild(targetName)
            if targetPlayer and targetPlayer:GetAttribute('Team') == myTeam then
                if isPlayerAlive(targetPlayer) and not isPlayerInVoid(targetPlayer) then
                    return targetPlayer
                end
            end
            return nil

        elseif mode == "Lowest Health" then
            local lowestHealth = math.huge
            local lowestPlayer = nil
            for _, player in playersService:GetPlayers() do
                if player ~= lplr and player:GetAttribute('Team') == myTeam then
                    if isPlayerAlive(player) and not isPlayerInVoid(player) then
                        local hp = getPlayerHealthPercent(player)
                        if hp < lowestHealth and hp > 0 then
                            lowestHealth = hp
                            lowestPlayer = player
                        end
                    end
                end
            end
            return lowestPlayer

        elseif mode == "Closest" then
            if not entitylib.isAlive then return nil end
            local myPos = entitylib.character.RootPart.Position
            local closestDist = math.huge
            local closestPlayer = nil
            for _, player in playersService:GetPlayers() do
                if player ~= lplr and player:GetAttribute('Team') == myTeam then
                    if isPlayerAlive(player) and not isPlayerInVoid(player) then
                        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                            local dist = (player.Character.HumanoidRootPart.Position - myPos).Magnitude
                            if dist < closestDist then
                                closestDist = dist
                                closestPlayer = player
                            end
                        end
                    end
                end
            end
            return closestPlayer

        elseif mode == "Furthest" then
            if not entitylib.isAlive then return nil end
            local myPos = entitylib.character.RootPart.Position
            local furthestDist = 0
            local furthestPlayer = nil
            for _, player in playersService:GetPlayers() do
                if player ~= lplr and player:GetAttribute('Team') == myTeam then
                    if isPlayerAlive(player) and not isPlayerInVoid(player) then
                        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                            local dist = (player.Character.HumanoidRootPart.Position - myPos).Magnitude
                            if dist > furthestDist then
                                furthestDist = dist
                                furthestPlayer = player
                            end
                        end
                    end
                end
            end
            return furthestPlayer

        elseif mode == "Random" then
            local valid = {}
            for _, player in playersService:GetPlayers() do
                if player ~= lplr and player:GetAttribute('Team') == myTeam then
                    if isPlayerAlive(player) and not isPlayerInVoid(player) then
                        table.insert(valid, player)
                    end
                end
            end
            if #valid > 0 then return valid[math.random(1, #valid)] end
            return nil
        end

        return nil
    end

    local function shouldActivateByHealth()
        if not HealthActivationToggle.Enabled then return true end
        if not entitylib.isAlive then return false end
        local myHp = getPlayerHealthPercent(lplr)
        if myHp <= HealthThresholdSlider.Value then return true end
        if TeammateHealthToggle.Enabled then
            local target = getTargetPlayer()
            if target then
                local targetHp = getPlayerHealthPercent(target)
                if targetHp <= TeammateHealthSlider.Value then return true end
            end
        end
        return false
    end

    local function buyScepter()
        pcall(function()
            bedwars.Client:Get(remotes.BedwarsPurchaseItem).instance:InvokeServer({
                shopItem = {
                    currency = "iron",
                    itemType = "scepter",
                    amount = 1,
                    price = 45,
                    category = "Combat",
                    requiresKit = {"paladin"},
                    lockAfterPurchase = true
                },
                shopId = "1_item_shop"
            })
        end)
    end

    local function startBuyLoop()
        if buyLoopThread then
            task.cancel(buyLoopThread)
            buyLoopThread = nil
        end
        buyRunning = true
        buyLoopThread = task.spawn(function()
            while buyRunning and AutoBuyToggle.Enabled and AutoLani.Enabled do
                local canBuy = GUICheck.Enabled
                    and bedwars.AppController:isAppOpen('BedwarsItemShopApp')
                    or (not GUICheck.Enabled and getShopNPC())
                if canBuy then
                    buyScepter()
                end
                task.wait(DelayBuySlider.Value)
            end
            buyLoopThread = nil
        end)
    end

    local function stopBuyLoop()
        buyRunning = false
        if buyLoopThread then
            task.cancel(buyLoopThread)
            buyLoopThread = nil
        end
    end

    AutoLani = vape.Categories.Kits:CreateModule({
        Name = "AutoLani",
        Function = function(callback)
            running = callback
            if callback then
                task.spawn(function()
                    AutoLani:Clean(lplr:GetAttributeChangedSignal("PaladinStartTime"):Connect(function()
                        if not running then return end
                        if not shouldActivateByHealth() then return end
                        if LimitItems.Enabled and not isHoldingScepter() then
                            notif("AutoLani", "bru u aint even holding the scepter", 3)
                            return
                        end

                        pcall(function()
                            local handItem = store.inventory and store.inventory.inventory and store.inventory.inventory.hand
                            if handItem then
                                bedwars.Client:Get(remotes.ConsumeItem).instance:InvokeServer({ item = handItem.tool })
                            end
                        end)

                        task.wait(DelaySlider.Value)

                        if bedwars.AbilityController:canUseAbility('PALADIN_ABILITY') then
                            local targetPlayer = getTargetPlayer()
                            if targetPlayer and targetPlayer.Character then
                                bedwars.Client:Get(remotes.PaladinAbilityRequest):SendToServer({ target = targetPlayer })
                                notif("AutoLani", "tp'd to " .. targetPlayer.Name .. " don't die lol", 2)
                            else
                                bedwars.Client:Get(remotes.PaladinAbilityRequest):SendToServer({})
                                notif("AutoLani", "used ability on self fr fr", 2)
                            end
                            task.wait(0.022)
                            bedwars.AbilityController:useAbility('PALADIN_ABILITY')
                        else
                            notif("AutoLani", "ability on cooldown rn", 2)
                        end
                    end))
                end)

                if AutoBuyToggle.Enabled then startBuyLoop() end

                AutoLani:Clean(playersService.PlayerAdded:Connect(function()
                    task.wait(0.5)
                    if PlayerDropdown and type(PlayerDropdown.SetList) == 'function' then PlayerDropdown:SetList(getTeammates(true)) end
                end))
                AutoLani:Clean(playersService.PlayerRemoving:Connect(function()
                    task.wait(0.5)
                    if PlayerDropdown and type(PlayerDropdown.SetList) == 'function' then PlayerDropdown:SetList(getTeammates(true)) end
                end))
                AutoLani:Clean(lplr:GetAttributeChangedSignal('Team'):Connect(function()
                    task.wait(1)
                    if PlayerDropdown and type(PlayerDropdown.SetList) == 'function' then PlayerDropdown:SetList(getTeammates(true)) end
                end))
            else
                running = false
                stopBuyLoop()
            end
        end,
        Tooltip = "auto tp to teammates w paladin scepter"
    })

    TargetModeDropdown = AutoLani:CreateDropdown({
        Name = "Target Mode",
        List = {"Specific Player", "Lowest Health", "Closest", "Furthest", "Random"},
        Default = "Specific Player",
        Function = function(val)
            if PlayerDropdown then
                PlayerDropdown.Object.Visible = (val == "Specific Player")
            end
        end,
        Tooltip = "who to tp to"
    })

    local function teammateListWithNone()
        local list = {"None"}
        for _, name in ipairs(getTeammates(true)) do
            table.insert(list, name)
        end
        return list
    end

    PlayerDropdown = AutoLani:CreateDropdown({
        Name = "Teammate",
        List = teammateListWithNone(),
        Tooltip = "pick ur teammate"
    })

    RefreshButton = AutoLani:CreateButton({
        Name = "Refresh Teammates",
        Function = function()
            task.spawn(function()
                local newNames = getTeammates(true)
                local newList = {"None"}
                for _, name in ipairs(newNames) do
                    table.insert(newList, name)
                end
                if PlayerDropdown then
                    pcall(function()
                        PlayerDropdown:Change(newList)
                        if #newList > 1 then
                            if not PlayerDropdown.Value or PlayerDropdown.Value == "" or not table.find(newList, PlayerDropdown.Value) then
                                PlayerDropdown:SetValue(newList[2] or "None")
                            else
                                PlayerDropdown:SetValue(PlayerDropdown.Value)
                            end
                        end
                    end)
                end
                notif("AutoLani", #newList > 0 and "refreshed, got " .. #newList .. " teammates" or "no teammates found", 2)
            end)
        end,
        Tooltip = "refresh the teammate list"
    })

    DelaySlider = AutoLani:CreateSlider({
        Name = "Teleport Delay",
        Min = 0,
        Max = 2,
        Default = 0.5,
        Decimal = 10,
        Suffix = "s",
        Tooltip = "delay before tping"
    })

    LimitItems = AutoLani:CreateToggle({
        Name = "Limit to Scepter",
        Default = true,
        Tooltip = "only tp when u holdin the scepter"
    })

    HealthActivationToggle = AutoLani:CreateToggle({
        Name = "Health Activation",
        Default = false,
        Function = function(val)
            if HealthThresholdSlider then HealthThresholdSlider.Object.Visible = val end
            if TeammateHealthToggle then TeammateHealthToggle.Object.Visible = val end

            if not val then
                if TeammateHealthSlider and TeammateHealthSlider.Object then
                    TeammateHealthSlider.Object.Visible = false
                end
            else
                if TeammateHealthToggle and TeammateHealthToggle.Enabled then
                    if TeammateHealthSlider and TeammateHealthSlider.Object then
                        TeammateHealthSlider.Object.Visible = true
                    end
                end
            end
        end,
        Tooltip = "only use ability based on hp"
    })

    HealthThresholdSlider = AutoLani:CreateSlider({
        Name = "Self Health %",
        Min = 1,
        Max = 100,
        Default = 50,
        Suffix = "%",
        Tooltip = "use ability when ur hp is below this",
        Visible = false
    })

    TeammateHealthToggle = AutoLani:CreateToggle({
        Name = "Teammate Health Check",
        Default = false,
        Function = function(val)
            if TeammateHealthSlider then TeammateHealthSlider.Object.Visible = val end
        end,
        Tooltip = "also check teammate hp",
        Visible = false
    })

    TeammateHealthSlider = AutoLani:CreateSlider({
        Name = "Teammate Health %",
        Min = 1,
        Max = 100,
        Default = 30,
        Suffix = "%",
        Tooltip = "use ability when teammate hp is below this",
        Visible = false
    })

    AutoBuyToggle = AutoLani:CreateToggle({
        Name = "Auto Buy Scepter",
        Default = false,
        Function = function(val)
            if GUICheck then GUICheck.Object.Visible = val end
            if DelayBuySlider then DelayBuySlider.Object.Visible = val end
            if val and AutoLani.Enabled then
                startBuyLoop()
            else
                stopBuyLoop()
            end
        end,
        Tooltip = "auto cop scepters from shop"
    })

    GUICheck = AutoLani:CreateToggle({
        Name = "GUI Check",
        Default = false,
        Tooltip = "only buy when shop is open",
        Visible = false
    })

    DelayBuySlider = AutoLani:CreateSlider({
        Name = "Buy Delay",
        Min = 0.1,
        Max = 2,
        Default = 0.3,
        Decimal = 10,
        Suffix = "s",
        Tooltip = "delay between buys",
        Visible = false
    })

    task.defer(function()
        if PlayerDropdown and PlayerDropdown.Object then
            PlayerDropdown.Object.Visible = true
        end
        if HealthThresholdSlider and HealthThresholdSlider.Object then
            HealthThresholdSlider.Object.Visible = false
        end
        if TeammateHealthToggle and TeammateHealthToggle.Object then
            TeammateHealthToggle.Object.Visible = false
        end
        if TeammateHealthSlider and TeammateHealthSlider.Object then
            TeammateHealthSlider.Object.Visible = false
        end
        if GUICheck and GUICheck.Object then GUICheck.Object.Visible = false end
        if DelayBuySlider and DelayBuySlider.Object then DelayBuySlider.Object.Visible = false end
    end)
end)

run(function()
	local KnitInit, Knit
	repeat
		KnitInit, Knit = pcall(function()
			return debug.getupvalue(require(lplr.PlayerScripts.TS.knit).setup, 9)
		end)
		if KnitInit then break end
		task.wait()
	until KnitInit

	if not debug.getupvalue(Knit.Start, 1) then
		repeat task.wait() until debug.getupvalue(Knit.Start, 1)
	end

	local Players = game:GetService("Players")

	shared.PERMISSION_CONTROLLER_HASANYPERMISSIONS_REVERT = shared.PERMISSION_CONTROLLER_HASANYPERMISSIONS_REVERT or Knit.Controllers.PermissionController.hasAnyPermissions
	shared.MATCH_CONTROLLER_GETPLAYERPARTY_REVERT = shared.MATCH_CONTROLLER_GETPLAYERPARTY_REVERT or Knit.Controllers.MatchController.getPlayerParty

	local AC_MOD_View = {
		playerConnections = {},
		Enabled = false,
		Friends = {}, 
		parties = {}, 
		teamMap = {}, 
		display = {},
		isRefreshing = false,
		cacheDirty = true,
		disable_disguises = false,
		disguises = {},
		teamData = {}
	}

	AC_MOD_View.controller = Knit.Controllers.PermissionController
	AC_MOD_View.match_controller = Knit.Controllers.MatchController

	function AC_MOD_View:getPartyById(displayId)
		if not displayId then return end
		displayId = tostring(displayId)
		if self.display[displayId] then return self.display[displayId] end
		for _, party in pairs(self.parties) do
			if party.displayId == tostring(displayId) then
				self.display[displayId] = party
				return party
			end
		end
	end

	function AC_MOD_View:refreshDisplayCache()
		for _, plr in pairs(Players:GetPlayers()) do
			local playerId = tostring(plr.UserId)

			local playerPartyId = self.teamMap[playerId]
			if playerPartyId ~= nil then
				self:getPartyById(playerPartyId)
			end
			task.wait()
		end
	end

	function AC_MOD_View:refreshDisplayCacheAsync()
		task.spawn(self.refreshDisplayCache, self)
	end

	function AC_MOD_View:getPlayerTeamData(plr)
		if self.teamData[plr] then return self.teamData[plr] end

		self.teamData[plr] = {}

		local teamMembers = {}
		local playerTeam = plr.Team 
		if not playerTeam then
			return teamMembers 
		end

		local playerId = tostring(plr.UserId)
		self.Friends[playerId] = self.Friends[playerId] or {}

		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer == plr then continue end 

			local otherPlayerId = tostring(otherPlayer.UserId)
			local areFriends = self.Friends[playerId][otherPlayerId]

			if areFriends == nil then
				local suc, res = pcall(function()
					return plr:IsFriendsWith(otherPlayer.UserId)
				end)
				areFriends = suc and res or false

				if suc then
					self.Friends = self.Friends or {}
					self.Friends[playerId] = self.Friends[playerId] or {}
					self.Friends[playerId][otherPlayerId] = areFriends
					self.Friends[otherPlayerId] = self.Friends[otherPlayerId] or {}
					self.Friends[otherPlayerId][playerId] = areFriends
				end
			end

			if areFriends and otherPlayer.Team == playerTeam then
				table.insert(teamMembers, otherPlayerId)
			end
		end

		self.teamData[plr] = teamMembers

		return teamMembers
	end

	function AC_MOD_View:refreshPlayerTeamData()
		for i,v in pairs(Players:GetPlayers()) do
			self:getPlayerTeamData(v)
			task.wait()
		end
	end

	function AC_MOD_View:refreshPlayerTeamDataAsync()
		task.spawn(self.refreshPlayerTeamData, self)
	end

	function AC_MOD_View:refreshTeamMap()
		local allTeams = {}
		for _, p in pairs(Players:GetPlayers()) do
			local teamMembers = self:getPlayerTeamData(p)
			if teamMembers and #teamMembers > 0 then 
				allTeams[p] = teamMembers
			end
		end

		local validTeams = {}
		for playerInTeams, members in pairs(allTeams) do
			local playerIdInTeams = tostring(playerInTeams.UserId)
			local cleanedMembers = {}

			for _, memberId in pairs(members) do
				local memberIdStr = tostring(memberId)
				if memberIdStr == playerIdInTeams then
					--print("Warning: Player " .. playerIdInTeams .. " has themselves in their team list.")
				else
					table.insert(cleanedMembers, memberIdStr)
				end
			end

			if #cleanedMembers > 0 then
				validTeams[playerInTeams] = cleanedMembers
			end
		end

		self.parties = {}
		self.teamMap = {}
		local teamId = 0
		for playerInTeams, members in pairs(validTeams) do
			local playerIdInTeams = tostring(playerInTeams.UserId)
			if not self.teamMap[playerIdInTeams] then
				self.teamMap[playerIdInTeams] = teamId
				table.insert(self.parties, {
					displayId = tostring(teamId),
					members = members
				})
				teamId = teamId + 1

				for _, memberId in pairs(members) do
					self.teamMap[memberId] = teamId - 1
				end
			end
		end

		self.cacheDirty = false
		self.isRefreshing = false
	end

	function AC_MOD_View:refreshTeamMapAsync()
		if self.isRefreshing then return end 
		self.isRefreshing = true
		task.spawn(function()
			self:refreshTeamMap()
		end)
	end

	function AC_MOD_View:getPlayerParty(plr)
		if not plr or not plr:IsA("Player") then
			return nil
		end

		local playerId = tostring(plr.UserId)

		if self.cacheDirty or not next(self.teamMap) then
			self:refreshTeamMapAsync()
		end

		local playerPartyId = self.teamMap[playerId]
		if playerPartyId ~= nil then
			return self:getPartyById(playerPartyId)
		end

		return nil 
	end

	AC_MOD_View.mockGetPlayerParty = function(self, plr)
		local parties = self.parties 
		if parties ~= nil and #parties > 0 then
			return shared.MATCH_CONTROLLER_GETPLAYERPARTY_REVERT(self, plr)
		end
		return AC_MOD_View:getPlayerParty(plr)
	end

	function AC_MOD_View:toggleDisableDisguises()
		if not self.Enabled then return end
		if self.disable_disguises then
			for _,v in pairs(Players:GetPlayers()) do
				if v == Players.LocalPlayer then continue end
				local disguiseName = v:GetAttribute("DisguiseDisplayName")
				if disguiseName and disguiseName ~= "" then
					self.disguises[v] = disguiseName
					v:SetAttribute("DisguiseDisplayName", "")
					notif("Remove Disguises", "Disabled streamer mode for "..tostring(v.Name).."!", 3)
				end
			end
			pcall(function() Knit.Controllers.StreamerModeController:updateNametags(true) end)
		else
			for v, originalName in pairs(self.disguises) do
				if v and v.Parent then
					v:SetAttribute("DisguiseDisplayName", originalName)
					notif("Remove Disguises", "Re-enabled Streamer mode for "..tostring(v.Name).."!", 2)
				end
			end
			table.clear(self.disguises)
			pcall(function() Knit.Controllers.StreamerModeController:updateNametags(true) end)
		end
	end

	function AC_MOD_View:refreshCore()
		self:refreshTeamMapAsync()
		self:refreshDisplayCacheAsync()
		self:refreshPlayerTeamDataAsync()

		self:toggleDisableDisguises()
	end

	function AC_MOD_View:refreshCoreAsync()
		task.spawn(self.refreshCore, self)
	end

	function AC_MOD_View:init()
		self.Enabled = true
		self.controller.hasAnyPermissions = function(self)
			return true
		end
		self.match_controller.getPlayerParty = self.mockGetPlayerParty

		self.playerConnections = {
			added = Players.PlayerAdded:Connect(function(player)
				self.cacheDirty = true
				self:refreshCoreAsync()
				player:GetPropertyChangedSignal("Team"):Connect(function()
					self.cacheDirty = true
					self:refreshCoreAsync()
				end)
			end),
			removed = Players.PlayerRemoving:Connect(function(player)
				local playerId = tostring(player.UserId)
				self.Friends[playerId] = nil 
				for _, cache in pairs(self.Friends) do
					cache[playerId] = nil
				end
				self.cacheDirty = true
				self:refreshCoreAsync()
			end)
		}

		self:refreshCore()
	end

	function AC_MOD_View:disable()
		self.Enabled = false

		self.controller.hasAnyPermissions = shared.PERMISSION_CONTROLLER_HASANYPERMISSIONS_REVERT
		self.match_controller.getPlayerParty = shared.MATCH_CONTROLLER_GETPLAYERPARTY_REVERT

		if self.playerConnections then
			for _, v in pairs(self.playerConnections) do
				pcall(function() v:Disconnect() end)
			end
			table.clear(self.playerConnections)
		end

		self.parties = {}
		self.teamMap = {}
		self.Friends = {}
		self.display = {}
		self.teamData = {}
		self.cacheDirty = true

		self:toggleDisableDisguises()
	end

	shared.ACMODVIEWENABLED = false
	AC_MOD_View.moduleInstance = vape.Categories.World:CreateModule({
		Name = "ACMODView",
		Function = function(call)
			shared.ACMODVIEWENABLED = call
			if call then
				AC_MOD_View:init()
			else
				AC_MOD_View:disable()
			end
		end
	})

	AC_MOD_View.disableDisguisesToggle = AC_MOD_View.moduleInstance:CreateToggle({
		Name = "Remove Disguises",
		Function = function(call)
			AC_MOD_View.disable_disguises = call
			AC_MOD_View:toggleDisableDisguises()
		end,
		Default = true
	})
end)

run(function()
    local InvisibleCursor = {}
    local isActive = false
    local renderConnection
    local ViewMode = {Value = 'First Person'}
    local LimitToItems = {Enabled = false}
    local ShowOnGUI = {Enabled = false}
    local lastCursorState = nil
    
    local function hasBowEquipped()
        if not store.hand or not store.hand.tool then
            return false
        end
        
        local toolName = store.hand.tool.Name:lower()
        return toolName:find('bow') ~= nil or toolName:find('crossbow') ~= nil
    end
    
    local function shouldHideCursor()
        if not isActive then return false end
        
        if ShowOnGUI.Enabled and isGUIOpen() then
            return false
        end
        
        if LimitToItems.Enabled and not hasBowEquipped() then
            return false
        end
        
        local inFirstPerson = isFirstPerson()
    
        if ViewMode.Value == 'First Person' then
            return inFirstPerson
        elseif ViewMode.Value == 'Third Person' then
            return not inFirstPerson
        elseif ViewMode.Value == 'Both' then
            return true
        end
        
        return false
    end
    
    local function updateCursor()
        local shouldHide = shouldHideCursor()
        
        if lastCursorState == shouldHide then
            return 
        end
        
        lastCursorState = shouldHide
        inputService.MouseIconEnabled = not shouldHide
    end
    
    InvisibleCursor = vape.Categories.Utility:CreateModule({
        Name = 'InvisibleCursor',
        Function = function(callback)
            if callback then
                isActive = true
                lastCursorState = nil
                
                if renderConnection then
                    renderConnection:Disconnect()
                end
                
                renderConnection = runService.RenderStepped:Connect(updateCursor)
                
                InvisibleCursor:Clean(vapeEvents.InventoryChanged.Event:Connect(updateCursor))
            else
                isActive = false
                
                if renderConnection then
                    renderConnection:Disconnect()
                    renderConnection = nil
                end
                
                inputService.MouseIconEnabled = true
                lastCursorState = nil
            end
        end,
    })
    
    ViewMode = InvisibleCursor:CreateDropdown({
        Name = 'View Mode',
        List = {'First Person', 'Third Person', 'Both'},
        Default = 'First Person',
        Function = function(val)
            ViewMode.Value = val
            updateCursor()
        end
    })
    
    LimitToItems = InvisibleCursor:CreateToggle({
        Name = 'Limit to Bow',
        Default = false,
        Function = function(val)
            LimitToItems.Enabled = val
            updateCursor()
        end
    })
    
    ShowOnGUI = InvisibleCursor:CreateToggle({
        Name = 'Show on GUI',
        Default = false,
        Function = function(val)
            ShowOnGUI.Enabled = val
            updateCursor()
        end
    })
end)

run(function()
    local LegacyAnimation
    local enabled = false
    local renderConnection = nil
    local lastSetValue = nil
    local CameraMode = { Value = 'Both' }

    local function ensureAttribute()
        local workspace = game:GetService("Workspace")
        if workspace:GetAttribute("RbxLegacyAnimationBlending") == nil then
            workspace:SetAttribute("RbxLegacyAnimationBlending", false)
        end
    end

    local function setLegacyAnimation(value)
        local workspace = game:GetService("Workspace")
        ensureAttribute()
        if lastSetValue ~= value then
            workspace:SetAttribute("RbxLegacyAnimationBlending", value)
            lastSetValue = value
        end
    end

    local function updateLegacyAnimation()
        if not enabled then
            setLegacyAnimation(false)
            return
        end

        local mode = 'Both'
        if CameraMode and CameraMode.Value then
            mode = CameraMode.Value
        end

        local inFirstPerson = isFirstPerson()

        local shouldEnable = false
        if mode == "Both" then
            shouldEnable = true
        elseif mode == "First Person" then
            shouldEnable = inFirstPerson
        elseif mode == "Third Person" then
            shouldEnable = not inFirstPerson
        end

        setLegacyAnimation(shouldEnable)
    end

    LegacyAnimation = vape.Categories.Render:CreateModule({
        Name = 'LegacyAnimation',
        Function = function(callback)
            enabled = callback

            if enabled then
                if not renderConnection then
                    renderConnection = game:GetService("RunService").RenderStepped:Connect(updateLegacyAnimation)
                end
                updateLegacyAnimation()
            else
                if renderConnection then
                    renderConnection:Disconnect()
                    renderConnection = nil
                end
                setLegacyAnimation(false)
            end
        end,
        Tooltip = 'turns on Roblox legacy animation blending'
    })

    CameraMode = LegacyAnimation:CreateDropdown({
        Name = 'Camera Mode',
        List = {'Both', 'First Person', 'Third Person'},
        Default = 'Both',
        Function = function(val)
            CameraMode.Value = val
            updateLegacyAnimation() 
        end
    })
end)

run(function()
	local RemovePlayerLevel
	
	local function removePlayerLevels(gui)
		for _, descendant in gui:GetDescendants() do
			if descendant:IsA("TextLabel") and descendant.Name == "PlayerLevel" then
				descendant:Destroy()
			end
		end
	end
	
	RemovePlayerLevel = vape.Categories.Render:CreateModule({
		Name = 'RemovePlayerLevelUI',
		Function = function(callback)
			if callback then
				local existingTabList = lplr.PlayerGui:FindFirstChild("TabListScreenGui")
				if existingTabList then
					removePlayerLevels(existingTabList)
				end
				
				RemovePlayerLevel:Clean(lplr.PlayerGui.ChildAdded:Connect(function(gui)
					if gui.Name == "TabListScreenGui" then
						removePlayerLevels(gui)
						
						RemovePlayerLevel:Clean(gui.DescendantAdded:Connect(function(descendant)
							if descendant:IsA("TextLabel") and descendant.Name == "PlayerLevel" then
								descendant:Destroy()
							end
						end))
					end
				end))
				
			end
		end,
		Tooltip = 'Removes player levels from the TabList'
	})
end)

run(function()
	local OG4v4v4v4
	local OldMaterials = {}
	local OldColors = {}
	local oldTexture = {}
	local oldColor = {}
	local deletedNumTeamMembers = {} 
	
	local worldFolder = getWorldFolder()
	if not worldFolder then return end
	local blocks = worldFolder:WaitForChild("Blocks")
	
	local function isValidWoolBlock(obj)
		if not obj:IsA("BasePart") then
			return false
		end
		if obj.Name ~= "wool_orange" and obj.Name ~= "wool_pink" then
			return false
		end
		local parent = obj.Parent
		if parent then
			if parent.Name == "Viewmodel" or parent.Parent and parent.Parent.Name == "Viewmodel" then
				return false
			end
			
			if parent:IsA("Accessory") or parent:IsA("Tool") then
				return false
			end
			
			local ancestor = parent
			while ancestor do
				if ancestor:IsA("Model") and playersService:GetPlayerFromCharacter(ancestor) then
					return false
				end
				ancestor = ancestor.Parent
			end
		end
		
		return true
	end
	
	local function removeNumTeamMembers(gui)
		if not gui then return end
		
		local topBarApp = gui:FindFirstChild("TopBarApp")
		if not topBarApp then return end
		
		local frame5 = topBarApp:FindFirstChild("5")
		if not frame5 then return end
		
		local frame4 = frame5:FindFirstChild("4")
		if not frame4 then return end
		
		for _, frameName in pairs({"2", "3", "4", "5"}) do
			local targetFrame = frame4:FindFirstChild(frameName)
			if targetFrame and targetFrame:IsA("Frame") then
				local numLabel = targetFrame:FindFirstChild("NumTeamMembers")
				if numLabel and numLabel:IsA("TextLabel") then
					deletedNumTeamMembers[numLabel] = {
						Parent = numLabel.Parent,
						Name = numLabel.Name,
						Text = numLabel.Text,
						Position = numLabel.Position,
						Size = numLabel.Size,
						Visible = numLabel.Visible
					}
					numLabel:Destroy()
				end
			end
		end
	end
	
	local function restoreNumTeamMembers()
		for label, data in pairs(deletedNumTeamMembers) do
			if data.Parent and data.Parent.Parent then
				local newLabel = Instance.new("TextLabel")
				newLabel.Name = data.Name
				newLabel.Text = data.Text
				newLabel.Position = data.Position
				newLabel.Size = data.Size
				newLabel.Visible = data.Visible
				newLabel.Parent = data.Parent
			end
		end
		table.clear(deletedNumTeamMembers)
	end
	
	OG4v4v4v4 = vape.Categories.Render:CreateModule({
		Name = 'OG4v4v4v4',
		Function = function(callback)
			if callback then
				local OrangeMaterial = Instance.new('MaterialVariant')
				OrangeMaterial.Parent = cloneref(game:GetService('MaterialService'))
				OrangeMaterial.Name = 'rbxassetid://16991768606_red'
				OrangeMaterial.ColorMap = 'rbxassetid://16991768606'
				OrangeMaterial.StudsPerTile = 3
				OrangeMaterial.RoughnessMap = 'rbxassetid://16991768606'
				OrangeMaterial.BaseMaterial = 'Fabric'
				
				local PinkMaterial = Instance.new('MaterialVariant')
				PinkMaterial.Parent = cloneref(game:GetService('MaterialService'))
				PinkMaterial.Name = 'rbxassetid://16991768606_green'
				PinkMaterial.ColorMap = 'rbxassetid://16991768606'
				PinkMaterial.StudsPerTile = 3
				PinkMaterial.RoughnessMap = 'rbxassetid://16991768606'
				PinkMaterial.BaseMaterial = 'Fabric'
				
				local topBarGui = lplr.PlayerGui:FindFirstChild('TopBarAppGui')
				if topBarGui then
					removeNumTeamMembers(topBarGui)
				end
				
				OG4v4v4v4:Clean(lplr.PlayerGui.ChildAdded:Connect(function(gui)
					if gui.Name == "TopBarAppGui" then
						removeNumTeamMembers(gui)
						
						OG4v4v4v4:Clean(gui.DescendantAdded:Connect(function(descendant)
							if descendant:IsA("Frame") and 
							   (descendant.Name == "2" or descendant.Name == "3" or 
							    descendant.Name == "4" or descendant.Name == "5") then
								local frame4 = descendant.Parent
								if frame4 and frame4.Name == "4" then
									local frame5 = frame4.Parent
									if frame5 and frame5.Name == "5" then
										local topBarApp = frame5.Parent
										if topBarApp and topBarApp.Name == "TopBarApp" then
											task.wait(0.1) 
											local numLabel = descendant:FindFirstChild("NumTeamMembers")
											if numLabel and numLabel:IsA("TextLabel") then
												deletedNumTeamMembers[numLabel] = {
													Parent = numLabel.Parent,
													Name = numLabel.Name,
													Text = numLabel.Text,
													Position = numLabel.Position,
													Size = numLabel.Size,
													Visible = numLabel.Visible
												}
												numLabel:Destroy()
											end
										end
									end
								end
							end
						end))
					end
				end))
				
				local viewmodel = gameCamera:FindFirstChild("Viewmodel")
				if viewmodel then
					OG4v4v4v4:Clean(viewmodel.ChildAdded:Connect(function(obj)
						if obj.Name == "wool_orange" then
							task.wait(0.01)
							if obj:FindFirstChild('Handle') then
								for i, texture in obj:FindFirstChild('Handle'):GetChildren() do
									if texture:IsA('Texture') then
										oldTexture[texture] = texture.Texture
										oldColor[texture] = texture.Color3
										texture.Texture = "rbxassetid://16991768606"
										texture.Color3 = Color3.fromRGB(196, 40, 28)
									end
								end
							end
						elseif obj.Name == "wool_pink" then
							task.wait(0.01)
							if obj:FindFirstChild('Handle') then
								for i, texture in obj:FindFirstChild('Handle'):GetChildren() do
									if texture:IsA('Texture') then
										oldTexture[texture] = texture.Texture
										oldColor[texture] = texture.Color3
										texture.Texture = "rbxassetid://16991768606"
										texture.Color3 = Color3.fromRGB(15, 185, 55)
									end
								end
							end
						end
					end))
				end
				
				OG4v4v4v4:Clean(lplr.Character.ChildAdded:Connect(function(obj)
					if obj.Name == "wool_orange" then
						task.wait(0.01)
						if obj:FindFirstChild('Handle') then
							for i, texture in obj:FindFirstChild('Handle'):GetChildren() do
								if texture:IsA('Texture') then
									oldTexture[texture] = texture.Texture
									oldColor[texture] = texture.Color3
									texture.Texture = "rbxassetid://16991768606"
									texture.Color3 = Color3.fromRGB(196, 40, 28)
								end
							end
						end
					elseif obj.Name == "wool_pink" then
						task.wait(0.01)
						if obj:FindFirstChild('Handle') then
							for i, texture in obj:FindFirstChild('Handle'):GetChildren() do
								if texture:IsA('Texture') then
									oldTexture[texture] = texture.Texture
									oldColor[texture] = texture.Color3
									texture.Texture = "rbxassetid://16991768606"
									texture.Color3 = Color3.fromRGB(15, 185, 55)
								end
							end
						end
					end
				end))
				
				OG4v4v4v4:Clean(blocks.ChildAdded:Connect(function(obj)
					if obj.Name == "wool_orange" and isValidWoolBlock(obj) then
						OldMaterials[obj] = obj.MaterialVariant
						OldColors[obj] = obj.Color
						obj.MaterialVariant = 'rbxassetid://16991768606_red'
						obj.Color = Color3.fromRGB(196, 40, 28)
					elseif obj.Name == "wool_pink" and isValidWoolBlock(obj) then
						OldMaterials[obj] = obj.MaterialVariant
						OldColors[obj] = obj.Color
						obj.MaterialVariant = 'rbxassetid://16991768606_green'
						obj.Color = Color3.fromRGB(15, 185, 55)
					end
				end))
				
				OG4v4v4v4:Clean(workspace.ChildAdded:Connect(function(obj)
					if obj.Name == "wool_orange" and isValidWoolBlock(obj) then
						OldMaterials[obj] = obj.MaterialVariant
						OldColors[obj] = obj.Color
						obj.MaterialVariant = 'rbxassetid://16991768606_red'
						obj.Color = Color3.fromRGB(196, 40, 28)
					elseif obj.Name == "wool_pink" and isValidWoolBlock(obj) then
						OldMaterials[obj] = obj.MaterialVariant
						OldColors[obj] = obj.Color
						obj.MaterialVariant = 'rbxassetid://16991768606_green'
						obj.Color = Color3.fromRGB(15, 185, 55)
					end
				end))
				
				for _, obj in blocks:GetChildren() do
					if obj.Name == "wool_orange" and isValidWoolBlock(obj) then
						OldMaterials[obj] = obj.MaterialVariant
						OldColors[obj] = obj.Color
						obj.MaterialVariant = 'rbxassetid://16991768606_red'
						obj.Color = Color3.fromRGB(196, 40, 28)
					elseif obj.Name == "wool_pink" and isValidWoolBlock(obj) then
						OldMaterials[obj] = obj.MaterialVariant
						OldColors[obj] = obj.Color
						obj.MaterialVariant = 'rbxassetid://16991768606_green'
						obj.Color = Color3.fromRGB(15, 185, 55)
					end
				end
				
				task.spawn(function()
					while OG4v4v4v4.Enabled do
						local topBarGui = lplr.PlayerGui:FindFirstChild('TopBarAppGui')
						if topBarGui then
							for i, v in topBarGui:GetDescendants() do
								if v:IsA("Frame") and v.Name == "3" then
									if v.BackgroundColor3 == Color3.fromRGB(242, 142, 41) then
										v.BackgroundColor3 = Color3.fromRGB(196, 40, 28)
										if v.Parent then
											for _, sibling in v.Parent:GetChildren() do
												if sibling:IsA("UIStroke") then
													sibling.Color = Color3.fromRGB(196, 40, 28)
												end
											end
										end
									elseif v.BackgroundColor3 == Color3.fromRGB(255, 102, 204) or 
										   v.BackgroundColor3 == Color3.fromRGB(255, 85, 255) or 
										   v.BackgroundColor3 == Color3.fromRGB(218, 133, 222) then
										v.BackgroundColor3 = Color3.fromRGB(15, 185, 55)
										if v.Parent then
											for _, sibling in v.Parent:GetChildren() do
												if sibling:IsA("UIStroke") then
													sibling.Color = Color3.fromRGB(15, 185, 55)
												end
											end
										end
									end
								end
							end
						end
						task.wait(0.5)
					end
				end)
				
				OG4v4v4v4:Clean(lplr.PlayerGui.ChildAdded:Connect(function(obj)
					if obj.Name == "TabListScreenGui" then
						for i, v in obj:GetDescendants() do
							if v:IsA("Frame") and v.Name == "2" then
								if v.BackgroundColor3 == Color3.fromRGB(242, 142, 41) then
									v.BackgroundColor3 = Color3.fromRGB(196, 40, 28)
									if v.Parent then
										for _, sibling in v.Parent:GetChildren() do
											if sibling:IsA("UIStroke") then
												sibling.Color = Color3.fromRGB(196, 40, 28)
											end
										end
									end
									if v:FindFirstChild("TeamName") then
										v:FindFirstChild("TeamName").RichText = true
										v:FindFirstChild("TeamName").Text = "<b>Red Team</b>"
									end
								elseif v.BackgroundColor3 == Color3.fromRGB(255, 102, 204) or 
									   v.BackgroundColor3 == Color3.fromRGB(255, 85, 255) or 
									   v.BackgroundColor3 == Color3.fromRGB(218, 133, 222) then
									v.BackgroundColor3 = Color3.fromRGB(15, 185, 55)
									if v.Parent then
										for _, sibling in v.Parent:GetChildren() do
											if sibling:IsA("UIStroke") then
												sibling.Color = Color3.fromRGB(15, 185, 55)
											end
										end
									end
									if v:FindFirstChild("TeamName") then
										v:FindFirstChild("TeamName").RichText = true
										v:FindFirstChild("TeamName").Text = "<b>Green Team</b>"
									end
								end
							end
						end
					end
				end))
			else
				for i, v in lplr.PlayerGui:FindFirstChild('TopBarAppGui'):GetDescendants() do
					if v:IsA("Frame") and v.Name == "3" then
						if v.BackgroundColor3 == Color3.fromRGB(196, 40, 28) then
							v.BackgroundColor3 = Color3.fromRGB(242, 142, 41)
							if v.Parent then
								for _, sibling in v.Parent:GetChildren() do
									if sibling:IsA("UIStroke") then
										sibling.Color = Color3.fromRGB(242, 142, 41)
									end
								end
							end
						elseif v.BackgroundColor3 == Color3.fromRGB(15, 185, 55) then
							v.BackgroundColor3 = Color3.fromRGB(255, 102, 204)
							if v.Parent then
								for _, sibling in v.Parent:GetChildren() do
									if sibling:IsA("UIStroke") then
										sibling.Color = Color3.fromRGB(255, 102, 204)
									end
								end
							end
						end
					end
				end
				
				restoreNumTeamMembers()
				
				for texture, oldTex in pairs(oldTexture) do
					if texture and texture.Parent then
						texture.Texture = oldTex
					end
				end
				for texture, oldCol in pairs(oldColor) do
					if texture and texture.Parent then
						texture.Color3 = oldCol
					end
				end
				
				for obj, oldMaterial in pairs(OldMaterials) do
					if obj and obj.Parent then
						obj.MaterialVariant = oldMaterial
						if OldColors[obj] then
							obj.Color = OldColors[obj]
						end
					end
				end
				
				table.clear(OldMaterials)
				table.clear(OldColors)
				table.clear(oldTexture)
				table.clear(oldColor)
			end
		end,
		Tooltip = 'koli shit'
	})
end)

run(function()
    local OGNametags
    local storedNametags = {}
    local connections = {}
    local ActiveTags = {}
    local CLAN_GRAY = "#B9B9B9"
    local HideOwnNametag
    local DotSizeSlider
    local DotPositionSlider

    local LocalPlayer = playersService.LocalPlayer

    local function create(className, props)
        local obj = Instance.new(className)
        for k, v in pairs(props) do
            obj[k] = v
        end
        return obj
    end

    local function getHead(char)
        return char:FindFirstChild("Head") or char:WaitForChild("Head", 5)
    end

    local function getClan(plr)
        if not plr then return "" end
        return plr:GetAttribute("ClanTag") or plr:GetAttribute("Clan") or ""
    end

    local function getNameColor(plr)
        if not plr then return Color3.fromRGB(255, 80, 80) end
        if LocalPlayer.Team and plr.Team and LocalPlayer.Team == plr.Team then
            return Color3.fromRGB(90, 255, 90)
        end
        return Color3.fromRGB(255, 80, 80)
    end

    local function getTeamDotColor(plr)
        if not plr or not plr.Team then return Color3.new(1, 1, 1) end
        local teamName = string.lower(plr.Team.Name)
        if teamName:find("pink") then
            return Color3.fromRGB(90, 255, 90)
        elseif teamName:find("orange") then
            return Color3.fromRGB(255, 80, 80)
        elseif teamName:find("blue") then
            return Color3.fromRGB(80, 160, 255)
        elseif teamName:find("yellow") then
            return Color3.fromRGB(255, 220, 80)
        end
        return Color3.new(1, 1, 1)
    end

    local function removeOtherNameTags(char)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.NameDisplayDistance = 0
        end
        local head = char:FindFirstChild("Head")
        if not head then return end
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("BillboardGui") and child.Name ~= "OGNametag" and child.Name ~= "Nametag" then
                child:Destroy()
            end
        end
    end

    local function updateTag(plr)
        local data = ActiveTags[plr]
        if not data then return end

        local nameColor = getNameColor(plr)
        local dotColor = getTeamDotColor(plr)
        local clan = getClan(plr)

        data.dot.BackgroundColor3 = dotColor
        data.stroke.Color = nameColor

        local displayName = plr.DisplayName ~= "" and plr.DisplayName or plr.Name

        if clan ~= "" then
            data.txt.Text = string.format(
                '<font color="%s" size="140">[%s]</font>&nbsp;<font color="rgb(%d,%d,%d)" size="130">%s</font>',
                CLAN_GRAY, clan,
                nameColor.R * 255, nameColor.G * 255, nameColor.B * 255,
                displayName
            )
        else
            data.txt.Text = string.format(
                '<font color="rgb(%d,%d,%d)" size="130">%s</font>',
                nameColor.R * 255, nameColor.G * 255, nameColor.B * 255,
                displayName
            )
        end
    end

    local function CreatePlayerTag(plr, isLocal)
        if not OGNametags or not OGNametags.Enabled then return end
        if isLocal and HideOwnNametag and HideOwnNametag.Enabled then return end
        if not isLocal and getAccountTier(plr) >= 4 and getAccountTier(plr) < 99 and getAccountTier(lplr) == 0 then return end

        local char = plr.Character
        if not char then return end
        local head = getHead(char)
        if not head then return end

        removeOtherNameTags(char)

        local originalNametag = head:FindFirstChild("Nametag")
        if originalNametag then
            storedNametags[char] = originalNametag:Clone()
            originalNametag:Destroy()
        end

        local old = head:FindFirstChild("OGNametag")
        if old then old:Destroy() end

        local nameColor = getNameColor(plr)
        local teamDotColor = getTeamDotColor(plr)
        local clan = getClan(plr)

        local dotPx = DotSizeSlider and DotSizeSlider.Value or 22
        local dotPos = DotPositionSlider and DotPositionSlider.Value or 0.10

        local billui = create("BillboardGui", {
            Name = "OGNametag",
            AlwaysOnTop = false,
            Parent = head,
            Size = UDim2.fromScale(5.35, 0.6),
            StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0),
            Adornee = head
        })

        local Main = create("Frame", {
            Parent = billui,
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1)
        })

        local Dot = create("Frame", {
            Parent = Main,
            BackgroundColor3 = teamDotColor,
            BackgroundTransparency = 0.1,
            Position = UDim2.fromScale(0.02, 0.10),
            Size = UDim2.fromScale(0.17, 0.88),
            BorderSizePixel = 0
        })

        create("UIAspectRatioConstraint", {
            Parent = Dot,
            AspectRatio = 1,
            DominantAxis = Enum.DominantAxis.Height
        })

        create("UICorner", { Parent = Dot, CornerRadius = UDim.new(1, 0) })

        local Bar = create("Frame", {
            Parent = Main,
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 0.65,
            Position = UDim2.fromScale(0.19, 0.14),
            Size = UDim2.fromScale(0.82, 0.72),
            BorderSizePixel = 0
        })

        create("UICorner", { Parent = Bar, CornerRadius = UDim.new(0, 0) })

        local Stroke = create("UIStroke", {
            Parent = Bar,
            Color = nameColor,
            Thickness = 1.2,
            Transparency = 0.3
        })

        local Txt = create("TextLabel", {
            Parent = Bar,
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(0.99, 1.15),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Font = Enum.Font.GothamMedium,
            TextScaled = true,
            RichText = true,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center
        })

        local displayName = plr.DisplayName ~= "" and plr.DisplayName or plr.Name

        if clan ~= "" then
            Txt.Text = string.format(
                '<font color="%s" size="140">[%s]</font>&nbsp;<font color="rgb(%d,%d,%d)" size="130">%s</font>',
                CLAN_GRAY, clan,
                nameColor.R * 255, nameColor.G * 255, nameColor.B * 255,
                displayName
            )
        else
            Txt.Text = string.format(
                '<font color="rgb(%d,%d,%d)" size="130">%s</font>',
                nameColor.R * 255, nameColor.G * 255, nameColor.B * 255,
                displayName
            )
        end

        ActiveTags[plr] = {
            bar = Bar,
            dot = Dot,
            stroke = Stroke,
            txt = Txt,
            head = head,
            char = char,
            gui = billui
        }
    end

    local function hook(plr)
        local function onCharAdded()
            task.wait(0.25)
            CreatePlayerTag(plr, plr == LocalPlayer)
        end

        local conn = plr.CharacterAdded:Connect(onCharAdded)
        table.insert(connections, conn)

        if plr.Character then
            task.wait(0.25)
            CreatePlayerTag(plr, plr == LocalPlayer)
        end
    end

    local renderConn

    OGNametags = vape.Categories.Render:CreateModule({
        Name = "OGNametags",
        Function = function(callback)
            if callback then
                for _, plr in ipairs(playersService:GetPlayers()) do
                    hook(plr)
                end

                local playerAddedConn = playersService.PlayerAdded:Connect(hook)
                table.insert(connections, playerAddedConn)

                local playerRemovingConn = playersService.PlayerRemoving:Connect(function(plr)
                    ActiveTags[plr] = nil
                end)
                table.insert(connections, playerRemovingConn)

                renderConn = game:GetService("RunService").RenderStepped:Connect(function()
                    local myChar = LocalPlayer.Character
                    if not myChar then return end
                    local myHead = myChar:FindFirstChild("Head")
                    if not myHead then return end

                    for plr, data in pairs(ActiveTags) do
                        if data.head and data.gui then
                            updateTag(plr)
                            local dist = (data.head.Position - myHead.Position).Magnitude
                            data.gui.AlwaysOnTop = dist <= 18
                        end
                    end
                end)

            else
                if renderConn then
                    renderConn:Disconnect()
                    renderConn = nil
                end

                for _, conn in ipairs(connections) do
                    if conn then conn:Disconnect() end
                end
                table.clear(connections)
                table.clear(ActiveTags)

                for _, plr in ipairs(playersService:GetPlayers()) do
                    if plr.Character then
                        local head = plr.Character:FindFirstChild("Head")
                        if head then
                            local og = head:FindFirstChild("OGNametag")
                            if og then og:Destroy() end
                            if storedNametags[plr.Character] then
                                storedNametags[plr.Character]:Clone().Parent = head
                                storedNametags[plr.Character] = nil
                            end
                        end
                    end
                end

                table.clear(storedNametags)
            end
        end,
        Tooltip = "oG BedWars nametags with koli's UI"
    })

    HideOwnNametag = OGNametags:CreateToggle({
        Name = "Hide Self Nametag",
        Default = true,
        Function = function(callback)
            if OGNametags.Enabled then
                if callback then
                    local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
                    if head then
                        local og = head:FindFirstChild("OGNametag")
                        if og then og:Destroy() end
                    end
                else
                    CreatePlayerTag(LocalPlayer, true)
                end
            end
        end
    })

    DotSizeSlider = OGNametags:CreateSlider({
        Name = "Dot Size",
        Min = 4,
        Max = 60,
        Default = 22,
        Decimal = 1,
        Suffix = "px",
        Tooltip = "adjust the size of the colored team dot",
        Function = function(val)
            for _, tagData in pairs(ActiveTags) do
                if tagData and tagData.dot then
                    tagData.dot.Size = UDim2.fromOffset(val, val)
                end
            end
        end
    })

    DotPositionSlider = OGNametags:CreateSlider({
        Name = "Dot Position",
        Min = 0.01,
        Max = 0.30,
        Default = 0.10,
        Decimal = 100,
        Tooltip = "move the dot up or down",
        Function = function(val)
            for _, tagData in pairs(ActiveTags) do
                if tagData and tagData.dot then
                    tagData.dot.Position = UDim2.fromScale(0.02, val)
                end
            end
        end
    })
end)

run(function()
	local privateFunc = loadstring(readfile('newvape/games/private.lua'))()
	if privateFunc then
		privateFunc(vape, run, bedwars, entitylib, lplr, inputService, runService, store, playersService, replicatedStorage, tweenService, httpService, textChatService, collectionService, contextActionService, guiService, coreGui, starterGui, lightingService, gameCamera, entitylib, targetinfo, sessioninfo, uipallet, tween, color, prediction, getfontsize, getcustomasset, vapeEvents, isnetworkowner, assetfunction, VirtualInputManager)
	end
end)
