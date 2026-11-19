-- LUAU-OL :: AOTR Jolo Hub
-- Player-side combat and ODM automation for Attack on Titan Revolution, wrapped in the Jolo Hub UI.
-- Close button or [F2] unloads. MIT.

local CONFIG = {
    Enabled = true,
    KillAura = false,
    KillAuraRange = 80,
    KillAuraInterval = 0.15,
    AutoReloadBlades = false,
    AutoRefillGas = false,
    InfiniteGas = false,
    InfiniteBoost = false,
    NoHookCooldown = false,
    InstantHook = false,
    TitanESP = false,
    ESPColor = Color3.fromRGB(245, 194, 17),
    AntiAFK = true,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Connections = {}
local RenderBindings = {}
local Drawings = {}
local Unloaded = false

local function addConnection(c) table.insert(Connections, c); return c end
local function addRender(name, priority, fn)
    RunService:BindToRenderStep(name, priority, fn)
    table.insert(RenderBindings, name)
end
local function addDrawing(d) table.insert(Drawings, d); return d end

-- API probes
local hasGetConnections = pcall(function() return type(getconnections) == "function" end)
local hasDrawing = pcall(function() return Drawing and Drawing.new ~= nil end)
if not hasGetConnections then warn("[AOTR] getconnections unavailable - Anti-AFK disabled.") end
if not hasDrawing then warn("[AOTR] Drawing API unavailable - Titan ESP disabled.") end

-- Helpers (refetch at point of use)
local function getChar() return player.Character end
local function getHumanoid()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getTitans()
    local t = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and (obj.Name:lower():find("titan") or obj:GetAttribute("IsTitan")) then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then table.insert(t, obj) end
        end
    end
    return t
end

local function getNearestTitan(range)
    local root = getRoot()
    if not root then return nil end
    local nearest, best = nil, range
    for _, titan in ipairs(getTitans()) do
        local hrp = titan:FindFirstChild("HumanoidRootPart")
        if hrp then
            local d = (hrp.Position - root.Position).Magnitude
            if d < best then nearest, best = titan, d end
        end
    end
    return nearest
end

local function getCombatRemote()
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") and (obj.Name:lower():find("combat") or obj.Name:lower():find("hit") or obj.Name:lower():find("attack")) then
            return obj
        end
    end
    return nil
end
local CombatRemote = getCombatRemote()
if not CombatRemote then warn("[AOTR] No combat remote found - Kill Aura will no-op.") end

-- Background loops
local function killAuraLoop()
    while CONFIG.Enabled and not Unloaded do
        if CONFIG.KillAura and CombatRemote then
            local titan = getNearestTitan(CONFIG.KillAuraRange)
            if titan then
                pcall(function() CombatRemote:FireServer(titan, 1) end)
            end
        end
        task.wait(CONFIG.KillAuraInterval)
    end
end

local function refillLoop()
    while CONFIG.Enabled and not Unloaded do
        if CONFIG.AutoRefillGas then
            local hum = getHumanoid()
            if hum then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
            end
        end
        task.wait(2)
    end
end

local function reloadLoop()
    while CONFIG.Enabled and not Unloaded do
        if CONFIG.AutoReloadBlades then
            local char = getChar()
            if char then
                local blades = char:FindFirstChild("Blades")
                if blades and blades:IsA("Tool") then
                    pcall(function() blades:Activate() end)
                end
            end
        end
        task.wait(3)
    end
end

-- ESP render
local function updateESP()
    if not hasDrawing then return end
    if not CONFIG.TitanESP then
        for _, d in ipairs(Drawings) do d.Visible = false end
        return
    end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local titans = getTitans()

    while #Drawings < #titans * 2 do
        local box = addDrawing(Drawing.new("Square"))
        box.Thickness = 1
        box.Color = CONFIG.ESPColor
        box.Filled = false
        local label = addDrawing(Drawing.new("Text"))
        label.Size = 14
        label.Color = CONFIG.ESPColor
        label.Center = true
        label.Outline = true
    end

    for i, titan in ipairs(titans) do
        local box = Drawings[(i - 1) * 2 + 1]
        local label = Drawings[(i - 1) * 2 + 2]
        local hrp = titan:FindFirstChild("HumanoidRootPart")
        if hrp and box and label then
            local pos, onScreen = cam:WorldToViewportPoint(hrp.Position)
            if onScreen then
                local size = 1200 / math.max(pos.Z, 1)
                box.Size = Vector2.new(size, size * 1.5)
                box.Position = Vector2.new(pos.X - size / 2, pos.Y - size * 0.75)
                box.Visible = true
                label.Text = titan.Name
                label.Position = Vector2.new(pos.X, pos.Y - size)
                label.Visible = true
            else
                box.Visible = false
                label.Visible = false
            end
        end
    end
    for i = #titans * 2 + 1, #Drawings do
        Drawings[i].Visible = false
    end
end

-- ODM render
local function updateODM()
    local hum = getHumanoid()
    if not hum then return end
    if CONFIG.InfiniteGas then pcall(function() hum:SetAttribute("Gas", math.huge) end) end
    if CONFIG.InfiniteBoost then pcall(function() hum:SetAttribute("Boost", math.huge) end) end
    if CONFIG.NoHookCooldown then pcall(function() hum:SetAttribute("HookCooldown", 0) end) end
    if CONFIG.InstantHook then pcall(function() hum:SetAttribute("HookSpeed", 999) end) end
end

local function applyAntiAFK()
    if not hasGetConnections then return end
    pcall(function()
        for _, conn in ipairs(getconnections(player.Idled)) do
            if conn.Disable then conn:Disable() end
        end
    end)
end

-- Prior instance guard
local oldUnload = getgenv().AOTR_JoloHub_Unload
if type(oldUnload) == "function" then pcall(oldUnload) end

-- ============================================================
-- UI (Jolo Hub replica)
-- ============================================================
local Theme = {
    Background = Color3.fromRGB(20, 20, 20),
    Sidebar    = Color3.fromRGB(15, 15, 15),
    Card       = Color3.fromRGB(30, 30, 30),
    Accent     = Color3.fromRGB(245, 194, 17),
    Text       = Color3.fromRGB(255, 255, 255),
    SubText    = Color3.fromRGB(150, 150, 150),
    ToggleOff  = Color3.fromRGB(50, 50, 50),
    Line       = Color3.fromRGB(40, 40, 40),
}

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "JoloHubUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = playerGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 650, 0, 450)
MainFrame.Position = UDim2.new(0.5, -325, 0.5, -225)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Theme.Line
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

local dragging, dragInput, dragStart, startPos
addConnection(MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        addConnection(input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end))
    end
end))
addConnection(MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end))
addConnection(UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end))

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 40)
TopBar.BackgroundTransparency = 1
TopBar.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 150, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Autofarm"
Title.TextColor3 = Theme.Accent
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -40, 0.5, -15)
CloseBtn.BackgroundColor3 = Theme.Card
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Theme.Text
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.Parent = TopBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 4)

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 160, 1, -50)
Sidebar.Position = UDim2.new(0, 10, 0, 45)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 6)

