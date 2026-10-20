
-- DQR HUB - GITHUB LOADER TEST V1

print("[DQR] SCRIPT LOADED FROM GITHUB")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui", 10)

if not pg then
    warn("[DQR] PlayerGui not found")
    return
end

local old = pg:FindFirstChild("DQR_GITHUB_TEST")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DQR_GITHUB_TEST"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99999
gui.Parent = pg

local frame = Instance.new("TextButton")
frame.Size = UDim2.fromOffset(290, 125)
frame.Position = UDim2.new(0.5, -145, 0.4, -62)
frame.BackgroundColor3 = Color3.fromRGB(205, 45, 135)
frame.BorderSizePixel = 0
frame.TextColor3 = Color3.new(1, 1, 1)
frame.TextSize = 18
frame.TextWrapped = true
frame.Font = Enum.Font.GothamBold
frame.Text = "DQR HUB\nGITHUB LOADER SUCCESS\nTAP TO CLOSE"
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

frame.Activated:Connect(function()
    gui:Destroy()
end)

print("[DQR] GITHUB GUI READY")
