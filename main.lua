-- DQR FIX LOADER: paste THIS entire code into Delta.
-- It creates a pink status window BEFORE attempting to load GitHub.
local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui",10)
if not pg then warn("[DQR] PlayerGui missing") return end
for _,name in ipairs({"DQR_TEST","DQRLoaderCheckV2","DQRBootFix"}) do
    local old=pg:FindFirstChild(name)
    if old then old:Destroy() end
end
local gui=Instance.new("ScreenGui")
gui.Name="DQRBootFix"
gui.ResetOnSpawn=false
gui.DisplayOrder=1000000
gui.IgnoreGuiInset=true
gui.Parent=pg
local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(345,276)
frame.Position=UDim2.new(0.5,-172,0.07,0)
frame.BackgroundColor3=Color3.fromRGB(35,25,42)
frame.BorderSizePixel=0
frame.Parent=gui
local label=Instance.new("TextLabel")
label.Size=UDim2.new(1,-20,1,-62)
label.Position=UDim2.fromOffset(10,9)
label.BackgroundTransparency=1
label.TextColor3=Color3.fromRGB(255,235,247)
label.TextXAlignment=Enum.TextXAlignment.Left
label.TextYAlignment=Enum.TextYAlignment.Top
label.TextWrapped=true
label.Font=Enum.Font.Code
label.TextSize=13
label.Text="DQR ONE-CLICK BOOT CHECK"
label.Parent=frame
local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(115,34)
close.Position=UDim2.new(1,-125,1,-41)
close.Text="CLOSE"
close.BackgroundColor3=Color3.fromRGB(205,54,135)
close.TextColor3=Color3.new(1,1,1)
close.Font=Enum.Font.GothamBold
close.TextSize=12
close.Parent=frame
close.MouseButton1Click:Connect(function() gui:Destroy() end)
local lines={}
local function show(message)
    local s=tostring(message)
    print("[DQR BOOT] "..s)
    table.insert(lines,s)
    if #lines>10 then table.remove(lines,1) end
    if label.Parent then label.Text=table.concat(lines,"\n") end
end
show("1. Pink UI: OK")
show("2. loadstring: "..type(loadstring))
if type(loadstring)~="function" then
    show("STOP: Delta has no loadstring in this session.")
    return
end
local url="https://raw.githubusercontent.com/pemuladariindo/rahasia/main/main.lua?fix=10121"
show("3. Downloading GitHub...")
local fetched,source=pcall(function() return game:HttpGet(url) end)
if not fetched then
    show("HTTP ERROR: "..tostring(source):sub(1,170))
    return
end
if type(source)~="string" then show("INVALID HTTP DATA") return end
show("4. Source size: "..#source.." bytes")
if not source:find("GILDED HUB V10.1",1,true) then
    show("WRONG VERSION / FILE. GitHub main.lua is not V10.1.")
    return
end
show("5. V10.1 confirmed")
local compiled,fn,why=pcall(loadstring,source)
if not compiled or type(fn)~="function" then
    show("COMPILE ERROR: "..tostring(compiled and why or fn):sub(1,180))
    return
end
show("6. Compile OK; launching...")
local monitor=game:GetService("LogService").MessageOut:Connect(function(message)
    if tostring(message):find("[GS101] STARTUP ERROR",1,true) then
        show("MAIN ERROR: "..tostring(message):sub(1,160))
    end
end)
local ok,err=pcall(fn)
if not ok then show("RUNTIME ERROR: "..tostring(err):sub(1,180)) return end
task.wait(0.5)
if pg:FindFirstChild("GildedHubV101") then
    show("7. SUCCESS: AUTO DUNGEON GUI FOUND!")
    show("Close this panel; tap START AUTO DUNGEON.")
else
    show("7. MAIN GUI MISSING; see MAIN ERROR above.")
end