local Logo = Instance.new("TextLabel")
Logo.Size = UDim2.new(1, -20, 0, 40)
Logo.Position = UDim2.new(0, 10, 0, 5)
Logo.BackgroundTransparency = 1
Logo.Text = "Jolo Hub"
Logo.TextColor3 = Theme.Text
Logo.Font = Enum.Font.GothamBold
Logo.TextSize = 18
Logo.TextXAlignment = Enum.TextXAlignment.Left
Logo.Parent = Sidebar

local VersionTag = Instance.new("TextLabel")
VersionTag.Size = UDim2.new(0, 30, 0, 15)
VersionTag.Position = UDim2.new(0, 80, 0, 12)
VersionTag.BackgroundColor3 = Theme.Accent
VersionTag.Text = "v1.0"
VersionTag.TextColor3 = Color3.new(0, 0, 0)
VersionTag.Font = Enum.Font.GothamBold
VersionTag.TextSize = 9
VersionTag.Parent = Logo
Instance.new("UICorner", VersionTag).CornerRadius = UDim.new(0, 4)

local SidebarList = Instance.new("Frame")
SidebarList.Size = UDim2.new(1, 0, 1, -50)
SidebarList.Position = UDim2.new(0, 0, 0, 50)
SidebarList.BackgroundTransparency = 1
SidebarList.Parent = Sidebar
local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 2)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = SidebarList

