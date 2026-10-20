
--[[
 DQR GILDED SKIES HUB V9 BETA
 Delta Android / Dungeon Quest Reborn

 Original implementation.
 UI inspired by AUR Hub.
 No external requests, webhook, or remote loader.

 Q = Enhanced Inner Focus
 E = Damage Spell

 Experimental movement, hazard and gate detection.
]]

print("[GS9] BOOT")

local started, startupError = pcall(function()

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local PFS = game:GetService("PathfindingService")
local WS = game:GetService("Workspace")

local player = Players.LocalPlayer
assert(player, "LocalPlayer missing")

local pg = player:WaitForChild("PlayerGui", 10)
assert(pg, "PlayerGui timeout")

-- Stop an older V9 copy.
if type(_G.GS9Cleanup) == "function" then
    pcall(_G.GS9Cleanup)
end

local previous = pg:FindFirstChild("GildedHubV9")
if previous then previous:Destroy() end

local cfg = {
    skills = true,
    move = true,
    dodge = true,
    gates = true,
    cooldown = 6,
    castDelay = 0.25,
    attackRange = 65,
    standoff = 32
}

local alive = true
local running = false
local epoch = 0
local casting = false
local lastQ = -math.huge
local state = "READY"
local kills = 0
local runStart = 0
local seenCombat = false
local lastEnemyTime = 0

local connections = {}
local enemies = {}
local hazards = {}
local gates = {}
local usedGates = {}
local logs = {}

local pathPoints = {}
local pathIndex = 1
local pathGoal = nil
local pathTime = 0
local pathSerial = 0
local planning = false
local scanning = false

local function on(signal, callback)
    local conn = signal:Connect(callback)
    table.insert(connections, conn)
    return conn
end

local function character()
    local model = player.Character
    if not model then return end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")

    if humanoid and root and humanoid.Health > 0 then
        return model, humanoid, root
    end
end

-- COLORS
local BG = Color3.fromRGB(18, 22, 32)
local PANEL = Color3.fromRGB(35, 40, 56)
local PINK = Color3.fromRGB(205, 54, 135)
local BLUE = Color3.fromRGB(56, 82, 126)
local RED = Color3.fromRGB(174, 48, 72)
local WHITE = Color3.fromRGB(244, 245, 249)

local gui = Instance.new("ScreenGui")
gui.Name = "GildedHubV9"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99999
gui.Parent = pg

local function make(class, parent, properties)
    local obj = Instance.new(class)

    for key, value in pairs(properties) do
        obj[key] = value
    end

    obj.Parent = parent
    return obj
end

local function round(obj)
    make("UICorner", obj, {
        CornerRadius = UDim.new(0, 7)
    })
end

local frame = make("Frame", gui, {
    Size = UDim2.fromOffset(332, 303),
    Position = UDim2.fromOffset(18, 72),
    BackgroundColor3 = BG,
    BorderSizePixel = 0
})
round(frame)

local function button(parent, name, x, y, w, h, color)
    local obj = make("TextButton", parent, {
        Text = name,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextColor3 = WHITE,
        BackgroundColor3 = color or PANEL,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h)
    })
    round(obj)
    return obj
end

local function label(parent, content, x, y, w, h)
    return make("TextLabel", parent, {
        Text = content,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextColor3 = WHITE,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h)
    })
end

-- HEADER
local title = button(
    frame, "GILDED HUB V9", 7, 7, 174, 35, PINK
)

local minus = button(frame, "-", 185, 7, 43, 35)
local plus = button(frame, "+", 233, 7, 43, 35)
local close = button(frame, "X", 281, 7, 43, 35, RED)

-- TABS
local tabs = {}
local pages = {}

local tabNames = {
    "FARM", "COMBAT", "SENSORS", "DEBUG"
}

for i, name in ipairs(tabNames) do
    tabs[i] = button(
        frame, name,
        7, 53 + (i - 1) * 49,
        78, 42
    )

    pages[i] = make("Frame", frame, {
        Size = UDim2.fromOffset(232, 207),
        Position = UDim2.fromOffset(93, 52),
        BackgroundColor3 = PANEL,
        BorderSizePixel = 0,
        Visible = i == 1
    })
    round(pages[i])
