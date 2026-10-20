
--[[
 DQR GILDED HUB V9.5
 DODGE PRIORITY + PATHFIND FIX

 Delta Android | Gilded Skies

 - Dodge overrides chasing
 - Direct escape + pathfinding fallback
 - Boss 1 lateral strafe
 - Boss 1 hazard recognition
 - Predictive hitbox risk
 - Natural WalkSpeed
 - EIF -> E
 - Face enemy
 - Look away from Kiryne
 - Auto respawn

 No webhook, HTTP calls, or external code.
 Experimental: verify behavior in-game.
]]

print("[GS95] BOOT")

local bootOK, bootError = pcall(function()

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local PFS = game:GetService("PathfindingService")
local RS = game:GetService("RunService")
local WS = game:GetService("Workspace")
local VIM = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
assert(player,"LocalPlayer unavailable")

local pg = player:WaitForChild("PlayerGui",10)
assert(pg,"PlayerGui unavailable")

if type(_G.GS9Cleanup) == "function" then
    pcall(_G.GS9Cleanup)
end

for _,name in ipairs({
    "GildedHubV9",
    "GildedHubV91",
    "GildedHubV92",
    "GildedHubV93",
    "GildedHubV94",
    "GildedHubV95"
}) do
    local old = pg:FindFirstChild(name)
    if old then old:Destroy() end
end

local cfg = {
    skills = true,
    movement = true,
    dodge = true,
    facing = true,
    lookAway = true,
    respawn = true,
    bossStrafe = true,
    gates = false,

    qCooldown = 6,
    buffWindow = 4.5,
    qToE = 0.55,
    eRepeat = 0.65,

    attackRange = 54,
    standoff = 28,

    dangerThreshold = 25,
    dodgeReplan = 0.40,
    dodgeCommit = 0.45
}

local active = true
local running = false
local epoch = 0
local state = "READY"

local enemies = {}
local hazards = {}
local gates = {}
local visitedGates = {}
local connections = {}
local logHistory = {}

local scanning = false
local waitingRespawn = false
local sawEnemies = false
local lastEnemyAt = 0

local kills = 0
local qCount = 0
local eCount = 0

local lastQ = -math.huge
local buffUntil = 0
local nextE = math.huge
local inputBusy = false

local currentTarget
local faceTarget

local gazeUntil = 0
local gazeVisible = false

local alignment
local attachment
local alignedRoot
local savedAutoRotate = true

local chase = {
    points = {},
    index = 1,
    goal = nil,
    at = 0,
    token = 0,
    planning = false
}

local dodge = {
    active = false,
    goal = nil,
    direct = false,
    mode = "IDLE",
    lastPlan = 0,
    holdUntil = 0,
    token = 0,
    points = {},
    index = 1,
    pathPlanning = false,
    lastPosition = nil
}

local lastMove = nil
local lastMoveAt = 0
local dodgeCount = 0

local lastRisk = 0
local lastHazardName = "NONE"

local function on(signal,fn)
    local c = signal:Connect(fn)
    table.insert(connections,c)
    return c
end

local function character()
    local char = player.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    if hum and root and hum.Health > 0 then
        return char,hum,root
    end
end

local function matchName(text,patterns)
    text = string.lower(tostring(text))

    for _,pattern in ipairs(patterns) do
        if string.find(text,pattern,1,true) then
            return pattern
        end
    end

    return nil
end

-- UI
local BG = Color3.fromRGB(18,22,32)
local PANEL = Color3.fromRGB(35,40,56)
local PINK = Color3.fromRGB(205,54,135)
local BLUE = Color3.fromRGB(56,82,126)
local RED = Color3.fromRGB(174,48,72)
local WHITE = Color3.fromRGB(245,245,250)

local function make(class,parent,props)
    local obj = Instance.new(class)

    for key,value in pairs(props) do
        obj[key] = value
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
    Name = "GildedHubV95",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 99999
})

local frame = make("Frame",gui,{
    Size = UDim2.fromOffset(338,333),
    Position = UDim2.fromOffset(15,65),
    BackgroundColor3 = BG,
    BorderSizePixel = 0
})
corner(frame)

local function button(parent,text,x,y,w,h,color)
    local obj = make("TextButton",parent,{
        Text = text,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextColor3 = WHITE,
        BackgroundColor3 = color or PANEL,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(x,y),
        Size = UDim2.fromOffset(w,h)
    })

    corner(obj)
    return obj
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
    frame,"GILDED HUB V9.5",7,7,177,35,PINK
)
local minus = button(frame,"-",189,7,43,35)
local plus = button(frame,"+",237,7,43,35)
local hide = button(frame,"X",285,7,45,35,RED)

local tabs = {}
local pages = {}

for i,name in ipairs({
    "FARM","COMBAT","SENSORS","DEBUG"
}) do
    tabs[i] = button(
        frame,name,7,54+(i-1)*52,78,44
    )

    pages[i] = make("Frame",frame,{
        Size = UDim2.fromOffset(237,241),
        Position = UDim2.fromOffset(93,53),
        BackgroundColor3 = PANEL,
        BorderSizePixel = 0,
        Visible = i == 1
    })

    corner(pages[i])
end

for i,tab in ipairs(tabs) do
    local selected = i

    on(tab.Activated,function()
        for j,page in ipairs(pages) do
            page.Visible = j == selected
            tabs[j].BackgroundColor3 =
                j == selected and PINK or PANEL
        end
    end)
end

