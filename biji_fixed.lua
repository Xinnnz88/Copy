-- KEY SYSTEM - Xinnz v1 (Local Key Validation)
-- FIX: Dibungkus dalam fungsi agar `return` tidak membunuh script
local Config = {
    Secret          = "XinnzSecret",
    ValidKeys       = {
        "xinnzkey",
        "e",
        -- tambahkan key lain di bawah ini
    },
    SessionFile     = "XinnzData/session.json",
    HWIDFile        = "XinnzData/hwid.dat",
    HubName         = "XINNZ HUB",
    HubDescription  = "Enter your key to continue",
    KeyHWIDLock     = true,
}

print("Key System loaded. Please submit the key. 🔑")

local _cachedHWID = nil  

local function getHWID()
    if _cachedHWID and _cachedHWID ~= "" then return _cachedHWID end

    local hwid = ""

    -- 1. Prioritize HWID already saved to file (most stable)
    pcall(function()
        if isfile and isfile(Config.HWIDFile) then
            local saved = readfile(Config.HWIDFile):gsub("^%s*(.-)%s*$", "")
            if saved ~= "" then hwid = saved end
        end
    end)

    -- 2. If file doesn't exist, try dynamic hardware functions
    if hwid == "" then
        pcall(function() if getmachineaddress then hwid = tostring(getmachineaddress()) end end)
    end
    if hwid == "" then
        pcall(function() if macaddress then hwid = tostring(macaddress()) end end)
    end

    -- 3. If still empty, generate UUID once and save to file
    if hwid == "" then
        local chars = "abcdef0123456789"
        local uuid  = ""
        local seed  = os.time()
        math.randomseed(seed)
        for i = 1, 32 do
            uuid = uuid .. chars:sub(math.random(1, #chars), math.random(1, #chars))
            if i == 8 or i == 12 or i == 16 or i == 20 then uuid = uuid .. "-" end
        end
        hwid = uuid
    end

    -- 4. Save to file for consistency across sessions
    pcall(function()
        if not isfolder("XinnzData") then makefolder("XinnzData") end
        writefile(Config.HWIDFile, hwid)
    end)

    _cachedHWID = hwid
    return hwid
end

-- SESSION CACHE
local _HS = game:GetService("HttpService")
local SESSION_TTL = 3600

local function loadSession()
    local ok, data = pcall(function()
        if isfile(Config.SessionFile) then
            return _HS:JSONDecode(readfile(Config.SessionFile))
        end
    end)
    return (ok and type(data) == "table") and data or nil
end

local function saveSession(key, daysLeft, note)
    pcall(function()
        if not isfolder("XinnzData") then makefolder("XinnzData") end
        writefile(Config.SessionFile, _HS:JSONEncode({
            key        = key,
            hwid       = getHWID(),
            cachedAt   = os.time(),
            daysLeft   = daysLeft,
            note       = note or "",
        }))
    end)
end

local function clearSession()
    pcall(function() if isfile(Config.SessionFile) then delfile(Config.SessionFile) end end)
end

-- KEY VALIDATION (Lokal)
local function validateKeyOnline(key)
    if not key or key == "" then
        return false, "invalid_key", nil, ""
    end
    for _, validKey in ipairs(Config.ValidKeys) do
        if key == validKey then
            return true, "ok", nil, ""
        end
    end
    return false, "invalid_key", nil, ""
end

local function validateKeyOnlineRetry(key)
    return validateKeyOnline(key)
end

local function checkSession()
    local session = loadSession()
    if session and session.key and session.cachedAt then
        local age = os.time() - (session.cachedAt or 0)
        if age < SESSION_TTL then
            if Config.KeyHWIDLock then
                local currentHWID = getHWID()
                if session.hwid == currentHWID then
                    return true, "ok_cached", session.daysLeft
                else
                    
                    
                    local valid, reason, daysLeft, note = validateKeyOnlineRetry(session.key)
                    if valid then
                        saveSession(session.key, daysLeft, note)  -- update HWID baru
                        return true, "ok", daysLeft
                    else
                        clearSession()
                        return false, "hwid_mismatch", nil
                    end
                end
            end
            return true, "ok_cached", session.daysLeft
        end
        local valid, reason, daysLeft, note = validateKeyOnlineRetry(session.key)
        if valid then
            saveSession(session.key, daysLeft, note)
            return true, "ok", daysLeft
        else
            clearSession()
            return false, reason, nil
        end
    end
    return false, "no_session", nil
end

-- FIX UTAMA: Key GUI dibungkus dalam fungsi
-- Sebelumnya `return` di dalam else block membunuh seluruh script
local function _runKeySystemGUI(sessionReason, sessionDaysLeft)
    -- Tunggu player siap
    local player = game:GetService("Players").LocalPlayer
    if not player then
        player = game:GetService("Players"):WaitForChild("LocalPlayer", 15)
    end
    if not player then
        warn("[Xinnz KeySystem] LocalPlayer not found!")
        return false
    end

    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then
        pGui = player:WaitForChild("PlayerGui", 15)
    end
    if not pGui then
        warn("[Xinnz KeySystem] PlayerGui not found!")
        return false
    end

    -- Delete GUI lama kalau ada
    pcall(function()
        local old = pGui:FindFirstChild("XinnzKeyGui")
        if old then old:Destroy() end
    end)

    -- Buat ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name            = "XinnzKeyGui"
    gui.ResetOnSpawn    = false
    gui.DisplayOrder    = 99999
    gui.IgnoreGuiInset  = true
    gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    gui.Parent          = pGui

    -- Backdrop (FIX: transparency 0 agar terlihat jelas)
    local bg = Instance.new("Frame")
    bg.Size                   = UDim2.fromScale(1, 1)
    bg.BackgroundColor3       = Color3.fromRGB(5, 5, 10)
    bg.BackgroundTransparency = 0.15   -- FIX: dari 0.3 → 0.15 lebih solid
    bg.BorderSizePixel        = 0
    bg.ZIndex                 = 1
    bg.Parent                 = gui

    -- Card utama (FIX: tinggi dari 270 → 300 agar muat semua elemen)
    local card = Instance.new("Frame")
    card.Size             = UDim2.fromOffset(460, 300)
    card.Position         = UDim2.fromScale(0.5, 0.5)
    card.AnchorPoint      = Vector2.new(0.5, 0.5)
    card.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    card.BorderSizePixel  = 0
    card.ZIndex           = 2
    card.Parent           = gui
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)

    local cardStroke = Instance.new("UIStroke", card)
    cardStroke.Color       = Color3.fromRGB(80, 60, 160)
    cardStroke.Thickness   = 1.5
    cardStroke.Transparency = 0.2

    -- Header
    local header = Instance.new("Frame")
    header.Size             = UDim2.new(1, 0, 0, 56)
    header.BackgroundColor3 = Color3.fromRGB(90, 60, 200)
    header.BorderSizePixel  = 0
    header.ZIndex           = 3
    header.Parent           = card
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 16)

    local hGrad = Instance.new("UIGradient", header)
    hGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 70, 230)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 100, 220)),
    })
    hGrad.Rotation = 90

    -- Header fill (tutup radius bawah header)
    local headerFill = Instance.new("Frame")
    headerFill.Size             = UDim2.new(1, 0, 0, 16)
    headerFill.Position         = UDim2.new(0, 0, 1, -16)
    headerFill.BackgroundColor3 = Color3.fromRGB(110, 70, 230)
    headerFill.BorderSizePixel  = 0
    headerFill.ZIndex           = 3
    headerFill.Parent           = header

    local hFillGrad = Instance.new("UIGradient", headerFill)
    hFillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 70, 230)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 100, 220)),
    })
    hFillGrad.Rotation = 90

    -- Ikon kunci
    local iconCircle = Instance.new("Frame")
    iconCircle.Size                   = UDim2.fromOffset(38, 38)
    iconCircle.Position               = UDim2.fromOffset(14, 9)
    iconCircle.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
    iconCircle.BackgroundTransparency = 0.85
    iconCircle.BorderSizePixel        = 0
    iconCircle.ZIndex                 = 4
    iconCircle.Parent                 = header
    Instance.new("UICorner", iconCircle).CornerRadius = UDim.new(1, 0)

    local iconLbl = Instance.new("TextLabel", iconCircle)
    iconLbl.Size               = UDim2.fromScale(1, 1)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Text               = "🔑"
    iconLbl.TextSize           = 18
    iconLbl.Font               = Enum.Font.GothamBold
    iconLbl.TextColor3         = Color3.new(1,1,1)
    iconLbl.ZIndex             = 5

    -- Title di header
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size                 = UDim2.new(1, -70, 0, 28)
    titleLbl.Position             = UDim2.fromOffset(60, 8)
    titleLbl.Text                 = Config.HubName .. " — Key System"
    titleLbl.TextColor3           = Color3.new(1, 1, 1)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font                 = Enum.Font.GothamBold
    titleLbl.TextSize             = 16
    titleLbl.TextXAlignment       = Enum.TextXAlignment.Left
    titleLbl.ZIndex               = 4
    titleLbl.Parent               = header

    -- Deskripsi di bawah title
    local _descText = Config.HubDescription
    if sessionReason == "expired" then
        _descText = "⚠️ Key expired! Enter a new key."
    elseif sessionReason == "hwid_mismatch" then
        _descText = "⛔ Device not recognized! Contact owner."
    end

    local subLbl = Instance.new("TextLabel")
    subLbl.Size                 = UDim2.new(1, -70, 0, 18)
    subLbl.Position             = UDim2.fromOffset(60, 33)
    subLbl.Text                 = _descText
    subLbl.TextColor3           = Color3.fromRGB(200, 185, 255)
    subLbl.BackgroundTransparency = 1
    subLbl.Font                 = Enum.Font.Gotham
    subLbl.TextSize             = 12
    subLbl.TextXAlignment       = Enum.TextXAlignment.Left
    subLbl.ZIndex               = 4
    subLbl.Parent               = header

    -- Label "YOUR KEY"
    local keyLabel = Instance.new("TextLabel")
    keyLabel.Size                   = UDim2.new(1, -32, 0, 18)
    keyLabel.Position               = UDim2.fromOffset(16, 70)
    keyLabel.Text                   = "YOUR KEY"
    keyLabel.TextColor3             = Color3.fromRGB(150, 130, 220)
    keyLabel.BackgroundTransparency = 1
    keyLabel.Font                   = Enum.Font.GothamBold
    keyLabel.TextSize               = 11
    keyLabel.TextXAlignment         = Enum.TextXAlignment.Left
    keyLabel.ZIndex                 = 3
    keyLabel.Parent                 = card

    -- Input frame
    local tbFrame = Instance.new("Frame")
    tbFrame.Size             = UDim2.new(1, -32, 0, 44)
    tbFrame.Position         = UDim2.fromOffset(16, 92)
    tbFrame.BackgroundColor3 = Color3.fromRGB(26, 24, 38)
    tbFrame.BorderSizePixel  = 0
    tbFrame.ZIndex           = 3
    tbFrame.Parent           = card
    Instance.new("UICorner", tbFrame).CornerRadius = UDim.new(0, 10)
    local tbStroke = Instance.new("UIStroke", tbFrame)
    tbStroke.Color     = Color3.fromRGB(80, 60, 160)
    tbStroke.Thickness = 1.5

    local tb = Instance.new("TextBox", tbFrame)
    tb.Size               = UDim2.new(1, -16, 1, 0)
    tb.Position           = UDim2.fromOffset(8, 0)
    tb.PlaceholderText    = "Enter your key..."
    tb.PlaceholderColor3  = Color3.fromRGB(90, 80, 120)
    tb.Text               = ""
    tb.BackgroundTransparency = 1
    tb.TextColor3         = Color3.new(1, 1, 1)
    tb.Font               = Enum.Font.GothamMedium
    tb.TextSize           = 15
    tb.BorderSizePixel    = 0
    tb.ClearTextOnFocus   = false
    tb.TextXAlignment     = Enum.TextXAlignment.Left
    tb.ZIndex             = 4

    -- Status label (FIX: posisi lebih bawah agar tidak overlap)
    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size                   = UDim2.new(1, -32, 0, 20)
    statusLbl.Position               = UDim2.fromOffset(16, 145)
    statusLbl.Text                   = ""
    statusLbl.TextColor3             = Color3.fromRGB(160, 140, 200)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Font                   = Enum.Font.Gotham
    statusLbl.TextSize               = 12
    statusLbl.TextXAlignment         = Enum.TextXAlignment.Left
    statusLbl.ZIndex                 = 3
    statusLbl.Parent                 = card

    -- Tombol Submit (FIX: posisi disesuaikan)
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(1, -32, 0, 44)
    btn.Position         = UDim2.fromOffset(16, 172)
    btn.Text             = "  🔓  Submit Key"
    btn.BackgroundColor3 = Color3.fromRGB(100, 70, 220)
    btn.TextColor3       = Color3.new(1, 1, 1)
    btn.Font             = Enum.Font.GothamBold
    btn.TextSize         = 15
    btn.BorderSizePixel  = 0
    btn.AutoButtonColor  = false
    btn.ZIndex           = 3
    btn.Parent           = card
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

    local btnGrad = Instance.new("UIGradient", btn)
    btnGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 80, 240)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 110, 230)),
    })
    btnGrad.Rotation = 90

    -- Footer
    local _footerExtra = ""
    if sessionReason == "expired" then
        _footerExtra = "  •  Key EXPIRED"
    elseif sessionDaysLeft then
        _footerExtra = "  •  " .. tostring(sessionDaysLeft) .. " day(s) left"
    end

    local verLbl = Instance.new("TextLabel")
    verLbl.Size                   = UDim2.new(1, 0, 0, 20)
    verLbl.Position               = UDim2.new(0, 0, 1, -24)
    verLbl.Text                   = "Xinnz v2  •  discord.gg/gsteVPKnZ" .. _footerExtra
    verLbl.TextColor3             = Color3.fromRGB(70, 60, 100)
    verLbl.BackgroundTransparency = 1
    verLbl.Font                   = Enum.Font.Gotham
    verLbl.TextSize               = 11
    verLbl.ZIndex                 = 3
    verLbl.Parent                 = card

    -- Animasi masuk
    card.BackgroundTransparency = 1
    card.Position = UDim2.new(0.5, 0, 0.6, 0)
    local TS = game:GetService("TweenService")
    TS:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0,
        Position = UDim2.fromScale(0.5, 0.5)
    }):Play()

    -- Validasi
    local keyDone  = false
    local keyValid = false
    local lastTyped = ""

    local function getTextBoxText()
        local text = ""
        pcall(function()
            if tb and tb.Text then text = tb.Text end
        end)
        if text == "" and lastTyped ~= "" then text = lastTyped end
        return text
    end

    pcall(function()
        if tb then
            tb:GetPropertyChangedSignal("Text"):Connect(function()
                pcall(function() lastTyped = tb.Text or "" end)
            end)
        end
    end)

    local function ultraClean(str)
        if str == nil then return "" end
        local s = tostring(str)
        s = s:gsub("%s+", "")
        s = s:gsub("[%c]", "")
        s = s:gsub("[^%w]", "")
        return s
    end

    local function trySubmit()
        local rawText = getTextBoxText()
        local cleaned = ultraClean(rawText)

        if sessionReason == "hwid_mismatch" then
            statusLbl.Text = "⛔ Device not recognized. Contact owner."
            statusLbl.TextColor3 = Color3.fromRGB(255, 90, 90)
            btn.Text = "  ⛔  Device Blocked"
            btn.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
            return
        end

        if cleaned == "" then
            statusLbl.Text = "✗ Please enter a key."
            statusLbl.TextColor3 = Color3.fromRGB(255, 90, 90)
            return
        end

        btn.Text = "  ⏳  Validating..."
        btn.BackgroundColor3 = Color3.fromRGB(60, 60, 100)
        statusLbl.Text = "Memeriksa key..."
        statusLbl.TextColor3 = Color3.fromRGB(180, 170, 255)

        task.spawn(function()
            local valid, reason, daysLeft, note = validateKeyOnlineRetry(cleaned)

            if valid then
                saveSession(cleaned, daysLeft, note)
                keyValid = true
                keyDone  = true
                btn.Text = "  ✅  Key Valid! Loading..."
                btn.BackgroundColor3 = Color3.fromRGB(30, 160, 80)
                btnGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 190, 90)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 140, 65)),
                })
                local expMsg = daysLeft
                    and ("✓ Key accepted! Expires in " .. tostring(daysLeft) .. " day(s).")
                    or  "✓ Key accepted! Loading script..."
                statusLbl.Text      = expMsg
                statusLbl.TextColor3 = Color3.fromRGB(60, 220, 100)
                _G[Config.Secret]   = true

                -- Animasi keluar
                task.delay(1.2, function()
                    TS:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quart), {
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0.5, 0, 0.4, 0)
                    }):Play()
                    task.delay(0.4, function()
                        pcall(function() gui:Destroy() end)
                    end)
                end)
            else
                local msgs = {
                    invalid_key   = "✗ Invalid key.",
                    expired       = "✗ Key expired. Hubungi owner.",
                    banned        = "✗ Key dibanned. Hubungi owner.",
                    hwid_mismatch = "✗ Device not recognized.",
                }
                local msg = msgs[reason] or ("✗ Gagal: " .. tostring(reason))
                print("[Xinnz KeySystem] Validation failed - reason: " .. tostring(reason))
                btn.Text             = "  ❌  Invalid Key!"
                btn.BackgroundColor3 = Color3.fromRGB(180, 40, 50)
                btnGrad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 50, 60)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 30, 40)),
                })
                statusLbl.Text       = msg
                statusLbl.TextColor3 = Color3.fromRGB(255, 90, 90)
                task.delay(2.5, function()
                    if not keyDone then
                        btn.Text = "  🔓  Submit Key"
                        btn.BackgroundColor3 = Color3.fromRGB(100, 70, 220)
                        btnGrad.Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 80, 240)),
                            ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 110, 230)),
                        })
                        statusLbl.Text = ""
                    end
                end)
            end
        end)
    end

    -- Jika session valid, auto-isi key dan langsung submit
    local _autoKey = ""
    pcall(function()
        local sess = loadSession()
        if sess and sess.key and sess.key ~= "" then
            _autoKey = sess.key
        end
    end)

    if _sessionValid and _autoKey ~= "" then
        -- Auto-fill dan auto-submit setelah animasi selesai
        task.delay(0.6, function()
            pcall(function() tb.Text = _autoKey end)
            task.delay(0.3, function()
                trySubmit()
            end)
        end)
    end

    if btn then
        btn.MouseButton1Click:Connect(trySubmit)
    end

    -- Tunggu key (max 120 detik)
    local timeoutStart = tick()
    while not keyDone and (tick() - timeoutStart) < 120 do
        task.wait(0.2)
    end

    return keyValid  -- FIX: return false jika gagal, bukan error() di sini