end

local function showTab(selected)
    for i, page in ipairs(pages) do
        page.Visible = i == selected
        tabs[i].BackgroundColor3 =
            i == selected and PINK or PANEL
    end
end

for i, tab in ipairs(tabs) do
    local selected = i
    on(tab.Activated, function()
        showTab(selected)
    end)
end

-- FARM PANEL
local farm = pages[1]
label(farm, "GILDED SKIES AUTOFARM", 8, 5, 216, 21)

local startBtn = button(
    farm, "START AUTOFARM", 8, 29, 216, 36, PINK
)

local skillsBtn = button(
    farm, "AUTO EIF + E: ON", 8, 70, 216, 31, PINK
)

local moveBtn = button(
    farm, "ADAPTIVE MOVE: ON", 8, 106, 216, 31, PINK
)

local dodgeBtn = button(
    farm, "EXPERIMENTAL DODGE: ON",
    8, 142, 216, 31, PINK
)

local stopBtn = button(
    farm, "EMERGENCY STOP", 8, 178, 216, 25, RED
)

-- COMBAT PANEL
local combat = pages[2]

label(combat, "EIF -> DAMAGE ROTATION", 8, 7, 216, 23)

local qTest = button(
    combat, "TEST Q", 8, 36, 103, 39, BLUE
)

local eTest = button(
    combat, "TEST E", 119, 36, 105, 39, BLUE
)

label(combat, "EIF COOLDOWN", 8, 87, 216, 23)

local cdMinus = button(
    combat, "-0.5", 8, 112, 65, 34
)

local cdValue = button(
    combat, "6.0s", 82, 112, 69, 34, BLUE
)

local cdPlus = button(
    combat, "+0.5", 160, 112, 64, 34
)

label(
    combat,
    "Q first, wait 0.25s, then E. Next cycle after EIF cooldown.",
    8, 157, 216, 44
)

-- SENSORS PANEL
local sensors = pages[3]

local enemyText = label(
    sensors, "ENEMIES: 0", 8, 8, 216, 25
)

local targetText = label(
    sensors, "TARGET: None", 8, 37, 216, 43
)

local hazardText = label(
    sensors, "HAZARDS: 0", 8, 84, 216, 25
)

local progressText = label(
    sensors, "PROGRESS: Unknown", 8, 113, 216, 25
)

local gateBtn = button(
    sensors, "AUTO NEXT ROOM: ON",
    8, 141, 216, 29, PINK
)

local scanBtn = button(
    sensors, "RESCAN WORLD", 8, 175, 216, 28, BLUE
)

-- DEBUG PANEL
local debugPage = pages[4]

local debugText = label(
    debugPage, "Waiting for events...",
    8, 6, 216, 156
)
debugText.TextYAlignment = Enum.TextYAlignment.Top
debugText.TextSize = 11

local removeBtn = button(
    debugPage, "REMOVE HUB", 8, 174, 216, 28, RED
)

local footer = label(
    frame, "READY | Waiting for START",
    8, 269, 316, 26
)

-- MOBILE FLOATING BUTTON
local reopen = button(
    gui, "OPEN GILDED HUB",
    15, 72, 148, 40, PINK
)
reopen.Visible = false

local floatStop = button(
    gui, "STOP FARM", 169, 72, 115, 40, RED
)
floatStop.Visible = false

local function log(message)
    if not alive then return end

    message = tostring(message)
    print("[GS9] " .. message)

    table.insert(logs, 1, message)

    while #logs > 6 do
        table.remove(logs)
    end

    debugText.Text = table.concat(logs, "\n\n")
end

local function setState(value)
    state = value
    footer.Text = "STATE: " .. value
end

print("[GS9] GUI READY")
log("GUI READY")

-- DRAG + RESIZE
local scale = Instance.new("UIScale")
scale.Scale = 0.9
scale.Parent = frame

