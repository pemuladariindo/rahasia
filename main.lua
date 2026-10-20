
--[[
 GILDED HUB V9.2 - SMOOTH NAVIGATION
 Dungeon Quest Reborn / Delta Android

 FIXES:
 - No forced WalkSpeed
 - Direct line-of-sight navigation
 - Async pathfinding behind obstacles
 - Less MoveTo command spam
 - Dodge movement priority
 - Stuck recovery
 - Auto resume after death

 Experimental: boss hazards and next-room gates
]]

print("[GS92] BOOT")

local bootOK, bootError = pcall(function()

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local PFS = game:GetService("PathfindingService")
local WS = game:GetService("Workspace")
local VIM = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui",10)
assert(pg,"PlayerGui unavailable")

-- Remove previous versions
for _,key in ipairs({"GS9Cleanup","GS92Cleanup"}) do
    if type(_G[key]) == "function" then
        pcall(_G[key])
    end
end

for _,name in ipairs({
    "GildedHubV9","GildedHubV91","GildedHubV92"
}) do
    local obj = pg:FindFirstChild(name)
    if obj then obj:Destroy() end
end

local cfg = {
    skills = true,
    nav = true,
    dodge = true,
    respawn = true,
    gates = false,
    cooldown = 6,
    castDelay = 0.25,
    spellRange = 65,
    standoff = 32,
    pathRefresh = 3.5
}

local active = true
local running = false
local epoch = 0
local casting = false
local waitingRespawn = false

local lastQ = -math.huge
local lastEnemyAt = 0
local sawEnemy = false
local kills = 0
local status = "READY"

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

local lastOrder = nil
local lastOrderAt = 0
local dodgeGoal = nil
local dodgeUntil = 0

local function on(signal,fn)
    local c = signal:Connect(fn)
    table.insert(connections,c)
    return c
end

local function charData()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if hum and root and hum.Health > 0 then
        return char,hum,root
    end
end

-- UI THEME
local BG = Color3.fromRGB(18,22,32)
local PANEL = Color3.fromRGB(35,40,56)
local PINK = Color3.fromRGB(205,54,135)
local BLUE = Color3.fromRGB(56,82,126)
local RED = Color3.fromRGB(174,48,72)
local WHITE = Color3.fromRGB(244,245,249)

local function make(class,parent,props)
    local obj = Instance.new(class)
    for k,v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

local function corner(obj)
    make("UICorner",obj,{
        CornerRadius = UDim.new(0,7)
    })
end

local gui = make("ScreenGui",pg,{
    Name = "GildedHubV92",
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
corner(frame)

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
    corner(b)
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

local title = button(
    frame,"GILDED HUB V9.2",7,7,174,35,PINK
)
local minus = button(frame,"-",185,7,43,35)
local plus = button(frame,"+",233,7,43,35)
local hide = button(frame,"X",281,7,43,35,RED)

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
    corner(pages[i])
end

for i,tab in ipairs(tabs) do
    local n = i
    on(tab.Activated,function()
        for j,page in ipairs(pages) do
            page.Visible = j == n
            tabs[j].BackgroundColor3 =
                j == n and PINK or PANEL
        end
    end)
end

-- FARM
local farm = pages[1]
label(farm,"GILDED SKIES | SMOOTH NAV",8,4,216,18)

local startBtn = button(
    farm,"START AUTOFARM",8,26,216,33,PINK
)
local skillBtn = button(
    farm,"AUTO EIF + E: ON",8,64,216,24,PINK
)
local navBtn = button(
    farm,"SMART NAVIGATION: ON",8,93,216,24,PINK
)
local dodgeBtn = button(
    farm,"HAZARD DODGE: ON",8,122,216,24,PINK
)
local respawnBtn = button(
    farm,"AUTO RESPAWN: ON",8,151,216,24,PINK
)
local stopBtn = button(
    farm,"EMERGENCY STOP",8,180,216,24,RED
)

-- COMBAT
local combat = pages[2]
label(combat,"EIF -> DAMAGE",8,7,216,21)

local testQ = button(
    combat,"TEST Q",8,35,103,36,BLUE
)
local testE = button(
    combat,"TEST E",119,35,105,36,BLUE
)

label(combat,"EIF COOLDOWN",8,82,216,22)

local cdMinus = button(
    combat,"-0.5",8,110,65,33
)
local cdText = button(
    combat,"6.0s",82,110,69,33,BLUE
)
local cdPlus = button(
    combat,"+0.5",160,110,64,33
)

label(
    combat,
    "Movement uses the game's natural speed. No WalkSpeed override.",
    8,154,216,48
)

-- SENSORS
local sensors = pages[3]

local enemyText = label(
    sensors,"ENEMIES: 0",8,6,216,25
)
local targetText = label(
    sensors,"TARGET: None",8,34,216,42
)
local speedText = label(
    sensors,"WALKSPEED: --",8,78,216,25
)
local velocityText = label(
    sensors,"ACTUAL VELOCITY: --",8,106,216,26
)
local hazardText = label(
    sensors,"HAZARDS: 0",8,135,216,25
)
local gateBtn = button(
    sensors,"AUTO NEXT ROOM: OFF",
    8,165,216,36,BLUE
)

-- DEBUG
local debug = pages[4]
local debugText = label(
    debug,"Waiting...",8,7,216,157
)
debugText.TextYAlignment = Enum.TextYAlignment.Top
debugText.TextSize = 11

local scanBtn = button(
    debug,"RESCAN WORLD",8,168,105,35,BLUE
)
local removeBtn = button(
    debug,"REMOVE HUB",119,168,105,35,RED
)

local footer = label(
    frame,"READY",8,268,316,27
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
    print("[GS92] "..message)

    table.insert(logs,1,message)
    while #logs > 6 do
        table.remove(logs)
    end

    debugText.Text = table.concat(logs,"\n\n")
end

local function setState(value)
    status = value
    footer.Text = "STATE: "..value
end

print("[GS92] GUI READY")
log("GUI READY")

-- RESIZE
local scale = make("UIScale",frame,{Scale = 0.9})
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
        log("INPUT ERROR: "..tostring(err):sub(1,50))
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

local function toggle(btn,prefix,value)
    btn.Text = prefix..(value and "ON" or "OFF")
    btn.BackgroundColor3 = value and PINK or BLUE
end

on(skillBtn.Activated,function()
    cfg.skills = not cfg.skills
    toggle(skillBtn,"AUTO EIF + E: ",cfg.skills)
end)

on(navBtn.Activated,function()
    cfg.nav = not cfg.nav
    toggle(navBtn,"SMART NAVIGATION: ",cfg.nav)
end)

on(dodgeBtn.Activated,function()
    cfg.dodge = not cfg.dodge
    toggle(dodgeBtn,"HAZARD DODGE: ",cfg.dodge)
end)

on(respawnBtn.Activated,function()
    cfg.respawn = not cfg.respawn
    toggle(respawnBtn,"AUTO RESPAWN: ",cfg.respawn)
end)

on(gateBtn.Activated,function()
    cfg.gates = not cfg.gates
    toggle(gateBtn,"AUTO NEXT ROOM: ",cfg.gates)
end)

-- GAME OBJECT NAMES
local mobNames = {
    "dracani","kiryne","cragg","vytelus"
}

local attackNames = {
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

-- ENEMY DETECTION
local function registerEnemy(model)
    if not model or not model:IsA("Model") then
        return
    end
    if enemies[model] then return end
    if Players:GetPlayerFromCharacter(model) then
        return
    end

    if not contains(model.Name,mobNames)
        and not CS:HasTag(model,"Enemy") then
        return
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart

    if not hum or not root or not root:IsA("BasePart") then
        return
    end

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

    registerEnemy(part.Parent)

    local name = string.lower(part.Name)
    local combined = name
    local parent = part.Parent

    for _ = 1,3 do
        if not parent or parent == WS then break end
        combined = combined.." "..string.lower(parent.Name)
        parent = parent.Parent
    end

    if contains(combined,safeNames) then return end

    local shapeName = contains(name,{
        "hitbox","precast","telegraph",
        "laser","beam","line","circle",
        "flame","projectile","shot","aoe"
    })

    if contains(name,attackNames)
        or (contains(combined,attackNames) and shapeName)
        or (
            contains(combined,mobNames)
            and contains(name,{
                "hitbox","precast","telegraph"
            })
        ) then

        if not hazards[part] then
            hazards[part] = {born = os.clock()}
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
        registerEnemy(obj:FindFirstAncestorOfClass("Model"))
    end
end)

local function scanWorld()
    if scanning or not active then return end
    scanning = true

    local ok,err = pcall(function()
        local objects = WS:GetDescendants()

        for i,obj in ipairs(objects) do
            if not active then break end
            inspect(obj)
            if i%300 == 0 then task.wait() end
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
    log(ok and "SCAN COMPLETE"
        or ("SCAN ERROR: "..tostring(err):sub(1,50)))
end

on(scanBtn.Activated,function()
    task.spawn(scanWorld)
end)

local function chooseTarget(root)
    local best
    local bestDistance = math.huge
    local count = 0

    for model,data in pairs(enemies) do
        if not model.Parent then
            enemies[model] = nil
        elseif data.root.Parent
            and data.hum.Parent
            and data.hum.Health > 0 then

            count = count+1

            local d =
                (data.root.Position-root.Position).Magnitude

            if d < bestDistance then
                bestDistance = d
                best = {
                    model = model,
                    root = data.root
                }
            end
        end
    end

    return best,bestDistance,count
end

-- HAZARD COST
local function dangerAt(pos)
    local risk = 0
    local count = 0
    local now = os.clock()

    for part,data in pairs(hazards) do
        if not part.Parent or now-data.born > 8 then
            hazards[part] = nil
        else
            count = count+1

            if (part.Position-pos).Magnitude < 100 then
                local localPos =
                    part.CFrame:PointToObjectSpace(pos)

                local half = part.Size*0.5

                if math.abs(localPos.Y) < half.Y+8 then
                    local dx = math.max(
                        math.abs(localPos.X)-half.X,0
                    )
                    local dz = math.max(
                        math.abs(localPos.Z)-half.Z,0
                    )
                    local gap = math.sqrt(dx*dx+dz*dz)

                    if gap < 4 then
                        risk = risk+100
                    elseif gap < 13 then
                        risk = risk+(13-gap)*4
                    end
                end
            end
        end
    end

    return risk,count
end

-- MOVEMENT CONTROLLER
-- NEVER WRITES WalkSpeed OR CFrame

local function resetPath()
    pathSerial = pathSerial+1
    pathPoints = {}
    pathIndex = 1
    pathGoal = nil
    pathTime = 0
    planning = false
    lastOrder = nil
end

local function issueMove(hum,goal,urgent)
    if not goal then return end

    local now = os.clock()
    local interval = urgent and 0.2 or 0.9

    if not lastOrder
        or (goal-lastOrder).Magnitude > (urgent and 3 or 6)
        or now-lastOrderAt > interval then

        hum:MoveTo(goal)
        lastOrder = goal
        lastOrderAt = now
    end
end

local function clearLine(char,targetModel,from,to)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true

    local excluded = {char}
    if targetModel then
        table.insert(excluded,targetModel)
    end
    params.FilterDescendantsInstances = excluded

    local start = from+Vector3.new(0,2,0)
    local finish = to+Vector3.new(0,2,0)

    return WS:Raycast(start,finish-start,params) == nil
end

local function navigate(char,hum,root,goal,targetModel)
    if not goal or not running then return end

    -- Prefer direct movement when unobstructed.
    if clearLine(
        char,targetModel,root.Position,goal
    ) then
        if pathGoal or #pathPoints > 0 then
            resetPath()
        end

        issueMove(hum,goal,false)
        return
    end

    local now = os.clock()
    local needsPlan =
        not pathGoal
        or (goal-pathGoal).Magnitude > 14
        or now-pathTime > cfg.pathRefresh

    if needsPlan and not planning then
        planning = true
        pathGoal = goal
        pathTime = now

        pathSerial = pathSerial+1
        local serial = pathSerial
        local runEpoch = epoch
        local origin = root.Position

        task.spawn(function()
            local ok,points = pcall(function()
                local path = PFS:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                    WaypointSpacing = 8
                })

                path:ComputeAsync(origin,goal)

                if path.Status ==
                    Enum.PathStatus.Success then
                    return path:GetWaypoints()
                end

                return {}
            end)

            if not active or not running
                or epoch ~= runEpoch
                or serial ~= pathSerial then
                return
            end

            pathPoints = ok and points or {}
            pathIndex =
                #pathPoints >= 2 and 2 or 1
            planning = false

            if #pathPoints == 0 then
                log("NO PATH TO TARGET")
            end
        end)
    end

    local wp = pathPoints[pathIndex]

    while wp and
        (root.Position-wp.Position).Magnitude < 5 do
        pathIndex = pathIndex+1
        wp = pathPoints[pathIndex]
    end

    if wp then
        if wp.Action ==
            Enum.PathWaypointAction.Jump then
            hum.Jump = true
        end

        issueMove(hum,wp.Position,false)
    end
end

-- DODGE: AVOID NEARBY HAZARD CANDIDATES
local function findDodge(char,root)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    params.RespectCanCollide = true

    local currentRisk = dangerAt(root.Position)
    local best,bestCost

    for _,radius in ipairs({14,24}) do
        for i = 1,12 do
            local a = 2*math.pi*i/12

            local offset = Vector3.new(
                math.cos(a)*radius,0,
                math.sin(a)*radius
            )

            local sample = root.Position+offset

            local ground = WS:Raycast(
                sample+Vector3.new(0,8,0),
                Vector3.new(0,-26,0),
                params
            )

            if ground and clearLine(
                char,nil,root.Position,sample
            ) then
                local goal = Vector3.new(
                    sample.X,
                    ground.Position.Y+3,
                    sample.Z
                )

                local score =
                    dangerAt(goal)*10+radius*0.2

                if not best or score < bestCost then
                    best = goal
                    bestCost = score
                end
            end
        end
    end

    if best and bestCost < currentRisk*8 then
        return best
    end
end

local function nextGate(root)
    local best
    local nearest = math.huge

    for part in pairs(gates) do
        if part.Parent
            and not usedGates[part]
            and not part.CanCollide then

            local d = (part.Position-root.Position).Magnitude

            if d < 160 and d < nearest then
                best = part
                nearest = d
            end
        end
    end

    return best,nearest
end

local function hudState()
    local lookAway = false
    local victory = false

    for _,obj in ipairs(pg:GetDescendants()) do
        if obj:IsA("TextLabel")
            and obj.Visible
            and not obj:IsDescendantOf(gui) then

            local value = string.upper(obj.Text)

            if value:find("LOOK AWAY",1,true) then
                lookAway = true
            end

            if value:find("DUNGEON COMPLETED",1,true)
                or value:find("VICTORY",1,true) then
                victory = true
            end
        end
    end

    return lookAway,victory
end

-- EIF -> DAMAGE
local function castRotation(target,distance)
    if not running or not cfg.skills or casting then
        return
    end

    if not target or distance > cfg.spellRange then
        return
    end

    if os.clock()-lastQ < cfg.cooldown then
        return
    end

    casting = true
    lastQ = os.clock()

    local runEpoch = epoch

    task.spawn(function()
        setState("CAST EIF")

        local ok = sendKey(Enum.KeyCode.Q)

        if ok then
            task.wait(cfg.castDelay)

            if running and epoch == runEpoch then
                setState("CAST DAMAGE")
                sendKey(Enum.KeyCode.E)
            end
        else
            lastQ = -math.huge
        end

        if epoch == runEpoch then
            casting = false
        end
    end)
end

local function stopFarm()
    running = false
    epoch = epoch+1
    casting = false
    waitingRespawn = false
    dodgeGoal = nil
    dodgeUntil = 0
    resetPath()

    startBtn.Text = "START AUTOFARM"
    floatStop.Visible = false

    local char,hum,root = charData()
    if hum and root then
        hum:MoveTo(root.Position)
    end

    setState("STOPPED")
    log("FARM STOPPED")
end

on(stopBtn.Activated,stopFarm)
on(floatStop.Activated,stopFarm)

on(startBtn.Activated,function()
    if running then
        stopFarm()
        return
    end

    local char,hum,root = charData()
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
    waitingRespawn = false
    sawEnemy = false
    lastEnemyAt = os.clock()
    lastQ = -math.huge

    resetPath()

    startBtn.Text = "FARM RUNNING"
    floatStop.Visible = not frame.Visible

    task.spawn(scanWorld)
    setState("SEARCHING ENEMIES")
    log("FARM STARTED - NATURAL SPEED")
end)

on(player.CharacterAdded,function()
    if running then
        epoch = epoch+1
        casting = false
        waitingRespawn = true
        resetPath()
        setState("RESPAWNING")
    end
end)

local function cleanup()
    if not active then return end

    active = false
    running = false
    epoch = epoch+1

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
_G.GS92Cleanup = cleanup

on(removeBtn.Activated,cleanup)
gui.Destroying:Connect(cleanup)

-- MAIN LOOP
task.spawn(function()
    local lastHud = 0
    local lastUI = 0
    local lastTags = 0
    local lastStuck = 0

    local oldPosition
    local lookAway = false
    local victory = false
    local failures = 0

    while active and gui.Parent do
        task.wait(0.15)

        local ok,err = pcall(function()
            local now = os.clock()

            if now-lastTags > 3 then
                lastTags = now

                for _,obj in ipairs(CS:GetTagged("Enemy")) do
                    if obj:IsA("Model") then
                        registerEnemy(obj)
                    else
                        registerEnemy(
                            obj:FindFirstAncestorOfClass("Model")
                        )
                    end
                end
            end

            local char,hum,root = charData()

            if running and not root then
                if not cfg.respawn then
                    stopFarm()
                else
                    if not waitingRespawn then
                        waitingRespawn = true
                        epoch = epoch+1
                        casting = false
                        resetPath()
                        log("WAITING FOR RESPAWN")
                    end
                    setState("RESPAWNING")
                end
                return
            end

            if not root then return end

            if running and waitingRespawn then
                waitingRespawn = false
                casting = false
                lastQ = -math.huge
                resetPath()
                log("AUTO RESUMED")
                task.spawn(scanWorld)
            end

            local target,distance,count =
                chooseTarget(root)

            if count > 0 then
                sawEnemy = true
                lastEnemyAt = now
            end

            local risk,hazardCount =
                dangerAt(root.Position)

            if now-lastHud > 1 then
                lastHud = now
                lookAway,victory = hudState()
            end

            if running then
                if victory then
                    stopFarm()
                    setState("DUNGEON COMPLETED")

                elseif lookAway then
                    setState("LOOK AWAY - MANUAL")
                    issueMove(hum,root.Position,true)

                elseif cfg.dodge and risk >= 25 then
                    setState("DODGING")

                    if not dodgeGoal or now >= dodgeUntil then
                        dodgeGoal = findDodge(char,root)
                        dodgeUntil = now+0.5
                    end

                    if dodgeGoal then
                        issueMove(hum,dodgeGoal,true)
                    end

                elseif cfg.dodge and dodgeGoal
                    and now < dodgeUntil then

                    setState("DODGE COMMIT")
                    issueMove(hum,dodgeGoal,true)

                else
                    if dodgeGoal then
                        dodgeGoal = nil
                        dodgeUntil = 0
                        resetPath()
                    end

                    if target then
                        if cfg.nav then
                            if distance > cfg.standoff+3 then
                                local delta =
                                    target.root.Position-root.Position

                                local flat = Vector3.new(
                                    delta.X,0,delta.Z
                                )

                                if flat.Magnitude > 1 then
                                    local goal =
                                        target.root.Position
                                        - flat.Unit*cfg.standoff

                                    navigate(
                                        char,hum,root,
                                        goal,target.model
                                    )
                                    setState("SMOOTH NAV")
                                end
                            else
                                issueMove(
                                    hum,root.Position,false
                                )
                                setState("COMBAT RANGE")
                            end
                        end

                        if risk < 25 then
                            castRotation(target,distance)
                        end

                    else
                        setState("WAITING NEXT WAVE")

                        if cfg.gates and cfg.nav
                            and sawEnemy
                            and now-lastEnemyAt > 3 then

                            local gate,d = nextGate(root)

                            if gate then
                                if d < 9 then
                                    usedGates[gate] = true
                                else
                                    navigate(
                                        char,hum,root,
                                        gate.Position,nil
                                    )
                                end
                            end
                        end
                    end

                    if now-lastStuck > 3.5 then
                        lastStuck = now

                        if oldPosition and target
                            and cfg.nav
                            and distance > cfg.standoff+12
                            and (
                                root.Position-oldPosition
                            ).Magnitude < 1.5 then

                            resetPath()
                            hum.Jump = true
                            log("STUCK - NEW PATH")
                        end

                        oldPosition = root.Position
                    end
                end
            end

            if now-lastUI > 0.7 then
                lastUI = now

                enemyText.Text =
                    "ENEMIES: "..count

                targetText.Text =
                    "TARGET: "..
                    (target and target.model.Name or "None")

                speedText.Text =
                    "WALKSPEED: "..
                    string.format("%.1f",hum.WalkSpeed)

                local v = root.AssemblyLinearVelocity
                local actual = Vector3.new(
                    v.X,0,v.Z
                ).Magnitude

                velocityText.Text =
                    "ACTUAL VELOCITY: "..
                    string.format("%.1f",actual)

                hazardText.Text =
                    "HAZARDS: "..hazardCount

                footer.Text =
                    "STATE: "..status..
                    " | KILLS: "..kills
            end
        end)

        if ok then
            failures = 0
        else
            failures = failures+1
            log("ERROR: "..tostring(err):sub(1,65))

            if failures >= 3 then
                if running then stopFarm() end
                log("AUTO STOP: REPEATED ERRORS")
                failures = 0
            end
        end
    end
end)

task.defer(scanWorld)

log("CONTROLLER READY")
print("[GS92] COMPLETE")

end)

if not bootOK then
    warn("[GS92] STARTUP ERROR: "..
        tostring(bootError))
end
