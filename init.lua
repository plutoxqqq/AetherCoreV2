--!nocheck
local license = ... or {}
license.Whitelist = getgenv().whitelist or license.Whitelist

local cloneref = cloneref or function(ref) return ref end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local delfile = delfile or function(file)
	writefile(file, '')
end

local function createLoadingScreen()
	local parent = gethui and gethui() or cloneref(game:GetService('CoreGui'))
	local existing = parent:FindFirstChild('AetherCoreLoading')
	if existing then return existing end

	local screen = Instance.new('ScreenGui')
	screen.Name = 'AetherCoreLoading'
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 2147483647
	screen.Parent = parent

	local background = Instance.new('Frame')
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(8, 9, 14)
	background.BorderSizePixel = 0
	background.Parent = screen

	local logo = Instance.new('ImageLabel')
	logo.Name = 'Logo'
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.43)
	logo.Size = UDim2.fromOffset(320, 140)
	logo.BackgroundTransparency = 1
	logo.ScaleType = Enum.ScaleType.Fit
	logo.Image = isfile('aethercorev2/assets/new/loading.png') and (getcustomasset and getcustomasset('aethercorev2/assets/new/loading.png') or 'aethercorev2/assets/new/loading.png') or ''
	logo.Parent = background

	local version = Instance.new('TextLabel')
	version.Name = 'Version'
	version.AnchorPoint = Vector2.new(0.5, 0)
	version.Position = UDim2.fromScale(0.5, 0.54)
	version.Size = UDim2.fromOffset(260, 22)
	version.BackgroundTransparency = 1
	version.Font = Enum.Font.GothamMedium
	version.TextSize = 14
	version.TextColor3 = Color3.fromRGB(190, 196, 220)
	version.Text = isfile('aethercorev2/version.txt') and ('Version '..readfile('aethercorev2/version.txt')) or 'Version loading...'
	version.Parent = background

	local bar = Instance.new('Frame')
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0.59)
	bar.Size = UDim2.fromOffset(360, 28)
	bar.BackgroundColor3 = Color3.fromRGB(18, 21, 34)
	bar.BorderSizePixel = 0
	bar.Parent = background
	local barCorner = Instance.new('UICorner')
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = bar

	local status = Instance.new('TextLabel')
	status.Name = 'Status'
	status.Size = UDim2.new(1, -18, 1, 0)
	status.Position = UDim2.fromOffset(9, 0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.TextSize = 13
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Color3.fromRGB(235, 238, 255)
	status.Text = 'Starting AetherCore...'
	status.Parent = bar

	_G.AetherCoreLoadingScreen = screen
	_G.AetherCoreSetLoadingStatus = function(text)
		if status.Parent then status.Text = text end
		if version.Parent and isfile('aethercorev2/version.txt') then version.Text = 'Version '..readfile('aethercorev2/version.txt') end
		if logo.Parent and logo.Image == '' and isfile('aethercorev2/assets/new/loading.png') then
			logo.Image = getcustomasset and getcustomasset('aethercorev2/assets/new/loading.png') or 'aethercorev2/assets/new/loading.png'
		end
	end
	return screen
end

local loadingScreen = createLoadingScreen()
local downloader = loadingScreen:FindFirstChild('Status', true)

local function downloadFile(path, func)
	if not isfile(path) then
		if not license.Closet then
			_G.AetherCoreSetLoadingStatus('Downloading '..path)
		end
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/plutoxqqq/AetherCoreV2/'..readfile('aethercorev2/profiles/commit.txt')..'/'..select(1, path:gsub('aethercorev2/', '')), true)
		end)
		if not suc or res == '404: Not Found' then
			error(res)
		end
		if path:find('.lua') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
		end
		writefile(path, res)
		_G.AetherCoreSetLoadingStatus('Downloaded '..path)
	end
	return (func or readfile)(path)
end

local function wipeFolder(path)
	if not isfolder(path) then return end
	for _, file in listfiles(path) do
		if file:find('init') then continue end
		if file:find('profile') then continue end
		if isfile(file) then
			delfile(file)
		elseif isfolder(file) then
			wipeFolder(file)
		end
	end
end


for _, folder in {'aethercorev2', 'aethercorev2/games', 'aethercorev2/profiles', 'aethercorev2/assets', 'aethercorev2/assets/new', 'aethercorev2/libraries', 'aethercorev2/guis', 'aethercorev2/configs'} do
	if not isfolder(folder) then
		_G.AetherCoreSetLoadingStatus('Creating '..folder)
		makefolder(folder)
	end
end

if not shared.VapeDeveloper then
	local commit = license.Commit or nil
	if not commit then
		local _, subbed = pcall(function()
			return game:HttpGet('https://github.com/plutoxqqq/AetherCoreV2')
		end)
		commit = subbed:find('currentOid')
		commit = commit and subbed:sub(commit + 13, commit + 52) or nil
		commit = commit and #commit == 40 and commit or 'main'
	end
	local oldCommit = isfile('aethercorev2/profiles/commit.txt') and readfile('aethercorev2/profiles/commit.txt') or ''
	if oldCommit ~= commit then
		if commit ~= 'main' and oldCommit ~= '' then
			shared.updated = oldCommit
		end
		wipeFolder('aethercorev2')
		wipeFolder('aethercorev2/games')
		wipeFolder('aethercorev2/guis')
		wipeFolder('aethercorev2/libraries')
	end
	writefile('aethercorev2/profiles/commit.txt', commit)
end

downloadFile('aethercorev2/version.txt')
downloadFile('aethercorev2/assets/new/loading.png')

_G.AetherCoreSetLoadingStatus('Loading main script...')
return loadstring(downloadFile('aethercorev2/main.lua'), 'main')(license)