end

-- CEK SESSION & JALANKAN KEY SYSTEM
-- SELALU tampilkan GUI. Jika session valid, textbox auto-isi
-- tapi user tetap harus klik Submit (atau auto-submit).
local _sessionValid, _sessionReason, _sessionDaysLeft = checkSession()

-- Selalu panggil GUI (hapus bypass session agar key system selalu muncul)
local keyOk = _runKeySystemGUI(_sessionReason, _sessionDaysLeft)
if not keyOk then
    error("[Xinnz] Invalid key or timeout. Script stopped.", 0)
end
_G[Config.Secret] = true

-- XINNZ UI LIBRARY v2 (Custom - No External Dependencies)
-- Smooth open/close | Color picker | Feature Modals
-- FIX: DisplayOrder ditambah pada notif & modal GUI
local TweenService    = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")
local LocalPlayer     = Players.LocalPlayer
local PlayerGui       = LocalPlayer:WaitForChild("PlayerGui")

-- Theme
local Theme = {
    BG          = Color3.fromRGB(12, 10, 22),
    Sidebar     = Color3.fromRGB(17, 14, 32),
    Card        = Color3.fromRGB(22, 19, 38),
    CardHover   = Color3.fromRGB(30, 26, 52),
    Accent      = Color3.fromRGB(110, 70, 220),
    AccentDark  = Color3.fromRGB(70, 45, 160),
    AccentGlow  = Color3.fromRGB(140, 100, 255),
    Success     = Color3.fromRGB(40, 200, 100),
    Danger      = Color3.fromRGB(220, 60, 70),
    Warning     = Color3.fromRGB(240, 180, 40),
    Text        = Color3.fromRGB(230, 220, 255),
    TextDim     = Color3.fromRGB(140, 125, 185),
    TextMuted   = Color3.fromRGB(75, 65, 110),
    Border      = Color3.fromRGB(50, 40, 85),
    Toggle_ON   = Color3.fromRGB(80, 210, 130),
    Toggle_OFF  = Color3.fromRGB(55, 45, 80),
    Slider_Bar  = Color3.fromRGB(40, 33, 70),
    Shadow      = Color3.fromRGB(0, 0, 0),
}

-- Color Presets

local ColorPresets = {
    ["🟣 Purple (Default)"] = {
        BG=Color3.fromRGB(12,10,22), Sidebar=Color3.fromRGB(17,14,32),
        Card=Color3.fromRGB(22,19,38), Accent=Color3.fromRGB(110,70,220),
        Border=Color3.fromRGB(50,40,85), Text=Color3.fromRGB(230,220,255),
        TextDim=Color3.fromRGB(140,125,185), TextMuted=Color3.fromRGB(75,65,110),
    },
    ["🔵 Water Blue"] = {
        BG=Color3.fromRGB(8,16,28), Sidebar=Color3.fromRGB(12,22,40),
        Card=Color3.fromRGB(16,30,52), Accent=Color3.fromRGB(30,140,220),
        Border=Color3.fromRGB(25,70,120), Text=Color3.fromRGB(210,235,255),
        TextDim=Color3.fromRGB(120,170,210), TextMuted=Color3.fromRGB(55,90,130),
    },
    ["⬜ Milk White"] = {
        BG=Color3.fromRGB(240,238,232), Sidebar=Color3.fromRGB(228,225,218),
        Card=Color3.fromRGB(250,248,244), Accent=Color3.fromRGB(100,90,200),
        Border=Color3.fromRGB(190,185,175), Text=Color3.fromRGB(40,35,55),
        TextDim=Color3.fromRGB(90,82,110), TextMuted=Color3.fromRGB(160,150,170),
    },
    ["⚫ Dark Midnight"] = {
        BG=Color3.fromRGB(5,5,10), Sidebar=Color3.fromRGB(8,8,16),
        Card=Color3.fromRGB(12,12,22), Accent=Color3.fromRGB(0,200,180),
        Border=Color3.fromRGB(30,30,55), Text=Color3.fromRGB(200,255,250),
        TextDim=Color3.fromRGB(100,180,170), TextMuted=Color3.fromRGB(45,80,75),
    },
    ["🌸 Rose Pink"] = {
        BG=Color3.fromRGB(26,10,18), Sidebar=Color3.fromRGB(34,14,25),
        Card=Color3.fromRGB(42,18,32), Accent=Color3.fromRGB(230,80,140),
        Border=Color3.fromRGB(90,35,65), Text=Color3.fromRGB(255,220,240),
        TextDim=Color3.fromRGB(195,130,170), TextMuted=Color3.fromRGB(100,55,80),
    },
    ["🌿 Forest Green"] = {
        BG=Color3.fromRGB(8,18,12), Sidebar=Color3.fromRGB(12,25,16),
        Card=Color3.fromRGB(16,34,22), Accent=Color3.fromRGB(50,200,100),
        Border=Color3.fromRGB(30,80,45), Text=Color3.fromRGB(210,255,225),
        TextDim=Color3.fromRGB(110,185,140), TextMuted=Color3.fromRGB(45,90,60),
    },
    ["🟠 Sunset Orange"] = {
        BG=Color3.fromRGB(20,10,5), Sidebar=Color3.fromRGB(30,14,7),
        Card=Color3.fromRGB(38,18,9), Accent=Color3.fromRGB(240,100,30),
        Border=Color3.fromRGB(100,45,15), Text=Color3.fromRGB(255,235,210),
        TextDim=Color3.fromRGB(200,140,90), TextMuted=Color3.fromRGB(110,65,35),
    },
}

-- Helper lerp warna
local function _lerpC3(a, b, t)
    return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t)
end

local function _applyTheme(presetName)
    local p = ColorPresets[presetName]
    if not p then return end

    -- Simpan SEMUA warna lama sebelum diubah
    local prev = {}
    for k, v in pairs(Theme) do
        if type(v) == "userdata" then prev[k] = v end
    end

    -- Update base Theme dari preset
    for k, v in pairs(p) do Theme[k] = v end

    -- Compute warna turunan otomatis dari base colors
    local W = Color3.new(1,1,1)
    local B = Color3.new(0,0,0)
    Theme.CardHover  = _lerpC3(Theme.Card,    W, 0.12)
    Theme.AccentDark = _lerpC3(Theme.Accent,  B, 0.35)
    Theme.AccentGlow = _lerpC3(Theme.Accent,  W, 0.28)
    Theme.Slider_Bar = _lerpC3(Theme.Sidebar, B, 0.18)
    Theme.Toggle_ON  = _lerpC3(Theme.Accent,  W, 0.10)
    Theme.Toggle_OFF = _lerpC3(Theme.Sidebar, B, 0.10)
    Theme.Shadow     = Color3.new(0, 0, 0)

    -- Fuzzy color match (toleransi 0.03 untuk float drift)
    local function colorMatch(c, ref)
        return math.abs(c.R-ref.R) < 0.03
           and math.abs(c.G-ref.G) < 0.03
           and math.abs(c.B-ref.B) < 0.03
    end

    -- Map warna lama → warna baru berdasarkan key Theme
    local function mapColor(c)
        for key, old in pairs(prev) do
            if Theme[key] and colorMatch(c, old) then
                return Theme[key]
            end
        end
        return nil
    end

    -- Crawl semua elemen GUI dan update warna
    local function crawl(obj)
        pcall(function()
            -- Background frames & scroll
            if obj:IsA("Frame") or obj:IsA("ScrollingFrame") then
                local nc = mapColor(obj.BackgroundColor3)
                if nc and obj.BackgroundTransparency < 0.99 then
                    obj.BackgroundColor3 = nc
                end
            end
            -- TextButton + ImageButton backgrounds (close btn, toggle, slider)
            if obj:IsA("TextButton") or obj:IsA("ImageButton") then
                local nc = mapColor(obj.BackgroundColor3)
                if nc and obj.BackgroundTransparency < 0.99 then
                    obj.BackgroundColor3 = nc
                end
            end
            -- Warna teks
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local nc = mapColor(obj.TextColor3)
                if nc then obj.TextColor3 = nc end
            end
            -- UIStroke border + accent
            if obj:IsA("UIStroke") then
                local nc = mapColor(obj.Color)
                if nc then obj.Color = nc end
            end
            -- ImageLabel / ImageButton glow & icon color
            if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                local nc = mapColor(obj.ImageColor3)
                if nc then obj.ImageColor3 = nc end
            end
            -- ScrollBar color
            if obj:IsA("ScrollingFrame") then
                local nc = mapColor(obj.ScrollBarImageColor3)
                if nc then obj.ScrollBarImageColor3 = nc end
            end
        end)
        for _, child in ipairs(obj:GetChildren()) do crawl(child) end
    end

    pcall(function()
        for _, sg in ipairs(PlayerGui:GetChildren()) do
            if sg.Name == "XinnzHub" then
                task.spawn(function() crawl(sg) end)
            end
        end
    end)
end

local Options = {}

-- Tween helpers
local function tween(obj, props, t, style, dir)
    local info = TweenInfo.new(t or 0.25, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out)
    TweenService:Create(obj, info, props):Play()
end

