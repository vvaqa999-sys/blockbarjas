local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local StarterGui         = game:GetService("StarterGui")
local HttpService        = game:GetService("HttpService")
local LocalPlayer        = Players.LocalPlayer
local VirtualInputManager = Instance.new("VirtualInputManager")

local Synchronizer, AnimalsModule, MutationsModule, TraitsModule
task.spawn(function()
    local Packages = ReplicatedStorage:WaitForChild("Packages", 10)
    local Datas = ReplicatedStorage:WaitForChild("Datas", 10)
    if Packages then
        pcall(function()
            Synchronizer = require(Packages:WaitForChild("Synchronizer", 5))
        end)
    end
    if Datas then
        pcall(function()
            AnimalsModule = require(Datas:WaitForChild("Animals", 5))
        end)
        pcall(function()
            MutationsModule = require(Datas:WaitForChild("Mutations", 5))
        end)
        pcall(function()
            TraitsModule = require(Datas:WaitForChild("Traits", 5))
        end)
    end
end)

local AutoBlockEnabled       = false
local AutoFlashEnabled       = false
local RagdollBypassEnabled   = false
local ApEspEnabled           = false
local AutoSelectBestBrainrot = false
local BypassAutoDefense      = false
local BlockSpeed             = "ULTRA"
local AntiRagdoll = { connections = {}, running = false }

local ActionHotkeys = {
    FLASH = nil,
    BLOCK = nil,
    RESET = nil,
}

local ConfigFileName = "V7Config.json"

local function SaveConfig()
	pcall(function()
		if not writefile then return end
		local hotkeysSaved = {}
		if ActionHotkeys then
			for k, v in pairs(ActionHotkeys) do
				if v and typeof(v) == "EnumItem" then
					hotkeysSaved[k] = v.Name
				end
			end
		end
		local data = {
			AutoBlockEnabled = AutoBlockEnabled,
			AutoFlashEnabled = AutoFlashEnabled,
			RagdollBypassEnabled = RagdollBypassEnabled,
			AntiRagdollEnabled = (AntiRagdoll and AntiRagdoll.running) or false,
			ApEspEnabled = ApEspEnabled,
			AutoSelectBestBrainrot = AutoSelectBestBrainrot,
			BypassAutoDefense = BypassAutoDefense,
			BlockSpeed = BlockSpeed or "ULTRA",
			Hotkeys = hotkeysSaved
		}
		writefile(ConfigFileName, HttpService:JSONEncode(data))
	end)
end

local function LoadConfig()
	pcall(function()
		if not (readfile and isfile and isfile(ConfigFileName)) then return end
		local raw = readfile(ConfigFileName)
		local data = HttpService:JSONDecode(raw)
		if type(data) ~= "table" then return end

		if data.AutoBlockEnabled ~= nil then AutoBlockEnabled = data.AutoBlockEnabled end
		if data.AutoFlashEnabled ~= nil then AutoFlashEnabled = data.AutoFlashEnabled end
		if data.RagdollBypassEnabled ~= nil then RagdollBypassEnabled = data.RagdollBypassEnabled end
		if data.ApEspEnabled ~= nil then ApEspEnabled = data.ApEspEnabled end
		if data.AutoSelectBestBrainrot ~= nil then AutoSelectBestBrainrot = data.AutoSelectBestBrainrot end
		if data.BypassAutoDefense ~= nil then BypassAutoDefense = data.BypassAutoDefense end
		if data.BlockSpeed ~= nil then BlockSpeed = data.BlockSpeed end
		if data.Hotkeys and type(data.Hotkeys) == "table" and ActionHotkeys then
			for k, keyName in pairs(data.Hotkeys) do
				local kc = Enum.KeyCode[keyName]
				if kc then
					ActionHotkeys[k] = kc
				end
			end
		end
	end)
end
LoadConfig()

local __AG_stealCbCache  = {}
local __AG_stealActive   = false
local __AG_MIN_HOLD_TIME = 1.3
local __AG_TRIGGER_DELAY = 0.05

local _ragdollCommandCache = {}
local _ragdollProfileCache = {}
local _ragdollCacheActivated, _ragdollFireActivated, _ragdollGetAdminFrames, _ragdollSelf


AntiRagdoll.forceBackpack = function()
	if not AntiRagdoll.running then return end
	local gui = LocalPlayer:FindFirstChild("PlayerGui")
	if not gui then return end
	local backpackGui = gui:FindFirstChild("BackpackGui")
	if not backpackGui then return end
	local backpack = backpackGui:FindFirstChild("Backpack")
	if not backpack then return end
	backpack.Visible = true
	if not backpack:FindFirstChild("ForceConnection") then
		local tag = Instance.new("BoolValue")
		tag.Name   = "ForceConnection"
		tag.Parent = backpack
		backpack:GetPropertyChangedSignal("Visible"):Connect(function()
			if not AntiRagdoll.running then return end
			if not backpack.Visible then backpack.Visible = true end
		end)
	end
end

AntiRagdoll.removeRagdollConstraints = function(char)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint")
			or d:IsA("NoCollisionConstraint")
			or (d:IsA("Attachment") and d.Name:find("RagdollAttachment")) then
			d:Destroy()
		end
	end
end

AntiRagdoll.resetCharacter = function(char)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart.Anchored = false
		rootPart.Velocity  = Vector3.zero
	end
	if humanoid then
		for _, obj in ipairs(char:GetDescendants()) do
			if obj:IsA("Motor6D") and obj.Enabled == false then
				obj.Enabled = true
			end
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,     false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid.PlatformStand = false
		humanoid.Sit           = false
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
		workspace.CurrentCamera.CameraSubject = humanoid
	end
end

AntiRagdoll.onCharacterAdded_AR = function(char)
	char:WaitForChild("HumanoidRootPart")
	local humanoid = char:WaitForChild("Humanoid")
	AntiRagdoll.connections.charDescAdded = char.DescendantAdded:Connect(function(obj)
		if not AntiRagdoll.running then return end
		if obj:IsA("BallSocketConstraint") or obj:IsA("HingeConstraint")
			or obj:IsA("NoCollisionConstraint")
			or (obj:IsA("Attachment") and obj.Name:find("RagdollAttachment")) then
			task.defer(function()
				if not AntiRagdoll.running then return end
				if obj.Parent then obj:Destroy() end
			end)
		end
	end)
	AntiRagdoll.connections.platformStand = humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(function()
		if not AntiRagdoll.running then return end
		if humanoid.PlatformStand then
			task.defer(function()
				if not AntiRagdoll.running then return end
				AntiRagdoll.resetCharacter(char)
				AntiRagdoll.removeRagdollConstraints(char)
			end)
		end
	end)
	AntiRagdoll.removeRagdollConstraints(char)
	AntiRagdoll.resetCharacter(char)
end

AntiRagdoll.enable = function()
	if AntiRagdoll.running then return end
	AntiRagdoll.running = true
	AntiRagdoll.connections.heartbeat = RunService.Heartbeat:Connect(function()
		local char = LocalPlayer.Character
		if not char then return end
		local hum  = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not (hum and root) then return end
		local s = hum:GetState()
		local ragdolled = (s == Enum.HumanoidStateType.Physics
			or s == Enum.HumanoidStateType.Ragdoll
			or s == Enum.HumanoidStateType.FallingDown)
		local endTime = LocalPlayer:GetAttribute("RagdollEndTime")
		if endTime and (endTime - workspace:GetServerTimeNow()) > 0 then
			ragdolled = true
		end
		if ragdolled or hum.PlatformStand then
			pcall(function() LocalPlayer:SetAttribute("RagdollEndTime", workspace:GetServerTimeNow()) end)
			AntiRagdoll.removeRagdollConstraints(char)
			for _, obj in ipairs(char:GetDescendants()) do
				if obj:IsA("Motor6D") and obj.Enabled == false then
					obj.Enabled = true
				end
			end
			if hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Running) end
			hum.PlatformStand = false
			hum.Sit           = false
			workspace.CurrentCamera.CameraSubject = hum
			root.Anchored = false
			root.Velocity  = Vector3.zero
		end
	end)
	AntiRagdoll.connections.charAdded = LocalPlayer.CharacterAdded:Connect(function(char)
		task.wait(1)
		AntiRagdoll.forceBackpack()
		AntiRagdoll.onCharacterAdded_AR(char)
	end)
	if LocalPlayer.Character then AntiRagdoll.onCharacterAdded_AR(LocalPlayer.Character) end
	task.spawn(function()
		while AntiRagdoll.running do
			task.wait(0.5)
			AntiRagdoll.forceBackpack()
		end
	end)
end

AntiRagdoll.disable = function()
	AntiRagdoll.running = false
	for _, conn in pairs(AntiRagdoll.connections) do
		if conn then pcall(function() conn:Disconnect() end) end
	end
	AntiRagdoll.connections = {}
	pcall(function()
		local char = LocalPlayer.Character
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,     true)
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
		end
	end)
end

local function drawClickDot(x, y)
	if not Drawing then return end
	local dot = Drawing.new("Circle")
	dot.Radius   = 5
	dot.Position = Vector2.new(x, y)
	dot.Color    = Color3.fromRGB(255, 80, 80)
	dot.Filled   = true
	dot.Visible  = true
	dot.Transparency = 0.6
	task.delay(0.25, function() dot:Remove() end)
end

local function getPlotOwnerPlayer()
	local sel = _G._FH_SelectedBrainrot
	if not sel or not sel.plotName then return nil end
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	local plot = plotsFolder:FindFirstChild(sel.plotName)
	if not plot then return nil end
	local ownerName = nil
	local sign = plot:FindFirstChild("PlotSign", true)
	if sign then
		for _, d in ipairs(sign:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text and d.Text ~= "" then
				local t = d.Text
				if not t:lower():find("empty") then
					local m = t:match("[Bb]ase [Oo]f%s+(.+)")
					if m then ownerName = m; break end
					if #t > 0 and #t < 30 then ownerName = t; break end
				end
			end
		end
	end
	if not ownerName then return nil end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and (p.Name == ownerName or p.DisplayName == ownerName) then
			return p
		end
	end
	return nil
end

local function getNearestPlayer()
	local chr = LocalPlayer and LocalPlayer.Character
	local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local nearest, nearestDist = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local c = p.Character
			local h = c and c:FindFirstChild("HumanoidRootPart")
			if h then
				local dist = (h.Position - hrp.Position).Magnitude
				if dist < nearestDist then
					nearestDist = dist
					nearest     = p
				end
			end
		end
	end
	return nearest
end

-- ==========================================
-- FIXED: getPromptConfirmButton
-- Targets "Block" button only, ignores "Block and report"
-- Works on all screen sizes (PC, Mobile, iPad)
-- ==========================================
local function getPromptConfirmButton()
	local coreGui = nil
	pcall(function() coreGui = game:GetService("CoreGui") end)
	if not coreGui then pcall(function() coreGui = gethui and gethui() end) end
	if not coreGui then return nil end

	local robloxGui = coreGui:FindFirstChild("RobloxGui") or coreGui
	local prompt = robloxGui:FindFirstChild("PromptDialog", true)
	if prompt and prompt.Visible ~= false then
		local fallbackBtns = {}
		for _, d in ipairs(prompt:GetDescendants()) do
			if (d:IsA("TextButton") or d:IsA("ImageButton") or d:IsA("GuiButton")) and d.Visible ~= false then
				local text = (d:IsA("TextButton") and d.Text:lower()) or ""
				local name = d.Name:lower()
				local isBlockBtn = text:find("block") or name:find("confirm") or name:find("button1") or name:find("yes")
				local isReportBtn = text:find("report") or name:find("report")
				if isBlockBtn then
					if not isReportBtn then
						-- Perfect match: "Block" only, not "Block and report"
						return d
					else
						-- Fallback if only report button found
						table.insert(fallbackBtns, d)
					end
				end
			end
		end
		if #fallbackBtns > 0 then return fallbackBtns[1] end
	end
	return nil
end

local function instantConfirmButton(btn)
	if not btn then return false end
	if firesignal then
		pcall(function() firesignal(btn.MouseButton1Click) end)
		pcall(function() firesignal(btn.Activated) end)
	end
	if getconnections then
		pcall(function()
			for _, c in ipairs(getconnections(btn.MouseButton1Click)) do
				if c.Function then task.spawn(c.Function) end
			end
			for _, c in ipairs(getconnections(btn.Activated)) do
				if c.Function then task.spawn(c.Function) end
			end
		end)
	end
	local pos = btn.AbsolutePosition + (btn.AbsoluteSize * 0.5)
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
		task.wait()
		VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
	end)
	return true
end

-- ==========================================
-- FIXED: Ultra-Fast Auto-Confirm Hook
-- Only clicks "Block", never "Block and report"
-- ==========================================
pcall(function()
	local coreGui = game:GetService("CoreGui")
	local robloxGui = coreGui:FindFirstChild("RobloxGui") or coreGui
	robloxGui.DescendantAdded:Connect(function(descendant)
		if (BlockSpeed == "ULTRA" or BlockSpeed == "ULTRA FAST") then
			if (descendant:IsA("TextButton") or descendant:IsA("GuiButton") or descendant:IsA("ImageButton")) then
				local text = (descendant:IsA("TextButton") and descendant.Text:lower()) or ""
				local name = descendant.Name:lower()
				local isBlockBtn = text:find("block") or name:find("confirm") or name:find("button1") or name:find("yes")
				local isReportBtn = text:find("report") or name:find("report")
				if isBlockBtn and not isReportBtn then
					task.spawn(function()
						instantConfirmButton(descendant)
					end)
				end
			end
		end
	end)
end)

local function blockPlayer(targetPlayer)
	if not targetPlayer then return end
	pcall(function() StarterGui:SetCore("PromptBlockPlayer", targetPlayer) end)

	local chr = LocalPlayer and LocalPlayer.Character
	local blockers = {}
	if chr then
		for _, t in ipairs(chr:GetChildren()) do
			if t:IsA("Tool") then
				local blocked = true
				local conn = t.Activated:Connect(function()
					if blocked then return end
				end)
				table.insert(blockers, { conn = conn, setUnblocked = function() blocked = false end })
			end
		end
	end

	local function clickScreen(x, y)
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
			task.wait()
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
		end)
	end

	task.spawn(function()
		local vSize = workspace.CurrentCamera.ViewportSize
		local defaultX = math.floor(vSize.X * 0.5)
		local defaultY = math.floor(vSize.Y * 0.5)
		local isUltra = (BlockSpeed == "ULTRA" or BlockSpeed == "ULTRA FAST")

		local directBtn = getPromptConfirmButton()
		if directBtn then
			instantConfirmButton(directBtn)
		else
			clickScreen(defaultX, defaultY)
			clickScreen(1277, 764)
		end

		local maxChecks = isUltra and 8 or 5
		for i = 1, maxChecks do
			local btn = getPromptConfirmButton()
			if btn then
				instantConfirmButton(btn)
				break
			else
				clickScreen(1277, 764)
			end
			if isUltra then
				RunService.RenderStepped:Wait()
			else
				RunService.Heartbeat:Wait()
			end
		end

		task.delay(0.05, function()
			for _, b in ipairs(blockers) do
				b.setUnblocked()
				pcall(function() b.conn:Disconnect() end)
			end
		end)
	end)
