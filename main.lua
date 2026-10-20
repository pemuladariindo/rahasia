
--[[
 DQR GILDED HUB V9.4
 BOSS 1 EARLY DODGE UPDATE
 Delta Android / Dungeon Quest Reborn

 Features:
 - Smart navigation, natural WalkSpeed
 - EIF Q -> repeated damage E
 - Face enemy while attacking
 - Automatic LOOK AWAY
 - Boss 1 attack recognition
 - Early predictive dodge
 - Auto resume after death
 - Dark pink mobile GUI

 No HTTP, webhook, or external dependencies.

 Experimental autofarm. Test under supervision.
]]

print("[GS94] BOOT")

local bootOK, bootError = pcall(function()

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local PFS = game:GetService("PathfindingService")
local RS = game:GetService("RunService")
local WS = game:GetService("Workspace")
local VIM = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui",10)
assert(pg,"PlayerGui not available")

-- CLEAN UP PREVIOUS HUB
if type(_G.GS9Cleanup) == "function" then
    pcall(_G.GS9Cleanup)
end

for _,name in ipairs({
    "GildedHubV9",
    "GildedHubV91",
    "GildedHubV92",
    "GildedHubV93",
    "GildedHubV94"
}) do
    local old = pg:FindFirstChild(name)
    if old then old:Destroy() end
end

local cfg = {
    skills = true,
    move = true,
    dodge = true,
    facing = true,
    lookAway = true,
    respawn = true,
    gates = false,

    qCooldown = 6,
    buffWindow = 4.5,
    qToE = 0.65,
    eRepeat = 0.65,

    spellRange = 55,
    standoff = 28,

    dodgeThreshold = 20,
    dodgeHold = 0.35
}

local active = true
local running = false
local epoch = 0
local state = "READY"

local enemies = {}
local hazards = {}
local gates = {}
local usedGates = {}
local connections = {}
local logHistory = {}

local scannedNames = {}

local scanning = false
local waitingRespawn = false
local sawEnemy = false
local lastEnemyTime = 0

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
local gazeStatus = "IDLE"

local align
local attachment
local alignedRoot
local savedAutoRotate = true

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
local lastDodgeDecision = 0
local dodgeCount = 0

local function on(signal,callback)
    local conn = signal:Connect(callback)
    table.insert(connections,conn)
    return conn
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

local function contains(value,patterns)
    value = string.lower(tostring(value))

    for _,pattern in ipairs(patterns) do
        if string.find(value,pattern,1,true) then
            return true
        end
    end

    return false
end

-- THEME
local BG = Color3.fromRGB(18,22,32)
local PANEL = Color3.fromRGB(35,40,56)
local PINK = Color3.fromRGB(205,54,135)
local BLUE = Color3.fromRGB(56,82,126)
local RED = Color3.fromRGB(174,48,72)
local WHITE = Color3.fromRGB(244,245,249)

local function make(class,parent,properties)
    local obj = Instance.new(class)

    for key,value in pairs(properties) do
        obj[key] = value
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
    Name = "GildedHubV94",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 99999
})

