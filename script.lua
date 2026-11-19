-- LUAU-OL :: AOTR Jolo Hub (Mobile/Delta)
-- Player-side combat automation + titan ESP for Attack on Titan Revolution.
-- Touch-sized UI, BillboardGui ESP, Tool:Activate combat. No Drawing/getconnections needed.
-- Float button toggles UI on mobile. [F2] unloads. MIT.

local CONFIG = {
    Enabled = true,
    -- Combat
    KillAura = false,
    KillAuraRange = 100,
    KillAuraInterval = 0.15,
    AutoReloadBlades = false,
    ReloadInterval = 2.5,
    -- Visuals
    TitanESP = false,
    ESPColor = Color3.fromRGB(245, 194, 17),
    -- Utility
    AntiAFK = true,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Mobile detection (works on Delta mobile and Studio phone emulator)
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

-- ============================================================
-- STATE & TRACKING
-- ============================================================
local Connections = {}
local ESP_TAGS = {}
local Unloaded = false

local function addConnection(c)
    table.insert(Connections, c)
    return c
end

-- ============================================================
-- HELPERS
-- ============================================================
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
        if obj:IsA("Model") then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local lower = obj.Name:lower()
                if lower:find("titan") or obj:GetAttribute("IsTitan") then
                    table.insert(t, obj)
                end
            end
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

local function getBladeTool()
    local char = getChar()
    if not char then return nil end
    local fallback
    for _, obj in ipairs(char:GetChildren()) do
        if obj:IsA("Tool") then
            local lower = obj.Name:lower()
            if lower:find("blade") or lower:find("sword") or lower:find("weapon") then
                return obj
            end
            fallback = fallback or obj
        end
    end
    return fallback
end

-- ============================================================
-- COMBAT (Tool:Activate — same path as a real tap)
-- ============================================================
local function faceTarget(target)
    local root = getRoot()
    local hrp = target:FindFirstChild("HumanoidRootPart")
    if root and hrp then
        local look = CFrame.lookAt(
            root.Position,
            Vector3.new(hrp.Position.X, root.Position.Y, hrp.Position.Z)
        )
        root.CFrame = look
    end
end

local function swingBlade()
    local tool = getBladeTool()
    if tool then
        pcall(function() tool:Activate() end)
        return true
    end
    return false
end

local function killAuraLoop()
    while CONFIG.Enabled and not Unloaded do
        if CONFIG.KillAura then
            local titan = getNearestTitan(CONFIG.KillAuraRange)
            if titan then
                faceTarget(titan)
                swingBlade()
            end
        end
        task.wait(CONFIG.KillAuraInterval)
    end
end

local function reloadLoop()
    while CONFIG.Enabled and not Unloaded do
        if CONFIG.AutoReloadBlades then
            local char = getChar()
            local hum = getHumanoid()
            local blade = getBladeTool()
            if char and hum and blade then
                pcall(function()
                    -- Move to backpack then back to character forces a re-equip + reload
                    local backpack = player:FindFirstChildOfClass("Backpack")
                    if backpack then
                        blade.Parent = backpack
                        task.wait(0.05)
                        blade.Parent = char
                    end
                end)
            end
        end
        task.wait(CONFIG.ReloadInterval)
    end
end

-- ============================================================
-- TITAN ESP (BillboardGui — no Drawing API needed)
-- ============================================================
local function clearESP()
    for _, tag in pairs(ESP_TAGS) do
        if tag and tag.Parent then pcall(function() tag:Destroy() end) end
    end
    ESP_TAGS = {}
end

local function updateESP()
    if not CONFIG.TitanESP then
        clearESP()
        return
    end

    local titans = getTitans()
    local seen = {}

    for _, titan in ipairs(titans) do
        local hrp = titan:FindFirstChild("HumanoidRootPart")
        if hrp then
            local existing = ESP_TAGS[titan]
            if not existing or not existing.Parent then
                local billboard = Instance.new("BillboardGui")
                billboard.Name = "AOTR_ESP"
                billboard.Size = UDim2.new(0, 120, 0, 36)
                billboard.StudsOffset = Vector3.new(0, 3, 0)
                billboard.AlwaysOnTop = true
                billboard.LightInfluence = 0
                billboard.Adornee = hrp

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                label.BackgroundTransparency = 0.45
                label.TextColor3 = CONFIG.ESPColor
                label.Text = titan.Name
                label.Font = Enum.Font.GothamBold
                label.TextSize = 14
                label.TextScaled = false
                label.Parent = billboard
                Instance.new("UICorner", label).CornerRadius = UDim.new(0, 4)

                billboard.Parent = hrp
                ESP_TAGS[titan] = billboard
            else
                existing.Adornee = hrp
            end
            seen[titan] = true
        end
    end

    for titan, tag in pairs(ESP_TAGS) do
        if not seen[titan] then
            if tag and tag.Parent then pcall(function() tag:Destroy() end) end
            ESP_TAGS[titan] = nil
        end
    end
end

local function espLoop()
    while CONFIG.Enabled and not Unloaded do
        pcall(updateESP)
        task.wait(0.4)
    end
end

-- ============================================================
-- ANTI-AFK (VirtualUser — works on Delta + mobile)
-- ============================================================
local function setupAntiAFK()
    addConnection(player.Idled:Connect(function()
        if not CONFIG.AntiAFK then return end
        pcall(function()
            VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
        end)
    end))
end

-- ============================================================
-- PRIOR INSTANCE GUARD
-- ============================================================
local oldUnload = getgenv().AOTR_JoloHub_Unload
if type(oldUnload) == "function" then pcall(oldUnload) end

-- ============================================================
-- UI
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

local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
local FRAME_W = isMobile and math.clamp(viewport.X - 24, 300, 560) or 650
local FRAME_H = isMobile and math.clamp(viewport.Y - 60, 340, 520) or 450
local ROW_H = isMobile and 52 or 40
local SHOW_SIDEBAR = not isMobile
local SIDEBAR_W = SHOW_SIDEBAR and 160 or 0

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "JoloHubUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = playerGui

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, FRAME_W, 0, FRAME_H)
MainFrame.Position = UDim2.new(0.5, -FRAME_W / 2, 0.5, -FRAME_H / 2)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = not isMobile
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Theme.Line
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- Drag helper
local function makeDraggable(gui, handle)
    local dragging, dragInput, dragStart, startPos
    addConnection(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = gui.Position
            local endConn
            endConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if endConn then endConn:Disconnect() end
                end
            end)
        end
    end))
    addConnection(handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))
    addConnection(UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            gui.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
end

-- Top bar
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 44)
TopBar.BackgroundTransparency = 1
TopBar.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 200, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Autofarm"
Title.TextColor3 = Theme.Accent
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 40, 0, 40)
CloseBtn.Position = UDim2.new(1, -46, 0.5, -20)
CloseBtn.BackgroundColor3 = Theme.Card
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Theme.Text
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
CloseBtn.AutoButtonColor = true
CloseBtn.Parent = TopBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