local sizes = {0.65, 0.8, 0.9, 1, 1.15, 1.3}
local sizeIndex = 3

on(minus.Activated, function()
    sizeIndex = math.max(1, sizeIndex - 1)
    scale.Scale = sizes[sizeIndex]
end)

on(plus.Activated, function()
    sizeIndex = math.min(#sizes, sizeIndex + 1)
    scale.Scale = sizes[sizeIndex]
end)

on(close.Activated, function()
    frame.Visible = false
    reopen.Visible = true
    floatStop.Visible = running
end)

on(reopen.Activated, function()
    frame.Visible = true
    reopen.Visible = false
    floatStop.Visible = false
end)

local dragging = false
local dragStart
local dragOrigin
local touchInput

on(title.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType ==
            Enum.UserInputType.MouseButton1 then

        dragging = true
        dragStart = input.Position
        dragOrigin = frame.Position

        touchInput =
            input.UserInputType == Enum.UserInputType.Touch
            and input or nil
    end
end)

on(UIS.InputChanged, function(input)
    if not dragging then return end
    if touchInput and touchInput ~= input then return end

    if not touchInput and input.UserInputType ~=
        Enum.UserInputType.MouseMovement then
        return
    end

    local delta = input.Position - dragStart

    frame.Position = UDim2.fromOffset(
        dragOrigin.X.Offset + delta.X,
        dragOrigin.Y.Offset + delta.Y
    )
end)

on(UIS.InputEnded, function(input)
    if (touchInput and touchInput == input)
        or (not touchInput and input.UserInputType ==
            Enum.UserInputType.MouseButton1) then

        dragging = false
        touchInput = nil
    end
end)

-- VIRTUAL INPUT
local function sendKey(key)
    local ok, errorText = pcall(function()
        local vim = game:GetService("VirtualInputManager")

        vim:SendKeyEvent(true, key, false, game)
        task.wait(0.08)
        vim:SendKeyEvent(false, key, false, game)
    end)

    if not ok then
        log("INPUT ERROR: " .. tostring(errorText):sub(1, 60))
    end

    return ok
end

on(qTest.Activated, function()
    if not running then
        sendKey(Enum.KeyCode.Q)
    end
end)

on(eTest.Activated, function()
    if not running then
        sendKey(Enum.KeyCode.E)
    end
end)

on(cdMinus.Activated, function()
    if running then return end

    cfg.cooldown = math.max(4, cfg.cooldown - 0.5)
    cdValue.Text = string.format("%.1fs", cfg.cooldown)
end)

on(cdPlus.Activated, function()
    if running then return end

    cfg.cooldown = math.min(20, cfg.cooldown + 0.5)
    cdValue.Text = string.format("%.1fs", cfg.cooldown)
end)

local function toggleText(obj, prefix, value)
    obj.Text = prefix .. (value and "ON" or "OFF")
    obj.BackgroundColor3 = value and PINK or BLUE
end

on(skillsBtn.Activated, function()
    cfg.skills = not cfg.skills
    toggleText(skillsBtn, "AUTO EIF + E: ", cfg.skills)
end)

on(moveBtn.Activated, function()
    cfg.move = not cfg.move
    toggleText(moveBtn, "ADAPTIVE MOVE: ", cfg.move)
end)

on(dodgeBtn.Activated, function()
    cfg.dodge = not cfg.dodge
    toggleText(
        dodgeBtn, "EXPERIMENTAL DODGE: ", cfg.dodge
    )
end)

on(gateBtn.Activated, function()
    cfg.gates = not cfg.gates
    toggleText(gateBtn, "AUTO NEXT ROOM: ", cfg.gates)
end)

-- GILDED SKIES ENTITY NAMES
local mobPatterns = {
    "dracani",
    "kiryne",
    "cragg",
    "vytelus"
}

local attackPatterns = {
    "dracanimageattack",
    "archpriestwavecircles",
    "craggcursedflame",
    "craggpinkline",
    "craggredline",
    "craggxline",
    "craggnightmaregroundslam",
    "craggnightmarelines",
    "vyteluslaserbeam",
    "vytelusflamewall",
    "vyteluspinkcirclemarkers",
    "thirdbossfireball",
    "thirdbossflamewall"
}

local safePatterns = {
    "archpriestsafezones",
    "vytelusmemorysafezone",
    "vytelussafezones",
    "thirdbosssafezones"
}

local function contains(text, patterns)
    text = string.lower(tostring(text))

    for _, pattern in ipairs(patterns) do
        if string.find(text, pattern, 1, true) then
            return true
        end
    end

    return false
end

-- DETECT ENEMIES
local function registerEnemy(model)
    if not model or not model:IsA("Model") then return end
    if enemies[model] then return end
    if Players:GetPlayerFromCharacter(model) then return end

    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart

    if not hum or not root then return end

    local recognized =
        contains(model.Name, mobPatterns)
        or CS:HasTag(model, "Enemy")

    if not recognized then return end

    enemies[model] = {
        hum = hum,
        root = root,
        counted = false
    }

    on(hum.Died, function()
        local entry = enemies[model]

        if entry and not entry.counted then
            entry.counted = true
            kills = kills + 1
            log("DEFEATED: " .. model.Name)
        end
    end)

    log("MOB: " .. model.Name)
end

-- DETECT HAZARD CANDIDATES
local function inspectPart(part)
    if not part:IsA("BasePart") then return end

    local partName = string.lower(part.Name)
    local fullName = partName
    local parent = part.Parent

    for _ = 1, 3 do
        if not parent or parent == WS then break end

        fullName = fullName .. " " ..
            string.lower(parent.Name)

        parent = parent.Parent
    end

    if contains(fullName, safePatterns) then
        return
    end

    local known = contains(fullName, attackPatterns)

    local telegraph =
        contains(fullName, mobPatterns)
        and contains(partName, {
            "precast", "hitbox", "telegraph"
        })

    if (known or telegraph) and not hazards[part] then
        hazards[part] = {
            spawned = os.clock()
        }
    end

    if contains(partName, {
        "dungeongate",
        "nextroom",
        "dungeonexit",
        "checkpoint",
        "portal"
    }) then
        gates[part] = true
    end
end

local function inspect(obj)
    if not alive then return end

    if obj:IsA("Model") then
        registerEnemy(obj)
    elseif obj:IsA("Humanoid") then
        registerEnemy(obj.Parent)
    elseif obj:IsA("BasePart") then
        inspectPart(obj)
    end
end

on(WS.DescendantAdded, inspect)

on(CS:GetInstanceAddedSignal("Enemy"), function(obj)
    if obj:IsA("Model") then
        registerEnemy(obj)
    else
        registerEnemy(obj:FindFirstAncestorOfClass("Model"))
    end
end)

local function scanWorld()
    if scanning or not alive then return end
    scanning = true
    log("WORLD SCAN START")

    local ok, errorText = pcall(function()
        for _, obj in ipairs(CS:GetTagged("Enemy")) do
            if obj:IsA("Model") then
                registerEnemy(obj)
            else
                registerEnemy(
                    obj:FindFirstAncestorOfClass("Model")
                )
            end
        end

        local objects = WS:GetDescendants()

        for i, obj in ipairs(objects) do
            if not alive then break end

            inspect(obj)

            if i % 250 == 0 then
                task.wait()
            end
        end
    end)

    scanning = false

    if ok then
        log("WORLD SCAN COMPLETE")
    else
        log("SCAN ERROR: " ..
            tostring(errorText):sub(1, 55))
    end
end

on(scanBtn.Activated, function()
    task.spawn(scanWorld)
end)

-- SELECT NEAREST LIVE TARGET
local function chooseTarget(root)
    local target = nil
    local nearest = math.huge
    local count = 0

    for model, data in pairs(enemies) do
        if model.Parent
            and data.root.Parent
            and data.hum.Health > 0 then

            count = count + 1

            local distance =
                (data.root.Position - root.Position).Magnitude

            if distance < nearest then
                nearest = distance
                target = {
                    model = model,
                    hum = data.hum,
                    root = data.root
                }
            end
        end
    end

    return target, nearest, count
end

-- ESTIMATED HAZARD GEOMETRY
local function dangerAt(position)
    local danger = 0
    local count = 0
    local now = os.clock()

    for part, data in pairs(hazards) do
        if not part.Parent
            or now - data.spawned > 12 then

            hazards[part] = nil
        else
            count = count + 1

            local localPos =
                part.CFrame:PointToObjectSpace(position)

            local half = part.Size * 0.5

            if math.abs(localPos.Y) < half.Y + 8 then
                local dx = math.max(
                    math.abs(localPos.X) - half.X, 0
                )

                local dz = math.max(
                    math.abs(localPos.Z) - half.Z, 0
                )

                local gap = math.sqrt(dx * dx + dz * dz)

                if gap < 4 then
                    danger = danger + 100
                elseif gap < 15 then
                    danger = danger + (15 - gap) * 4
                end
            end
        end
    end

    return danger, count
end

-- CHOOSE A CANDIDATE SAFE DIRECTION
local function dodgeDestination(char, root)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    params.RespectCanCollide = true

    local currentDanger = dangerAt(root.Position)
    local best, bestScore

    for _, radius in ipairs({13, 24, 35}) do
        for i = 1, 12 do
            local angle = 2 * math.pi * i / 12

            local flat = Vector3.new(
                math.cos(angle) * radius,
                0,
                math.sin(angle) * radius
            )

            local candidate = root.Position + flat

            local ground = WS:Raycast(
                candidate + Vector3.new(0, 9, 0),
                Vector3.new(0, -28, 0),
                params
            )

            local wall = WS:Raycast(
                root.Position + Vector3.new(0, 2, 0),
                flat,
                params
            )

            if ground and not wall then
                candidate = Vector3.new(
                    candidate.X,
                    ground.Position.Y + 3,
                    candidate.Z
                )

                local score = dangerAt(candidate) * 10
                    + radius * 0.15

                if not best or score < bestScore then
                    best = candidate
                    bestScore = score
                end
            end
        end
    end

    if best and bestScore < currentDanger * 8 then
        return best
    end
end

-- ADAPTIVE PATHFINDING
local function clearPath()
    pathSerial = pathSerial + 1
    pathPoints = {}
    pathIndex = 1
    pathGoal = nil
    planning = false
end

local function navigate(hum, root, goal)
    if not goal or not running then return end

    local now = os.clock()

    local needsPath =
        not pathGoal
        or (goal - pathGoal).Magnitude > 12
        or now - pathTime > 3

    if needsPath and not planning then
        planning = true
        pathTime = now
        pathGoal = goal

        pathSerial = pathSerial + 1
        local serial = pathSerial
        local runEpoch = epoch
        local from = root.Position

        task.spawn(function()
            local ok, result = pcall(function()
                local path = PFS:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                    WaypointSpacing = 6
                })

                path:ComputeAsync(from, goal)

                if path.Status == Enum.PathStatus.Success then
                    return path:GetWaypoints()
                end

                return {}
            end)

            if not alive or not running
                or epoch ~= runEpoch
                or pathSerial ~= serial then
                return
            end

            pathPoints = ok and result or {}
            pathIndex = #pathPoints >= 2 and 2 or 1
            planning = false

            if not ok then
                log("PATH COMPUTE FAILED")
            end
        end)
    end

    local destination = goal
    local wp = pathPoints[pathIndex]

    while wp and
        (root.Position - wp.Position).Magnitude < 5 do

        pathIndex = pathIndex + 1
        wp = pathPoints[pathIndex]
    end

    if wp then
        destination = wp.Position

        if wp.Action == Enum.PathWaypointAction.Jump then
            hum.Jump = true
        end
    end

    hum:MoveTo(destination)
