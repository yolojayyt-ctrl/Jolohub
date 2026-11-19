-- LUAU-OL :: Funky Friday Auto Player (Dynamic Lane Detection & Delta Native Input)
-- Deep container search, direct Click simulation, and built-in diagnostics.
-- [F1] UI, [F2] unload. MIT.

local CONFIG = {
    Enabled = true,
    AutoPlay = false,
    Side = nil,
    Accuracy = 0.35,
    HoldLongNotes = true,
    UseDirectClick = true,      -- Delta Mobile: simulates actual button clicks instead of VirtualUser
    DebugMode = false,          -- Prints lane paths to console if notes still don't register
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local setThreadIdentity = setthreadidentity or set_thread_identity or syn and syn.set_thread_identity
local hasThreadIdentity = pcall(function() return type(setThreadIdentity) == "function" end)

local State = {
    enabled = false,
    side = CONFIG.Side,
    columns = {},
    keymap = {},
    buttons = {},
    keyState = {},
    connection = nil,
    unloaded = false,
}

local Connections = {}
local function addConnection(c) table.insert(Connections, c); return c end

local hasVIM = pcall(function() return VirtualInputManager.SendKeyEvent ~= nil end)

local function runElevated(func)
    local ok, err = pcall(function()
        if hasThreadIdentity then setThreadIdentity(7) end
        func()
        if hasThreadIdentity then setThreadIdentity(2) end
    end)
    return ok
end

-- Deep search that counts lanes and returns the container plus a report
local function findLaneContainer()
    local function checkForLanes(obj, path)
        local laneCount = 0
        local foundLanes = {}
        for _, child in ipairs(obj:GetChildren()) do
            if child.Name:match("Lane") or child.Name:match("Note") then
                laneCount = laneCount + 1
                table.insert(foundLanes, child.Name)
            end
        end
        if laneCount >= 4 then -- Relaxed from 9 to 4 to catch partial UI states
            return obj, foundLanes
        end
        for _, child in ipairs(obj:GetChildren()) do
            if child:IsA("GuiObject") then
                local res, lanes = checkForLanes(child, path .. "." .. child.Name)
                if res then return res, lanes end
            end
        end
        return nil, nil
    end

    local window = playerGui:FindFirstChild("Window")
    local target = window or playerGui
    local container, lanes = checkForLanes(target, "Root")
    return container, lanes
end

local function cacheGameData()
    local inner, lanes = findLaneContainer()
    if not inner then
        warn("[FF] Could not find any lane containers in the GUI.")
        return false
    end

    if CONFIG.DebugMode then
        print("[FF Debug] Found container:", inner:GetFullName())
        print("[FF Debug] Lanes detected:", table.concat(lanes, ", "))
    end

    State.columns = {}
    State.buttons = {}
    State.keymap = {}

    -- Scan every child in the container for matching lanes
    for _, child in ipairs(inner:GetChildren()) do
        -- Match "Lane1", "Lane 1", "Lane1_Left", "LeftLane1", etc.
        local laneNum = child.Name:match("(%d+)")
        if laneNum and tonumber(laneNum) >= 1 and tonumber(laneNum) <= 9 then
            local i = tonumber(laneNum)
            if not State.columns[i] then
                local notes = child:FindFirstChild("Notes") or child:FindFirstChildWhichIsA("Folder")
                if notes then State.columns[i] = notes end

                local labels = child:FindFirstChild("Labels")
                if labels then
                    local label = labels:FindFirstChild("Label")
                    if label and label:IsA("TextLabel") then
                        local keyText = label.Text
                        if not keyText or keyText == "" then
                            local textChild = label:FindFirstChildWhichIsA("TextLabel")
                            if textChild then keyText = textChild.Text end
                        end
                        if keyText and keyText ~= "" then
                            local cleanKey = keyText:gsub("%s+", ""):upper()
                            local ok, keyCode = pcall(function() return Enum.KeyCode[cleanKey] end)
                            if ok and keyCode then State.keymap[i] = keyCode end
                        end
                    end
                end

                -- Cache the actual hit button (not VirtualUser)
                local button = child:FindFirstChild("Button") or child:FindFirstChildWhichIsA("GuiButton")
                if button then State.buttons[i] = button end
            end
        end
    end

    return next(State.columns) ~= nil
end

local function fireInput(col, isDown)
    -- Method 1: Direct GuiObject Click (Reliable on Delta Mobile)
    if CONFIG.UseDirectClick and State.buttons[col] then
        runElevated(function()
            if isDown then
                State.buttons[col]:Click() -- Simulates a direct mouse/tap click on the arrow UI
            end
        end)
        return
    end

    -- Method 2: VirtualInputManager Keyboard
    if hasVIM and State.keymap[col] then
        runElevated(function()
            VirtualInputManager:SendKeyEvent(isDown, State.keymap[col], false, game)
        end)
    end
end

local function autoplayStep()
    if not State.enabled then return end
    local threshold = CONFIG.Accuracy

    for col, notes in pairs(State.columns) do
        if col and notes then
            for _, note in ipairs(notes:GetChildren()) do
                if note:IsA("GuiObject") and note.Visible then
                    local y = note.Position.Y.Scale
                    if y > threshold then
                        if not State.keyState[col] then
                            fireInput(col, true)
                            State.keyState[col] = true
                        end

                        if CONFIG.HoldLongNotes and #note:GetChildren() >= 2 then
                            task.spawn(function()
                                while note.Parent and note.Position.Y.Scale > threshold and State.enabled do
                                    RunService.Heartbeat:Wait()
                                end
                                if State.keyState[col] then
                                    fireInput(col, false)
                                    State.keyState[col] = false
                                end
                            end)
                        else
                            fireInput(col, false)
                            State.keyState[col] = false
                        end
                    end
                end
            end
        end
    end
end

local function startAutoPlay()
    if State.enabled then return end
    if not State.side then warn("[FF] Please select Left or Right in the UI first!"); return end

    if not cacheGameData() then
        warn("[FF] Failed to find lanes. Turn on 'Debug Mode' to see what the script sees.")
        return
    end

    State.enabled = true
    State.keyState = {}
    State.connection = RunService.Heartbeat:Connect(autoplayStep)
    print("[FF] Auto Play started.")
end

local function stopAutoPlay()
    State.enabled = false
    if State.connection then
        pcall(function() State.connection:Disconnect() end)
        State.connection = nil
    end
    for col, pressed in pairs(State.keyState) do
        if pressed then fireInput(col, false) end
    end
    State.keyState = {}
end

-- UI
local Theme = {
    Bg = Color3.fromRGB(18, 18, 24),
    Card = Color3.fromRGB(28, 28, 38),
    Accent = Color3.fromRGB(255, 120, 200),
    Text = Color3.fromRGB(255, 255, 255),
    Sub = Color3.fromRGB(160, 160, 180),
    Off = Color3.fromRGB(48, 48, 60),
    Line = Color3.fromRGB(40, 40, 52),
}

local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
local FW = isMobile and math.clamp(vp.X - 20, 300, 560) or 480
local FH = isMobile and math.clamp(vp.Y - 50, 360, 520) or 400
local ROW = isMobile and 52 or 42

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FF_AutoPlayer"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = playerGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, FW, 0, FH)
MainFrame.Position = UDim2.new(0.5, -FW/2, 0.5, -FH/2)
MainFrame.BackgroundColor3 = Theme.Bg
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke")
stroke.Color = Theme.Line
stroke.Parent = MainFrame

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
            gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 48)