local function CreateSidebarButton(text, isCategory, isActive)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 30)
    btn.BackgroundColor3 = isActive and Theme.Card or Theme.Sidebar
    btn.BackgroundTransparency = 1
    btn.Text = isCategory and ("  " .. text) or ("    " .. text)
    btn.TextColor3 = isActive and Theme.Accent or (isCategory and Theme.Text or Theme.SubText)
    btn.Font = isCategory and Enum.Font.GothamBold or Enum.Font.Gotham
    btn.TextSize = isCategory and 12 or 13
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = SidebarList
    if isActive then
        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.new(0, 2, 1, 0)
        indicator.BackgroundColor3 = Theme.Accent
        indicator.BorderSizePixel = 0
        indicator.Parent = btn
    end
end

CreateSidebarButton("MAIN", true, false)
CreateSidebarButton("Home", false, false)
CreateSidebarButton("Kaitun", false, false)
CreateSidebarButton("Autofarm", false, true)
CreateSidebarButton("FARMING", true, false)
CreateSidebarButton("Missions", false, false)

local ContentArea = Instance.new("ScrollingFrame")
ContentArea.Size = UDim2.new(1, -190, 1, -50)
ContentArea.Position = UDim2.new(0, 180, 0, 45)
ContentArea.BackgroundTransparency = 1
ContentArea.BorderSizePixel = 0
ContentArea.ScrollBarThickness = 4
ContentArea.ScrollBarImageColor3 = Theme.Line
ContentArea.Parent = MainFrame
local ContentLayout = Instance.new("UIListLayout")
ContentLayout.Padding = UDim.new(0, 10)
ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
ContentLayout.Parent = ContentArea

local function CreateCard(titleText, height)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -10, 0, height or 150)
    card.BackgroundColor3 = Theme.Background
    card.BorderSizePixel = 0
    card.Parent = ContentArea
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.Line
    stroke.Parent = card
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 30)
    title.Position = UDim2.new(0, 15, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = Theme.Accent
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, -30, 0, 1)
    line.Position = UDim2.new(0, 15, 0, 35)
    line.BackgroundColor3 = Theme.Line
    line.BorderSizePixel = 0
    line.Parent = card
    return card
end

local function CreateToggle(parent, nameText, descText, yPos, initialState, callback, validator)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -30, 0, 35)
    row.Position = UDim2.new(0, 15, 0, yPos)
    row.BackgroundTransparency = 1
    row.Active = true
    row.Parent = parent

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -50, 0, 15)
    name.BackgroundTransparency = 1
    name.Text = nameText
    name.TextColor3 = Theme.Text
    name.Font = Enum.Font.Gotham
    name.TextSize = 13
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Parent = row

    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, -50, 0, 15)
    desc.Position = UDim2.new(0, 0, 0, 15)
    desc.BackgroundTransparency = 1
    desc.Text = descText
    desc.TextColor3 = Theme.SubText
    desc.Font = Enum.Font.Gotham
    desc.TextSize = 11
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.Parent = row

    local state = initialState and true or false

    local switchBg = Instance.new("Frame")
    switchBg.Size = UDim2.new(0, 36, 0, 18)
    switchBg.Position = UDim2.new(1, -36, 0, 5)
    switchBg.BackgroundColor3 = state and Theme.Accent or Theme.ToggleOff
    switchBg.Parent = row
    Instance.new("UICorner", switchBg).CornerRadius = UDim.new(1, 0)

    local switchDot = Instance.new("Frame")
    switchDot.Size = UDim2.new(0, 14, 0, 14)
    switchDot.Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    switchDot.BackgroundColor3 = Theme.Background
    switchDot.Parent = switchBg
    Instance.new("UICorner", switchDot).CornerRadius = UDim.new(1, 0)

    local function render()
        switchBg.BackgroundColor3 = state and Theme.Accent or Theme.ToggleOff
        switchDot.Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    end

    addConnection(row.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local next = not state
        if validator and not validator(next) then return end
        state = next
        render()
        if callback then callback(state) end
    end))
