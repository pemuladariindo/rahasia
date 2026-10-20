
--[[
 GILDED HUB V9.1 - FAST + AUTO RESPAWN
 Dungeon Quest Reborn / Delta Android

 Changes:
 - Faster movement updates
 - Adjustable speed boost
 - Faster dodge decisions
 - Auto resume after death
 - Event-based enemy scanning
 - Responsive UI based on working V9

 No external HTTP, webhook, or loader.
]]

print("[GS91] BOOT START")

local bootOK, bootError = pcall(function()

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local PFS = game:GetService("PathfindingService")
local WS = game:GetService("Workspace")
local VIM = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
assert(player, "LocalPlayer missing")

local pg = player:WaitForChild("PlayerGui", 10)
assert(pg, "PlayerGui timeout")

-- Clean up V9 / V9.1 if already running
if type(_G.GS9Cleanup) == "function" then
    pcall(_G.GS9Cleanup)
end

local previous = pg:FindFirstChild("GildedHubV91")
if previous then previous:Destroy() end

local cfg = {
    skills = true,
    movement = true,
    dodge = true,
    gates = true,
    autoResume = true,
    fast = true,

    speed = 28,
    cooldown = 6,
    castDelay = 0.25,
    attackRange = 65,
    standoff = 32,

    moveInterval = 0.15,
    dodgeHold = 0.4,
    pathRefresh = 1.8
}

local active = true
local running = false
local epoch = 0
local casting = false
local respawning = false

local state = "READY"
local lastQ = -math.huge
local lastEnemyAt = 0
local seenEnemies = false
local kills = 0

local enemies = {}
local hazards = {}
local gates = {}
local visitedGates = {}
local connections = {}
local logLines = {}

local pathPoints = {}
local pathIndex = 1
local pathGoal
local pathAt = 0
local pathSerial = 0
local planning = false
local scanning = false

local lastMoveAt = 0
local lastMoveGoal
local dodgeUntil = 0
local dodgeGoal
local lastSpeedCheck = 0

local originalSpeed = setmetatable({}, {
    __mode = "k"
})

local function on(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end

local function character()
    local char = player.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    if hum and root and hum.Health > 0 then
        return char, hum, root
    end
end

-- THEME
local BG = Color3.fromRGB(18,22,32)
local PANEL = Color3.fromRGB(35,40,56)
local PINK = Color3.fromRGB(205,54,135)
local BLUE = Color3.fromRGB(56,82,126)
local RED = Color3.fromRGB(174,48,72)
local WHITE = Color3.fromRGB(244,245,249)

local function make(class, parent, props)
    local obj = Instance.new(class)
    for k,v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

local function round(obj)
    make("UICorner",obj,{
        CornerRadius = UDim.new(0,7)
    })
end

-- CREATE GUI FIRST
local gui = make("ScreenGui",pg,{
    Name = "GildedHubV91",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 99999
})

local frame = make("Frame",gui,{
    Size = UDim2.fromOffset(332,303),
    Position = UDim2.fromOffset(18,72),
    BackgroundColor3 = BG,
    BorderSizePixel = 0
})
round(frame)

local function button(parent,text,x,y,w,h,color)
    local b = make("TextButton",parent,{
        Text = text,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextColor3 = WHITE,
        BackgroundColor3 = color or PANEL,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(x,y),
        Size = UDim2.fromOffset(w,h)
    })
    round(b)
    return b
end

local function label(parent,text,x,y,w,h)
    return make("TextLabel",parent,{
        Text = text,
        TextSize = 12,
        Font = Enum.Font.Gotham,
        TextColor3 = WHITE,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(x,y),
        Size = UDim2.fromOffset(w,h)
    })
end

-- HEADER
local title = button(
    frame,"GILDED HUB V9.1",7,7,174,35,PINK
)
local minus = button(frame,"-",185,7,43,35)
local plus = button(frame,"+",233,7,43,35)
local hide = button(frame,"X",281,7,43,35,RED)

-- TABS
local pages = {}
local tabs = {}

for i,name in ipairs({
    "FARM","COMBAT","SENSORS","DEBUG"
}) do
    tabs[i] = button(
        frame,name,7,53+(i-1)*49,78,42
    )

    pages[i] = make("Frame",frame,{
        Size = UDim2.fromOffset(232,207),
        Position = UDim2.fromOffset(93,52),
        BackgroundColor3 = PANEL,
        BorderSizePixel = 0,
        Visible = i == 1
    })
    round(pages[i])
end

local function showTab(n)
    for i,page in ipairs(pages) do
        page.Visible = i == n
        tabs[i].BackgroundColor3 =
            i == n and PINK or PANEL
    end
end

for i,tab in ipairs(tabs) do
    local n = i
    on(tab.Activated,function()
        showTab(n)
    end)
end

-- FARM
local farm = pages[1]

label(farm,"GILDED SKIES | FAST FARM",8,3,216,20)

local startBtn = button(
    farm,"START AUTOFARM",8,26,216,33,PINK
)
local skillBtn = button(
    farm,"AUTO EIF + E: ON",8,63,216,26,PINK
)
local moveBtn = button(
    farm,"FAST NAVIGATION: ON",8,93,216,26,PINK
)
local dodgeBtn = button(
    farm,"DODGE: ON",8,123,216,26,PINK
)
local resumeBtn = button(
    farm,"AUTO RESPAWN: ON",8,153,216,26,PINK
)
local stopBtn = button(
    farm,"EMERGENCY STOP",8,183,216,21,RED
)

-- COMBAT
local combat = pages[2]

label(combat,"EIF -> DAMAGE",8,5,216,20)

local testQ = button(
    combat,"TEST Q",8,28,103,35,BLUE
)
local testE = button(
    combat,"TEST E",119,28,105,35,BLUE
)

label(combat,"EIF COOLDOWN",8,70,216,18)

local cdMinus = button(
    combat,"-0.5",8,91,65,29
)
local cdText = button(
    combat,"6.0s",82,91,69,29,BLUE
)
local cdPlus = button(
    combat,"+0.5",160,91,64,29
)

label(combat,"MOVEMENT SPEED",8,128,216,19)

local speedMinus = button(
    combat,"-2",8,151,65,29
)
local speedText = button(
    combat,"28",82,151,69,29,BLUE
)
local speedPlus = button(
    combat,"+2",160,151,64,29
)

local boostBtn = button(
    combat,"SPEED BOOST: ON",
    8,184,216,20,PINK
)

-- SENSORS
local sensors = pages[3]

local enemyText = label(
    sensors,"ENEMIES: 0",8,8,216,25
)
local targetText = label(
    sensors,"TARGET: None",8,37,216,43
)
local hazardText = label(
    sensors,"HAZARDS: 0",8,85,216,25
)
local speedInfo = label(
    sensors,"ACTUAL SPEED: --",8,113,216,25
)

local gateBtn = button(
    sensors,"AUTO NEXT ROOM: ON",
    8,145,216,28,PINK
)
local scanBtn = button(
    sensors,"RESCAN WORLD",8,178,216,26,BLUE
)

-- DEBUG
local debug = pages[4]

local debugText = label(
    debug,"Waiting for logs...",8,6,216,162
)
debugText.TextYAlignment = Enum.TextYAlignment.Top
debugText.TextSize = 11

local removeBtn = button(
    debug,"REMOVE HUB",8,178,216,26,RED
)

-- FOOTER
local footer = label(
    frame,"READY",8,268,315,28
)

local reopen = button(
    gui,"OPEN GILDED HUB",15,72,148,40,PINK
)
reopen.Visible = false

local floatStop = button(
    gui,"STOP FARM",169,72,115,40,RED
)
floatStop.Visible = false

local function log(message)
    if not active then return end
    message = tostring(message)

    print("[GS91] "..message)
    table.insert(logLines,1,message)

    while #logLines > 6 do
        table.remove(logLines)
    end

    debugText.Text = table.concat(logLines,"\n\n")
end

local function setState(message)
    state = message
    footer.Text = "STATE: "..message
end

print("[GS91] GUI READY")
log("GUI READY")

-- RESIZE
local scale = make("UIScale",frame,{
    Scale = 0.9
})

local sizes = {0.65,0.8,0.9,1,1.15,1.3}
local sizeIndex = 3

on(minus.Activated,function()
    sizeIndex = math.max(1,sizeIndex-1)
    scale.Scale = sizes[sizeIndex]
end)

on(plus.Activated,function()
    sizeIndex = math.min(#sizes,sizeIndex+1)
    scale.Scale = sizes[sizeIndex]
end)

on(hide.Activated,function()
    frame.Visible = false
    reopen.Visible = true
    floatStop.Visible = running
end)

on(reopen.Activated,function()
    frame.Visible = true
    reopen.Visible = false
    floatStop.Visible = false
end)

-- DRAG
local dragging = false
local dragStart,dragOrigin,touchInput

on(title.InputBegan,function(input)
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

on(UIS.InputChanged,function(input)
    if not dragging then return end
    if touchInput and touchInput ~= input then return end

    if not touchInput and input.UserInputType ~=
        Enum.UserInputType.MouseMovement then
        return
    end

    local d = input.Position-dragStart

    frame.Position = UDim2.fromOffset(
        dragOrigin.X.Offset+d.X,
        dragOrigin.Y.Offset+d.Y
    )
end)

on(UIS.InputEnded,function(input)
    if (touchInput and touchInput == input)
        or (not touchInput and input.UserInputType ==
            Enum.UserInputType.MouseButton1) then

        dragging = false
        touchInput = nil
    end
end)

-- ABILITY INPUT
local function sendKey(key)
    local ok,err = pcall(function()
        VIM:SendKeyEvent(true,key,false,game)
        task.wait(0.08)
        VIM:SendKeyEvent(false,key,false,game)
    end)

    if not ok then
        log("INPUT ERROR: "..tostring(err):sub(1,65))
    end

    return ok
end

on(testQ.Activated,function()
    if not running then
        sendKey(Enum.KeyCode.Q)
    end
end)

on(testE.Activated,function()
    if not running then
        sendKey(Enum.KeyCode.E)
    end
end)

on(cdMinus.Activated,function()
    if running then return end
    cfg.cooldown = math.max(4,cfg.cooldown-0.5)
    cdText.Text = string.format("%.1fs",cfg.cooldown)
end)

on(cdPlus.Activated,function()
    if running then return end
    cfg.cooldown = math.min(20,cfg.cooldown+0.5)
    cdText.Text = string.format("%.1fs",cfg.cooldown)
end)

on(speedMinus.Activated,function()
    cfg.speed = math.max(16,cfg.speed-2)
    speedText.Text = tostring(cfg.speed)
end)

on(speedPlus.Activated,function()
    cfg.speed = math.min(32,cfg.speed+2)
    speedText.Text = tostring(cfg.speed)
end)

local function toggle(button,prefix,enabled)
    button.Text = prefix..
        (enabled and "ON" or "OFF")

    button.BackgroundColor3 =
        enabled and PINK or BLUE
end

on(skillBtn.Activated,function()
    cfg.skills = not cfg.skills
    toggle(skillBtn,"AUTO EIF + E: ",cfg.skills)
end)

on(moveBtn.Activated,function()
    cfg.movement = not cfg.movement
    toggle(moveBtn,"FAST NAVIGATION: ",cfg.movement)
end)

on(dodgeBtn.Activated,function()
    cfg.dodge = not cfg.dodge
    toggle(dodgeBtn,"DODGE: ",cfg.dodge)
end)

on(resumeBtn.Activated,function()
    cfg.autoResume = not cfg.autoResume
    toggle(resumeBtn,"AUTO RESPAWN: ",cfg.autoResume)
end)

on(gateBtn.Activated,function()
    cfg.gates = not cfg.gates
    toggle(gateBtn,"AUTO NEXT ROOM: ",cfg.gates)
end)

-- SPEED MANAGEMENT
local function restoreSpeed(hum)
    if not hum then return end

    local previous = originalSpeed[hum]
    if previous then
        pcall(function()
            hum.WalkSpeed = previous
        end)
        originalSpeed[hum] = nil
    end
end

local function applySpeed(hum)
    if not hum then return end

    if not cfg.fast then
        restoreSpeed(hum)
        return
    end

    if not originalSpeed[hum] then
        originalSpeed[hum] = hum.WalkSpeed
    end

    if hum.WalkSpeed < cfg.speed then
        hum.WalkSpeed = cfg.speed
    end
end

on(boostBtn.Activated,function()
    cfg.fast = not cfg.fast
    toggle(boostBtn,"SPEED BOOST: ",cfg.fast)

    if not cfg.fast then
        local char,hum = character()
        restoreSpeed(hum)
    end
end)

-- ENTITY RECOGNITION
local mobNames = {
    "dracani","kiryne","cragg","vytelus"
}

local hazardNames = {
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

local safeNames = {
    "archpriestsafezones",
    "vytelusmemorysafezone",
    "vytelussafezones",
    "thirdbosssafezones"
}

local function contains(text,patterns)
    text = string.lower(tostring(text))

    for _,pattern in ipairs(patterns) do
        if string.find(text,pattern,1,true) then
            return true
        end
    end

    return false
end

local function registerEnemy(model)
    if not model or not model:IsA("Model") then
        return
    end

    if enemies[model] then return end
    if Players:GetPlayerFromCharacter(model) then
        return
    end

    local recognized =
        contains(model.Name,mobNames)
        or CS:HasTag(model,"Enemy")

    if not recognized then return end

    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart

    if not hum or not root then return end
    if not root:IsA("BasePart") then return end

    enemies[model] = {
        hum = hum,
        root = root,
        counted = false
    }

    on(hum.Died,function()
        local info = enemies[model]
        if info and not info.counted then
            info.counted = true
            kills = kills+1
        end
    end)

    log("MOB: "..model.Name)
end

local function inspectPart(part)
    if not part:IsA("BasePart") then return end

    -- A model may receive its root after spawning.
    registerEnemy(part.Parent)

    local name = string.lower(part.Name)
    local combined = name
    local parent = part.Parent

    for _ = 1,3 do
        if not parent or parent == WS then break end
        combined = combined.." "..
            string.lower(parent.Name)
        parent = parent.Parent
    end

    if contains(combined,safeNames) then
        return
    end

    local known = contains(combined,hazardNames)
    local telegraph =
        contains(combined,mobNames)
        and contains(name,{
            "precast","hitbox","telegraph"
        })

    if known or telegraph then
        if not hazards[part] then
            hazards[part] = {
                created = os.clock()
            }
        end
    end

    if contains(name,{
        "dungeongate","nextroom",
        "dungeonexit","checkpoint","portal"
    }) then
        gates[part] = true
    end
end

local function inspect(obj)
    if not active then return end

    if obj:IsA("Model") then
        registerEnemy(obj)
    elseif obj:IsA("Humanoid") then
        registerEnemy(obj.Parent)
    elseif obj:IsA("BasePart") then
        inspectPart(obj)
    end
end

on(WS.DescendantAdded,inspect)

on(CS:GetInstanceAddedSignal("Enemy"),function(obj)
    if obj:IsA("Model") then
        registerEnemy(obj)
    else
        registerEnemy(
            obj:FindFirstAncestorOfClass("Model")
        )
    end
end)

-- FULL SCAN: INITIAL OR MANUAL ONLY
local function scanWorld()
    if scanning or not active then return end

    scanning = true
    log("SCAN START")

    local ok,err = pcall(function()
        local items = WS:GetDescendants()

        for i,obj in ipairs(items) do
            if not active then break end
            inspect(obj)

            if i%300 == 0 then
                task.wait()
            end
        end

        for _,obj in ipairs(CS:GetTagged("Enemy")) do
            if obj:IsA("Model") then
                registerEnemy(obj)
            else
                registerEnemy(
                    obj:FindFirstAncestorOfClass("Model")
                )
            end
        end
    end)

    scanning = false

    if ok then
        log("SCAN COMPLETE")
    else
        log("SCAN ERROR: "..tostring(err):sub(1,60))
    end
end

on(scanBtn.Activated,function()
    task.spawn(scanWorld)
end)

-- TARGET SELECTION
local function selectTarget(root)
    local target
    local nearest = math.huge
    local count = 0

    for model,info in pairs(enemies) do
        if not model.Parent then
            enemies[model] = nil

        elseif info.hum.Parent
            and info.root.Parent
            and info.hum.Health > 0 then

            count = count+1

            local d = (
                info.root.Position-root.Position
            ).Magnitude

            if d < nearest then
                nearest = d
                target = {
                    model = model,
                    hum = info.hum,
                    root = info.root
                }
            end
        end
    end

    return target,nearest,count
end

-- HAZARD RISK
local function dangerAt(position)
    local risk = 0
    local count = 0
    local now = os.clock()

    for part,data in pairs(hazards) do
        if not part.Parent
            or now-data.created > 9 then

            hazards[part] = nil

        else
            count = count+1

            -- Ignore very distant objects
            if (part.Position-position).Magnitude < 150 then
                local relative =
                    part.CFrame:PointToObjectSpace(position)

                local half = part.Size*0.5

                if math.abs(relative.Y) < half.Y+8 then
                    local dx = math.max(
                        math.abs(relative.X)-half.X,0
                    )

                    local dz = math.max(
                        math.abs(relative.Z)-half.Z,0
                    )

                    local gap = math.sqrt(dx*dx+dz*dz)

                    if gap < 5 then
                        risk = risk+110
                    elseif gap < 15 then
                        risk = risk+(15-gap)*4
                    end
                end
            end
        end
    end

    return risk,count
end

-- QUICK DODGE
local function chooseDodge(char,root)
    local params = RaycastParams.new()
    params.FilterType =
        Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    params.RespectCanCollide = true

    local here = root.Position
    local currentRisk = dangerAt(here)

    local best,bestScore

    for _,radius in ipairs({16,27}) do
        for i = 1,12 do
            local angle = i*math.pi/6

            local offset = Vector3.new(
                math.cos(angle)*radius,
                0,
                math.sin(angle)*radius
            )

            local candidate = here+offset

            local ground = WS:Raycast(
                candidate+Vector3.new(0,9,0),
                Vector3.new(0,-27,0),
                params
            )

            if ground then
                local wall = WS:Raycast(
                    here+Vector3.new(0,2,0),
                    offset,
                    params
                )

                if not wall then
                    local goal = Vector3.new(
                        candidate.X,
                        ground.Position.Y+3,
                        candidate.Z
                    )

                    local score =
                        dangerAt(goal)*10+radius*0.1

                    if not best or score < bestScore then
                        best = goal
                        bestScore = score
                    end
                end
            end
        end
    end

    if best and bestScore < currentRisk*9 then
        return best
    end
end

-- PATH CONTROL
local function resetPath()
    pathSerial = pathSerial+1
    pathPoints = {}
    pathIndex = 1
    pathGoal = nil
    pathAt = 0
    planning = false
end

local function moveTo(hum,goal,force)
    local now = os.clock()

    if force
        or not lastMoveGoal
        or (goal-lastMoveGoal).Magnitude > 4
        or now-lastMoveAt >= cfg.moveInterval then

        hum:MoveTo(goal)
        lastMoveGoal = goal
        lastMoveAt = now
    end
end

local function navigate(hum,root,goal)
    if not running or not goal then return end

    local now = os.clock()

    local needsNewPath =
        not pathGoal
        or (goal-pathGoal).Magnitude > 14
        or now-pathAt > cfg.pathRefresh

    if needsNewPath and not planning then
        planning = true
        pathAt = now
        pathGoal = goal

        pathSerial = pathSerial+1
        local serial = pathSerial
        local runEpoch = epoch
        local start = root.Position

        task.spawn(function()
            local ok,points = pcall(function()
                local path = PFS:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                    WaypointSpacing = 6
                })

                path:ComputeAsync(start,goal)

                if path.Status ==
                    Enum.PathStatus.Success then
                    return path:GetWaypoints()
                end

                return {}
            end)

            if serial ~= pathSerial
                or epoch ~= runEpoch
                or not running or not active then
                return
            end

            pathPoints = ok and points or {}
            pathIndex =
                #pathPoints >= 2 and 2 or 1
            planning = false

            if not ok then
                log("PATHFIND ERROR")
            end
        end)
    end

    local destination = goal
    local waypoint = pathPoints[pathIndex]

    while waypoint and
        (root.Position-waypoint.Position).Magnitude < 6 do

        pathIndex = pathIndex+1
        waypoint = pathPoints[pathIndex]
    end

    if waypoint then
        destination = waypoint.Position

        if waypoint.Action ==
            Enum.PathWaypointAction.Jump then

            hum.Jump = true
        end
    end

    -- Move immediately, even while path calculates.
    moveTo(hum,destination,false)
end

local function nextGate(root)
    local nearest,nearestD

    for part in pairs(gates) do
        if part.Parent
            and not visitedGates[part]
            and not part.CanCollide then

            local d = (
                part.Position-root.Position
            ).Magnitude

            if d > 6 and d < 160
                and (not nearestD or d < nearestD) then

                nearest = part
                nearestD = d
            end
        end
    end

    return nearest,nearestD
end

-- HUD MECHANICS
local function hudState()
    local lookAway = false
    local victory = false

    for _,obj in ipairs(pg:GetDescendants()) do
        if obj:IsA("TextLabel")
            and obj.Visible
            and not obj:IsDescendantOf(gui) then

            local text = string.upper(obj.Text)

            if text:find("LOOK AWAY",1,true) then
                lookAway = true
            end

            if text:find("DUNGEON COMPLETED",1,true)
                or text:find("VICTORY",1,true) then

                victory = true
            end
        end
    end

    return lookAway,victory
end

-- STRICT EIF -> E
local function autoCast(target,distance)
    if not running or not cfg.skills or casting then
        return
    end

    if not target or distance > cfg.attackRange then
        return
    end

    if os.clock()-lastQ < cfg.cooldown then
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

-- STOP
local function stopFarm()
    running = false
    epoch = epoch+1
    casting = false
    respawning = false
    dodgeUntil = 0
    dodgeGoal = nil

    resetPath()

    startBtn.Text = "START AUTOFARM"
    floatStop.Visible = false

    local char,hum,root = character()

    if hum and root then
        hum:MoveTo(root.Position)
        restoreSpeed(hum)
    end

    setState("STOPPED")
    log("FARM STOPPED")
end

on(stopBtn.Activated,stopFarm)
on(floatStop.Activated,stopFarm)

-- START
on(startBtn.Activated,function()
    if running then
        stopFarm()
        return
    end

    local char,hum,root = character()
    if not root then
        log("CHARACTER NOT READY")
        return
    end

    local dungeon = WS:FindFirstChild("dungeonName")

    if dungeon and dungeon:IsA("StringValue")
        and dungeon.Value ~= "Gilded Skies" then

        log("WRONG DUNGEON: "..dungeon.Value)
        return
    end

    running = true
    epoch = epoch+1
    casting = false
    respawning = false
    seenEnemies = false
    lastEnemyAt = os.clock()
    lastQ = -math.huge

    resetPath()

    startBtn.Text = "FARM RUNNING"
    floatStop.Visible = not frame.Visible

    task.spawn(scanWorld)

    applySpeed(hum)
    setState("SEARCHING ENEMIES")
    log("FARM STARTED")
end)

-- CHARACTER RESPAWN HANDLING
on(player.CharacterAdded,function()
    if running then
        epoch = epoch+1
        casting = false
        respawning = true
        resetPath()
        setState("RESPAWNING")
    end
end)

-- CLEANUP
local function cleanup()
    if not active then return end

    active = false
    running = false
    epoch = epoch+1

    local char,hum = character()
    restoreSpeed(hum)

    for _,conn in ipairs(connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end

    if gui.Parent then
        gui:Destroy()
    end
end

_G.GS9Cleanup = cleanup

on(removeBtn.Activated,cleanup)

gui.Destroying:Connect(function()
    cleanup()
end)

-- LIVE CONTROL LOOP
task.spawn(function()
    local lastHud = 0
    local lastUI = 0
    local lastTagCheck = 0
    local lastStuckCheck = 0
    local previousPosition

    local lookAway = false
    local victory = false
    local failures = 0

    while active and gui.Parent do
        task.wait(0.12)

        local ok,err = pcall(function()
            local now = os.clock()

            -- Lightweight enemy-tag refresh.
            if now-lastTagCheck > 2 then
                lastTagCheck = now

                for _,obj in ipairs(
                    CS:GetTagged("Enemy")
                ) do
                    if obj:IsA("Model") then
                        registerEnemy(obj)
                    else
                        registerEnemy(
                            obj:FindFirstAncestorOfClass(
                                "Model"
                            )
                        )
                    end
                end
            end

            local char,hum,root = character()

            -- AUTO RESPAWN: DO NOT STOP FARM
            if running and not root then
                if not cfg.autoResume then
                    stopFarm()
                else
                    if not respawning then
                        respawning = true
                        epoch = epoch+1
                        casting = false
                        resetPath()
                        log("DEAD - WAITING FOR RESPAWN")
                    end

                    setState("RESPAWNING")
                end

                return
            end

            if running and respawning and root then
                respawning = false
                casting = false
                lastQ = -math.huge
                lastEnemyAt = now

                resetPath()
                task.spawn(scanWorld)

                log("RESPAWNED - AUTO RESUME")
                setState("RESUMING FARM")
            end

            if not root then return end

            -- Maintain faster movement if enabled.
            if running and now-lastSpeedCheck > 0.5 then
                lastSpeedCheck = now
                applySpeed(hum)
            end

            local target,distance,count =
                selectTarget(root)

            if count > 0 then
                seenEnemies = true
                lastEnemyAt = now
            end

            local risk,hazardCount =
                dangerAt(root.Position)

            if now-lastHud > 0.8 then
                lastHud = now
                lookAway,victory = hudState()
            end

            if running then
                if victory then
                    stopFarm()
                    setState("DUNGEON COMPLETED")
                    log("DUNGEON COMPLETED")

                elseif lookAway then
                    setState("LOOK AWAY - MANUAL")

                    -- Automated turning is not yet verified.
                    moveTo(hum,root.Position,true)

                elseif cfg.dodge and risk >= 25 then
                    -- Dodge overrides normal navigation.
                    setState("DODGING")

                    if not dodgeGoal
                        or now >= dodgeUntil then

                        dodgeGoal = chooseDodge(
                            char,root
                        )

                        dodgeUntil =
                            now+cfg.dodgeHold
                    end

                    if dodgeGoal then
                        moveTo(hum,dodgeGoal,true)
                    end

                elseif now < dodgeUntil
                    and dodgeGoal and cfg.dodge then

                    -- Avoid immediately cancelling dodge.
                    setState("DODGE COMMIT")
                    moveTo(hum,dodgeGoal,true)

                else
                    if dodgeGoal then
                        dodgeGoal = nil
                        dodgeUntil = 0
                        resetPath()
                    end

                    if target then
                        if cfg.movement then
                            if distance >
                                cfg.standoff+2 then

                                local delta =
                                    target.root.Position
                                    - root.Position

                                local flat = Vector3.new(
                                    delta.X,0,delta.Z
                                )

                                if flat.Magnitude > 1 then
                                    local goal =
                                        target.root.Position
                                        - flat.Unit*cfg.standoff

                                    navigate(hum,root,goal)
                                    setState("FAST NAVIGATION")
                                end
                            else
                                moveTo(
                                    hum,root.Position,false
                                )
                                setState("COMBAT RANGE")
                            end
                        end

                        if risk < 25 then
                            autoCast(target,distance)
                        end

                    else
                        setState("WAITING NEXT WAVE")

                        if cfg.gates and cfg.movement
                            and seenEnemies
                            and now-lastEnemyAt > 2.5 then

                            local gate,gateD =
                                nextGate(root)

                            if gate then
                                if gateD < 9 then
                                    visitedGates[gate] = true
                                else
                                    setState("NEXT ROOM")
                                    navigate(
                                        hum,root,
                                        gate.Position
                                    )
                                end
                            end
                        end
                    end

                    -- Stuck detection.
                    if now-lastStuckCheck > 3 then
                        lastStuckCheck = now

                        if previousPosition and target
                            and cfg.movement
                            and distance >
                                cfg.standoff+12
                            and (
                                root.Position
                                - previousPosition
                            ).Magnitude < 2 then

                            resetPath()
                            log("STUCK - REPLANNING")
                        end

                        previousPosition = root.Position
                    end
                end
            end

            if now-lastUI > 0.6 then
                lastUI = now

                enemyText.Text =
                    "ENEMIES ALIVE: "..count

                targetText.Text =
                    "TARGET: "..
                    (target and target.model.Name
                    or "None")

                hazardText.Text =
                    "HAZARDS: "..hazardCount

                speedInfo.Text =
                    "ACTUAL SPEED: "..
                    string.format(
                        "%.1f",hum.WalkSpeed
                    )..
                    " | SET: "..cfg.speed

                footer.Text =
                    "STATE: "..state..
                    " | KILLS: "..kills
            end
        end)

        if ok then
            failures = 0
        else
            failures = failures+1

            log("ERROR: "..tostring(err):sub(1,70))

            if failures >= 3 then
                if running then
                    stopFarm()
                end

                log("AUTO STOP: REPEATED ERROR")
                failures = 0
            end
        end
    end
end)

task.defer(scanWorld)

log("CONTROLLER READY")
print("[GS91] COMPLETE")

end)

if not bootOK then
    warn(
        "[GS91] STARTUP ERROR: "..
        tostring(bootError)
    )
end