makeDraggable(MainFrame, TopBar)

-- Sidebar (desktop only)
if SHOW_SIDEBAR then
    local Sidebar = Instance.new("Frame")
    Sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -54)
    Sidebar.Position = UDim2.new(0, 10, 0, 48)
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
    VersionTag.Size = UDim2.new(0, 34, 0, 16)
    VersionTag.Position = UDim2.new(0, 88, 0, 12)
    VersionTag.BackgroundColor3 = Theme.Accent
    VersionTag.Text = "v1.1"
    VersionTag.TextColor3 = Color3.new(0, 0, 0)
    VersionTag.Font = Enum.Font.GothamBold
    VersionTag.TextSize = 10
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
        btn.Size = UDim2.new(1, 0, 0, 32)
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
end

-- Content
local ContentArea = Instance.new("ScrollingFrame")
ContentArea.Size = UDim2.new(1, -(SIDEBAR_W + 20), 1, -54)
ContentArea.Position = UDim2.new(0, SIDEBAR_W + 10, 0, 48)
ContentArea.BackgroundTransparency = 1
ContentArea.BorderSizePixel = 0
ContentArea.ScrollBarThickness = 6
ContentArea.ScrollBarImageColor3 = Theme.Line
ContentArea.ScrollingDirection = Enum.ScrollingDirection.Y
ContentArea.CanvasSize = UDim2.new(0, 0, 0, 0)
ContentArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
ContentArea.Parent = MainFrame

local ContentLayout = Instance.new("UIListLayout")
ContentLayout.Padding = UDim.new(0, 10)
ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
ContentLayout.Parent = ContentArea

local function CreateCard(titleText, toggleCount)
    local height = 45 + toggleCount * (ROW_H + 6)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, -6, 0, height)
    card.BackgroundColor3 = Theme.Background
    card.BorderSizePixel = 0
    card.Parent = ContentArea
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.Line
    stroke.Parent = card
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 30)
    title.Position = UDim2.new(0, 15, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = Theme.Accent
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, -30, 0, 1)
    line.Position = UDim2.new(0, 15, 0, 36)
    line.BackgroundColor3 = Theme.Line
    line.BorderSizePixel = 0
    line.Parent = card
    return card
end