end

-- FARM
local FarmCard = CreateCard("✦ FARM", 150)
CreateToggle(FarmCard, "Auto farm", "The main switch. Farms every titan for you.", 45, CONFIG.KillAura,
    function(v) CONFIG.KillAura = v end)
CreateToggle(FarmCard, "Auto reload blades", "Reloads your blades automatically when empty.", 85, CONFIG.AutoReloadBlades,
    function(v) CONFIG.AutoReloadBlades = v end)

-- MISC
local MiscCard = CreateCard("✦ MISC", 150)
CreateToggle(MiscCard, "Auto refill gas", "Refills your gas tanks automatically.", 45, CONFIG.AutoRefillGas,
    function(v) CONFIG.AutoRefillGas = v end)
CreateToggle(MiscCard, "Anti-AFK", "Prevents being kicked for inactivity.", 85, CONFIG.AntiAFK,
    function(v)
        CONFIG.AntiAFK = v
        if v then applyAntiAFK() end
    end,
    function(v)
        if v and not hasGetConnections then
            warn("[AOTR] getconnections unavailable - Anti-AFK cannot be enabled.")
            return false
        end
        return true
    end)

-- ODM
local ODMCard = CreateCard("✦ ODM", 250)
CreateToggle(ODMCard, "Infinite gas", "Keeps your gas tanks topped up.", 45, CONFIG.InfiniteGas,
    function(v) CONFIG.InfiniteGas = v end)
CreateToggle(ODMCard, "Infinite boost", "Keeps your boost stat topped up.", 85, CONFIG.InfiniteBoost,
    function(v) CONFIG.InfiniteBoost = v end)
CreateToggle(ODMCard, "No hook cooldown", "Removes the hook cooldown attribute.", 125, CONFIG.NoHookCooldown,
    function(v) CONFIG.NoHookCooldown = v end)
CreateToggle(ODMCard, "Instant hook", "Sets your hook speed high.", 165, CONFIG.InstantHook,
    function(v) CONFIG.InstantHook = v end)

-- VISUALS
local VisualCard = CreateCard("✦ VISUALS", 120)
CreateToggle(VisualCard, "Titan ESP", "Draws a box around every titan.", 45, CONFIG.TitanESP,
    function(v) CONFIG.TitanESP = v end,
    function(v)
        if v and not hasDrawing then
            warn("[AOTR] Drawing API unavailable - Titan ESP cannot be enabled.")
            return false
        end
        return true
    end)

-- ============================================================
-- CLEANUP
-- ============================================================
local function unload()
    if Unloaded then return end
    Unloaded = true
    CONFIG.Enabled = false

    for _, name in ipairs(RenderBindings) do
        pcall(function() RunService:UnbindFromRenderStep(name) end)
    end
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    for _, d in ipairs(Drawings) do
        pcall(function() d:Remove() end)
    end
    if ScreenGui then ScreenGui:Destroy() end
    if getgenv().AOTR_JoloHub_Unload == unload then
        getgenv().AOTR_JoloHub_Unload = nil
    end
    print("[AOTR] Jolo Hub unloaded.")
end

getgenv().AOTR_JoloHub_Unload = unload

CloseBtn.MouseButton1Click:Connect(function()
    unload()
end)

addConnection(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F2 then unload() end
end))

-- ============================================================
-- STARTUP
-- ============================================================
addRender("AOTR_ESP", Enum.RenderPriority.Camera.Value + 1, updateESP)
addRender("AOTR_ODM", Enum.RenderPriority.Camera.Value + 2, updateODM)

task.spawn(killAuraLoop)
task.spawn(refillLoop)
task.spawn(reloadLoop)

if CONFIG.AntiAFK then applyAntiAFK() end

print("[AOTR] Jolo Hub loaded. Close button or F2 unloads.")