end

-- OPEN-GATE HEURISTIC
local function nextGate(root)
    local nearest = nil
    local distance = math.huge

    for part in pairs(gates) do
        if part.Parent and not usedGates[part]
            and not part.CanCollide then

            local d =
                (part.Position - root.Position).Magnitude

            if d > 6 and d < 160 and d < distance then
                nearest = part
                distance = d
            end
        end
    end

    return nearest, distance
end

-- HUD MECHANIC DETECTION
local function readHud()
    local lookAway = false
    local completed = false

    for _, obj in ipairs(pg:GetDescendants()) do
        if obj:IsA("TextLabel")
            and obj.Visible
            and not obj:IsDescendantOf(gui) then

            local message = string.upper(obj.Text)

            if message:find("LOOK AWAY", 1, true) then
                lookAway = true
            end

            if message:find("DUNGEON COMPLETED", 1, true)
                or message:find("VICTORY", 1, true) then
                completed = true
            end
        end
    end

    return lookAway, completed
end

-- EIF -> DAMAGE ROTATION
local function runAbilities(target, distance)
    if not running or not cfg.skills or casting then
        return
    end

    if not target or distance > cfg.attackRange then
        return
    end

    if os.clock() - lastQ < cfg.cooldown then
        return
    end

    casting = true
    lastQ = os.clock()

    local castEpoch = epoch

    task.spawn(function()
        setState("CASTING EIF")

        local ok = sendKey(Enum.KeyCode.Q)

        if ok then
            task.wait(cfg.castDelay)

            if running and epoch == castEpoch then
                setState("CASTING DAMAGE")
                sendKey(Enum.KeyCode.E)
            end
        else
            lastQ = -math.huge
        end

        if epoch == castEpoch then
            casting = false
        end
    end)
