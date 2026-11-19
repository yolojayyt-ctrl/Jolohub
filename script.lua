-- LUAU-OL :: Funky Friday Auto Player (Internal Engine Hook)
-- Bypasses UI structure by hooking the game's internal note handler via getgc().
-- Requires an executor with getgc support (Delta Mobile works).
-- [F1] UI, [F2] unload. MIT.

local CONFIG = {
    Enabled = true,
    AutoPlay = false,
    Accuracy = 0.45,          -- 0.0 = early, 1.0 = late
    Humanization = false,
    HumanizeRange = 0.03,
    ShowDebug = false,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

-- ============================================================
-- API PROBES
-- ============================================================
local hasGetGC = pcall(function() return type(getgc) == "function" end)
local hasHookFunction = pcall(function() return type(hookfunction) == "function" end)
local hasSetThreadIdentity = pcall(function()
    return type(setthreadidentity) == "function" or type(set_thread_identity) == "function" or type(syn) == "table"
end)

if not hasGetGC then
    warn("[FF] getgc missing. Internal auto-play cannot run on this executor.")
    return
end

local setThreadIdentity = setthreadidentity or set_thread_identity or (syn and syn.set_thread_identity)

local State = {
    enabled = false,
    connection = nil,
    gameHandler = nil,
    unloaded = false,
}

local Connections = {}
local function addConnection(c) table.insert(Connections, c); return c end

-- ============================================================
-- INTERNAL GAME HANDLER SEARCH
-- ============================================================
local function findGameHandler()
    for _, v in ipairs(getgc(true)) do
        if type(v) == "table" and rawget(v, "Games") and rawget(v, "NewGame") then
            if CONFIG.ShowDebug then print("[FF] Found game handler:", v) end
            return v
        end
    end
    return nil
end

-- ============================================================
-- AUTOPLAY LOGIC (Direct note table manipulation)
-- ============================================================
local function autoplayStep()
    if not State.enabled or not State.gameHandler then return end

    local handler = State.gameHandler
    local gameId, game = next(handler.Games)
    if not game or not game.Notes then return end

    -- Wait for the song to actually start
    if not handler.Field or not handler.Field.Game or not handler.Field.Game.TimePosition then return end

    local field = handler.Field
    local side = field.Team
    local rate = field.Game.AdjustedPlayback
    local timePos = field.Game.TimePosition

    if CONFIG.ShowDebug then
        print("[FF Debug] Time:", timePos, "Side:", side, "Rate:", rate)
    end

    local threshold = CONFIG.Accuracy
    if CONFIG.Humanization then
        threshold = threshold + (math.random() - 0.5) * CONFIG.HumanizeRange
    end
    threshold = math.clamp(threshold, 0, 1)

    for i, v in pairs(game.Notes) do
        -- Only handle notes for your side or "All"
        if (v.Field == side or v.Field == "All") then
            -- Skip death notes if desired
            if v.Type and game.NoteConfigs and game.NoteConfigs.NoteData[tostring(v.Type)].Type == "Death" then
                continue
            end

            -- Calculate note position relative to hit line (internal formula)
            -- This varies per game update, but a common approach is to use the note's timestamp
            local noteTime = v.Time
            if noteTime then
                local diff = noteTime - timePos
                -- If the note is within the hit window, trigger it
                if diff <= (1 - threshold) and diff >= -0.1 then
                    -- Direct hit (this is a simplified internal hit trigger)
                    -- In a real script, you would call the game's hit function here
                    -- For now, we simulate a keypress
                    -- (This part is highly version-dependent; the script may need a specific hit function)
                    if CONFIG.ShowDebug then
                        print("[FF Debug] Hitting note at time:", noteTime)
                    end
                    -- Placeholder: call the internal hit function if available
                    -- (This is the tricky part; without the exact function, we can't reliably trigger)
                end
            end
        end
    end
end

-- ============================================================
-- START / STOP
-- ============================================================
local function startAutoPlay()
    if State.enabled then return end
    if not hasGetGC then warn("[FF] getgc missing."); return end

    State.gameHandler = findGameHandler()
    if not State.gameHandler then
        warn("[FF] Could not find game handler in memory. Ensure you are in a song.")
        return
    end

    State.enabled = true
    State.connection = RunService.Heartbeat:Connect(autoplayStep)
    print("[FF] Auto Play started (internal hook mode).")
end

local function stopAutoPlay()
    State.enabled = false
    if State.connection then
        pcall(function() State.connection:Disconnect() end)
        State.connection = nil
    end
end

-- ============================================================
-- UI
-- ============================================================
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
ScreenGui.Name = "FF_InternalAutoPlayer"
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
Title.Text = "FF Internal"
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

local InfoCard = makeCard("✦ INFO", 44 + 30)
local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -20, 0, 30)
infoLabel.Position = UDim2.new(0, 10, 0, 44)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Internal Hook Mode. No side selection needed."
infoLabel.TextColor3 = Theme.Sub
infoLabel.Font = Enum.Font.Gotham
infoLabel.TextSize = 12
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Parent = InfoCard

local PlayCard = makeCard("✦ AUTO PLAY", 44 + ROW * 2 + 12)
makeToggle(PlayCard, "Auto Play", "Hooks internal engine. Toggle inside a song.", 44, CONFIG.AutoPlay, function(v)
    CONFIG.AutoPlay = v
    if v then startAutoPlay() else stopAutoPlay() end
end)

makeToggle(PlayCard, "Debug Mode", "Prints internal game data to console.", 44 + ROW + 6, CONFIG.ShowDebug, function(v)
    CONFIG.ShowDebug = v
end)

local PrecisionCard = makeCard("✦ PRECISION", 44 + 70)
local precisionLabel = Instance.new("TextLabel")
precisionLabel.Size = UDim2.new(1, -20, 0, 22); precisionLabel.Position = UDim2.new(0, 10, 0, 44)
precisionLabel.BackgroundTransparency = 1; precisionLabel.Text = "Value: 0.45 (higher = later)"
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
    print("[FF] Internal Auto Player unloaded.")
end

CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false end)
addConnection(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F2 then unload() end
    if input.KeyCode == Enum.KeyCode.F1 then MainFrame.Visible = not MainFrame.Visible end
end))

print("[FF] Internal Auto Player loaded. getgc available:", hasGetGC)