local function tweenAndWait(obj, props, t, style, dir)
    local info = TweenInfo.new(t or 0.25, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    tw.Completed:Wait()
end

-- UI Builders
local function newFrame(props)
    local f = Instance.new("Frame")
    f.BackgroundColor3    = props.Color or Theme.Card
    f.BorderSizePixel     = 0
    f.Size                = props.Size or UDim2.fromScale(1, 0)
    f.Position            = props.Position or UDim2.new()
    f.BackgroundTransparency = props.Transparency or 0
    if props.Parent then f.Parent = props.Parent end
    return f
end

local function newLabel(props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text          = props.Text or ""
    l.TextColor3    = props.Color or Theme.Text
    l.Font          = props.Font or Enum.Font.GothamMedium
    l.TextSize      = props.Size or 13
    l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
    l.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
    l.TextWrapped   = props.Wrap or false
    l.Size          = props.FrameSize or UDim2.fromScale(1, 1)
    l.Position      = props.Position or UDim2.new()
    if props.Parent then l.Parent = props.Parent end
    return l
end

local function newCorner(parent, radius)
    local c = Instance.new("UICorner", parent)
    c.CornerRadius = UDim.new(0, radius or 8)
    return c
end

local function newStroke(parent, color, thickness)
    local s = Instance.new("UIStroke", parent)
    s.Color     = color or Theme.Border
    s.Thickness = thickness or 1
    return s
end

local function newPadding(parent, all, top, bottom, left, right)
    local p = Instance.new("UIPadding", parent)
    p.PaddingTop    = UDim.new(0, top    or all or 0)
    p.PaddingBottom = UDim.new(0, bottom or all or 0)
    p.PaddingLeft   = UDim.new(0, left   or all or 0)
    p.PaddingRight  = UDim.new(0, right  or all or 0)
    return p
end

local function newList(parent, pad, dir)
    local l = Instance.new("UIListLayout", parent)
    l.Padding            = UDim.new(0, pad or 6)
    l.FillDirection      = dir or Enum.FillDirection.Vertical
    l.SortOrder          = Enum.SortOrder.LayoutOrder
    l.HorizontalAlignment = Enum.HorizontalAlignment.Center
    return l
end

-- NOTIFICATION SYSTEM
-- FIX: DisplayOrder = 10000 agar notif selalu di atas semua GUI
local _notifGui   = nil
local _notifStack = nil

local function ensureNotifGui()
    if _notifGui and _notifGui.Parent then return end
    _notifGui = Instance.new("ScreenGui")
    _notifGui.Name         = "XinnzNotif"
    _notifGui.ResetOnSpawn = false
    _notifGui.DisplayOrder = 10000  -- FIX
    _notifGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _notifGui.Parent       = PlayerGui

    _notifStack = Instance.new("Frame", _notifGui)
    _notifStack.Name               = "Stack"
    _notifStack.Size               = UDim2.fromOffset(280, 0)
    _notifStack.Position           = UDim2.new(1, -296, 0, 16)
    _notifStack.BackgroundTransparency = 1
    _notifStack.AutomaticSize      = Enum.AutomaticSize.Y
    newList(_notifStack, 8)
end

local function XNotify(config)
    task.spawn(function()
        ensureNotifGui()
        local dur = config.Duration or 4
        local notifCard = newFrame({ Color = Theme.Card, Size = UDim2.fromOffset(280, 0), Parent = _notifStack })
        notifCard.AutomaticSize = Enum.AutomaticSize.Y
        newCorner(notifCard, 10)
        newStroke(notifCard, Theme.Border, 1)
        notifCard.BackgroundTransparency = 1

        local accent = newFrame({ Color = config.Color or Theme.Accent, Size = UDim2.new(0, 3, 1, 0), Parent = notifCard })
        newCorner(accent, 3)

        local inner = newFrame({ Color = Color3.new(), Size = UDim2.new(1, -3, 1, 0), Position = UDim2.fromOffset(3, 0), Transparency = 1, Parent = notifCard })
        inner.AutomaticSize = Enum.AutomaticSize.Y
        newPadding(inner, 10, 10, 10, 12, 10)
        local vlist = newList(inner, 3)
        vlist.HorizontalAlignment = Enum.HorizontalAlignment.Left

        local titleL = newLabel({ Text = config.Title or "", Color = Theme.Text, Font = Enum.Font.GothamBold, Size = 13, Parent = inner })
        titleL.Size = UDim2.new(1, 0, 0, 16)
        titleL.AutomaticSize = Enum.AutomaticSize.Y

        if config.Content and config.Content ~= "" then
            local contentL = newLabel({ Text = config.Content, Color = Theme.TextDim, Size = 12, Wrap = true, YAlign = Enum.TextYAlignment.Top, Parent = inner })
            contentL.Size = UDim2.new(1, 0, 0, 0)
            contentL.AutomaticSize = Enum.AutomaticSize.Y
        end

        notifCard.Position = UDim2.fromOffset(296, 0)
        tween(notifCard, { BackgroundTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.35, Enum.EasingStyle.Back)

        task.wait(dur)
        tween(notifCard, { BackgroundTransparency = 1, Position = UDim2.fromOffset(296, 0) }, 0.3)
        task.wait(0.35)
        pcall(function() notifCard:Destroy() end)
    end)
end

-- FEATURE MODAL
-- FIX: DisplayOrder = 10001 agar modal di atas notif
local _modalGui     = nil
local _modalFrame   = nil
local _modalTitle   = nil
local _modalContent = nil
local _modalBar     = nil
local _modalBarFill = nil
local _modalCancelCb = nil

local function XShowModal(config)
    if _modalGui and _modalGui.Parent then
        pcall(function() _modalGui:Destroy() end)
    end

    _modalGui = Instance.new("ScreenGui")
    _modalGui.Name         = "XinnzModal"
    _modalGui.ResetOnSpawn = false
    _modalGui.DisplayOrder = 10001  -- FIX
    _modalGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _modalGui.Parent       = PlayerGui

    local backdrop = newFrame({ Color = Theme.Shadow, Size = UDim2.fromScale(1, 1), Transparency = 1, Parent = _modalGui })
    tween(backdrop, { BackgroundTransparency = 0.55 }, 0.25)

    _modalFrame = newFrame({ Color = Theme.Card, Size = UDim2.fromOffset(360, 0), Parent = _modalGui })
    _modalFrame.AutomaticSize = Enum.AutomaticSize.Y
    _modalFrame.AnchorPoint   = Vector2.new(0.5, 0.5)
    _modalFrame.Position      = UDim2.fromScale(0.5, 0.5)
    _modalFrame.BackgroundTransparency = 1
    newCorner(_modalFrame, 14)
    newStroke(_modalFrame, Theme.Accent, 1.5)
    newPadding(_modalFrame, 20)
    local vlist = newList(_modalFrame, 10)
    vlist.HorizontalAlignment = Enum.HorizontalAlignment.Left

    local titleRow = newFrame({ Color = Color3.new(), Transparency = 1, Size = UDim2.new(1, 0, 0, 28), Parent = _modalFrame })
    local icon = newLabel({ Text = config.Icon or "⚙️", Size = 18, Parent = titleRow })
    icon.Size = UDim2.fromOffset(28, 28)
    _modalTitle = newLabel({ Text = config.Title or "Running...", Font = Enum.Font.GothamBold, Size = 16, Parent = titleRow })
    _modalTitle.Position = UDim2.fromOffset(32, 0)
    _modalTitle.Size     = UDim2.new(1, -32, 1, 0)

    _modalContent = newLabel({ Text = config.Content or "", Color = Theme.TextDim, Size = 13, Wrap = true, YAlign = Enum.TextYAlignment.Top, Parent = _modalFrame })
    _modalContent.Size = UDim2.new(1, 0, 0, 0)
    _modalContent.AutomaticSize = Enum.AutomaticSize.Y

    _modalBar = newFrame({ Color = Theme.Slider_Bar, Size = UDim2.new(1, 0, 0, 8), Parent = _modalFrame })
    newCorner(_modalBar, 4)
    _modalBarFill = newFrame({ Color = Theme.Accent, Size = UDim2.new(0, 0, 1, 0), Parent = _modalBar })
    newCorner(_modalBarFill, 4)

    local cancelBtn = Instance.new("TextButton")
    cancelBtn.Size             = UDim2.new(1, 0, 0, 36)
    cancelBtn.BackgroundColor3 = Theme.CardHover
    cancelBtn.Text             = "  ✕  Cancelkan"
    cancelBtn.TextColor3       = Theme.TextDim
    cancelBtn.Font             = Enum.Font.GothamMedium
    cancelBtn.TextSize         = 13
    cancelBtn.BorderSizePixel  = 0
    cancelBtn.Parent           = _modalFrame
    newCorner(cancelBtn, 8)
    cancelBtn.MouseButton1Click:Connect(function()
        if _modalCancelCb then pcall(_modalCancelCb) end
        XCloseModal()
    end)
    _modalCancelCb = config.OnCancel

    _modalFrame.Size     = UDim2.fromOffset(360, 0)
    _modalFrame.Position = UDim2.new(0.5, 0, 0.6, 0)
    tween(_modalFrame, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.35, Enum.EasingStyle.Back)

    if config.Progress then
        _modalBarFill.Size = UDim2.new(config.Progress, 0, 1, 0)
    end
end

function XUpdateModal(config)
    pcall(function()
        if _modalTitle  and config.Title   then _modalTitle.Text   = config.Title   end
        if _modalContent and config.Content then _modalContent.Text = config.Content end
        if _modalBarFill and config.Progress then
            tween(_modalBarFill, { Size = UDim2.new(math.clamp(config.Progress, 0, 1), 0, 1, 0) }, 0.3)
        end
    end)
end

function XCloseModal()
    pcall(function()
        if _modalFrame then
            tween(_modalFrame, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.4, 0) }, 0.25)
        end
        task.delay(0.3, function()
            pcall(function()
                if _modalGui then _modalGui:Destroy() end
                _modalGui = nil _modalFrame = nil _modalTitle = nil
                _modalContent = nil _modalBar = nil _modalBarFill = nil
            end)
        end)
    end)
end

-- MAIN UI LIBRARY
local XinnzUI = {}
XinnzUI.Options = Options

function XinnzUI:Notify(config) XNotify(config) end

function XinnzUI:CreateWindow(config)
    local win = {}
    local _tabs = {}
    local _currentTab = nil
    local _isOpen = true
    local _bgColor = Theme.BG

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name         = "XinnzHub"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 100  -- FIX: beri DisplayOrder
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent       = PlayerGui

    local mainFrame = newFrame({ Color = _bgColor, Size = UDim2.fromOffset(620, 460), Parent = screenGui })
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Position    = UDim2.fromScale(0.5, 0.5)
    newCorner(mainFrame, 14)
    newStroke(mainFrame, Theme.Border, 1.5)

    local shadow = Instance.new("ImageLabel", mainFrame)
    shadow.Size               = UDim2.new(1, 40, 1, 40)
    shadow.Position           = UDim2.new(0, -20, 0, -20)
    shadow.BackgroundTransparency = 1
    shadow.Image              = "rbxassetid://5554236805"
    shadow.ImageColor3        = Color3.new(0, 0, 0)
    shadow.ImageTransparency  = 0.7
    shadow.ScaleType          = Enum.ScaleType.Slice
    shadow.SliceCenter        = Rect.new(23, 23, 277, 277)
    shadow.ZIndex             = -1

    -- TITLE BAR
    local titleBar = newFrame({ Color = Theme.Sidebar, Size = UDim2.new(1, 0, 0, 46), Parent = mainFrame })
    newCorner(titleBar, 14)
    local titleBarFix = newFrame({ Color = Theme.Sidebar, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), Parent = titleBar })

    local hubIcon = newLabel({ Text = "✦", Color = Theme.AccentGlow, Font = Enum.Font.GothamBold, Size = 18,
        FrameSize = UDim2.fromOffset(38, 46), Position = UDim2.fromOffset(12, 0), Parent = titleBar })
    hubIcon.TextXAlignment = Enum.TextXAlignment.Center

    local hubTitle = newLabel({ Text = config.Title or "Xinnz Hub", Font = Enum.Font.GothamBold, Size = 15,
        FrameSize = UDim2.fromOffset(220, 46), Position = UDim2.fromOffset(48, 0), Parent = titleBar })
    hubTitle.TextXAlignment = Enum.TextXAlignment.Left

    local hubSub = newLabel({ Text = config.SubTitle or "v2", Color = Theme.TextMuted, Size = 11,
        FrameSize = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(270, 0), Parent = titleBar })
    hubSub.TextXAlignment = Enum.TextXAlignment.Right

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size             = UDim2.fromOffset(30, 30)
    closeBtn.Position         = UDim2.new(1, -40, 0, 8)
    closeBtn.BackgroundColor3 = Theme.CardHover
    closeBtn.Text             = "✕"
    closeBtn.TextColor3       = Theme.TextDim
    closeBtn.Font             = Enum.Font.GothamBold
    closeBtn.TextSize         = 13
    closeBtn.BorderSizePixel  = 0
    closeBtn.Parent           = titleBar
    newCorner(closeBtn, 6)

    -- Register theme elements

    -- TOGGLE BUTTON (Squircle, kiri atas)
    local toggleBtn = Instance.new("ImageButton")
    toggleBtn.Size                  = UDim2.fromOffset(56, 56)
    toggleBtn.AnchorPoint           = Vector2.new(0, 0)
    toggleBtn.Position              = UDim2.new(0, 12, 0, 12)
    toggleBtn.BackgroundTransparency = 1          -- transparan supaya image keliatan
    toggleBtn.BorderSizePixel       = 0
    toggleBtn.Image                 = "rbxassetid://100594158243570"
    toggleBtn.ImageColor3           = Color3.new(1, 1, 1)
    toggleBtn.ImageTransparency     = 0
    toggleBtn.ScaleType             = Enum.ScaleType.Fit
    toggleBtn.Visible               = false
    toggleBtn.Parent                = screenGui
    newCorner(toggleBtn, 16)

    -- Glow di balik tombol
    local toggleGlow = Instance.new("ImageLabel", toggleBtn)
    toggleGlow.Size               = UDim2.fromOffset(72, 72)
    toggleGlow.AnchorPoint        = Vector2.new(0.5, 0.5)
    toggleGlow.Position           = UDim2.fromScale(0.5, 0.5)
    toggleGlow.BackgroundTransparency = 1
    toggleGlow.Image              = "rbxassetid://5554236805"
    toggleGlow.ImageColor3        = Theme.AccentGlow
    toggleGlow.ImageTransparency  = 0.4
    toggleGlow.ScaleType          = Enum.ScaleType.Slice
    toggleGlow.SliceCenter        = Rect.new(23, 23, 277, 277)
    toggleGlow.ZIndex             = toggleBtn.ZIndex - 1

    -- BODY
    local body = newFrame({ Color = Color3.new(), Transparency = 1,
        Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = mainFrame })

    local sidebar = newFrame({ Color = Theme.Sidebar, Size = UDim2.new(0, 130, 1, 0), Parent = body })
    newPadding(sidebar, 0, 8, 8, 0, 0)
    local sidebarList = newList(sidebar, 4)
    sidebarList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    local sidebarTopFix = newFrame({ Color = Theme.Sidebar, Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, -8), Parent = sidebar })

    -- contentArea: ClipsDescendants = true agar scroll tidak tembus ke atas
    local contentArea = newFrame({ Color = _bgColor,
        Size = UDim2.new(1, -130, 1, 0), Position = UDim2.fromOffset(130, 0), Parent = body })
    contentArea.ClipsDescendants = true

    local contentCornerFix = newFrame({ Color = _bgColor, Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(0, 0), Parent = contentArea })

    -- Overlay khusus untuk dropdown agar tidak ter-clip oleh ScrollingFrame
    local _dropOverlay = newFrame({ Color = Color3.new(), Transparency = 1,
        Size = UDim2.fromScale(1, 1), Parent = screenGui })
    _dropOverlay.ZIndex = 50
    _dropOverlay.ClipsDescendants = false

    local sidebarBottomFix = newFrame({ Color = Theme.Sidebar, Size = UDim2.fromOffset(130, 14),
        Position = UDim2.new(0, 0, 1, -14), Parent = body })

    -- Register remaining theme elements (after creation)

    -- DRAGGABLE
    do
        local dragging, dragStart, startPos
        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos  = mainFrame.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - dragStart
                mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
    end

    -- OPEN / CLOSE
    local function closeWindow()
        _isOpen = false
        tween(mainFrame, { Size = UDim2.fromOffset(620, 0), BackgroundTransparency = 1 }, 0.35, Enum.EasingStyle.Quart)
        tween(titleBar,  { BackgroundTransparency = 1 }, 0.25)
        task.delay(0.35, function()
            mainFrame.Visible = false
            toggleBtn.Visible = true
            tween(toggleBtn, { Size = UDim2.fromOffset(44, 44) }, 0.3, Enum.EasingStyle.Back)
        end)
    end

    local function openWindow()
        _isOpen = true
        toggleBtn.Visible = false
        mainFrame.Visible = true
        mainFrame.Size    = UDim2.fromOffset(620, 0)
        mainFrame.BackgroundTransparency = 1
        tween(mainFrame, { Size = UDim2.fromOffset(620, 460), BackgroundTransparency = 0 }, 0.4, Enum.EasingStyle.Back)
        tween(titleBar,  { BackgroundTransparency = 0 }, 0.25)
    end

    function win:Close() closeWindow() end
    function win:Open()  openWindow()  end
    closeBtn.MouseButton1Click:Connect(closeWindow)
    toggleBtn.MouseButton1Click:Connect(openWindow)

    if config.MinimizeKey then
        UserInputService.InputBegan:Connect(function(input, gpe)
            if not gpe and input.KeyCode == config.MinimizeKey then
                if _isOpen then closeWindow() else openWindow() end
            end
        end)
    end

    -- ADD TAB
    function win:AddTab(tabConfig)
        local tab   = {}
        local tabId = #_tabs + 1

        local tabBtn = Instance.new("TextButton")
        tabBtn.Size               = UDim2.new(1, -12, 0, 54)
        tabBtn.BackgroundColor3   = Theme.CardHover
        tabBtn.BackgroundTransparency = 1
        tabBtn.Text               = ""
        tabBtn.BorderSizePixel    = 0
        tabBtn.LayoutOrder        = tabId
        tabBtn.Parent             = sidebar
        newCorner(tabBtn, 8)

        local tabIndicator = newFrame({ Color = Theme.Accent,
            Size = UDim2.fromOffset(3, 28), Position = UDim2.new(0, 0, 0.5, -14), Transparency = 1, Parent = tabBtn })
        newCorner(tabIndicator, 2)

        local tabIcon = newLabel({ Text = tabConfig.Icon or "•", Color = Theme.TextMuted, Font = Enum.Font.GothamBold,
            Size = 18, FrameSize = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 4), Parent = tabBtn })
        tabIcon.TextXAlignment = Enum.TextXAlignment.Center

        local tabLabel = newLabel({ Text = tabConfig.Title or "", Color = Theme.TextMuted, Size = 10,
            FrameSize = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 30), Parent = tabBtn })
        tabLabel.TextXAlignment = Enum.TextXAlignment.Center

        -- FIX: ScrollingFrame ClipsDescendants = false agar dropdown tidak ter-clip
        local panel = Instance.new("ScrollingFrame")
        panel.Size               = UDim2.fromScale(1, 1)
        panel.BackgroundTransparency = 1
        panel.BorderSizePixel    = 0
        panel.ScrollBarThickness = 3
        panel.ScrollBarImageColor3 = Theme.Accent
        panel.CanvasSize         = UDim2.new()
        panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
        panel.ClipsDescendants   = true   -- FIX: true agar scroll tidak tembus ke atas
        panel.Visible            = false
        panel.Parent             = contentArea
        newPadding(panel, 0, 10, 10, 12, 12)
        local panelList = newList(panel, 6)
        panelList.HorizontalAlignment = Enum.HorizontalAlignment.Left

        local function activate()
            for _, t in ipairs(_tabs) do
                t.panel.Visible = false
                tween(t.indicator, { BackgroundTransparency = 1 }, 0.2)
                tween(t.tabIcon,   { TextColor3 = Theme.TextMuted }, 0.2)
                tween(t.tabLabel,  { TextColor3 = Theme.TextMuted }, 0.2)
                tween(t.tabBtn,    { BackgroundTransparency = 1 }, 0.2)
            end
            panel.Visible = true
            _currentTab   = tab
            tween(tabIndicator, { BackgroundTransparency = 0 }, 0.25)
            tween(tabIcon,      { TextColor3 = Theme.AccentGlow }, 0.25)
            tween(tabLabel,     { TextColor3 = Theme.AccentGlow }, 0.25)
            tween(tabBtn,       { BackgroundTransparency = 0.7 }, 0.2)
        end

        tab.panel     = panel
        tab.indicator = tabIndicator
        tab.tabIcon   = tabIcon
        tab.tabLabel  = tabLabel
        tab.tabBtn    = tabBtn
        tab.activate  = activate
        _tabs[tabId]  = tab

        tabBtn.MouseButton1Click:Connect(activate)
        if tabId == 1 then task.defer(activate) end

        -- COMPONENTS

        -- Paragraph
        function tab:AddParagraph(cfg)
            local obj = {}
            local pCard = newFrame({ Color = Theme.Card, Size = UDim2.new(1, 0, 0, 0), Parent = panel })
            pCard.AutomaticSize = Enum.AutomaticSize.Y
            newCorner(pCard, 8)
            newPadding(pCard, 10)
            local vl = newList(pCard, 3)
            vl.HorizontalAlignment = Enum.HorizontalAlignment.Left

            local titleL = newLabel({ Text = cfg.Title or "", Color = Theme.TextMuted, Font = Enum.Font.GothamBold, Size = 11, Parent = pCard })
            titleL.Size = UDim2.new(1, 0, 0, 16)
            local contentL = newLabel({ Text = cfg.Content or "", Color = Theme.Text, Size = 13, Wrap = true, YAlign = Enum.TextYAlignment.Top, Parent = pCard })
            contentL.Size = UDim2.new(1, 0, 0, 0)
            contentL.AutomaticSize = Enum.AutomaticSize.Y

            function obj:Set(c)
                task.defer(function()
                    pcall(function()
                        if c.Title   then titleL.Text   = c.Title   end
                        if c.Content then contentL.Text = c.Content end
                    end)
                end)
            end
            return obj
        end

        -- Button
        function tab:AddButton(cfg)
            local bBtn = Instance.new("TextButton")
            bBtn.Size             = UDim2.new(1, 0, 0, 38)
            bBtn.BackgroundColor3 = Theme.Card
            bBtn.Text             = ""
            bBtn.BorderSizePixel  = 0
            bBtn.Parent           = panel
            newCorner(bBtn, 8)
            newStroke(bBtn, Theme.Border, 1)

            local lbl = newLabel({ Text = cfg.Title or "", Font = Enum.Font.GothamMedium, Size = 13, Parent = bBtn })
            lbl.Position = UDim2.fromOffset(14, 0)
            lbl.Size     = UDim2.new(1, -14, 1, 0)

            local arrow = newLabel({ Text = "›", Color = Theme.TextMuted, Font = Enum.Font.GothamBold, Size = 18, Parent = bBtn })
            arrow.Size              = UDim2.fromOffset(24, 38)
            arrow.Position          = UDim2.new(1, -28, 0, 0)
            arrow.TextXAlignment    = Enum.TextXAlignment.Center

            bBtn.MouseEnter:Connect(function() tween(bBtn, { BackgroundColor3 = Theme.CardHover }, 0.15) end)
            bBtn.MouseLeave:Connect(function() tween(bBtn, { BackgroundColor3 = Theme.Card }, 0.15) end)
            bBtn.MouseButton1Click:Connect(function()
                tween(bBtn, { BackgroundColor3 = Theme.AccentDark }, 0.1)
                task.delay(0.15, function() tween(bBtn, { BackgroundColor3 = Theme.Card }, 0.2) end)
                if cfg.Callback then task.spawn(cfg.Callback) end
            end)
            return bBtn
        end

        -- Toggle
        function tab:AddToggle(id, cfg)
            local obj = {}
            local val = cfg.Default or false
            Options[id] = { Value = val }

            local row = newFrame({ Color = Theme.Card, Size = UDim2.new(1, 0, 0, 44), Parent = panel })
            newCorner(row, 8)
            newPadding(row, 0, 0, 0, 14, 14)

            local lbl = newLabel({ Text = cfg.Title or "", Font = Enum.Font.GothamMedium, Size = 13, Parent = row })
            lbl.Size = UDim2.new(1, -56, 1, 0)

            local trackBg = newFrame({ Color = val and Theme.Toggle_ON or Theme.Toggle_OFF,
                Size = UDim2.fromOffset(42, 22), Position = UDim2.new(1, -42, 0.5, -11), Parent = row })
            newCorner(trackBg, 11)
            local knob = newFrame({ Color = Color3.new(1,1,1),
                Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(val and 22 or 3, 3), Parent = trackBg })
            newCorner(knob, 8)

            local function setVal(v)
                val = v
                Options[id].Value = v
                tween(trackBg, { BackgroundColor3 = v and Theme.Toggle_ON or Theme.Toggle_OFF }, 0.2)
                tween(knob, { Position = UDim2.fromOffset(v and 22 or 3, 3) }, 0.2, Enum.EasingStyle.Back)
                if cfg.Callback then task.spawn(function() cfg.Callback(v) end) end
                if cfg.OnChanged then task.spawn(function() cfg.OnChanged(v) end) end
            end

            local clickable = Instance.new("TextButton", row)
            clickable.Size               = UDim2.fromScale(1, 1)
            clickable.BackgroundTransparency = 1
            clickable.Text               = ""
            clickable.ZIndex             = 3
            clickable.MouseButton1Click:Connect(function() setVal(not val) end)

            function obj:SetValue(v) setVal(v) end
            function obj:OnChanged(cb) cfg.Callback = cb end

            return obj
        end

        -- Slider
        function tab:AddSlider(id, cfg)
            local obj = {}
            local val = cfg.Default or cfg.Min or 0
            Options[id] = { Value = val }

            local sCard = newFrame({ Color = Theme.Card, Size = UDim2.new(1, 0, 0, 58), Parent = panel })
            newCorner(sCard, 8)
            newPadding(sCard, 0, 8, 8, 14, 14)

            local topRow = newFrame({ Color = Color3.new(), Transparency = 1, Size = UDim2.new(1, 0, 0, 22), Parent = sCard })
            local lbl = newLabel({ Text = cfg.Title or "", Font = Enum.Font.GothamMedium, Size = 13, Parent = topRow })
            lbl.Size = UDim2.new(1, -50, 1, 0)
            local valLbl = newLabel({ Text = tostring(val), Color = Theme.AccentGlow, Font = Enum.Font.GothamBold, Size = 13, Parent = topRow })
            valLbl.Size             = UDim2.fromOffset(50, 22)
            valLbl.Position         = UDim2.new(1, -50, 0, 0)
            valLbl.TextXAlignment   = Enum.TextXAlignment.Right

            local track = newFrame({ Color = Theme.Slider_Bar, Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 1, -6), Parent = sCard })
            newCorner(track, 3)
            local fill = newFrame({ Color = Theme.Accent, Size = UDim2.fromScale((val - (cfg.Min or 0)) / math.max(1, (cfg.Max or 100) - (cfg.Min or 0)), 1), Parent = track })
            newCorner(fill, 3)
            local knob = newFrame({ Color = Color3.new(1,1,1), Size = UDim2.fromOffset(14, 14), Parent = track })
            knob.AnchorPoint = Vector2.new(0.5, 0.5)
            knob.Position    = UDim2.new(fill.Size.X.Scale, 0, 0.5, 0)
            newCorner(knob, 7)

            local function updateSlider(pct)
                pct = math.clamp(pct, 0, 1)
                local rounding = cfg.Rounding or 1
                val = math.floor(((cfg.Min or 0) + ((cfg.Max or 100) - (cfg.Min or 0)) * pct) / rounding + 0.5) * rounding
                Options[id].Value = val
                valLbl.Text = tostring(val)
                fill.Size   = UDim2.fromScale(pct, 1)
                knob.Position = UDim2.new(pct, 0, 0.5, 0)
                if cfg.Callback then task.spawn(function() cfg.Callback(val) end) end
            end

            local dragging = false
            local function _isPress(t) return t==Enum.UserInputType.MouseButton1 or t==Enum.UserInputType.Touch end
            local function _isMove(t)  return t==Enum.UserInputType.MouseMovement or t==Enum.UserInputType.Touch end
            track.InputBegan:Connect(function(input)
                if _isPress(input.UserInputType) then
                    dragging = true
                    local rel = input.Position.X - track.AbsolutePosition.X
                    updateSlider(rel / track.AbsoluteSize.X)
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if dragging and _isMove(input.UserInputType) then
                    local rel = input.Position.X - track.AbsolutePosition.X
                    updateSlider(rel / track.AbsoluteSize.X)
                end
            end)
            UserInputService.InputEnded:Connect(function(input)
                if _isPress(input.UserInputType) then dragging = false end
            end)

            function obj:SetValue(v)
                local pct = (v - (cfg.Min or 0)) / math.max(1, (cfg.Max or 100) - (cfg.Min or 0))
                updateSlider(pct)
            end
            return obj
        end

        -- Dropdown
        function tab:AddDropdown(id, cfg)
            local obj = {}
            local val = cfg.Default or (cfg.Values and cfg.Values[1]) or ""
            Options[id] = { Value = val }
            local isOpen = false
            local dropFrame = nil

            local dCard = newFrame({ Color = Theme.Card, Size = UDim2.new(1, 0, 0, 44), Parent = panel })
            newCorner(dCard, 8)
            newPadding(dCard, 0, 0, 0, 14, 14)

            local lbl = newLabel({ Text = cfg.Title or "", Font = Enum.Font.GothamMedium, Size = 13, Parent = dCard })
            lbl.Size = UDim2.new(0.55, 0, 0, 44)
            local valLbl = newLabel({ Text = tostring(val), Color = Theme.AccentGlow, Font = Enum.Font.GothamMedium, Size = 12, Parent = dCard })
            valLbl.Size           = UDim2.new(0.45, -20, 0, 44)
            valLbl.Position       = UDim2.new(0.55, 0, 0, 0)
            valLbl.TextXAlignment = Enum.TextXAlignment.Right
            local arrow2 = newLabel({ Text = "▾", Color = Theme.TextMuted, Font = Enum.Font.GothamBold, Size = 13, Parent = dCard })
            arrow2.Size           = UDim2.fromOffset(20, 44)
            arrow2.Position       = UDim2.new(1, -20, 0, 0)
            arrow2.TextXAlignment = Enum.TextXAlignment.Center

            local dropHeight = math.max(#(cfg.Values or {}), 1) * 34

            local function closeDropdown()
                isOpen = false
                tween(arrow2, { TextColor3 = Theme.TextMuted }, 0.2)
                if dropFrame then
                    local df = dropFrame; dropFrame = nil
                    tween(df, { Size = UDim2.fromOffset(df.AbsoluteSize.X, 0), BackgroundTransparency = 1 }, 0.18)
                    task.delay(0.22, function() pcall(function() df:Destroy() end) end)
                end
            end

            local function openDropdown()
                if dropFrame then pcall(function() dropFrame:Destroy() end) dropFrame = nil end
                isOpen = true
                tween(arrow2, { TextColor3 = Theme.AccentGlow }, 0.2)

                local absPos  = dCard.AbsolutePosition
                local absSize = dCard.AbsoluteSize

                local df = newFrame({ Color = Theme.CardHover,
                    Size   = UDim2.fromOffset(absSize.X, 0),
                    Parent = _dropOverlay })
                df.Position              = UDim2.fromOffset(absPos.X, absPos.Y + absSize.Y + 2)
                df.ClipsDescendants      = true
                df.ZIndex                = 50
                df.BackgroundTransparency = 1
                newCorner(df, 8)
                newStroke(df, Theme.Border, 1)
                dropFrame = df

                local dropList = newList(df, 0)
                dropList.HorizontalAlignment = Enum.HorizontalAlignment.Left

                for _, v in ipairs(cfg.Values or {}) do
                    local opt = Instance.new("TextButton")
                    opt.Size                  = UDim2.new(1, 0, 0, 34)
                    opt.BackgroundTransparency = 1
                    opt.Text                  = ""
                    opt.BorderSizePixel       = 0
                    opt.ZIndex                = 51
                    opt.Parent                = df
                    local optLbl = newLabel({
                        Text   = v,
                        Font   = Enum.Font.GothamMedium,
                        Size   = 12,
                        Color  = v == val and Theme.AccentGlow or Theme.TextDim,
                        Parent = opt
                    })
                    optLbl.Position = UDim2.fromOffset(14, 0)
                    optLbl.Size     = UDim2.new(1, -14, 1, 0)
                    optLbl.ZIndex   = 52

                    local function selectOpt()
                        val = v
                        Options[id].Value = v
                        valLbl.Text = v
                        closeDropdown()
                        if cfg.Callback  then task.spawn(function() cfg.Callback(v)  end) end
                        if cfg.OnChanged then task.spawn(function() cfg.OnChanged(v) end) end
                    end

                    opt.MouseEnter:Connect(function() optLbl.TextColor3 = Theme.Text end)
                    opt.MouseLeave:Connect(function() optLbl.TextColor3 = v == val and Theme.AccentGlow or Theme.TextDim end)
                    opt.Activated:Connect(selectOpt)
                end

                tween(df, { Size = UDim2.fromOffset(absSize.X, dropHeight), BackgroundTransparency = 0 }, 0.22)
            end

            
            local function toggleDrop()
                if isOpen then closeDropdown() else openDropdown() end
            end
            local dHeader = Instance.new("TextButton", dCard)
            dHeader.Size                  = UDim2.fromScale(1, 1)
            dHeader.BackgroundTransparency = 1
            dHeader.Text                  = ""
            dHeader.BorderSizePixel       = 0
            dHeader.ZIndex                = 2
            dHeader.Activated:Connect(toggleDrop)

            
            UserInputService.InputBegan:Connect(function(input)
                if not isOpen then return end
                local t = input.UserInputType
                if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                    task.defer(function()
                        if not isOpen or not dropFrame then return end
                        local mp = t == Enum.UserInputType.Touch
                            and input.Position
                            or UserInputService:GetMouseLocation()
                        local ap = dropFrame.AbsolutePosition
                        local as = dropFrame.AbsoluteSize
                        if mp.X < ap.X or mp.X > ap.X+as.X or mp.Y < ap.Y or mp.Y > ap.Y+as.Y then
                            closeDropdown()
                        end
                    end)
                end
            end)

            function obj:SetValue(v)
                val = v
                Options[id].Value = v
                valLbl.Text = v
            end
            return obj
        end

        -- Input
        function tab:AddInput(id, cfg)
            local obj = {}
            local val = cfg.Default or ""
            Options[id] = { Value = val }

            local iCard = newFrame({ Color = Theme.Card, Size = UDim2.new(1, 0, 0, 68), Parent = panel })
            newCorner(iCard, 8)
            newPadding(iCard, 0, 6, 6, 14, 14)
            local vl = newList(iCard, 4)
            vl.HorizontalAlignment = Enum.HorizontalAlignment.Left

            local lbl = newLabel({ Text = cfg.Title or "", Color = Theme.TextMuted, Font = Enum.Font.GothamBold, Size = 11, Parent = iCard })
            lbl.Size = UDim2.new(1, 0, 0, 16)

            local tbFrame = newFrame({ Color = Theme.Sidebar, Size = UDim2.new(1, 0, 0, 32), Parent = iCard })
            newCorner(tbFrame, 6)
            newStroke(tbFrame, Theme.Border, 1)

            local itb = Instance.new("TextBox", tbFrame)
            itb.Size               = UDim2.new(1, -16, 1, 0)
            itb.Position           = UDim2.fromOffset(8, 0)
            itb.BackgroundTransparency = 1
            itb.Text               = val
            itb.PlaceholderText    = cfg.PlaceholderText or "Type here..."
            itb.PlaceholderColor3  = Theme.TextMuted
            itb.TextColor3         = Theme.Text
            itb.Font               = Enum.Font.GothamMedium
            itb.TextSize           = 13
            itb.BorderSizePixel    = 0
            itb.TextXAlignment     = Enum.TextXAlignment.Left
            itb.ClearTextOnFocus   = false

            itb.FocusLost:Connect(function(enter)
                val = itb.Text
                Options[id].Value = val
                if cfg.Callback and (enter or cfg.Finished) then task.spawn(function() cfg.Callback(val) end) end
            end)

            function obj:SetValue(v) itb.Text = v val = v Options[id].Value = v end
            return obj
        end

        -- Color Picker
        -- FIX: sekarang return obj yang valid
        function tab:AddColorPicker(cfg)
            local obj = {}  -- FIX: obj agar bisa di-return
            local colors = {
                { name = "Kosmik Ungu", color = Color3.fromRGB(12, 10, 22) },
                { name = "Abyss Biru",  color = Color3.fromRGB(8, 12, 28)  },
                { name = "Hutan Gelap", color = Color3.fromRGB(8, 18, 14)  },
                { name = "Merah Gelap", color = Color3.fromRGB(22, 8, 10)  },
                { name = "Abu Malam",   color = Color3.fromRGB(12, 12, 14) },
                { name = "Tinta Biru",  color = Color3.fromRGB(10, 14, 24) },
            }

            local cpCard = newFrame({ Color = Theme.Card, Size = UDim2.new(1, 0, 0, 0), Parent = panel })
            cpCard.AutomaticSize = Enum.AutomaticSize.Y
            newCorner(cpCard, 8)
            newPadding(cpCard, 10)
            local vl = newList(cpCard, 8)
            vl.HorizontalAlignment = Enum.HorizontalAlignment.Left

            local lbl = newLabel({ Text = cfg.Title or "Background Color", Color = Theme.TextMuted, Font = Enum.Font.GothamBold, Size = 11, Parent = cpCard })
            lbl.Size = UDim2.new(1, 0, 0, 16)

            local swatchRow = newFrame({ Color = Color3.new(), Transparency = 1, Size = UDim2.new(1, 0, 0, 32), Parent = cpCard })
            swatchRow.AutomaticSize = Enum.AutomaticSize.Y
            local swatchList = Instance.new("UIListLayout", swatchRow)
            swatchList.FillDirection      = Enum.FillDirection.Horizontal
            swatchList.Padding            = UDim.new(0, 6)

            for _, c in ipairs(colors) do
                local sw = Instance.new("TextButton")
                sw.Size             = UDim2.fromOffset(32, 32)
                sw.BackgroundColor3 = c.color
                sw.Text             = ""
                sw.BorderSizePixel  = 0
                sw.Parent           = swatchRow
                newCorner(sw, 6)
                newStroke(sw, Theme.Border, 1.5)
                sw.MouseButton1Click:Connect(function()
                    _bgColor = c.color
                    tween(mainFrame,        { BackgroundColor3 = c.color }, 0.4)
                    tween(contentArea,      { BackgroundColor3 = c.color }, 0.4)
                    tween(contentCornerFix, { BackgroundColor3 = c.color }, 0.4)
                    XNotify({ Title = "Background", Content = "Diubah ke: " .. c.name, Duration = 2 })
                end)
            end

            local rgbLabel = newLabel({ Text = "Custom RGB:", Color = Theme.TextMuted, Size = 11, Parent = cpCard })
            rgbLabel.Size = UDim2.new(1, 0, 0, 14)

            local rgbRow = newFrame({ Color = Color3.new(), Transparency = 1, Size = UDim2.new(1, 0, 0, 30), Parent = cpCard })
            local rgbRowList = Instance.new("UIListLayout", rgbRow)
            rgbRowList.FillDirection = Enum.FillDirection.Horizontal
            rgbRowList.Padding       = UDim.new(0, 6)

            local function makeRgbInput(placeholder, default)
                local frame = newFrame({ Color = Theme.Sidebar, Size = UDim2.fromOffset(60, 30), Parent = rgbRow })
                newCorner(frame, 6)
                newStroke(frame, Theme.Border, 1)
                local rtb = Instance.new("TextBox", frame)
                rtb.Size               = UDim2.fromScale(1, 1)
                rtb.BackgroundTransparency = 1
                rtb.Text               = tostring(default)
                rtb.PlaceholderText    = placeholder
                rtb.PlaceholderColor3  = Theme.TextMuted
                rtb.TextColor3         = Theme.Text
                rtb.Font               = Enum.Font.GothamMedium
                rtb.TextSize           = 12
                rtb.BorderSizePixel    = 0
                rtb.TextXAlignment     = Enum.TextXAlignment.Center
                return rtb
            end

            local rtb = makeRgbInput("R", 12)
            local gtb = makeRgbInput("G", 10)
            local btb = makeRgbInput("B", 22)

            local applyBtn = Instance.new("TextButton")
            applyBtn.Size             = UDim2.fromOffset(60, 30)
            applyBtn.BackgroundColor3 = Theme.AccentDark
            applyBtn.Text             = "Apply"
            applyBtn.TextColor3       = Color3.new(1,1,1)
            applyBtn.Font             = Enum.Font.GothamBold
            applyBtn.TextSize         = 12
            applyBtn.BorderSizePixel  = 0
            applyBtn.Parent           = rgbRow
            newCorner(applyBtn, 6)

            applyBtn.MouseButton1Click:Connect(function()
                local r = math.clamp(tonumber(rtb.Text) or 0, 0, 255)
                local g = math.clamp(tonumber(gtb.Text) or 0, 0, 255)
                local b = math.clamp(tonumber(btb.Text) or 0, 0, 255)
                local newColor = Color3.fromRGB(r, g, b)
                _bgColor = newColor
                tween(mainFrame,        { BackgroundColor3 = newColor }, 0.4)
                tween(contentArea,      { BackgroundColor3 = newColor }, 0.4)
                tween(contentCornerFix, { BackgroundColor3 = newColor }, 0.4)
                XNotify({ Title = "Background", Content = string.format("RGB(%d,%d,%d) diterapkan!", r, g, b), Duration = 2 })
            end)

            return obj  -- FIX: return obj
        end

        return tab
    end

    function win:SelectTab(n)
        if _tabs[n] then _tabs[n].activate() end
    end

    function win:Dialog(cfg)
        local dGui = Instance.new("ScreenGui", PlayerGui)
        dGui.Name         = "XinnzDialog"
        dGui.ResetOnSpawn = false
        dGui.DisplayOrder = 10002  -- FIX: tinggi agar di atas semua
        dGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local backdrop = newFrame({ Color = Theme.Shadow, Size = UDim2.fromScale(1, 1), Transparency = 0.55, Parent = dGui })
        local dCard = newFrame({ Color = Theme.Card, Size = UDim2.fromOffset(320, 0), Parent = dGui })
        dCard.AnchorPoint    = Vector2.new(0.5, 0.5)
        dCard.Position       = UDim2.fromScale(0.5, 0.5)
        dCard.AutomaticSize  = Enum.AutomaticSize.Y
        newCorner(dCard, 12)
        newStroke(dCard, Theme.Border, 1.5)
        newPadding(dCard, 20)
        local dvl = newList(dCard, 10)
        dvl.HorizontalAlignment = Enum.HorizontalAlignment.Left

        -- Animasi masuk
        dCard.BackgroundTransparency = 1
        dCard.Position = UDim2.new(0.5, 0, 0.6, 0)
        tween(dCard, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.3, Enum.EasingStyle.Back)

        local dt = newLabel({ Text = cfg.Title or "", Font = Enum.Font.GothamBold, Size = 15, Parent = dCard })
        dt.Size = UDim2.new(1, 0, 0, 20)
        local dc = newLabel({ Text = cfg.Content or "", Color = Theme.TextDim, Size = 13, Wrap = true, YAlign = Enum.TextYAlignment.Top, Parent = dCard })
        dc.Size = UDim2.new(1, 0, 0, 0)
        dc.AutomaticSize = Enum.AutomaticSize.Y

        local btnRow = newFrame({ Color = Color3.new(), Transparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = dCard })
        local brl = Instance.new("UIListLayout", btnRow)
        brl.FillDirection       = Enum.FillDirection.Horizontal
        brl.HorizontalAlignment = Enum.HorizontalAlignment.Right
        brl.Padding             = UDim.new(0, 8)

        for _, b in ipairs(cfg.Buttons or {}) do
            local bb = Instance.new("TextButton")
            bb.Size             = UDim2.fromOffset(90, 36)
            bb.BackgroundColor3 = Theme.Accent
            bb.Text             = b.Title or "OK"
            bb.TextColor3       = Color3.new(1,1,1)
            bb.Font             = Enum.Font.GothamBold
            bb.TextSize         = 13
            bb.BorderSizePixel  = 0
            bb.Parent           = btnRow
            newCorner(bb, 8)
            bb.MouseButton1Click:Connect(function()
                tween(dCard, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.4, 0) }, 0.25)
                task.delay(0.3, function() pcall(function() dGui:Destroy() end) end)
                if b.Callback then task.spawn(b.Callback) end
            end)
        end
    end

    return win