end

local function getBlockDelay()
	if BlockSpeed == "ULTRA" or BlockSpeed == "ULTRA FAST" then
		return 0.001
	elseif BlockSpeed == "FAST" then
		return 0.02
	elseif BlockSpeed == "NORMAL" then
		return 0.04
	elseif BlockSpeed == "SLOW" then
		return 0.12
	end
	return 0.01
end

local function triggerAutoBlock()
	if not AutoBlockEnabled then return end
	local delayTime = getBlockDelay()
	if delayTime <= 0 then
		local target = getPlotOwnerPlayer() or getNearestPlayer()
		if target then pcall(blockPlayer, target) end
	else
		task.spawn(function()
			task.wait(delayTime)
			local target = getPlotOwnerPlayer() or getNearestPlayer()
			if target then pcall(blockPlayer, target) end
		end)
	end
end

local function triggerTimedBlock(dist, speed)
	if not AutoBlockEnabled then return end
	local travelTime = dist / math.max(speed, 1)
	local preDelay   = math.max(0, travelTime)
	task.delay(preDelay, function()
		if not AutoBlockEnabled then return end
		local target = getPlotOwnerPlayer() or getNearestPlayer()
		if target then pcall(blockPlayer, target) end
	end)
end

local function __AG_findTargetPrompt()
	local sel = _G._FH_SelectedBrainrot
	if not sel then return nil end

	if sel.prompt and sel.prompt.Parent and sel.prompt:IsA("ProximityPrompt") then
		pcall(function()
			sel.prompt.RequiresLineOfSight = false
			sel.prompt.MaxActivationDistance = math.huge
			sel.prompt.HoldDuration = 0
		end)
		return sel.prompt
	end

	if not sel.plotName or not sel.slot then return nil end
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	local plot = plotsFolder:FindFirstChild(sel.plotName)
	if not plot then return nil end
	local podiums = plot:FindFirstChild("AnimalPodiums") or plot:FindFirstChild("Podiums")
	if not podiums then return nil end

	local targetSlot = tonumber(sel.slot)
	local targetPodium = nil

	for _, podium in ipairs(podiums:GetChildren()) do
		local slotNum = tonumber(podium.Name:match("%d+"))
		if slotNum == targetSlot or podium.Name == tostring(targetSlot) then
			targetPodium = podium
			break
		end
	end

	if not targetPodium then return nil end
	local base   = targetPodium:FindFirstChild("Base") or targetPodium
	local spawn_ = base:FindFirstChild("Spawn") or base
	local pa     = (spawn_ and spawn_:FindFirstChild("PromptAttachment")) or targetPodium:FindFirstChild("PromptAttachment", true)
	local prompt = (pa and pa:FindFirstChildWhichIsA("ProximityPrompt")) or targetPodium:FindFirstChildWhichIsA("ProximityPrompt", true)

	if prompt then
		pcall(function()
			prompt.RequiresLineOfSight   = false
			prompt.MaxActivationDistance = math.huge
			prompt.HoldDuration          = 0
		end)
		sel.prompt = prompt
	end
	return prompt
end

local function __AG_buildStealCallbacks(prompt)
	if not prompt then return nil end
	if __AG_stealCbCache[prompt] then return __AG_stealCbCache[prompt] end
	local data = { hold = {}, trigger = {} }
	if getconnections then
		local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
		if ok1 and type(conns1) == "table" then
			for _, c in ipairs(conns1) do
				if type(c.Function) == "function" then table.insert(data.hold, c.Function) end
			end
		end
		local ok2, conns2 = pcall(getconnections, prompt.Triggered)
		if ok2 and type(conns2) == "table" then
			for _, c in ipairs(conns2) do
				if type(c.Function) == "function" then table.insert(data.trigger, c.Function) end
			end
		end
	end
	__AG_stealCbCache[prompt] = data
	return data
end

local function __AG_startStealHold(prompt)
	if not prompt or not prompt.Parent then return nil end
	pcall(function()
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = math.huge
		prompt.HoldDuration = 0
		if fireproximityprompt then
			fireproximityprompt(prompt)
		end
	end)

	local cb = __AG_buildStealCallbacks(prompt)
	if cb and cb.hold then
		for _, fn in ipairs(cb.hold) do task.spawn(fn) end
	end
	__AG_stealActive = true
	return {
		prompt         = prompt,
		cb             = cb or { hold = {}, trigger = {} },
		ragdollFireTime = tick(),
		holdBeganAt    = tick(),
		holdDone       = false,
	}
end

local function __AG_doHoldAndWait(ctx)
	if not ctx or ctx.holdDone then return end
	if ctx.cb and ctx.cb.hold then
		for _, fn in ipairs(ctx.cb.hold) do task.spawn(fn) end
	end
	ctx.holdBeganAt = tick()
	task.wait(__AG_MIN_HOLD_TIME)
	ctx.holdDone = true
end

local function __AG_finishStealHold(ctx)
	if not ctx then return false end
	if not ctx.holdBeganAt then __AG_doHoldAndWait(ctx) end
	local held = tick() - (ctx.holdBeganAt or tick())
	if held < __AG_MIN_HOLD_TIME then task.wait(__AG_MIN_HOLD_TIME - held) end
	task.wait(__AG_TRIGGER_DELAY)

	if ctx.cb and ctx.cb.trigger then
		for _, fn in ipairs(ctx.cb.trigger) do task.spawn(fn) end
	end

	if ctx.prompt and ctx.prompt.Parent then
		pcall(function()
			if fireproximityprompt then
				fireproximityprompt(ctx.prompt)
			end
		end)
	end

	__AG_stealActive = false
	return true
end

_ragdollCacheActivated = function(guiObject)
	local cached = {}
	local ok, conns = pcall(getconnections, guiObject.Activated)
	if ok and type(conns) == "table" then
		for _, conn in ipairs(conns) do
			if type(conn.Function) == "function" then
				table.insert(cached, conn.Function)
			end
		end
	end
	return cached
end

local _adminDealRemote = nil
local _GUID_CONSTANT = "5de09977-5fee-4669-bf61-a08ed7c0d38f"

local function _getAdminDealRemote()
	if _adminDealRemote and _adminDealRemote.Parent then return _adminDealRemote end
	pcall(function()
		local packagesNet = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("Net")
		if packagesNet then
			_adminDealRemote = packagesNet:FindFirstChild("RE/AdminPanelService/DealWithThis")
		end
		if not _adminDealRemote then
			local net = ReplicatedStorage:FindFirstChild("Net")
			if net then _adminDealRemote = net:FindFirstChild("RE/AdminPanelService/DealWithThis") end
		end
		if not _adminDealRemote then
			for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
				if desc:IsA("RemoteEvent") and desc.Name == "RE/AdminPanelService/DealWithThis" then
					_adminDealRemote = desc
					break
				end
			end
		end
	end)
	return _adminDealRemote
end

_ragdollSelf = function()
	local rem = _getAdminDealRemote()
	if rem then
		pcall(function()
			rem:FireServer(_GUID_CONSTANT, LocalPlayer, "ragdoll")
		end)
	end

	pcall(function()
		local commandFrame, profileFrame = _ragdollGetAdminFrames()
		if not commandFrame or not profileFrame then return end
		local pName = LocalPlayer.Name
		local profileBtn = profileFrame:FindFirstChild(pName)
		local ragdollBtn = commandFrame:FindFirstChild("ragdoll")
		if not profileBtn or not ragdollBtn then return end
		if not _ragdollProfileCache[pName] then
			_ragdollProfileCache[pName] = _ragdollCacheActivated(profileBtn)
		end
		if not _ragdollCommandCache["ragdoll"] then
			_ragdollCommandCache["ragdoll"] = _ragdollCacheActivated(ragdollBtn)
		end
		_ragdollFireActivated(_ragdollCommandCache["ragdoll"])
		task.wait()
		_ragdollFireActivated(_ragdollProfileCache[pName])
	end)
end

local ShowToggleNotification
do
	local _activeNotifs = {}
	local NOTIF_W, NOTIF_H, NOTIF_GAP, NOTIF_PAD_X, NOTIF_PAD_Y, NOTIF_DUR = 200, 44, 6, 14, 14, 2
	local T_White = Color3.fromRGB(245, 245, 245)
	local T_Border = Color3.fromRGB(45, 45, 45)

	local function _shadowTargetY(slotIdx)
		return -(NOTIF_PAD_Y + NOTIF_H + 4 + slotIdx * (NOTIF_H + NOTIF_GAP))
	end
	local function _repoAll(tweenInfo)
		for i, e in ipairs(_activeNotifs) do
			TweenService:Create(e.shadow, tweenInfo, {
				Position = UDim2.new(0, NOTIF_PAD_X - 4, 1, _shadowTargetY(i - 1))
			}):Play()
		end
	end

	local function Corner(p, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or 8)
		c.Parent = p
		return c
	end
	local function NStroke(p, col, th)
		local s = Instance.new("UIStroke")
		s.Color           = col or T_Border
		s.Thickness       = th or 1
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = p
		return s
	end
	local function NLabel(p, txt, sz, col, font)
		local l = Instance.new("TextLabel")
		l.Text              = txt or ""
		l.TextSize          = sz or 13
		l.TextColor3        = col or T_White
		l.Font              = font or Enum.Font.GothamMedium
		l.BackgroundTransparency = 1
		l.TextXAlignment    = Enum.TextXAlignment.Left
		l.Parent            = p
		return l
	end

	ShowToggleNotification = function(toggleName, enabled)
		local guiParent = LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("RaqFlashBlock")
		if not guiParent then return end

		local statusTxt = enabled and "Enabled" or "Disabled"
		local statusCol = enabled and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 100, 100)
		local IN_INFO   = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local OUT_INFO  = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		local BAR_INFO  = TweenInfo.new(NOTIF_DUR, Enum.EasingStyle.Linear)
		local FADE_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Linear)
		local REPO_INFO = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

		local shadow = Instance.new("Frame")
		shadow.Name                   = "ToastShadow"
		shadow.Size                   = UDim2.new(0, NOTIF_W + 8, 0, NOTIF_H + 8)
		shadow.Position               = UDim2.new(0, -(NOTIF_W + 32), 1, _shadowTargetY(0))
		shadow.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
		shadow.BackgroundTransparency = 0.12
		shadow.BorderSizePixel        = 0
		shadow.ZIndex                 = 99
		shadow.Parent                 = guiParent
		Corner(shadow, 12)

		local toast = Instance.new("Frame")
		toast.Name                   = "ToastNotif"
		toast.Size                   = UDim2.new(0, NOTIF_W, 0, NOTIF_H)
		toast.Position               = UDim2.new(0, 4, 0, 4)
		toast.BackgroundColor3       = Color3.fromRGB(18, 18, 18)
		toast.BackgroundTransparency = 1
		toast.BorderSizePixel        = 0
		toast.ZIndex                 = 100
		toast.Parent                 = shadow
		Corner(toast, 10)
		local _stroke = NStroke(toast, Color3.fromRGB(55, 55, 55), 1); _stroke.Transparency = 1

		local pill = Instance.new("Frame")
		pill.Size             = UDim2.new(0, 3, 0, NOTIF_H - 16)
		pill.Position         = UDim2.new(0, 9, 0.5, -(NOTIF_H - 16) / 2)
		pill.BackgroundColor3 = T_White
		pill.BorderSizePixel  = 0
		pill.ZIndex           = 101
		pill.Parent           = toast
		Corner(pill, 2)

		local nameLabel = NLabel(toast, toggleName, 11, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)
		nameLabel.Size = UDim2.new(1, -24, 0, 15); nameLabel.Position = UDim2.new(0, 19, 0, 7)
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd; nameLabel.TextTransparency = 1; nameLabel.ZIndex = 101

		local statusLabel = NLabel(toast, statusTxt, 10, statusCol, Enum.Font.Gotham)
		statusLabel.Size = UDim2.new(1, -24, 0, 11); statusLabel.Position = UDim2.new(0, 19, 0, 23)
		statusLabel.TextTransparency = 1; statusLabel.ZIndex = 101

		local barTrack = Instance.new("Frame")
		barTrack.Size = UDim2.new(1, 0, 0, 2); barTrack.Position = UDim2.new(0, 0, 1, -2)
		barTrack.BackgroundColor3 = Color3.fromRGB(35, 35, 35); barTrack.BorderSizePixel = 0
		barTrack.ZIndex = 101; barTrack.Parent = toast

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(1, 0, 1, 0); barFill.BackgroundColor3 = T_White
		barFill.BorderSizePixel = 0; barFill.ZIndex = 102; barFill.Parent = barTrack

		local entry = { shadow = shadow }
		table.insert(_activeNotifs, 1, entry)
		_repoAll(REPO_INFO)
		TweenService:Create(shadow, IN_INFO, {Position = UDim2.new(0, NOTIF_PAD_X - 4, 1, _shadowTargetY(0))}):Play()
		TweenService:Create(toast,       IN_INFO, {BackgroundTransparency = 0}):Play()
		TweenService:Create(_stroke,     IN_INFO, {Transparency = 0.3}):Play()
		TweenService:Create(nameLabel,   IN_INFO, {TextTransparency = 0}):Play()
		TweenService:Create(statusLabel, IN_INFO, {TextTransparency = 0}):Play()
		task.delay(0.1, function() TweenService:Create(barFill, BAR_INFO, {Size = UDim2.new(0, 0, 1, 0)}):Play() end)
		task.delay(NOTIF_DUR + 0.15, function()
			for i, e in ipairs(_activeNotifs) do if e == entry then table.remove(_activeNotifs, i); break end end
			_repoAll(REPO_INFO)
			local exitY = shadow.Position.Y.Offset
			TweenService:Create(shadow, OUT_INFO, {Position = UDim2.new(0, -(NOTIF_W + 32), 1, exitY)}):Play()
			TweenService:Create(toast,       FADE_INFO, {BackgroundTransparency = 1}):Play()
			TweenService:Create(nameLabel,   FADE_INFO, {TextTransparency = 1}):Play()
			local tw = TweenService:Create(statusLabel, FADE_INFO, {TextTransparency = 1})
			tw:Play()
			tw.Completed:Connect(function() shadow:Destroy() end)
		end)
	end
end