local frame = make("Frame",gui,{
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
    frame,"GILDED HUB V9.4",7,7,174,35,PINK
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
    local selected = i

    on(tab.Activated,function()
        for j,page in ipairs(pages) do
            page.Visible = j == selected

            tabs[j].BackgroundColor3 =
                j == selected and PINK or PANEL
        end
    end)
end

-- FARM TAB
local farm = pages[1]

label(
    farm,"GILDED SKIES | BOSS DODGE",
    8,4,216,20
)

local startBtn = button(
    farm,"START AUTOFARM",8,27,216,34,PINK
)

local skillBtn = button(
    farm,"AUTO EIF + E: ON",8,66,216,27,PINK
)

local moveBtn = button(
    farm,"SMART MOVEMENT: ON",8,98,216,27,PINK
)

local dodgeBtn = button(
    farm,"EARLY DODGE: ON",8,130,216,27,PINK
)

local respawnBtn = button(
    farm,"AUTO RESPAWN: ON",8,162,216,27,PINK
)

local stopBtn = button(
    farm,"EMERGENCY STOP",8,194,216,26,RED
)

-- COMBAT TAB
local combat = pages[2]

label(
    combat,"EIF -> DAMAGE ROTATION",8,5,216,20
)

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

label(combat,"BUFF WINDOW",8,122,216,16)

local buffMinus = button(
    combat,"-0.5",8,142,65,29
)
local buffText = button(
    combat,"4.5s",82,142,69,29,BLUE
)
local buffPlus = button(
    combat,"+0.5",160,142,64,29
)

local aimBtn = button(
    combat,"FACE ENEMY: ON",8,180,216,19,PINK
)

local lookBtn = button(
    combat,"AUTO LOOK AWAY: ON",8,202,216,19,PINK
)

-- SENSORS TAB
local sensors = pages[3]

local enemyText = label(
    sensors,"ENEMIES: 0",8,5,216,20
)

local targetText = label(
    sensors,"TARGET: None",8,29,216,37
)

local boss1Text = label(
    sensors,"BOSS 1 HAZARDS: 0",8,70,216,22
)

local dodgeText = label(
    sensors,"DODGE: IDLE",8,96,216,21
)

local gazeText = label(
    sensors,"LOOK AWAY: IDLE",8,121,216,22
)

local abilityText = label(
    sensors,"Q: 0 | E: 0",8,147,216,20
)

local gateBtn = button(
    sensors,"AUTO NEXT ROOM: OFF",
    8,184,216,35,BLUE
)

-- DEBUG TAB
local debugPage = pages[4]

local debugText = label(
    debugPage,"Waiting for events...",
    8,7,216,167
)

debugText.TextYAlignment = Enum.TextYAlignment.Top
debugText.TextSize = 11

local scanBtn = button(
    debugPage,"RESCAN",8,182,105,37,BLUE
)

local removeBtn = button(
    debugPage,"REMOVE HUB",119,182,105,37,RED
)

local footer = label(
    frame,"READY",8,286,316,27
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
    print("[GS94] "..message)

    table.insert(logHistory,1,message)

    while #logHistory > 6 do
        table.remove(logHistory)
    end

    debugText.Text =
        table.concat(logHistory,"\n\n")
end

local function setState(message)
    state = message
    footer.Text = "STATE: "..message
end

print("[GS94] GUI READY")
log("GUI READY")

-- MOBILE UI CONTROLS
local scale = make("UIScale",frame,{
    Scale = 0.9
})

local scales = {
    0.65,0.8,0.9,1,1.15,1.3
}

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
local dragStart
local dragOrigin
local touchInput

on(title.InputBegan,function(input)
    if input.UserInputType ==
        Enum.UserInputType.Touch
        or input.UserInputType ==
            Enum.UserInputType.MouseButton1 then

        dragging = true
        dragStart = input.Position
        dragOrigin = frame.Position

        touchInput =
            input.UserInputType ==
                Enum.UserInputType.Touch
            and input or nil
    end
end)

on(UIS.InputChanged,function(input)
    if not dragging then return end

    if touchInput and touchInput ~= input then
        return
    end

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
    btn.Text = prefix..
        (value and "ON" or "OFF")

    btn.BackgroundColor3 =
        value and PINK or BLUE
end

on(skillBtn.Activated,function()
    cfg.skills = not cfg.skills
    toggle(skillBtn,"AUTO EIF + E: ",cfg.skills)
end)

on(moveBtn.Activated,function()
    cfg.move = not cfg.move
    toggle(moveBtn,"SMART MOVEMENT: ",cfg.move)
end)

on(dodgeBtn.Activated,function()
    cfg.dodge = not cfg.dodge
    toggle(dodgeBtn,"EARLY DODGE: ",cfg.dodge)
end)

on(respawnBtn.Activated,function()
    cfg.respawn = not cfg.respawn
    toggle(respawnBtn,"AUTO RESPAWN: ",cfg.respawn)
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

-- VIRTUAL INPUT
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
            tostring(err):sub(1,55))
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

-- GILDED SKIES ENEMIES
local mobNames = {
    "dracani",
    "kiryne",
    "archpriest",
    "cragg",
    "vytelus",
    "dragon lord"
}

-- BOSS 1: ARCHPRIESTESS KIRYNE
-- Names from previous Gilded Skies references.
local boss1HazardNames = {
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
    "firstbossspinningrockhitbox",
    "firstbossspinningrock",
    "archpriestwavecircles"
}

local otherHazardNames = {
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

local gazeBeamNames = {
    "firstbossblindingblastbeam",
    "archpriestblindingbeam"
}

-- REGISTER ENEMY
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
        local entry = enemies[model]

        if entry and not entry.counted then
            entry.counted = true
            kills = kills+1
        end
    end)

    log("ENEMY: "..model.Name)
end

-- REGISTER ATTACK PARTS
local function inspectPart(part)
    if not part:IsA("BasePart") then
        return
    end

    registerEnemy(part.Parent)

    local name = string.lower(part.Name)
    local combined = name
    local parent = part.Parent

    -- Include names of attack models.
    for _ = 1,5 do
        if not parent or parent == WS then
            break
        end

        combined =
            combined.." "..string.lower(parent.Name)

        parent = parent.Parent
    end

    if contains(combined,safeNames) then
        return
    end

    local boss1 =
        contains(combined,boss1HazardNames)

    local general =
        contains(combined,otherHazardNames)

    local genericPrecast =
        contains(combined,{
            "firstboss",
            "archpriest"
        })
        and contains(name,{
            "precast","telegraph"
        })

    local isGazeBeam =
        contains(combined,gazeBeamNames)

    -- Gaze blast is handled by orientation logic.
    -- Don't treat it as a regular dodge hazard.
    if isGazeBeam then
        return
    end

    if (boss1 or general or genericPrecast)
        and not hazards[part] then

        local now = os.clock()

        hazards[part] = {
            born = now,
            boss1 = boss1 or genericPrecast,
            lastPosition = part.Position,
            lastSample = now,
            velocity = Vector3.zero
        }

        if boss1 or genericPrecast then
            local attackName = string.lower(
                part.Parent and part.Parent.Name
                or part.Name
            )

            if not scannedNames[attackName] then
                scannedNames[attackName] = true

                log("BOSS1: "..attackName)
            end
        end
    end

    if contains(name,{
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
    if not active then return end

    if obj:IsA("Model") then
        registerEnemy(obj)

    elseif obj:IsA("Humanoid") then
        registerEnemy(obj.Parent)

    elseif obj:IsA("BasePart") then
        inspectPart(obj)
    end
end

on(WS.DescendantAdded,function(obj)
    inspect(obj)

    -- Pre-populated attack models may arrive
    -- with their child hitboxes already created.
    if obj:IsA("Model")
        and contains(obj.Name,{
            "firstboss","archpriest"
        }) then

        task.defer(function()
            if not active or not obj.Parent then
                return
            end

            for _,part in ipairs(obj:GetDescendants()) do
                if part:IsA("BasePart") then
                    inspectPart(part)
                end
            end
        end)
    end
end)

on(CS:GetInstanceAddedSignal("Enemy"),function(obj)
    local model = obj:IsA("Model")
        and obj
        or obj:FindFirstAncestorOfClass("Model")

    registerEnemy(model)
end)

local function scanWorld()
    if scanning or not active then return end

    scanning = true
    log("WORLD SCAN START")

    local ok,err = pcall(function()
        local objects = WS:GetDescendants()

        for i,obj in ipairs(objects) do
            if not active then break end

            inspect(obj)

            if i%300 == 0 then
                task.wait()
            end
        end

        for _,obj in ipairs(
            CS:GetTagged("Enemy")
        ) do
            local model = obj:IsA("Model")
                and obj
                or obj:FindFirstAncestorOfClass(
                    "Model"
                )

            registerEnemy(model)
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

-- TARGET SELECTION
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
                (root.Position-e.root.Position)
                .Magnitude

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

local function findGazeBoss(root)
    local selected
    local nearest = math.huge

    for model,e in pairs(enemies) do
        if model.Parent
            and e.root.Parent
            and e.hum.Health > 0
            and contains(model.Name,{
                "kiryne","archpriest"
            }) then

            local distance =
                (root.Position-e.root.Position)
                .Magnitude

            if distance < nearest then
                selected = e.root
                nearest = distance
            end
        end
    end

    return selected
end

-- LOOK AWAY DETECTOR
local textObjects = setmetatable({},{
    __mode = "k"
})

local function watchText(obj)
    if obj:IsA("TextLabel")
        or obj:IsA("TextButton")
        or obj:IsA("TextBox") then

        textObjects[obj] = true
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

        for obj in pairs(textObjects) do
            if obj.Parent
                and not obj:IsDescendantOf(gui)
                and visible(obj) then

                local text =
                    string.upper(obj.Text or "")

                if text:find("LOOK%s*AWAY") then
                    found = true
                    break
                end
            end
        end

        if found then
            gazeUntil = os.clock()+0.5
        end

        if gazeVisible ~= found then
            gazeVisible = found

            if found then
                log("LOOK AWAY DETECTED")
            end
        end
    end
end)

-- ORIENTATION CONTROLLER
local function releaseFacing()
    if align then
        align:Destroy()
        align = nil
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

local function prepareFacing(hum,root)
    if alignedRoot == root and align then
        return
    end

    releaseFacing()

    alignedRoot = root
    savedAutoRotate = hum.AutoRotate

    attachment = Instance.new("Attachment")
    attachment.Name = "GS94FacingAttachment"
    attachment.Parent = root

    align = Instance.new("AlignOrientation")
    align.Name = "GS94Facing"
    align.Mode =
        Enum.OrientationAlignmentMode.OneAttachment

    align.Attachment0 = attachment
    align.MaxTorque = 250000
    align.MaxAngularVelocity = 100
    align.Responsiveness = 65
    align.RigidityEnabled = false
    align.Enabled = false
    align.Parent = root
end

local function faceDirection(hum,root,direction)
    local flat = Vector3.new(
        direction.X,0,direction.Z
    )

    if flat.Magnitude < 0.05 then
        return
    end

    prepareFacing(hum,root)

    hum.AutoRotate = false
    align.Enabled = true

    align.CFrame = CFrame.lookAt(
        Vector3.zero,
        flat.Unit
    )
end

local function naturalFacing(hum)
    if align then
        align.Enabled = false
    end

    if hum then
        hum.AutoRotate = savedAutoRotate
    end
end

on(RS.Heartbeat,function()
    if not active or not running then
        return
    end

    local char,hum,root = character()
    if not root then return end

    local gazeActive =
        cfg.lookAway
        and os.clock() < gazeUntil

    if gazeActive then
        local boss = findGazeBoss(root)

        if not boss and currentTarget then
            boss = currentTarget.root
        end

        if boss and boss.Parent then
            faceDirection(
                hum,root,
                root.Position-boss.Position
            )

            gazeStatus = "FACING AWAY"
        else
            gazeStatus = "NO BOSS TARGET"
            naturalFacing(hum)
        end

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

-- BOSS 1 PREDICTIVE HAZARD SCORING
local predictionTimes = {
    0,0.3,0.6
}

local function dangerAt(position)
    local risk = 0
    local count = 0
    local boss1Count = 0
    local now = os.clock()

    for part,data in pairs(hazards) do
        if not part.Parent
            or now-data.born > 10 then

            hazards[part] = nil

        else
            count = count+1

            if data.boss1 then
                boss1Count = boss1Count+1
            end

            local near =
                (part.Position-position).Magnitude

            if near < 140 then
                -- Estimate motion from sampled positions.
                -- Helps when the part moves via CFrame.
                local dt =
                    now-(data.lastSample or now)

                if dt >= 0.10 then
                    local previous =
                        data.lastPosition
                        or part.Position

                    local measured =
                        (part.Position-previous)/dt

                    if measured.Magnitude < 200 then
                        data.velocity =
                            (data.velocity or Vector3.zero)
                            :Lerp(measured,0.6)
                    end

                    data.lastPosition = part.Position
                    data.lastSample = now
                end

                local velocity =
                    data.velocity or Vector3.zero

                if velocity.Magnitude < 1 then
                    velocity =
                        part.AssemblyLinearVelocity
                end

                local padding =
                    data.boss1 and 25 or 17

                local highest = 0
                local half = part.Size*0.5

                for _,ahead in ipairs(predictionTimes) do
                    local predictedCF =
                        part.CFrame+velocity*ahead

                    local p =
                        predictedCF:PointToObjectSpace(
                            position
                        )

                    if math.abs(p.Y) < half.Y+9 then
                        local dx = math.max(
                            math.abs(p.X)-half.X,0
                        )

                        local dz = math.max(
                            math.abs(p.Z)-half.Z,0
                        )

                        local gap =
                            math.sqrt(dx*dx+dz*dz)

                        local score = 0

                        if gap < 5 then
                            score = 140

                        elseif gap < padding then
                            score =
                                30+(padding-gap)*4
                        end

                        highest = math.max(
                            highest,score
                        )
                    end
                end

                risk = risk+highest
            end
        end
    end

    return risk,count,boss1Count
end

-- LINE OF SIGHT
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

    local start =
        a+Vector3.new(0,2,0)

    local finish =
        b+Vector3.new(0,2,0)

    return WS:Raycast(
        start,finish-start,params
    ) == nil
end

-- FIND EARLY DODGE DESTINATION
local function findDodge(char,root)
    local params = RaycastParams.new()

    params.FilterType =
        Enum.RaycastFilterType.Exclude

    params.FilterDescendantsInstances = {char}
    params.RespectCanCollide = true

    local currentRisk =
        dangerAt(root.Position)

    local best
    local bestScore = math.huge
    local bestRisk = math.huge

    -- Try short escapes first.
    for _,radius in ipairs({10,18,27}) do
        for i = 1,8 do
            local a = 2*math.pi*i/8

            local offset = Vector3.new(
                math.cos(a)*radius,
                0,
                math.sin(a)*radius
            )

            local point =
                root.Position+offset

            local ground = WS:Raycast(
                point+Vector3.new(0,8,0),
                Vector3.new(0,-26,0),
                params
            )

            if ground
                and math.abs(
                    ground.Position.Y-root.Position.Y
                ) < 8
                and ground.Normal.Y > 0.65
                and clearLine(
                    char,nil,root.Position,point
                ) then

                local goal = Vector3.new(
                    point.X,
                    ground.Position.Y+3,
                    point.Z
                )

                local candidateRisk =
                    dangerAt(goal)

                -- Safe nearby escape.
                if candidateRisk <= 1 then
                    return goal
                end

                local score =
                    candidateRisk*12+radius*0.5

                if score < bestScore then
                    best = goal
                    bestScore = score
                    bestRisk = candidateRisk
                end
            end
        end
    end

    if best and bestRisk < currentRisk then
        return best
    end

    return nil
end

-- NATURAL SPEED NAVIGATION
-- Never changes WalkSpeed or teleports position.
local function resetPath()
    pathToken = pathToken+1
    pathPoints = {}
    pathIndex = 1
    pathGoal = nil
    pathAt = 0
    planning = false
    lastMoveGoal = nil
end

local function issueMove(hum,goal,urgent)
    if not goal then return end

    local now = os.clock()
    local interval = urgent and 0.12 or 0.7
    local threshold = urgent and 2 or 5

    if not lastMoveGoal
        or (goal-lastMoveGoal).Magnitude > threshold
        or now-lastMoveAt >= interval then

        hum:MoveTo(goal)
        lastMoveGoal = goal
        lastMoveAt = now
    end
end

local function navigate(char,hum,root,goal,model)
    if not running or not goal then
        return
    end

    if clearLine(
        char,model,root.Position,goal
    ) then

        if pathGoal then
            resetPath()
        end

        issueMove(hum,goal,false)
        return
    end

    local now = os.clock()

    local newPath =
        not pathGoal
        or (goal-pathGoal).Magnitude > 14
        or now-pathAt > 3

    if newPath and not planning then
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

    while wp
        and (root.Position-wp.Position).Magnitude < 5 do

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

local function nextGate(root)
    local selected
    local nearest = math.huge

    for part in pairs(gates) do
        if part.Parent
            and not usedGates[part]
            and not part.CanCollide then

            local d =
                (part.Position-root.Position).Magnitude

            if d < 160 and d < nearest then
                selected = part
                nearest = d
            end
        end
    end

    return selected,nearest
end

-- EIF -> E COMBAT
local function castRotation(target,distance,risk)
    if not running or not cfg.skills then
        return
    end

    if not target
        or distance > cfg.spellRange then
        return
    end

    if risk >= cfg.dodgeThreshold then
        return
    end

    if cfg.lookAway
        and os.clock() < gazeUntil then
        return
    end

    local char,hum,root = character()
    if not root then return end

    if cfg.facing then
        local delta =
            target.root.Position-root.Position

        local flat = Vector3.new(
            delta.X,0,delta.Z
        )

        local look = root.CFrame.LookVector
        local flatLook = Vector3.new(
            look.X,0,look.Z
        )

        if flat.Magnitude > 0.1
            and flatLook.Magnitude > 0.1
            and flatLook.Unit:Dot(flat.Unit) < 0.7 then

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
        log("EIF ACTIVATED - E WINDOW")

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

    -- Repeated E attempts while buff window
    -- is estimated to remain active.
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

-- STOP FARM
local function stopFarm()
    running = false
    epoch = epoch+1

    waitingRespawn = false
    currentTarget = nil
    faceTarget = nil
    dodgeGoal = nil
    dodgeUntil = 0

    buffUntil = 0
    nextE = math.huge
    lastQ = -math.huge

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

-- START FARM
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

    local dungeon = WS:FindFirstChild(
        "dungeonName"
    )

    if dungeon
        and dungeon:IsA("StringValue")
        and dungeon.Value ~= "Gilded Skies" then

        log("WRONG DUNGEON: "..dungeon.Value)
        return
    end

    running = true
    epoch = epoch+1

    waitingRespawn = false
    sawEnemy = false
    lastEnemyTime = os.clock()

    lastQ = -math.huge
    buffUntil = 0
    nextE = math.huge

    dodgeGoal = nil
    dodgeUntil = 0

    resetPath()
    task.spawn(scanWorld)

    startBtn.Text = "FARM RUNNING"
    floatStop.Visible = not frame.Visible

    setState("SEARCHING ENEMIES")
    log("FARM STARTED")
end)

-- AUTO RESPAWN
on(player.CharacterAdded,function()
    if running then
        epoch = epoch+1
        waitingRespawn = true

        currentTarget = nil
        faceTarget = nil
        dodgeGoal = nil

        buffUntil = 0
        nextE = math.huge
        lastQ = -math.huge

        resetPath()
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
    local lastTagScan = 0
    local lastStuck = 0
    local oldPosition
    local failures = 0

    while active and gui.Parent do
        task.wait(0.08)

        local ok,err = pcall(function()
            local now = os.clock()

            if now-lastTagScan > 3 then
                lastTagScan = now

                for _,obj in ipairs(
                    CS:GetTagged("Enemy")
                ) do
                    local model = obj:IsA("Model")
                        and obj
                        or obj:
                        FindFirstAncestorOfClass(
                            "Model"
                        )

                    registerEnemy(model)
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
                        dodgeGoal = nil

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

                lastQ = -math.huge
                buffUntil = 0
                nextE = math.huge

                dodgeGoal = nil
                dodgeUntil = 0

                resetPath()
                task.spawn(scanWorld)

                log("AUTO RESUMED")
            end

            local target,distance,count =
                selectTarget(root)

            currentTarget = target

            if count > 0 then
                sawEnemy = true
                lastEnemyTime = now
            end

            local risk,hazardCount,boss1Count =
                dangerAt(root.Position)

            local gazeActive =
                cfg.lookAway
                and now < gazeUntil

            if running then
                -- PRIORITY 1: LOOK AWAY
                if gazeActive then
                    faceTarget = nil
                    setState("LOOK AWAY")

                    -- Keep facing AWAY from boss.
                    -- If overlapping another hazard,
                    -- movement may still dodge.
                    if cfg.dodge
                        and risk >= cfg.dodgeThreshold then

                        if now-lastDodgeDecision > 0.2 then
                            lastDodgeDecision = now

                            dodgeGoal =
                                findDodge(char,root)

                            dodgeUntil =
                                now+cfg.dodgeHold
                        end

                        if dodgeGoal then
                            issueMove(
                                hum,dodgeGoal,true
                            )
                        end
                    else
                        issueMove(
                            hum,root.Position,true
                        )
                    end

                -- PRIORITY 2: EARLY DODGE
                elseif cfg.dodge
                    and risk >= cfg.dodgeThreshold then

                    faceTarget = nil
                    setState("EARLY DODGE")

                    if not dodgeGoal
                        or now-lastDodgeDecision > 0.28
                        or now >= dodgeUntil then

                        lastDodgeDecision = now

                        local candidate =
                            findDodge(char,root)

                        if candidate then
                            dodgeGoal = candidate
                            dodgeUntil =
                                now+cfg.dodgeHold

                            dodgeCount = dodgeCount+1
                        end
                    end

                    if dodgeGoal then
                        issueMove(
                            hum,dodgeGoal,true
                        )
                    end

                -- PRIORITY 3: FINISH DODGE
                elseif cfg.dodge
                    and dodgeGoal
                    and now < dodgeUntil then

                    faceTarget = nil
                    setState("DODGE COMMIT")

                    issueMove(
                        hum,dodgeGoal,true
                    )

                -- PRIORITY 4: NORMAL COMBAT
                else
                    if dodgeGoal then
                        dodgeGoal = nil
                        dodgeUntil = 0
                        resetPath()
                    end

                    if target then
                        if cfg.facing
                            and distance <=
                                cfg.spellRange+5 then

                            faceTarget =
                                target.root
                        else
                            faceTarget = nil
                        end

                        if cfg.move then
                            if distance >
                                cfg.standoff+3 then

                                local delta =
                                    target.root.Position
                                    - root.Position

                                local flat =
                                    Vector3.new(
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

                            else
                                issueMove(
                                    hum,
                                    root.Position,
                                    false
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
                            and cfg.move
                            and sawEnemy
                            and now-lastEnemyTime > 3 then

                            local gate,d =
                                nextGate(root)

                            if gate then
                                if d < 9 then
                                    usedGates[gate] =
                                        true
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

                        if oldPosition
                            and target
                            and cfg.move
                            and distance >
                                cfg.standoff+12
                            and (
                                root.Position-oldPosition
                            ).Magnitude < 1.5 then

                            resetPath()
                            hum.Jump = true

                            log(
                                "STUCK - REPLANNING"
                            )
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
                        or "None")

                boss1Text.Text =
                    "BOSS 1 HAZARDS: "..
                    boss1Count

                dodgeText.Text =
                    "DODGE: "..dodgeCount..
                    " | RISK: "..
                    math.floor(risk)

                gazeText.Text =
                    "LOOK AWAY: "..
                    (gazeActive and "ACTIVE"
                        or "IDLE")

                abilityText.Text =
                    "Q: "..qCount..
                    " | E: "..eCount

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
                "LOOP ERROR: "..
                tostring(err):sub(1,65)
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

-- LOAD SENSORS AFTER GUI
task.defer(scanWorld)

log("CONTROLLER READY")
print("[GS94] COMPLETE")

end)

if not bootOK then
    warn(
        "[GS94] STARTUP ERROR: "..
        tostring(bootError)
    )
end