local function CreateToggle(parent, nameText, descText, yPos, initialState, callback)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -20, 0, ROW_H)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundTransparency = 1
    row.AutoButtonColor = false
    row.Text = ""
    row.Parent = parent

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, -70, 0, 20)
    name.Position = UDim2.new(0, 8, 0, (isMobile and 8) or 4)
    name.BackgroundTransparency = 1
    name.Text = nameText
    name.TextColor3 = Theme.Text
    name.Font = Enum.Font.Gotham
    name.TextSize = isMobile and 15 or 14
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Parent = row

    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, -70, 0, 16)
    desc.Position = UDim2.new(0, 8, 0, (isMobile and 28) or 22)
    desc.BackgroundTransparency = 1
    desc.Text = descText
    desc.TextColor3 = Theme.SubText
    desc.Font = Enum.Font.Gotham
    desc.TextSize = isMobile and 12 or 11
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.Parent = row

    local state = initialState and true or false

    local SW_W = isMobile and 46 or 36
    local SW_H = isMobile and 22 or 18
    local DOT = isMobile and 18 or 14

    local switchBg = Instance.new("Frame")
    switchBg.Size = UDim2.new(0, SW_W, 0, SW_H)
    switchBg.Position = UDim2.new(1, -(SW_W + 8), 0.5, -SW_H / 2)
    switchBg.BackgroundColor3 = state and Theme.Accent or Theme.ToggleOff
    switchBg.Parent = row
    Instance.new("UICorner", switchBg).CornerRadius = UDim.new(1, 0)

    local switchDot = Instance.new("Frame")
    switchDot.Size = UDim2.new(0, DOT, 0, DOT)
    switchDot.Position = state
        and UDim2.new(1, -(DOT + 2), 0.5, -DOT / 2)
        or UDim2.new(0, 2, 0.5, -DOT / 2)
    switchDot.BackgroundColor3 = Theme.Background
    switchDot.Parent = switchBg
    Instance.new("UICorner", switchDot).CornerRadius = UDim.new(1, 0)

    local function render()
        switchBg.BackgroundColor3 = state and Theme.Accent or Theme.ToggleOff
        switchDot.Position = state
            and UDim2.new(1, -(DOT + 2), 0.5, -DOT / 2)
            or UDim2.new(0, 2, 0.5, -DOT / 2)
    end

    row.MouseButton1Click:Connect(function()
        state = not state
        render()
        if callback then pcall(callback, state) end
    end)
end

-- FARM
local FarmCard = CreateCard("✦ FARM", 2)
CreateToggle(FarmCard, "Kill Aura", "Faces and swings at the nearest titan.", 44, CONFIG.KillAura,
    function(v) CONFIG.KillAura = v end)
CreateToggle(FarmCard, "Auto Reload Blades", "Re-equips your blade to trigger reload.", 44 + ROW_H + 6, CONFIG.AutoReloadBlades,
    function(v) CONFIG.AutoReloadBlades = v end)

-- VISUALS
local VisualCard = CreateCard("✦ VISUALS", 1)
CreateToggle(VisualCard, "Titan ESP", "Name tags over every titan.", 44, CONFIG.TitanESP,
    function(v) CONFIG.TitanESP = v end)

-- UTILITY
local UtilCard = CreateCard("✦ UTILITY", 1)
CreateToggle(UtilCard, "Anti-AFK", "Prevents idle kick via VirtualUser.", 44, CONFIG.AntiAFK,
    function(v) CONFIG.AntiAFK = v end)

-- ============================================================
-- FLOAT BUTTON (mobile)
-- ============================================================
if isMobile then
    local floatBtn = Instance.new("TextButton")
    floatBtn.Size = UDim2.new(0, 56, 0, 56)
    floatBtn.Position = UDim2.new(0, 16, 0.5, -28)
    floatBtn.BackgroundColor3 = Theme.Accent
    floatBtn.Text = "J"
    floatBtn.TextColor3 = Color3.new(0, 0, 0)
    floatBtn.Font = Enum.Font.GothamBold
    floatBtn.TextSize = 22
    floatBtn.Parent = ScreenGui
    Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(1, 0)

    local startPos, startInputPos, dragging, moved, moveConn

    floatBtn.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        dragging = true
        moved = false
        startPos = floatBtn.Position
        startInputPos = input.Position
        if moveConn then moveConn:Disconnect() end
        moveConn = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.Change and dragging then
                local delta = input.Position - startInputPos
                if delta.Magnitude > 8 then moved = true end
                if moved then
                    floatBtn.Position = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + delta.X,
                        startPos.Y.Scale, startPos.Y.Offset + delta.Y
                    )
                end
            elseif input.UserInputState == Enum.UserInputState.End then
                dragging = false
                if not moved then
                    MainFrame.Visible = not MainFrame.Visible
                end
                if moveConn then moveConn:Disconnect() end
            end
        end)
    end)
end

-- ============================================================
-- CLEANUP
-- ============================================================
local function unload()
    if Unloaded then return end
    Unloaded = true
    CONFIG.Enabled = false

    clearESP()
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    if ScreenGui then ScreenGui:Destroy() end
    if getgenv().AOTR_JoloHub_Unload == unload then
        getgenv().AOTR_JoloHub_Unload = nil
    end
    print("[AOTR] Jolo Hub unloaded.")
end

getgenv().AOTR_JoloHub_Unload = unload

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

addConnection(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F2 then unload() end
    if input.KeyCode == Enum.KeyCode.F1 then
        MainFrame.Visible = not MainFrame.Visible
    end
end))

-- ============================================================
-- STARTUP
-- ============================================================
task.spawn(killAuraLoop)
task.spawn(reloadLoop)
task.spawn(espLoop)
setupAntiAFK()

print("[AOTR] Jolo Hub loaded. Mobile:", isMobile)