local resetCooldown = false
local function doReset()
	if resetCooldown then return end
	resetCooldown = true

	local char = LocalPlayer.Character
	if not char then
		resetCooldown = false
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
	if not hrp then
		resetCooldown = false
		return
	end

	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.new(-337.938599, -0.585044861, 106.739204, 0.133411571, -0.379638135, 0.915465117, 0, 0.923722506, 0.383062422, -0.991060734, -0.0511049591, 0.123235278)
		cam.Focus = CFrame.new(-349.381927, -5.37332535, 105.198761, 1, 0, 0, 0, 1, 0, 0, 0, 1)

		task.delay(0.1, function()
			if cam then
				cam.CameraType = Enum.CameraType.Custom
				if hum then cam.CameraSubject = hum end
			end
		end)
	end

	if hum then
		hum.BreakJointsOnDeath = true
		hum.PlatformStand = true
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end

	hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	hrp.AssemblyLinearVelocity = Vector3.new(0, 1000000, 0)

	task.delay(0.5, function()
		resetCooldown = false
	end)
end

_G._FH_DoSelectedReset = doReset

local function doFlash()
	local lp  = LocalPlayer
	local chr = lp and lp.Character
	local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local PODIUM_CFRAMES = {
		[1] = {
			[1] = {
				hrp = CFrame.new(Vector3.new(-347.6983, -7.5033, -4.5494)),
				cam = CFrame.new(-357.0927, 0.0048, -0.272)
					* CFrame.Angles(-0.954463, -0.903625, -0.837019),
			},
			[2] = { hrp = CFrame.new(0,0,0), cam = nil },
			[3] = { hrp = CFrame.new(0,0,0), cam = nil },
			[4] = { hrp = CFrame.new(0,0,0), cam = nil },
			[5] = { hrp = CFrame.new(0,0,0), cam = nil },
		},
		[2] = {
			[1] = { hrp = CFrame.new(Vector3.new(-349.9259, -7.3841, -1.578)), cam = CFrame.new(-361.8253, 1.3324, 5.126) * CFrame.Angles(-0.824269, -0.878251, -0.693896) },
			[2] = { hrp = CFrame.new(Vector3.new(-348.4448, -7.1043, 3.3442)), cam = CFrame.new(-358.5857, -0.0841, 9.5148) * CFrame.Angles(-0.732523, -0.884924, -0.608084) },
			[3] = { hrp = CFrame.new(-346.1821, -7.2885, -1.609) * CFrame.Angles(0, -1.247212, 0), cam = CFrame.new(-360.1625, 0.6353, 3.1776) * CFrame.Angles(-0.932656, -1.049154, -0.86316) },
			[4] = { hrp = CFrame.new(-343.6695, -7.0385, 10.3377) * CFrame.Angles(0, -0.982332, 0), cam = CFrame.new(-356.477, -0.7795, 18.8846) * CFrame.Angles(-0.510736, -0.917793, -0.418726) },
			[5] = { hrp = CFrame.new(-343.7608, -7.4124, -9.7994) * CFrame.Angles(0, -1.544676, 0), cam = CFrame.new(-359.4998, -2.4726, -9.2893) * CFrame.Angles(-1.424811, -1.351549, -1.421283) },
			[6] = { hrpWalk = CFrame.new(-348.2407, -7.5033, 74.3719), hrp = CFrame.new(-325.655, -7.5033, 54.5488) * CFrame.Angles(0, -0.69115, 0), cam = CFrame.new(-338.7595, -4.0265, 70.3894) * CFrame.Angles(-0.126016, -0.687243, -0.080199) },
			[7] = { hrpWalk = CFrame.new(-348.2407, -7.5033, 74.3719), hrp = CFrame.new(-344.4383, -7.5033, 41.8672) * CFrame.Angles(0, -1.108982, 0), cam = CFrame.new(-362.8094, -4.325, 51.1551) * CFrame.Angles(-0.181885, -1.095968, -0.162135) },
			[8] = { hrpWalk = CFrame.new(-348.2407, -7.5033, 74.3719), hrp = CFrame.new(-348.5228, -7.5033, 48.1022) * CFrame.Angles(0, -0.939336, 0), cam = CFrame.new(-363.5051, -2.5713, 59.0596) * CFrame.Angles(-0.30602, -0.916511, -0.245634) },
			[9] = { hrp = CFrame.new(-339.6349, -7.5033, 60.4164) * CFrame.Angles(0, -0.405266, 0), cam = CFrame.new(-346.7646, -3.7365, 77.0351) * CFrame.Angles(-0.137335, -0.401849, -0.054002) },
			[10] = { hrp = CFrame.new(-339.4453, -7.5033, 61.9429) * CFrame.Angles(0, -0.29845, 0), cam = CFrame.new(-342.5024, -5.2211, 71.8802) * CFrame.Angles(-0.081543, -0.297517, -0.023953) },
			[11] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-331.5262, -7.5033, -47.3607) * CFrame.Angles(0, 0.003141, 0), cam = CFrame.new(-331.4885, -9.6045, -59.3396) * CFrame.Angles(2.851853, -0.097011, -3.140695) },
			[12] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-338.729, -7.5033, -43.4714) * CFrame.Angles(0, -1.420208, 0), cam = CFrame.new(-345.1804, -9.9578, -56.8524) * CFrame.Angles(2.856299, -0.433315, 3.01906) },
			[13] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-334.5183, -7.5033, -41.6819) * CFrame.Angles(0, -0.543495, 0), cam = CFrame.new(-341.912, -9.959, -53.9192) * CFrame.Angles(2.831168, -0.52207, 2.982964) },
			[14] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-319.8298, -7.5033, -45.1476) * CFrame.Angles(0, -0.323585, 0), cam = CFrame.new(-323.983, -9.9618, -57.5315) * CFrame.Angles(2.834406, -0.309406, 3.045298) },
			[15] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-317.917, -7.5033, -41.9999) * CFrame.Angles(0, -0.565487, 0), cam = CFrame.new(-325.8, -9.9581, -54.4216) * CFrame.Angles(2.835549, -0.544183, 2.979445) },
			[16] = { hrp = CFrame.new(-338.285, -7.5033, 57.204) * CFrame.Angles(0, -0.207346, 0), cam = CFrame.new(-340.4345, -9.5916, 67.4219) * CFrame.Angles(0.335111, -0.196113, 0.067755) },
			[17] = { hrp = CFrame.new(-337.9285, -7.5033, 55.1757) * CFrame.Angles(0, -0.430398, 0), cam = CFrame.new(-341.7441, -8.9535, 63.4867) * CFrame.Angles(0.337895, -0.408747, 0.138758) },
			[18] = { hrp = CFrame.new(-332.1088, -7.5033, 53.1675) * CFrame.Angles(0, -0.49323, 0), cam = CFrame.new(-336.3932, -9.2396, 61.1377) * CFrame.Angles(0.382481, -0.462609, 0.177644) },
			[19] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-328.579, -3.1209, -35.0857) * CFrame.Angles(0, 0.021988, 0), cam = CFrame.new(-328.5137, -10.011, -45.4753) * CFrame.Angles(2.387391, -0.004579, 3.137291) },
			[20] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-321.5783, -7.5033, -33.5778) * CFrame.Angles(0, 0.006284, 0), cam = CFrame.new(-321.5535, -10.0218, -37.5259) * CFrame.Angles(2.387391, -0.004579, 3.137291) },
			[21] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-314.088, -7.5033, -32.1806) * CFrame.Angles(0, -0.006282, 0), cam = CFrame.new(-314.1147, -10.0174, -36.4214) * CFrame.Angles(2.387391, -0.004579, 3.137291) },
			[22] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-306.8919, -7.5033, -33.9124) * CFrame.Angles(0, -0.006284, 0), cam = CFrame.new(-306.923, -10.008, -38.86) * CFrame.Angles(2.4648, -0.004898, 3.137657) },
			[23] = { hrpWalk = CFrame.new(-351.5396, -7.5033, -41.797), hrp = CFrame.new(-300.2759, -7.5033, -32.7047) * CFrame.Angles(0, -0.031416, 0), cam = CFrame.new(-300.4669, -10.016, -37.044) * CFrame.Angles(2.399014, -0.032413, 3.111857) },
			[24] = { hrpWalk = CFrame.new(-348.2407, -7.5033, 74.3719), hrp = CFrame.new(-330.0484, -7.5033, 48.183) * CFrame.Angles(0, -0.006377, 0), cam = CFrame.new(-330.1124, -10.0063, 53.2779) * CFrame.Angles(0.662308, -0.00991, 0.007727) },
			[25] = { hrpWalk = CFrame.new(-348.2407, -7.5033, 74.3719), hrp = CFrame.new(-325.4576, -7.5033, 46.8182) * CFrame.Angles(0, -0.125663, 0), cam = CFrame.new(-326.0541, -10.0104, 51.5397) * CFrame.Angles(0.700033, -0.09632, 0.080833) },
			[26] = { hrpWalk = CFrame.new(-348.2407, -7.5033, 74.3719), hrp = CFrame.new(-324.6721, -7.5033, 47.2033) * CFrame.Angles(0, -0.40212, 0), cam = CFrame.new(-326.6859, -10.0057, 51.9385) * CFrame.Angles(0.698024, -0.314979, 0.254268) },
			[27] = { hrpWalk = CFrame.new(-348.2407, -7.5033, 74.3719), hrp = CFrame.new(-320.4196, -7.5033, 44.1) * CFrame.Angles(0, -0.571769, 0), cam = CFrame.new(-322.9213, -10.0122, 49.5157) * CFrame.Angles(0.876985, -0.422603, 0.397417) },
			[28] = { hrpWalk = CFrame.new(-348.2407, -7.5033, 74.3719), hrp = CFrame.new(-305.1093, 0.4133, 50.1513) * CFrame.Angles(-0.000000, -0.255980, -0.000000), cam = CFrame.new(-307.6093, -2.0867, 55.5513) * CFrame.Angles(0.876985, -0.255980, 0.397417) },
		},
	}

		local myBase = nil
		local plotsFolder = workspace:FindFirstChild("Plots")
		if plotsFolder then
			for _, plot in ipairs(plotsFolder:GetChildren()) do
				if plot:IsA("Model") then
					local sign = plot:FindFirstChild("PlotSign")
					if sign and sign:FindFirstChild("YourBase") and sign.YourBase.Enabled then
						local ok, order = pcall(function() return plot:GetAttribute("Order") end)
						if ok and order then myBase = tonumber(order) end
						break
					end
				end
			end
		end

		if not myBase then
			pcall(ShowToggleNotification, "Flash: base not detected", false)
			return
		end

		local targetBase = (myBase == 1) and 2 or 1
		local podiumCFs = PODIUM_CFRAMES[targetBase]
		if not podiumCFs then return end

		local selected = _G._FH_SelectedBrainrot
		if not selected then
			pcall(ShowToggleNotification, "Flash: select an animal first", false)
			return
		end

		local slot = tonumber(selected.slot)
		if not slot then
			pcall(ShowToggleNotification, "Flash: selected animal has no slot", false)
			return
		end

		local entry = podiumCFs[slot]
		if not entry or not entry.cam then
			pcall(ShowToggleNotification, "Flash: podium " .. tostring(slot) .. " not configured yet", false)
			return
		end

		if BypassAutoDefense then
			-- Block/Protect for 0.5s right before triggering Flash TP to bypass auto block defense
			task.spawn(function()
				pcall(doBlock)
			end)
			task.wait(0.5)
		end

		task.spawn(function()
			local currentSpeed = entry.hrpFloat and 800 or 180
			local ARRIVE_DIST  = 4
			local TIMEOUT      = 8

		local player    = LocalPlayer
		local targetPos = (entry.hrpWalk and entry.hrpWalk.Position) or entry.hrp.Position

		local function findTool(kw)
			local c = player.Character
			local b = player:FindFirstChild("Backpack")
			if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") and t.Name:lower():find(kw) then return t end end end
			if b then for _, t in ipairs(b:GetChildren()) do if t:IsA("Tool") and t.Name:lower():find(kw) then return t end end end
		end

		local function doEquip(tool, timeout)
			local c = player.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if not (c and h) then return end
			if tool.Parent == c then return end
			local done = false
			local cn
			cn = tool.Equipped:Connect(function() done = true; cn:Disconnect() end)
			pcall(function() h:EquipTool(tool) end)
			local dl = tick() + (timeout or 1)
			while not done and tick() < dl do task.wait() end
			if cn then pcall(function() cn:Disconnect() end) end
		end

		local carpet = findTool("carpet")
		if carpet then doEquip(carpet, 1) end

		local stealCtx     = nil
		local _lateGrabSlots = {[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,
								 [19]=true,[20]=true,[21]=true,[22]=true,[23]=true}
		if not _lateGrabSlots[slot] then
			task.spawn(function()
				local chr3 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local dest = (entry.hrpWalk and entry.hrpWalk.Position) or entry.hrp.Position
				local dist = chr3 and (chr3.Position - dest).Magnitude or 0
				local POST_ARRIVAL = 0.10 + 0.15 + 0.07 + 0.30 + 0.12
				local travelTime   = dist / math.max(currentSpeed, 1)
				local timeUntilFire = travelTime + POST_ARRIVAL
				local preDelay     = math.max(0, timeUntilFire - __AG_MIN_HOLD_TIME)
				if preDelay > 0 then task.wait(preDelay) end
				local targetPrompt = __AG_findTargetPrompt()
				if targetPrompt then stealCtx = __AG_startStealHold(targetPrompt) end
			end)
		end

		local boostConn
		boostConn = RunService.Heartbeat:Connect(function()
			if not player.Character then return end
			local hrpB = player.Character:FindFirstChild("HumanoidRootPart")
			local humB = player.Character:FindFirstChildOfClass("Humanoid")
			if not hrpB or not humB then return end
			local diff = targetPos - hrpB.Position
			local flat = Vector3.new(diff.X, 0, diff.Z)
			if flat.Magnitude > ARRIVE_DIST then
				local flatDir = flat.Unit
				hrpB.Velocity = Vector3.new(flatDir.X * currentSpeed, hrpB.Velocity.Y, flatDir.Z * currentSpeed)
			else
				hrpB.Velocity = Vector3.new(0, hrpB.Velocity.Y, 0)
			end
		end)

		local chr2 = player.Character
		local hum2 = chr2 and chr2:FindFirstChildOfClass("Humanoid")
		if hum2 then hum2:MoveTo(targetPos) end

		local deadline = tick() + TIMEOUT
		local _lastMoveTo = 0
		repeat
			task.wait()
			chr2 = player.Character
			local hrp2 = chr2 and chr2:FindFirstChild("HumanoidRootPart")
			hum2       = chr2 and chr2:FindFirstChildOfClass("Humanoid")
			if not (hrp2 and hum2) then break end
			local _now = tick()
			if _now - _lastMoveTo >= 0.1 then hum2:MoveTo(targetPos); _lastMoveTo = _now end
			if (hrp2.Position - targetPos).Magnitude < ARRIVE_DIST then break end
		until tick() > deadline

		if boostConn then boostConn:Disconnect(); boostConn = nil end

		local function snapAndRelease(cf)
			local _chr = player.Character
			local _hrp = _chr and _chr:FindFirstChild("HumanoidRootPart")
			local _hum = _chr and _chr:FindFirstChildOfClass("Humanoid")
			if _hrp and _hum then
				_hum:MoveTo(_hrp.Position)
				_hrp.Velocity = Vector3.zero
				_hrp.Anchored = true
				task.defer(function() task.defer(function()
					local c = player.Character
					local h = c and c:FindFirstChild("HumanoidRootPart")
					if h then h.Velocity = Vector3.zero; h.Anchored = false end
				end) end)
			end
		end

		if _lateGrabSlots[slot] then
			task.spawn(function()
				local _chr3 = player.Character
				local _hrp3 = _chr3 and _chr3:FindFirstChild("HumanoidRootPart")
				local _finalP = entry.hrp.Position
				local _d2 = _hrp3 and (_hrp3.Position - _finalP).Magnitude or 0
				local _POST2 = 0.10 + 0.15 + 0.07 + 0.30 + 0.12
				local _pre2 = math.max(0, (_d2 / math.max(currentSpeed, 1)) + _POST2 - __AG_MIN_HOLD_TIME)
				if _pre2 > 0 then task.wait(_pre2) end
				local _tp = __AG_findTargetPrompt()
				if _tp then stealCtx = __AG_startStealHold(_tp) end
			end)
		end

		if entry.hrpWalk then
			local finalPos = entry.hrp.Position
			local boostConn2
			boostConn2 = RunService.Heartbeat:Connect(function()
				if not player.Character then return end
				local hrp3 = player.Character:FindFirstChild("HumanoidRootPart")
				if not hrp3 then return end
				local diff3 = finalPos - hrp3.Position
				local flat3 = Vector3.new(diff3.X, 0, diff3.Z)
				if flat3.Magnitude > ARRIVE_DIST then
					local fd = flat3.Unit
					hrp3.Velocity = Vector3.new(fd.X * currentSpeed, hrp3.Velocity.Y, fd.Z * currentSpeed)
				else
					hrp3.Velocity = Vector3.new(0, hrp3.Velocity.Y, 0)
				end
			end)
			chr2 = player.Character; hum2 = chr2 and chr2:FindFirstChildOfClass("Humanoid")
			if hum2 then hum2:MoveTo(finalPos) end
			local deadline2 = tick() + TIMEOUT
			local _lastMoveTo2 = 0
			repeat
				task.wait()
				chr2 = player.Character
				local hrp2b = chr2 and chr2:FindFirstChild("HumanoidRootPart")
				hum2 = chr2 and chr2:FindFirstChildOfClass("Humanoid")
				if not (hrp2b and hum2) then break end
				local _now2 = tick()
				if _now2 - _lastMoveTo2 >= 0.1 then hum2:MoveTo(finalPos); _lastMoveTo2 = _now2 end
				if (hrp2b.Position - finalPos).Magnitude < ARRIVE_DIST then break end
			until tick() > deadline2
			boostConn2:Disconnect()
			chr2 = player.Character; hum2 = chr2 and chr2:FindFirstChildOfClass("Humanoid")
			local hrpStop = chr2 and chr2:FindFirstChild("HumanoidRootPart")
			if hrpStop and hum2 then
				hrpStop.CFrame = entry.hrp; hrpStop.Velocity = Vector3.zero; hrpStop.Anchored = true
				task.defer(function() task.defer(function()
					local _c = player.Character; local _h = _c and _c:FindFirstChild("HumanoidRootPart")
					if _h then _h.Velocity = Vector3.zero; _h.Anchored = false end
				end) end)
			end
		else
			chr2 = player.Character; hum2 = chr2 and chr2:FindFirstChildOfClass("Humanoid")
			local hrpStop = chr2 and chr2:FindFirstChild("HumanoidRootPart")
			if hrpStop and hum2 then
				hrpStop.CFrame = entry.hrp; hrpStop.Velocity = Vector3.zero; hrpStop.Anchored = true
				task.defer(function() task.defer(function()
					local _c = player.Character; local _h = _c and _c:FindFirstChild("HumanoidRootPart")
					if _h then _h.Velocity = Vector3.zero; _h.Anchored = false end
				end) end)
			end
		end

		local cam = workspace.CurrentCamera
		if cam and entry.cam then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = entry.cam
			task.defer(function()
				cam.CFrame = entry.cam
				task.defer(function()
					cam.CFrame = entry.cam
					cam.CameraType = Enum.CameraType.Custom
				end)
			end)
		end

		local carpetMid = findTool("carpet")
		if carpetMid then doEquip(carpetMid, 1.5) end
		task.wait(0.35)

		if (slot >= 19 and slot <= 28) then
			local hrpJump = chr2 and chr2:FindFirstChild("HumanoidRootPart")
			if hrpJump then
				hrpJump.AssemblyLinearVelocity = Vector3.new(hrpJump.AssemblyLinearVelocity.X, 55, hrpJump.AssemblyLinearVelocity.Z)
			end
			if hum2 then
				hum2:ChangeState(Enum.HumanoidStateType.Jumping)
			end
			task.wait(0.08)
		end

		chr2 = player.Character; hum2 = chr2 and chr2:FindFirstChildOfClass("Humanoid")
		if not (chr2 and hum2) then return end

		local flashTool = nil
		local bp = player:FindFirstChild("Backpack")
		if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") and t.Name:lower():find("flash") then flashTool = t; break end end end
		if not flashTool then for _, t in ipairs(chr2:GetChildren()) do if t:IsA("Tool") and t.Name:lower():find("flash") then flashTool = t; break end end end

		if not flashTool then
			pcall(ShowToggleNotification, "Flash: tool not found in inventory", false)
			return
		end

		pcall(function() hum2:UnequipTools() end)
		task.wait(0.07)

		local _flashEquipped = false
		local _flashEquipConn
		_flashEquipConn = flashTool.Equipped:Connect(function()
			_flashEquipped = true; _flashEquipConn:Disconnect(); _flashEquipConn = nil
		end)
		flashTool.Parent = chr2
		pcall(function() hum2:EquipTool(flashTool) end)
		local _eqDeadline = tick() + 1
		while not _flashEquipped and tick() < _eqDeadline do task.wait() end
		if _flashEquipConn then pcall(function() _flashEquipConn:Disconnect() end) end

		pcall(function() flashTool:Activate() end)

		task.spawn(function()
			triggerAutoBlock()
			if not RagdollBypassEnabled then
				if stealCtx then
					__AG_finishStealHold(stealCtx)
				elseif type(_G._sv2DoSteal) == "function" then
					pcall(_G._sv2DoSteal)
				end
			end
		end)

		task.wait(0.02)
		pcall(function() flashTool:Activate() end)
		task.wait(0.08)

		if hum2 then pcall(function() hum2:UnequipTools() end) end
		task.wait(0.05)
		local bp2 = player:FindFirstChild("Backpack")
		if bp2 and flashTool and flashTool.Parent ~= bp2 then flashTool.Parent = bp2 end

		if RagdollBypassEnabled then
			task.spawn(function()
				pcall(_ragdollSelf)
				triggerAutoBlock()

				local _kicked     = false
				local _kickConn1, _kickConn2
				local _tgtPlayer  = getPlotOwnerPlayer()
				local _tgtChar    = _tgtPlayer and _tgtPlayer.Character
				local _tgtHum     = _tgtChar and _tgtChar:FindFirstChildOfClass("Humanoid")
				local function _onKicked()
					if _kicked then return end
					_kicked = true
					if _kickConn1 then pcall(function() _kickConn1:Disconnect() end); _kickConn1 = nil end
					if _kickConn2 then pcall(function() _kickConn2:Disconnect() end); _kickConn2 = nil end
					local _wf = 0
					while not stealCtx and _wf < 3 do task.wait(); _wf = _wf + 1 end
					if not stealCtx then
						local _fp = __AG_findTargetPrompt()
						if _fp then stealCtx = __AG_startStealHold(_fp) end
					end
					if stealCtx then
						__AG_finishStealHold(stealCtx)
					elseif type(_G._sv2DoSteal) == "function" then
						pcall(_G._sv2DoSteal)
					end
				end
				if _tgtHum then
					_kickConn1 = _tgtHum.StateChanged:Connect(function(_, new)
						if new == Enum.HumanoidStateType.Physics
							or new == Enum.HumanoidStateType.Ragdoll
							or new == Enum.HumanoidStateType.FallingDown then
							_onKicked()
						end
					end)
					_kickConn2 = _tgtHum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
						if _tgtHum.PlatformStand then _onKicked() end
					end)
				end
				task.delay(0.35, _onKicked)

				local carpetFinal = findTool("carpet")
				if carpetFinal then doEquip(carpetFinal, 1) end
			end)
		end

		pcall(ShowToggleNotification, "Flash -> Base " .. targetBase .. " Podium " .. slot, true)
	end)