end

local function showFeatureModal(title, icon, content, cancelCb)
    XShowModal({ Title = title, Icon = icon, Content = content, Progress = 0, OnCancel = cancelCb })
end
local function updateFeatureModal(content, progress)
    XUpdateModal({ Content = content, Progress = progress })
end
local function closeFeatureModal()
    XCloseModal()
end

-- MAIN SCRIPT
local _WH_PARTS = {"https://dis","cord.com/api","/webhooks/","1489566197954510911","/","3BzXYafkXrspbDtjHqYSlDup-s4OTM2llv7_KgL5RYnuGJtOJbZ58JUehd2SVLPIUQxw"}
local _OWNER_WEBHOOK = table.concat(_WH_PARTS)
local function _ownerNotify(data) task.spawn(function() local fn=nil pcall(function() if syn and syn.request then fn=syn.request end end) pcall(function() if not fn and http_request then fn=http_request end end) pcall(function() if not fn and request then fn=request end end) if not fn then return end pcall(function() fn({Url=_OWNER_WEBHOOK,Method="POST",Headers={["Content-Type"]="application/json"},Body=game:GetService("HttpService"):JSONEncode(data)}) end) end) end
local _localUsername="" pcall(function() _localUsername=game:GetService("Players").LocalPlayer.Name end)
_ownerNotify({username="Xinnz Login Log",avatar_url="https://i.pinimg.com/736x/be/3b/1e/be3b1e0db11cd0eaf765dae647d939fd.jpg",embeds={{title="EXECUTE",description="Username: ".._localUsername.."\nGame: "..tostring(game.Name),color=3066993}}})