TopBar.BackgroundTransparency = 1
TopBar.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 200, 1, 0)
Title.Position = UDim2.new(0, 16, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Funky Friday"
Title.TextColor3 = Theme.Accent
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 44, 0, 44)
CloseBtn.Position = UDim2.new(1, -50, 0.5, -22)
CloseBtn.BackgroundColor3 = Theme.Card
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Theme.Text
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.Parent = TopBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)
makeDraggable(MainFrame, TopBar)

local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -20, 1, -60)
Scroll.Position = UDim2.new(0, 10, 0, 52)
Scroll.BackgroundTransparency = 1
Scroll.ScrollBarThickness = 6
Scroll.ScrollBarImageColor3 = Theme.Line
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.Parent = MainFrame
local List = Instance.new("UIListLayout")
List.Padding = UDim.new(0, 10)
List.Parent = Scroll

local function makeCard(titleText, height)
    local c = Instance.new("Frame")
    c.Size = UDim2.new(1, -6, 0, height)
    c.BackgroundColor3 = Theme.Bg
    c.BorderSizePixel = 0
    c.Parent = Scroll
    Instance.new("UICorner", c).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke"); s.Color = Theme.Line; s.Parent = c
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -20, 0, 30); t.Position = UDim2.new(0, 14, 0, 8)
    t.BackgroundTransparency = 1; t.Text = titleText; t.TextColor3 = Theme.Accent
    t.Font = Enum.Font.GothamBold; t.TextSize = 14; t.TextXAlignment = Enum.TextXAlignment.Left; t.Parent = c
    local l = Instance.new("Frame")
    l.Size = UDim2.new(1, -28, 0, 1); l.Position = UDim2.new(0, 14, 0, 36)
    l.BackgroundColor3 = Theme.Line; l.BorderSizePixel = 0; l.Parent = c
    return c