end

local function doBlock()
	local target = getPlotOwnerPlayer() or getNearestPlayer()
	if target then
		pcall(blockPlayer, target)
		pcall(ShowToggleNotification, "Blocked: " .. target.Name, true)
	else
		pcall(ShowToggleNotification, "Block: no players nearby", false)
	end
end

_G._FH_ResetBtnEntry = { fire = doReset }
_G._FH_FlashBtnEntry = { fire = doFlash }
_G._FH_BlockBtnEntry = { fire = doBlock }

do
	local _afPending = false

	local function tryAutoFlash()
		if not AutoFlashEnabled then return end
		if not _G._FH_SelectedBrainrot then
			pcall(ShowToggleNotification, "Auto Flash: no animal selected", false)
			return
		end
		if _afPending then return end
		_afPending = true

		task.spawn(function()
			pcall(ShowToggleNotification, "Auto Flash: resetting...", true)
			if _G._FH_DoSelectedReset then pcall(_G._FH_DoSelectedReset) end

			local deadline = tick() + 8
			while (not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) and tick() < deadline do
				task.wait(0.1)
			end
			if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
				_afPending = false; return
			end

			task.wait(0.15)
			if not AutoFlashEnabled then _afPending = false; return end
			if not _G._FH_SelectedBrainrot then _afPending = false; return end

			pcall(ShowToggleNotification, "Auto Flash: flashing!", true)
			if _G._FH_FlashBtnEntry then pcall(_G._FH_FlashBtnEntry.fire) end

			task.wait(3)
			_afPending = false
		end)
	end

	local _afBoundRemotes = {}
	local _afLastBalloon  = 0
	local function _afBindRemote(obj)
		if not obj:IsA("RemoteEvent") then return end
		if _afBoundRemotes[obj] then return end
		local ok, conn = pcall(function()
			return obj.OnClientEvent:Connect(function(...)
				if not AutoFlashEnabled then return end
				for i = 1, select("#", ...) do
					local arg = select(i, ...)
					if type(arg) == "string" and arg:lower():find("jump higher", 1, true) then
						local now = tick()
						if now - _afLastBalloon < 3 then return end
						_afLastBalloon = now
						tryAutoFlash()
						return
					end
				end
			end)
		end)
		if ok and conn then _afBoundRemotes[obj] = conn end
	end
	for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do _afBindRemote(obj) end
	ReplicatedStorage.DescendantAdded:Connect(function(obj) _afBindRemote(obj) end)
end

local function create(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	if children then for _, child in ipairs(children) do child.Parent = inst end end
	return inst
end

local function makeToggleRow(title, desc, callback)
	local row = create("Frame", {
		Name = title:gsub(" ", ""),
		Size = UDim2.new(1, -16, 0, 38),
		BackgroundColor3 = Color3.fromRGB(25, 25, 25),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 6) }).Parent = row
	create("UIStroke", { Color = Color3.fromRGB(55, 55, 55), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }).Parent = row

	local accent = create("Frame", {
		Size = UDim2.new(0, 3, 0, 28), Position = UDim2.new(0, 0, 0, 5),
		BackgroundColor3 = Color3.fromRGB(45, 45, 45), BorderSizePixel = 0, ZIndex = 2,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 2) }).Parent = accent
	accent.Parent = row

	create("TextLabel", {
		Size = UDim2.new(1, -80, 0, 12), Position = UDim2.new(0, 10, 0, 5),
		BackgroundTransparency = 1, ZIndex = 2, Text = title,
		TextColor3 = Color3.fromRGB(245, 245, 245), TextSize = 9,
		Font = Enum.Font.GothamMedium,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}).Parent = row

	create("TextLabel", {
		Size = UDim2.new(1, -80, 0, 10), Position = UDim2.new(0, 10, 0, 18),
		BackgroundTransparency = 1, ZIndex = 2, Text = desc,
		TextColor3 = Color3.fromRGB(110, 110, 110), TextSize = 8,
		Font = Enum.Font.Gotham,
		FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}).Parent = row

	create("TextLabel", {
		Size = UDim2.new(0, 24, 0, 12), Position = UDim2.new(1, -64, 0.5, -6),
		BackgroundTransparency = 1, ZIndex = 3, Text = "",
		TextColor3 = Color3.fromRGB(110, 110, 110), Font = Enum.Font.GothamBold,
	}).Parent = row

	local track = create("Frame", {
		Name = "Track", Size = UDim2.new(0, 28, 0, 15), Position = UDim2.new(1, -36, 0.5, -7),
		BackgroundColor3 = Color3.fromRGB(45, 45, 45), BorderSizePixel = 0, ZIndex = 2,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 7) }).Parent = track
	create("UIStroke", { Color = Color3.fromRGB(55, 55, 55), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }).Parent = track

	local knob = create("Frame", {
		Name = "Knob", Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, 2, 0.5, -5),
		BackgroundColor3 = Color3.fromRGB(160, 160, 160), BorderSizePixel = 0, ZIndex = 3,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 5) }).Parent = knob
	knob.Parent = track
	track.Parent = row

	local hitbox = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 4, Active = true,
	})
	hitbox.Parent = row

	local toggled = false
	hitbox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			toggled = not toggled
			local goalPos   = toggled and UDim2.new(0, 15, 0.5, -5) or UDim2.new(0, 2, 0.5, -5)
			local goalTrack = toggled and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(45, 45, 45)
			local goalKnob  = toggled and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(160, 160, 160)
			local goalAccent= toggled and Color3.fromRGB(245, 245, 245) or Color3.fromRGB(45, 45, 45)
			local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(knob, info, { Position = goalPos, BackgroundColor3 = goalKnob }):Play()
			TweenService:Create(track, info, { BackgroundColor3 = goalTrack }):Play()
			TweenService:Create(accent, info, { BackgroundColor3 = goalAccent }):Play()
			if callback then task.spawn(function() pcall(callback, toggled) end) end
			pcall(ShowToggleNotification, title, toggled)
		end
	end)

	return row
end