end

-- STOP & CLEANUP
local function stopFarm()
    running = false
    epoch = epoch + 1
    casting = false

    clearPath()
    startBtn.Text = "START AUTOFARM"
    floatStop.Visible = false

    local char, hum, root = character()

    if hum and root then
        hum:MoveTo(root.Position)
    end

    setState("STOPPED")
    log("FARM STOPPED")
end

_G.GS9Cleanup = function()
    alive = false
    running = false
    epoch = epoch + 1

    for _, conn in ipairs(connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end

    if gui.Parent then
        gui:Destroy()
    end
end

on(stopBtn.Activated, stopFarm)
on(floatStop.Activated, stopFarm)
on(removeBtn.Activated, _G.GS9Cleanup)

on(startBtn.Activated, function()
    if running then
        stopFarm()
        return
    end

    local char, hum, root = character()

    if not root then
        log("CHARACTER NOT READY")
        return
    end

    local dungeon = WS:FindFirstChild("dungeonName")

    if dungeon and dungeon:IsA("StringValue")
        and dungeon.Value ~= "Gilded Skies" then

        log("WRONG DUNGEON: " .. dungeon.Value)
        return
    end

    running = true
    epoch = epoch + 1
    runStart = os.clock()
    lastQ = -math.huge
    casting = false
    seenCombat = false
    lastEnemyTime = os.clock()

    clearPath()
    startBtn.Text = "FARM RUNNING"

    floatStop.Visible = not frame.Visible

    task.spawn(scanWorld)

    setState("SEARCHING ENEMIES")
    log("FARM STARTED")
end)

-- CONTINUOUS CONTROLLER
task.spawn(function()
    local lastUI = 0
    local lastHud = 0
    local lastScan = 0
    local lastMove = 0
    local lastStuck = 0

    local previousPosition = nil
    local lookAway = false
    local victory = false
    local failures = 0
    local lastProgress = ""

    while alive and gui.Parent do
        task.wait(0.3)

        local ok, errorText = pcall(function()
            local now = os.clock()

            -- Rescan periodically for newly loaded rooms.
            if now - lastScan > 18 and not scanning then
                lastScan = now
                task.spawn(scanWorld)
            end

            local char, hum, root = character()

            if not root then
                if running then stopFarm() end
                return
            end

            local target, distance, count =
                chooseTarget(root)

            if count > 0 then
                seenCombat = true
                lastEnemyTime = now
            end

            local risk, hazardCount =
                dangerAt(root.Position)

            if now - lastHud > 1 then
                lastHud = now
                lookAway, victory = readHud()
            end

            -- Read progressive dungeon state.
            local progressNames = {
                "dungeonProgress",
                "currentWave",
                "dungeonStarted"
            }

            local progressParts = {}

            for _, name in ipairs(progressNames) do
                local obj = WS:FindFirstChild(name)

                if obj and obj:IsA("ValueBase") then
                    table.insert(
                        progressParts,
                        name .. "=" .. tostring(obj.Value)
                    )
                end
            end

            local progress = #progressParts > 0
                and table.concat(progressParts, " | ")
                or "Unavailable"

            if progress ~= lastProgress then
                lastProgress = progress
                log("PROGRESS: " .. progress)
            end

            if running then
                if victory then
                    stopFarm()
                    setState("DUNGEON COMPLETED")
                    log("DUNGEON COMPLETED")

                elseif lookAway then
                    -- Mechanic is detected, but automatic
                    -- turning has not been validated.
                    setState("LOOK AWAY - MANUAL")
                    hum:MoveTo(root.Position)

                elseif cfg.dodge and risk >= 25 then
                    local safe = dodgeDestination(char, root)

                    if safe then
                        setState("DODGING")
                        hum:MoveTo(safe)
                    else
                        setState("HAZARD - NO SAFE SPOT")
                    end

                elseif target then
                    if cfg.move
                        and now - lastMove > 0.55 then

                        lastMove = now

                        if distance > cfg.standoff then
                            local vector =
                                target.root.Position -
                                root.Position

                            local flat = Vector3.new(
                                vector.X, 0, vector.Z
                            )

                            if flat.Magnitude > 1 then
                                local goal =
                                    target.root.Position
                                    - flat.Unit * cfg.standoff

                                navigate(hum, root, goal)
                                setState("NAVIGATING")
                            end
                        else
                            hum:MoveTo(root.Position)
                            setState("COMBAT RANGE")
                        end
                    end

                    if risk < 25 then
                        runAbilities(target, distance)
                    end

                else
                    setState("WAITING FOR NEXT WAVE")

                    -- Only look for the next area
                    -- after previously seeing enemies.
                    if cfg.gates and cfg.move
                        and seenCombat
                        and now - lastEnemyTime > 3
                        and now - lastMove > 0.55 then

                        lastMove = now

                        local gate, gateDistance =
                            nextGate(root)

                        if gate then
                            if gateDistance < 9 then
                                usedGates[gate] = true
                            else
                                setState("NEXT ROOM")
                                navigate(
                                    hum, root, gate.Position
                                )
                            end
                        end
                    end
                end

                -- Replan if navigation appears stuck.
                if now - lastStuck > 4 then
                    lastStuck = now

                    if previousPosition and target
                        and cfg.move
                        and distance > cfg.standoff + 10
                        and (
                            root.Position - previousPosition
                        ).Magnitude < 2 then

                        clearPath()
                        log("STUCK: PATH RESET")
                    end

                    previousPosition = root.Position
                end
            end

            if now - lastUI > 0.8 then
                lastUI = now

                enemyText.Text =
                    "ENEMIES ALIVE: " .. count

                targetText.Text =
                    "TARGET: " .. (
                        target and target.model.Name or "None"
                    )

                hazardText.Text =
                    "HAZARDS TRACKED: " .. hazardCount

                progressText.Text =
                    "PROGRESS: " .. progress

                footer.Text = "STATE: " .. state ..
                    " | KILLS: " .. kills
            end
        end)

        if ok then
            failures = 0
        else
            failures = failures + 1

            log("LOOP ERROR: " ..
                tostring(errorText):sub(1, 70))

            if failures >= 3 then
                if running then stopFarm() end
                log("AUTO STOP AFTER 3 ERRORS")
                failures = 0
            end
        end
    end
end)

-- START SENSORS AFTER UI IS READY
task.defer(scanWorld)

log("CONTROLLER READY")
print("[GS9] COMPLETE")

end)

if not started then
    warn("[GS9] STARTUP ERROR: " ..
        tostring(startupError))
end