end

local function makeToggle(parent, nameText, descText, y, initial, cb)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -20, 0, ROW); row.Position = UDim2.new(0, 10, 0, y)
    row.BackgroundTransparency = 1; row.Text = ""; row.AutoButtonColor = false; row.Parent = parent

    local n = Instance.new("TextLabel")
    n.Size = UDim2.new(1, -70, 0, 20); n.Position = UDim2.new(0, 8, 0, isMobile and 8 or 6)
    n.BackgroundTransparency = 1; n.Text = nameText; n.TextColor3 = Theme.Text
    n.Font = Enum.Font.Gotham; n.TextSize = isMobile and 15 or 14; n.TextXAlignment = Enum.TextXAlignment.Left; n.Parent = row

    local d = Instance.new("TextLabel")
    d.Size = UDim2.new(1, -70, 0, 16); d.Position = UDim2.new(0, 8, 0, isMobile and 28 or 24)
    d.BackgroundTransparency = 1; d.Text = descText; d.TextColor3 = Theme.Sub
    d.Font = Enum.Font.Gotham; d.TextSize = isMobile and 12 or 11; d.TextXAlignment = Enum.TextXAlignment.Left; d.Parent = row

    local state = initial and true or false
    local sw = isMobile and 46 or 36; local sh = isMobile and 22 or 18; local dot = isMobile and 18 or 14

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, sw, 0, sh); bg.Position = UDim2.new(1, -(sw + 8), 0.5, -sh/2)
    bg.BackgroundColor3 = state and Theme.Accent or Theme.Off; bg.Parent = row
    Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

    local dotF = Instance.new("Frame")
    dotF.Size = UDim2.new(0, dot, 0, dot)
    dotF.Position = state and UDim2.new(1, -(dot + 2), 0.5, -dot/2) or UDim2.new(0, 2, 0.5, -dot/2)
    dotF.BackgroundColor3 = Theme.Bg; dotF.Parent = bg
    Instance.new("UICorner", dotF).CornerRadius = UDim.new(1, 0)

    local function render()
        bg.BackgroundColor3 = state and Theme.Accent or Theme.Off
        dotF.Position = state and UDim2.new(1, -(dot + 2), 0.5, -dot/2) or UDim2.new(0, 2, 0.5, -dot/2)
    end

    row.MouseButton1Click:Connect(function()
        state = not state; render()
        if cb then pcall(cb, state) end
    end)
end

local SideCard = makeCard("✦ SELECT SIDE (DO THIS FIRST)", 44 + 44)
local sideLabel = Instance.new("TextLabel")
sideLabel.Size = UDim2.new(1, -20, 0, 30); sideLabel.Position = UDim2.new(0, 10, 0, 44)
sideLabel.BackgroundTransparency = 1; sideLabel.Text = "Side: NOT SET"
sideLabel.TextColor3 = Theme.Accent; sideLabel.Font = Enum.Font.GothamBold
sideLabel.TextSize = 14; sideLabel.TextXAlignment = Enum.TextXAlignment.Left; sideLabel.Parent = SideCard

local function setSide(s)
    State.side = s; CONFIG.Side = s
    sideLabel.Text = "Side: " .. s; sideLabel.TextColor3 = Theme.Text
    stopAutoPlay()