-- FARM
local farm = pages[1]

label(
    farm,"DODGE PRIORITY SYSTEM",
    8,5,221,20
)

local startBtn = button(
    farm,"START AUTOFARM",8,28,221,36,PINK
)

local skillsBtn = button(
    farm,"AUTO EIF + E: ON",8,68,221,29,PINK
)

local moveBtn = button(
    farm,"SMART MOVEMENT: ON",8,101,221,29,PINK
)

local dodgeBtn = button(
    farm,"PATHFIND DODGE: ON",8,134,221,29,PINK
)

local respawnBtn = button(
    farm,"AUTO RESPAWN: ON",8,167,221,29,PINK
)

local stopBtn = button(
    farm,"EMERGENCY STOP",8,204,221,30,RED
)

-- COMBAT
local combat = pages[2]

label(combat,"Q = EIF  |  E = DAMAGE",8,7,221,20)

local testQ = button(
    combat,"TEST Q",8,33,106,34,BLUE
)

local testE = button(
    combat,"TEST E",122,33,107,34,BLUE
)

label(combat,"EIF COOLDOWN",8,73,221,17)

local cdMinus = button(
    combat,"-0.5",8,94,67,30
)

local cdText = button(
    combat,"6.0s",83,94,69,30,BLUE
)

local cdPlus = button(
    combat,"+0.5",160,94,69,30
)

label(combat,"EIF DAMAGE WINDOW",8,130,221,17)

local buffMinus = button(
    combat,"-0.5",8,151,67,30
)

local buffText = button(
    combat,"4.5s",83,151,69,30,BLUE
)

local buffPlus = button(
    combat,"+0.5",160,151,69,30
)

local faceBtn = button(
    combat,"FACE ENEMY: ON",8,190,221,22,PINK
)

local lookBtn = button(
    combat,"LOOK AWAY: ON",8,216,221,22,PINK
)

-- SENSORS
local sensors = pages[3]

local enemyText = label(
    sensors,"ENEMIES: 0",8,5,221,20
)

local targetText = label(
    sensors,"TARGET: NONE",8,28,221,32
)

local hazardText = label(
    sensors,"HAZARDS: 0",8,62,221,22
)

local nearText = label(
    sensors,"NEAREST: NONE",8,88,221,32
)

local riskText = label(
    sensors,"RISK: 0",8,122,221,21
)

local dodgeText = label(
    sensors,"DODGE MODE: IDLE",8,146,221,22
)

local strafeBtn = button(
    sensors,"BOSS 1 STRAFE: ON",
    8,177,221,26,PINK
)

local gateBtn = button(
    sensors,"AUTO NEXT ROOM: OFF",
    8,208,221,26,BLUE
)

-- DEBUG
local debugPage = pages[4]

local debugText = label(
    debugPage,"Waiting for events...",
    8,7,221,187
)

debugText.TextSize = 11
debugText.TextYAlignment = Enum.TextYAlignment.Top

local scanBtn = button(
    debugPage,"RESCAN",8,200,106,33,BLUE
)

local removeBtn = button(
    debugPage,"REMOVE HUB",122,200,107,33,RED
)

local footer = label(
    frame,"READY",8,302,322,27
)

local reopen = button(
    gui,"OPEN GILDED HUB",15,70,148,40,PINK
)
reopen.Visible = false

local floatStop = button(
    gui,"STOP FARM",170,70,115,40,RED
)
floatStop.Visible = false

local function log(message)
    if not active then return end

    message = tostring(message)
    print("[GS95] "..message)

    table.insert(logHistory,1,message)

    while #logHistory > 7 do
        table.remove(logHistory)
    end

    debugText.Text =
        table.concat(logHistory,"\n\n")
end

local function setState(message)
    state = message
    footer.Text = "STATE: "..message
end

print("[GS95] GUI READY")
log("GUI READY")

-- GUI SCALE + DRAG
local scale = make("UIScale",frame,{
    Scale = 0.9
})

local scales = {0.65,0.8,0.9,1,1.15,1.3}
local scaleIndex = 3

on(minus.Activated,function()
    scaleIndex = math.max(1,scaleIndex-1)
    scale.Scale = scales[scaleIndex]
end)

