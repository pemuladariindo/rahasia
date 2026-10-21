--[[
  GILDED HUB V10.0 - HARVARD-INSPIRED DODGE PLANNER
  Dungeon Quest Reborn / Gilded Skies / Delta Android

  Original rewrite from observed techniques in a deobfuscated reference:
  - classify attack models by precast / hitbox / shape
  - track attack activation windows, not just proximity
  - score future positions and paths using estimated travel speed
  - allow ONE movement controller to steer chase and dodge
  - special first-boss look-away GUI detection

  No network requests, webhook, external loader or leaked code execution.
  Experimental; timings are estimates, not verified actual hit frames.
]]

print('[GS10] BOOT')

local bootOK, bootError = pcall(function()
local Players = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local CollectionService = game:GetService('CollectionService')
local PathfindingService = game:GetService('PathfindingService')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local VirtualInputManager = game:GetService('VirtualInputManager')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local player = Players.LocalPlayer
assert(player, 'LocalPlayer missing')
local playerGui = player:WaitForChild('PlayerGui', 10)
assert(playerGui, 'PlayerGui missing')

if type(_G.GS9Cleanup) == 'function' then
    pcall(_G.GS9Cleanup)
end
pcall(function() RunService:UnbindFromRenderStep('GS10_MOTOR') end)
for _, name in ipairs({'GildedHubV96', 'GildedHubV10'}) do
    local existing = playerGui:FindFirstChild(name)
    if existing then existing:Destroy() end
end

local active, running = true, false
local epoch = 0
local connections = {}
local enemies, hazards, gateParts = {}, {}, {}
local logs, announced = {}, {}
local scanBusy = false
local cfg = {
    autoSkill = true, autoMove = true, dodge = true,
    faceEnemy = true, lookMechanic = true,
    autoRespawn = true, nextRoom = false,
    qCooldown = 6, qToE = 0.28, eRepeat = 0.55,
    buffWindow = 4.0, castRange = 54, standoff = 30,
    planningHorizon = 1.5, planningDt = 0.15,
    warningScore = 13
}
local motorMode = 'MOVE'  -- optional fallback to MOVETO
local moveDirection = Vector3.zero
local moveGoal = nil
local mode = 'READY'
local target, targetDistance = nil, math.huge
local healthLoss, lastHealth = 0, nil
local discoveredAttacks, liveThreats = 0, {}
local riskNow, riskSoon = 0, 0
local threatName = 'NONE'
local dodgePlan, dodgeCommitUntil = nil, 0
local dodgeAt, dodgeCount = 0, 0
local path = {token = 0, points = {}, index = 1, goal = nil, mode = nil, pending = false, requestedAt = 0}
local lastQ, buffUntil, nextE = -math.huge, 0, math.huge
local qCount, eCount, keyBusy = 0, 0, false
local respawning, sawEnemy, lastEnemyAt = false, false, 0
local gaze = {active = false, toward = false, source = nil, untilAt = 0}
local rotatingRoot, facingAlign, facingAttachment, originalAutoRotate
local controls, controlsLocked
local manualTest = {untilAt = 0, beginPos = nil, direction = Vector3.zero, issued = false}
local lastStuckAt, lastStuckPosition = 0, nil

local function connect(signal, handler)
    local c = signal:Connect(handler)
    connections[#connections+1] = c
    return c
end
local function character()
    local c = player.Character
    if not c then return end
    local h = c:FindFirstChildOfClass('Humanoid')
    local r = c:FindFirstChild('HumanoidRootPart')
    if h and r and h.Health > 0 then return c,h,r end
end
local function lower(s) return string.lower(tostring(s or '')) end
local function has(s, frag) return string.find(lower(s), frag, 1, true) ~= nil end
local function flat(v)
    local v2 = Vector3.new(v.X,0,v.Z)
    return v2.Magnitude > 0.001 and v2.Unit or Vector3.zero
end
local function now() return os.clock() end