-- ==========================================
-- GUI DESIGN - HUGO NOIR THEME
-- ==========================================
for _, gName in ipairs({"V7_SCRIPT", "HUGO'S SCRIPT", "RaqFlashBlock", "AceFreeInstaReset"}) do
    local g = LocalPlayer.PlayerGui:FindFirstChild(gName)
    if g then pcall(function() g:Destroy() end) end
    pcall(function()
        local cg = game:GetService("CoreGui"):FindFirstChild(gName)
        if cg then cg:Destroy() end
    end)
end

local C = {
    accent    = Color3.fromRGB(80, 80, 90),
    accentHi  = Color3.fromRGB(100, 100, 110),
    deepBlue  = Color3.fromRGB(10, 10, 12),
    body      = Color3.fromRGB(8, 8, 10),
    panel     = Color3.fromRGB(12, 12, 15),
    tabBar    = Color3.fromRGB(10, 10, 12),
    card      = Color3.fromRGB(20, 20, 25),
    iconBg    = Color3.fromRGB(25, 25, 30),
    stroke    = Color3.fromRGB(40, 40, 50),
    strokeDim = Color3.fromRGB(35, 35, 45),
    textBright= Color3.fromRGB(220, 220, 230),
    textBlue  = Color3.fromRGB(180, 180, 190),
    textMute  = Color3.fromRGB(130, 130, 140),
    textDim   = Color3.fromRGB(90, 90, 100),
    knobOn    = Color3.fromRGB(100, 100, 110),
    knobOff   = Color3.fromRGB(60, 60, 70),
    trackOff  = Color3.fromRGB(30, 30, 38),
}

local borderGradientSeq = ColorSequence.new({
    ColorSequenceKeypoint.new(0, C.accentHi),
    ColorSequenceKeypoint.new(0.25, C.deepBlue),
    ColorSequenceKeypoint.new(0.5, C.accent),
    ColorSequenceKeypoint.new(0.75, C.deepBlue),
    ColorSequenceKeypoint.new(1, C.accentHi),
})

local function getDevice()
    local screen = workspace.CurrentCamera.ViewportSize
    local w, h = screen.X, screen.Y
    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    if isMobile then
        if w >= 900 or h >= 900 then return "ipad" end
        return "mobile"
    end
    return "pc"
end

local function getScaleFactor()
    local screen = workspace.CurrentCamera.ViewportSize
    local baseW = 1920
    local baseH = 1080
    local scaleW = screen.X / baseW
    local scaleH = screen.Y / baseH
    local s = math.min(scaleW, scaleH)
    s = math.clamp(s, 0.45, 1.6)
    return s
end

local DEVICE = getDevice()
local BASE_LAYOUT = {
    pc = {
        winW = 310, winH = 420,
        posX = UDim2.new(0.5, 0, 0.5, 0),
        btnSize = 94, btnH = 40,
        tabH = 32, headerH = 47,
        actionBarY = 34, actionBarH = 69,
        actionDividerY = 55,
        frame2Y = 90, frame2Offset = -94,
        tabBarY = 90,
        contentDividerY = 121,
        contentY = 122, contentOffsetH = -126,
        actionXs = {8, 108, 208},
        textSize = { header = 11, btn = 12, tab = 12 },
    },
    ipad = {
        winW = 280, winH = 390,
        posX = UDim2.new(0.5, 0, 0.5, 0),
        btnSize = 83, btnH = 38,
        tabH = 30, headerH = 45,
        actionBarY = 32, actionBarH = 64,
        actionDividerY = 50,
        frame2Y = 82, frame2Offset = -86,
        tabBarY = 82,
        contentDividerY = 111,
        contentY = 112, contentOffsetH = -116,
        actionXs = {7, 96, 185},
        textSize = { header = 11, btn = 11, tab = 11 },
    },
    mobile = {
        winW = 240, winH = 330,
        posX = UDim2.new(0.5, 0, 0.5, 0),
        btnSize = 70, btnH = 36,
        tabH = 28, headerH = 42,
        actionBarY = 28, actionBarH = 58,
        actionDividerY = 44,
        frame2Y = 72, frame2Offset = -76,
        tabBarY = 72,
        contentDividerY = 99,
        contentY = 100, contentOffsetH = -104,
        actionXs = {6, 82, 158},
        textSize = { header = 10, btn = 10, tab = 10 },
    },
}

local function buildScaledLayout(device)
    local base = BASE_LAYOUT[device]
    local s = getScaleFactor()
    return {
        winW = math.floor(base.winW * s),
        winH = math.floor(base.winH * s),
        posX = base.posX,
        btnSize = math.floor(base.btnSize * s),
        btnH = math.floor(base.btnH * s),
        tabH = math.floor(base.tabH * s),
        headerH = math.floor(base.headerH * s),
        actionBarY = math.floor(base.actionBarY * s),
        actionBarH = math.floor(base.actionBarH * s),
        actionDividerY = math.floor(base.actionDividerY * s),
        frame2Y = math.floor(base.frame2Y * s),
        frame2Offset = math.floor(base.frame2Offset * s),
        tabBarY = math.floor(base.tabBarY * s),
        contentDividerY = math.floor(base.contentDividerY * s),
        contentY = math.floor(base.contentY * s),
        contentOffsetH = math.floor(base.contentOffsetH * s),
        actionXs = {
            math.floor(base.actionXs[1] * s),
            math.floor(base.actionXs[2] * s),
            math.floor(base.actionXs[3] * s),
        },
        textSize = {
            header = math.max(8, math.floor(base.textSize.header * s)),
            btn = math.max(8, math.floor(base.textSize.btn * s)),
            tab = math.max(8, math.floor(base.textSize.tab * s)),
        },
        scale = s,
    }
end

local L = buildScaledLayout(DEVICE)

local targetParent = LocalPlayer:WaitForChild("PlayerGui")
pcall(function()
    if gethui then targetParent = gethui() end
end)

local V7_SCRIPT_GUI = Instance.new("ScreenGui")
V7_SCRIPT_GUI.Name = "V7_SCRIPT"
V7_SCRIPT_GUI.ResetOnSpawn = false
V7_SCRIPT_GUI.DisplayOrder = 999
V7_SCRIPT_GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
V7_SCRIPT_GUI.IgnoreGuiInset = false
V7_SCRIPT_GUI.Parent = targetParent

local BorderFrame = Instance.new("Frame")
BorderFrame.Name = "BorderFrame"
BorderFrame.Size = UDim2.new(0, L.winW + 4, 0, L.winH + 4)
BorderFrame.Position = L.posX
BorderFrame.AnchorPoint = Vector2.new(0.5, 0.5)
BorderFrame.BackgroundColor3 = C.accent
BorderFrame.BorderSizePixel = 0
BorderFrame.Parent = V7_SCRIPT_GUI
local BorderCorner = Instance.new("UICorner")
BorderCorner.CornerRadius = UDim.new(0, 13)
BorderCorner.Parent = BorderFrame

local UIGradient = Instance.new("UIGradient")
UIGradient.Color = borderGradientSeq
UIGradient.Rotation = 308.077
UIGradient.Parent = BorderFrame

local Win = Instance.new("Frame")
Win.Name = "Win"
Win.Size = UDim2.new(0, L.winW, 0, L.winH)
Win.Position = L.posX
Win.AnchorPoint = Vector2.new(0.5, 0.5)
Win.BackgroundTransparency = 1
Win.BorderSizePixel = 0
Win.ZIndex = 2
Win.Parent = V7_SCRIPT_GUI

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(1, 0, 1, 0)
Frame.BackgroundColor3 = C.body
Frame.BorderSizePixel = 0
Frame.ClipsDescendants = true
Frame.Parent = Win
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 13)

local Frame2 = Instance.new("Frame")
Frame2.Size = UDim2.new(1, 0, 1, L.frame2Offset)
Frame2.Position = UDim2.new(0, 0, 0, L.frame2Y)
Frame2.BackgroundColor3 = C.panel
Frame2.BorderSizePixel = 0
Frame2.Parent = Frame
Instance.new("UICorner", Frame2).CornerRadius = UDim.new(0, 13)

local Frame3 = Instance.new("Frame")
Frame3.Size = UDim2.new(1, 0, 0, L.headerH)
Frame3.Position = UDim2.new(0, 0, 0, -8)
Frame3.BackgroundTransparency = 1
Frame3.BorderSizePixel = 0
Frame3.ZIndex = 3
Frame3.Parent = Frame

local Frame4 = Instance.new("Frame")
Frame4.Size = UDim2.new(1, 0, 0, 1)
Frame4.Position = UDim2.new(0, 0, 1, -1)
Frame4.BackgroundColor3 = C.stroke
Frame4.BorderSizePixel = 0
Frame4.ZIndex = 4
Frame4.Parent = Frame3

local Frame5 = Instance.new("Frame")
Frame5.Size = UDim2.new(0, 6, 0, 6)
Frame5.Position = UDim2.new(0, 10, 0.5, -3)
Frame5.BackgroundColor3 = C.accent
Frame5.BorderSizePixel = 0
Frame5.ZIndex = 5
Frame5.Parent = Frame3
Instance.new("UICorner", Frame5).CornerRadius = UDim.new(0, 4)

local Frame6 = Instance.new("Frame")
Frame6.Size = UDim2.new(0, 12, 0, 12)
Frame6.Position = UDim2.new(0, 7, 0.5, -6)
Frame6.BackgroundColor3 = C.accent
Frame6.BackgroundTransparency = 0.75
Frame6.BorderSizePixel = 0
Frame6.ZIndex = 4
Frame6.Parent = Frame3
Instance.new("UICorner", Frame6).CornerRadius = UDim.new(0, 7)

local TextLabel = Instance.new("TextLabel")
TextLabel.Size = UDim2.new(0, 120, 1, 0)
TextLabel.Position = UDim2.new(0, 24, 0, 0)
TextLabel.BackgroundTransparency = 1
TextLabel.ZIndex = 5
TextLabel.Text = "V7 SCRIPT"
TextLabel.TextColor3 = C.textBright
TextLabel.TextSize = 11
TextLabel.Font = Enum.Font.GothamBold
TextLabel.TextXAlignment = Enum.TextXAlignment.Left
TextLabel.Parent = Frame3

local TextLabel2 = Instance.new("TextLabel")
TextLabel2.Size = UDim2.new(1, -163, 1, 0)
TextLabel2.Position = UDim2.new(0, 95, 0, 0)
TextLabel2.BackgroundTransparency = 1
TextLabel2.ZIndex = 5
TextLabel2.Text = '<font color="rgb(100,100,110)">V7 pvp</font>'
TextLabel2.TextColor3 = C.textBright
TextLabel2.TextSize = 11
TextLabel2.Font = Enum.Font.GothamBold
TextLabel2.TextXAlignment = Enum.TextXAlignment.Left
TextLabel2.RichText = true
TextLabel2.Parent = Frame3

local HB = DEVICE == "mobile" and 20 or 22
local function headerButton(name, txt, xOff)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = UDim2.new(0, HB, 0, HB)
    b.Position = UDim2.new(1, xOff, 0.5, -HB / 2)
    b.BackgroundColor3 = C.card
    b.BorderSizePixel = 0
    b.ZIndex = 6
    b.Text = txt
    b.TextColor3 = C.textMute
    b.TextSize = L.textSize.header
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = false
    b.Parent = Frame3
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    local s = Instance.new("UIStroke"); s.Color = C.stroke; s.Parent = b
    return b
end

local hbOff = DEVICE == "mobile" and {-64, -42, -20} or {-70, -46, -22}
local LockBtn = headerButton("Lock", "🔓 ", hbOff[1])
local MinBtn = headerButton("Min", "-", hbOff[2])
local CloseBtn = headerButton("Close", "X", hbOff[3])

local Frame7 = Instance.new("Frame")
Frame7.Size = UDim2.new(1, 0, 0, L.actionBarH)
Frame7.Position = UDim2.new(0, 0, 0, L.actionBarY)
Frame7.BackgroundTransparency = 1
Frame7.BorderSizePixel = 0
Frame7.ZIndex = 4
Frame7.Parent = Frame

local Frame8 = Instance.new("Frame")
Frame8.Size = UDim2.new(1, 0, 0, 1)
Frame8.Position = UDim2.new(0, 0, 0, L.actionDividerY)
Frame8.BackgroundColor3 = C.stroke
Frame8.BorderSizePixel = 0
Frame8.ZIndex = 4
Frame8.Parent = Frame7

local function actionButton(name, label, xPos, bW)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, bW, 0, L.btnH)
    btn.Position = UDim2.new(0, xPos, 0, 8)
    btn.BackgroundColor3 = C.card
    btn.BorderSizePixel = 0
    btn.ZIndex = 5
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = Frame7
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    local s = Instance.new("UIStroke"); s.Color = C.stroke; s.Parent = btn
    local top = Instance.new("Frame")
    top.Size = UDim2.new(1, -10, 0, 2)
    top.Position = UDim2.new(0, 5, 0, 0)
    top.BackgroundColor3 = C.stroke
    top.BorderSizePixel = 0
    top.ZIndex = 6
    top.Parent = btn
    Instance.new("UICorner", top).CornerRadius = UDim.new(0, 1)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.ZIndex = 7
    lbl.Text = label
    lbl.TextColor3 = C.textBright
    lbl.TextSize = L.textSize.btn
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = btn
    return btn, top, lbl
end

ActionHotkeys = ActionHotkeys or {
    FLASH = nil,
    BLOCK = nil,
    RESET = nil,
}
local bindingAction = nil

local flashTitle = ActionHotkeys.FLASH and ("FLASH TP [" .. ActionHotkeys.FLASH.Name .. "]") or "FLASH TP"
local blockTitle = ActionHotkeys.BLOCK and ("BLOCK [" .. ActionHotkeys.BLOCK.Name .. "]") or "BLOCK"
local resetTitle = ActionHotkeys.RESET and ("RESET [" .. ActionHotkeys.RESET.Name .. "]") or "RESET"

local FLASHTP, flashAccent, flashLbl = actionButton("FLASH TP", flashTitle, L.actionXs[1], L.btnSize)
local BLOCK, blockAccent, blockLbl     = actionButton("BLOCK", blockTitle, L.actionXs[2], L.btnSize)
local RESET, resetAccent, resetLbl     = actionButton("RESET", resetTitle, L.actionXs[3], L.btnSize)

local function startBinding(id, btn, top, lbl, baseName)
    if bindingAction then
        local prevKey = ActionHotkeys[bindingAction.id]
        bindingAction.lbl.Text = prevKey and (bindingAction.baseName .. " [" .. prevKey.Name .. "]") or bindingAction.baseName
        bindingAction.top.BackgroundColor3 = C.stroke
        bindingAction.lbl.TextColor3 = C.textBright
    end
    bindingAction = { id = id, btn = btn, top = top, lbl = lbl, baseName = baseName }
    lbl.Text = "[ ... ]"
    lbl.TextColor3 = Color3.fromRGB(255, 220, 60)
    top.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
