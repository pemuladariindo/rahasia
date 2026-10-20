
--[[
 GILDED HUB V9.3 - COMBAT FIX
 Dungeon Quest Reborn / Delta Android

 FEATURES:
 - Natural WalkSpeed (no forced speed)
 - EIF then repeated E attempts during buff window
 - Face enemy while casting
 - Face AWAY when LOOK AWAY warning appears
 - Adaptive navigation and experimental dodge
 - Auto-resume after death

 No HTTP requests or webhooks.
]]

print("[GS93] BOOT")

local bootOK, bootError = pcall(function()

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local PFS = game:GetService("PathfindingService")
local RS = game:GetService("RunService")
local WS = game:GetService("Workspace")
local VIM = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui", 10)
assert(pg, "PlayerGui unavailable")

if type(_G.GS9Cleanup) == "function" then
    pcall(_G.GS9Cleanup)
end

local old = pg:FindFirstChild("GildedHubV93")
if old then old:Destroy() end

local cfg = {
    skills = true,
    movement = true,
    dodge = true,
    facing = true,
    lookAway = true,
    respawn = true,
    gates = false,

    qCooldown = 6,
    buffWindow = 4,
    qToE = 0.45,
    eRepeat = 0.55,

    attackDistance = 38,
    standoff = 27
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
local logs = {}

local kills = 0
local scanning = false
local waitingRespawn = false
local sawEnemy = false
local lastEnemyAt = 0

local nextQ = 0
local nextE = math.huge
local buffUntil = 0
local inputBusy = false
local qCount = 0
local eCount = 0

local currentTarget = nil
local faceTarget = nil
local gazeUntil = 0
local gazeDetected = false
local gazeSource = "NONE"

local orientation
local orientationAttachment
local orientationRoot
local originalAutoRotate = true

local pathPoints = {}
local pathIndex = 1
local pathGoal
local pathAt = 0
local pathToken = 0
local planning = false

local lastMoveGoal
local lastMoveAt = 0
local dodgeGoal
local dodgeUntil = 0

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

-- UI
local BG = Color3.fromRGB(18,22,32)
local PANEL = Color3.fromRGB(35,40,56)
local PINK = Color3.fromRGB(205,54,135)
local BLUE = Color3.fromRGB(56,82,126)
local RED = Color3.fromRGB(174,48,72)
local WHITE = Color3.fromRGB(245,245,250)

local function make(class, parent, props)
    local obj = Instance.new(class)

    for k,v in pairs(props) do
        obj[k] = v
    end

    obj.Parent = parent
    return obj
end

local function round(obj)
    make("UICorner", obj, {
        CornerRadius = UDim.new(0,7)
    })
end

local gui = make("ScreenGui", pg, {
    Name = "GildedHubV93",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 99999
})

local frame = make("Frame", gui, {
    Size = UDim2.fromOffset(332,317),
    Position = UDim2.fromOffset(18,70),
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

local title = button(
    frame,"GILDED HUB V9.3",7,7,174,35,PINK
)
local minus = button(frame,"-",185,7,43,35)
local plus = button(frame,"+",233,7,43,35)
local hide = button(frame,"X",281,7,43,35,RED)

local tabs = {}
local pages = {}

for i,name in ipairs({
    "FARM","COMBAT","SENSORS","DEBUG"
}) do
    tabs[i] = button(
        frame,name,7,53+(i-1)*52,78,44
    )

    pages[i] = make("Frame",frame,{
        Size = UDim2.fromOffset(232,225),
        Position = UDim2.fromOffset(93,52),
        BackgroundColor3 = PANEL,
        BorderSizePixel = 0,
        Visible = i == 1
    })
    round(pages[i])
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
label(farm,"GILDED SKIES COMBAT FIX",8,5,216,18)

local startBtn = button(
    farm,"START AUTOFARM",8,26,216,34,PINK
)
local skillsBtn = button(
    farm,"AUTO EIF + E: ON",8,65,216,27,PINK
)
local moveBtn = button(
    farm,"SMART MOVEMENT: ON",8,97,216,27,PINK
)
local dodgeBtn = button(
    farm,"HAZARD DODGE: ON",8,129,216,27,PINK
)
local resumeBtn = button(
    farm,"AUTO RESPAWN: ON",8,161,216,27,PINK
)
local stopBtn = button(
    farm,"EMERGENCY STOP",8,193,216,27,RED
)

-- COMBAT
local combat = pages[2]
label(combat,"Q = EIF   |   E = DAMAGE",8,5,216,20)

local testQ = button(
    combat,"TEST Q",8,29,103,32,BLUE
)
local testE = button(
    combat,"TEST E",119,29,105,32,BLUE
)

label(combat,"EIF COOLDOWN",8,67,216,16)

local cdMinus = button(
    combat,"-0.5",8,87,65,29
)
local cdText = button(
    combat,"6.0s",82,87,69,29,BLUE
)
local cdPlus = button(
    combat,"+0.5",160,87,64,29
)

label(combat,"EIF DAMAGE WINDOW",8,122,216,16)

local buffMinus = button(
    combat,"-0.5",8,142,65,29
)
local buffText = button(
    combat,"4.0s",82,142,69,29,BLUE
)
local buffPlus = button(
    combat,"+0.5",160,142,64,29
)

local aimBtn = button(
    combat,"FACE ENEMY: ON",8,179,216,20,PINK
)
local lookBtn = button(
    combat,"AUTO LOOK AWAY: ON",8,202,216,20,PINK
)

-- SENSORS
local sensors = pages[3]

local enemyText = label(
    sensors,"ENEMIES: 0",8,6,216,22
)
local targetText = label(
    sensors,"TARGET: None",8,32,216,38
)
local faceText = label(
    sensors,"FACING: IDLE",8,74,216,23
)
local gazeText = label(
    sensors,"LOOK AWAY: INACTIVE",8,102,216,23
)
local abilityText = label(
    sensors,"Q: 0 | E ATTEMPTS: 0",8,130,216,23
)
local hazardText = label(
    sensors,"HAZARDS: 0",8,158,216,22
)

local gateBtn = button(
    sensors,"AUTO NEXT ROOM: OFF",
    8,189,216,31,BLUE
)

-- DEBUG
local debugPage = pages[4]

local debugText = label(
    debugPage,"Waiting...",8,7,216,170
)
debugText.TextYAlignment = Enum.TextYAlignment.Top
debugText.TextSize = 11

local scanBtn = button(
    debugPage,"RESCAN",8,183,105,36,BLUE
)
local removeBtn = button(
    debugPage,"REMOVE HUB",119,183,105,36,RED
)

local footer = label(
    frame,"READY",8,286,316,25
)

local reopen = button(
    gui,"OPEN GILDED HUB",15,72,148,40,PINK
)
reopen.Visible = false

local floatStop = button(
    gui,"STOP FARM",169,72,115,40,RED
)
floatStop.Visible = false

local function log(text)
    if not active then return end
    text = tostring(text)

    print("[GS93] "..text)
    table.insert(logs,1,text)

    while #logs > 6 do
        table.remove(logs)
    end

    debugText.Text = table.concat(logs,"\n\n")
end

local function setState(text)
    state = text
    footer.Text = "STATE: "..text
end

print("[GS93] GUI READY")
log("GUI READY")

-- MOBILE GUI CONTROLS
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

local function toggle(btn,prefix,value)
    btn.Text = prefix..(value and "ON" or "OFF")
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
    toggle(dodgeBtn,"HAZARD DODGE: ",cfg.dodge)
end)

on(resumeBtn.Activated,function()
    cfg.respawn = not cfg.respawn
    toggle(resumeBtn,"AUTO RESPAWN: ",cfg.respawn)
end)

on(aimBtn.Activated,function()
    cfg.facing = not cfg.facing
    toggle(aimBtn,"FACE ENEMY: ",cfg.facing)
end)

on(lookBtn.Activated,function()
    cfg.lookAway = not cfg.lookAway
    toggle(lookBtn,"AUTO LOOK AWAY: ",cfg.lookAway)
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

-- INPUT
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
        log("KEY ERROR: "..tostring(err):sub(1,45))
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

-- ENEMY SCANNING
local function contains(text,patterns)
    text = string.lower(tostring(text))

    for _,p in ipairs(patterns) do
        if string.find(text,p,1,true) then
            return true
        end
    end

    return false
end

local mobNames = {
    "dracani","kiryne","archpriest",
    "cragg","vytelus","dragon lord"
}

local bossNames = {
    "kiryne","archpriest","cragg",
    "vytelus","dragon lord"
}

local hazardNames = {
    "dracanimageattack",
    "archpriestwavecircles",
    "archpriestblindingbeam",
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

    log("FOUND: "..model.Name)
end

local function inspect(obj)
    if not active then return end

    if obj:IsA("Model") then
        registerEnemy(obj)
        return
    end

    if obj:IsA("Humanoid") then
        registerEnemy(obj.Parent)
        return
    end

    if not obj:IsA("BasePart") then return end

    registerEnemy(obj.Parent)

    local name = string.lower(obj.Name)
    local combined = name
    local parent = obj.Parent

    for _ = 1,3 do
        if not parent or parent == WS then break end

        combined =
            combined.." "..string.lower(parent.Name)

        parent = parent.Parent
    end

    if not contains(combined,safeNames) then
        local known = contains(name,hazardNames)

        local telegraph =
            contains(combined,bossNames)
            and contains(name,{
                "precast","hitbox","telegraph"
            })

        if (known or telegraph)
            and not hazards[obj] then

            hazards[obj] = {
                born = os.clock()
            }
        end
    end

    if contains(name,{
        "dungeongate","nextroom",
        "dungeonexit","checkpoint","portal"
    }) then
        gates[obj] = true
    end
end

on(WS.DescendantAdded,inspect)

on(CS:GetInstanceAddedSignal("Enemy"),function(obj)
    registerEnemy(
        obj:IsA("Model")
        and obj
        or obj:FindFirstAncestorOfClass("Model")
    )
end)

local function scanWorld()
    if scanning or not active then return end
    scanning = true

    local ok,err = pcall(function()
        local objects = WS:GetDescendants()

        for i,obj in ipairs(objects) do
            if not active then break end
            inspect(obj)

            if i%300 == 0 then
                task.wait()
            end
        end
    end)

    scanning = false

    if ok then
        log("SCAN COMPLETE")
    else
        log("SCAN ERROR: "..tostring(err):sub(1,45))
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

        elseif e.root.Parent and e.hum.Parent
            and e.hum.Health > 0 then

            count = count+1

            local dist =
                (root.Position-e.root.Position).Magnitude

            if dist < nearest then
                nearest = dist

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

-- Select the boss responsible for gaze attacks.
local function findGazeBoss(root)
    local best
    local distance = math.huge

    for model,e in pairs(enemies) do
        if model.Parent
            and e.hum.Health > 0
            and e.root.Parent
            and contains(model.Name,{
                "kiryne","archpriest"
            }) then

            local d =
                (root.Position-e.root.Position).Magnitude

            if d < distance then
                best = e.root
                distance = d
            end
        end
    end

    return best
end

-- FAST HUD WARNING READER
local hudTextObjects = setmetatable({},{
    __mode = "k"
})

local function watchText(obj)
    if obj:IsA("TextLabel")
        or obj:IsA("TextButton")
        or obj:IsA("TextBox") then

        hudTextObjects[obj] = true
    end
end

for _,obj in ipairs(pg:GetDescendants()) do
    watchText(obj)
end

on(pg.DescendantAdded,watchText)

local function reallyVisible(obj)
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
        task.wait(0.055)

        local found = false

        for obj in pairs(hudTextObjects) do
            if obj.Parent
                and not obj:IsDescendantOf(gui) then

                local text = string.upper(obj.Text or "")

                if text:find("LOOK%s*AWAY")
                    and reallyVisible(obj) then

                    found = true
                    gazeSource = obj.Name
                    break
                end
            end
        end

        if found then
            gazeUntil = os.clock()+0.55
        end

        if gazeDetected ~= found then
            gazeDetected = found

            if found then
                log("LOOK AWAY WARNING DETECTED")
            else
                log("LOOK AWAY TEXT CLEARED")
            end
        end
    end
end)

-- FACE CONTROLLER: ROTATION ONLY
-- No CFrame position modification.
local function releaseFacing()
    if orientation then
        orientation:Destroy()
        orientation = nil
    end

    if orientationAttachment then
        orientationAttachment:Destroy()
        orientationAttachment = nil
    end

    if orientationRoot and orientationRoot.Parent then
        local hum =
            orientationRoot.Parent:FindFirstChildOfClass(
                "Humanoid"
            )

        if hum then
            hum.AutoRotate = originalAutoRotate
        end
    end

    orientationRoot = nil
end

local function prepareFacing(hum,root)
    if orientationRoot == root and orientation then
        return
    end

    releaseFacing()

    orientationRoot = root
    originalAutoRotate = hum.AutoRotate

    orientationAttachment = Instance.new("Attachment")
    orientationAttachment.Name = "GS93AimAttachment"
    orientationAttachment.Parent = root

    orientation = Instance.new("AlignOrientation")
    orientation.Name = "GS93Facing"
    orientation.Mode =
        Enum.OrientationAlignmentMode.OneAttachment
    orientation.Attachment0 = orientationAttachment
    orientation.MaxTorque = 1000000000
    orientation.MaxAngularVelocity = 1000000
    orientation.Responsiveness = 200
    orientation.RigidityEnabled = true
    orientation.Enabled = false
    orientation.Parent = root
end

local function faceDirection(hum,root,direction)
    local flat = Vector3.new(
        direction.X,0,direction.Z
    )

    if flat.Magnitude < 0.05 then return end

    prepareFacing(hum,root)

    hum.AutoRotate = false
    orientation.Enabled = true

    orientation.CFrame = CFrame.lookAt(
        Vector3.zero,flat.Unit
    )
end

local function releaseRotation(hum)
    if orientation then
        orientation.Enabled = false
    end

    if hum then
        hum.AutoRotate = originalAutoRotate
    end
end

-- Heartbeat updates facing without changing position.
on(RS.Heartbeat,function()
    if not active or not running then return end

    local char,hum,root = character()
    if not root then return end

    local gazeActive =
        cfg.lookAway and os.clock() < gazeUntil

    if gazeActive then
        local boss = findGazeBoss(root)

        if not boss and currentTarget then
            boss = currentTarget.root
        end

        if boss and boss.Parent then
            local away = root.Position-boss.Position
            faceDirection(hum,root,away)
        else
            releaseRotation(hum)
        end

        return
    end

    if cfg.facing and faceTarget
        and faceTarget.Parent then

        faceDirection(
            hum,root,
            faceTarget.Position-root.Position
        )
    else
        releaseRotation(hum)
    end
end)

-- HAZARDS
local function dangerAt(position)
    local risk,count = 0,0
    local now = os.clock()

    for part,e in pairs(hazards) do
        if not part.Parent or now-e.born > 9 then
            hazards[part] = nil
        else
            count = count+1

            if (part.Position-position).Magnitude < 100 then
                local p =
                    part.CFrame:PointToObjectSpace(position)
                local h = part.Size*0.5

                if math.abs(p.Y) < h.Y+8 then
                    local x = math.max(math.abs(p.X)-h.X,0)
                    local z = math.max(math.abs(p.Z)-h.Z,0)
                    local gap = math.sqrt(x*x+z*z)

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

local function clearLine(char,targetModel,a,b)
    local params = RaycastParams.new()
    params.FilterType =
        Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true

    local excluded = {char}

    if targetModel then
        table.insert(excluded,targetModel)
    end

    params.FilterDescendantsInstances = excluded

    local start = a+Vector3.new(0,2,0)
    local finish = b+Vector3.new(0,2,0)

    return WS:Raycast(
        start,finish-start,params
    ) == nil
end

local function findDodge(char,root)
    local params = RaycastParams.new()
    params.FilterType =
        Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    params.RespectCanCollide = true

    local currentRisk = dangerAt(root.Position)
    local best,bestScore

    for _,radius in ipairs({14,24}) do
        for i = 1,12 do
            local a = i*math.pi/6

            local offset = Vector3.new(
                math.cos(a)*radius,0,
                math.sin(a)*radius
            )

            local candidate = root.Position+offset

            local ground = WS:Raycast(
                candidate+Vector3.new(0,8,0),
                Vector3.new(0,-26,0),
                params
            )

            if ground and clearLine(
                char,nil,root.Position,candidate
            ) then

                local goal = Vector3.new(
                    candidate.X,
                    ground.Position.Y+3,
                    candidate.Z
                )

                local cost = dangerAt(goal)*10+radius*0.2

                if not best or cost < bestScore then
                    best,bestScore = goal,cost
                end
            end
        end
    end

    if best and bestScore < currentRisk*8 then
        return best
    end
end

-- MOVEMENT
local function resetPath()
    pathToken = pathToken+1
    pathPoints = {}
    pathIndex = 1
    pathGoal = nil
    pathAt = 0
    planning = false
    lastMoveGoal = nil
end

local function moveTo(hum,goal,urgent)
    local now = os.clock()
    local delay = urgent and 0.2 or 0.8

    if not lastMoveGoal
        or (goal-lastMoveGoal).Magnitude > 5
        or now-lastMoveAt >= delay then

        hum:MoveTo(goal)
        lastMoveGoal = goal
        lastMoveAt = now
    end
end

local function navigate(char,hum,root,goal,model)
    if clearLine(char,model,root.Position,goal) then
        if pathGoal then resetPath() end
        moveTo(hum,goal,false)
        return
    end

    local now = os.clock()

    if (not pathGoal
        or (goal-pathGoal).Magnitude > 14
        or now-pathAt > 3.5)
        and not planning then

        planning = true
        pathGoal = goal
        pathAt = now
        pathToken = pathToken+1

        local token = pathToken
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
                or token ~= pathToken then
                return
            end

            pathPoints = ok and points or {}
            pathIndex =
                #pathPoints >= 2 and 2 or 1
            planning = false
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

        moveTo(hum,wp.Position,false)
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
                (part.Position-root.Position).Magnitude

            if d < 160 and d < nearest then
                best,nearest = part,d
            end
        end
    end

    return best,nearest
end

-- COMBAT: REPEAT E WHILE EIF WINDOW IS OPEN
local function attackCycle(target,distance,risk)
    if not running or not cfg.skills then return end
    if not target or distance > cfg.attackDistance then
        return
    end

    if risk >= 25 then return end
    if cfg.lookAway and os.clock() < gazeUntil then
        return
    end

    local char,hum,root = character()
    if not root then return end

    -- Wait until character is facing target.
    if cfg.facing then
        local delta = target.root.Position-root.Position
        local flat = Vector3.new(delta.X,0,delta.Z)

        if flat.Magnitude > 0.1 then
            local facing = root.CFrame.LookVector
            local flatFacing = Vector3.new(
                facing.X,0,facing.Z
            )

            if flatFacing.Magnitude > 0.1
                and flatFacing.Unit:Dot(flat.Unit) < 0.7 then
                return
            end
        end
    end

    local now = os.clock()

    if now >= nextQ and now >= buffUntil then
        if inputBusy then return end

        nextQ = now+cfg.qCooldown
        buffUntil = now+cfg.buffWindow
        nextE = now+cfg.qToE

        qCount = qCount+1
        log("EIF Q -> E WINDOW OPEN")
        setState("EIF BUFF")

        local runEpoch = epoch

        task.spawn(function()
            local ok = sendKey(Enum.KeyCode.Q)

            if not ok and epoch == runEpoch then
                nextQ = 0
                buffUntil = 0
                nextE = math.huge
            end
        end)

        return
    end

    -- E is retried repeatedly, rather than once.
    if now >= nextE
        and now < buffUntil-0.15
        and not inputBusy then

        nextE = now+cfg.eRepeat
        eCount = eCount+1

        setState("DAMAGE E")
        task.spawn(sendKey,Enum.KeyCode.E)

        if eCount <= 3 or eCount%5 == 0 then
            log("E INPUT ATTEMPT "..eCount)
        end
    end
end

local function stopFarm()
    running = false
    epoch = epoch+1
    waitingRespawn = false
    currentTarget = nil
    faceTarget = nil
    dodgeGoal = nil
    dodgeUntil = 0

    buffUntil = 0
    nextQ = 0
    nextE = math.huge

    resetPath()
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
    sawEnemy = false
    lastEnemyAt = os.clock()

    nextQ = 0
    nextE = math.huge
    buffUntil = 0

    resetPath()
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

        faceTarget = nil
        currentTarget = nil
        buffUntil = 0
        nextQ = 0
        nextE = math.huge

        resetPath()
        releaseFacing()
        setState("RESPAWNING")
    end
end)

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

-- FARM CONTROLLER
task.spawn(function()
    local lastUI = 0
    local lastTags = 0
    local lastStuck = 0
    local previousPosition
    local failures = 0

    while active and gui.Parent do
        task.wait(0.12)

        local ok,err = pcall(function()
            local now = os.clock()

            if now-lastTags > 3 then
                lastTags = now

                for _,obj in ipairs(
                    CS:GetTagged("Enemy")
                ) do
                    registerEnemy(
                        obj:IsA("Model")
                        and obj
                        or obj:FindFirstAncestorOfClass(
                            "Model"
                        )
                    )
                end
            end

            local char,hum,root = character()

            if running and not root then
                if cfg.respawn then
                    if not waitingRespawn then
                        waitingRespawn = true
                        epoch = epoch+1

                        faceTarget = nil
                        currentTarget = nil
                        resetPath()
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
                nextQ = 0
                buffUntil = 0
                nextE = math.huge

                task.spawn(scanWorld)
                log("AUTO RESUMED")
            end

            local target,distance,count =
                selectTarget(root)

            currentTarget = target

            if count > 0 then
                sawEnemy = true
                lastEnemyAt = now
            end

            local risk,hazardCount =
                dangerAt(root.Position)

            local gazeActive =
                cfg.lookAway and now < gazeUntil

            if running then
                -- Highest priority: LOOK AWAY.
                if gazeActive then
                    faceTarget = nil
                    setState("LOOK AWAY")

                    -- Stop chasing; facing controller
                    -- rotates away from Kiryne.
                    if cfg.dodge and risk >= 25 then
                        local safe = findDodge(char,root)

                        if safe then
                            moveTo(hum,safe,true)
                        end
                    else
                        moveTo(hum,root.Position,true)
                    end

                elseif cfg.dodge and risk >= 25 then
                    faceTarget = nil
                    setState("DODGING")

                    if not dodgeGoal
                        or now >= dodgeUntil then

                        dodgeGoal = findDodge(char,root)
                        dodgeUntil = now+0.5
                    end

                    if dodgeGoal then
                        moveTo(hum,dodgeGoal,true)
                    end

                elseif dodgeGoal and now < dodgeUntil then
                    faceTarget = nil
                    setState("DODGE COMMIT")
                    moveTo(hum,dodgeGoal,true)

                else
                    dodgeGoal = nil

                    if target then
                        -- Face target only when near enough
                        -- to attack. Let natural rotation
                        -- handle long-distance navigation.
                        if cfg.facing
                            and distance <=
                                cfg.attackDistance+5 then

                            faceTarget = target.root
                        else
                            faceTarget = nil
                        end

                        if cfg.movement then
                            if distance >
                                cfg.standoff+3 then

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

                                    navigate(
                                        char,hum,root,
                                        goal,target.model
                                    )

                                    setState("NAVIGATING")
                                end
                            else
                                moveTo(
                                    hum,root.Position,false
                                )
                            end
                        end

                        attackCycle(target,distance,risk)

                    else
                        faceTarget = nil
                        setState("WAITING NEXT WAVE")

                        if cfg.gates and cfg.movement
                            and sawEnemy
                            and now-lastEnemyAt > 3 then

                            local gate,d = nextGate(root)

                            if gate then
                                if d < 9 then
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

                    if now-lastStuck > 3.5 then
                        lastStuck = now

                        if previousPosition
                            and target
                            and cfg.movement
                            and distance >
                                cfg.standoff+12
                            and (
                                root.Position
                                - previousPosition
                            ).Magnitude < 1.5 then

                            resetPath()
                            hum.Jump = true
                            log("STUCK: REPLANNING")
                        end

                        previousPosition = root.Position
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
                        or "None")

                faceText.Text =
                    "FACING: "..
                    (gazeActive and "AWAY FROM BOSS"
                    or faceTarget and "ENEMY"
                    or "NATURAL")

                gazeText.Text =
                    "LOOK AWAY: "..
                    (gazeActive and "ACTIVE" or "OFF")

                abilityText.Text =
                    "Q: "..qCount..
                    " | E ATTEMPTS: "..eCount

                hazardText.Text =
                    "HAZARDS: "..hazardCount

                footer.Text =
                    "STATE: "..state..
                    " | KILLS: "..kills
            end
        end)

        if ok then
            failures = 0
        else
            failures = failures+1
            log("ERROR: "..tostring(err):sub(1,65))

            if failures >= 3 then
                if running then
                    stopFarm()
                end

                log("STOPPED: REPEATED ERRORS")
                failures = 0
            end
        end
    end
end)

task.defer(scanWorld)

log("CONTROLLER READY")
print("[GS93] COMPLETE")

end)

if not bootOK then
    warn(
        "[GS93] STARTUP ERROR: "..
        tostring(bootError)
    )
end