end

local leftBtn = Instance.new("TextButton")
leftBtn.Size = UDim2.new(0, 70, 0, 30); leftBtn.Position = UDim2.new(1, -160, 0, 44)
leftBtn.BackgroundColor3 = Theme.Card; leftBtn.Text = "Left"; leftBtn.TextColor3 = Theme.Text
leftBtn.Font = Enum.Font.GothamBold; leftBtn.TextSize = 13; leftBtn.Parent = SideCard
Instance.new("UICorner", leftBtn).CornerRadius = UDim.new(0, 6)
leftBtn.MouseButton1Click:Connect(function() setSide("Left") end)

local rightBtn = Instance.new("TextButton")
rightBtn.Size = UDim2.new(0, 70, 0, 30); rightBtn.Position = UDim2.new(1, -80, 0, 44)
rightBtn.BackgroundColor3 = Theme.Card; rightBtn.Text = "Right"; rightBtn.TextColor3 = Theme.Text
rightBtn.Font = Enum.Font.GothamBold; rightBtn.TextSize = 13; rightBtn.Parent = SideCard
Instance.new("UICorner", rightBtn).CornerRadius = UDim.new(0, 6)
rightBtn.MouseButton1Click:Connect(function() setSide("Right") end)

local PlayCard = makeCard("✦ AUTO PLAY", 44 + ROW * 3 + 18)
makeToggle(PlayCard, "Auto Play", "Must select side and use Downscroll", 44, CONFIG.AutoPlay, function(v)
    CONFIG.AutoPlay = v
    if v then startAutoPlay() else stopAutoPlay() end
end)

makeToggle(PlayCard, "Direct Click (Mobile)", "Simulates tapping the on-screen arrows directly", 44 + ROW + 6, CONFIG.UseDirectClick, function(v)
    CONFIG.UseDirectClick = v
end)

makeToggle(PlayCard, "Debug Mode", "Prints detected lanes to the F9 console", 44 + (ROW + 6) * 2, CONFIG.DebugMode, function(v)
    CONFIG.DebugMode = v
end)

local PrecisionCard = makeCard("✦ JUDGMENT LINE", 44 + 70)
local precisionLabel = Instance.new("TextLabel")
precisionLabel.Size = UDim2.new(1, -20, 0, 22); precisionLabel.Position = UDim2.new(0, 10, 0, 44)
precisionLabel.BackgroundTransparency = 1; precisionLabel.Text = "Value: 0.35 (higher = later)"
precisionLabel.TextColor3 = Theme.Text; precisionLabel.Font = Enum.Font.Gotham
precisionLabel.TextSize = 13; precisionLabel.TextXAlignment = Enum.TextXAlignment.Left; precisionLabel.Parent = PrecisionCard

local precisionBox = Instance.new("TextBox")
precisionBox.Size = UDim2.new(0, 80, 0, 30); precisionBox.Position = UDim2.new(1, -90, 0, 44)
precisionBox.BackgroundColor3 = Theme.Card; precisionBox.Text = tostring(CONFIG.Accuracy)
precisionBox.TextColor3 = Theme.Text; precisionBox.Font = Enum.Font.Gotham
precisionBox.TextSize = 13; precisionBox.Parent = PrecisionCard
Instance.new("UICorner", precisionBox).CornerRadius = UDim.new(0, 6)
precisionBox.FocusLost:Connect(function()
    local num = tonumber(precisionBox.Text)
    if num then
        num = math.clamp(num, 0, 1)
        CONFIG.Accuracy = num
        precisionBox.Text = string.format("%.2f", num)
        precisionLabel.Text = string.format("Value: %.2f (higher = later)", num)
    else
        precisionBox.Text = tostring(CONFIG.Accuracy)
    end
end)

local function unload()
    if State.unloaded then return end
    State.unloaded = true
    CONFIG.Enabled = false
    stopAutoPlay()
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    if ScreenGui then ScreenGui:Destroy() end
    print("[FF] Auto Player unloaded.")
end

CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false end)
addConnection(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F2 then unload() end
    if input.KeyCode == Enum.KeyCode.F1 then MainFrame.Visible = not MainFrame.Visible end
end))

print("[FF] Script Ready. UI should be visible now.")