end

FLASHTP.MouseButton2Click:Connect(function()
    startBinding("FLASH", FLASHTP, flashAccent, flashLbl, "FLASH TP")
end)

BLOCK.MouseButton2Click:Connect(function()
    startBinding("BLOCK", BLOCK, blockAccent, blockLbl, "BLOCK")
end)

RESET.MouseButton2Click:Connect(function()
    startBinding("RESET", RESET, resetAccent, resetLbl, "RESET")
end)

local Frame12 = Instance.new("Frame")
Frame12.Size = UDim2.new(1, 0, 0, L.tabH)
Frame12.Position = UDim2.new(0, 0, 0, L.tabBarY)
Frame12.BackgroundColor3 = C.tabBar
Frame12.BorderSizePixel = 0
Frame12.ZIndex = 5
Frame12.Parent = Frame
local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.FillDirection = Enum.FillDirection.Horizontal
UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
UIListLayout.Parent = Frame12

local TextButton4 = Instance.new("TextButton")
TextButton4.Size = UDim2.new(0.5, 0, 1, 0)
TextButton4.BackgroundColor3 = C.tabBar
TextButton4.BorderSizePixel = 0
TextButton4.ZIndex = 5
TextButton4.LayoutOrder = 1
TextButton4.Text = ""
TextButton4.AutoButtonColor = false
TextButton4.Parent = Frame12
local TextLabel7 = Instance.new("TextLabel")
TextLabel7.Size = UDim2.new(1, 0, 1, 0)
TextLabel7.BackgroundTransparency = 1
TextLabel7.ZIndex = 6
TextLabel7.Text = "Brainrots"
TextLabel7.TextColor3 = C.textBlue
TextLabel7.TextSize = L.textSize.tab
TextLabel7.Font = Enum.Font.GothamMedium
TextLabel7.Parent = TextButton4
local Frame13 = Instance.new("Frame")
Frame13.Size = UDim2.new(1, -16, 0, 2)
Frame13.Position = UDim2.new(0, 8, 1, -2)
Frame13.BackgroundColor3 = C.accent
Frame13.BorderSizePixel = 0
Frame13.ZIndex = 7
Frame13.Parent = TextButton4
Instance.new("UICorner", Frame13).CornerRadius = UDim.new(0, 1)

local TextButton5 = Instance.new("TextButton")
TextButton5.Size = UDim2.new(0.5, 0, 1, 0)
TextButton5.BackgroundColor3 = C.tabBar
TextButton5.BorderSizePixel = 0
TextButton5.ZIndex = 5
TextButton5.LayoutOrder = 2
TextButton5.Text = ""
TextButton5.AutoButtonColor = false
TextButton5.Parent = Frame12
local TextLabel8 = Instance.new("TextLabel")
TextLabel8.Size = UDim2.new(1, 0, 1, 0)
TextLabel8.BackgroundTransparency = 1
TextLabel8.ZIndex = 6
TextLabel8.Text = "Settings"
TextLabel8.TextColor3 = C.textDim
TextLabel8.TextSize = L.textSize.tab
TextLabel8.Font = Enum.Font.GothamMedium
TextLabel8.Parent = TextButton5
local Frame14 = Instance.new("Frame")
Frame14.Size = UDim2.new(1, -16, 0, 2)
Frame14.Position = UDim2.new(0, 8, 1, -2)
Frame14.BackgroundColor3 = C.accent
Frame14.BackgroundTransparency = 1
Frame14.BorderSizePixel = 0
Frame14.ZIndex = 7
Frame14.Parent = TextButton5
Instance.new("UICorner", Frame14).CornerRadius = UDim.new(0, 1)

local Frame15 = Instance.new("Frame")
Frame15.Size = UDim2.new(1, 0, 0, 1)
Frame15.Position = UDim2.new(0, 0, 0, L.contentDividerY)
Frame15.BackgroundColor3 = C.stroke
Frame15.BorderSizePixel = 0
Frame15.ZIndex = 6
Frame15.Parent = Frame

local Frame16 = Instance.new("Frame")
Frame16.Size = UDim2.new(1, 0, 1, L.contentOffsetH)
Frame16.Position = UDim2.new(0, 0, 0, L.contentY)
Frame16.BackgroundTransparency = 1
Frame16.BorderSizePixel = 0
Frame16.ZIndex = 2
Frame16.ClipsDescendants = true
Frame16.Parent = Frame

local Frame17 = Instance.new("Frame")
Frame17.Name = "Frame_Brainrots"
Frame17.Size = UDim2.new(1, 0, 1, 0)
Frame17.Position = UDim2.new(0, 0, 0, 0)
Frame17.BackgroundTransparency = 1
Frame17.BorderSizePixel = 0
Frame17.ZIndex = 3
Frame17.Parent = Frame16

local scrollListRef = Instance.new("ScrollingFrame")
scrollListRef.Name = "ScrollingFrame"
scrollListRef.Size = UDim2.new(1, 0, 1, 0)
scrollListRef.BackgroundTransparency = 1
scrollListRef.BorderSizePixel = 0
scrollListRef.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollListRef.ScrollBarThickness = 3
scrollListRef.ScrollBarImageColor3 = C.accent
scrollListRef.ScrollingDirection = Enum.ScrollingDirection.Y
scrollListRef.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollListRef.Parent = Frame17

local UIListLayout2 = Instance.new("UIListLayout")
UIListLayout2.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout2.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayout2.Padding = UDim.new(0, 4)
UIListLayout2.Parent = scrollListRef

local UIPaddingList = Instance.new("UIPadding")
UIPaddingList.PaddingTop = UDim.new(0, 6)
UIPaddingList.PaddingBottom = UDim.new(0, 6)
UIPaddingList.PaddingLeft = UDim.new(0, 4)
UIPaddingList.PaddingRight = UDim.new(0, 4)
UIPaddingList.Parent = scrollListRef

local Frame21 = Instance.new("Frame")
Frame21.Name = "Frame_Settings"
Frame21.Size = UDim2.new(1, 0, 1, 0)
Frame21.Position = UDim2.new(1, 0, 0, 0)
Frame21.BackgroundTransparency = 1
Frame21.BorderSizePixel = 0
Frame21.Visible = false
Frame21.ZIndex = 3
Frame21.Parent = Frame16

local ScrollingFrame2 = Instance.new("ScrollingFrame")
ScrollingFrame2.Size = UDim2.new(1, 0, 1, 0)
ScrollingFrame2.BackgroundTransparency = 1
ScrollingFrame2.BorderSizePixel = 0
ScrollingFrame2.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollingFrame2.ScrollBarThickness = 3
ScrollingFrame2.ScrollBarImageColor3 = C.accent
ScrollingFrame2.ScrollingDirection = Enum.ScrollingDirection.Y
ScrollingFrame2.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollingFrame2.Parent = Frame21

local UIListLayout3 = Instance.new("UIListLayout")
UIListLayout3.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout3.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayout3.Padding = UDim.new(0, 4)
UIListLayout3.Parent = ScrollingFrame2

local UIPadding2 = Instance.new("UIPadding")
UIPadding2.PaddingTop = UDim.new(0, 10)
UIPadding2.PaddingBottom = UDim.new(0, 10)
UIPadding2.PaddingLeft = UDim.new(0, 8)
UIPadding2.PaddingRight = UDim.new(0, 8)
UIPadding2.Parent = ScrollingFrame2

local sectionOrder = 0
local function sectionHeader(text)
    sectionOrder = sectionOrder + 1
    local wrap = Instance.new("Frame")
    wrap.Size = UDim2.new(1, 0, 0, 24)
    wrap.BackgroundTransparency = 1
    wrap.BorderSizePixel = 0
    wrap.ZIndex = 4
    wrap.LayoutOrder = sectionOrder
    wrap.Parent = ScrollingFrame2

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3 = C.stroke
    line.BorderSizePixel = 0
    line.ZIndex = 5
    line.Parent = wrap

    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 0, 1, 0)
    pill.Position = UDim2.new(0.5, 0, 0, 0)
    pill.AnchorPoint = Vector2.new(0.5, 0)
    pill.BackgroundColor3 = C.panel
    pill.BorderSizePixel = 0
    pill.ZIndex = 6
    pill.AutomaticSize = Enum.AutomaticSize.X
    pill.Parent = wrap

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.ZIndex = 7
    lbl.Text = text
    lbl.TextColor3 = C.textMute
    lbl.TextSize = 10
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = pill
    return wrap
end

local function toggleRow(title, desc, defaultOn, onToggle)
    sectionOrder = sectionOrder + 1
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = C.card
    row.BorderSizePixel = 0
    row.ZIndex = 4
    row.LayoutOrder = sectionOrder
    row.Parent = ScrollingFrame2
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke"); s.Color = C.stroke; s.Parent = row

    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.new(0, 3, 1, -10)
    accentBar.Position = UDim2.new(0, 0, 0, 5)
    accentBar.BackgroundColor3 = C.accent
    accentBar.BorderSizePixel = 0
    accentBar.ZIndex = 5
    accentBar.Parent = row
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 2)

    local t1 = Instance.new("TextLabel")
    t1.Size = UDim2.new(1, -52, 0, 24)
    t1.Position = UDim2.new(0, 12, 0, 0)
    t1.BackgroundTransparency = 1
    t1.ZIndex = 5
    t1.Text = title
    t1.TextColor3 = C.textBright
    t1.TextSize = 13
    t1.Font = Enum.Font.GothamMedium
    t1.TextXAlignment = Enum.TextXAlignment.Left
    t1.Parent = row

    local t2 = Instance.new("TextLabel")
    t2.Size = UDim2.new(1, -52, 0, 20)
    t2.Position = UDim2.new(0, 12, 0, 22)
    t2.BackgroundTransparency = 1
    t2.ZIndex = 5
    t2.Text = desc
    t2.TextColor3 = C.textMute
    t2.TextSize = 11
    t2.Font = Enum.Font.Gotham
    t2.TextWrapped = true
    t2.TextXAlignment = Enum.TextXAlignment.Left
    t2.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, 36, 0, 20)
    track.Position = UDim2.new(1, -42, 0.5, -10)
    track.BackgroundColor3 = C.accent
    track.BorderSizePixel = 0
    track.ZIndex = 6
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 10)
    local ts = Instance.new("UIStroke"); ts.Color = C.accent; ts.Parent = track

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(0, 19, 0.5, -7)
    knob.BackgroundColor3 = C.knobOn
    knob.BorderSizePixel = 0
    knob.ZIndex = 7
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 7)

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(1, 0, 1, 0)
    hit.BackgroundTransparency = 1
    hit.ZIndex = 8
    hit.Text = ""
    hit.Parent = row

    local ref = { on = defaultOn ~= false, track = track, stroke = ts, knob = knob }
    local function render(animate)
        local info = TweenInfo.new(animate and 0.16 or 0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        if ref.on then
            TweenService:Create(track, info, { BackgroundColor3 = C.accent }):Play()
            TweenService:Create(ts, info, { Color = C.accent }):Play()
            TweenService:Create(knob, info, { Position = UDim2.new(0, 19, 0.5, -7), BackgroundColor3 = C.knobOn }):Play()
        else
            TweenService:Create(track, info, { BackgroundColor3 = C.trackOff }):Play()
            TweenService:Create(ts, info, { Color = C.stroke }):Play()
            TweenService:Create(knob, info, { Position = UDim2.new(0, 3, 0.5, -7), BackgroundColor3 = C.knobOff }):Play()
        end
    end
    render(false)
    hit.MouseButton1Click:Connect(function()
        ref.on = not ref.on
        render(true)
        if onToggle then pcall(onToggle, ref.on) end
    end)
    return row, ref
end

local function makeSpeedRow(title, options, defaultVal, onSelect)
    sectionOrder = sectionOrder + 1
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 56)
    row.BackgroundColor3 = C.card
    row.BorderSizePixel = 0
    row.ZIndex = 4
    row.LayoutOrder = sectionOrder
    row.Parent = ScrollingFrame2
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke"); s.Color = C.stroke; s.Parent = row

    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.new(0, 3, 1, -10)
    accentBar.Position = UDim2.new(0, 0, 0, 5)
    accentBar.BackgroundColor3 = C.accent
    accentBar.BorderSizePixel = 0
    accentBar.ZIndex = 5
    accentBar.Parent = row
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 2)

    local t1 = Instance.new("TextLabel")
    t1.Size = UDim2.new(1, -12, 0, 20)
    t1.Position = UDim2.new(0, 12, 0, 4)
    t1.BackgroundTransparency = 1
    t1.ZIndex = 5
    t1.Text = title
    t1.TextColor3 = C.textBright
    t1.TextSize = 13
    t1.Font = Enum.Font.GothamMedium
    t1.TextXAlignment = Enum.TextXAlignment.Left
    t1.Parent = row

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, -24, 0, 22)
    container.Position = UDim2.new(0, 12, 0, 27)
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.ZIndex = 5
    container.Parent = row

    local count = #options
    local segLayout = Instance.new("UIListLayout")
    segLayout.FillDirection = Enum.FillDirection.Horizontal
    segLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    segLayout.Padding = UDim.new(0, 4)
    segLayout.Parent = container

    local currentVal = defaultVal or "FAST"
    local btns = {}

    local function updateVisuals()
        for opt, bData in pairs(btns) do
            local isSel = (opt == currentVal)
            local targetBg = isSel and C.accentHi or Color3.fromRGB(16, 16, 20)
            local targetTxt = isSel and C.textBright or C.textDim
            local targetStroke = isSel and C.accent or C.stroke
            TweenService:Create(bData.btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { BackgroundColor3 = targetBg }):Play()
            TweenService:Create(bData.stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Color = targetStroke }):Play()
            bData.btn.TextColor3 = targetTxt
        end
    end

    for _, opt in ipairs(options) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1 / count, -4, 1, 0)
        btn.BackgroundColor3 = (opt == currentVal) and C.accentHi or Color3.fromRGB(16, 16, 20)
        btn.BorderSizePixel = 0
        btn.ZIndex = 6
        btn.Text = opt
        btn.TextColor3 = (opt == currentVal) and C.textBright or C.textDim
        btn.TextScaled = false
        btn.TextSize = L.textSize.tab - 2
        btn.Font = Enum.Font.GothamBold
        btn.AutoButtonColor = false
        btn.Parent = container
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local bs = Instance.new("UIStroke")
        bs.Color = (opt == currentVal) and C.accent or C.stroke
        bs.Parent = btn

        btns[opt] = { btn = btn, stroke = bs }

        btn.MouseButton1Click:Connect(function()
            if currentVal == opt then return end
            currentVal = opt
            updateVisuals()
            if onSelect then pcall(onSelect, opt) end
        end)
    end

    return row
end