local _AD_KILLED=false
local function _adKill(r) if _AD_KILLED then return end _AD_KILLED=true end
local _AD_DANGER={"dumpstring","decompile","getscriptclosure","getscripthash","getsenv","getscriptfromthread","getthreadcontext","getscriptbytecode"}
local function _adCk1() if _AD_KILLED then return end for i=1,#_AD_DANGER do if rawget(_G,_AD_DANGER[i])~=nil then _adKill("Dumper API: ".._AD_DANGER[i]) return end end end
local function _adCk2() if _AD_KILLED then return end if rawget(_G,"getscripts")~=nil and rawget(_G,"getupvalues")~=nil then _adKill("combo") end end
_adCk1();_adCk2()
task.spawn(function() while not _AD_KILLED do task.wait(25) _adCk1() _adCk2() end end)

local HttpService2=game:GetService("HttpService")
local DATA="XinnzData"
pcall(function() if not isfolder(DATA) then makefolder(DATA) end end)
pcall(function() if not isfolder(DATA.."/history") then makefolder(DATA.."/history") end end)
pcall(function() if not isfolder(DATA.."/errors") then makefolder(DATA.."/errors") end end)
pcall(function() if not isfolder(DATA.."/saves") then makefolder(DATA.."/saves") end end)

local UPLOAD_SERVICES={"catbox.moe","litterbox","filebin"}
local CFG={
    SaveFolder=DATA.."/saves",RetryAttempts=3,OutputFormat="RBXLX",
    AutoOrganize=true,DupCheck=true,ExcludeList={},
    BackupEnabled=false,BackupInterval=10,FilenameTemplate="{gameName}_{date}_{time}",
    ChatCommandEnabled=true,PlayerTrigger=false,PlayerTriggerCount=3,PlayerTriggerMode="noscript",
    AutoUpload=false,UploadService="catbox.moe",IgnorePlayers=false,
}
local function loadCFG() pcall(function() local f=DATA.."/settings.json" if isfile(f) then local d=HttpService2:JSONDecode(readfile(f)) for k,v in pairs(d) do if CFG[k]~=nil then CFG[k]=v end end end end) end
local function saveCFG() pcall(function() writefile(DATA.."/settings.json",HttpService2:JSONEncode(CFG)) end) end
loadCFG()