on(plus.Activated,function()
    scaleIndex = math.min(#scales,scaleIndex+1)
    scale.Scale = scales[scaleIndex]
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

    local delta = input.Position-dragStart

    frame.Position = UDim2.fromOffset(
        dragOrigin.X.Offset+delta.X,
        dragOrigin.Y.Offset+delta.Y
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

local function toggle(btn,prefix,value)
    btn.Text = prefix..
        (value and "ON" or "OFF")

    btn.BackgroundColor3 =
        value and PINK or BLUE
end

on(skillsBtn.Activated,function()
    cfg.skills = not cfg.skills
    toggle(skillsBtn,"AUTO EIF + E: ",cfg.skills)
end)

on(moveBtn.Activated,function()
    cfg.movement = not cfg.movement
    toggle(moveBtn,"SMART MOVEMENT: ",cfg.movement)
end)

on(dodgeBtn.Activated,function()
    cfg.dodge = not cfg.dodge
    toggle(dodgeBtn,"PATHFIND DODGE: ",cfg.dodge)
end)

on(respawnBtn.Activated,function()
    cfg.respawn = not cfg.respawn
    toggle(respawnBtn,"AUTO RESPAWN: ",cfg.respawn)
end)

on(faceBtn.Activated,function()
    cfg.facing = not cfg.facing
    toggle(faceBtn,"FACE ENEMY: ",cfg.facing)
end)

on(lookBtn.Activated,function()
    cfg.lookAway = not cfg.lookAway
    toggle(lookBtn,"LOOK AWAY: ",cfg.lookAway)
end)

on(strafeBtn.Activated,function()
    cfg.bossStrafe = not cfg.bossStrafe
    toggle(strafeBtn,"BOSS 1 STRAFE: ",cfg.bossStrafe)
end)

on(gateBtn.Activated,function()
    cfg.gates = not cfg.gates
    toggle(gateBtn,"AUTO NEXT ROOM: ",cfg.gates)
end)

on(cdMinus.Activated,function()
    if running then return end

    cfg.qCooldown =
        math.max(4,cfg.qCooldown-0.5)

    cdText.Text =
        string.format("%.1fs",cfg.qCooldown)
end)

on(cdPlus.Activated,function()
    if running then return end

    cfg.qCooldown =
        math.min(20,cfg.qCooldown+0.5)

    cdText.Text =
        string.format("%.1fs",cfg.qCooldown)
end)

on(buffMinus.Activated,function()
    if running then return end

    cfg.buffWindow =
        math.max(1.5,cfg.buffWindow-0.5)

    buffText.Text =
        string.format("%.1fs",cfg.buffWindow)
end)

on(buffPlus.Activated,function()
    if running then return end

    cfg.buffWindow =
        math.min(10,cfg.buffWindow+0.5)

    buffText.Text =
        string.format("%.1fs",cfg.buffWindow)
end)

-- KEY INPUT
local function sendKey(key)
    if inputBusy then return false end
    inputBusy = true

    local ok,err = pcall(function()
        VIM:SendKeyEvent(true,key,false,game)
        task.wait(0.08)
        VIM:SendKeyEvent(false,key,false,game)
    end)

    inputBusy = false

    if not ok then
        log("INPUT ERROR: "..
            tostring(err):sub(1,50))
    end

    return ok
end

on(testQ.Activated,function()
    if not running then
        task.spawn(sendKey,Enum.KeyCode.Q)
    end
end)

on(testE.Activated,function()
    if not running then
        task.spawn(sendKey,Enum.KeyCode.E)
    end
end)

-- DUNGEON NAMES
local enemyNames = {
    "dracani","archpriest","kiryne",
    "cragg","vytelus","dragon lord"
}

local boss1Names = {
    "firstbosslongline",
    "firstbosspassivecriclehitbox",
    "firstbosspassivecircle",
    "firstbossbeamtrackerline",
    "firstbossorbprecastline",
    "firstbossmovingorb",
    "firstbossmoveorb",
    "archpriestmovingorb",
    "firstbossjumpslam",
    "firstbosspassivebeam",
    "firstbosslefthandshot",
    "firstbossrighthandshot",
    "firstbossseekingspikes",
    "firstbossminionexplosion",
    "firstbossrocket",
    "firstbossrockethitbox",
    "firstbossspinningrock",
    "archpriestwavecircles"
}

local otherAttacks = {
    "dracanimageattack",
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

local lookBeamNames = {
    "firstbossblindingblastbeam",
    "archpriestblindingbeam"
}

local recognizedNames = {}

local function registerEnemy(model)
    if not model or not model:IsA("Model") then
        return
    end

    if enemies[model] then return end
    if Players:GetPlayerFromCharacter(model) then
        return
    end

    if not matchName(model.Name,enemyNames)
        and not CS:HasTag(model,"Enemy") then
        return
    end

    local hum =
        model:FindFirstChildOfClass("Humanoid")

    local root =
        model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart

    if not hum or not root
        or not root:IsA("BasePart") then
        return
    end

    enemies[model] = {
        hum = hum,
        root = root,
        counted = false
    }

    on(hum.Died,function()
        local e = enemies[model]

        if e and not e.counted then
            e.counted = true
            kills = kills+1
        end
    end)

    log("ENEMY: "..model.Name)
end

-- HAZARD SENSOR
local function registerHazard(part)
    if not part:IsA("BasePart") then return end

    local combined = string.lower(part.Name)
    local node = part.Parent

    for _ = 1,5 do
        if not node or node == WS then break end

        combined =
            combined.." "..string.lower(node.Name)

        node = node.Parent
    end

    if matchName(combined,safeNames)
        or matchName(combined,lookBeamNames) then
        return
    end

    local attackName =
        matchName(combined,boss1Names)
        or matchName(combined,otherAttacks)

    local genericPrecast =
        matchName(combined,{
            "firstboss","archpriest"
        })
        and matchName(
            part.Name,{"precast","telegraph"}
        )

    if not attackName and not genericPrecast then
        return
    end

    if hazards[part] then return end

    local source = attackName or "precast"

    local kind = "box"

    if matchName(source,{
        "orb","rocket","shot","rock"
    }) then
        kind = "projectile"

    elseif matchName(source,{
        "line","beam"
    }) then
        kind = "line"

    elseif matchName(source,{
        "circle","cricle","slam"
    }) then
        kind = "circle"
    end

    hazards[part] = {
        name = source,
        kind = kind,
        born = os.clock(),
        lastPosition = part.Position,
        lastSample = os.clock(),
        velocity = Vector3.zero
    }

    if not recognizedNames[source] then
        recognizedNames[source] = true
        log("HAZARD: "..source)
    end
end

local function inspect(obj)
    if not active then return end

    if obj:IsA("Model") then
        registerEnemy(obj)

        if matchName(obj.Name,boss1Names)
            or matchName(obj.Name,otherAttacks) then

            task.defer(function()
                if not active or not obj.Parent then
                    return
                end

                for _,child in ipairs(
                    obj:GetDescendants()
                ) do
                    if child:IsA("BasePart") then
                        registerHazard(child)
                    end
                end
            end)
        end

    elseif obj:IsA("Humanoid") then
        registerEnemy(obj.Parent)

    elseif obj:IsA("BasePart") then
        registerEnemy(obj.Parent)
        registerHazard(obj)

        if matchName(obj.Name,{
            "dungeongate",
            "nextroom",
            "dungeonexit",
            "checkpoint",
            "portal"
        }) then
            gates[obj] = true
        end
    end
end

on(WS.DescendantAdded,inspect)

on(CS:GetInstanceAddedSignal("Enemy"),function(obj)
    local model =
        obj:IsA("Model")
        and obj
        or obj:FindFirstAncestorOfClass("Model")

    registerEnemy(model)
end)

local function scanWorld()
    if scanning or not active then return end

    scanning = true

    local ok,err = pcall(function()
        local objects = WS:GetDescendants()

        for i,obj in ipairs(objects) do
            if not active then break end

            inspect(obj)

            if i%350 == 0 then
                task.wait()
            end
        end
    end)

    scanning = false

    if ok then
        log("SCAN COMPLETE")
    else
        log("SCAN ERROR: "..
            tostring(err):sub(1,60))
    end
end

on(scanBtn.Activated,function()
    task.spawn(scanWorld)
end)

local function selectTarget(root)
    local best
    local nearest = math.huge
    local count = 0

    for model,e in pairs(enemies) do
        if not model.Parent then
            enemies[model] = nil

        elseif e.root.Parent
            and e.hum.Parent
            and e.hum.Health > 0 then

            count = count+1

            local distance =
                (root.Position-e.root.Position).Magnitude

            if distance < nearest then
                nearest = distance

                best = {
                    model = model,
                    root = e.root,
                    hum = e.hum
                }
            end
        end
    end

    return best,nearest,count
end

-- TRACK MOVING HITBOXES
local function updateHazardMotion()
    local now = os.clock()

    for part,data in pairs(hazards) do
        if not part.Parent then
            hazards[part] = nil

        else
            local dt = now-data.lastSample

            if dt >= 0.07 then
                local velocity =
                    (part.Position-data.lastPosition)/dt

                if velocity.Magnitude < 220 then
                    data.velocity =
                        data.velocity:Lerp(velocity,0.55)
                end

                data.lastSample = now
                data.lastPosition = part.Position
            end
        end
    end
end

-- RISK AT A LOCATION
local function riskAt(position)
    local risk = 0
    local count = 0
    local strongest = 0
    local strongestName = "NONE"

    for part,data in pairs(hazards) do
        if not part.Parent then
            hazards[part] = nil

        else
            count = count+1

            local velocity = data.velocity

            if velocity.Magnitude < 1 then
                velocity = part.AssemblyLinearVelocity
            end

            local near =
                (part.Position-position).Magnitude

            local futureNear =
                (
                    part.Position+velocity*0.65-position
                ).Magnitude

            if near < 145 or futureNear < 145 then
                local half = part.Size*0.5

                local padding =
                    data.kind == "line" and 13
                    or data.kind == "projectile" and 15
                    or 12

                local highest = 0

                for _,ahead in ipairs({
                    0,0.35,0.7
                }) do
                    local predicted =
                        position-velocity*ahead

                    local localPos =
                        part.CFrame:PointToObjectSpace(
                            predicted
                        )

                    if math.abs(localPos.Y) <
                        half.Y+10 then

                        local dx = math.max(
                            math.abs(localPos.X)-half.X,0
                        )

                        local dz = math.max(
                            math.abs(localPos.Z)-half.Z,0
                        )

                        local gap =
                            math.sqrt(dx*dx+dz*dz)

                        local score = 0

                        if gap < 4 then
                            score = 140

                        elseif gap < padding+12 then
                            score =
                                15+(padding+12-gap)*5
                        end

                        highest =
                            math.max(highest,score)
                    end
                end

                if highest > 0 then
                    risk = risk+highest

                    if highest > strongest then
                        strongest = highest
                        strongestName = data.name
                    end
                end
            end
        end
    end

    return math.min(risk,500),
        count,strongestName
end

-- GEOMETRY HELPERS
local function rayParams(char)
    local params = RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {char}
    params.RespectCanCollide = true

    return params
end

local function groundPoint(char,point,rootY)
    local hit = WS:Raycast(
        point+Vector3.new(0,10,0),
        Vector3.new(0,-31,0),
        rayParams(char)
    )

    if not hit then return nil end
    if hit.Normal.Y < 0.65 then return nil end

    if math.abs(hit.Position.Y-rootY) > 7 then
        return nil
    end

    return Vector3.new(
        point.X,
        hit.Position.Y+3,
        point.Z
    )
end

local function clearLine(char,excluded,a,b)
    local params = rayParams(char)

    if excluded then
        params.FilterDescendantsInstances =
            {char,excluded}
    end

    local start =
        a+Vector3.new(0,2,0)

    local finish =
        b+Vector3.new(0,2,0)

    return WS:Raycast(
        start,finish-start,params
    ) == nil
end

-- MOVEMENT ISSUER
local function moveTo(hum,goal,urgent)
    if not goal then return end

    local now = os.clock()

    local interval =
        urgent and 0.13 or 0.75

    local distanceThreshold =
        urgent and 1.5 or 5

    if not lastMove
        or (goal-lastMove).Magnitude >
            distanceThreshold
        or now-lastMoveAt > interval then

        hum:MoveTo(goal)
        lastMove = goal
        lastMoveAt = now
    end
end

-- CANCEL CHASE PATH
local function resetChase()
    chase.token = chase.token+1
    chase.points = {}
    chase.index = 1
    chase.goal = nil
    chase.at = 0
    chase.planning = false
    lastMove = nil
end

-- ORDINARY NAVIGATION
local function navigate(char,hum,root,goal,model)
    if not running or not goal then return end

    if clearLine(
        char,model,root.Position,goal
    ) then
        if chase.goal then
            resetChase()
        end

        moveTo(hum,goal,false)
        return
    end

    local now = os.clock()

    local refresh =
        not chase.goal
        or (goal-chase.goal).Magnitude > 14
        or now-chase.at > 3

    if refresh and not chase.planning then
        chase.planning = true
        chase.goal = goal
        chase.at = now

        chase.token = chase.token+1

        local token = chase.token
        local runEpoch = epoch
        local origin = root.Position

        task.spawn(function()
            local ok,points = pcall(function()
                local path = PFS:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                    WaypointSpacing = 7
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
                or token ~= chase.token then
                return
            end

            chase.points = ok and points or {}
            chase.index =
                #chase.points >= 2 and 2 or 1

            chase.planning = false
        end)
    end

    local wp = chase.points[chase.index]

    while wp and
        (root.Position-wp.Position).Magnitude < 5 do

        chase.index = chase.index+1
        wp = chase.points[chase.index]
    end

    if wp then
        if wp.Action ==
            Enum.PathWaypointAction.Jump then

            hum.Jump = true
        end

        moveTo(hum,wp.Position,false)
    end
end

-- DODGE CONTROLLER
local function resetDodge()
    dodge.token = dodge.token+1
    dodge.active = false
    dodge.goal = nil
    dodge.direct = false
    dodge.mode = "IDLE"
    dodge.lastPlan = 0
    dodge.holdUntil = 0
    dodge.points = {}
    dodge.index = 1
    dodge.pathPlanning = false
    dodge.lastPosition = nil
end

-- CHOOSE AN ESCAPE POINT.
-- Evaluates the destination and travel corridor.
local function chooseEscape(char,root)
    local origin = root.Position
    local currentRisk =
        riskAt(origin)

    local best
    local bestScore = math.huge
    local bestDirect = false
    local bestRisk = math.huge

    for _,radius in ipairs({10,19,30}) do
        for i = 1,8 do
            local angle = i*math.pi/4

            local offset = Vector3.new(
                math.cos(angle)*radius,
                0,
                math.sin(angle)*radius
            )

            local rawPoint = origin+offset

            local point = groundPoint(
                char,rawPoint,origin.Y
            )

            if point then
                local direct = clearLine(
                    char,nil,origin,point
                )

                local destinationRisk =
                    riskAt(point)

                local halfway =
                    origin:Lerp(point,0.65)

                local routeRisk =
                    riskAt(halfway)

                -- Penalize running deeper into danger.
                local score =
                    destinationRisk*8
                    +routeRisk*1.5
                    +radius*0.5
                    +(direct and 0 or 85)

                -- Prefer real improvement.
                if destinationRisk >= currentRisk then
                    score = score+75
                end

                if score < bestScore then
                    best = point
                    bestScore = score
                    bestDirect = direct
                    bestRisk = destinationRisk
                end
            end
        end
    end

    return best,bestDirect,bestRisk
end

-- ASYNC PATHFINDING IF DIRECT DODGE IS BLOCKED
local function requestDodgePath(root,goal)
    dodge.token = dodge.token+1

    local token = dodge.token
    local runEpoch = epoch
    local origin = root.Position

    dodge.pathPlanning = true
    dodge.points = {}

    task.spawn(function()
        local ok,points = pcall(function()
            local path = PFS:CreatePath({
                AgentRadius = 2,
                AgentHeight = 5,
                AgentCanJump = true,
                WaypointSpacing = 5
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
            or token ~= dodge.token then
            return
        end

        dodge.pathPlanning = false
        dodge.points = ok and points or {}

        dodge.index =
            #dodge.points >= 2 and 2 or 1

        if #dodge.points == 0 then
            dodge.mode = "BLOCKED"
        else
            dodge.mode = "DODGE PATH"
        end
    end)
end

-- CRITICAL FIX:
-- Chase is cancelled before dodge takes over.
local function beginDodge(hum,root)
    resetChase()
    resetDodge()

    dodge.active = true
    dodge.mode = "EVALUATING"
    dodge.holdUntil =
        os.clock()+cfg.dodgeCommit

    faceTarget = nil
    lastMove = nil

    -- Cancel previously issued chase command.
    hum:MoveTo(root.Position)

    log("DODGE OVERRIDE: CHASE CANCELLED")
end

local function runDodge(char,hum,root,risk)
    local now = os.clock()

    if not dodge.active then
        beginDodge(hum,root)
    end

    if risk >= cfg.dangerThreshold then
        dodge.holdUntil =
            now+cfg.dodgeCommit
    end

    local goalReached =
        dodge.goal
        and (root.Position-dodge.goal).Magnitude < 5

    local needsNewGoal =
        not dodge.goal
        or (
            now-dodge.lastPlan > cfg.dodgeReplan
            and (
                goalReached
                or dodge.mode == "BLOCKED"
            )
        )

    if needsNewGoal then
        dodge.lastPlan = now

        local goal,direct,goalRisk =
            chooseEscape(char,root)

        if goal then
            dodge.goal = goal
            dodge.direct = direct
            dodge.lastPosition = root.Position

            dodgeCount = dodgeCount+1

            if direct then
                dodge.token = dodge.token+1
                dodge.points = {}
                dodge.mode = "DODGE DIRECT"

            else
                dodge.mode = "DODGE PATH"
                requestDodgePath(root,goal)
            end

        else
            dodge.goal = nil
            dodge.mode = "NO SAFE POINT"
        end
    end

    if dodge.goal then
        if dodge.direct then
            moveTo(hum,dodge.goal,true)

        else
            local wp =
                dodge.points[dodge.index]

            while wp and
                (root.Position-wp.Position).Magnitude < 4 do

                dodge.index = dodge.index+1
                wp = dodge.points[dodge.index]
            end

            if wp then
                if wp.Action ==
                    Enum.PathWaypointAction.Jump then

                    hum.Jump = true
                end

                moveTo(hum,wp.Position,true)

            else
                -- No valid dodge route yet.
                -- Never resume the old chase.
                hum:MoveTo(root.Position)
            end
        end

    else
        -- Failsafe: hold position instead of
        -- walking directly into the attack.
        hum:MoveTo(root.Position)
    end
end

local function finishDodge()
    resetDodge()
    resetChase()
    lastMove = nil
end

-- BOSS 1 STRAFING FALLBACK
-- Keeps moving sideways if the attack signal
-- has not yet exposed an identifiable hitbox.
local strafeDirection = 1
local lastStrafeChange = 0

local function bossStrafe(char,hum,root,bossRoot)
    local now = os.clock()

    if now-lastStrafeChange > 3 then
        lastStrafeChange = now
        strafeDirection = -strafeDirection
    end

    local away =
        root.Position-bossRoot.Position

    local flat = Vector3.new(
        away.X,0,away.Z
    )

    if flat.Magnitude < 1 then
        return
    end

    local tangent = Vector3.new(
        -flat.Z,0,flat.X
    ).Unit*strafeDirection

    local nextPoint =
        root.Position+tangent*12

    local ground = groundPoint(
        char,nextPoint,root.Position.Y
    )

    if ground and clearLine(
        char,nil,root.Position,ground
    ) then

        moveTo(hum,ground,false)
    end
end

-- LOOK AWAY DETECTION
local hudTexts = setmetatable({},{
    __mode = "k"
})

local function watchText(obj)
    if obj:IsA("TextLabel")
        or obj:IsA("TextButton")
        or obj:IsA("TextBox") then

        hudTexts[obj] = true
    end
end

for _,obj in ipairs(pg:GetDescendants()) do
    watchText(obj)
end

on(pg.DescendantAdded,watchText)

local function visible(obj)
    local node = obj

    while node and node ~= pg do
        if node:IsA("GuiObject")
            and not node.Visible then
            return false
        end

        if node:IsA("ScreenGui")
            and not node.Enabled then
            return false
        end

        node = node.Parent
    end

    return node == pg
end

task.spawn(function()
    while active and gui.Parent do
        task.wait(0.06)

        local found = false

        for obj in pairs(hudTexts) do
            if obj.Parent
                and not obj:IsDescendantOf(gui)
                and visible(obj) then

                local message =
                    string.upper(obj.Text or "")

                if message:find("LOOK%s*AWAY") then
                    found = true
                    break
                end
            end
        end

        if found then
            gazeUntil = os.clock()+0.5
        end

        if found and not gazeVisible then
            log("LOOK AWAY DETECTED")
        end

        gazeVisible = found
    end
end)

local function gazeBoss(root)
    local best
    local nearest = math.huge

    for model,e in pairs(enemies) do
        if model.Parent
            and e.root.Parent
            and e.hum.Health > 0
            and matchName(model.Name,{
                "kiryne","archpriest"
            }) then

            local distance =
                (root.Position-e.root.Position).Magnitude

            if distance < nearest then
                best = e.root
                nearest = distance
            end
        end
    end

    return best
end

-- BODY ORIENTATION
local function releaseFacing()
    if alignment then
        alignment:Destroy()
        alignment = nil
    end

    if attachment then
        attachment:Destroy()
        attachment = nil
    end

    if alignedRoot and alignedRoot.Parent then
        local hum =
            alignedRoot.Parent:
            FindFirstChildOfClass("Humanoid")

        if hum then
            hum.AutoRotate = savedAutoRotate
        end
    end

    alignedRoot = nil
end

local function faceDirection(hum,root,direction)
    local flat = Vector3.new(
        direction.X,0,direction.Z
    )

    if flat.Magnitude < 0.05 then
        return
    end

    if alignedRoot ~= root or not alignment then
        releaseFacing()

        alignedRoot = root
        savedAutoRotate = hum.AutoRotate

        attachment = Instance.new("Attachment")
        attachment.Parent = root

        alignment = Instance.new("AlignOrientation")
        alignment.Mode =
            Enum.OrientationAlignmentMode.OneAttachment

        alignment.Attachment0 = attachment
        alignment.Responsiveness = 90
        alignment.MaxTorque = 250000
        alignment.MaxAngularVelocity = 100
        alignment.RigidityEnabled = false
        alignment.Enabled = true
        alignment.Parent = root
    end

    hum.AutoRotate = false
    alignment.Enabled = true

    alignment.CFrame = CFrame.lookAt(
        Vector3.zero,flat.Unit
    )
end

local function naturalFacing(hum)
    if alignment then
        alignment.Enabled = false
    end

    if hum then
        hum.AutoRotate = savedAutoRotate
    end
end

on(RS.Heartbeat,function()
    if not active or not running then return end

    local char,hum,root = character()
    if not root then return end

    if cfg.lookAway
        and os.clock() < gazeUntil then

        local boss = gazeBoss(root)

        if not boss and currentTarget then
            boss = currentTarget.root
        end

        if boss and boss.Parent then
            faceDirection(
                hum,root,
                root.Position-boss.Position
            )
        end

        return
    end

    -- During dodge, allow natural movement.
    if dodge.active then
        naturalFacing(hum)
        return
    end

    if cfg.facing
        and faceTarget
        and faceTarget.Parent then

        faceDirection(
            hum,root,
            faceTarget.Position-root.Position
        )
    else
        naturalFacing(hum)
    end
end)

-- EIF -> E
local function castRotation(target,distance,risk)
    if not running or not cfg.skills then
        return
    end

    if dodge.active then return end

    if not target
        or distance > cfg.attackRange then
        return
    end

    if risk >= cfg.dangerThreshold then
        return
    end

    if cfg.lookAway
        and os.clock() < gazeUntil then
        return
    end

    local char,hum,root = character()
    if not root then return end

    if cfg.facing then
        local dir =
            target.root.Position-root.Position

        local flat = Vector3.new(
            dir.X,0,dir.Z
        )

        local look = root.CFrame.LookVector
        local facing = Vector3.new(
            look.X,0,look.Z
        )

        if flat.Magnitude > 1
            and facing.Magnitude > 0.1
            and facing.Unit:Dot(flat.Unit) < 0.7 then

            return
        end
    end

    local now = os.clock()

    if now-lastQ >= cfg.qCooldown
        and now >= buffUntil
        and not inputBusy then

        lastQ = now
        buffUntil = now+cfg.buffWindow
        nextE = now+cfg.qToE
        qCount = qCount+1

        setState("CAST EIF")

        local runEpoch = epoch

        task.spawn(function()
            local ok = sendKey(Enum.KeyCode.Q)

            if not ok and runEpoch == epoch then
                lastQ = -math.huge
                buffUntil = 0
                nextE = math.huge
            end
        end)

        return
    end

    if now >= nextE
        and now < buffUntil-0.1
        and not inputBusy then

        nextE = now+cfg.eRepeat
        eCount = eCount+1

        setState("CAST DAMAGE E")

        task.spawn(
            sendKey,Enum.KeyCode.E
        )
    end
end

local function nextGate(root)
    local best
    local nearest = math.huge

    for part in pairs(gates) do
        if part.Parent
            and not visitedGates[part]
            and not part.CanCollide then

            local d =
                (root.Position-part.Position).Magnitude

            if d < 160 and d < nearest then
                best = part
                nearest = d
            end
        end
    end

    return best,nearest
end

-- STOP
local function stopFarm()
    running = false
    epoch = epoch+1

    waitingRespawn = false
    currentTarget = nil
    faceTarget = nil

    buffUntil = 0
    nextE = math.huge
    lastQ = -math.huge

    resetChase()
    resetDodge()
    releaseFacing()

    startBtn.Text = "START AUTOFARM"
    floatStop.Visible = false

    local char,hum,root = character()
    if hum and root then
        hum:MoveTo(root.Position)
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

    waitingRespawn = false
    sawEnemies = false
    lastEnemyAt = os.clock()

    lastQ = -math.huge
    buffUntil = 0
    nextE = math.huge

    resetChase()
    resetDodge()
    task.spawn(scanWorld)

    startBtn.Text = "FARM RUNNING"
    floatStop.Visible = not frame.Visible

    setState("SEARCHING ENEMIES")
    log("FARM STARTED")
end)

on(player.CharacterAdded,function()
    if running then
        epoch = epoch+1
        waitingRespawn = true

        currentTarget = nil
        faceTarget = nil

        buffUntil = 0
        nextE = math.huge
        lastQ = -math.huge

        resetChase()
        resetDodge()
        releaseFacing()

        setState("RESPAWNING")
    end
end)

-- CLEANUP
local function cleanup()
    if not active then return end

    active = false
    running = false
    epoch = epoch+1

    releaseFacing()

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
gui.Destroying:Connect(cleanup)

-- MAIN CONTROLLER
task.spawn(function()
    local lastUI = 0
    local lastTags = 0
    local lastMotion = 0
    local lastStuck = 0

    local oldPosition
    local failures = 0

    while active and gui.Parent do
        task.wait(0.07)

        local ok,err = pcall(function()
            local now = os.clock()

            if now-lastTags > 3 then
                lastTags = now

                for _,obj in ipairs(
                    CS:GetTagged("Enemy")
                ) do
                    local model =
                        obj:IsA("Model")
                        and obj
                        or obj:
                        FindFirstAncestorOfClass("Model")

                    registerEnemy(model)
                end
            end

            if now-lastMotion > 0.09 then
                lastMotion = now
                updateHazardMotion()
            end

            local char,hum,root = character()

            -- Preserve farm state after death.
            if running and not root then
                if cfg.respawn then
                    if not waitingRespawn then
                        waitingRespawn = true
                        epoch = epoch+1

                        currentTarget = nil
                        faceTarget = nil

                        resetChase()
                        resetDodge()
                        releaseFacing()

                        log("WAITING FOR RESPAWN")
                    end

                    setState("RESPAWNING")
                else
                    stopFarm()
                end

                return
            end

            if not root then return end

            if running and waitingRespawn then
                waitingRespawn = false

                lastQ = -math.huge
                buffUntil = 0
                nextE = math.huge

                resetChase()
                resetDodge()

                task.spawn(scanWorld)
                log("AUTO RESUMED")
            end

            local target,distance,count =
                selectTarget(root)

            currentTarget = target

            if count > 0 then
                sawEnemies = true
                lastEnemyAt = now
            end

            local risk,hazardCount,hazardName =
                riskAt(root.Position)

            lastRisk = risk
            lastHazardName = hazardName

            local gazeActive =
                cfg.lookAway
                and now < gazeUntil

            if running then
                -- LOOK AWAY HAS HIGHEST PRIORITY.
                if gazeActive then
                    faceTarget = nil
                    setState("LOOK AWAY")

                    if cfg.dodge
                        and risk >=
                            cfg.dangerThreshold then

                        runDodge(
                            char,hum,root,risk
                        )

                    else
                        if dodge.active then
                            finishDodge()
                        end

                        hum:MoveTo(root.Position)
                    end

                -- DODGE OVERRIDES CHASE.
                elseif cfg.dodge
                    and (
                        risk >= cfg.dangerThreshold
                        or (
                            dodge.active
                            and now < dodge.holdUntil
                        )
                    ) then

                    faceTarget = nil
                    setState("DODGE PRIORITY")

                    runDodge(
                        char,hum,root,risk
                    )

                else
                    if dodge.active then
                        finishDodge()
                    end

                    if target then
                        local isBoss1 =
                            matchName(
                                target.model.Name,
                                {"kiryne","archpriest"}
                            ) ~= nil

                        if cfg.facing
                            and distance <=
                                cfg.attackRange+5 then

                            faceTarget = target.root
                        else
                            faceTarget = nil
                        end

                        if cfg.movement then
                            if distance >
                                cfg.standoff+4 then

                                local delta =
                                    target.root.Position
                                    - root.Position

                                local flat = Vector3.new(
                                    delta.X,0,delta.Z
                                )

                                if flat.Magnitude > 1 then
                                    local goal =
                                        target.root.Position
                                        - flat.Unit
                                        * cfg.standoff

                                    navigate(
                                        char,hum,root,
                                        goal,target.model
                                    )

                                    setState(
                                        "NAVIGATING"
                                    )
                                end

                            elseif isBoss1
                                and cfg.bossStrafe then

                                -- Keep lateral movement
                                -- if hitboxes are not detected.
                                bossStrafe(
                                    char,hum,root,
                                    target.root
                                )

                                setState(
                                    "BOSS 1 STRAFE"
                                )

                            else
                                moveTo(
                                    hum,root.Position,false
                                )
                            end
                        end

                        castRotation(
                            target,distance,risk
                        )

                    else
                        faceTarget = nil
                        setState("WAITING NEXT WAVE")

                        if cfg.gates
                            and cfg.movement
                            and sawEnemies
                            and now-lastEnemyAt > 3 then

                            local gate,gateDistance =
                                nextGate(root)

                            if gate then
                                if gateDistance < 9 then
                                    visitedGates[gate] = true

                                else
                                    navigate(
                                        char,hum,root,
                                        gate.Position,nil
                                    )
                                end
                            end
                        end
                    end

                    -- Chase stuck recovery.
                    if now-lastStuck > 3.5 then
                        lastStuck = now

                        if oldPosition
                            and target
                            and cfg.movement
                            and distance >
                                cfg.standoff+12
                            and (
                                root.Position-oldPosition
                            ).Magnitude < 1.5 then

                            resetChase()
                            hum.Jump = true

                            log("CHASE PATH RESET")
                        end

                        oldPosition = root.Position
                    end
                end
            end

            if now-lastUI > 0.55 then
                lastUI = now

                enemyText.Text =
                    "ENEMIES: "..count

                targetText.Text =
                    "TARGET: "..
                    (target and target.model.Name
                        or "NONE")

                hazardText.Text =
                    "HAZARDS TRACKED: "..
                    hazardCount

                nearText.Text =
                    "DANGER SOURCE: "..
                    lastHazardName

                riskText.Text =
                    "RISK: "..
                    math.floor(lastRisk)..
                    " | DODGES: "..dodgeCount

                dodgeText.Text =
                    "DODGE MODE: "..dodge.mode

                footer.Text =
                    "STATE: "..state..
                    " | KILLS: "..kills
            end
        end)

        if ok then
            failures = 0

        else
            failures = failures+1

            log(
                "CONTROLLER ERROR: "..
                tostring(err):sub(1,62)
            )

            if failures >= 3 then
                if running then
                    stopFarm()
                end

                log("STOPPED AFTER ERRORS")
                failures = 0
            end
        end
    end
end)

-- INITIAL SENSOR SCAN
task.defer(scanWorld)

log("CONTROLLER READY")
print("[GS95] COMPLETE")

end)

if not bootOK then
    warn(
        "[GS95] STARTUP ERROR: "..
        tostring(bootError)
    )
end
