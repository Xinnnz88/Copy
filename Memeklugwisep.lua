local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local doCopy
local isCopying = false
local schedulerRunning = false

local function getService(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    return ok and s or nil
end

local Players = getService("Players")
local HttpService = getService("HttpService")
local RunService = getService("RunService")
local LocalPlayer = Players.LocalPlayer

local DATA = "XinnzData"
pcall(function() if not isfolder(DATA) then makefolder(DATA) end end)
pcall(function() if not isfolder(DATA.."/history") then makefolder(DATA.."/history") end end)
pcall(function() if not isfolder(DATA.."/errors") then makefolder(DATA.."/errors") end end)
pcall(function() if not isfolder(DATA.."/saves") then makefolder(DATA.."/saves") end end)

local UPLOAD_SERVICES = {"catbox.moe", "litterbox", "filebin"}

local CFG = {
    SaveFolder = DATA.."/saves",
    RetryAttempts = 3,
    OutputFormat = "RBXLX",
    AutoOrganize = true,
    DupCheck = true,
    ExcludeList = {},
    BackupEnabled = false,
    BackupInterval = 10,
    FilenameTemplate = "{gameName}_{date}_{time}",
    WebhookURL = "",
    WebhookEnabled = false,
    WebhookAvatar = "",
    ChatCommandEnabled = true,
    PlayerTrigger = false,
    PlayerTriggerCount = 3,
    PlayerTriggerMode = "noscript",
    AutoUpload = false,
    UploadService = "catbox.moe",
    IgnorePlayers = false,
    DiscordCmdEnabled = false,
    DiscordCmdFile = DATA.."/discord_cmd.txt",
    DiscordRespFile = DATA.."/discord_resp.txt",
}

local function loadCFG()
    pcall(function()
        local f = DATA.."/settings.json"
        if isfile(f) then
            local d = HttpService:JSONDecode(readfile(f))
            for k, v in pairs(d) do if CFG[k] ~= nil then CFG[k] = v end end
        end
    end)
end

local function saveCFG()
    pcall(function() writefile(DATA.."/settings.json", HttpService:JSONEncode(CFG)) end)
end

loadCFG()

local _realGameName = nil
local function getRealGameName()
    if _realGameName then return _realGameName end
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId, Enum.InfoType.Asset)
    end)
    _realGameName = (ok and info and info.Name and info.Name ~= "" and info.Name) or "Place_"..tostring(game.PlaceId)
    return _realGameName
end

local function cleanName()
    local n = getRealGameName():gsub("[^%w_%-]","_")
    return (n == "" and "Unknown") or n
end

local function fmtTime(s)
    s = math.floor(s or 0)
    if s < 60 then return s.."s" end
    return math.floor(s/60).."m "..(s%60).."s"
end

local function fmtBytes(b)
    b = b or 0
    if b < 1024 then return b.."B"
    elseif b < 1048576 then return string.format("%.2fKB", b/1024)
    else return string.format("%.2fMB", b/1048576) end
end

local function fmtMB(b) return string.format("%.2f MB", (b or 0)/1048576) end

local function countInst()
    local n = 0
    pcall(function() for _ in pairs(game:GetDescendants()) do n = n+1 end end)
    return n
end

local function safeDate()
    local ok, r = pcall(function() return os.date("%d/%m/%y %H:%M") end)
    return (ok and r) or tostring(os.time())
end

local function applyTemplate(tmpl)
    local ts = tostring(os.time())
    local dS, tS
    pcall(function() dS = os.date("%Y%m%d") end)
    pcall(function() tS = os.date("%H%M%S") end)
    dS = dS or ts; tS = tS or ts
    local result = (tmpl or "{gameName}_{date}_{time}")
        :gsub("{gameName}", cleanName())
        :gsub("{placeId}", tostring(game.PlaceId))
        :gsub("{gameId}", tostring(game.GameId))
        :gsub("{date}", dS)
        :gsub("{time}", tS)
    local extMap = {RBXL=".rbxl", RBXLX=".rbxlx", RBXM=".rbxm"}
    local ext = extMap[CFG.OutputFormat] or ".rbxlx"
    if not result:match("%.[a-zA-Z]+$") then result = result..ext end
    return result
end

local function httpReq(options)
    local fn = nil
    pcall(function() if syn and syn.request then fn = syn.request end end)
    pcall(function() if not fn and http_request then fn = http_request end end)
    pcall(function() if not fn and request then fn = request end end)
    if not fn then return false, "No HTTP function" end
    return pcall(fn, options)
end

local function getRespBody(resp)
    local body = ""
    pcall(function()
        body = type(resp) == "table" and tostring(resp.Body or resp.body or "") or tostring(resp or "")
    end)
    return body
end

local function isHTMLResp(body)
    local low = body:lower():gsub("^%s+","")
    return low:match("^<!doctype") ~= nil or low:match("^<html") ~= nil or body:match("<title>") ~= nil
end

local function playSound(pitch)
    pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://9119713951"
        s.Volume = 0.5; s.Pitch = pitch or 1
        s.Parent = game:GetService("SoundService"); s:Play()
        task.delay(2, function() pcall(function() s:Destroy() end) end)
    end)
end

local function loadHistory()
    local ok, r = pcall(function()
        local f = DATA.."/history/index.json"
        if isfile(f) then return HttpService:JSONDecode(readfile(f)) end
        return {}
    end)
    return (ok and r) or {}
end

local function saveHistory(h)
    pcall(function() writefile(DATA.."/history/index.json", HttpService:JSONEncode(h)) end)
end

local function pushHistory(e)
    local h = loadHistory(); table.insert(h, 1, e)
    if #h > 30 then table.remove(h, #h) end
    saveHistory(h)
end

local function loadStats()
    local ok, r = pcall(function()
        local f = DATA.."/stats.json"
        if isfile(f) then return HttpService:JSONDecode(readfile(f)) end
        return {success=0, fail=0, totalBytes=0}
    end)
    return (ok and r) or {success=0, fail=0, totalBytes=0}
end

local function saveStats(s)
    pcall(function() writefile(DATA.."/stats.json", HttpService:JSONEncode(s)) end)
end

local function addStat(success, bytes)
    local s = loadStats()
    if success then s.success = (s.success or 0)+1 else s.fail = (s.fail or 0)+1 end
    s.totalBytes = (s.totalBytes or 0)+(bytes or 0)
    saveStats(s); return s
end

local function logError(ctx, err)
    pcall(function()
        local dir = DATA.."/errors"
        if not isfolder(dir) then makefolder(dir) end
        writefile(dir.."/err_"..tostring(os.time())..".txt", "Time:"..tostring(os.time()).."\nCtx:"..tostring(ctx).."\nErr:"..tostring(err).."\nPlace:"..tostring(game.PlaceId))
    end)
end