sectionHeader(" FLASH TP ")
makeSpeedRow("Block Speed", {"ULTRA", "FAST", "NORMAL", "SLOW"}, BlockSpeed or "ULTRA", function(v)
    BlockSpeed = v
    pcall(SaveConfig)
end)
toggleRow("Auto Block", "Block auto the plot owner after grab", AutoBlockEnabled, function(v)
    AutoBlockEnabled = v
    pcall(SaveConfig)
end)
toggleRow("Auto Flash", "Auto flash teleport on enemies", AutoFlashEnabled, function(v)
    AutoFlashEnabled = v
    pcall(SaveConfig)
end)
toggleRow("Ragdoll Bypass", "Bypasses ragdoll effects on character", RagdollBypassEnabled, function(v)
    RagdollBypassEnabled = v
    pcall(SaveConfig)
end)
toggleRow("Bypass Auto Defense", "Blocks 0.5s before flashing to bypass auto blocks", BypassAutoDefense, function(v)
    BypassAutoDefense = v
    pcall(SaveConfig)
end)
toggleRow("Anti Ragdoll", "Prevents ragdoll from triggering", (AntiRagdoll and AntiRagdoll.running) or false, function(v)
    if v then AntiRagdoll.enable() else AntiRagdoll.disable() end
    pcall(SaveConfig)
end)

local activeHighlights = {}
local activeBillboards = {}
local apEspConnections = {}

local function removeESP(targetPlayer)
    local char = targetPlayer and targetPlayer.Character
    if char then
        local hl = char:FindFirstChild("AdminESP")
        if hl then hl:Destroy() end
        local head = char:FindFirstChild("Head")
        if head then
            local tag = head:FindFirstChild("AdminTag")
            if tag then tag:Destroy() end
        end
    end
    activeHighlights[targetPlayer] = nil
    activeBillboards[targetPlayer] = nil
end

local function createESP(targetPlayer, isAdmin)
    local char = targetPlayer.Character
    if not char or targetPlayer == LocalPlayer then return end
    removeESP(targetPlayer)
    local hl = Instance.new("Highlight")
    hl.Name = "AdminESP"
    hl.FillColor = isAdmin and Color3.fromRGB(80, 80, 80) or Color3.fromRGB(50, 50, 50)
    hl.OutlineColor = isAdmin and Color3.fromRGB(100, 100, 100) or Color3.fromRGB(40, 40, 40)
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = char
    activeHighlights[targetPlayer] = hl
    local head = char:FindFirstChild("Head")
    if head then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "AdminTag"
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.new(0, 110, 0, 38)
        billboard.StudsOffset = Vector3.new(0, 2.5, 0)
        billboard.Parent = head
        activeBillboards[targetPlayer] = billboard
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundTransparency = 0.1
        frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        frame.Parent = billboard
        local uiCorner = Instance.new("UICorner")
        uiCorner.CornerRadius = UDim.new(0, 10)
        uiCorner.Parent = frame
        local gradient = Instance.new("UIGradient")
        gradient.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 35)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 40, 45)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 35))
        }
        gradient.Rotation = 90
        gradient.Parent = frame
        local stroke = Instance.new("UIStroke")
        stroke.Color = isAdmin and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(60, 60, 70)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.3
        stroke.Parent = frame
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = isAdmin and "AP" or "No AP"
        label.TextColor3 = isAdmin and Color3.fromRGB(200, 200, 200) or Color3.fromRGB(120, 120, 130)
        label.TextStrokeTransparency = 0.3
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 15
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Parent = frame
        if isAdmin then
            local glowStroke = Instance.new("UIStroke")
            glowStroke.Color = Color3.fromRGB(150, 150, 150)
            glowStroke.Thickness = 4
            glowStroke.Transparency = 0.6
            glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            glowStroke.Parent = frame
        end
    end
end

local function checkPlayerESP(targetPlayer)
    if not ApEspEnabled then return end
    if targetPlayer == LocalPlayer then return end
    if targetPlayer.Character then
        local isAdmin = targetPlayer:GetAttribute("AdminCommands") == true
        createESP(targetPlayer, isAdmin)
    else
        removeESP(targetPlayer)
    end
end

local function setupPlayerESP(targetPlayer)
    if targetPlayer == LocalPlayer then return end
    task.wait(0.5)
    checkPlayerESP(targetPlayer)
    local conn1 = targetPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        checkPlayerESP(targetPlayer)
    end)
    local conn2 = targetPlayer:GetAttributeChangedSignal("AdminCommands"):Connect(function()
        checkPlayerESP(targetPlayer)
    end)
    table.insert(apEspConnections, conn1)
    table.insert(apEspConnections, conn2)
end

local function enableAPESP()
    for _, p in ipairs(Players:GetPlayers()) do
        setupPlayerESP(p)
    end
    ApEspEnabled = true
end

local function disableAPESP()
    ApEspEnabled = false
    for _, conn in ipairs(apEspConnections) do
        if conn then pcall(function() conn:Disconnect() end) end
    end
    table.clear(apEspConnections)
    for _, p in ipairs(Players:GetPlayers()) do
        removeESP(p)
    end
    for k in pairs(activeHighlights) do activeHighlights[k] = nil end
    for k in pairs(activeBillboards) do activeBillboards[k] = nil end
end

Players.ChildAdded:Connect(function(child)
    if child:IsA("Player") and ApEspEnabled then
        task.wait(2)
        if ApEspEnabled then setupPlayerESP(child) end
    end
end)

RunService.Heartbeat:Connect(function()
    if ApEspEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local currentIsAdmin = p:GetAttribute("AdminCommands") == true
                local hl = activeHighlights[p]
                local existingIsAdmin = hl and (hl.FillColor == Color3.fromRGB(80, 80, 80))
                if currentIsAdmin ~= existingIsAdmin then
                    checkPlayerESP(p)
                end
            end
        end
    end
end)

sectionHeader(" VISUALS & MISC ")
toggleRow("AP ESP", "Tag players with Admin Commands gamepass", ApEspEnabled, function(v)
    ApEspEnabled = v
    if v then enableAPESP() else disableAPESP() end
    pcall(SaveConfig)
end)

sectionHeader(" BRAINROT ")
toggleRow("Auto Select Best", "Auto-selects highest $/s brainrot", AutoSelectBestBrainrot, function(v)
    AutoSelectBestBrainrot = v
    pcall(SaveConfig)
end)

-- ============================================
-- BRAINROT SCANNER (EXTRACTED FROM LACASA.LUA)
-- ============================================
local yG = {}
local _cacheHash = {}

local _suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function formatNumber(num, decimals)
    decimals = decimals or 1
    local absNum = math.abs(num)
    local order = math.max(1, absNum)
    local exp = math.floor(math.log(order, 1000))
    local suffix = _suffixes[exp + 1] or ("e+" .. exp)
    local scaled = num * (10 ^ decimals / 1000 ^ exp)
    local rounded = math.floor(scaled) / 10 ^ decimals
    return (("%." .. decimals .. "f"):format(rounded)):gsub("%.?0+$", "") .. suffix
end

local function calcIncome(animalIndex, mutation, traits)
    if not AnimalsModule then return 0 end
    local animalData = AnimalsModule[animalIndex]
    if not animalData then return 0 end
    local base = animalData.Generation or animalData.Price * 0.1
    local multiplier = 1
    if mutation and mutation ~= "None" and MutationsModule then
        local mutData = MutationsModule[mutation]
        if mutData and mutData.Modifier then
            multiplier = multiplier + mutData.Modifier
        end
    end
    local isSleepy = false
    if type(traits) == "table" and TraitsModule then
        for _, trait in ipairs(traits) do
            if trait == "Sleepy" then
                isSleepy = true
            else
                local traitData = TraitsModule[trait]
                if traitData and traitData.MultiplierModifier then
                    multiplier = multiplier + traitData.MultiplierModifier
                end
            end
        end
    end
    local income = math.round(base * multiplier)
    if isSleepy then income = math.round(income * 0.5) end
    return income
end

local function getPlotData(plotName)
    if not Synchronizer then return nil end
    local ok, result = pcall(function()
        local oldId = getthreadidentity and getthreadidentity() or nil
        if setthreadidentity then setthreadidentity(8) end
        local data = Synchronizer:GetTableFromChannel(plotName)
        if oldId and setthreadidentity then pcall(setthreadidentity, oldId) end
        return data
    end)
    if ok and type(result) == "table" then return result end
    return nil
end

local function isOwnerMe(owner)
    if not owner then return false end
    if typeof(owner) == "Instance" then return owner == LocalPlayer end
    if type(owner) == "string" then return owner == LocalPlayer.Name end
    return false
end

local function hashAnimalList(animalList, ownerStr)
    if not animalList then return "" end
    local h = ""
    for k, v in pairs(animalList) do
        if type(v) == "table" then
            h = h .. tostring(k) .. tostring(v.Index) .. tostring(v.Mutation)
        end
    end
    return h
end

local function isMyPlot(plot)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") and yourBase.Enabled then return true end
    end
    return false
end

local function getPromptFromSlot(plotName, slotNumber)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums") or plot:FindFirstChild("Podiums")
    if not podiums then return nil end
    local targetSlot = tonumber(slotNumber)
    local targetPodium = nil
    for _, podium in ipairs(podiums:GetChildren()) do
        local slotNum = tonumber(podium.Name:match("%d+"))
        if slotNum == targetSlot or podium.Name == tostring(targetSlot) then
            targetPodium = podium
            break
        end
    end
    if not targetPodium then return nil end
    local base = targetPodium:FindFirstChild("Base") or targetPodium
    local spawn_ = base:FindFirstChild("Spawn") or base
    local pa = (spawn_ and spawn_:FindFirstChild("PromptAttachment")) or targetPodium:FindFirstChild("PromptAttachment", true)
    local prompt = (pa and pa:FindFirstChildWhichIsA("ProximityPrompt")) or targetPodium:FindFirstChildWhichIsA("ProximityPrompt", true)
    return prompt
end

local function scanPlotData(plot)
    local changed = false
    pcall(function()
        local data = getPlotData(plot.Name)
        if not data then return end
        local animalList = data.AnimalList
        local owner = data.Owner

        if not owner or isOwnerMe(owner)
            or (typeof(owner) == "Instance" and not Players:FindFirstChild(owner.Name))
            or (type(owner) == "string" and not Players:FindFirstChild(owner)) then
            _cacheHash[plot.Name] = nil
            for idx = #yG, 1, -1 do
                if yG[idx].plot == plot.Name then
                    table.remove(yG, idx); changed = true
                end
            end
            return
        end

        if not animalList then
            _cacheHash[plot.Name] = nil
            for idx = #yG, 1, -1 do
                if yG[idx].plot == plot.Name then
                    table.remove(yG, idx); changed = true
                end
            end
            return
        end

        local ownerStr = typeof(owner) == "Instance" and owner.Name or tostring(owner)
        local hash = hashAnimalList(animalList, ownerStr)
        if _cacheHash[plot.Name] == hash then return end

        for idx = #yG, 1, -1 do
            if yG[idx].plot == plot.Name then table.remove(yG, idx) end
        end

        for slotKey, slotData in pairs(animalList) do
            if type(slotData) == "table" then
                local animalIndex = slotData.Index
                local animalInfo = AnimalsModule and AnimalsModule[animalIndex]
                if animalInfo then
                    local mut = slotData.Mutation or "None"
                    if mut == "Yin Yang" then mut = "YinYang" end
                    local income = calcIncome(animalIndex, slotData.Mutation, slotData.Traits)
                    local incomeText = "$" .. formatNumber(income) .. "/s"
                    table.insert(yG, {
                        name = animalInfo.DisplayName or animalIndex,
                        genText = incomeText,
                        genValue = income,
                        mutation = mut,
                        traits = slotData.Traits and #slotData.Traits > 0 and table.concat(slotData.Traits, ", ") or "None",
                        owner = ownerStr,
                        plot = plot.Name,
                        slot = tostring(slotKey),
                        uid = plot.Name .. "_" .. tostring(slotKey),
                    })
                end
            end
        end
        _cacheHash[plot.Name] = hash
        changed = true
    end)
    return changed
end

local function fullScan()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end
    local anyChanged = false
    for _, plot in ipairs(plots:GetChildren()) do
        if not isMyPlot(plot) then
            if scanPlotData(plot) then anyChanged = true end
        end
    end
    if anyChanged then
        table.sort(yG, function(a, b) return a.genValue > b.genValue end)
    end
end

local lastRenderedHash = ""
local selectedPetUid = nil
local function updatePetList()
    local hash = ""
    for _, p in ipairs(yG) do
        hash = hash .. p.uid .. p.name .. (p.uid == selectedPetUid and "1" or "0") .. ";"
    end
    if hash == lastRenderedHash and #scrollListRef:GetChildren() > 1 then
        return
    end
    lastRenderedHash = hash

    for _, child in ipairs(scrollListRef:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local C_list = {
        card = Color3.fromRGB(20, 20, 25),
        accent = Color3.fromRGB(100, 100, 110),
        stroke = Color3.fromRGB(45, 45, 55),
        bright = Color3.fromRGB(220, 220, 230),
        mute = Color3.fromRGB(130, 130, 140),
    }

    for _, petData in ipairs(yG) do
        local isSelected = (selectedPetUid == petData.uid)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 44)
        row.BackgroundColor3 = isSelected and Color3.fromRGB(35, 35, 42) or C_list.card
        row.BorderSizePixel = 0
        row.Parent = scrollListRef
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local rStroke = Instance.new("UIStroke")
        rStroke.Color = isSelected and C_list.accent or C_list.stroke
        rStroke.Thickness = isSelected and 1.5 or 1
        rStroke.Parent = row

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Text = petData.name .. " (" .. petData.mutation .. ")"
        nameLabel.Size = UDim2.new(1, -120, 0, 22)
        nameLabel.Position = UDim2.new(0, 10, 0, 2)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = C_list.bright
        nameLabel.Font = Enum.Font.GothamMedium
        nameLabel.TextSize = 12
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row

        local infoLabel = Instance.new("TextLabel")
        infoLabel.Text = petData.owner .. " | slot " .. petData.slot
        infoLabel.Size = UDim2.new(1, -120, 0, 16)
        infoLabel.Position = UDim2.new(0, 10, 0, 22)
        infoLabel.BackgroundTransparency = 1
        infoLabel.TextColor3 = C_list.mute
        infoLabel.Font = Enum.Font.Gotham
        infoLabel.TextSize = 10
        infoLabel.TextXAlignment = Enum.TextXAlignment.Left
        infoLabel.Parent = row

        local valLabel = Instance.new("TextLabel")
        valLabel.Text = petData.genText
        valLabel.Size = UDim2.new(0, 100, 1, 0)
        valLabel.Position = UDim2.new(1, -110, 0, 0)
        valLabel.BackgroundTransparency = 1
        valLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
        valLabel.Font = Enum.Font.GothamBold
        valLabel.TextSize = 12
        valLabel.TextXAlignment = Enum.TextXAlignment.Right
        valLabel.Parent = row

        local clickBtn = Instance.new("TextButton")
        clickBtn.Size = UDim2.new(1, 0, 1, 0)
        clickBtn.BackgroundTransparency = 1
        clickBtn.Text = ""
        clickBtn.BorderSizePixel = 0
        clickBtn.Parent = row

        clickBtn.MouseButton1Click:Connect(function()
            selectedPetUid = petData.uid
            local prompt = getPromptFromSlot(petData.plot, petData.slot)
            _G._FH_SelectedBrainrot = {
                plotName = petData.plot,
                slot = tostring(petData.slot),
                name = petData.name,
                prompt = prompt,
            }
            updatePetList()
        end)
    end

    if #yG == 0 then
        local emptyCard = Instance.new("Frame")
        emptyCard.Name = "EmptyCard"
        emptyCard.Size = UDim2.new(1, -8, 0, 100)
        emptyCard.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        emptyCard.BorderSizePixel = 0
        emptyCard.Parent = scrollListRef
        Instance.new("UICorner", emptyCard).CornerRadius = UDim.new(0, 10)
        local es = Instance.new("UIStroke"); es.Color = Color3.fromRGB(45, 45, 55); es.Parent = emptyCard

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -16, 1, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = "Scanning plots for pets..."
        titleLabel.TextColor3 = Color3.fromRGB(130, 130, 140)
        titleLabel.TextSize = 12
        titleLabel.Font = Enum.Font.GothamMedium
        titleLabel.Parent = emptyCard
    end