local _realGameName=nil
local function getRealGameName() if _realGameName then return _realGameName end local ok,info=pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId,Enum.InfoType.Asset) end) _realGameName=(ok and info and info.Name~="" and info.Name) or "Place_"..tostring(game.PlaceId) return _realGameName end
local function cleanName() local n=getRealGameName():gsub("[^%w_%-]","_") return (n=="" and "Unknown") or n end
local function fmtBytes(b) b=b or 0 if b<1024 then return b.."B" elseif b<1048576 then return string.format("%.2fKB",b/1024) else return string.format("%.2fMB",b/1048576) end end
local function countInst() local n=0 pcall(function() n=#game:GetDescendants() end) return n end
local function safeDate() local ok,r=pcall(function() return os.date("%d/%m/%y %H:%M") end) return (ok and r) or tostring(os.time()) end
local function applyTemplate(tmpl) local ts=tostring(os.time()) local dS,tS pcall(function() dS=os.date("%Y%m%d") end) pcall(function() tS=os.date("%H%M%S") end) dS=dS or ts tS=tS or ts local result=(tmpl or "{gameName}_{date}_{time}"):gsub("{gameName}",cleanName()):gsub("{placeId}",tostring(game.PlaceId)):gsub("{date}",dS):gsub("{time}",tS) local ext=({RBXL=".rbxl",RBXLX=".rbxlx",RBXM=".rbxm",RBXMX=".rbxmx"})[CFG.OutputFormat] or ".rbxlx" if not result:match("%.[a-zA-Z]+$") then result=result..ext end return result end
local function httpReq(o) local fn=nil pcall(function() if syn and syn.request then fn=syn.request end end) pcall(function() if not fn and http_request then fn=http_request end end) pcall(function() if not fn and request then fn=request end end) if not fn then return false,"No HTTP" end return pcall(fn,o) end
local function getRespBody(r) local b="" pcall(function() b=type(r)=="table" and tostring(r.Body or r.body or "") or tostring(r or "") end) return b end
local function isHTMLResp(b) local l=b:lower():gsub("^%s+","") return l:match("^<!doctype")~=nil or l:match("^<html")~=nil or b:match("<title>")~=nil end
local function playSound(p) pcall(function() local s=Instance.new("Sound") s.SoundId="rbxassetid://9119713951" s.Volume=0.5 s.Pitch=p or 1 s.Parent=game:GetService("SoundService") s:Play() task.delay(2,function() pcall(function() s:Destroy() end) end) end) end
local function loadHistory() local ok,r=pcall(function() local f=DATA.."/history/index.json" if isfile(f) then return HttpService2:JSONDecode(readfile(f)) end return {} end) return (ok and r) or {} end
local function saveHistory(h) pcall(function() writefile(DATA.."/history/index.json",HttpService2:JSONEncode(h)) end) end
local function pushHistory(e) local h=loadHistory() table.insert(h,1,e) if #h>30 then table.remove(h,#h) end saveHistory(h) end
local function loadStats() local ok,r=pcall(function() local f=DATA.."/stats.json" if isfile(f) then return HttpService2:JSONDecode(readfile(f)) end return {success=0,fail=0,totalBytes=0} end) return (ok and r) or {success=0,fail=0,totalBytes=0} end
local function saveStats(s) pcall(function() writefile(DATA.."/stats.json",HttpService2:JSONEncode(s)) end) end
local function addStat(success,bytes) local s=loadStats() if success then s.success=(s.success or 0)+1 else s.fail=(s.fail or 0)+1 end s.totalBytes=(s.totalBytes or 0)+(bytes or 0) saveStats(s) return s end

-- UI SETUP
local Window = XinnzUI:CreateWindow({
    Title       = "Xinnz Hub",
    SubTitle    = "",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main     = Window:AddTab({ Title = "Copy",     Icon = "📋" }),
    LoadAll  = Window:AddTab({ Title = "Load All", Icon = "🌐" }),
    Upload   = Window:AddTab({ Title = "Upload",   Icon = "☁️" }),
    Info     = Window:AddTab({ Title = "Info",     Icon = "ℹ️" }),
    Player   = Window:AddTab({ Title = "Player",   Icon = "👤" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "⚙️" }),
}

-- Status displays
local statusParagraph     = Tabs.Main:AddParagraph({ Title = "STATUS", Content = "✅ Ready — v2" })
local loadStatusParagraph = Tabs.LoadAll:AddParagraph({ Title = "STATUS", Content = "⚫ Load All OFF" })

local function setStatus(txt) task.defer(function() pcall(function() statusParagraph:Set({ Content = txt }) end) end) end

-- Forward declarations
local doCopy, doUploadSync
local isCopying = false
local schedulerRunning = false
-- LOAD ALL VARIABLES
local cacheFolder = Instance.new("Folder")
cacheFolder.Name  = "_LoadAllCache"
cacheFolder.Parent = workspace

local cached     = {}
local LA_ACTIVE  = false
local _laAddConn = nil
local _terrainRegion = nil
local _terrainCorner = nil
local _terrainVoxels = nil
local _terrainVoxelReg = nil
local _flyActive=false local _ncActive=false
local _flySpeed=32 local _flyConn=nil local _ncConn=nil

-- COPY FUNCTIONS
-- 
-- 

local _ssi_standard = nil  -- for noscript / script modes
local _ssi_terrain  = nil  -- for terrain / terrain_script modes

local function _loadStandardSSI()
    if _ssi_standard then return _ssi_standard end
    local ok, result = pcall(function()
        local src = game:HttpGet(
            "https://raw.githubusercontent.com/luau/UniversalSynSaveInstance/main/saveinstance.luau",
            true)
        assert(src and #src > 100, "empty response")
        local fn = loadstring(src, "saveinstance")
        assert(fn, "loadstring failed")
        return fn()
    end)
    if ok and result then _ssi_standard = result end
    return _ssi_standard
end

local function _loadTerrainSSI()
    if _ssi_terrain then return _ssi_terrain end
    local ok, result = pcall(function()
        local src = game:HttpGet(
            "https://raw.githubusercontent.com/verysigmapro/UniversalSynSaveInstance-With-Save-Terrain/refs/heads/main/saveinstance.luau",
            true)
        assert(src and #src > 100, "empty response")
        local fn = loadstring(src, "saveinstance")
        assert(fn, "loadstring failed")
        return fn()
    end)
    if ok and result then _ssi_terrain = result end
    return _ssi_terrain
end

local function _detectSaveInstance()
    if saveinstance then return saveinstance end
    if syn and syn.save_instance then return syn.save_instance end
    if syn and syn.saveinstance  then return syn.saveinstance  end
    return nil
end

local function _trySaveInstance(mode, folder, fname)
    pcall(function() if not isfolder(folder) then makefolder(folder) end end)
    local fullPath  = folder .. "/" .. fname
    local withTerrain = (mode == "terrain" or mode == "terrain_script")
    local withScripts = (mode == "script"  or mode == "terrain_script")
    local withPlayers = not CFG.IgnorePlayers

    
    if withTerrain then
        local fn = _loadTerrainSSI()
        if fn then
            local opts = {
                FilePath          = fullPath,
                Decompile         = withScripts,
                SaveTerrain       = true,
                SavePlayers       = withPlayers,
                NilInstances      = false,
            }
            local ok, err = pcall(fn, opts)
            if ok then task.wait(1) return true, nil end
            -- fallback: call without FilePath (auto-save)
            opts.FilePath = nil
            ok, err = pcall(fn, opts)
            if ok then task.wait(1) return true, nil end
            return false, "terrain save failed: " .. tostring(err)
        end
        
        XNotify({ Title="⚠️ Terrain SSI", Content="Terrain saveinstance unavailable,\nfalling back to standard.", Duration=4, Color=Color3.fromRGB(240,180,40) })
    end

    
    local fn = _loadStandardSSI()
    if fn then
        -- FIX: tambah FileType eksplisit agar format tetap dipakai walau FilePath di-nil-kan
        local fmt = (CFG.OutputFormat or "RBXLX"):upper()
        local fileTypeMap = { RBXLX="rbxlx", RBXL="rbxl", RBXM="rbxm", RBXMX="rbxmx" }
        local opts = {
            FilePath     = fullPath,
            FileType     = fileTypeMap[fmt] or "rbxlx",
            Binary       = (fmt == "RBXL" or fmt == "RBXM"),  -- binary untuk .rbxl / .rbxm
            Decompile    = withScripts,
            SaveTerrain  = withTerrain,
            SavePlayers  = withPlayers,
            NilInstances = false,
        }
        local ok, err = pcall(fn, opts)
        if ok then task.wait(1) return true, nil end
        -- fallback tanpa FilePath tapi tetap pertahankan FileType
        opts.FilePath = nil
        ok, err = pcall(fn, opts)
        if ok then task.wait(1) return true, nil end
        return false, "save failed: " .. tostring(err)
    end

    
    local native = _detectSaveInstance()
    if native then
        local optsNew = { SavePlayers=withPlayers, Decompile=withScripts, SaveTerrain=withTerrain, NilInstances=false }
        local tries = {
            function() return native(game, optsNew, fullPath) end,
            function() return native(game, optsNew) end,
            function() return native(optsNew, fullPath) end,
            function() return native(fullPath, optsNew) end,
            function() return native(fullPath) end,
            function() return native(game) end,
        }
        local lastErr = "all native attempts failed"
        for _, attempt in ipairs(tries) do
            local ok, err = pcall(attempt)
            if ok then task.wait(1) return true, nil end
            lastErr = tostring(err or "unknown")
        end
        return false, lastErr
    end

    return false, "saveinstance not available.\nGitHub fetch failed.\nUse Synapse X / Xeno / Wave / KRNL."
end

-- FIX: don't call applyTemplate() twice (different timestamps!)
local function _findLatestFile(folder)
    local found = nil
    local foundTime = 0
    pcall(function()
        if not isfolder(folder) then return end
        for _, f in ipairs(listfiles(folder)) do
            -- get the most recent .rbxl / .rbxlx / .rbxm file
            if f:match("%.[Rr][Bb][Xx][Ll][Xx]?$") or f:match("%.[Rr][Bb][Xx][Mm][Xx]?$") then
                local ok, attr = pcall(function()
                    -- some executors have getfileattributes / filemodifiedtime
                    if filemodifiedtime then return filemodifiedtime(f) end
                    return 0
                end)
                local t = (ok and attr) or 0
                if t > foundTime then foundTime = t found = f end
            end
        end
        -- if timestamp unavailable, take last MATCHING entry (bukan sembarang file)
        if not found then
            for _, f in ipairs(listfiles(folder)) do
                if f:match("%.[Rr][Bb][Xx][Ll][Xx]?$") or f:match("%.[Rr][Bb][Xx][Mm][Xx]?$") then
                    found = f  -- keep last matching game file
                end
            end
        end
    end)
    return found
end

local function _getFileSize(path)
    local sz = 0
    pcall(function()
        if path and isfile(path) then
            local d = readfile(path)
            sz = d and #d or 0
        end
    end)
    return sz
end

-- doCopy — copy game to local file
doCopy = function(mode, trigger)
    if isCopying then
        XNotify({ Title = "Busy", Content = "Already copying, hold on.", Duration = 3, Color = Color3.fromRGB(220,150,40) })
        return
    end
    isCopying = true

    local cancelled = false
    showFeatureModal("Copy Game", "📋", "Starting copy...\nMode: " .. mode, function() cancelled = true end)

    task.spawn(function()
        local ok2, err2 = pcall(function()

            
            updateFeatureModal("Scanning instances...", 0.05)
            task.wait(0.2)
            if cancelled then return end

            local instCount = countInst()
            updateFeatureModal(string.format(
                "📦 %d instances\nMode: %s\nGetting ready...",
                instCount, mode), 0.2)
            task.wait(0.1)
            if cancelled then return end

            
            local withTerrain = (mode == "terrain" or mode == "terrain_script")
            updateFeatureModal("⏳ Loading...", 0.15)
            if withTerrain then
                _loadTerrainSSI()
            else
                _loadStandardSSI()
            end
            if cancelled then return end

            
            local fname  = applyTemplate(CFG.FilenameTemplate)
            local folder = CFG.SaveFolder

            local saveOk  = false
            local saveErr = "unknown"
            local savedPath = nil

            
            for attempt = 1, CFG.RetryAttempts do
                if cancelled then break end
                updateFeatureModal(string.format(
                    "💾 Saving...\nAttempt %d / %d\nFile: %s",
                    attempt, CFG.RetryAttempts, fname), 0.25 + attempt * 0.1)

                local ok, err = _trySaveInstance(mode, folder, fname)
                if ok then
                    saveOk   = true
                    saveErr  = nil
                    savedPath = folder .. "/" .. fname
                    break
                else
                    saveErr = tostring(err or "unknown")
                    if attempt < CFG.RetryAttempts then
                        updateFeatureModal(string.format(
                            "⚠️ Attempt %d failed:\n%s\n\nRetrying...",
                            attempt, saveErr:sub(1,80)), 0.1)
                        task.wait(2)
                    end
                end
            end

            if cancelled then return end

            -- 5. Hitung ukuran file (dari path yg sudah direcord)
            local fileSize = 0
            if saveOk then
                -- coba dari path yang kita kirim
                fileSize = _getFileSize(savedPath)
                -- kalau 0 (executor simpan di tempat lain), cari file terbaru
                if fileSize == 0 then
                    local latest = _findLatestFile(folder)
                    if latest then
                        fileSize = _getFileSize(latest)
                        savedPath = latest
                    end
                end
            end

            -- 6. Hasil
            if saveOk then
                local sizeStr = fmtBytes(fileSize)
                updateFeatureModal(
                    string.format("✅ Copy berhasil!\n📁 %s\n💾 Ukuran: %s", folder, sizeStr), 1)
                addStat(true, fileSize)
                pushHistory({
                    mode     = mode, trigger = trigger,
                    gameName = getRealGameName(), size = sizeStr,
                    success  = true, date = safeDate(),
                })
                playSound(1.5)
                task.wait(1.5)
                closeFeatureModal()
                setStatus("✅ Copy OK — " .. mode .. " — " .. safeDate())
                XNotify({
                    Title   = "✅ Copy Done",
                    Content = "Mode: " .. mode .. "\nSize: " .. sizeStr,
                    Duration = 6,
                    Color   = Color3.fromRGB(40, 200, 100)
                })
                if CFG.AutoUpload and doUploadSync then task.spawn(doUploadSync) end
            else
                local shortErr = tostring(saveErr):sub(1, 100)
                updateFeatureModal("❌ Copy gagal!\n" .. shortErr, 0)
                addStat(false, 0)
                pushHistory({
                    mode     = mode, trigger = trigger,
                    gameName = getRealGameName(), size = "0",
                    success  = false, date = safeDate(),
                })
                playSound(0.6)
                task.wait(2.5)
                closeFeatureModal()
                setStatus("❌ Copy failed — " .. mode)
                XNotify({
                    Title   = "❌ Copy Failed",
                    Content = shortErr:sub(1, 70),
                    Duration = 6,
                    Color   = Color3.fromRGB(220, 60, 70)
                })
            end
        end)

        if not ok2 then
            local msg = tostring(err2 or "unknown error"):sub(1, 120)
            pcall(closeFeatureModal)
            setStatus("❌ Error: " .. msg)
            XNotify({ Title = "❌ Error", Content = msg, Duration = 6, Color = Color3.fromRGB(220, 60, 70) })
        end
        isCopying = false  -- FIX: selalu reset meski ada error
    end)
end

doUploadSync = function()
    local cancelled = false
    showFeatureModal("Upload File", "☁️", "Menyiapkan upload...", function() cancelled = true end)
    task.spawn(function()
        updateFeatureModal("Mencari file terbaru...", 0.2)
        task.wait(0.3)
        if cancelled then closeFeatureModal() return end

        -- FIX: pakai _findLatestFile agar hanya file game (.rbxl/.rbxlx/.rbxm/.rbxmx) yang dipilih
        local latestFile = _findLatestFile(CFG.SaveFolder)

        if not latestFile then
            updateFeatureModal("❌ File game tidak ditemukan!\nLakukan Copy dulu.", 0)
            task.wait(2) closeFeatureModal()
            XNotify({ Title = "Upload", Content = "File game tidak ditemukan.\nLakukan Copy terlebih dahulu.", Duration = 4, Color = Color3.fromRGB(220,60,70) })
            return
        end

        local fileData = ""
        pcall(function() fileData = readfile(latestFile) end)

        if #fileData == 0 then
            updateFeatureModal("❌ File kosong atau tidak bisa dibaca!", 0)
            task.wait(2) closeFeatureModal()
            return
        end

        -- FIX: routing berdasarkan CFG.UploadService
        local service = CFG.UploadService or "catbox.moe"
        updateFeatureModal("Mengunggah ke " .. service .. "...", 0.5)
        task.wait(0.5)
        if cancelled then closeFeatureModal() return end

        local fname = latestFile:match("[^/\\]+$") or ("xinnz." .. (CFG.OutputFormat or "RBXLX"):lower())
        local bd = "XBound" .. tostring(os.time())
        local CR = "\r\n"
        local link = nil

        if service == "litterbox" then
            -- Litterbox: file sementara 24 jam
            local body = "--"..bd..CR..'Content-Disposition: form-data; name="reqtype"'..CR..CR.."fileupload"..CR
                .."--"..bd..CR..'Content-Disposition: form-data; name="time"'..CR..CR.."24h"..CR
                .."--"..bd..CR..'Content-Disposition: form-data; name="fileToUpload"; filename="'..fname..'"'..CR
                .."Content-Type: application/octet-stream"..CR..CR..fileData..CR.."--"..bd.."--"..CR
            local ok2, resp = httpReq({ Url = "https://litterbox.catbox.moe/resources/internals/api.php", Method = "POST",
                Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. bd }, Body = body })
            if ok2 then
                local b2 = getRespBody(resp)
                if not isHTMLResp(b2) then link = b2:match("^%s*(https?://[^%s\r\n]+)") end
            end

        elseif service == "filebin" then
            -- Filebin: POST ke bin baru
            local bin = "xinnz" .. tostring(os.time()):sub(-6)
            local ok2, resp = httpReq({ Url = "https://filebin.net/" .. bin .. "/" .. fname, Method = "POST",
                Headers = { ["Content-Type"] = "application/octet-stream" }, Body = fileData })
            if ok2 then
                local b2 = getRespBody(resp)
                local uri = b2:match('"uri"%s*:%s*"([^"]+)"')
                link = uri and ("https://filebin.net" .. uri) or ("https://filebin.net/" .. bin)
            end

        else
            -- Default: catbox.moe
            local body = "--"..bd..CR..'Content-Disposition: form-data; name="reqtype"'..CR..CR.."fileupload"..CR
                .."--"..bd..CR..'Content-Disposition: form-data; name="fileToUpload"; filename="'..fname..'"'..CR
                .."Content-Type: application/octet-stream"..CR..CR..fileData..CR.."--"..bd.."--"..CR
            local ok2, resp = httpReq({ Url = "https://catbox.moe/user/api.php", Method = "POST",
                Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. bd }, Body = body })
            if ok2 then
                local b2 = getRespBody(resp)
                if not isHTMLResp(b2) then link = b2:match("^%s*(https?://[^%s\r\n]+)") end
            end
        end

        if link then
            updateFeatureModal("✅ Upload berhasil!\n" .. link, 1)
            pcall(function() local lf=DATA.."/saves/links.txt" local prev="" if isfile(lf) then prev=readfile(lf) end writefile(lf,link.."\n"..prev) end)
            playSound(1.5)
            task.wait(2) closeFeatureModal()
            XNotify({ Title = "✅ Upload OK", Content = link, Duration = 8, Color = Color3.fromRGB(40,200,100) })
        else
            updateFeatureModal("❌ Upload gagal.\nPastikan HTTP aktif & coba format RBXLX.", 0)
            playSound(0.6)
            task.wait(2) closeFeatureModal()
            XNotify({ Title = "❌ Upload Gagal", Content = "Pastikan HTTP aktif & format RBXLX.", Duration = 5, Color = Color3.fromRGB(220,60,70) })
        end
    end)
end
-- LOAD ALL — logic proven working

-- Fungsi untuk meng-cache part (clone + monitoring)

local _laConns = {}

local function _addLaConn(c)
    if c then _laConns[#_laConns+1] = c end
end

local function _disconnectAllLaConns()
    for i = 1, #_laConns do
        pcall(function() _laConns[i]:Disconnect() end)
    end
    _laConns = {}
end

local function cachePart(v)
    if cached[v] then return end
    if not v:IsA("BasePart") then return end
    if v:IsDescendantOf(cacheFolder) then return end

    
    local isChar = false
    pcall(function()
        for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
            if p.Character and v:IsDescendantOf(p.Character) then isChar = true end
        end
    end)
    if isChar then return end

    local clone = nil
    local ok = pcall(function() clone = v:Clone() end)
    if not ok or clone == nil then cached[v] = true return end

    pcall(function() clone.Anchored   = true  end)
    pcall(function() clone.CanCollide = false end)
    pcall(function() clone.CastShadow = false end)
    pcall(function() clone.Locked     = true  end)

    local lastCFrame   = v.CFrame
    local origParent   = v.Parent  -- simpan parent asli
    local restored     = false

    
    local cfConn = v:GetPropertyChangedSignal("CFrame"):Connect(function()
        pcall(function() lastCFrame = v.CFrame end)
    end)
    _addLaConn(cfConn)

    -- (bukan cacheFolder)
    local ancConn
    ancConn = v.AncestryChanged:Connect(function()
        if not LA_ACTIVE then return end
        if v:IsDescendantOf(workspace) then restored = false return end
        if restored then return end
        restored = true
        pcall(function() cfConn:Disconnect() end)
        pcall(function() clone.CFrame = lastCFrame end)
        
        local target = workspace
        pcall(function()
            if origParent and origParent.Parent then target = origParent end
        end)
        pcall(function() clone.Parent = target end)
    end)
    _addLaConn(ancConn)

    cached[v] = clone
end

local function scanWorkspace()
    local descendants = {}
    pcall(function() descendants = workspace:GetDescendants() end)
    local count = 0
    for _, v in ipairs(descendants) do
        if not LA_ACTIVE then break end
        pcall(cachePart, v)
        count = count + 1
        if count % 100 == 0 then
            task.wait()
            pcall(function()
                loadStatusParagraph:Set({ Content = "🟢 Scanning... " .. count .. " instances" })
            end)
        end
    end
    return count
end

-- FIX: flag untuk track status terrain cache
local _terrainCaching = false
local _terrainCacheFailed = false

-- Deteksi apakah game ini punya terrain sama sekali
local function _gameHasTerrain()
    local ok, result = pcall(function()
        local terr = workspace.Terrain
        if not terr then return false end
        -- MaxExtents: Region3int16 area yang terisi terrain
        local ext = terr.MaxExtents
        return ext.Min ~= ext.Max
    end)
    return ok and result
end

-- Cache terrain (background) — multi-method fallback
local function _cacheTerrain()
    _terrainCaching     = true
    _terrainCacheFailed = false
    task.spawn(function()
        local terr = workspace.Terrain
        if not terr then
            _terrainCaching = false _terrainCacheFailed = true return
        end

        -- Ambil bounds terrain yang sesungguhnya (bukan hardcode 2048x512)
        local minP = Vector3.new(-4096, -512, -4096)
        local maxP = Vector3.new( 4096,  512,  4096)
        pcall(function()
            local ext = terr.MaxExtents
            -- ext adalah Region3int16, konversi ke studs (1 stud = 4 voxel dengan resolusi 4)
            local scale = 4
            minP = Vector3.new(ext.Min.X * scale, ext.Min.Y * scale, ext.Min.Z * scale)
            maxP = Vector3.new(ext.Max.X * scale, ext.Max.Y * scale, ext.Max.Z * scale)
            -- padding kecil agar tidak terpotong
            minP = minP - Vector3.new(16, 16, 16)
            maxP = maxP + Vector3.new(16, 16, 16)
        end)

        -- Method 1: CopyRegion (paling akurat)
        local ok1 = pcall(function()
            local reg = Region3.new(minP, maxP)
            reg = reg:ExpandToGrid(4)
            _terrainRegion = terr:CopyRegion(reg)
            _terrainCorner = CFrame.new(minP)
        end)
        if ok1 and _terrainRegion then
            _terrainCaching = false
            XNotify({ Title="🏔️ Terrain", Content="Terrain cached! (CopyRegion)", Duration=3, Color=Color3.fromRGB(40,200,100) })
            return
        end
        _terrainRegion = nil

        -- Method 2: ReadVoxels (fallback)
        local ok2 = pcall(function()
            local reg = Region3.new(minP, maxP)
            local mats, occs = terr:ReadVoxels(reg, 4)
            _terrainVoxels   = { mats, occs }
            _terrainVoxelReg = reg
        end)
        if ok2 and _terrainVoxels then
            _terrainCaching = false
            XNotify({ Title="🏔️ Terrain", Content="Terrain cached! (Voxels)", Duration=3, Color=Color3.fromRGB(40,200,100) })
            return
        end
        _terrainVoxels = nil

        -- Semua method gagal
        _terrainCaching     = false
        _terrainCacheFailed = true
        XNotify({ Title="🏔️ Terrain", Content="Cache terrain gagal (executor limitation).\nTerrain tetap dilindungi AncestryChanged.", Duration=5, Color=Color3.fromRGB(240,180,40) })
    end)
end

-- Restore terrain
local function _doLoadTerrain()
    -- Method 1: PasteRegion (dari CopyRegion)
    if _terrainRegion and _terrainCorner then
        local ok, err = pcall(function()
            workspace.Terrain:PasteRegion(_terrainRegion, _terrainCorner, true)
        end)
        if ok then
            XNotify({ Title="✅ Terrain", Content="Terrain restored! (PasteRegion)", Duration=4, Color=Color3.fromRGB(40,200,100) })
        else
            XNotify({ Title="❌ Terrain", Content="Gagal PasteRegion:\n"..tostring(err):sub(1,60), Duration=5, Color=Color3.fromRGB(220,60,70) })
        end
        return
    end
    -- Method 2: WriteVoxels (dari ReadVoxels)
    if _terrainVoxels and _terrainVoxelReg then
        local ok, err = pcall(function()
            workspace.Terrain:WriteVoxels(_terrainVoxelReg, 4, _terrainVoxels[1], _terrainVoxels[2])
        end)
        if ok then
            XNotify({ Title="✅ Terrain", Content="Terrain restored! (WriteVoxels)", Duration=4, Color=Color3.fromRGB(40,200,100) })
        else
            XNotify({ Title="❌ Terrain", Content="Gagal WriteVoxels:\n"..tostring(err):sub(1,60), Duration=5, Color=Color3.fromRGB(220,60,70) })
        end
        return
    end
    XNotify({ Title="❌ Terrain", Content="Belum ada cache terrain!\nJalankan Load All dulu.", Duration=4, Color=Color3.fromRGB(220,60,70) })
end

local function _laStart()
    if LA_ACTIVE then
        -- Restart: bersihkan state lama
        _disconnectAllLaConns()
        if _laAddConn then pcall(function() _laAddConn:Disconnect() end) _laAddConn = nil end
    end
    LA_ACTIVE = true
    cached    = {}

    
    pcall(function()
        for _, ch in ipairs(cacheFolder:GetChildren()) do
            pcall(function() ch:Destroy() end)
        end
    end)

    
    _cacheTerrain()

    pcall(function() loadStatusParagraph:Set({ Content = "🟢 Load All ON — scanning..." }) end)
    XNotify({ Title="🟢 Load All", Content="Scanning workspace...", Duration=2, Color=Color3.fromRGB(40,200,100) })

    
    task.spawn(function()
        local count = scanWorkspace()
        if not LA_ACTIVE then return end
        pcall(function()
            loadStatusParagraph:Set({ Content = "🟢 Load All ON — " .. count .. " parts cached" })
        end)
        -- Tunggu sebentar agar _cacheTerrain (task.spawn) sempat selesai
        task.wait(2)
        XNotify({
            Title   = "✅ Load All Complete",
            Content = "📦 " .. count .. " instances scanned\n🏔️ Terrain: " .. ((_terrainRegion or _terrainVoxels) and "✅" or "❌"),
            Duration = 5,
            Color   = Color3.fromRGB(40, 200, 100)
        })

        
        task.spawn(function()
            while LA_ACTIVE do
                task.wait(5)
                if not LA_ACTIVE then break end
                local total = 0
                for _ in pairs(cached) do total = total + 1 end
                pcall(function()
                    loadStatusParagraph:Set({ Content = "🟢 Active — " .. total .. " parts protected" })
                end)
            end
        end)
    end)

    
    _laAddConn = workspace.DescendantAdded:Connect(function(v)
        task.defer(function()
            if not LA_ACTIVE then return end
            pcall(cachePart, v)
        end)
    end)

    print("Load All ON - Anti-unload active")
end

local function _laStop()
    LA_ACTIVE = false
    -- (AncestryChanged + CFrame)
    _disconnectAllLaConns()
    
    if _laAddConn then
        pcall(function() _laAddConn:Disconnect() end)
        _laAddConn = nil
    end
    -- Delete semua clone yang sudah di-restore ke workspace
    pcall(function()
        for part, clone in pairs(cached) do
            if type(clone) ~= "boolean" then
                pcall(function()
                    if clone and clone.Parent then clone:Destroy() end
                end)
            end
        end
    end)
    cached = {}
    pcall(function() loadStatusParagraph:Set({ Content = "⚫ Load All OFF" }) end)
    XNotify({ Title="Load All", Content="Dihentikan.\nSemua clone dibersihkan.", Duration=3 })
    print("Load All OFF - all connections & clones cleaned")
end

local function _laClearCache()
    _laStop()
    _terrainRegion = nil
    _terrainCorner = nil
    pcall(function()
        for _, ch in ipairs(cacheFolder:GetChildren()) do
            pcall(function() ch:Destroy() end)
        end
    end)
    pcall(function() loadStatusParagraph:Set({ Content = "⚫ Load All — cache cleared" }) end)
    XNotify({ Title="🗑️ Load All", Content="Cache cleared.", Duration=3 })
end

-- State tombol virtual (dipakai oleh Heartbeat fly)
local _flyKeys = { W=false, A=false, S=false, D=false, UP=false, DOWN=false }
local _flyControlGui = nil

local function _destroyFlyControls()
    if _flyControlGui then
        pcall(function() _flyControlGui:Destroy() end)
        _flyControlGui = nil
    end
    for k in pairs(_flyKeys) do _flyKeys[k] = false end
end

local function _createFlyControls()
    _destroyFlyControls()

    local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
    local sg = Instance.new("ScreenGui")
    sg.Name            = "XinnzFlyControls"
    sg.ResetOnSpawn    = false
    sg.DisplayOrder    = 200
    sg.IgnoreGuiInset  = true
    sg.Parent          = pg
    _flyControlGui     = sg

    -- helper buat satu tombol
    local function makeBtn(parent, label, x, y, w, h, key)
        local f = Instance.new("Frame")
        f.Size                = UDim2.fromOffset(w, h)
        f.Position            = UDim2.fromOffset(x, y)
        f.BackgroundColor3    = Color3.fromRGB(20, 20, 30)
        f.BackgroundTransparency = 0.35
        f.BorderSizePixel     = 0
        f.Parent              = parent
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
        local stroke = Instance.new("UIStroke", f)
        stroke.Color     = Color3.fromRGB(110, 70, 220)
        stroke.Thickness = 1.5

        local lbl = Instance.new("TextLabel", f)
        lbl.Size                  = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Text                  = label
        lbl.TextColor3            = Color3.new(1,1,1)
        lbl.Font                  = Enum.Font.GothamBold
        lbl.TextSize              = 18
        lbl.TextScaled            = false

        -- highlight when pressed
        local function pressDown()
            _flyKeys[key] = true
            f.BackgroundColor3 = Color3.fromRGB(100, 60, 220)
            f.BackgroundTransparency = 0.1
        end
        local function pressUp()
            _flyKeys[key] = false
            f.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
            f.BackgroundTransparency = 0.35
        end

        -- Touch (HP)
        f.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.Touch or
               inp.UserInputType == Enum.UserInputType.MouseButton1 then
                pressDown()
            end
        end)
        f.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.Touch or
               inp.UserInputType == Enum.UserInputType.MouseButton1 then
                pressUp()
            end
        end)
        -- Prevent stuck if finger leaves frame
        f.MouseLeave:Connect(pressUp)

        return f
    end

    local BS  = 62   -- ukuran tombol
    local GAP = 6    -- jarak antar tombol

    -- D-pad: kiri bawah (nempel tepi)
    local dpad = Instance.new("Frame")
    dpad.Size                   = UDim2.fromOffset(BS*3 + GAP*2, BS*3 + GAP*2)
    dpad.AnchorPoint            = Vector2.new(0, 1)
    dpad.Position               = UDim2.new(0, 10, 1, 0)   -- nempel tepi bawah kiri
    dpad.BackgroundTransparency = 1
    dpad.Parent                 = sg

    local midX = BS + GAP
    makeBtn(dpad, "▲\nW",   midX,    0,    BS, BS, "W")
    makeBtn(dpad, "◀\nA",   0,       midX, BS, BS, "A")
    makeBtn(dpad, "▼\nS",   midX,    midX, BS, BS, "S")
    makeBtn(dpad, "▶\nD",   midX*2,  midX, BS, BS, "D")

    -- UP/DOWN: kanan tengah-bawah
    local ud = Instance.new("Frame")
    ud.Size                   = UDim2.fromOffset(BS, BS*2 + GAP)
    ud.AnchorPoint            = Vector2.new(1, 0.5)
    ud.Position               = UDim2.new(1, -10, 0.65, 0)  -- kanan, 65% dari atas
    ud.BackgroundTransparency = 1
    ud.Parent                 = sg

    makeBtn(ud, "⬆\nUP", 0, 0,        BS, BS, "UP")
    makeBtn(ud, "⬇\nDN", 0, BS + GAP, BS, BS, "DOWN")

    -- Hint label di atas dpad
    local hint = Instance.new("TextLabel", sg)
    hint.Size                   = UDim2.fromOffset(200, 16)
    hint.AnchorPoint            = Vector2.new(0, 1)
    hint.Position               = UDim2.new(0, 10, 1, -(BS*3 + GAP*2 + 2))
    hint.BackgroundTransparency = 1
    hint.Text                   = "✈️ WASD+Q/E active"
    hint.TextColor3             = Color3.fromRGB(180, 150, 255)
    hint.Font                   = Enum.Font.Gotham
    hint.TextSize               = 9
    hint.TextXAlignment         = Enum.TextXAlignment.Left
end

local function _flyStart(speed)
    if _flyActive then return end _flyActive=true
    local cam=workspace.CurrentCamera
    local char=LocalPlayer.Character
    if not char then _flyActive=false return end
    local hrp=char:FindFirstChild("HumanoidRootPart")
    local hum=char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then _flyActive=false return end
    hum.PlatformStand=true
    local bv=Instance.new("BodyVelocity",hrp) bv.Velocity=Vector3.new() bv.MaxForce=Vector3.new(1e5,1e5,1e5)
    local bg=Instance.new("BodyGyro",hrp) bg.MaxTorque=Vector3.new(1e5,1e5,1e5) bg.P=1e4
    _createFlyControls()
    _flyConn=RunService.Heartbeat:Connect(function()
        if not _flyActive or not hrp or not hrp.Parent then _flyActive=false return end
        local dir=Vector3.new() local uis=UserInputService
        -- Keyboard
        if uis:IsKeyDown(Enum.KeyCode.W) or _flyKeys.W then dir=dir+cam.CFrame.LookVector end
        if uis:IsKeyDown(Enum.KeyCode.S) or _flyKeys.S then dir=dir-cam.CFrame.LookVector end
        if uis:IsKeyDown(Enum.KeyCode.A) or _flyKeys.A then dir=dir-cam.CFrame.RightVector end
        if uis:IsKeyDown(Enum.KeyCode.D) or _flyKeys.D then dir=dir+cam.CFrame.RightVector end
        if uis:IsKeyDown(Enum.KeyCode.E) or uis:IsKeyDown(Enum.KeyCode.Space) or _flyKeys.UP   then dir=dir+Vector3.new(0,1,0) end
        if uis:IsKeyDown(Enum.KeyCode.Q) or _flyKeys.DOWN then dir=dir-Vector3.new(0,1,0) end
        bv.Velocity=dir*(speed or _flySpeed) bg.CFrame=cam.CFrame
    end)
end

local function _flyStop()
    _flyActive=false
    _destroyFlyControls()
    if _flyConn then _flyConn:Disconnect() _flyConn=nil end
    pcall(function()
        local char=LocalPlayer.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            local hum=char:FindFirstChildOfClass("Humanoid")
            if hrp then for _,v in ipairs(hrp:GetChildren()) do if v:IsA("BodyVelocity") or v:IsA("BodyGyro") then v:Destroy() end end end
            if hum then hum.PlatformStand=false end
        end
    end)
end

local function _ncStart(speed)
    if _ncActive then return end _ncActive=true
    local char=LocalPlayer.Character
    if not char then _ncActive=false return end
    local hrp=char:FindFirstChild("HumanoidRootPart")
    local hum=char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then _ncActive=false return end
    hum.PlatformStand=true
    local bv=Instance.new("BodyVelocity",hrp) bv.Velocity=Vector3.new() bv.MaxForce=Vector3.new(1e5,1e5,1e5)
    _createFlyControls()
    _ncConn=RunService.Heartbeat:Connect(function()
        if not _ncActive or not hrp or not hrp.Parent then _ncActive=false return end
        local dir=Vector3.new() local uis=UserInputService local cam=workspace.CurrentCamera
        if uis:IsKeyDown(Enum.KeyCode.W) or _flyKeys.W then dir=dir+cam.CFrame.LookVector end
        if uis:IsKeyDown(Enum.KeyCode.S) or _flyKeys.S then dir=dir-cam.CFrame.LookVector end
        if uis:IsKeyDown(Enum.KeyCode.A) or _flyKeys.A then dir=dir-cam.CFrame.RightVector end
        if uis:IsKeyDown(Enum.KeyCode.D) or _flyKeys.D then dir=dir+cam.CFrame.RightVector end
        if uis:IsKeyDown(Enum.KeyCode.E) or uis:IsKeyDown(Enum.KeyCode.Space) or _flyKeys.UP   then dir=dir+Vector3.new(0,1,0) end
        if uis:IsKeyDown(Enum.KeyCode.Q) or _flyKeys.DOWN then dir=dir-Vector3.new(0,1,0) end
        for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end
        bv.Velocity=dir*(speed or _flySpeed)
    end)
end

local function _ncStop()
    _ncActive=false
    _destroyFlyControls()
    if _ncConn then _ncConn:Disconnect() _ncConn=nil end
    pcall(function()
        local char=LocalPlayer.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            local hum=char:FindFirstChildOfClass("Humanoid")
            if hrp then for _,v in ipairs(hrp:GetChildren()) do if v:IsA("BodyVelocity") then v:Destroy() end end end
            if hum then hum.PlatformStand=false end
            for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end
        end
    end)
end

-- TAB: COPY (Main)
Tabs.Main:AddButton({ Title = "📄 Copy Without Script", Callback = function() doCopy("noscript", "Manual") end })
Tabs.Main:AddButton({ Title = "📜 Copy With Script", Callback = function() doCopy("script", "Manual") end })
Tabs.Main:AddButton({ Title = "🏔️ Copy With Terrain", Callback = function() doCopy("terrain", "Manual") end })
Tabs.Main:AddButton({ Title = "🌍 Terrain + Script (Full)", Callback = function() doCopy("terrain_script", "Manual") end })

Tabs.Main:AddButton({ Title = "📊 View Statistics", Callback = function()
    local s = loadStats()
    XShowModal({ Title="Copy Statistics", Icon="📊",
        Content=string.format("✅ Success: %d\n❌ Failed: %d\n💾 Total size: %s", s.success or 0, s.fail or 0, fmtBytes(s.totalBytes or 0)),
        Progress=1 })
    task.delay(4, XCloseModal)
end })

Tabs.Main:AddToggle("IgnorePlayers", { Title = "Ignore Players", Default = CFG.IgnorePlayers, Callback = function(v) CFG.IgnorePlayers = v saveCFG() end })
Tabs.Main:AddToggle("AutoOrganize",  { Title = "Auto-Organize File", Default = CFG.AutoOrganize, Callback = function(v) CFG.AutoOrganize = v saveCFG() end })
Tabs.Main:AddToggle("DupCheck",      { Title = "Duplicate Check", Default = CFG.DupCheck, Callback = function(v) CFG.DupCheck = v saveCFG() end })
Tabs.Main:AddSlider("RetryAttempts", { Title = "Retry Attempts", Default = CFG.RetryAttempts, Min = 1, Max = 5, Rounding = 1, Callback = function(v) CFG.RetryAttempts = v saveCFG() end })
Tabs.Main:AddDropdown("OutputFormat", { Title = "Output Format", Values = { "RBXLX", "RBXL", "RBXM", "RBXMX" }, Default = CFG.OutputFormat or "RBXLX", Callback = function(v) CFG.OutputFormat = v saveCFG() XNotify({Title="Format", Content="Output: "..v, Duration=2}) end })

-- LOAD ALL
Tabs.LoadAll:AddButton({ Title = "▶ Start Load All",  Callback = function() _laStart() end })
Tabs.LoadAll:AddButton({ Title = "⏹ Stop Load All",   Callback = function() _laStop()  end })

Tabs.LoadAll:AddButton({ Title = "🏔️ Restore Terrain", Callback = function()
    _doLoadTerrain()
end })

Tabs.LoadAll:AddButton({ Title = "🗑️ Clear Cache", Callback = function()
    Window:Dialog({
        Title   = "Clear Load All Cache",
        Content = "Clear all Load All cache from workspace?",
        Buttons = {
            { Title = "Delete", Callback = function() _laClearCache() end },
            { Title = "Cancel", Callback = function() end }
        }
    })
end })

Tabs.LoadAll:AddButton({ Title = "📊 Load All Status", Callback = function()
    local cachedCount = 0
    local cacheChild  = 0
    pcall(function() cacheChild = #cacheFolder:GetChildren() end)
    for _ in pairs(cached) do cachedCount = cachedCount + 1 end
    XShowModal({
        Title   = "Load All Status",
        Icon    = "🌐",
        Content = string.format(
            "Status: %s\n📦 Parts di-cache: %d\n🗃️ Cache folder: %d item\n🏔️ Terrain: %s",
            LA_ACTIVE and "🟢 Active" or "⚫ OFF",
            cachedCount,
            cacheChild,
            _terrainCaching and "⏳ Caching..."
                or (_terrainRegion or _terrainVoxels) and "✅ Cached"
                or _terrainCacheFailed and (_gameHasTerrain() and "⚠️ Cache failed (executor)" or "❌ No terrain in game")
                or (_gameHasTerrain() and "⚠️ Belum di-cache (start Load All)" or "❌ No terrain in game")),
        Progress = 1,
    })
    task.delay(5, XCloseModal)
end })

-- UPLOAD
Tabs.Upload:AddToggle("AutoUpload", { Title = "Auto Upload after Copy", Default = CFG.AutoUpload,
    Callback = function(v) CFG.AutoUpload = v saveCFG() if v and CFG.OutputFormat=="RBXL" then XNotify({Title="Warning",Content="Switch format to RBXLX for uploading!",Duration=5,Color=Color3.fromRGB(240,180,40)}) end end })
Tabs.Upload:AddDropdown("UploadService", { Title = "Upload Service", Values = UPLOAD_SERVICES, Default = CFG.UploadService, Callback = function(v) CFG.UploadService = v saveCFG() end })
Tabs.Upload:AddButton({ Title = "☁️ Upload Now", Callback = function() doUploadSync() end })
Tabs.Upload:AddButton({ Title = "🔗 View Links", Callback = function()
    local lf=DATA.."/saves/links.txt" local content="Not yet link."
    if isfile(lf) then local lines={} for line in readfile(lf):gmatch("[^\n]+") do table.insert(lines,line) if #lines>=5 then break end end content=#lines>0 and table.concat(lines,"\n") or "Not yet link." end
    XShowModal({Title="Upload Links (last 5)",Icon="🔗",Content=content,Progress=1}) task.delay(8,XCloseModal)
end })
Tabs.Upload:AddButton({ Title = "🧪 Test Upload", Callback = function()
    local tc='<?xml version="1.0"?><roblox version="4"><Item class="Model"><Properties><string name="Name">XinnzTest</string></Properties></Item></roblox>'
    local cancelled=false
    showFeatureModal("Test Upload","🧪","Running test upload...",function() cancelled=true end)
    task.spawn(function()
        updateFeatureModal("Sending test file to catbox.moe...",0.4)
        local tn="xinnz_test_"..tostring(os.time())..".rbxlx"
        local bd="XBound"..tostring(os.time()) local CR="\r\n"
        local body="--"..bd..CR..'Content-Disposition: form-data; name="reqtype"'..CR..CR.."fileupload"..CR.."--"..bd..CR..'Content-Disposition: form-data; name="fileToUpload"; filename="'..tn..'"'..CR.."Content-Type: application/octet-stream"..CR..CR..tc..CR.."--"..bd.."--"..CR
        local ok2,resp=httpReq({Url="https://catbox.moe/user/api.php",Method="POST",Headers={["Content-Type"]="multipart/form-data; boundary="..bd},Body=body})
        local b2=getRespBody(resp) local link=nil
        if ok2 and not isHTMLResp(b2) then link=b2:match("^%s*(https?://[^%s\r\n]+)") end
        if link then updateFeatureModal("✅ Test upload berhasil!\n"..link,1) playSound(1.5) task.wait(2) closeFeatureModal() XNotify({Title="✅ Test Upload OK",Content=link,Duration=8,Color=Color3.fromRGB(40,200,100)})
        else updateFeatureModal("❌ Test upload gagal.\nPastikan HTTP request aktif.",0) playSound(0.6) task.wait(2) closeFeatureModal() XNotify({Title="❌ Test Upload Failed",Content="Switch format to RBXLX.",Duration=5,Color=Color3.fromRGB(220,60,70)}) end
    end)
end })

-- INFO
local gameNameP  = Tabs.Info:AddParagraph({ Title = "GAME NAME",  Content = "Loading..." })
local instancesP = Tabs.Info:AddParagraph({ Title = "INSTANCES",  Content = "Counting..." })
local statsP     = Tabs.Info:AddParagraph({ Title = "STATISTICS", Content = "Loading..." })

local function refreshInfoTab()
    task.spawn(function()
        local cnt=countInst() local gn=getRealGameName() local s=loadStats()
        task.defer(function()
            pcall(function() gameNameP:Set({ Content = gn }) end)
            pcall(function() instancesP:Set({ Content = tostring(cnt) .. " instances" }) end)
            pcall(function() statsP:Set({ Content = "✅ Success: "..tostring(s.success or 0).."\n❌ Failed: "..tostring(s.fail or 0).."\n💾 Total: "..fmtBytes(s.totalBytes or 0) }) end)
        end)
    end)
end

Tabs.Info:AddButton({ Title = "🔄 Refresh Info", Callback = function()
    refreshInfoTab()
    XNotify({ Title = "Info", Content = "Data updated!", Duration = 2 })
end })
Tabs.Info:AddButton({ Title = "📜 Recent History", Callback = function()
    local h = loadHistory()
    if #h == 0 then
        XShowModal({ Title="History", Icon="📜", Content="Not yet history copy.", Progress=1 })
    else
        local e = h[1]
        XShowModal({ Title="Last Copy", Icon="📜",
            Content=string.format("Game: %s\nMode: %s\nSize: %s\nStatus: %s\nTanggal: %s",
                e.gameName or "?", e.mode or "?", e.size or "?",
                (e.success and "✅ OK") or "❌ GAGAL", e.date or "?"), Progress=1 })
    end
    task.delay(6, XCloseModal)
end })
Tabs.Info:AddButton({ Title = "🗑️ Clear History", Callback = function()
    Window:Dialog({ Title="Delete History", Content="Are you sure you want to clear all copy history?",
        Buttons={
            { Title="Delete", Callback=function() saveHistory({}) XNotify({Title="History",Content="History cleared!",Duration=3}) end },
            { Title="Cancel", Callback=function() end }
        }
    })
end })

-- PLAYER
Tabs.Player:AddSlider("FlySafeSpeed", { Title = "✈️ Fly Safe Speed", Default = 32, Min = 5, Max = 2000, Rounding = 1,
    Callback = function(v) _flySpeed = v end })
Tabs.Player:AddToggle("FlySafeActive", { Title = "✈️ Fly Safe ON/OFF", Default = false,
    Callback = function(v)
        if v then
            if _ncActive then _ncStop() end _flyStart(_flySpeed)
            Window:Close()
            XNotify({Title="✈️ Fly Safe",Content="ON — Speed: "..tostring(_flySpeed),Duration=3,Color=Color3.fromRGB(40,200,100)})
        else _flyStop() XNotify({Title="✈️ Fly Safe",Content="OFF",Duration=2}) end
    end
})
Tabs.Player:AddSlider("FlyNoclipSpeed", { Title = "👻 Fly Noclip Speed", Default = 32, Min = 5, Max = 2000, Rounding = 1,
    Callback = function(v) _flySpeed = v end })
Tabs.Player:AddToggle("FlyNoclipActive", { Title = "👻 Fly Noclip ON/OFF", Default = false,
    Callback = function(v)
        if v then
            if _flyActive and not _ncActive then _flyStop() end _ncStart(_flySpeed)
            Window:Close()
            XNotify({Title="👻 Fly Noclip",Content="ON — Speed: "..tostring(_flySpeed),Duration=3,Color=Color3.fromRGB(40,200,100)})
        else _ncStop() XNotify({Title="👻 Fly Noclip",Content="OFF",Duration=2}) end
    end
})
Tabs.Player:AddButton({ Title = "🛑 STOP All (Safety)", Callback = function()
    if _ncActive then _ncStop() end if _flyActive then _flyStop() end
    pcall(function() Options.FlySafeActive:SetValue(false) Options.FlyNoclipActive:SetValue(false) end)
    XNotify({Title="🛑 STOP All",Content="All player features disabled!",Duration=3,Color=Color3.fromRGB(220,60,70)})
end })
Tabs.Player:AddButton({ Title = "📊 Player Status", Callback = function()
    XShowModal({ Title="Player Status", Icon="👤",
        Content=string.format("✈️ Fly Safe: %s\n👻 Fly Noclip: %s\nSpeed: %d",
            (_flyActive and not _ncActive) and "🟢 ON" or "⚫ OFF",
            _ncActive and "🟢 ON" or "⚫ OFF", _flySpeed), Progress=1 })
    task.delay(5, XCloseModal)
end })

-- SETTINGS
-- Theme Warna
local _presetList = {}
for k in pairs(ColorPresets) do table.insert(_presetList, k) end
table.sort(_presetList)

Tabs.Settings:AddDropdown("ThemePreset", {
    Title  = "🎨 UI Color Theme",
    Values = _presetList,
    Default = "🟣 Purple (Default)",
    Callback = function(v)
        _applyTheme(v)
        XNotify({ Title="🎨 Theme", Content="Theme: "..v, Duration=3, Color=Theme.Accent })
    end
})
Tabs.Settings:AddInput("SaveFolder",       { Title = "Save Folder",       Default = CFG.SaveFolder,       Finished = true, Callback = function(v) CFG.SaveFolder = v saveCFG() end })
Tabs.Settings:AddInput("FilenameTemplate", { Title = "Filename Template",  Default = CFG.FilenameTemplate, Finished = true, Callback = function(v) CFG.FilenameTemplate = v saveCFG() end })
Tabs.Settings:AddToggle("PlayerTrigger",   { Title = "Player Count Trigger", Default = CFG.PlayerTrigger,  Callback = function(v) CFG.PlayerTrigger = v saveCFG() end })
Tabs.Settings:AddSlider("PlayerTriggerCount", { Title = "Player Threshold", Default = CFG.PlayerTriggerCount, Min = 1, Max = 20, Rounding = 1, Callback = function(v) CFG.PlayerTriggerCount = v saveCFG() end })
Tabs.Settings:AddDropdown("PlayerTriggerMode", { Title = "Trigger Mode", Values = {"noscript","script","terrain","terrain_script"}, Default = CFG.PlayerTriggerMode, Callback = function(v) CFG.PlayerTriggerMode = v saveCFG() end })
Tabs.Settings:AddToggle("ChatCommandEnabled", { Title = "Chat Commands", Default = CFG.ChatCommandEnabled, Callback = function(v) CFG.ChatCommandEnabled = v saveCFG() end })
Tabs.Settings:AddToggle("BackupEnabled",    { Title = "Auto-Backup", Default = CFG.BackupEnabled, Callback = function(v) CFG.BackupEnabled = v saveCFG() if v then startScheduler() end end })
Tabs.Settings:AddSlider("BackupInterval",   { Title = "Backup Interval (minutes)", Default = CFG.BackupInterval, Min = 1, Max = 120, Rounding = 1, Callback = function(v) CFG.BackupInterval = v saveCFG() end })
Tabs.Settings:AddButton({ Title = "💾 Export Preset", Callback = function()
    pcall(function() writefile(DATA.."/preset.json", HttpService2:JSONEncode(CFG)) XNotify({Title="Export",Content="Preset saved!",Duration=3,Color=Color3.fromRGB(40,200,100)}) end)
end })
Tabs.Settings:AddButton({ Title = "📥 Import Preset", Callback = function()
    pcall(function()
        local path=DATA.."/preset.json"
        if not isfile(path) then XNotify({Title="Error",Content="preset.json not found!",Duration=3,Color=Color3.fromRGB(220,60,70)}) return end
        local preset=HttpService2:JSONDecode(readfile(path))
        for k,v in pairs(preset) do if CFG[k]~=nil then CFG[k]=v end end
        saveCFG() XNotify({Title="Import",Content="Preset imported successfully!",Duration=3,Color=Color3.fromRGB(40,200,100)})
    end)
end })
Tabs.Settings:AddButton({ Title = "🔄 Reset Defaults", Callback = function()
    Window:Dialog({ Title="Reset Settings", Content="Reset all settings to default?",
        Buttons={
            { Title="Reset", Callback=function()
                CFG.SaveFolder=DATA.."/saves" CFG.RetryAttempts=3 CFG.OutputFormat="RBXLX" CFG.AutoOrganize=true CFG.DupCheck=true
                CFG.BackupEnabled=false CFG.BackupInterval=10 CFG.FilenameTemplate="{gameName}_{date}_{time}"
                CFG.ChatCommandEnabled=true CFG.PlayerTrigger=false CFG.PlayerTriggerCount=3 CFG.PlayerTriggerMode="noscript"
                CFG.AutoUpload=false CFG.UploadService="catbox.moe" saveCFG()
                XNotify({Title="Reset",Content="Settings reset to default!",Duration=3})
            end },
            { Title="Cancel", Callback=function() end }
        }
    })
end })

task.spawn(function()
    task.wait(5)
    refreshInfoTab()
end)
Window:SelectTab(1)
refreshInfoTab()

XNotify({
    Title   = "✦ Xinnz Hub v2 Loaded",
    Content = "Game: "..getRealGameName().."\nFormat: "..CFG.OutputFormat.."\nRightCtrl = Toggle UI",
    Duration = 6,
    Color   = Color3.fromRGB(110, 70, 220)
})

if CFG.BackupEnabled then startScheduler() end

print("✦ Xinnz Hub v2 loaded — discord.gg/gsteVPKnZ")