local Window = Fluent:CreateWindow({
    Title = "Xinnz Copy v1.2",
    SubTitle = "Game Copier",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 480),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local Tabs = {
    Main = Window:AddTab({ Title = "Copy", Icon = "copy" }),
    LoadAll = Window:AddTab({ Title = "Load All", Icon = "globe" }),
    Upload = Window:AddTab({ Title = "Upload", Icon = "upload-cloud" }),
    Webhook = Window:AddTab({ Title = "Webhook", Icon = "webhook" }),
    Discord = Window:AddTab({ Title = "Discord", Icon = "bot" }),
    Info = Window:AddTab({ Title = "Info", Icon = "info" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Options = Fluent.Options

local statusParagraph = Tabs.Main:AddParagraph({
    Title = "Status",
    Content = "✅ Ready — v1.2",
})

local function setStatus(txt)
    pcall(function() statusParagraph:Set({ Title = "Status", Content = txt }) end)
    print("[Xinnz] STATUS: "..tostring(txt))
end

local function addLog(txt)
    print("[Xinnz] "..tostring(txt))
end

Tabs.Main:AddParagraph({
    Title = "⚡ Xinnz Copy Mobile v1.2",
    Content = "Pilih mode copy di bawah. Pastikan format RBXLX untuk upload.",
})

Tabs.Main:AddButton({
    Title = "📄 Format: "..CFG.OutputFormat,
    Description = "Klik untuk ganti format output (RBXLX / RBXL / RBXM)",
    Callback = function()
        local fmts = {"RBXLX","RBXL","RBXM"}; local idx = 1
        for i,v in ipairs(fmts) do if v == CFG.OutputFormat then idx = i; break end end
        idx = (idx % #fmts)+1; CFG.OutputFormat = fmts[idx]; saveCFG()
        Fluent:Notify({ Title="Format", Content="📄 Format → "..CFG.OutputFormat, Duration=3 })
        if CFG.OutputFormat == "RBXL" then
            Fluent:Notify({ Title="⚠️ Peringatan", Content="RBXL binary — gunakan RBXLX untuk upload!", Duration=5 })
        end
    end,
})

local IgnoreToggle = Tabs.Main:AddToggle("IgnorePlayers", {
    Title = "👤 Ignore Players",
    Description = "Hapus karakter player dari copy",
    Default = CFG.IgnorePlayers,
})
IgnoreToggle:OnChanged(function() CFG.IgnorePlayers = Options.IgnorePlayers.Value; saveCFG() end)

local AutoOrgToggle = Tabs.Main:AddToggle("AutoOrganize", {
    Title = "📁 Auto-Organize",
    Description = "Simpan di subfolder PlaceID",
    Default = CFG.AutoOrganize,
})
AutoOrgToggle:OnChanged(function() CFG.AutoOrganize = Options.AutoOrganize.Value; saveCFG() end)

local DupCheckToggle = Tabs.Main:AddToggle("DupCheck", {
    Title = "🔍 Dup Check",
    Description = "Skip jika file sudah ada",
    Default = CFG.DupCheck,
})
DupCheckToggle:OnChanged(function() CFG.DupCheck = Options.DupCheck.Value; saveCFG() end)

Tabs.Main:AddButton({
    Title = "📦 Copy WITHOUT Script",
    Description = "Copy semua kecuali script",
    Callback = function() if doCopy then doCopy("noscript","Manual") end end,
})
Tabs.Main:AddButton({
    Title = "📜 Copy WITH Script",
    Description = "Copy termasuk script (decompile)",
    Callback = function() if doCopy then doCopy("script","Manual") end end,
})
Tabs.Main:AddButton({
    Title = "🏔️ Copy WITH Terrain",
    Description = "Copy termasuk terrain",
    Callback = function() if doCopy then doCopy("terrain","Manual") end end,
})
Tabs.Main:AddButton({
    Title = "🏔️📜 Terrain + Script (Full)",
    Description = "Copy lengkap: terrain + script",
    Callback = function() if doCopy then doCopy("terrain_script","Manual") end end,
})

local RetrySlider = Tabs.Main:AddSlider("RetryAttempts", {
    Title = "🔁 Retry Attempts",
    Description = "Jumlah percobaan ulang jika gagal",
    Default = CFG.RetryAttempts,
    Min = 1,
    Max = 5,
    Rounding = 0,
    Callback = function(v) CFG.RetryAttempts = v; saveCFG() end,
})

Tabs.Main:AddButton({
    Title = "📊 Show Stats",
    Callback = function()
        local s = loadStats()
        Fluent:Notify({
            Title = "📊 Statistics",
            Content = "✅ Success: "..tostring(s.success or 0).."\n❌ Fail: "..tostring(s.fail or 0).."\n💾 Total: "..fmtBytes(s.totalBytes or 0),
            Duration = 8
        })
    end,
})

local LA_FOLDER = "Xinnz_Loaded"
local LA_ACTIVE = false
local _laSeen = {}
local _laAddConn = nil
local _laHeartConn = nil
local _laKnownPos = {}
local _laKnownKeys = {}
local _laKnownIdx = 1

Tabs.LoadAll:AddParagraph({
    Title = "🌍 Load All Instances",
    Content = "Menggunakan Heartbeat 60fps untuk keep-alive streaming.\nInstance di-clone ke folder lokal agar tidak hilang.",
})

local loadStatusParagraph = Tabs.LoadAll:AddParagraph({
    Title = "Status",
    Content = "🔴 OFF",
})

local function _laGetFolder()
    local f = workspace:FindFirstChild(LA_FOLDER)
    if not f then f = Instance.new("Folder"); f.Name = LA_FOLDER; f.Parent = workspace end
    return f
end

local function _laUpdateUI(txt)
    pcall(function() loadStatusParagraph:Set({ Title="Status", Content=txt }) end)
end

local function _laAddPos(pos)
    if not pos then return end
    local key = math.floor(pos.X/80)..","..math.floor(pos.Z/80)
    if not _laKnownKeys[key] then _laKnownKeys[key]=true; table.insert(_laKnownPos,pos) end
end

local function _laClone(v, folder)
    if not v or _laSeen[v] then return false end
    local ok1,par = pcall(function() return v.Parent end)
    if not ok1 or par == folder or v:IsDescendantOf(folder) then return false end
    local ok2,name = pcall(function() return v.Name end)
    if not ok2 or name == LA_FOLDER then return false end
    local ok3,cls = pcall(function() return v.ClassName end)
    if not ok3 then return false end
    local allowed = cls=="Model" or cls=="Part" or cls=="BasePart" or cls=="MeshPart" or cls=="UnionOperation" or cls=="WedgePart"
    if not allowed then return false end
    _laSeen[v] = true
    pcall(function()
        local cl = v:Clone(); if not cl then return end
        if cl:IsA("BasePart") then cl.Anchored = true end
        for _,p in ipairs(cl:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
        cl.Parent = folder
    end)
    for _,d in ipairs(v:GetDescendants()) do _laSeen[d] = true end
    return true
end

local function stopLoadAll()
    LA_ACTIVE = false
    if _laAddConn then pcall(function() _laAddConn:Disconnect() end); _laAddConn = nil end
    if _laHeartConn then pcall(function() _laHeartConn:Disconnect() end); _laHeartConn = nil end
    _laUpdateUI("🔴 OFF — Clone folder tetap ada di workspace."..LA_FOLDER)
    setStatus("🌍 Load All OFF")
    addLog("⏹ Load All: OFF")
    Fluent:Notify({ Title="Load All", Content="⏹ OFF — clone folder tetap ada", Duration=3 })
end

local function startLoadAll()
    if LA_ACTIVE then return end
    LA_ACTIVE = true; _laSeen = {}; _laKnownPos = {}; _laKnownKeys = {}; _laKnownIdx = 1
    local folder = _laGetFolder()
    _laUpdateUI("🟢 ON — Heartbeat 60fps aktif...")
    setStatus("🌍 Load All ON")
    addLog("🌍 Load All ON v1.2")
    Fluent:Notify({ Title="Load All", Content="🌍 ON — Heartbeat 60fps aktif!\nTap OFF untuk berhenti.", Duration=4 })
    local heartN = 0
    _laHeartConn = RunService.Heartbeat:Connect(function()
        if not LA_ACTIVE then return end
        heartN = heartN+1
        pcall(function()
            local char = LocalPlayer.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
                if hrp then workspace:RequestStreamAroundAsync(hrp.Position, 512); _laAddPos(hrp.Position) end
            end
        end)
        if heartN%30 == 0 and #_laKnownPos > 0 then
            pcall(function()
                local pos = _laKnownPos[_laKnownIdx]
                if pos then workspace:RequestStreamAroundAsync(pos, 300) end
                _laKnownIdx = (_laKnownIdx % #_laKnownPos)+1
            end)
        end
    end)
    _laAddConn = workspace.DescendantAdded:Connect(function(v)
        if not LA_ACTIVE then return end
        if v == folder or v:IsDescendantOf(folder) then return end
        _laClone(v, folder)
        pcall(function()
            local pos
            if v:IsA("BasePart") then pos = v.Position
            elseif v:IsA("Model") then
                local ok4,cf = pcall(function() return v:GetPivot() end)
                if ok4 and cf then pos = cf.Position end
            end
            _laAddPos(pos)
        end)
    end)
    task.spawn(function()
        local loopN = 0; local cloned = 0
        while LA_ACTIVE do
            loopN = loopN+1; local newN = 0
            for _,v in ipairs(workspace:GetDescendants()) do
                if not LA_ACTIVE then break end
                if not (v == folder or v:IsDescendantOf(folder) or _laSeen[v]) then
                    if _laClone(v, folder) then cloned = cloned+1; newN = newN+1 end
                    pcall(function()
                        local pos
                        if v:IsA("BasePart") then pos = v.Position
                        elseif v:IsA("Model") then
                            local ok4,cf = pcall(function() return v:GetPivot() end)
                            if ok4 and cf then pos = cf.Position end
                        end
                        _laAddPos(pos)
                    end)
                end
            end
            if newN > 0 or loopN%10 == 0 then
                local saved = 0; pcall(function() saved = #folder:GetChildren() end)
                local inst = countInst()
                local txt = "🟢 ON  Loop #"..loopN.."  Saved: "..saved.."  Instances: "..inst
                _laUpdateUI(txt)
                setStatus("🌍 Load ON 🟢 saved:"..saved.." inst:"..inst)
            end
            for _ = 1,3 do if not LA_ACTIVE then break end; task.wait(0.1) end
        end
        print("[Xinnz] 🌍 Clone loop stopped")
    end)
end

Tabs.LoadAll:AddButton({
    Title = "🌍 START Load All",
    Description = "Mulai loading semua instance (Heartbeat 60fps)",
    Callback = function()
        if LA_ACTIVE then
            Fluent:Notify({ Title="Load All", Content="⚠️ Sudah aktif! Klik STOP untuk berhenti.", Duration=3 })
        else
            startLoadAll()
        end
    end,
})

Tabs.LoadAll:AddButton({
    Title = "⏹ STOP Load All",
    Description = "Hentikan loading (folder clone tetap ada)",
    Callback = function()
        if LA_ACTIVE then stopLoadAll()
        else Fluent:Notify({ Title="Load All", Content="⚠️ Tidak aktif.", Duration=2 }) end
    end,
})

Tabs.LoadAll:AddButton({
    Title = "📊 Load All Status",
    Description = "Lihat status folder dan jumlah instance",
    Callback = function()
        local saved = 0
        pcall(function()
            local f = workspace:FindFirstChild(LA_FOLDER)
            if f then saved = #f:GetChildren() end
        end)
        Fluent:Notify({
            Title = "🌍 Load All Status",
            Content = "Status: "..(LA_ACTIVE and "🟢 AKTIF" or "🔴 TIDAK AKTIF").."\nSaved: "..saved.."\nInstances: "..countInst().."\nKnown Pos: "..#_laKnownPos,
            Duration = 6,
        })
    end,
})

Tabs.Upload:AddParagraph({
    Title = "☁️ Auto Upload",
    Content = "Upload otomatis setelah copy ke catbox.moe / litterbox / filebin.\n⚠️ Gunakan format RBXLX!",
})

local AutoUploadToggle = Tabs.Upload:AddToggle("AutoUpload", {
    Title = "☁️ Auto Upload",
    Description = "Upload file setelah copy selesai",
    Default = CFG.AutoUpload,
})
AutoUploadToggle:OnChanged(function()
    CFG.AutoUpload = Options.AutoUpload.Value; saveCFG()
    if CFG.AutoUpload and CFG.OutputFormat == "RBXL" then
        Fluent:Notify({ Title="⚠️ Warning", Content="RBXL binary dapat menyebabkan error upload! Ganti ke RBXLX.", Duration=5 })
    end
end)

local UploadServiceDropdown = Tabs.Upload:AddDropdown("UploadService", {
    Title = "☁️ Upload Service",
    Description = "Pilih layanan upload utama",
    Values = UPLOAD_SERVICES,
    Default = CFG.UploadService,
})
UploadServiceDropdown:OnChanged(function(v) CFG.UploadService = v; saveCFG() end)

Tabs.Upload:AddButton({
    Title = "🧪 Test Upload",
    Description = "Test upload file kecil ke catbox.moe",
    Callback = function()
        task.spawn(function()
            setStatus("🧪 Testing upload...")
            local tc = '<?xml version="1.0" encoding="utf-8"?>\n<roblox version="4">\n<Item class="Model">\n<Properties>\n<string name="Name">Xinnz_Test</string>\n</Properties>\n</Item>\n</roblox>'
            local tn = "xinnz_test_"..tostring(os.time())..".rbxlx"
            local urlSafe = tn:gsub("[^%w%.%-_]","_")
            local boundary = "XBound"..tostring(os.time())
            local CRLF = "\r\n"
            local body = "--"..boundary..CRLF..'Content-Disposition: form-data; name="reqtype"'..CRLF..CRLF.."fileupload"..CRLF
                .."--"..boundary..CRLF..'Content-Disposition: form-data; name="fileToUpload"; filename="'..urlSafe..'"'..CRLF
                .."Content-Type: application/octet-stream"..CRLF..CRLF..tc..CRLF.."--"..boundary.."--"..CRLF
            local ok2, resp = httpReq({
                Url = "https://catbox.moe/user/api.php", Method = "POST",
                Headers = {["Content-Type"]="multipart/form-data; boundary="..boundary},
                Body = body,
            })
            local b2 = getRespBody(resp)
            local link = nil
            if ok2 and not isHTMLResp(b2) then link = b2:match("^%s*(https?://[^%s\r\n]+)") end
            if link then
                setStatus("✅ Upload OK: "..link:sub(1,40))
                Fluent:Notify({ Title="✅ Test Upload OK", Content=link, Duration=8 })
                playSound(1.5)
            else
                setStatus("❌ Upload failed")
                Fluent:Notify({ Title="❌ Test Upload Gagal", Content="Pastikan format RBXLX dan koneksi OK.", Duration=5 })
                playSound(0.6)
            end
        end)
    end,
})

Tabs.Upload:AddButton({
    Title = "📋 Lihat Links",
    Description = "Tampilkan history upload links",
    Callback = function()
        local lf = DATA.."/saves/links.txt"
        if isfile(lf) then
            local content = readfile(lf)
            local lines = {}
            for line in content:gmatch("[^\n]+") do
                table.insert(lines, line)
                if #lines >= 5 then break end
            end
            Fluent:Notify({
                Title = "📋 Upload Links (5 terbaru)",
                Content = table.concat(lines, "\n"),
                Duration = 10,
            })
        else
            Fluent:Notify({ Title="📋 Links", Content="Belum ada link tersimpan.", Duration=3 })
        end
    end,
})

Tabs.Webhook:AddParagraph({
    Title = "📡 Discord Webhook",
    Content = "Kirim notifikasi ke Discord setelah copy selesai.",
})

local WebhookToggle = Tabs.Webhook:AddToggle("WebhookEnabled", {
    Title = "📡 Enable Webhook",
    Default = CFG.WebhookEnabled,
})
WebhookToggle:OnChanged(function() CFG.WebhookEnabled = Options.WebhookEnabled.Value; saveCFG() end)

local WebhookInput = Tabs.Webhook:AddInput("WebhookURL", {
    Title = "🔗 Webhook URL",
    Description = "https://discord.com/api/webhooks/...",
    Default = CFG.WebhookURL,
    Placeholder = "https://discord.com/api/webhooks/ID/TOKEN",
    Numeric = false,
    Finished = true,
    Callback = function(v) CFG.WebhookURL = v; saveCFG() end,
})

local AvatarInput = Tabs.Webhook:AddInput("WebhookAvatar", {
    Title = "🖼️ Avatar URL (optional)",
    Default = CFG.WebhookAvatar,
    Placeholder = "https://...",
    Numeric = false,
    Finished = true,
    Callback = function(v) CFG.WebhookAvatar = v; saveCFG() end,
})

Tabs.Webhook:AddButton({
    Title = "🧪 Test Webhook",
    Callback = function()
        if CFG.WebhookURL == "" then
            Fluent:Notify({ Title="⚠️", Content="URL webhook belum diisi!", Duration=3 }); return
        end
        task.spawn(function()
            local payload = {
                username = "Xinnz v1.2",
                embeds = {{
                    title = "🧪 Test Webhook",
                    description = "Webhook Xinnz aktif!\nGame: **"..getRealGameName().."**",
                    color = 3066993,
                }}
            }
            local ok, resp = httpReq({
                Url = CFG.WebhookURL, Method = "POST",
                Headers = {["Content-Type"]="application/json"},
                Body = HttpService:JSONEncode(payload),
            })
            if ok then
                Fluent:Notify({ Title="✅ Webhook OK", Content="Notifikasi dikirim!", Duration=4 })
            else
                Fluent:Notify({ Title="❌ Webhook Gagal", Content=getRespBody(resp):sub(1,60), Duration=5 })
            end
        end)
    end,
})

Tabs.Discord:AddParagraph({
    Title = "🤖 Discord Command Bridge",
    Content = "Kontrol script dari file teks.\nTulis perintah ke file, script akan membaca dan mengeksekusi.",
})

local DiscordCmdToggle = Tabs.Discord:AddToggle("DiscordCmdEnabled", {
    Title = "🤖 Enable Discord Commands",
    Default = CFG.DiscordCmdEnabled,
})
DiscordCmdToggle:OnChanged(function() CFG.DiscordCmdEnabled = Options.DiscordCmdEnabled.Value; saveCFG() end)

local CmdFileInput = Tabs.Discord:AddInput("DiscordCmdFile", {
    Title = "📁 Command File Path",
    Default = CFG.DiscordCmdFile,
    Placeholder = "XinnzData/discord_cmd.txt",
    Finished = true,
    Callback = function(v) CFG.DiscordCmdFile = v; saveCFG() end,
})

local RespFileInput = Tabs.Discord:AddInput("DiscordRespFile", {
    Title = "📄 Response File Path",
    Default = CFG.DiscordRespFile,
    Placeholder = "XinnzData/discord_resp.txt",
    Finished = true,
    Callback = function(v) CFG.DiscordRespFile = v; saveCFG() end,
})

Tabs.Discord:AddParagraph({
    Title = "📋 Perintah tersedia",
    Content = "• status\n• copy [noscript|script|terrain|terrain_script]\n• upload_last\n• list_files\n• help",
})

Tabs.Discord:AddButton({
    Title = "📝 Tulis Command Manual",
    Description = "Tulis perintah test 'status' ke file",
    Callback = function()
        pcall(function()
            writefile(CFG.DiscordCmdFile, "status")
            Fluent:Notify({ Title="📝 Command ditulis", Content="'status' ditulis ke "..CFG.DiscordCmdFile, Duration=3 })
        end)
    end,
})

Tabs.Discord:AddButton({
    Title = "📖 Baca Response",
    Callback = function()
        if isfile(CFG.DiscordRespFile) then
            local r = readfile(CFG.DiscordRespFile)
            Fluent:Notify({ Title="📖 Response", Content=r:sub(1,200), Duration=8 })
        else
            Fluent:Notify({ Title="📖 Response", Content="File response belum ada.", Duration=3 })
        end
    end,
})

Tabs.Info:AddParagraph({
    Title = "🎮 Game Info",
    Content = "Place ID: "..tostring(game.PlaceId).."\nGame ID: "..tostring(game.GameId).."\nStreaming: "..(workspace.StreamingEnabled and "ON ⚠️" or "OFF ✅"),
})

local execName = "Unknown"
pcall(function() if identifyexecutor then execName = identifyexecutor() or "Unknown" end end)

Tabs.Info:AddParagraph({
    Title = "⚙️ Executor",
    Content = execName,
})

local gameNameParagraph = Tabs.Info:AddParagraph({
    Title = "🎮 Game Name",
    Content = "Loading...",
})

local instancesParagraph = Tabs.Info:AddParagraph({
    Title = "🏗️ Instances",
    Content = "Counting...",
})

local statsParagraph = Tabs.Info:AddParagraph({
    Title = "📊 Stats",
    Content = "Loading...",
})

local function refreshInfoTab()
    task.spawn(function()
        local cnt = countInst()
        local gn = getRealGameName()
        local s = loadStats()
        pcall(function()
            gameNameParagraph:Set({ Title="🎮 Game Name", Content=gn })
            instancesParagraph:Set({ Title="🏗️ Instances", Content=tostring(cnt).." ("..fmtBytes(cnt*180).." est)" })
            statsParagraph:Set({
                Title = "📊 Statistics",
                Content = "✅ Success: "..tostring(s.success or 0).."\n❌ Fail: "..tostring(s.fail or 0).."\n💾 Total: "..fmtBytes(s.totalBytes or 0),
            })
        end)
    end)
end

Tabs.Info:AddButton({
    Title = "🔄 Refresh Info",
    Callback = function() refreshInfoTab(); Fluent:Notify({ Title="🔄", Content="Info diperbarui!", Duration=2 }) end,
})

Tabs.Info:AddButton({
    Title = "📜 History Terakhir",
    Callback = function()
        local h = loadHistory()
        if #h == 0 then
            Fluent:Notify({ Title="📜 History", Content="Belum ada history.", Duration=3 }); return
        end
        local e = h[1]
        Fluent:Notify({
            Title = "📜 Copy Terakhir",
            Content = "Game: "..(e.gameName or "?").."\nMode: "..(e.mode or "?").."\nSize: "..(e.size or "?").."\nStatus: "..(e.success and "✅" or "❌").."\nDate: "..(e.date or "?"),
            Duration = 8,
        })
    end,
})

Tabs.Settings:AddParagraph({
    Title = "⚙️ Settings",
    Content = "Konfigurasi copy, template, backup, dan trigger.",
})

local SaveFolderInput = Tabs.Settings:AddInput("SaveFolder", {
    Title = "📂 Save Folder",
    Default = CFG.SaveFolder,
    Finished = true,
    Callback = function(v) CFG.SaveFolder = v; saveCFG() end,
})

local TemplateInput = Tabs.Settings:AddInput("FilenameTemplate", {
    Title = "📝 Filename Template",
    Description = "{gameName} {placeId} {gameId} {date} {time}",
    Default = CFG.FilenameTemplate,
    Finished = true,
    Callback = function(v) CFG.FilenameTemplate = v; saveCFG() end,
})

local PlayerTrigToggle = Tabs.Settings:AddToggle("PlayerTrigger", {
    Title = "👥 Player Count Trigger",
    Description = "Auto-copy saat player ≤ threshold",
    Default = CFG.PlayerTrigger,
})
PlayerTrigToggle:OnChanged(function() CFG.PlayerTrigger = Options.PlayerTrigger.Value; saveCFG() end)

local PlayerTrigCount = Tabs.Settings:AddSlider("PlayerTriggerCount", {
    Title = "👥 Player Threshold",
    Default = CFG.PlayerTriggerCount,
    Min = 1,
    Max = 20,
    Rounding = 0,
    Callback = function(v) CFG.PlayerTriggerCount = v; saveCFG() end,
})

local TrigModeDropdown = Tabs.Settings:AddDropdown("PlayerTriggerMode", {
    Title = "📦 Trigger Mode",
    Values = {"noscript","script","terrain","terrain_script"},
    Default = CFG.PlayerTriggerMode,
})
TrigModeDropdown:OnChanged(function(v) CFG.PlayerTriggerMode = v; saveCFG() end)

local ChatCmdToggle = Tabs.Settings:AddToggle("ChatCommandEnabled", {
    Title = "💬 Chat Commands",
    Description = "/xinnz [copy|script|terrain|ts|loadall|status|help]",
    Default = CFG.ChatCommandEnabled,
})
ChatCmdToggle:OnChanged(function() CFG.ChatCommandEnabled = Options.ChatCommandEnabled.Value; saveCFG() end)

local BackupToggle = Tabs.Settings:AddToggle("BackupEnabled", {
    Title = "⏰ Auto-Backup",
    Default = CFG.BackupEnabled,
})
BackupToggle:OnChanged(function() CFG.BackupEnabled = Options.BackupEnabled.Value; saveCFG() end)

local BackupInterval = Tabs.Settings:AddSlider("BackupInterval", {
    Title = "⏱ Backup Interval (menit)",
    Default = CFG.BackupInterval,
    Min = 1,
    Max = 120,
    Rounding = 0,
    Callback = function(v) CFG.BackupInterval = v; saveCFG() end,
})

Tabs.Settings:AddButton({
    Title = "📤 Export Preset",
    Callback = function()
        pcall(function()
            writefile(DATA.."/preset.json", HttpService:JSONEncode(CFG))
            Fluent:Notify({ Title="📤 Export", Content="Preset disimpan ke XinnzData/preset.json", Duration=3 })
        end)
    end,
})

Tabs.Settings:AddButton({
    Title = "📥 Import Preset",
    Callback = function()
        pcall(function()
            local path = DATA.."/preset.json"
            if not isfile(path) then
                Fluent:Notify({ Title="❌", Content="File preset.json tidak ditemukan!", Duration=3 }); return
            end
            local preset = HttpService:JSONDecode(readfile(path))
            for k, v in pairs(preset) do if CFG[k] ~= nil then CFG[k] = v end end
            saveCFG()
            pcall(function() Options.AutoUpload:SetValue(CFG.AutoUpload) end)
            pcall(function() Options.AutoOrganize:SetValue(CFG.AutoOrganize) end)
            pcall(function() Options.DupCheck:SetValue(CFG.DupCheck) end)
            pcall(function() Options.WebhookEnabled:SetValue(CFG.WebhookEnabled) end)
            pcall(function() Options.PlayerTrigger:SetValue(CFG.PlayerTrigger) end)
            pcall(function() Options.BackupEnabled:SetValue(CFG.BackupEnabled) end)
            pcall(function() Options.ChatCommandEnabled:SetValue(CFG.ChatCommandEnabled) end)
            Fluent:Notify({ Title="📥 Import", Content="Preset berhasil diimpor!", Duration=3 })
        end)
    end,
})

Tabs.Settings:AddButton({
    Title = "♻️ Reset Defaults",
    Callback = function()
        Window:Dialog({
            Title = "Reset Settings",
            Content = "Reset semua setting ke default?",
            Buttons = {
                { Title="Reset", Callback = function()
                    CFG.SaveFolder=DATA.."/saves"; CFG.RetryAttempts=3; CFG.OutputFormat="RBXLX"
                    CFG.AutoOrganize=true; CFG.DupCheck=true; CFG.ExcludeList={}
                    CFG.BackupEnabled=false; CFG.BackupInterval=10
                    CFG.FilenameTemplate="{gameName}_{date}_{time}"
                    CFG.WebhookURL=""; CFG.WebhookEnabled=false; CFG.WebhookAvatar=""
                    CFG.ChatCommandEnabled=true; CFG.PlayerTrigger=false
                    CFG.PlayerTriggerCount=3; CFG.PlayerTriggerMode="noscript"
                    CFG.AutoUpload=false; CFG.UploadService="catbox.moe"
                    CFG.DiscordCmdEnabled=false
                    saveCFG()
                    Fluent:Notify({ Title="♻️ Reset", Content="Settings direset ke default!", Duration=3 })
                end},
                { Title="Cancel", Callback = function() end },
            }
        })
    end,
})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("XinnzFluentHub")
SaveManager:SetFolder("XinnzFluentHub/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

local function doUploadOnce(service, fileContent, fileName)
    local urlSafe = fileName:gsub("[^%w%.%-_]","_")
    local boundary = "XBound"..tostring(os.time())
    local CRLF = "\r\n"
    local ok, resp
    if service == "catbox.moe" then
        local body = "--"..boundary..CRLF..'Content-Disposition: form-data; name="reqtype"'..CRLF..CRLF.."fileupload"..CRLF
            .."--"..boundary..CRLF..'Content-Disposition: form-data; name="fileToUpload"; filename="'..urlSafe..'"'..CRLF
            .."Content-Type: application/octet-stream"..CRLF..CRLF..fileContent..CRLF.."--"..boundary.."--"..CRLF
        ok,resp = httpReq({Url="https://catbox.moe/user/api.php",Method="POST",
            Headers={["Content-Type"]="multipart/form-data; boundary="..boundary},Body=body})
        local b2 = getRespBody(resp)
        if not ok then return nil,"catbox error" end
        if isHTMLResp(b2) then return nil,"catbox HTML — use RBXLX!" end
        local url = b2:match("^%s*(https://files%.catbox%.moe/[^%s\r\n]+)") or b2:match("^%s*(https?://[^%s\r\n]+)")
        if url then return url,nil end
        return nil,"catbox: "..b2:sub(1,80)
    end
    if service == "litterbox" then
        local body = "--"..boundary..CRLF..'Content-Disposition: form-data; name="reqtype"'..CRLF..CRLF.."fileupload"..CRLF
            .."--"..boundary..CRLF..'Content-Disposition: form-data; name="time"'..CRLF..CRLF.."72h"..CRLF
            .."--"..boundary..CRLF..'Content-Disposition: form-data; name="fileToUpload"; filename="'..urlSafe..'"'..CRLF
            .."Content-Type: application/octet-stream"..CRLF..CRLF..fileContent..CRLF.."--"..boundary.."--"..CRLF
        ok,resp = httpReq({Url="https://litterbox.catbox.moe/resources/internals/api.php",Method="POST",
            Headers={["Content-Type"]="multipart/form-data; boundary="..boundary},Body=body})
        local b2 = getRespBody(resp)
        if not ok then return nil,"litterbox error" end
        if isHTMLResp(b2) then return nil,"litterbox HTML" end
        local url = b2:match("^%s*(https?://[^%s\r\n]+)")
        if url then return url,nil end
        return nil,"litterbox: "..b2:sub(1,80)
    end
    if service == "filebin" then
        local binId = "xinnz"..tostring(game.PlaceId):sub(-6)..tostring(os.time()):sub(-4)
        local upURL = "https://filebin.net/"..binId.."/"..urlSafe
        ok,resp = httpReq({Url=upURL,Method="POST",
            Headers={["Content-Type"]="application/octet-stream",["Accept"]="application/json"},Body=fileContent})
        local b2 = getRespBody(resp)
        if not ok then return nil,"filebin error" end
        if isHTMLResp(b2) then return nil,"filebin HTML" end
        local sc = 0; pcall(function() sc = tonumber(resp.StatusCode or resp.statusCode or 0) or 0 end)
        if sc >= 400 then return nil,"filebin HTTP "..tostring(sc) end
        return "https://filebin.net/"..binId.."/"..urlSafe, nil
    end
    return nil,"Unknown service"
end

local function doUploadSync(fileContent, fileName)
    local order = {CFG.UploadService}
    for _,svc in ipairs(UPLOAD_SERVICES) do
        local found = false
        for _,s in ipairs(order) do if s == svc then found = true; break end end
        if not found then table.insert(order, svc) end
    end
    if CFG.OutputFormat == "RBXL" then addLog("⚠️ RBXL binary — use RBXLX") end
    for _,service in ipairs(order) do
        setStatus("📤 Upload → "..service.."...")
        local link, err = doUploadOnce(service, fileContent, fileName)
        if link then
            setStatus("✅ Uploaded! ["..service.."]")
            addLog("✅ Upload OK ["..service.."]: "..link)
            Fluent:Notify({ Title="✅ Upload OK", Content="["..service.."]\n"..link:sub(1,50), Duration=8 })
            pcall(function()
                local lf = DATA.."/saves/links.txt"; local ex = ""
                pcall(function() if isfile(lf) then ex = readfile(lf) end end)
                writefile(lf, safeDate().." | "..fileName.." | "..service.." | "..link.."\n"..ex)
            end)
            return link, service
        else
            addLog("⚠️ "..service..": "..(err or "?"):sub(1,50))
        end
    end
    addLog("❌ All uploads failed!")
    Fluent:Notify({ Title="❌ Upload Gagal", Content="Pastikan format RBXLX dan koneksi OK.", Duration=5 })
    return nil, nil
end

local function sendWebhook(data)
    if not CFG.WebhookEnabled then return end
    local url = CFG.WebhookURL or ""
    if url == "" or not url:match("https://discord%.com/api/webhooks/") then
        addLog("📡 Webhook URL invalid"); return
    end
    local gameName = getRealGameName()
    local placeLink = "https://www.roblox.com/games/"..tostring(game.PlaceId)
    local thumb = (CFG.WebhookAvatar ~= "" and CFG.WebhookAvatar) or "https://www.roblox.com/Thumbs/GameIcon.ashx?universeId="..tostring(game.GameId)
    local desc = "**Game:** ["..gameName.."]("..placeLink..")\n**Status:** "..(data.success and "✅ Success" or "❌ Failed")
    if data.uploadLink and data.uploadLink ~= "" then
        desc = desc.."\n\n⬇️ **[DOWNLOAD]("..data.uploadLink..")**\n`"..data.uploadLink.."`"
    end
    local dlVal = data.uploadLink and data.uploadLink ~= "" and "[Download]("..data.uploadLink..")" or "_No upload_"
    local fields = {
        {name="📦 Size", value=data.size or "N/A", inline=true},
        {name="⏱ Duration", value=data.duration or "?", inline=true},
        {name="⚡ Speed", value=data.speed or "?", inline=true},
        {name="📄 Format", value=CFG.OutputFormat, inline=true},
        {name="🏷️ Mode", value=data.mode or "?", inline=true},
        {name="📡 Trigger", value=data.trigger or "Manual", inline=true},
        {name="🏗️ Instances", value=data.instances or "?", inline=true},
        {name="💾 Saved Inst", value=data.savedInst or "0", inline=true},
        {name="⬇️ Download", value=dlVal, inline=false},
    }
    local payload = {
        username = "Xinnz v1.2",
        avatar_url = thumb,
        embeds = {{
            title = (data.success and "✅" or "❌").." ["..gameName.."] "..(data.mode or ""),
            description = desc,
            color = data.success and 3066993 or 15158332,
            fields = fields,
            thumbnail = {url=thumb},
            footer = {text="Xinnz v1.2 · "..(data.date or safeDate()), icon_url=thumb},
        }}
    }
    local ok, resp = httpReq({Url=url, Method="POST", Headers={["Content-Type"]="application/json"}, Body=HttpService:JSONEncode(payload)})
    if ok then addLog("📡 Webhook ✅") else addLog("📡 Webhook FAILED: "..getRespBody(resp):sub(1,40)) end
end

local function runUSSI(decompile, ignorePlayer, saveTerrain)
    local ussi_url = "https://raw.githubusercontent.com/verysigmapro/UniversalSynSaveInstance-With-Save-Terrain/refs/heads/main/saveinstance.luau"
    local ussi_code = nil
    local ok0, e0 = pcall(function() ussi_code = game:HttpGet(ussi_url, true) end)
    if not ok0 or not ussi_code or ussi_code == "" then
        addLog("❌ Gagal download USSI: "..(tostring(e0):sub(1,60)))
        error("USSI download failed")
    end
    local si = loadstring(ussi_code, "saveinstance")
    if not si then error("USSI load failed") end
    si = si()
    local baseName = applyTemplate(CFG.FilenameTemplate)
    si({ FilePath=baseName, Decompile=decompile, ShowStatus=true,
         RemovePlayerCharacters=ignorePlayer, SaveTerrain=saveTerrain or false })
    task.wait(0.5)
    local rawBytes=0; local rawContent=nil; local foundName=baseName
    local function tryRead(name)
        if rawBytes > 0 or not name or name == "" then return end
        pcall(function()
            if isfile(name) then
                local c = readfile(name)
                if c and #c > 200 and not (c:sub(1,50):lower():match("<!doctype") or c:sub(1,50):lower():match("<html")) then
                    rawContent=c; rawBytes=#c; foundName=name
                    print("[Xinnz] ✅ File: "..name.." ("..rawBytes.."b)")
                end
            end
        end)
    end
    tryRead(baseName)
    if rawBytes == 0 then
        local stem = baseName:match("^(.-)%.[^%.]+$") or baseName
        for _,ext in ipairs({".rbxlx",".rbxl",".rbxm"}) do tryRead(stem..ext); if rawBytes>0 then break end end
    end
    if rawBytes == 0 then
        task.wait(1.0); tryRead(baseName)
        if rawBytes == 0 then
            local stem = baseName:match("^(.-)%.[^%.]+$") or baseName
            for _,ext in ipairs({".rbxlx",".rbxl",".rbxm"}) do tryRead(stem..ext); if rawBytes>0 then break end end
        end
    end
    if rawBytes == 0 then
        pcall(function()
            local rf = listfiles("") or {}
            for i = #rf,1,-1 do
                local fp = rf[i]
                if fp:match("%.rbxl[x]?$") or fp:match("%.rbxm$") then tryRead(fp); if rawBytes>0 then break end end
            end
        end)
    end
    if rawBytes == 0 then
        local an = cleanName()
        for _,ext in ipairs({".rbxlx",".rbxl",".rbxm"}) do tryRead(an..ext); if rawBytes>0 then break end end
    end
    if rawBytes == 0 then
        task.wait(2.0); tryRead(baseName)
        if rawBytes == 0 then
            pcall(function()
                for _,fp in ipairs(listfiles("") or {}) do
                    if fp:match("%.rbxl[x]?$") or fp:match("%.rbxm$") then tryRead(fp); if rawBytes>0 then break end end
                end
            end)
        end
    end
    if rawBytes == 0 then addLog("⚠️ File not found after 6 passes!") end
    local dir = (CFG.SaveFolder ~= "" and CFG.SaveFolder) or DATA.."/saves"
    if CFG.AutoOrganize then dir = dir.."/PlaceID_"..tostring(game.PlaceId) end
    pcall(function() if not isfolder(dir) then makefolder(dir) end end)
    local justFileName = foundName:match("([^/\\]+)$") or foundName
    local finalPath = dir.."/"..justFileName
    if CFG.DupCheck and isfile(finalPath) then
        addLog("⚠️ Duplicate, skip.")
        return finalPath, rawBytes, rawContent, justFileName
    end
    if rawContent and rawBytes > 0 then
        pcall(function() writefile(finalPath, rawContent); pcall(function() delfile(foundName) end) end)
    end
    return finalPath, rawBytes, rawContent, justFileName
end

local timerRunning = false; local timerStart = 0
local function startTimer()
    timerStart=tick(); timerRunning=true
    task.spawn(function()
        while timerRunning do
            local e = tick()-timerStart
            task.wait(0.5)
        end
    end)
end

local function stopTimer()
    timerRunning=false
    return tick()-timerStart
end

doCopy = function(mode, trigger)
    if isCopying then
        Fluent:Notify({ Title="⚠️", Content="Masih memproses copy!", Duration=2 }); return
    end
    isCopying = true
    local decompile = (mode == "script") or (mode == "terrain_script")
    local saveTerrain = (mode == "terrain") or (mode == "terrain_script")
    local modeLabel
    if mode == "script" then modeLabel = "WITH Script"
    elseif mode == "terrain" then modeLabel = "WITH Terrain"
    elseif mode == "terrain_script" then modeLabel = "Terrain + Script"
    else modeLabel = "WITHOUT Script"
    end
    local trigLabel = trigger or "Manual"
    setStatus("⏳ "..modeLabel.."...")
    addLog("⏳ "..modeLabel.." ["..trigLabel.."]")
    startTimer()
    local instBefore = countInst()
    local speedClock = tick()
    Fluent:Notify({ Title="⏳ Copy Started", Content=modeLabel.." | Trigger: "..trigLabel, Duration=3 })
    task.spawn(function()
        local success=false; local filePath=""
        local sizeBytes=0; local savedContent=nil
        for attempt = 1, CFG.RetryAttempts do
            setStatus(string.format("⏳ [%d/%d] %s", attempt, CFG.RetryAttempts, modeLabel))
            addLog("Attempt "..attempt.."/"..CFG.RetryAttempts.."...")
            local ok, r1, r2, r3 = pcall(runUSSI, decompile, CFG.IgnorePlayers, saveTerrain)
            if ok then
                success=true; filePath=tostring(r1 or "")
                sizeBytes=tonumber(r2) or 0; savedContent=r3
                addLog("✅ Copy OK! "..sizeBytes.."b")
                break
            else
                addLog("❌ Attempt "..attempt..": "..tostring(r1):sub(1,55))
                logError("Attempt "..attempt, tostring(r1))
                task.wait(2)
            end
        end
        local elapsed = stopTimer()
        local durStr = fmtTime(elapsed)
        local speedStr = "~"..tostring(math.floor(instBefore/math.max(tick()-speedClock,0.1))).." inst/s"
        if success and sizeBytes == 0 and filePath ~= "" then
            pcall(function()
                if isfile(filePath) then
                    local c = readfile(filePath); if c and #c > 0 then sizeBytes=#c; savedContent=c end
                end
            end)
        end
        local sizeStr = sizeBytes > 0 and fmtBytes(sizeBytes) or "Unknown"
        local sizeMBStr = sizeBytes > 0 and fmtMB(sizeBytes) or "Unknown"
        local ns = addStat(success, success and sizeBytes or 0)
        if success then
            setStatus("✅ Done! "..sizeStr.." · "..durStr)
            addLog("✅ "..sizeStr.." · "..durStr.." · "..speedStr)
            playSound(1.4)
            Fluent:Notify({
                Title = "✅ Copy Berhasil!",
                Content = modeLabel.."\nSize: "..sizeStr.."\nDuration: "..durStr.."\nSpeed: "..speedStr,
                Duration = 8,
            })
            local uploadLink=nil; local uploadService=nil
            if CFG.AutoUpload then
                local fileContent = savedContent
                if not fileContent or #fileContent == 0 then
                    pcall(function()
                        if filePath ~= "" and isfile(filePath) then fileContent = readfile(filePath) end
                    end)
                end
                local gname = _realGameName or getRealGameName()
                local cleanGame = gname:gsub("[^%w%s%-%.%(%)%[%]]",""):gsub("%s+","_"):gsub("_+","_")
                if cleanGame:match("^_") then cleanGame = cleanGame:sub(2) end
                if cleanGame:match("_$") then cleanGame = cleanGame:sub(1,-2) end
                if cleanGame == "" then cleanGame = "Game_"..tostring(game.PlaceId) end
                cleanGame = cleanGame:sub(1,50)
                local ext2 = ({RBXL=".rbxl",RBXLX=".rbxlx",RBXM=".rbxm"})[CFG.OutputFormat] or ".rbxlx"
                local ds = ""; pcall(function() ds = "_"..os.date("%Y%m%d_%H%M%S") end)
                local fileName = cleanGame..ds..ext2
                if fileContent and #fileContent > 100 then
                    uploadLink, uploadService = doUploadSync(fileContent, fileName)
                    if uploadLink then playSound(1.5) end
                else
                    addLog("⚠️ Content empty, upload skipped")
                end
            end
            local savedInst = 0
            if LA_ACTIVE then pcall(function() savedInst = #_laGetFolder():GetChildren() end) end
            pushHistory({ gameName=getRealGameName(), placeId=tostring(game.PlaceId),
                mode=modeLabel, format=CFG.OutputFormat, date=safeDate(),
                duration=durStr, size=sizeStr, speed=speedStr, success=true, trigger=trigLabel,
                uploadLink=uploadLink, uploadService=uploadService })
            if CFG.WebhookEnabled then
                sendWebhook({ success=true, mode=modeLabel, size=sizeStr.." ("..sizeMBStr..")",
                    duration=durStr, speed=speedStr, date=safeDate(), trigger=trigLabel,
                    uploadLink=uploadLink, uploadService=uploadService,
                    instances=tostring(instBefore), savedInst=tostring(savedInst) })
            end
            if uploadLink then
                setStatus("✅ Done + Uploaded! ["..tostring(uploadService).."]")
            else
                setStatus("✅ Done! "..sizeStr.." · "..durStr)
            end
        else
            setStatus("❌ Failed! "..durStr)
            addLog("❌ Failed after "..CFG.RetryAttempts.." attempts")
            playSound(0.6)
            Fluent:Notify({ Title="❌ Copy Gagal", Content=durStr.." — lihat console untuk detail.", Duration=6 })
            pushHistory({ gameName=getRealGameName(), placeId=tostring(game.PlaceId),
                mode=modeLabel, format=CFG.OutputFormat, date=safeDate(),
                duration=durStr, size="N/A", speed=speedStr, success=false, trigger=trigLabel })
            if CFG.WebhookEnabled then
                sendWebhook({ success=false, mode=modeLabel, size="N/A",
                    duration=durStr, speed=speedStr, date=safeDate(), trigger=trigLabel,
                    instances=tostring(instBefore), savedInst="0" })
            end
        end
        task.wait(3); isCopying=false
    end)
end

pcall(function()
    LocalPlayer.Chatted:Connect(function(msg)
        if not CFG.ChatCommandEnabled then return end
        local lower = msg:lower():match("^%s*(.-)%s*$") or ""
        if lower == "/xinnz copy" then doCopy("noscript","Chat")
        elseif lower == "/xinnz script" then doCopy("script","Chat")
        elseif lower == "/xinnz terrain" then doCopy("terrain","Chat")
        elseif lower == "/xinnz ts" or lower == "/xinnz terrainscript" then doCopy("terrain_script","Chat")
        elseif lower == "/xinnz loadall" then
            if LA_ACTIVE then stopLoadAll() else startLoadAll() end
        elseif lower == "/xinnz status" then
            Fluent:Notify({ Title="📊 Status", Content=(isCopying and "⏳ Copying..." or "✅ Ready")..(LA_ACTIVE and "\n🌍 Load All: ON" or "\n🌍 Load All: OFF"), Duration=4 })
        elseif lower == "/xinnz help" then
            Fluent:Notify({ Title="💬 Commands", Content="copy|script|terrain|ts|loadall|status|help", Duration=5 })
        end
    end)
end)

task.spawn(function()
    local lastTrig = 0; local COOL = 300
    while true do
        task.wait(15)
        if CFG.PlayerTrigger then
            local count = #Players:GetPlayers()
            local thresh = math.max(CFG.PlayerTriggerCount or 3, 1)
            local now = tick()
            if count <= thresh and (now-lastTrig) >= COOL then
                lastTrig = now
                addLog("👥 Trigger! "..count.."p")
                Fluent:Notify({ Title="👥 Player Trigger", Content="Auto-copy! "..count.." player(s) online.", Duration=3 })
                doCopy(CFG.PlayerTriggerMode or "noscript", "Player Trigger ("..count.."p)")
            end
        end
    end
end)

local function startScheduler()
    if schedulerRunning then return end; schedulerRunning=true
    task.spawn(function()
        while schedulerRunning and CFG.BackupEnabled do
            task.wait(math.max((CFG.BackupInterval or 10),1)*60)
            if schedulerRunning and CFG.BackupEnabled then
                addLog("⏰ Auto-backup!")
                Fluent:Notify({ Title="⏰ Auto-Backup", Content="Memulai backup otomatis...", Duration=3 })
                doCopy("noscript","Backup Scheduler")
            end
        end
        schedulerRunning = false
    end)
end

local function processDiscordCommand()
    if not CFG.DiscordCmdEnabled then return end
    local cmdFile = CFG.DiscordCmdFile or DATA.."/discord_cmd.txt"
    local respFile = CFG.DiscordRespFile or DATA.."/discord_resp.txt"
    if not isfile(cmdFile) then return end
    local cmd = readfile(cmdFile):gsub("^%s*(.-)%s*$","")
    if cmd == "" then return end
    pcall(function() delfile(cmdFile) end)
    local function respond(msg)
        pcall(function() writefile(respFile, msg) end)
        addLog("🤖 Discord cmd '"..cmd.."' → "..msg:sub(1,50))
    end
    if cmd:lower() == "status" then
        local s = loadStats()
        respond(string.format("**Status**\n- Copy: %s\n- Load All: %s\n- Success: %d\n- Fail: %d\n- Size: %s",
            isCopying and "⏳ Copying" or "✅ Idle",
            LA_ACTIVE and "🟢 ON" or "🔴 OFF",
            s.success or 0, s.fail or 0, fmtBytes(s.totalBytes or 0)))
    elseif cmd:lower():match("^copy") then
        local mode = cmd:match("copy%s+(%w+)") or "noscript"
        local valid = {noscript=true,script=true,terrain=true,terrain_script=true}
        if not valid[mode] then respond("❌ Mode tidak dikenal.")
        elseif isCopying then respond("⚠️ Sedang busy.")
        else
            respond("⏳ Memulai copy "..mode.."...")
            task.spawn(function() doCopy(mode,"Discord Command") end)
        end
    elseif cmd:lower() == "list_files" then
        local dir = (CFG.SaveFolder ~= "" and CFG.SaveFolder) or DATA.."/saves"
        if CFG.AutoOrganize then dir = dir.."/PlaceID_"..tostring(game.PlaceId) end
        local files = {}
        pcall(function() if isfolder(dir) then for _,fp in ipairs(listfiles(dir) or {}) do table.insert(files, fp:match("([^/\\]+)$") or fp) end end end)
        respond(#files == 0 and "📭 Kosong." or "📁 Files:\n"..table.concat(files,"\n"):sub(1,400))
    elseif cmd:lower() == "help" then
        respond("Perintah: status | copy [mode] | list_files | help")
    else
        respond("❌ Perintah tidak dikenal. Coba 'help'.")
    end
end

task.spawn(function()
    while true do task.wait(10); pcall(processDiscordCommand) end
end)

Window:SelectTab(1)
refreshInfoTab()

Fluent:Notify({
    Title = "✅ Xinnz v1.2 Loaded",
    Content = "Game: "..getRealGameName().."\nFormat: "..CFG.OutputFormat.."\nUpload: "..(CFG.AutoUpload and CFG.UploadService or "OFF"),
    Duration = 6,
})

if CFG.BackupEnabled then startScheduler() end

SaveManager:LoadAutoloadConfig()

print("========================================")
print("[Xinnz] ✅ Xinnz v1.2 Fluent LOADED!")
print("[Xinnz]    Game  : "..getRealGameName())
print("[Xinnz]    Format: "..CFG.OutputFormat)
print("[Xinnz]    Upload: "..tostring(CFG.AutoUpload).." ["..CFG.UploadService.."]")
print("[Xinnz]    Webhook: "..tostring(CFG.WebhookEnabled))
print("[Xinnz]    Discord Cmd: "..tostring(CFG.DiscordCmdEnabled))
print("========================================")