end

task.spawn(function()
    while true do
        task.wait(1)
        if AutoSelectBestBrainrot and #yG > 0 then
            local best = yG[1]
            if not selectedPetUid or selectedPetUid ~= best.uid then
                selectedPetUid = best.uid
                local prompt = getPromptFromSlot(best.plot, best.slot)
                _G._FH_SelectedBrainrot = {
                    plotName = best.plot,
                    slot = tostring(best.slot),
                    name = best.name,
                    prompt = prompt,
                }
                pcall(updatePetList)
            end
        end
    end
end)

task.spawn(function()
    while not (Synchronizer and AnimalsModule) do
        task.wait(0.2)
    end
    task.wait(0.5)
    fullScan()
    pcall(updatePetList)
    
    local plots = workspace:WaitForChild("Plots", 10)
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            if not isMyPlot(plot) then
                local pods = plot:FindFirstChild("AnimalPodiums") or plot:FindFirstChild("Podiums")
                if pods then
                    pods.ChildAdded:Connect(function() task.wait(0.1); scanPlotData(plot); pcall(updatePetList) end)
                    pods.ChildRemoved:Connect(function()
                        for idx = #yG, 1, -1 do
                            if yG[idx].plot == plot.Name then table.remove(yG, idx) end
                        end
                        _cacheHash[plot.Name] = nil
                        task.wait(0.1)
                        scanPlotData(plot)
                        pcall(updatePetList)
                    end)
                end
            end
        end
        plots.ChildAdded:Connect(function(plot)
            task.wait(0.5)
            if not isMyPlot(plot) then
                scanPlotData(plot)
                pcall(updatePetList)
            end
        end)
    end
    while true do
        task.wait(1)
        fullScan()
        pcall(updatePetList)
    end
end)

task.spawn(function()
    local base1 = UIGradient.Rotation
    while UIGradient and UIGradient.Parent do
        local t = os.clock()
        UIGradient.Rotation = (base1 + t * 60) % 360
        RunService.RenderStepped:Wait()
    end
end)

local function syncBorder()
    BorderFrame.Position = Win.Position
end

do
    local dragging, dragStart, startPos
    local function begin(input)
        dragging = true
        dragStart = input.Position
        startPos = Win.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
    Frame3.Active = true
    Frame3.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then begin(input) end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            Win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            syncBorder()
        end
    end)
end

local activeTab = "brainrots"
local function setTab(tab)
    if tab == activeTab then return end
    activeTab = tab
    local info = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    if tab == "settings" then
        Frame21.Visible = true
        Frame21.Position = UDim2.new(1, 0, 0, 0)
        TweenService:Create(Frame17, info, { Position = UDim2.new(-1, 0, 0, 0) }):Play()
        TweenService:Create(Frame21, info, { Position = UDim2.new(0, 0, 0, 0) }):Play()
        TextLabel7.TextColor3 = C.textDim
        TextLabel8.TextColor3 = C.textBlue
        TweenService:Create(Frame13, info, { BackgroundTransparency = 1 }):Play()
        TweenService:Create(Frame14, info, { BackgroundTransparency = 0 }):Play()
    else
        Frame17.Visible = true
        Frame17.Position = UDim2.new(-1, 0, 0, 0)
        TweenService:Create(Frame17, info, { Position = UDim2.new(0, 0, 0, 0) }):Play()
        TweenService:Create(Frame21, info, { Position = UDim2.new(1, 0, 0, 0) }):Play()
        TextLabel7.TextColor3 = C.textBlue
        TextLabel8.TextColor3 = C.textDim
        TweenService:Create(Frame13, info, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(Frame14, info, { BackgroundTransparency = 1 }):Play()
        task.delay(0.22, function() if activeTab == "brainrots" then Frame21.Visible = false end end)
    end
end

TextButton4.MouseButton1Click:Connect(function() setTab("brainrots") end)
TextButton5.MouseButton1Click:Connect(function() setTab("settings") end)

local locked = false
LockBtn.MouseButton1Click:Connect(function()
    locked = not locked
    LockBtn.Text = locked and "lock" or "unlock"
    Frame3.Active = not locked
    LockBtn.TextColor3 = locked and C.accent or C.textMute
end)

local minimised = false
local fullSize = Win.Size
local fullBorder = BorderFrame.Size
local MIN_WIN_H = L.headerH + 41
local MIN_BORDER_H = MIN_WIN_H + 4
MinBtn.MouseButton1Click:Connect(function()
    minimised = not minimised
    local info = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    if minimised then
        TweenService:Create(Win, info, { Size = UDim2.new(0, L.winW, 0, MIN_WIN_H) }):Play()
        TweenService:Create(BorderFrame, info, { Size = UDim2.new(0, L.winW + 4, 0, MIN_BORDER_H) }):Play()
    else
        TweenService:Create(Win, info, { Size = fullSize }):Play()
        TweenService:Create(BorderFrame, info, { Size = fullBorder }):Play()
    end
end)

local winVisible = true
CloseBtn.MouseButton1Click:Connect(function()
    local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local t1 = TweenService:Create(Win, info, { Size = UDim2.new(0, 0, 0, 0) })
    local t2 = TweenService:Create(BorderFrame, info, { Size = UDim2.new(0, 0, 0, 0) })
    t1:Play(); t2:Play()
    t1.Completed:Connect(function()
        Win.Visible = false
        BorderFrame.Visible = false
        winVisible = false
    end)
end)

local function hookButton(btn, normal, hover)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = normal }):Play()
    end)
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.06), { BackgroundColor3 = C.deepBlue }):Play()
    end)
    btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = hover }):Play()
    end)
end

hookButton(FLASHTP, C.card, C.iconBg)
hookButton(BLOCK, C.card, C.iconBg)
hookButton(RESET, C.card, C.iconBg)
for _, b in ipairs({ LockBtn, MinBtn, CloseBtn }) do hookButton(b, C.card, C.iconBg) end

local function flashBar(bar)
    bar.BackgroundColor3 = C.accentHi
    TweenService:Create(bar, TweenInfo.new(0.4), { BackgroundColor3 = C.stroke }):Play()
end

FLASHTP.MouseButton1Click:Connect(function()
    flashBar(flashAccent)
    task.spawn(function() pcall(doFlash) end)
end)

BLOCK.MouseButton1Click:Connect(function()
    flashBar(blockAccent)
    task.spawn(function() pcall(doBlock) end)
end)

RESET.MouseButton1Click:Connect(function()
    flashBar(resetAccent)
    task.spawn(function() pcall(doReset) end)
end)

local function toggleWindow()
    winVisible = not winVisible
    if winVisible then
        Win.Visible = true
        BorderFrame.Visible = true
        TweenService:Create(Win, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = fullSize }):Play()
        TweenService:Create(BorderFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = fullBorder }):Play()
    else
        local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local t1 = TweenService:Create(Win, info, { Size = UDim2.new(0, 0, 0, 0) })
        local t2 = TweenService:Create(BorderFrame, info, { Size = UDim2.new(0, 0, 0, 0) })
        t1:Play(); t2:Play()
        t1.Completed:Connect(function()
            if not winVisible then
                Win.Visible = false
                BorderFrame.Visible = false
            end
        end)
    end
end

UserInputService.InputBegan:Connect(function(inp, gpe)
    if bindingAction then
        if inp.UserInputType == Enum.UserInputType.Keyboard then
            local target = bindingAction
            bindingAction = nil
            if inp.KeyCode == Enum.KeyCode.Escape or inp.KeyCode == Enum.KeyCode.Backspace then
                ActionHotkeys[target.id] = nil
                target.lbl.Text = target.baseName
                target.lbl.TextColor3 = C.textBright
                target.top.BackgroundColor3 = C.stroke
                pcall(ShowToggleNotification, target.baseName .. " hotkey cleared", true)
                pcall(SaveConfig)
            else
                ActionHotkeys[target.id] = inp.KeyCode
                target.lbl.Text = target.baseName .. " [" .. inp.KeyCode.Name .. "]"
                target.lbl.TextColor3 = C.textBright
                target.top.BackgroundColor3 = C.stroke
                pcall(ShowToggleNotification, target.baseName .. " bound to " .. inp.KeyCode.Name, true)
                pcall(SaveConfig)
            end
            return
        end
    end

    if gpe then return end

    if inp.KeyCode == Enum.KeyCode.LeftControl or inp.KeyCode == Enum.KeyCode.RightControl then
        toggleWindow()
        return
    end

    if ActionHotkeys.FLASH and inp.KeyCode == ActionHotkeys.FLASH then
        flashBar(flashAccent)
        task.spawn(function() pcall(doFlash) end)
    elseif ActionHotkeys.BLOCK and inp.KeyCode == ActionHotkeys.BLOCK then
        flashBar(blockAccent)
        task.spawn(function() pcall(doBlock) end)
    elseif ActionHotkeys.RESET and inp.KeyCode == ActionHotkeys.RESET then
        flashBar(resetAccent)
        task.spawn(function() pcall(doReset) end)
    end
end)

-- Background pet list update loop removed

local lastViewportSize = workspace.CurrentCamera.ViewportSize
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
    local newSize = workspace.CurrentCamera.ViewportSize
    if math.abs(newSize.X - lastViewportSize.X) < 2 and math.abs(newSize.Y - lastViewportSize.Y) < 2 then
        return
    end
    lastViewportSize = newSize
    DEVICE = getDevice()
    L = buildScaledLayout(DEVICE)

    local info = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    local newWinSize = UDim2.new(0, L.winW, 0, L.winH)
    local newBorderSize = UDim2.new(0, L.winW + 4, 0, L.winH + 4)

    if not minimised then
        TweenService:Create(Win, info, { Size = newWinSize }):Play()
        TweenService:Create(BorderFrame, info, { Size = newBorderSize }):Play()
        fullSize = newWinSize
        fullBorder = newBorderSize
    else
        fullSize = newWinSize
        fullBorder = newBorderSize
        MIN_WIN_H = L.headerH + math.floor(41 * L.scale)
        MIN_BORDER_H = MIN_WIN_H + 4
        TweenService:Create(Win, info, { Size = UDim2.new(0, L.winW, 0, MIN_WIN_H) }):Play()
        TweenService:Create(BorderFrame, info, { Size = UDim2.new(0, L.winW + 4, 0, MIN_BORDER_H) }):Play()
    end

    Frame2.Size = UDim2.new(1, 0, 1, L.frame2Offset)
    Frame2.Position = UDim2.new(0, 0, 0, L.frame2Y)
    Frame3.Size = UDim2.new(1, 0, 0, L.headerH)
    Frame7.Size = UDim2.new(1, 0, 0, L.actionBarH)
    Frame7.Position = UDim2.new(0, 0, 0, L.actionBarY)
    Frame8.Position = UDim2.new(0, 0, 0, L.actionDividerY)

    FLASHTP.Size = UDim2.new(0, L.btnSize, 0, L.btnH)
    FLASHTP.Position = UDim2.new(0, L.actionXs[1], 0, 8)
    BLOCK.Size = UDim2.new(0, L.btnSize, 0, L.btnH)
    BLOCK.Position = UDim2.new(0, L.actionXs[2], 0, 8)
    RESET.Size = UDim2.new(0, L.btnSize, 0, L.btnH)
    RESET.Position = UDim2.new(0, L.actionXs[3], 0, 8)

    flashLbl.TextSize = L.textSize.btn
    blockLbl.TextSize = L.textSize.btn
    resetLbl.TextSize = L.textSize.btn
    TextLabel.TextSize = L.textSize.header
    TextLabel2.TextSize = L.textSize.header
    TextLabel7.TextSize = L.textSize.tab
    TextLabel8.TextSize = L.textSize.tab

    Frame12.Size = UDim2.new(1, 0, 0, L.tabH)
    Frame12.Position = UDim2.new(0, 0, 0, L.tabBarY)

    Frame15.Position = UDim2.new(0, 0, 0, L.contentDividerY)
    Frame16.Size = UDim2.new(1, 0, 1, L.contentOffsetH)
    Frame16.Position = UDim2.new(0, 0, 0, L.contentY)

    local HB_new = DEVICE == "mobile" and math.floor(20 * L.scale) or math.floor(22 * L.scale)
    local hbOff_new = DEVICE == "mobile"
        and {math.floor(-64 * L.scale), math.floor(-42 * L.scale), math.floor(-20 * L.scale)}
        or {math.floor(-70 * L.scale), math.floor(-46 * L.scale), math.floor(-22 * L.scale)}
    for i, btn in ipairs({LockBtn, MinBtn, CloseBtn}) do
        btn.Size = UDim2.new(0, HB_new, 0, HB_new)
        btn.Position = UDim2.new(1, hbOff_new[i], 0.5, -HB_new / 2)
        btn.TextSize = L.textSize.header
    end
end)

task.spawn(function()
    local target = L.posX
    Win.Position = UDim2.new(target.X.Scale, target.X.Offset, target.Y.Scale, target.Y.Offset - 40)
    BorderFrame.Position = Win.Position
    Win.Visible = true
    BorderFrame.Visible = true
    TweenService:Create(Win, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = target }):Play()
    local bt = TweenService:Create(BorderFrame, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = target })
    bt:Play()
    bt.Completed:Wait()
    RunService.RenderStepped:Connect(syncBorder)
end)

pcall(ShowToggleNotification, "V7 Script loaded", true)
if ApEspEnabled then pcall(enableAPESP) end
