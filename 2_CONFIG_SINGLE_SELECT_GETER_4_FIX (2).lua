--[[
    KERANGKA MENU TAB -> WindUI (VERSI FINAL)
    Urutan sesuai permintaan terbaru - 11 tab, TIDAK di-flatten lagi.
    Automation & Reroll masing-masing CUMA 1 tab (sub-fitur di dalamnya diatur
    pakai Section/Group nanti waktu pengisian fungsi, bukan dipecah jadi tab sidebar).

    Tambahan: profil user (avatar + username Roblox asli) di pojok kiri-bawah sidebar,
    di bawah tab Theme - pakai config native `User` WindUI (pengganti CreateUserProfile()
    di baris 1132-1172 source asli).

    Pemetaan tab -> baris source asli (referensi buat pengisian fungsi nanti):
      1. Main        -> PANEL: MAIN (3812)
      2. Hide         -> PANEL: HIDE (5171)
      3. Farm         -> PANEL: FARM (5571)
      4. Mass Attack  -> PANEL: ATTACK (6785)
      5. Automation   -> Auto Raid (13577), Auto Ascension (14700), Auto Siege (16029),
                         Single Tower Map2 (17293), Join To Tower (17486), Join To Raid (17800)
      6. Reroll       -> Hero Fastroll (7241), Weapon Fastroll (7633), Pet Gear (8002),
                         Halo (8217), Ornament (8311)
      7. Player       -> PANEL: PLAYER (7022)
      8. Setting      -> PANEL: SETTINGS (19002)
      9. Webhook      -> PANEL: WEBHOOK (19113)
      10. Config      -> PANEL: CONFIG (20199)
      11. Theme       -> PANEL: THEME (21364)

      [belum dipetakan ke tab mana - tunggu instruksi]: Claim Reward (18167),
        Anniversary Celebration (18475) -- kemungkinan masuk ke dalam tab Main atau
        tab tersendiri, BELUM ditentukan di list barumu. Tanya saya nanti kalau sudah sampai sana.

    [v3] PENAMBAHAN ke tab Main:
      - COUNTER AUTO SELL HERO EQUIP  (Paragraph: R/Y/B/Supreme + Button RESET COUNTER)
      - AUTO SELL HERO EQUIP          (Toggle + seluruh logika sell)
        Logika: StartAutoSell, scanGuidNames, getType, getGrade, shouldSell, doSell,
                _sellToggleCb, global expose _setSellHeroToggle/_visSellHero/_autoSellOnState
      - Status info via Paragraph yang diupdate realtime

    [v4] PENAMBAHAN ke tab Main:
      - AUTO COLLECT GOLD & ITEM      (Toggle + seluruh logika collect)
        Dependency chain:
          _collectObj           (baris ~486)  - TP obj ke player + fire CollectItem/ExtraReward
          _instantCollectConns  (baris ~483)  - tabel koneksi instant collector
          _instantCollected     (baris ~484)  - dedup cache instant collector
          StartInstantGoldCollector (baris ~511) - listen ChildAdded per folder
          _goldMagnetRunning    (baris ~2420) - flag magnet loop
          StartGoldMagnet       (baris ~2421) - loop TP semua item ke player tiap 0.05s
          StopGoldMagnet        (baris ~2468) - stop magnet loop
          DoAutoCollect         (baris ~2720) - polling loop collect via StartLoop
          DoAutoCollectGoldItem (baris ~2472) - master toggle: panggil semua di atas
        Global expose: _setAutoCollectToggle, _visAutoCollect, _autoCollectState
        Dependency global: STATE, LOOPS, COLLECTED, RE, LP, PG_Wait, StartLoop, StopLoop
--]]

--  SERVICES 
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LP                = Players.LocalPlayer

-- [WELCOME] Notifikasi sederhana saat script mulai jalan
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "FLa",
        Text = "Welcome back!",
        Duration = 4,
    })
end)

-- ============================================================================
-- [PERF] FETCH WINDUI PARALEL (dimulai paling awal, sebelum WaitForChild
-- remote di bawah). HttpGet jalan di thread terpisah lewat task.spawn,
-- jadi selagi thread utama nunggu PlayerGui/Remotes/dll, network request
-- WindUI sudah jalan bareng2 -- bukan antre bergantian kayak versi lama.
-- Hasil (module WindUI atau error) ditampung di _WindUIFetch, dan baru
-- di-"join" (ditunggu) tepat sebelum CreateWindow dipanggil nanti.
-- Tidak ada perubahan pada CARA WindUI dipakai, cuma KAPAN fetch-nya mulai.
-- ============================================================================
local _WindUIFetch = { done = false, ok = false, module = nil, err = nil }
task.spawn(function()
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/mhankbe/WindUi/refs/heads/main/dist/main.lua"))()
    end)
    _WindUIFetch.ok     = ok
    _WindUIFetch.module = ok and result or nil
    _WindUIFetch.err    = (not ok) and result or nil
    _WindUIFetch.done   = true
end)

local PG                = LP:WaitForChild("PlayerGui", 30)
if not PG then
    error("[FLa] PlayerGui tidak ketemu dalam 30 detik - coba execute ulang setelah masuk game sepenuhnya.")
end

local Remotes           = ReplicatedStorage:WaitForChild("Remotes", 30)
if not Remotes then
    error("[FLa] Folder 'Remotes' tidak ketemu dalam 30 detik - coba tunggu lebih lama setelah masuk game sebelum execute.")
end


--  BLOCK ANIMATION TOTAL (GLOBAL, independen RA/TA) 
-- Menstop + mencegah SEMUA AnimationTrack di 3 kategori:
--   1. PLAYER   (LP.Character)
--   2. HEROS    (workspace.Heros)
--   3. ENEMIES  (semua folder musuh yang dipakai script ini: Bosses, Boss,
--                RaidBoss, Enemys, Enemy, Enemies, RaidEnemys, Monsters,
--                Monster, EnemyCityRaid, CityRaidEnemys)
-- Menghapus warning "Failed to play animation: rbxassetid://..." dengan cara
-- menstop track SEBELUM asset selesai/gagal di-load, dan terus-menerus
-- menyapu Animator baru (hero/enemy baru spawn, player respawn).
-- HANYA menstop/menghapus AnimationTrack -- tidak menyentuh remote/fire
-- attack logic, jadi TIDAK mengganggu fungsi serang RA/TA/MA manapun.
-- Aktif dari awal script jalan, tidak bergantung pada state RA/TA/MA.
local _animBlockConns = {}

local function _blockAnimTrack(animator)
    if not animator or not animator:IsA("Animator") then return end
    pcall(function()
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function() track:Stop(0) end)
        end
    end)
    table.insert(_animBlockConns, animator.AnimationPlayed:Connect(function(track)
        pcall(function() track:Stop(0) end)
    end))
end

local function _hookAnimatorsIn(root)
    if not root then return end
    -- pasang di semua Animator yang sudah ada
    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("Animator") then
            _blockAnimTrack(desc)
        end
    end
    -- pasang di Animator baru (spawn/respawn baru)
    table.insert(_animBlockConns, root.DescendantAdded:Connect(function(desc)
        if desc:IsA("Animator") then
            _blockAnimTrack(desc)
        end
    end))
end

local _ANIM_ENEMY_FOLDER_NAMES = {
    "Bosses", "Boss", "RaidBoss", "Enemys", "Enemy", "Enemies",
    "RaidEnemys", "Monsters", "Monster", "EnemyCityRaid", "CityRaidEnemys",
}

local function _hookEnemyAnimFolders()
    for _, fname in ipairs(_ANIM_ENEMY_FOLDER_NAMES) do
        local f = workspace:FindFirstChild(fname)
        if f then
            _hookAnimatorsIn(f)
        end
    end
    -- pasang juga di workspace langsung, jaga-jaga folder musuh baru muncul
    -- belakangan (folder itu sendiri belum ada saat script pertama jalan)
    table.insert(_animBlockConns, workspace.ChildAdded:Connect(function(child)
        for _, fname in ipairs(_ANIM_ENEMY_FOLDER_NAMES) do
            if child.Name == fname then
                _hookAnimatorsIn(child)
                break
            end
        end
    end))
end

local function _hookHeroAnimFolder()
    local herosFolder = workspace:FindFirstChild("Heros")
    if not herosFolder then
        herosFolder = workspace:WaitForChild("Heros", 30)
    end
    if herosFolder then
        _hookAnimatorsIn(herosFolder)
    end
end

local function _hookPlayerAnim()
    local function hookChar(char)
        if not char then return end
        _hookAnimatorsIn(char)
    end
    hookChar(LP.Character)
    table.insert(_animBlockConns, LP.CharacterAdded:Connect(function(char)
        hookChar(char)
    end))
end

task.spawn(function()
    pcall(_hookHeroAnimFolder)
end)
task.spawn(function()
    pcall(_hookEnemyAnimFolders)
end)
task.spawn(function()
    pcall(_hookPlayerAnim)
end)

-- [FIX 64-TRACK LIMIT] Listener reaktif (AnimationPlayed) saja tidak cukup:
-- attack loop RA/TA/Auto-Raid fire remote sampai tiap 0.001s, jadi banyak
-- animasi bisa ke-play beruntun DALAM 1 FRAME YANG SAMA, sebelum listener
-- sempat men-Stop() satu-per-satu -> track menumpuk lebih cepat dari proses
-- stop-nya dan tetap kena limit keras 64/Animator ("AnimationTrack limit of
-- 64 tracks exceeded"). Solusi: proactive polling loop yang jalan TERUS dari
-- awal script (independen RA/TA/MA), menyapu SEMUA Animator yang sedang
-- playing track di Player + Heros + semua folder Enemy setiap ~0.03 detik.
local function _sweepAnimatorsIn(root)
    if not root then return end
    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("Animator") then
            local tracks = desc:GetPlayingAnimationTracks()
            if #tracks > 0 then
                for _, track in ipairs(tracks) do
                    pcall(function() track:Stop(0) end)
                end
            end
        end
    end
end

task.spawn(function()
    while true do
        pcall(function()
            _sweepAnimatorsIn(LP.Character)
            _sweepAnimatorsIn(workspace:FindFirstChild("Heros"))
            for _, fname in ipairs(_ANIM_ENEMY_FOLDER_NAMES) do
                _sweepAnimatorsIn(workspace:FindFirstChild(fname))
            end
        end)
        task.wait(0.03)
    end
end)

--  GLOBALS FARM (dibutuhkan StartRA / TA) 
HERO_GUIDS       = HERO_GUIDS or {}
HERO_DATA        = HERO_DATA  or {}
_walkSpeedState  = _walkSpeedState or 16
MY_USER_ID       = MY_USER_ID or LP.UserId

function IsValidUUID(str)
    if type(str) ~= "string" then return false end
    return str:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

--  GLOBALS BERSAMA (dibutuhkan AUTO COLLECT dan fitur lain) 
-- Source asli baris ~1504
STATE = {
    autoCollect         = false,
    autoCollectGoldItem = false,
    autoDestroyer       = false,
    autoArise           = false,
    noClip              = false,
    antiAfk             = false,
    autoConfirm         = false,
    autoClose           = false,
}
LOOPS     = {}  -- { [key] = thread } - dikelola StopLoop/StartLoop
COLLECTED = {}  -- dedup cache collect loop

--  StopLoop / StartLoop 
-- Source asli baris ~1507-1516
function StopLoop(key)
    if LOOPS[key] then
        pcall(function() task.cancel(LOOPS[key]) end)
        LOOPS[key] = nil
    end
end

function StartLoop(key, fn)
    StopLoop(key)
    LOOPS[key] = task.spawn(fn)
end

--  PG_Wait (Adaptive PingGuard wait) 
-- Source asli baris ~1588-1594
-- Fallback ke 1x kalau PG_Multiplier() belum ada (kerangka standalone).
-- Saat digabung ke script utama, PG_Multiplier() dari script utama yang dipakai.
if not PG_Wait then
    function PG_Wait(baseTime)
        local mult = (type(PG_Multiplier) == "function") and PG_Multiplier() or 1
        local t = (baseTime or 0.05) * mult
        if t > 5 then t = 5 end
        task.wait(t)
    end
end

--  RE: Remote Events / Functions 
-- Source asli baris ~443-477
-- Hanya remote yang dibutuhkan fitur di kerangka ini.
-- Remote lain (HeroUseSkill, Atk, dll) ditambahkan saat panel lain masuk.
RE = RE or {}
RE.CollectItem      = RE.CollectItem      or Remotes:WaitForChild("CollectItem", 10)
RE.ExtraReward      = RE.ExtraReward      or Remotes:WaitForChild("ExtraReward", 10)
RE.Click            = RE.Click            or Remotes:FindFirstChild("ClickEnemy")
RE.Atk              = RE.Atk              or Remotes:FindFirstChild("PlayerClickAttackSkill")
RE.Death            = RE.Death            or Remotes:FindFirstChild("EnemyDeath")
RE.HeroMove         = RE.HeroMove         or Remotes:FindFirstChild("HeroMoveToEnemyPos")
RE.HeroStand        = RE.HeroStand        or Remotes:FindFirstChild("HeroStandTo")
RE.HeroSkill        = RE.HeroSkill        or Remotes:FindFirstChild("HeroPlaySkillAnim")
RE.HeroUseSkill     = RE.HeroUseSkill     or Remotes:FindFirstChild("HeroUseSkill")
RE.StartTp          = RE.StartTp          or Remotes:FindFirstChild("StartLocalPlayerTeleport")
RE.LocalTp          = RE.LocalTp          or Remotes:FindFirstChild("LocalPlayerTeleport")
-- ============================================================================
-- [PERF] REROLL REMOTES -> LAZY RESOLVE
-- 6 remote di bawah (Hero/Weapon/PetGear Fastroll + Halo + Ornament) cuma
-- dipakai di fitur Reroll (baris ~12887-14571), jauh di bawah sini. Daripada
-- WaitForChild semuanya di awal script (nunggu 10-15 detik masing2 kalau
-- server telat bikin remote-nya, padahal user belum tentu buka tab Reroll),
-- kita resolve baru saat PERTAMA KALI dibutuhkan lewat ResolveRE().
-- Pola RE.X = RE.X or ... yang lama TETAP terjaga (idempotent, aman dipanggil
-- berkali-kali), cuma titik eksekusinya dipindah ke titik pakai. Fitur lain
-- (CollectItem/ExtraReward/dll di bawah) TIDAK disentuh, tetap eager seperti
-- semula karena bisa aktif dari awal (instant collector / gold magnet).
-- ============================================================================
function ResolveRE(key, remoteName, timeout)
    if RE[key] then return RE[key] end
    RE[key] = Remotes:WaitForChild(remoteName, timeout or 10)
    return RE[key]
end

-- ============================================================================
-- GLOBAL: SafeReequipAfterTeleport
-- Dipanggil OTOMATIS setelah SETIAP fitur teleport (Mass Attack, Auto Raid,
-- Auto Raid Ascension, Auto Siege, Join To Raid
-- Player) berhasil memasukkan/memindahkan Player.
-- Urutan wajib: UnequipAllHero -> jeda singkat -> AutoEquipBestHero.
-- Tidak ada UI/Toggle -- selalu aktif kapanpun fitur di atas ON.
-- Guard _SafeReequipBusy mencegah overlap kalau dipanggil beruntun cepat.
-- ============================================================================
_SafeReequipBusy = false
function SafeReequipAfterTeleport(tag)
    if _SafeReequipBusy then return end
    _SafeReequipBusy = true
    task.spawn(function()
        local ok = pcall(function()
            local unequipRe = Remotes:FindFirstChild("UnequipAllHero")
            local equipRe   = Remotes:FindFirstChild("AutoEquipBestHero")
            if unequipRe then unequipRe:FireServer() end
            task.wait(0.4)
            if equipRe then equipRe:FireServer() end
        end)
        if not ok then
            warn("[SafeReequipAfterTeleport] gagal ("..tostring(tag or "?")..")")
        end
        _SafeReequipBusy = false
    end)
end

--  LOAD WINDUI (VIA GITHUB - loadstring) 
-- [PERF] Fetch-nya udah DIMULAI dari baris paling atas script (paralel sama
-- semua WaitForChild remote di atas). Di titik ini kita cuma nunggu hasilnya
-- kalau ternyata belum selesai -- jadi total waktu tunggu = MAX(waktu fetch
-- WindUI, waktu semua WaitForChild), bukan JUMLAH keduanya kayak sebelumnya.
while not _WindUIFetch.done do
    task.wait()
end
if not _WindUIFetch.ok then
    error("[FLa] Gagal fetch/load WindUI dari GitHub: " .. tostring(_WindUIFetch.err))
end
local WindUI = _WindUIFetch.module
if type(WindUI) ~= "table" then
    error("[FLa] WindUI (loadstring GitHub) tidak mengembalikan modul yang valid (type = " .. type(WindUI) .. ").")
end

--  WINDOW (+ floating minimize bubble, sudah teruji OK) 
local Window = WindUI:CreateWindow({
    Title       = "FLa Project Premium",
    Icon        = "sword",
    Theme       = "Dark",
    Folder      = "premium_rejoin",
    Transparent = true,   -- aktifkan mode transparan (diperlukan SetBackgroundTransparency)

    OpenButton = {
        Title           = "FLa Project",
        CornerRadius    = UDim.new(0, 12),
        StrokeThickness = 2,
        Enabled         = true,
        Draggable       = true,
        OnlyMobile      = false,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    Color3.fromRGB(25, 45, 115)),
            ColorSequenceKeypoint.new(0.55, Color3.fromRGB(55, 105, 255)),
            ColorSequenceKeypoint.new(1,    Color3.fromRGB(90, 145, 255)),
        }),
    },

    --  Pengganti CreateUserProfile() (baris 1132-1172 source asli) 
    User = {
        Enabled   = true,
        Anonymous = false,
        Callback  = function() end, -- diisi ulang di bawah (ToggleUserIdentity)
    },
})

Window:SetToggleKey(Enum.KeyCode.LeftAlt)

-- ============================================================================
-- TOGGLE USER IDENTITY (klik User card = ganti tampilan asli <-> anonim)
-- ============================================================================
-- Struktur AKTUAL dikonfirmasi via debug (2x putaran, akhirnya presisi):
--   CoreGui.HiddenUI.WindUI.Window.Frame.Main.TextButton.UserIcon               <- container (ImageTransparency=1 dari awal, BUKAN yang tampil)
--   CoreGui.HiddenUI.WindUI.Window.Frame.Main.TextButton.UserIcon.ImageLabel    <- FOTO SEBENARNYA (ImageTransparency=0, Visible=true)
--   CoreGui.HiddenUI.WindUI.Window.Frame.Main.TextButton.UserIcon.Frame.DisplayName  (TextLabel)
--   CoreGui.HiddenUI.WindUI.Window.Frame.Main.TextButton.UserIcon.Frame.UserName     (TextLabel)
-- UserIcon (container) ber-Active=false, jadi klik dideteksi lewat InputBegan
-- (bukan MouseButton1Click/Activated yang tidak fire kalau Active=false).
local _uiIdentityAnon     = false
local ANON_NAME_TEXT      = "Roblox"

local function _getUserIconButton()
    local ok, result = pcall(function()
        local coreGui   = game:GetService("CoreGui")
        -- Path asli terkonfirmasi via debug: CoreGui.RobloxGui.WindUI.Window.Frame.Main.TextButton.UserIcon
        -- (bukan CoreGui.HiddenUI.WindUI... seperti dugaan awal)
        local robloxGui = coreGui:FindFirstChild("RobloxGui")
        local windUIGui = robloxGui and robloxGui:FindFirstChild("WindUI")
        local win       = windUIGui and windUIGui:FindFirstChild("Window")
        local p = win
        for _, childName in ipairs({"Frame", "Main", "TextButton", "UserIcon"}) do
            p = p and p:FindFirstChild(childName)
            if not p then return nil end
        end
        return p -- container UserIcon (dipakai untuk klik + traversal ke child)
    end)
    if ok then return result end
    return nil
end

-- Capture nilai ASLI cuma sekali, SEGERA saat UserIcon pertama kali ditemukan
-- (bukan ditunda sampai klik pertama) -- supaya tidak pernah ke-capture nilai
-- yang sudah ter-anonymize kalau sempat toggle duluan sebelum capture selesai.
local _uiIdentityOriginal = {photoTransparency = nil, displayName = nil, userName = nil}
local _uiIdentityCaptured = false

local function _captureUserIdentityOriginal(btn)
    if _uiIdentityCaptured then return end

    local photo = btn:FindFirstChild("ImageLabel")
    local frame = btn:FindFirstChild("Frame")
    local dn    = frame and frame:FindFirstChild("DisplayName")
    local un    = frame and frame:FindFirstChild("UserName")

    -- pcall TERPISAH per elemen, supaya kegagalan 1 elemen tidak mengunci
    -- _uiIdentityCaptured=false untuk elemen lain yang sebenarnya valid.
    if photo then
        pcall(function() _uiIdentityOriginal.photoTransparency = photo.ImageTransparency end)
    end
    if dn then
        pcall(function() _uiIdentityOriginal.displayName = dn.Text end)
    end
    if un then
        pcall(function() _uiIdentityOriginal.userName = un.Text end)
    end

    _uiIdentityCaptured = true
end

local function ToggleUserIdentity()
    local btn = _getUserIconButton()
    if not btn or not _uiIdentityCaptured then return end -- belum sempat capture original, jangan toggle dulu
    _uiIdentityAnon = not _uiIdentityAnon

    local photo = btn:FindFirstChild("ImageLabel")
    local frame = btn:FindFirstChild("Frame")
    local dn    = frame and frame:FindFirstChild("DisplayName")
    local un    = frame and frame:FindFirstChild("UserName")

    -- Sembunyikan foto (transparency=1) saat anonim, tampilkan lagi saat asli
    if photo and _uiIdentityOriginal.photoTransparency ~= nil then
        local newVal = _uiIdentityAnon and 1 or _uiIdentityOriginal.photoTransparency
        pcall(function() photo.ImageTransparency = newVal end)
    end
    if dn and _uiIdentityOriginal.displayName then
        pcall(function() dn.Text = _uiIdentityAnon and ANON_NAME_TEXT or _uiIdentityOriginal.displayName end)
    end
    if un and _uiIdentityOriginal.userName then
        pcall(function() un.Text = _uiIdentityAnon and ANON_NAME_TEXT or _uiIdentityOriginal.userName end)
    end
end

-- Pasang listener klik ke tombol UserIcon secara langsung. WindUI mungkin
-- baru selesai membangun Window sesaat setelah CreateWindow() return, jadi
-- kita retry singkat (bukan WaitForChild tanpa batas, biar tidak nge-hang
-- kalau strukturnya memang beda dari dugaan). Capture original dilakukan
-- SEGERA begitu UserIcon ketemu, sebelum listener dipasang.
task.spawn(function()
    local btn = nil
    for _ = 1, 40 do -- max ~4 detik (40 x 0.1s)
        btn = _getUserIconButton()
        if btn then break end
        task.wait(0.1)
    end
    if btn then
        _captureUserIdentityOriginal(btn)
        pcall(function()
            btn.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                    ToggleUserIdentity()
                end
            end)
        end)
    else
        print("[FLa UserIdentity] btn tidak ketemu setelah 4 detik -- path RobloxGui.WindUI.Window.Frame.Main.TextButton.UserIcon mungkin masih perlu penyesuaian")
    end
end)

-- ============================================================================
-- 4 TAB: FARM, AUTOMATION, PLAYER, CONFIG
-- ============================================================================

local FarmTab = Window:Tab({
    Title = "Farm",
    Icon  = "sword",
})

local AutomationTab = Window:Tab({
    Title = "Automation",
    Icon  = "bot",
})

local PlayerTab = Window:Tab({
    Title = "Player",
    Icon  = "user",
})

local ConfigTab = Window:Tab({
    Title = "Config",
    Icon  = "save",
})

-- ============================================================================
-- PANEL: FARM
-- Dipindah dari baris ~5571 source premium (1.lua)
-- Ditulis ulang pakai WindUI native API
--
-- Perbedaan API vs source asli:
--   Source asli : ToggleRow(), custom Frame/Btn dropdown, custom ScrollingFrame rows
--   WindUI      : Tab:Toggle(), Tab:Dropdown(Multi=false), Tab:Paragraph(), Tab:Button()
--                 Enemy list rows dibuat manual (WindUI tidak punya dynamic list),
--                 disimulasikan via Paragraph + Button per enemy (lihat catatan TA di bawah)
--
-- Fitur:
--   1. ENEMY HP MONITOR   HP bar + stopwatch (Paragraph + Button START/STOP/RESET)
--   2. RANDOM ATTACK (RA)  Toggle, kill counter Paragraph, BlockSkillEffects
--   3. SELECT ENEMY / TARGET ATTACK (TA)  Mode dropdown + Refresh + enemy list rows
--
-- Remote:
--   RE.Atk   (RemoteEvent)  : FireServer({attackEnemyGUID=guid})
--   RE.Click (RemoteFunction): InvokeServer({enemyGuid=guid})
--   RE.Death (RemoteEvent)  : OnClientEvent  data.enemyGuid / data.guid
--   ShowEnemyTakeDamageInfo (RemoteEvent RS.Remotes): OnClientEvent  {enemyId, hp, maxHp}
--
-- Global expose:
--   _setRAToggle       set + trigger toggle RA
--   _visRandomAtk      set visual only RA
--   _raRunningState    bool state RA
-- ============================================================================
do
    --  Global expose (dibaca Config panel saat save/load) 
    _raRunningState = false
    _setRAToggle    = nil
    _visRandomAtk   = nil

    --  State RA & TA 
    local RA = { running=false, threads={}, killed=0, cur=nil, next=nil, _lockConn=nil }
    local TA = { running=false, threads={}, killed=0, cur=nil, targetName=nil }

    local _byNameLiveToken = nil
    local _raDiedConns     = {}
    local _deadG_F         = {}
    local HERO_GUIDS_F     = HERO_GUIDS  -- alias ke global, bukan copy

    -- [HP-BASED DEATH DETECT] Table HP terkini per-guid, diisi oleh listener
    -- ShowEnemyTakeDamageInfo (dipasang di section ENEMY HP MONITOR di bawah).
    -- Dipakai IsTargetAliveRA (RA) dan IsDeadF (TA) sebagai sinyal kematian
    -- pengganti Humanoid.Died/Humanoid.Health. Musuh yang GUID-nya belum pernah
    -- muncul di table ini (belum pernah kena damage sama sekali) dianggap HIDUP.
    _enemyHpByGuid = _enemyHpByGuid or {}

    --  Death listener global 
    -- Source asli baris 5587-5597
    if RE and RE.Death then
        RE.Death.OnClientEvent:Connect(function(d)
            if not d then return end
            local g = d.enemyGuid or d.guid
            if g then
                _deadG_F[g] = false
                if RA.running then RA.killed = RA.killed + 1 end
                if TA.running then TA.killed = TA.killed + 1 end
            end
        end)
    end

    --  Helper: validasi posisi HRP 
    -- Source asli baris 5600-5606
    local function IsPosValidF(hrp)
        if not hrp then return false end
        local pos = hrp.Position
        if pos.X~=pos.X or pos.Y~=pos.Y or pos.Z~=pos.Z then return false end
        if math.abs(pos.X)>1e10 or math.abs(pos.Y)>1e10 or math.abs(pos.Z)>1e10 then return false end
        return true
    end

    --  Helper: scan semua folder enemy standar 
    -- Source asli baris 5611-5635
    local function GetEnemiesF()
        local list = {}
        local seen = {}
        for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
            local f = workspace:FindFirstChild(fname)
            if f then
                for _,e in ipairs(f:GetChildren()) do
                    if e:IsA("Model") then
                        local g = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid")
                                or e:GetAttribute("Guid")     or e:GetAttribute("GUID")
                        local h = e:FindFirstChild("HumanoidRootPart")
                                or e.PrimaryPart
                                or e:FindFirstChild("Torso")
                                or e:FindFirstChild("UpperTorso")
                                or e:FindFirstChildWhichIsA("BasePart")
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        if g and h and hum and hum.Health>0 and not seen[g] and IsPosValidF(h) then
                            seen[g] = true
                            table.insert(list, {model=e, guid=g, hrp=h, name=e.Name})
                        end
                    end
                end
            end
        end
        return list
    end

    -- [HP-BASED DEATH DETECT] Cek mati pakai HP dari remote ShowEnemyTakeDamageInfo
    -- (_enemyHpByGuid), bukan Humanoid.Health/_deadG_F lagi. Musuh yang guid-nya
    -- belum pernah tercatat di _enemyHpByGuid (belum pernah kena damage) dianggap HIDUP.
    local function IsDeadF(e)
        if not e then return true end
        if not e.model or not e.model.Parent then return true end
        local hp = _enemyHpByGuid[e.guid]
        if hp ~= nil and hp <= 0 then return true end
        return false
    end

    local function FindByGuidF(guid)
        for _,e in ipairs(GetEnemiesF()) do
            if e.guid == guid and not IsDeadF(e) then return e end
        end
        return nil
    end

    local function FindAllByNameF(nm)
        local result = {}
        for _,e in ipairs(GetEnemiesF()) do
            if e.name == nm and not IsDeadF(e) then
                table.insert(result, e)
            end
        end
        return result
    end

    --  Freeze / Unfreeze player 
    -- Source asli baris 5665-5710
    local _frozenWS     = nil
    local _frozenAnchor = false

    local function FreezePlayer()
        local char = LP and LP.Character; if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        _frozenWS = true
        if hrp then
            pcall(function() hrp.AssemblyLinearVelocity  = Vector3.new(0,0,0) end)
            pcall(function() hrp.AssemblyAngularVelocity = Vector3.new(0,0,0) end)
            hum.PlatformStand = false
            hrp.Anchored      = true
            _frozenAnchor     = true
        end
    end

    local function UnfreezePlayer()
        if _frozenWS == nil then return end
        local char = LP and LP.Character; if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and _frozenAnchor then
            hrp.Anchored  = false
            _frozenAnchor = false
        end
        _frozenWS = nil
    end

    local function ReassertFreeze()
        if _frozenWS == nil then return end
        local char = LP and LP.Character; if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and not hrp.Anchored then
            pcall(function() hrp.AssemblyLinearVelocity  = Vector3.new(0,0,0) end)
            pcall(function() hrp.AssemblyAngularVelocity = Vector3.new(0,0,0) end)
            hrp.Anchored = true
        end
    end

    --  TpHerosToPos  teleport semua hero (workspace.Heros) ke CFrame yang sama
    -- dengan player, supaya hero ikut pindah tiap kali target RA/TA berganti.
    -- Client-side only (set CFrame HumanoidRootPart tiap model hero), pola sama
    -- persis dengan yang sudah dipakai di Auto Ascension (lihat _offsetFromBoss
    -- TP hero baris ~10095-10106).
    local function TpHerosToPos(cf)
        if not cf then return end
        pcall(function()
            local herosFolder = workspace:FindFirstChild("Heros")
            if not herosFolder then return end
            -- [FIX] Struktur nyata: workspace.Heros.Hero_XXXXXXX.<NamaHero>.HumanoidRootPart
            -- (ada 1 model wrapper "Hero_XXXXXXX" di antara folder Heros dan hero
            -- aslinya). GetChildren() level pertama SAJA tidak cukup -- harus
            -- scan tiap Humanoid di dalam wrapper itu (bukan GetDescendants penuh
            -- workspace.Heros, supaya tidak ikut TP part lain yang kebetulan
            -- bernama sama di masa depan).
            --
            -- [FIX OVERLAP] Hero TIDAK ditumpuk persis di titik yang sama (cf),
            -- tapi disebar melingkar 2 stud dari titik itu -- pola sama seperti
            -- _offsetFromBoss di Auto Ascension. Kalau semua hero + player numpuk
            -- di 1 titik yang sama persis dengan musuh, efek server seperti
            -- AffectedTargetEffect (yang keluar nempel di HumanoidRootPart
            -- terdekat) jadi gampang salah nempel ke Hero alih-alih musuh,
            -- menyebabkan warning "tried to set parent to NULL". Offset kecil
            -- ini tidak mengubah efektivitas serangan (hero tetap dalam jarak
            -- attack range), cuma menghindari tumpukan fisik persis di 1 titik.
            local hrpList = {}
            for _, wrapper in ipairs(herosFolder:GetChildren()) do
                local directHrp = wrapper:FindFirstChild("HumanoidRootPart")
                if directHrp then table.insert(hrpList, directHrp) end
                for _, hModel in ipairs(wrapper:GetChildren()) do
                    if hModel:IsA("Model") then
                        local hHrp = hModel:FindFirstChild("HumanoidRootPart")
                        if hHrp then table.insert(hrpList, hHrp) end
                    end
                end
            end

            local n = #hrpList
            if n == 0 then return end
            for i, hHrp in ipairs(hrpList) do
                local angle  = (i - 1) * (2 * math.pi / math.max(n, 1))
                local offset = Vector3.new(math.cos(angle) * 2, 0, math.sin(angle) * 2)
                local destCF = cf * CFrame.new(offset)
                pcall(function() hHrp.CFrame = destCF end)
            end
        end)
    end

    --  TpToF  teleport 3 stud di depan musuh + FreezePlayer (anchor + velocity reset)
    -- + ikut teleport semua Hero ke posisi yang sama dengan Player.
    local function TpToF(tgt)
        if not tgt or not tgt.hrp then return end
        local char = LP.Character; if not char then return end
        local hrp  = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        local destCF = tgt.hrp.CFrame * CFrame.new(0, 0, -3)
        pcall(function()
            hrp.CFrame = destCF
        end)
        TpHerosToPos(destCF)
        FreezePlayer()
    end

    --  IsEnemyGuidValid  validasi enemy masih ada & hidup 
    -- Source asli baris 2180-2214
    local function IsEnemyGuidValid(g)
        if not g then return false end
        local ENEMY_FOLDERS = {"Enemys","EnemyCityRaid","CityRaidEnemys","Enemies","Enemy"}
        for _, folderName in ipairs(ENEMY_FOLDERS) do
            local f = workspace:FindFirstChild(folderName)
            if f then
                for _, e in ipairs(f:GetChildren()) do
                    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
                        local hrp = e:FindFirstChild("HumanoidRootPart")
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        if hrp and hum and hum.Health > 0 then return true end
                        return false
                    end
                end
            end
        end
        -- Fallback: nested di workspace.Map.CityRaidEnter (Siege)
        pcall(function()
            local mapF = workspace:FindFirstChild("Map")
            local cre  = mapF and mapF:FindFirstChild("CityRaidEnter")
            if cre then
                for _, e in ipairs(cre:GetDescendants()) do
                    if e:IsA("Model") and e:GetAttribute("EnemyGuid") == g then
                        local hrp = e:FindFirstChild("HumanoidRootPart")
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        if hrp and hum and hum.Health > 0 then return true end
                    end
                end
            end
        end)
        return false
    end

    --  Hero-attack thread per-GUID (EnsureHeroAtkThreadFor / StopHeroAtkThreadFor) 
    -- Source asli baris 2217-2260
    local _heroAtkThreads = {}


    local function EnsureHeroAtkThreadFor(g)
        if not g then return end
        if _heroAtkThreads[g] and _heroAtkThreads[g].running then return end
        local handle = {running = true, tick = 0}
        _heroAtkThreads[g] = handle
        task.spawn(function()
            local _lastFire = {}
            while handle.running do
                if #HERO_GUIDS > 0 and (tick() - handle.tick) >= 0.001 and IsEnemyGuidValid(g) then
                    handle.tick = tick()
                    -- Ambil posisi player sekarang untuk dipasang ke semua hero
                    local _char = LP and LP.Character
                    local _pHRP = _char and _char:FindFirstChild("HumanoidRootPart")
                    local _pPos = _pHRP and _pHRP.Position or Vector3.new(0,0,0)
                    for _, hGuid in ipairs(HERO_GUIDS) do
                        local last = _lastFire[hGuid] or 0
                        if (tick() - last) >= 0.001 then
                            _lastFire[hGuid] = tick()
                            if RE.HeroUseSkill then
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                                task.wait(0.001)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                                task.wait(0.001)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                                task.wait(0.001)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                                task.wait(0.001)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                                task.wait(0.001)
                                pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g}) end)
                            end
                        end
                        task.wait(0.001)
                    end
                end
                task.wait(0.001)
                if not IsEnemyGuidValid(g) then
                    handle.running = false
                end
            end
            _heroAtkThreads[g] = nil
        end)
    end

    local function StopHeroAtkThreadFor(g)
        if g and _heroAtkThreads[g] then
            _heroAtkThreads[g].running = false
            _heroAtkThreads[g] = nil
        end
    end

    --  TA Spam threads  unlimited attack per-target 
    -- [UNIFIED] Disamakan dgn pola attack thread RA (tAtk, lihat StartRA):
    --   RE.Atk:FireServer 1x/frame + RE.Click:InvokeServer 1x/frame (spawned)
    --   + EnsureHeroAtkThreadFor(g) untuk serangan hero.
    -- FireAttack/FireAllDamage (dual RE.Atk + hero attackType=1 throttle 0.04s
    -- terpisah dari EnsureHeroAtkThreadFor) DIHAPUS karena cuma dipakai di sini
    -- dan menyebabkan RE.Atk + hero attackType=1 ke-fire dobel per frame.
    local _taSpamThreads = {}

    local function TaSpamF(g, enemyHRP)
        if not g then return end
        if _taSpamThreads[g] and _taSpamThreads[g].running then return end
        local handle = {running = true}
        _taSpamThreads[g] = handle
        task.spawn(function()
            while handle.running do
                if IsEnemyGuidValid(g) then
                    if RE.Atk then
                        pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end) -- fire 1
                    end
                    if RE.Click then
                        task.spawn(function()
                            pcall(function() RE.Click:InvokeServer({enemyGuid=g}) end) -- invoke 1
                        end)
                    end
                    EnsureHeroAtkThreadFor(g)
                end
                task.wait(0.001)
            end
        end)
    end

    local function StopClickSpamF(g)
        if g and _taSpamThreads[g] then
            _taSpamThreads[g].running = false
            _taSpamThreads[g] = nil
        end
    end

    local function StopAllClickSpamF()
        for _, handle in pairs(_taSpamThreads) do
            handle.running = false
        end
        _taSpamThreads = {}
    end

    local function FCharF(g, enemyHRP)
        if not g then return end
        TaSpamF(g, enemyHRP)
    end

    -- ============================================================================
    -- GLOBAL NUKE: workspace.Anims (isi apapun, semua asset ID) + ClickAttackEffect
    -- / HitEffect pada musuh manapun (global, tidak peduli musuh yang mana).
    -- Bersifat DESTROY permanen (bukan sekadar Stop/Disable) selama RA/TA aktif,
    -- supaya AnimationTrack limit 64 tidak pernah kena karena sumbernya langsung
    -- dihapus dari awal, bukan cuma di-stop belakangan.
    -- ============================================================================
    local _globalNukeOn      = false
    local _globalNukeConns   = {}
    local _globalNukePoll    = nil

    local function _nukeAnimsFolder()
        pcall(function()
            local anims = workspace:FindFirstChild("Anims")
            if not anims then return end
            for _, child in ipairs(anims:GetChildren()) do
                task.defer(function()
                    pcall(function() if child and child.Parent then child:Destroy() end end)
                end)
            end
        end)
    end

    local function _nukeClickHitEffects()
        pcall(function()
            local enemysFolder = workspace:FindFirstChild("Enemys")
            if not enemysFolder then return end
            for _, desc in ipairs(enemysFolder:GetDescendants()) do
                if desc.Name == "ClickAttackEffect" or desc.Name == "HitEffect" then
                    task.defer(function()
                        pcall(function() if desc and desc.Parent then desc:Destroy() end end)
                    end)
                end
            end
        end)
    end

    local function BlockGlobalNuke(on)
        if on == _globalNukeOn then return end
        _globalNukeOn = on

        if on then
            -- Sapuan awal langsung
            _nukeAnimsFolder()
            _nukeClickHitEffects()

            -- Listener real-time: workspace.Anims - hapus SEGALA child baru,
            -- tidak peduli isinya (asset ID apapun).
            pcall(function()
                local anims = workspace:FindFirstChild("Anims")
                if anims then
                    table.insert(_globalNukeConns, anims.ChildAdded:Connect(function(child)
                        if not _globalNukeOn then return end
                        task.defer(function()
                            pcall(function() if child and child.Parent then child:Destroy() end end)
                        end)
                    end))
                end
            end)

            -- Listener real-time: ClickAttackEffect / HitEffect di musuh manapun (global)
            pcall(function()
                local enemysFolder = workspace:FindFirstChild("Enemys")
                if enemysFolder then
                    table.insert(_globalNukeConns, enemysFolder.DescendantAdded:Connect(function(desc)
                        if not _globalNukeOn then return end
                        if desc.Name == "ClickAttackEffect" or desc.Name == "HitEffect" then
                            task.defer(function()
                                pcall(function() if desc and desc.Parent then desc:Destroy() end end)
                            end)
                        end
                    end))
                end
            end)

            -- Polling backup (jaga-jaga kalau ada yang lolos dari listener karena
            -- race dengan attack spam 0.001s) - jalan tiap 0.15 detik.
            if _globalNukePoll then
                pcall(function() task.cancel(_globalNukePoll) end)
                _globalNukePoll = nil
            end
            _globalNukePoll = task.spawn(function()
                while _globalNukeOn do
                    _nukeAnimsFolder()
                    _nukeClickHitEffects()
                    task.wait(0.15)
                end
                _globalNukePoll = nil
            end)
        else
            if _globalNukePoll then
                pcall(function() task.cancel(_globalNukePoll) end)
                _globalNukePoll = nil
            end
            for _, c in ipairs(_globalNukeConns) do
                pcall(function() c:Disconnect() end)
            end
            _globalNukeConns = {}
        end
    end

    --  Skill Effect Blocker  DESTROY MODE 
    -- Source asli baris 5806-5907
    -- [REWRITE] Diganti total dari hide/restore (Transparency/Enabled toggle)
    -- menjadi DESTROY penuh. Semua isi workspace.SkillEffectContainer dan
    -- workspace.Anims di-Destroy() tanpa filter tipe object (Animator,
    -- ParticleEmitter, Trail, Beam, BasePart, Model, Folder, dll -- apapun
    -- isinya langsung dihapus), baik yang sudah ada saat toggle ON maupun
    -- yang baru muncul sesudahnya (real-time via DescendantAdded). Karena
    -- Destroy() itu final (tidak bisa di-restore), tidak ada lagi cache
    -- Transparency/CastShadow original dan tidak ada lagi proses restore
    -- saat OFF -- OFF cuma menghentikan listener/poll, tidak mengembalikan
    -- apapun (memang sudah hancur).
    --
    -- Reference-count 3 sumber (RA/TA/MA), pola sama persis dengan
    -- BlockAffectedTargetEffect: supaya aman dipanggil dari 3 fitur
    -- berbeda tanpa saling mematikan proteksi fitur lain (mis. MA ON lalu
    -- RA OFF tidak boleh mematikan destroy untuk MA yang masih jalan).
    local _secBlockRefs = {RA = false, TA = false, MA = false}
    local _secBlocked    = false
    local _secConns       = {}
    local _secPollThread  = nil

    local _enemyAnimBlocked = false
    local _enemyAnimConns   = {}
    local _enemyAnimPollThread = nil

    local function _secAnyActive()
        return _secBlockRefs.RA or _secBlockRefs.TA or _secBlockRefs.MA
    end

    -- Destroy aman: task.defer supaya tidak bentrok dengan proses internal
    -- Roblox yang sedang re-parent objek yang sama di frame yang sama
    -- persis (pola identik _ateSafeDestroy).
    local function _secSafeDestroy(desc)
        if not desc or not desc.Parent then return end
        task.defer(function()
            pcall(function()
                if desc and desc.Parent then
                    desc:Destroy()
                end
            end)
        end)
    end

    local _secTargetFolders = {"SkillEffectContainer", "Anims"}

    local function _secDestroyExisting()
        pcall(function()
            for _, folderName in ipairs(_secTargetFolders) do
                local folder = workspace:FindFirstChild(folderName)
                if not folder then continue end
                for _, desc in ipairs(folder:GetChildren()) do
                    _secSafeDestroy(desc)
                end
            end
        end)
    end

    -- source: "RA" | "TA" | "MA"
    function BlockSkillEffects(on, source)
        source = source or "RA"
        if on then
            _secBlockRefs[source] = true
        else
            _secBlockRefs[source] = false
        end

        local shouldBlock = _secAnyActive()
        if shouldBlock == _secBlocked then
            -- Tetap bersihkan yang sudah ada sekarang walau state tidak berubah
            if shouldBlock then _secDestroyExisting() end
            return
        end
        _secBlocked = shouldBlock

        pcall(function()
            if shouldBlock then
                _secDestroyExisting()
                -- Listener real-time per folder: hapus setiap object baru
                -- yang muncul (langsung child ATAU descendant lebih dalam),
                -- tidak peduli tipe object apapun.
                for _, folderName in ipairs(_secTargetFolders) do
                    local folder = workspace:FindFirstChild(folderName)
                    if not folder then continue end
                    table.insert(_secConns, folder.DescendantAdded:Connect(function(desc)
                        if not _secBlocked then return end
                        _secSafeDestroy(desc)
                    end))
                end
                -- Polling backup (jaga-jaga ada yang lolos dari listener
                -- karena race dengan attack spam), sama pola dengan
                -- _enemyAnimPollThread di bawah.
                if _secPollThread then
                    pcall(function() task.cancel(_secPollThread) end)
                    _secPollThread = nil
                end
                _secPollThread = task.spawn(function()
                    while _secBlocked do
                        _secDestroyExisting()
                        task.wait(0.15)
                    end
                    _secPollThread = nil
                end)
            else
                if _secPollThread then
                    pcall(function() task.cancel(_secPollThread) end)
                    _secPollThread = nil
                end
                for _, c in ipairs(_secConns) do
                    pcall(function() c:Disconnect() end)
                end
                _secConns = {}
            end
        end)
    end

    -- BlockEnemyHitAnim: memblokir animasi hit-react musuh (Animator di dalam
    -- model workspace.Enemys) secara real-time. Berbeda dari BlockSkillEffects
    -- (yang menangani SkillEffectContainer/Anims), ini menyasar Animator milik
    -- karakter musuh itu sendiri supaya track animasi tidak menumpuk (>64 limit)
    -- dan menghemat memory saat RA/TA/FASTATTACK menyerang enemy berkali-kali.
    --
    -- [PATCH PERF] Diperluas supaya juga mematikan ParticleEmitter/Trail/Beam
    -- yang muncul langsung di dalam model musuh (workspace.Enemys.<Model>.*).
    -- Sebelumnya objek ini TIDAK PERNAH dibersihkan oleh BlockSkillEffects
    -- (yang cuma menyasar folder SkillEffectContainer/Anims terpisah), jadi
    -- saat RA+TA+Hero menyerang 1 target bersamaan, partikel hit-effect
    -- (mis. lingkaran merah) menumpuk terus di dalam model musuh REAL tanpa
    -- pernah dibersihkan -> inilah akar penyebab FPS anjlok saat 3 fitur
    -- (RA -> clone, TA -> real, Fast Attack 1 Enemy) aktif bersamaan.
    -- Scope: mematikan SEMUA ParticleEmitter/Trail/Beam di workspace.Enemys
    -- tanpa filter (termasuk aura/efek skill musuh lain), sesuai konfirmasi.
    local function BlockEnemyHitAnim(on)
        if on == _enemyAnimBlocked then return end
        _enemyAnimBlocked = on
        pcall(function()
            local enemysFolder = workspace:FindFirstChild("Enemys")
            if not enemysFolder then return end

            if on then
                -- Stop semua track yang sedang jalan sekarang + matikan partikel yang sudah ada
                for _, desc in ipairs(enemysFolder:GetDescendants()) do
                    if desc:IsA("Animator") then
                        pcall(function()
                            for _, track in ipairs(desc:GetPlayingAnimationTracks()) do
                                track:Stop(0)
                            end
                        end)
                    elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                        pcall(function()
                            desc.Enabled = false
                            if desc:IsA("ParticleEmitter") then desc:Clear() end
                        end)
                    end
                end
                -- Listener: setiap Animator/Particle baru yang muncul (enemy baru di-spawn, atau hit-effect baru)
                table.insert(_enemyAnimConns, enemysFolder.DescendantAdded:Connect(function(desc)
                    if not _enemyAnimBlocked then return end
                    if desc:IsA("Animator") then
                        table.insert(_enemyAnimConns, desc.AnimationPlayed:Connect(function(track)
                            if not _enemyAnimBlocked then return end
                            pcall(function() track:Stop(0) end)
                        end))
                    elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                        pcall(function()
                            desc.Enabled = false
                            if desc:IsA("ParticleEmitter") then desc:Clear() end
                        end)
                    end
                end))
                -- Listener: pasang juga di Animator yang sudah ada sekarang,
                -- untuk track baru yang mau diputar setelahnya (real-time block)
                for _, desc in ipairs(enemysFolder:GetDescendants()) do
                    if desc:IsA("Animator") then
                        table.insert(_enemyAnimConns, desc.AnimationPlayed:Connect(function(track)
                            if not _enemyAnimBlocked then return end
                            pcall(function() track:Stop(0) end)
                        end))
                    end
                end

                -- [FIX 64-TRACK LIMIT] Listener reaktif (AnimationPlayed) saja tidak
                -- cukup: attack loop RA/TA fire remote setiap 0.001s, jadi banyak
                -- animasi bisa ke-play beruntun SEBELUM masing-masing sempat
                -- di-Stop() satu-per-satu -> track menumpuk lebih cepat dari proses
                -- stop-nya dan kena limit keras 64/Animator ("AnimationTrack limit
                -- of 64 tracks exceeded"). Solusi: proactive polling loop yang jalan
                -- terus selama RA/TA/MA aktif, sapu bersih SEMUA Animator di dalam
                -- Enemys DAN Heros setiap ~0.1 detik -- baik yang sedang diserang
                -- maupun tidak, murah karena cuma looping track yang sedang playing.
                if _enemyAnimPollThread then
                    pcall(function() task.cancel(_enemyAnimPollThread) end)
                    _enemyAnimPollThread = nil
                end
                _enemyAnimPollThread = task.spawn(function()
                    while _enemyAnimBlocked do
                        pcall(function()
                            -- Sapu Animator musuh
                            local ef = workspace:FindFirstChild("Enemys")
                            if ef then
                                for _, desc in ipairs(ef:GetDescendants()) do
                                    if desc:IsA("Animator") then
                                        local tracks = desc:GetPlayingAnimationTracks()
                                        if #tracks > 0 then
                                            for _, track in ipairs(tracks) do
                                                pcall(function() track:Stop(0) end)
                                            end
                                        end
                                    end
                                end
                            end
                            -- Sapu Animator hero juga (permintaan: destroy pergerakan
                            -- Heros/Enemies yang sedang diserang RA/TA, bukan cuma musuh)
                            local hf = workspace:FindFirstChild("Heros")
                            if hf then
                                for _, desc in ipairs(hf:GetDescendants()) do
                                    if desc:IsA("Animator") then
                                        local tracks = desc:GetPlayingAnimationTracks()
                                        if #tracks > 0 then
                                            for _, track in ipairs(tracks) do
                                                pcall(function() track:Stop(0) end)
                                            end
                                        end
                                    end
                                end
                            end
                        end)
                        task.wait(0.1)
                    end
                    _enemyAnimPollThread = nil
                end)
            else
                if _enemyAnimPollThread then
                    pcall(function() task.cancel(_enemyAnimPollThread) end)
                    _enemyAnimPollThread = nil
                end
                for _, c in ipairs(_enemyAnimConns) do
                    pcall(function() c:Disconnect() end)
                end
                _enemyAnimConns = {}
                -- Nyalakan lagi semua partikel yang sempat dimatikan
                for _, desc in ipairs(enemysFolder:GetDescendants()) do
                    if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
                        pcall(function() desc.Enabled = true end)
                    end
                end
            end
        end)
    end

    -- BlockAffectedTargetEffect: mematikan/menghapus objek "AffectedTargetEffect"
    -- (partikel lingkaran hit-effect) yang di-spawn SERVER langsung di dalam
    -- model musuh (workspace.Enemys.<Model>.AffectedTargetEffect) setiap kali
    -- musuh kena damage. Ini objek terpisah dari SkillEffectContainer/Anims
    -- (ditangani BlockSkillEffects) dan dari Animator (ditangani
    -- BlockEnemyHitAnim) -- karena itu perlu blocker sendiri.
    --
    -- Dikonfirmasi oleh user: saat objek ini dihapus manual, partikel lingkaran
    -- merah yang menumpuk benar-benar hilang. Bisa dipicu oleh Mass Attack, RA,
    -- TA, atau kombinasi ketiganya secara bersamaan -- karena itu blocker ini
    -- pakai reference-count sendiri (bukan reuse flag RA/TA) supaya aman
    -- dipanggil dari 3 fitur berbeda tanpa saling mematikan proteksi milik
    -- fitur lain (mis. MA ON lalu RA OFF tidak boleh mematikan block untuk MA).
    local _ateBlockRefs  = {RA = false, TA = false, MA = false}
    local _ateBlocked     = false
    local _ateConns        = {}

    local function _ateAnyActive()
        return _ateBlockRefs.RA or _ateBlockRefs.TA or _ateBlockRefs.MA
    end

    -- [FIX RACE] Destroy aman: pakai task.defer supaya tidak bentrok dengan
    -- proses internal Roblox yang sedang re-parent objek yang sama di frame
    -- yang sama persis (ini yang menyebabkan warning "tried to set parent of
    -- AffectedTargetEffect to NULL... current parent is HumanoidRootPart").
    -- Race ini jadi lebih sering muncul sekarang karena Hero ikut TP ke posisi
    -- musuh setiap RA/TA ganti target, jadi AffectedTargetEffect yang di-spawn
    -- server sempat ke-weld ke part Hero yang lagi tumpang-tindih posisi
    -- dengan musuh. task.defer menunda Destroy() ke akhir frame (setelah
    -- semua proses re-parent engine selesai), jadi tidak lagi rebutan dengan
    -- write internal Roblox pada Parent yang sama.
    local function _ateSafeDestroy(desc)
        if not desc or not desc.Parent then return end
        task.defer(function()
            pcall(function()
                if desc and desc.Parent then
                    desc:Destroy()
                end
            end)
        end)
    end

    local function _ateKillExisting()
        pcall(function()
            local enemysFolder = workspace:FindFirstChild("Enemys")
            if not enemysFolder then return end
            for _, desc in ipairs(enemysFolder:GetDescendants()) do
                if desc.Name == "AffectedTargetEffect" then
                    _ateSafeDestroy(desc)
                end
            end
        end)
    end

    -- source: "RA" | "TA" | "MA"
    -- [FIX] Dihapus 'local' -- fungsi ini dipanggil dari blok MASS ATTACK
    -- (do...end terpisah, baris ~4211+) yang tidak bisa melihat local
    -- di blok FARM ini. Tanpa expose global, DoMassAttack(true) akan error
    -- "attempt to call a nil value" SEBELUM sempat spawn MA.thread, sehingga
    -- toggle Mass Attack terlihat ON tapi statusnya diam di "Idle" selamanya.
    function BlockAffectedTargetEffect(on, source)
        source = source or "MA"
        if on then
            _ateBlockRefs[source] = true
        else
            _ateBlockRefs[source] = false
        end

        local shouldBlock = _ateAnyActive()
        if shouldBlock == _ateBlocked then
            -- Tetap bersihkan yang sudah ada sekarang walau state tidak berubah
            if shouldBlock then _ateKillExisting() end
            return
        end
        _ateBlocked = shouldBlock

        pcall(function()
            local enemysFolder = workspace:FindFirstChild("Enemys")
            if not enemysFolder then return end

            if shouldBlock then
                _ateKillExisting()
                -- Listener real-time: hapus setiap kali objek ini muncul lagi
                table.insert(_ateConns, enemysFolder.DescendantAdded:Connect(function(desc)
                    if not _ateBlocked then return end
                    if desc.Name == "AffectedTargetEffect" then
                        _ateSafeDestroy(desc)
                    end
                end))
            else
                for _, c in ipairs(_ateConns) do
                    pcall(function() c:Disconnect() end)
                end
                _ateConns = {}
            end
        end)
    end

    --  StopRA     -- Source asli baris 6122-6145 (forward-declared, dipakai StartRA  StopRA)
    local function StopRA()
        RA.running = false
        BlockSkillEffects(false, "RA")
        if not TA.running then BlockEnemyHitAnim(false) end
        if not TA.running then BlockGlobalNuke(false) end
        BlockAffectedTargetEffect(false, "RA")
        if RA._lockConn then
            pcall(function() RA._lockConn:Disconnect() end)
            RA._lockConn = nil
        end
        for _,t in ipairs(RA.threads) do pcall(function() task.cancel(t) end) end
        -- Stop semua hero-atk thread
        for g in pairs(_heroAtkThreads) do StopHeroAtkThreadFor(g) end
        if RA.cur and RA.cur.guid then StopHeroAtkThreadFor(RA.cur.guid) end
        RA.threads={}; RA.cur=nil; RA.next=nil
        for _,c in ipairs(_raDiedConns or {}) do pcall(function() c:Disconnect() end) end
        _raDiedConns = {}
        if not TA.running then
            UnfreezePlayer()
        end
    end

    --  StopTA 
    -- Source asli baris 6274-6287
    local function StopTA()
        TA.running = false
        BlockSkillEffects(false, "TA")
        if not RA.running then BlockEnemyHitAnim(false) end
        if not RA.running then BlockGlobalNuke(false) end
        BlockAffectedTargetEffect(false, "TA")
        for _,t in ipairs(TA.threads) do pcall(function() task.cancel(t) end) end
        TA.threads = {}
        StopAllClickSpamF()
        if TA.cur and TA.cur.guid then
            StopHeroAtkThreadFor(TA.cur.guid)
        end
        TA.cur=nil; TA.targetName=nil
        if not RA.running then
            UnfreezePlayer()
        end
        -- [FIX v17] Hapus task.defer(TpToRA)  race condition dengan auto-switch dropdown.
        -- Combat Lock Heartbeat RA akan otomatis relock player ke musuh RA di frame berikutnya.
        -- [v30] TP eksplisit balik ke musuh RA begitu TA off, supaya snap instan
        -- (tidak nunggu throttle Heartbeat _raLockFrame % 2). Remote serang RA
        -- (RE.Atk + hero) juga otomatis full lagi di tAtk karena TA.running sudah false.
        if RA.running and RA.cur and RA.cur.hrp then
            local char = LP.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    hrp.CFrame = RA.cur.hrp.CFrame * CFrame.new(0, 0, -3)
                end)
            end
        end
    end

    --  StartRA 
    -- Source asli baris 5909-6120
    local function StartRA()
        if #HERO_GUIDS == 0 then
            pcall(function()
                for _, obj in ipairs(LP.PlayerGui:GetChildren()) do
                    local g = obj:GetAttribute("heroGuid") or obj:GetAttribute("guid")
                    if type(g)=="string" and IsValidUUID(g) then
                        local dup=false
                        for _,ex in ipairs(HERO_GUIDS) do if ex==g then dup=true; break end end
                        if not dup then table.insert(HERO_GUIDS, g) end
                    end
                end
            end)
        end
        RA.running=true; RA.killed=0; RA.cur=nil; RA.next=nil; RA.threads={}
        BlockSkillEffects(true, "RA")
        BlockEnemyHitAnim(true)
        BlockGlobalNuke(true)
        BlockAffectedTargetEffect(true, "RA")

        -- [HP-BASED DEATH DETECT] Cek hidup/mati pakai HP dari remote
        -- ShowEnemyTakeDamageInfo (_enemyHpByGuid), bukan Humanoid.Health lagi.
        -- Musuh yang guid-nya belum pernah tercatat di _enemyHpByGuid (belum
        -- pernah kena damage) dianggap HIDUP.
        local function IsTargetAliveRA(t)
            if not t or not t.model or not t.model.Parent then return false end
            local hp = _enemyHpByGuid[t.guid]
            if hp ~= nil and hp <= 0 then return false end
            return true
        end

        -- RAFreezePlayer/RAUnfreezePlayer diganti dengan FreezePlayer/UnfreezePlayer global
        -- supaya StopRA -> UnfreezePlayer() selalu bisa melepas Anchored dengan benar

        local function TpToRA(tgt)
            if not tgt or not tgt.hrp then return end
            local char = LP.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local destCF = tgt.hrp.CFrame * CFrame.new(0, 0, -3)
            pcall(function()
                hrp.CFrame = destCF
            end)
            TpHerosToPos(destCF)
        end

        local function PickRandomEnemy(excludeGuids)
            local pool = {}
            local taGuid = TA.running and TA.cur and TA.cur.guid
            for _,e in ipairs(GetEnemiesF()) do
                if IsTargetAliveRA(e) then
                    local skip = false
                    if taGuid and e.guid == taGuid then skip = true end
                    if excludeGuids then
                        for _,ex in ipairs(excludeGuids) do
                            if e.guid == ex then skip = true; break end
                        end
                    end
                    if not skip then table.insert(pool, e) end
                end
            end
            if #pool == 0 then
                for _,e in ipairs(GetEnemiesF()) do
                    if IsTargetAliveRA(e) then table.insert(pool, e) end
                end
            end
            if #pool == 0 then return nil end
            return pool[math.random(1, #pool)]
        end

        local function LockNextTarget()
            local excludes = {}
            if RA.cur then table.insert(excludes, RA.cur.guid) end
            RA.next = PickRandomEnemy(excludes)
        end

        -- [HP-BASED DEATH DETECT] WatchEnemyRA dipertahankan sebagai no-op guard
        -- (dipanggil dari beberapa tempat) tapi tidak lagi connect ke Humanoid.Died.
        -- Deteksi kematian sekarang murni polling _enemyHpByGuid via IsTargetAliveRA
        -- di loop utama tMain (task.wait(0.15)) supaya ganti target cepat & konsisten
        -- dengan satu sumber sinyal (HP remote), bukan campur event+polling lagi.
        local function WatchEnemyRA(e)
            -- sengaja kosong: tidak ada lagi listener Humanoid.Died
        end

        -- Combat Lock via Heartbeat
        -- [FIX v17] Player nempel ke musuh RA (bukan musuh ke player).
        -- Skip saat TA running: player sedang di posisi musuh TA, biarkan saja.
        local _raLockFrame = 0
        local _raLockConn = RunService.Heartbeat:Connect(function()
            _raLockFrame = _raLockFrame + 1
            if _raLockFrame % 2 ~= 0 then return end
            if not RA.running then return end
            if TA.running then return end  -- TA ON: player harus di posisi musuh TA, bukan RA
            if not RA.cur or not IsTargetAliveRA(RA.cur) then return end
            local char = LP.Character
            local pHRP = char and char:FindFirstChild("HumanoidRootPart")
            local eHRP = RA.cur.hrp
            if pHRP and eHRP then
                pcall(function()
                    -- Player mengikuti musuh (3 stud di depan musuh)
                    pHRP.CFrame = eHRP.CFrame * CFrame.new(0, 0, -3)
                end)
            end
        end)
        RA._lockConn = _raLockConn

        -- Main thread
        local tMain = task.spawn(function()
            RA.cur = PickRandomEnemy({})
            if RA.cur then
                TpToRA(RA.cur); FreezePlayer()
                WatchEnemyRA(RA.cur)
                -- [HP-BASED DEATH DETECT] Tidak lagi connect Humanoid.Died di sini.
                -- Kematian target dideteksi via IsTargetAliveRA (_enemyHpByGuid)
                -- di pengecekan while-loop di bawah.
                LockNextTarget()
            end
            while RA.running do
                if not RA.cur or not IsTargetAliveRA(RA.cur) then
                    local _oldGuid = RA.cur and RA.cur.guid
                    if _oldGuid then
                        StopHeroAtkThreadFor(_oldGuid)
                        _deadG_F[_oldGuid] = nil
                    end
                    RA.cur = IsTargetAliveRA(RA.next) and RA.next or PickRandomEnemy({})
                    RA.next = nil
                    if RA.cur then
                        if not TA.running then TpToRA(RA.cur); FreezePlayer() end  -- TA ON: jangan override posisi TA
                        WatchEnemyRA(RA.cur)
                        -- [HP-BASED DEATH DETECT] Tidak lagi connect Humanoid.Died.
                        LockNextTarget()
                    end
                end
                if not IsTargetAliveRA(RA.next) then LockNextTarget() end
                task.wait(0.15)
            end
        end)

        -- [v29] Attack thread RA: disamakan dengan TA (TaSpamF) - single-fire per iterasi
        -- [v30] Saat TA.running true (TA dinyalakan setelah RA), RA HANYA Click Enemy
        -- (RE.Click) untuk menangkap GUID -- RE.Atk dan hero attack RA dimatikan total
        -- supaya tidak dobel serang bareng TA. Begitu TA.running kembali false (TA
        -- di-OFF-kan user atau target TA mati), RA otomatis balik full attack di
        -- iterasi berikutnya (cek TA.running dilakukan tiap loop, tidak perlu state
        -- tambahan/flag manual).
        local tAtk = task.spawn(function()
            while RA.running do
                if RA.cur and IsTargetAliveRA(RA.cur) then
                    local g = RA.cur.guid
                    if TA.running then
                        -- TA aktif: RA cuma Click untuk capture GUID, tanpa Atk & tanpa hero
                        if RE and RE.Click then
                            task.spawn(function()
                                pcall(function() RE.Click:InvokeServer({enemyGuid=g}) end) -- invoke 1
                            end)
                        end
                        StopHeroAtkThreadFor(g)
                    else
                        -- TA tidak aktif: RA full attack seperti biasa
                        if RE and RE.Atk then
                            pcall(function() RE.Atk:FireServer({attackEnemyGUID=g}) end) -- fire 1
                        end
                        if RE and RE.Click then
                            task.spawn(function()
                                pcall(function() RE.Click:InvokeServer({enemyGuid=g}) end) -- invoke 1
                            end)
                        end
                        EnsureHeroAtkThreadFor(g)
                    end
                end
                task.wait(0.001)
            end
        end)

        RA.threads = {tMain, tAtk}
    end

    --  StartTA By ID 
    -- Source asli baris 6147-6198
    local function StartTA_ByID(targetGuid, targetName, onStatus, onStop)
        TA.running=true; TA.killed=0; TA.targetName=targetName; TA.cur=nil; TA.threads={}
        BlockEnemyHitAnim(true)
        BlockGlobalNuke(true)
        BlockSkillEffects(true, "TA")
        BlockAffectedTargetEffect(true, "TA")
        local tChar = task.spawn(function()
            local tgt = FindByGuidF(targetGuid)
            if tgt then
                TpToF(tgt); FreezePlayer()
                TA.cur = tgt
                -- [HP-BASED DEATH DETECT] Tidak lagi connect Humanoid.Died di sini.
                -- Kematian target dideteksi via IsDeadF (_enemyHpByGuid) di
                -- pengecekan while-loop di bawah, supaya ganti target cepat &
                -- konsisten dengan satu sumber sinyal (HP remote).
            end
            while TA.running do
                tgt = FindByGuidF(targetGuid)
                if not tgt then
                    StopClickSpamF(targetGuid)
                    StopHeroAtkThreadFor(targetGuid)
                    TA.cur = nil
                    if onStatus then onStatus(" ["..targetName.."] mati") end
                    TA.running = false
                    if onStop then onStop() end
                    break
                end
                if IsDeadF(tgt) then
                    StopClickSpamF(targetGuid)
                    StopHeroAtkThreadFor(targetGuid)
                    TA.cur = nil
                    if onStatus then onStatus(" ["..targetName.."] mati") end
                    TA.running = false
                    if onStop then onStop() end
                    break
                end
                if tgt.model.Parent then
                    TA.cur = tgt
                    -- [v27] GASS terus tanpa jeda
                    ReassertFreeze()
                    FCharF(tgt.guid, tgt.hrp)
                    if onStatus then
                        onStatus(">> ["..targetName.."] "..(tgt.guid:sub(1,5)).." Kill: "..TA.killed)
                    end
                    task.wait()
                else
                    task.wait(0.1)
                end
            end
        end)
        TA.threads = {tChar}
    end

    --  StartTA By Name 
    -- Source asli baris 6200-6272
    local function StartTA_ByName(targetName, onStatus, onStop)
        TA.running=true; TA.killed=0; TA.targetName=targetName; TA.cur=nil; TA.threads={}
        BlockEnemyHitAnim(true)
        BlockGlobalNuke(true)
        BlockSkillEffects(true, "TA")
        BlockAffectedTargetEffect(true, "TA")
        local tChar = task.spawn(function()
            local rrIdx    = 1
            local _curDied = false
            -- [HP-BASED DEATH DETECT] WatchTarget dipertahankan sebagai no-op guard
            -- (dipanggil dari beberapa tempat) tapi tidak lagi connect ke Humanoid.Died.
            -- Kematian target dideteksi via IsDeadF (_enemyHpByGuid) di kondisi
            -- while-loop rotasi round-robin di bawah.
            local function WatchTarget(tgt)
                -- sengaja kosong: tidak ada lagi listener Humanoid.Died
            end
            while TA.running do
                local pool = FindAllByNameF(targetName)
                if #pool == 0 then
                    if onStatus then onStatus("WAITING ["..targetName.."] respawn...") end
                    while TA.running do
                        task.wait(0.1)
                        pool = FindAllByNameF(targetName)
                        if #pool > 0 then break end
                    end
                    if not TA.running then break end
                    rrIdx=1; _curDied=false
                end
                if rrIdx > #pool then rrIdx = 1 end
                local tgt = pool[rrIdx]
                if not tgt or IsDeadF(tgt) then
                    rrIdx = rrIdx + 1
                    task.wait(0.1)
                else
                    TA.cur   = tgt
                    _curDied = false
                    TpToF(tgt); FreezePlayer()
                    WatchTarget(tgt)
                    while TA.running and not _curDied and not IsDeadF(tgt) and tgt.model.Parent do
                        -- [v27] GASS terus tanpa jeda
                        ReassertFreeze()
                        FCharF(tgt.guid, tgt.hrp)
                        if onStatus then
                            onStatus(">> ["..targetName.."] ["..rrIdx.."/"..#pool.."] Kill: "..TA.killed)
                        end
                        task.wait()
                    end
                    StopClickSpamF(tgt.guid)
                    StopHeroAtkThreadFor(tgt.guid)
                    if TA.running then
                        rrIdx    = rrIdx + 1
                        _curDied = false
                    end
                end
            end
        end)
        TA.threads = {tChar}
    end

    -- =========================================================================
    --  ENEMY HP MONITOR (WindUI Paragraph + Buttons) 
    -- Source asli baris 6289-6507
    -- WindUI tidak punya custom widget HP bar, jadi kita pakai:
    --   Paragraph untuk display HP + % + rate
    --   Button START / STOP / RESET stopwatch
    -- =========================================================================
    do
        local _ehpLastEnemyId = nil
        local _ehpMaxHp       = 0
        local _ehpConn        = nil
        local _ehpStartPct    = nil
        local _ehpCurPct      = 0

        local _swRunning    = false
        local _swStartTick  = nil
        local _swAccum      = 0
        local _swTimerConn  = nil

        -- Format angka: suffix K/M/B/T/Qa/Qi/Sx/Sp/Oc/No/Dc/Ud/Dd/Td (e03-e44),
        -- lalu format E kelipatan 3 (mirip TransferNumber game) untuk e45+
        -- (disamakan persis dengan dps_display.lua)
        local _NUM_SUFFIXES = {
            {1e3,  "K"},  {1e6,  "M"},  {1e9,  "B"},  {1e12, "T"},
            {1e15, "Qa"}, {1e18, "Qi"}, {1e21, "Sx"}, {1e24, "Sp"},
            {1e27, "Oc"}, {1e30, "No"}, {1e33, "Dc"}, {1e36, "Ud"},
            {1e39, "Dd"}, {1e42, "Td"},
        }
        local _NUM_E_START = 1e45

        local function FmtHp(n)
            if not n or n <= 0 then return "0" end

            if n < 1e3 then
                if n == math.floor(n) then
                    return tostring(math.floor(n))
                end
                return string.format("%.1f", n)
            end

            if n < _NUM_E_START then
                for i = #_NUM_SUFFIXES, 1, -1 do
                    local val, suf = _NUM_SUFFIXES[i][1], _NUM_SUFFIXES[i][2]
                    if n >= val then
                        local mant = n / val
                        if math.floor(mant * 10 + 0.5) % 10 == 0 then
                            return string.format("%d%s", math.floor(mant + 0.5), suf)
                        end
                        return string.format("%.1f%s", mant, suf)
                    end
                end
            end

            local exp  = math.floor(math.log10(n))
            local exp3 = math.floor(exp / 3) * 3
            local mant = n / (10 ^ exp3)
            if math.floor(mant * 10 + 0.5) % 10 == 0 then
                return string.format("%dE%d", math.floor(mant + 0.5), exp3)
            end
            return string.format("%.1fE%d", mant, exp3)
        end

        local function FmtTime(secs)
            local s = math.floor(secs)
            return string.format("%02d:%02d", math.floor(s/60), s%60)
        end
        local function HpColor(pct)
            if pct > 50 then return ""
            elseif pct > 25 then return ""
            else return "" end
        end

        local _ehpPara   = nil
        local _dpsPara   = nil
        local _timerPara = nil
        local _ratePara  = nil

        -- =========================================================
        -- DPS ENGINE (diambil dari dps_display.lua, disederhanakan)
        -- Sliding window 1 detik dari ShowEnemyTakeDamageInfo,
        -- hanya menampilkan angka realtime, tanpa tombol reset dll.
        -- =========================================================
        local MY_USER_ID   = tostring(LP and LP.UserId or "")
        local _DPS_WINDOW   = 1.0
        local _dpsHits      = {}   -- list {t=tick(), dmg=n}
        local _dpsConn      = nil

        local function DpsUpdateDisplay()
            local now    = tick()
            local cutoff = now - _DPS_WINDOW

            local i = 1
            while i <= #_dpsHits do
                if _dpsHits[i].t < cutoff then
                    table.remove(_dpsHits, i)
                else
                    i = i + 1
                end
            end

            local windowDmg = 0
            for _, h in ipairs(_dpsHits) do
                windowDmg = windowDmg + h.dmg
            end

            local dps = windowDmg / _DPS_WINDOW
            if _dpsPara then
                pcall(function() _dpsPara:SetDesc(" " .. FmtHp(dps)) end)
            end
        end

        local function SwGetElapsed()
            if _swRunning and _swStartTick then
                return _swAccum + (tick() - _swStartTick)
            end
            return _swAccum
        end

        local function SwUpdateDisplay()
            local elapsed = SwGetElapsed()
            if _timerPara then
                pcall(function()
                    _timerPara:SetDesc(" " .. FmtTime(elapsed) .. (_swRunning and " [RUNNING]" or " [PAUSED]"))
                end)
            end
            if _ratePara and _ehpStartPct and elapsed > 2 then
                local pctDone = _ehpStartPct - _ehpCurPct
                if pctDone > 0.01 then
                    pcall(function() _ratePara:SetDesc("1% setiap ~" .. FmtTime(elapsed / pctDone)) end)
                end
            end
        end

        do
            local _dpsLastUpdate = 0
            RunService.Heartbeat:Connect(function()
                local now = tick()
                if (now - _dpsLastUpdate) < 0.1 then return end
                _dpsLastUpdate = now
                DpsUpdateDisplay()
            end)
        end

        FarmTab:Section({ Title = " ENEMY HP MONITOR", Icon = "heart-pulse" })

        _ehpPara = FarmTab:Paragraph({ Title = "HP", Desc = " / " })
        _dpsPara = FarmTab:Paragraph({ Title = "DPS", Desc = " 0" })
        _timerPara = FarmTab:Paragraph({ Title = "Stopwatch", Desc = " 00:00 [STOPPED]" })
        _ratePara  = FarmTab:Paragraph({ Title = "Rate", Desc = "1% setiap ~--:--" })

        FarmTab:Button({
            Title    = " START Stopwatch",
            Desc     = "Mulai / lanjut hitung waktu",
            Callback = function()
                if _swRunning then return end
                _swRunning   = true
                _swStartTick = tick()
                if _ehpStartPct == nil then _ehpStartPct = _ehpCurPct end
                if not _swTimerConn then
                    local _swLastUpdate = 0
                    _swTimerConn = RunService.Heartbeat:Connect(function()
                        local now = tick()
                        if (now - _swLastUpdate) < 0.1 then return end
                        _swLastUpdate = now
                        SwUpdateDisplay()
                    end)
                end
            end,
        })
        FarmTab:Button({
            Title    = " STOP Stopwatch",
            Desc     = "Pause timer (bisa dilanjut)",
            Callback = function()
                if not _swRunning then return end
                _swAccum     = SwGetElapsed()
                _swRunning   = false
                _swStartTick = nil
                if _swTimerConn then
                    pcall(function() _swTimerConn:Disconnect() end)
                    _swTimerConn = nil
                end
                SwUpdateDisplay()
            end,
        })
        FarmTab:Button({
            Title    = " RESET Stopwatch",
            Desc     = "Reset timer ke 00:00",
            Callback = function()
                _swAccum     = 0
                _swRunning   = false
                _swStartTick = nil
                _ehpStartPct = nil
                if _swTimerConn then
                    pcall(function() _swTimerConn:Disconnect() end)
                    _swTimerConn = nil
                end
                if _timerPara then pcall(function() _timerPara:SetDesc(" 00:00 [STOPPED]") end) end
                if _ratePara   then pcall(function() _ratePara:SetDesc("1% setiap ~--:--") end) end
            end,
        })

        -- Pasang listener HP dari ShowEnemyTakeDamageInfo
        pcall(function()
            local RS  = game:GetService("ReplicatedStorage")
            local rem = RS:FindFirstChild("Remotes")
                     and RS.Remotes:FindFirstChild("ShowEnemyTakeDamageInfo")
            if rem then
                _ehpConn = rem.OnClientEvent:Connect(function(data)
                    if type(data) ~= "table" then return end
                    pcall(function()
                        -- [FIX] Game update memisahkan enemyGuid (string GUID asli) dari
                        -- enemyId (angka numerik biasa). TA.cur.guid selalu berformat GUID,
                        -- jadi harus match ke enemyGuid, bukan enemyId lagi.
                        local eid = tostring(data.enemyGuid or data.enemyId or "")
                        local hp  = tonumber(data.hp)    or 0
                        local mhp = tonumber(data.maxHp) or 0

                        -- [HP-BASED DEATH DETECT] Catat HP terkini per-guid ke table
                        -- global, dipakai IsTargetAliveRA (RA) & IsDeadF (TA).
                        -- SENGAJA TIDAK DIFILTER TA-only -- table ini dipakai untuk
                        -- SEMUA musuh (RA & TA sekaligus) supaya deteksi kematian
                        -- tetap akurat untuk kedua fitur. Yang difilter TA-only cuma
                        -- bagian DISPLAY di bawah (_ehpPara).
                        if eid ~= "" then
                            _enemyHpByGuid[eid] = hp
                        end

                        -- [FILTER TA-ONLY] Enemy HP Monitor (display) sekarang HANYA
                        -- mengikuti musuh yang sedang diserang Target Attack (TA.cur.guid)
                        -- saat TA.running. Damage dari Random Attack / Mass Attack ke
                        -- musuh lain diabaikan total di sini (DPS di bawah TIDAK ikut
                        -- difilter, tetap menghitung semua damage seperti biasa).
                        local taGuid = TA.running and TA.cur and tostring(TA.cur.guid) or nil
                        if not taGuid or eid == "" or eid ~= taGuid then return end

                        if eid ~= _ehpLastEnemyId then
                            _ehpLastEnemyId = eid
                            _ehpMaxHp       = mhp
                        end
                        if mhp > 0 and mhp > _ehpMaxHp then _ehpMaxHp = mhp end
                        local curMaxHp = (_ehpMaxHp > 0) and _ehpMaxHp or mhp
                        if curMaxHp <= 0 then return end
                        local pct = math.clamp(hp / curMaxHp * 100, 0, 100)
                        _ehpCurPct = pct
                        if _ehpPara then
                            pcall(function()
                                _ehpPara:SetDesc(
                                    HpColor(pct) .. " " .. FmtHp(hp) .. " / " .. FmtHp(curMaxHp)
                                    .. "  (" .. string.format("%.3f%%", pct) .. ")"
                                )
                            end)
                        end
                    end)
                    -- DPS capture: hanya damage dari player kita sendiri
                    pcall(function()
                        local uid = tostring(data.attackUserId or "")
                        if uid ~= MY_USER_ID then return end
                        local dmg = tonumber(data.attack) or tonumber(data.realityHarm) or 0
                        if dmg <= 0 then return end
                        table.insert(_dpsHits, {t = tick(), dmg = dmg})
                    end)
                end)
            end
        end)
    end -- end Enemy HP Monitor block

    -- =========================================================================
    --  SELECT ENEMY / TARGET ATTACK (TA) 
    -- Source asli baris 6519-6783
    --
    -- WindUI tidak punya dynamic scrollable row list, jadi pendekatan:
    --   1. Dropdown Mode (By ID / By Name)   Tab:Dropdown(Multi=false)
    --   2. Button "Refresh Enemies"          Tab:Button()
    --   3. Status Paragraph                  Tab:Paragraph() diupdate realtime
    --   4. Enemy rows disimulasikan via      Tab:Dropdown(Multi=false, Values=list)
    --      Single dropdown terpilih = target TA yang aktif
    --   5. Button "START TARGET ATTACK"      Tab:Button()
    --   6. Button "STOP TARGET ATTACK"       Tab:Button()
    --
    -- Logika identik, hanya UI layer yang beda (row individual  dropdown pilih target)
    -- =========================================================================
    local _taStatusPara      = FarmTab:Paragraph({ Title = "Status TA", Desc = "Idle" })

    -- Mode dropdown: By ID / By Name
    local _listMode = "id"
    FarmTab:Dropdown({
        Flag     = "farmTAMode",
        Title    = "Mode Select",
        Desc     = "By ID = target individu | By Name = musuh yang sama",
        Values   = {"By ID", "By Name"},
        Value    = "By ID",
        Multi    = false,
        Callback = function(val)
            local v = type(val)=="string" and val or nil
            if v == "By Name" then _listMode = "name"
            else _listMode = "id" end
        end,
    })

    -- Enemy dropdown  di-rebuild setiap klik Refresh Enemies
    local _enemyDropValues   = {}
    local _enemyDropSelected = nil
    local _enemyDropElement  = nil
    local _enemyDataById     = {}
    local _enemyDataByName   = {}

    _enemyDropElement = FarmTab:Dropdown({
        -- Flag tidak dipasang: list ini di-rebuild dinamis tiap REFRESH ENEMIES,
        -- nilai yang disimpan tidak bermakna lintas sesi (GUID enemy berubah).
        Title    = "Pilih Enemy",
        Desc     = "Klik REFRESH ENEMIES untuk load daftar musuh",
        Values   = {},
        Value    = nil,
        Multi    = false,
        Callback = function(val)
            _enemyDropSelected = type(val)=="string" and val or nil

            -- Auto-switch target jika TA sedang running  tidak perlu OFF/ON lagi
            if not _enemyDropSelected then return end
            if not TA.running then return end

            -- Stop TA lama
            StopTA()

            -- Start TA ke target baru sesuai mode
            if _listMode == "id" then
                local data = _enemyDataById[_enemyDropSelected]
                if not data then
                    if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Enemy tidak valid, Refresh dulu") end) end
                    -- Toggle kembali ke OFF karena target tidak valid
                    if _taToggleElement then pcall(function() _taToggleElement:Set(false, false) end) end
                    return
                end
                StartTA_ByID(data.guid, data.name,
                    function(msg)
                        if _taStatusPara then pcall(function() _taStatusPara:SetDesc(msg) end) end
                    end,
                    _taOnStop
                )
            else
                local data = _enemyDataByName[_enemyDropSelected]
                if not data then
                    if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Enemy tidak valid, Refresh dulu") end) end
                    if _taToggleElement then pcall(function() _taToggleElement:Set(false, false) end) end
                    return
                end
                StartTA_ByName(data.nm,
                    function(msg)
                        if _taStatusPara then pcall(function() _taStatusPara:SetDesc(msg) end) end
                    end,
                    _taOnStop
                )
            end
        end,
    })

    -- Refresh Enemies  scan workspace + rebuild dropdown sekaligus (soal 7 & 8)
    FarmTab:Button({
        Title    = " REFRESH ENEMIES",
        Desc     = "Scan & isi dropdown dengan musuh hidup beserta ID-nya",
        Callback = function()
            -- Stop TA dulu jika sedang running
            if TA.running then
                StopTA()
                if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Stopped (Refresh)") end) end
            end
            _enemyDataById   = {}
            _enemyDataByName = {}
            _enemyDropValues = {}
            _enemyDropSelected = nil

            local enemies = GetEnemiesF()
            if #enemies == 0 then
                if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Map kosong  tidak ada musuh") end) end
                if _enemyDropElement then pcall(function() _enemyDropElement:Set({}) end) end
                return
            end

            if _listMode == "id" then
                table.sort(enemies, function(a,b) return a.name < b.name end)
                for _, e in ipairs(enemies) do
                    local label = e.name .. " [" .. e.guid:sub(1,8) .. "]"
                    table.insert(_enemyDropValues, label)
                    _enemyDataById[label] = {guid=e.guid, name=e.name}
                end
                if _taStatusPara then
                    pcall(function() _taStatusPara:SetDesc(#enemies .. " musuh (By ID)  pilih dari dropdown") end)
                end
            else
                local nc = {}
                for _, e in ipairs(enemies) do nc[e.name]=(nc[e.name] or 0)+1 end
                local names = {}
                for nm in pairs(nc) do table.insert(names, nm) end
                table.sort(names)
                for _, nm in ipairs(names) do
                    local label = nm .. " x" .. nc[nm]
                    table.insert(_enemyDropValues, label)
                    _enemyDataByName[label] = {nm=nm}
                end
                if _taStatusPara then
                    pcall(function() _taStatusPara:SetDesc(#names .. " jenis, " .. #enemies .. " total (By Name)") end)
                end
            end

            -- Rebuild dropdown dengan data baru
            if _enemyDropElement then
                pcall(function() _enemyDropElement:Refresh(_enemyDropValues, nil) end)
                -- Fallback jika Refresh tidak tersedia di versi WindUI ini
                pcall(function()
                    _enemyDropElement.Values = _enemyDropValues
                end)
            end
        end,
    })

    -- =========================================================================
    --  RANDOM ATTACK (RA) 
    -- Source asli baris 6509-6517
    -- =========================================================================
    local _raToggleElement = FarmTab:Toggle({
        Flag     = "farmRA",
        Title    = "RANDOM ATTACK",
        Desc     = "Auto attack musuh random sampai mati, lalu ganti target",
        Value    = false,
        Callback = function(on)
            _raRunningState = on
            if on then StartRA() else StopRA() end
        end,
    })

    _setRAToggle = function(v)
        _raRunningState = v
        if _raToggleElement then pcall(function() _raToggleElement:Set(v) end) end
    end
    _visRandomAtk = function(v)
        if _raToggleElement then pcall(function() _raToggleElement:Set(v, false) end) end
    end

    -- TARGET ATTACK Toggle (ON = START, OFF = STOP)  soal 9
    local _taToggleElement = nil
    local function _taOnStop()
        -- [SYNC RA+TA] Kalau target TA mati SAAT RA juga sedang aktif bersamaan,
        -- DAN mode select-nya "By ID" (bukan "By Name") -> matikan RA juga secara
        -- total (fungsi/logika + visual toggle), bukan cuma TA.
        -- Tidak berlaku kalau RA sedang OFF, atau mode-nya "By Name".
        if _listMode == "id" and RA.running then
            StopRA()
            _raRunningState = false
            if _raToggleElement then pcall(function() _raToggleElement:Set(false, false) end) end
        end

        if _taToggleElement then
            pcall(function() _taToggleElement:Set(false, false) end)
        end
        if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Target mati  pilih enemy baru & ON lagi") end) end
    end

    _taToggleElement = FarmTab:Toggle({
        Flag     = "farmTA",
        Title    = "TARGET ATTACK",
        Desc     = "ON = mulai serang target terpilih | OFF = stop",
        Value    = false,
        Callback = function(on)
            if on then
                if not _enemyDropSelected then
                    if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Pilih enemy dulu dari dropdown!") end) end
                    task.defer(function()
                        if _taToggleElement then
                            pcall(function() _taToggleElement:Set(false, false) end)
                        end
                    end)
                    return
                end
                if TA.running then StopTA() end

                if _listMode == "id" then
                    local data = _enemyDataById[_enemyDropSelected]
                    if not data then
                        if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Enemy tidak valid, Refresh dulu") end) end
                        task.defer(function()
                            if _taToggleElement then pcall(function() _taToggleElement:Set(false, false) end) end
                        end)
                        return
                    end
                    StartTA_ByID(data.guid, data.name,
                        function(msg)
                            if _taStatusPara then pcall(function() _taStatusPara:SetDesc(msg) end) end
                        end,
                        _taOnStop
                    )
                else
                    local data = _enemyDataByName[_enemyDropSelected]
                    if not data then
                        if _taStatusPara then pcall(function() _taStatusPara:SetDesc("[!] Enemy tidak valid, Refresh dulu") end) end
                        task.defer(function()
                            if _taToggleElement then pcall(function() _taToggleElement:Set(false, false) end) end
                        end)
                        return
                    end
                    StartTA_ByName(data.nm,
                        function(msg)
                            if _taStatusPara then pcall(function() _taStatusPara:SetDesc(msg) end) end
                        end,
                        _taOnStop
                    )
                end
            else
                StopTA()
                if _taStatusPara then pcall(function() _taStatusPara:SetDesc("Stop") end) end
            end
        end,
    })

    -- ════════════════════════════════════════════════════════════════════════
    --  SECTION: FAST ATTACK 1 ENEMYS
    --  Duplikat salah satu musuh secara RANDOM dari workspace.Enemys.
    --  Clone disimpan di workspace.Enemys selama toggle ON.
    --  Ketika OFF → clone dihapus, koneksi dibersihkan.
    --
    --  Strategi:
    --    1. Ambil anak pertama workspace.Enemys yang valid (Model + HumanoidRootPart)
    --    2. Clone model tersebut
    --    3. Set EnemyGuid baru agar tidak bentrok dengan enemy asli
    --    4. Parent ke workspace.Enemys
    --    5. Heartbeat: jika enemy asli mati → pilih ulang (respawn) clone baru
    --    6. OFF → hapus clone + disconnect Heartbeat
    -- ════════════════════════════════════════════════════════════════════════
    FarmTab:Section({ Title = " FAST ATTACK 1 ENEMYS", Icon = "zap" })

    local _dupePara = FarmTab:Paragraph({
        Title = "Status",
        Desc  = "Idle",
    })

    -- State FAST ATTACK 1 ENEMYS
    local _dupeOn        = false
    local _dupeClone     = nil   -- referensi clone aktif
    local _dupeConn      = nil   -- Heartbeat connection (GET: monitor & respawn clone)

    -- State START (spawn di depan Player + face-lock ke Player)
    local _spawnOn          = false
    local _spawnConn        = nil  -- Heartbeat connection (START: hadapkan clone ke Player)
    local _spawnFixedCFrame = nil  -- posisi tetap hasil spawn, tidak ikut player setelah itu

    -- Config jarak spawn di depan Player
    local _SPAWN_DISTANCE = 8 -- studs di depan player

    -- Helper: set desc paragraph
    local function _dupeStatus(msg)
        if _dupePara then pcall(function() _dupePara:SetDesc(msg) end) end
    end

    -- GUID attrs yang mungkin dipakai game
    local _GUID_ATTRS = {"EnemyGuid","BossGuid","Guid","GUID"}

    -- Helper: baca GUID dari model (return attrName, value)
    local function _getGuid(model)
        for _, attr in ipairs(_GUID_ATTRS) do
            local v = model:GetAttribute(attr)
            if v then return attr, v end
        end
        return nil, nil
    end

    -- Helper: ambil random enemy valid dari workspace.Enemys (skip clone sendiri by GUID)
    local function _getRandomEnemy()
        local folder = workspace:FindFirstChild("Enemys")
        if not folder then return nil end

        -- GUID clone aktif untuk di-skip
        local cloneGuid = nil
        if _dupeClone then
            local _, g = _getGuid(_dupeClone)
            cloneGuid = g
        end

        local valid = {}
        for _, e in ipairs(folder:GetChildren()) do
            if e:IsA("Model") and e ~= _dupeClone then
                local _, g = _getGuid(e)
                if g and g ~= cloneGuid then
                    local hrp = e:FindFirstChild("HumanoidRootPart")
                             or e.PrimaryPart
                             or e:FindFirstChildWhichIsA("BasePart")
                    local hum = e:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        table.insert(valid, {model=e, guid=g, hrp=hrp})
                    end
                end
            end
        end
        if #valid == 0 then return nil end
        return valid[math.random(1, #valid)]
    end

    -- Helper: spawn clone dari model enemy sumber
    -- GUID dipakai ASLI persis dari enemy sumber (Clone() sudah copy semua Attributes)
    -- Posisi PERSIS sama (tidak di-offset) -- identik Ctrl+D / Duplicate manual di Studio
    local function _spawnClone(srcData)
        if _dupeClone then
            pcall(function() _dupeClone:Destroy() end)
            _dupeClone = nil
        end

        local src = srcData.model
        local ok, clone = pcall(function() return src:Clone() end)
        if not ok or not clone then return nil end

        -- Clone() sudah menyalin SEMUA Attributes (termasuk EnemyGuid, BossGuid, dll)
        -- dan posisi HumanoidRootPart persis sama dengan enemy asli
        -- Tidak perlu override apapun -- identik dengan Duplicate manual

        clone.Parent = workspace:FindFirstChild("Enemys")
        _dupeClone   = clone
        return clone
    end

    -- Helper: stop SPAWN (bersihkan face-lock conn + posisi tetap, TIDAK menghapus clone)
    local function _stopSpawnFacing()
        if _spawnConn then
            pcall(function() _spawnConn:Disconnect() end)
            _spawnConn = nil
        end
        _spawnOn = false
        _spawnFixedCFrame = nil
    end

    -- Helper: stop DUPE (bersihkan clone + conn + spawn state)
    local function _stopDupe()
        if _dupeConn then
            pcall(function() _dupeConn:Disconnect() end)
            _dupeConn = nil
        end
        _stopSpawnFacing()
        if _dupeClone then
            pcall(function() _dupeClone:Destroy() end)
            _dupeClone = nil
        end
        _dupeOn = false
        _dupeStatus("Idle")
    end

    -- Helper: mulai DUPE loop via Heartbeat
    local function _startDupe()
        -- pilih enemy awal
        local srcData = _getRandomEnemy()
        if not srcData then
            _dupeStatus("[!] Tidak ada enemy di workspace.Enemys")
            _dupeOn = false
            return
        end

        -- spawn clone pertama
        _spawnClone(srcData)
        _dupeStatus("SUCCESS - Random Attack First")

        -- Heartbeat: monitor clone; respawn jika mati/hilang
        local _dupeHbThrottle = 0
        _dupeConn = RunService.Heartbeat:Connect(function(dt)
            if not _dupeOn then return end

            -- throttle: cek setiap ~0.5s saja, tidak perlu tiap frame
            _dupeHbThrottle = _dupeHbThrottle + dt
            if _dupeHbThrottle < 0.5 then return end
            _dupeHbThrottle = 0

            local cloneAlive = false
            pcall(function()
                if _dupeClone and _dupeClone.Parent then
                    local hum = _dupeClone:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        cloneAlive = true
                    end
                end
            end)

            if not cloneAlive then
                -- clone mati/hilang → pilih enemy baru dan spawn clone baru
                local newData = _getRandomEnemy()
                if newData then
                    _spawnClone(newData)
                    _dupeStatus("SUCCESS - Select Enemy Target")
                else
                    _dupeStatus("SUCCESS - Attack Target Enemy")
                end
            end
        end)
    end

    -- Helper: mulai SPAWN (posisikan clone di depan Player, sekali, lalu clone terus
    -- menghadap ke Player kemanapun Player berjalan. Posisi TIDAK ikut Player.)
    local function _startSpawn()
        if not _dupeClone or not _dupeClone.Parent then
            _dupeStatus("[!] Belum ada clone. Tekan GET dahulu")
            return
        end

        local char = LP.Character
        local pHRP = char and char:FindFirstChild("HumanoidRootPart")
        if not pHRP then
            _dupeStatus("[!] Character/HumanoidRootPart Player tidak ditemukan")
            return
        end

        local cloneHRP = _dupeClone:FindFirstChild("HumanoidRootPart")
                       or _dupeClone.PrimaryPart
                       or _dupeClone:FindFirstChildWhichIsA("BasePart")
        if not cloneHRP then
            _dupeStatus("[!] Clone tidak punya bagian tubuh valid")
            return
        end

        -- hentikan facing-loop lama (jika START ditekan ulang) sebelum reposisi
        _stopSpawnFacing()

        -- hitung posisi tetap: beberapa studs di depan Player, hadap ke Player
        local pCFrame   = pHRP.CFrame
        local spawnPos  = pCFrame.Position + (pCFrame.LookVector * _SPAWN_DISTANCE)
        local faceToPlr = CFrame.lookAt(spawnPos, Vector3.new(pHRP.Position.X, spawnPos.Y, pHRP.Position.Z))
        _spawnFixedCFrame = faceToPlr

        pcall(function()
            if _dupeClone.PrimaryPart then
                _dupeClone:SetPrimaryPartCFrame(_spawnFixedCFrame)
            else
                _dupeClone:PivotTo(_spawnFixedCFrame)
            end
        end)

        _spawnOn = true
        _dupeStatus("SUCCESS - Enemy Spawned In Front Of Player")

        -- Heartbeat: posisi tetap diam di _spawnFixedCFrame, tapi rotasi selalu
        -- menghadap ke Player kemanapun Player berjalan (posisi X/Z/Y clone tidak berubah)
        _spawnConn = RunService.Heartbeat:Connect(function()
            if not _spawnOn then return end
            if not _dupeClone or not _dupeClone.Parent then
                _stopSpawnFacing()
                return
            end

            local pChar = LP.Character
            local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
            local cRoot = _dupeClone:FindFirstChild("HumanoidRootPart")
                        or _dupeClone.PrimaryPart
                        or _dupeClone:FindFirstChildWhichIsA("BasePart")
            if not pRoot or not cRoot or not _spawnFixedCFrame then return end

            local fixedPos = _spawnFixedCFrame.Position
            local lookCF   = CFrame.lookAt(fixedPos, Vector3.new(pRoot.Position.X, fixedPos.Y, pRoot.Position.Z))

            pcall(function()
                if _dupeClone.PrimaryPart then
                    _dupeClone:SetPrimaryPartCFrame(lookCF)
                else
                    _dupeClone:PivotTo(lookCF)
                end
            end)
        end)
    end

    -- Helper: STOP -> hapus clone (musuh duplikat) + hapus posisi spawn (reset semua state)
    local function _stopSpawn()
        _stopDupe()
        _dupeStatus("Idle")
    end

    -- Button GET (logika identik dengan toggle lama: pilih random enemy, clone,
    -- auto-respawn via Heartbeat jika clone mati)
    FarmTab:Button({
        Title    = "GET",
        Desc     = "START FIRST",
        Callback = function()
            -- restart bersih setiap kali GET ditekan
            if _dupeConn then
                pcall(function() _dupeConn:Disconnect() end)
                _dupeConn = nil
            end
            _stopSpawnFacing()
            if _dupeClone then
                pcall(function() _dupeClone:Destroy() end)
                _dupeClone = nil
            end
            _dupeOn = true
            BlockEnemyHitAnim(true)
            BlockGlobalNuke(true)
            _startDupe()
        end,
    })

    -- Button START (spawn clone hasil GET di depan Player, posisi tetap, hadap ke Player)
    FarmTab:Button({
        Title    = "START",
        Desc     = "CLICK",
        Callback = function()
            _startSpawn()
        end,
    })

    -- Button STOP (hapus clone + hapus posisi spawn)
    FarmTab:Button({
        Title    = "STOP",
        Desc     = "Delete",
        Callback = function()
            _stopSpawn()
            if not RA.running and not TA.running then
                BlockEnemyHitAnim(false)
                BlockGlobalNuke(false)
            end
        end,
    })

end -- end do PANEL: FARM


-- ============================================================================
-- PANEL: AUTOMATION - AUTO RAID (v30)
-- Port dari 1.lua baris 8875-14697 ke WindUI
-- Section slide up/down persis seperti 1.lua, menggunakan AutomationTab
-- ============================================================================

do -- AUTO RAID: DATA & STATE GLOBAL

-- Remote tambahan untuk RAID (di luar yang sudah ada di RE)
RE = RE or {}
RE.CreateRaidTeam       = RE.CreateRaidTeam       or Remotes:FindFirstChild("CreateRaidTeam")
RE.StartChallengeRaidMap= RE.StartChallengeRaidMap or Remotes:FindFirstChild("StartChallengeRaidMap")
RE.LocalTpSuccess       = RE.LocalTpSuccess        or Remotes:FindFirstChild("LocalPlayerTeleportSuccess")
RE.UseRaidItem          = RE.UseRaidItem           or Remotes:FindFirstChild("UseRaidItem")
RE.GetRaidTeamInfos     = RE.GetRaidTeamInfos      or Remotes:FindFirstChild("GetRaidTeamInfos")
-- [FIX] Hero remotes untuk AUTO BOSS KILL (UnEquip -> EquipBest setelah TP)
RE.UnEquipHero          = RE.UnEquipHero           or Remotes:FindFirstChild("UnequipAllHero")
RE.EquipBestHero        = RE.EquipBestHero         or Remotes:FindFirstChild("AutoEquipBestHero")
RE.EquipHeroWithData    = RE.EquipHeroWithData      or Remotes:FindFirstChild("EquipHeroWithData")
RE.HeroStand            = RE.HeroStand             or Remotes:FindFirstChild("HeroStandTo")

--  SPAWN_RANK 
SPAWN_RANK = SPAWN_RANK or {
    RE1001=1, RE1002=2, RE1003=3, RE1004=4, RE1005=5, RE1006=6,
}

--  RANK_LABEL 
RANK_LABEL = RANK_LABEL or {
    [1]="E",[2]="D",[3]="C",[4]="B",[5]="A",
    [6]="S",[7]="SS",[8]="G",[9]="N",[10]="M",
    [11]="M+",[12]="M++",[15]="XM",[17]="ULT",
}

--  MAP_NAMES 
MAP_NAMES = MAP_NAMES or {
    [1]="Shadow Gate City",[2]="Level Grinding Cavern",[3]="Shadow Castle",
    [4]="Seolhan Forest",[5]="Demon Castle - Tier 1",[6]="Orc Palace",
    [7]="Demon Castle - Tier 2",[8]="Ant Island",[9]="Land of Giant",
    [10]="Plagueheart",[11]="Umbralfrost Domain",[12]="Kamish's Demise",
    [13]="Lava Hell",[14]="Illusory World",[15]="Inferno Altar",
    [16]="Shadow Throne",[17]="Angel Holy Realm",[18]="Golden Throne",
    [19]="Dragon Ball City",[20]="Dragon Ball Wasteland",[21]="Cursed City",
}

--  GRADE_LIST / GRADE_RANK 
GRADE_LIST = GRADE_LIST or {"E","D","C","B","A","S","SS","G","N","M","M+","M++","XM","ULT"}
GRADE_RANK = GRADE_RANK or {
    ["E"]=1,["D"]=2,["C"]=3,["B"]=4,["A"]=5,["S"]=6,["SS"]=7,
    ["G"]=8,["N"]=9,["M"]=10,["M+"]=11,["M++"]=12,["XM"]=15,["ULT"]=17,["GOD"]=18,
}

--  RAID_CONFIG_GRADE (formula dari raidId) 
if not RAID_CONFIG_GRADE then
    local _GRADE_IDX  = {"E","D","C","B","A","S","SS","G","N","M","M+","M++","XM","ULT","GOD"}
    local _GRADE_RAID = {"D","B","S","SS","G","N","M+","M++","XM","ULT"}
    RAID_CONFIG_GRADE = setmetatable({},{
        __index = function(_, raidId)
            if type(raidId) ~= "number" then return nil end
            if raidId == 937101 then return nil end
            if raidId >= 935001 then return _GRADE_IDX[raidId%100] or "?" end
            if raidId >= 930001 then return _GRADE_RAID[(raidId-930001)%10+1] or "?" end
            return nil
        end
    })
end

--  RAID_SPAWN_POS 
RAID_SPAWN_POS = RAID_SPAWN_POS or {
    [50101]=Vector3.new(2424.9,8.5,482.9),[50102]=Vector3.new(1683.1,8.6,-24.1),
    [50103]=Vector3.new(1913.1,12,-194.4),[50104]=Vector3.new(515.8,7.6,-98.0),
    [50105]=Vector3.new(-229.3,9.6,-2.3),[50106]=Vector3.new(1998.2,8.0,237.7),
    [50107]=Vector3.new(-42.0,8.4,334.0),[50108]=Vector3.new(-925.8,-396.2,-901.6),
    [50109]=Vector3.new(8.7,13.0,244.2),[50110]=Vector3.new(2003.0,8.1,344.0),
    [50111]=Vector3.new(2068.0,49.4,-155.8),[50112]=Vector3.new(16.5,9.0,269.5),
    [50113]=Vector3.new(2100.7,63.1,423.1),[50114]=Vector3.new(27.8,49.8,303.9),
    [50115]=Vector3.new(-0.9,24.0,185.3),[50116]=Vector3.new(1999.6,17.0,236.5),
    [50117]=Vector3.new(-0.4,18.5,93.5),[50118]=Vector3.new(2000.0,45.4,234.7),
    [50119]=Vector3.new(0,10.0,0),[50120]=Vector3.new(0,10.0,0),
}

--  RAID_MAP_INFO 
RAID_MAP_INFO = RAID_MAP_INFO or {
    [1]={instance="Map1",rootPart="4025"},[2]={instance="Map2",rootPart="4050"},
    [3]={instance="Map3",rootPart="4025"},[4]={instance="Map4",rootPart="4050"},
    [5]={instance="Map5",rootPart="4050"},[6]={instance="Map6",rootPart="4044"},
    [7]={instance="Map7",rootPart="4050"},[8]={instance="Map8",rootPart="4050"},
    [9]={instance="Map9",rootPart="4050"},[10]={instance="Map10",rootPart="4050"},
    [11]={instance="Map11",rootPart="4050"},[12]={instance="Map12",rootPart="4050"},
    [13]={instance="Map13",rootPart="4050"},[14]={instance="Map14",rootPart="4050"},
    [15]={instance="Map15",rootPart="4050"},[16]={instance="Map16",rootPart="4050"},
    [17]={instance="Map17",rootPart="4050"},[18]={instance="Map18",rootPart="4050"},
    [19]={instance="Map19",rootPart="4050"},[20]={instance="Map20",rootPart="4050"},
    [21]={instance="Map21",rootPart="4050"},
}

--  RAID & ASC STATE TABLES 
if not RAID then
    RAID = {
        running=false,inMap=false,thread=nil,sukses=0,collected=0,
        raidId=0,raidMapId=50001,slotIndex=2,fromMapId=nil,serverMapId=nil,
        _raidDone=false,statusLbl=nil,suksesLbl=nil,dot=nil,
        difficulty="easy",preferMaps={},runeGrades={},runeEnabled=false,
        runeMapTarget=0,
        -- [SLOT MANAGER] 3 toggle rank independen (2x UP + 1x DOWN) + Rune Map
        -- (dropdown existing) berbagi MAKSIMAL 2 slot fisik (slotIndex 1 & 2).
        -- _slotOrder = urutan nyala toggle non-rune (dipakai utk tentukan siapa
        -- yang di-auto-off duluan kalau slot penuh). Rune Map TIDAK pernah masuk
        -- _slotOrder karena dia selalu menang slotIndex=1 (lihat ResolveItemSlots).
        upRankAEnabled=false, upRankBEnabled=false, downRankEnabled=false,
        _slotOrder={},
        diffLbl=nil,snapshotMapId=nil,
        listEntries={},listEnabled=false,_listVisitedMaps={},
        autoKillBoss=false,bossDelay=3,pickMode="default",
        manualMatchMode="none",updateActiveLabel=nil,activeRaidLbl=nil,
    }
end
if not ASC then
    ASC = {
        running=false,inMap=false,thread=nil,sukses=0,pickMode="easy",
        preferMaps={},runeGrades={},runeEnabled=false,runeMapTarget=0,
        -- [SLOT MANAGER] sama seperti RAID (lihat catatan di atas)
        upRankAEnabled=false, upRankBEnabled=false, downRankEnabled=false,
        _slotOrder={},
        preferMapTarget=0,manualMatchMode="none",_rrIdx=0,
        autoKillBoss=false,bossDelay=3,listEnabled=false,listEntries={},
        _listVisitedMaps={},statusLbl=nil,dot=nil,suksesLbl=nil,serverMapId=nil,
    }
end

-- ============================================================================
-- [SLOT MANAGER] Auto Item Rank (UP-A / UP-B / DOWN) + Rune Map berbagi
-- MAKSIMAL 2 slot fisik (slotIndex 1 & 2) yang dikirim ke remote UseRaidItem.
-- Dipakai bersama oleh panel RAID dan ASC/Tower (state = RAID atau ASC).
--
-- ATURAN (dikonfirmasi user):
--   1) Maksimal 2 dari 4 kandidat (Rune Map, UP-A, UP-B, DOWN) boleh ON.
--   2) Rune Map, kalau ON, SELALU menempati slotIndex=1. Kandidat non-rune
--      yang sedang ON "digeser" ke slotIndex=2 (TIDAK dimatikan).
--   3) Kalau Rune Map OFF: slotIndex ditentukan urutan nyala non-rune
--      (duluan ON = slotIndex 1, berikutnya = slotIndex 2).
--   4) Menyalakan toggle ke-3 (non-rune) saat 2 slot non-rune sudah penuh
--      akan mematikan toggle non-rune yang PALING LAMA nyala secara
--      otomatis (Rune Map tidak pernah kena auto-off, dia selalu menang
--      tempat di slotIndex=1).
--
-- state._slotOrder menyimpan urutan nyala kandidat NON-RUNE saja (array of
-- "upA"/"upB"/"down", terlama di index 1). Rune Map dibaca langsung dari
-- state.runeEnabled (tidak perlu tracking order, karena dia selalu menang).
-- ============================================================================

-- Dipanggil dari Callback tiap toggle rank saat statusnya jadi ON.
-- name = "upA" / "upB" / "down". Mengurus auto-off kandidat lain kalau perlu.
-- setToggleUiFn(name, on) = callback untuk update visual toggle UI kalau ada
-- kandidat lain yang di-auto-off (supaya UI tetap sinkron dengan state).
function SlotManager_OnEnable(state, name, setToggleUiFn)
    -- Buang dulu kalau sudah ada di order (hindari duplikat)
    for i = #state._slotOrder, 1, -1 do
        if state._slotOrder[i] == name then table.remove(state._slotOrder, i) end
    end
    table.insert(state._slotOrder, name) -- paling baru = paling akhir

    -- Slot non-rune yang tersedia: 2 kalau Rune Map OFF, 1 kalau Rune Map ON
    -- (karena Rune Map selalu ambil slotIndex=1).
    local maxNonRuneSlots = state.runeEnabled and 1 or 2

    while #state._slotOrder > maxNonRuneSlots do
        local victim = table.remove(state._slotOrder, 1) -- paling lama nyala
        if victim == "upA" then state.upRankAEnabled = false
        elseif victim == "upB" then state.upRankBEnabled = false
        elseif victim == "down" then state.downRankEnabled = false end
        if setToggleUiFn then pcall(setToggleUiFn, victim, false) end
    end
end

-- Dipanggil dari Callback tiap toggle rank saat statusnya jadi OFF (manual).
function SlotManager_OnDisable(state, name)
    for i = #state._slotOrder, 1, -1 do
        if state._slotOrder[i] == name then table.remove(state._slotOrder, i) end
    end
end

-- Dipanggil saat Rune Map ON dinyalakan: non-rune yang ON "digeser" (TIDAK
-- dimatikan), tapi kalau ternyata ada 2 non-rune ON sekaligus (harusnya tidak
-- mungkin karena slot manager sudah jaga max 2 total, tapi jaga-jaga), yang
-- paling lama nyala di-auto-off supaya sisa cuma 1 (karena slot non-rune
-- cuma 1 saat Rune Map ON).
function SlotManager_OnRuneEnabled(state, setToggleUiFn)
    while #state._slotOrder > 1 do
        local victim = table.remove(state._slotOrder, 1)
        if victim == "upA" then state.upRankAEnabled = false
        elseif victim == "upB" then state.upRankBEnabled = false
        elseif victim == "down" then state.downRankEnabled = false end
        if setToggleUiFn then pcall(setToggleUiFn, victim, false) end
    end
end

-- Resolve slotIndex FINAL untuk fire ke remote UseRaidItem, dipanggil saat
-- benar-benar masuk raid (bukan saat toggle diklik). Return array terurut:
--   { {name="rune", itemId=X, slotIndex=1}, {name="upA", itemId=Y, slotIndex=2}, ... }
-- RUNE_ITEM_ID = itemId rune yang sudah dihitung oleh caller (tergantung
-- target map), atau nil kalau Rune Map OFF.
function SlotManager_ResolveFireList(state, runeItemId)
    local UP_ITEM_ID, DOWN_ITEM_ID = 10270, 10271
    local list = {}

    if state.runeEnabled and runeItemId then
        table.insert(list, { name = "rune", itemId = runeItemId })
    end

    -- Urutan non-rune ikuti _slotOrder (terlama duluan = slotIndex lebih kecil)
    for _, name in ipairs(state._slotOrder) do
        if name == "upA" and state.upRankAEnabled then
            table.insert(list, { name = "upA", itemId = UP_ITEM_ID })
        elseif name == "upB" and state.upRankBEnabled then
            table.insert(list, { name = "upB", itemId = UP_ITEM_ID })
        elseif name == "down" and state.downRankEnabled then
            table.insert(list, { name = "down", itemId = DOWN_ITEM_ID })
        end
    end

    -- [FIX] Potong list ke MAX 2 SEBELUM assign slotIndex - mencegah entry ke-3+
    -- (kalau _slotOrder somehow punya lebih dari yang seharusnya, misal state
    -- corrupt dari sesi lama) ikut fire dengan slotIndex=nil yang gagal senyap
    -- di server. Rune SELALU diprioritaskan (dia sudah di index 1 kalau ada).
    while #list > 2 do
        table.remove(list) -- buang dari belakang (yang paling baru/terakhir masuk)
    end

    -- Assign slotIndex final berdasar posisi di list (max 2, dijamin oleh potongan di atas)
    for i, entry in ipairs(list) do
        entry.slotIndex = i
    end

    return list
end

_ascOn           = _ascOn           or false
_ascWakeup       = _ascWakeup       or nil
_ascBusy         = _ascBusy         or false
_ascMatchedThisCycle  = _ascMatchedThisCycle  or false
_raidFallbackActive   = _raidFallbackActive   or false
_eventOwner           = _eventOwner           or nil
_ascInterrupt    = _ascInterrupt    or false
_MAP_ENTER_LOCK  = _MAP_ENTER_LOCK  or nil
_MAP_ENTER_LOCK_TIME = _MAP_ENTER_LOCK_TIME or 0
_raidIdRefreshCb = _raidIdRefreshCb or nil
_runeGradeCache  = _runeGradeCache  or {}
_ASC_CHAT_CACHE  = _ASC_CHAT_CACHE  or {}
_pendingTowerNum  = _pendingTowerNum  or nil
_pendingTowerTime = _pendingTowerTime or 0
_raidSessionStart = _raidSessionStart or nil
_defaultRRIdx    = _defaultRRIdx    or 0
_entryWakeupTimer = _entryWakeupTimer or nil
_ENTRY_DEBOUNCE_SEC = _ENTRY_DEBOUNCE_SEC or 3

-- Forward declare fungsi yang diperlukan UI
_setRaidToggle   = nil
_visRaidToggle   = nil
_setAscToggle    = nil
_visAscToggle    = nil
_setRaidPMIdx    = nil
_setAscPMIdx     = nil
_raidBossToggleVis   = nil
_raidBossDelaySet    = nil
_raidUpdatePrefLabel = nil
_raidUpdateRankLabel = nil
_raidRebuildListRows = nil
_setRaidListEnabledVis = nil
_setRaidRuneMapTarget= nil
_syncRaidRuneState   = nil
_prefLocked = false; _rankLocked = false; _runeLocked = false; _listLocked = false
_prefLockLbl=nil; _rankLockLbl=nil; _runeLockLbl=nil
_prefKeyL=nil; _rankKeyL=nil; _runeKeyL=nil
_ascUpdatePrefLabel  = nil
_ascUpdateRankLabel  = nil
_setAscRuneMapTarget = nil
_ascPrefLocked = false; _ascRankLocked = false; _ascRuneLocked = false

--  RAID_LIVE & RAID_ID_LIST 
RAID_LIVE    = RAID_LIVE    or {}
RAID_ID_LIST = RAID_ID_LIST or {}

--  ATOMIC MAP LOCK 
function TryClaimMapLock(featureName)
    local now = os.clock()
    if _MAP_ENTER_LOCK == nil or _MAP_ENTER_LOCK == featureName then
        _MAP_ENTER_LOCK = featureName; _MAP_ENTER_LOCK_TIME = now; return true
    end
    if (now - _MAP_ENTER_LOCK_TIME) > 30 then
        _MAP_ENTER_LOCK = featureName; _MAP_ENTER_LOCK_TIME = now; return true
    end
    return false
end

function ReleaseMapLock(featureName)
    if _MAP_ENTER_LOCK == featureName then
        _MAP_ENTER_LOCK = nil; _MAP_ENTER_LOCK_TIME = 0
    end
end

function IsAnyMapActive()
    if RAID and RAID.inMap then return true,"raid" end
    if ASC  and ASC.inMap  then return true,"asc"  end
    if SIEGE and SIEGE.inMap then return true,"siege" end
    if ST2 and ST2.inMap then return true,"st2" end
    if _MAP_ENTER_LOCK ~= nil then return true,_MAP_ENTER_LOCK end
    return false,nil
end

--  HELPER FUNCTIONS 
function GetBossRootPartCFrame(mapNum)
    local info = RAID_MAP_INFO[mapNum]; if not info then return nil end
    local mf = workspace:FindFirstChild("Maps"); if not mf then return nil end
    local mapFolder = mf:FindFirstChild(info.instance); if not mapFolder then return nil end
    local mapChild = mapFolder:FindFirstChild("Map"); if not mapChild then return nil end
    local re = mapChild:FindFirstChild("RaidsEnemys"); if not re then return nil end
    local rp = re:FindFirstChild(info.rootPart); if not rp then return nil end
    return rp.CFrame
end

function GetRaidMapNum(mapId)
    local mf = workspace:FindFirstChild("Maps")
    if mf then
        local ord = {
            {1,"Map1"},{2,"Map2"},{3,"Map3"},{4,"Map4"},{5,"Map5"},
            {6,"Map6"},{7,"Map7"},{8,"Map8"},{9,"Map9"},{10,"Map10"},
            {11,"Map11"},{12,"Map12"},{13,"Map13"},{14,"Map14"},{15,"Map15"},
            {16,"Map16"},{17,"Map17"},{18,"Map18"},{19,"Map19"},{20,"Map20"},{21,"Map21"},
        }
        for _,v in ipairs(ord) do if mf:FindFirstChild(v[2]) then return v[1] end end
    end
    if type(mapId) ~= "number" then return nil end
    if mapId >= 50101 and mapId <= 50121 then return mapId - 50100 end
    if mapId >= 50001 and mapId <= 50021 then return mapId - 50000 end
    return nil
end

function GetBestGrade(mapNum, isAscension)
    local mapId = isAscension and (50300+mapNum) or (50000+mapNum)
    local cacheKey = isAscension and (-mapNum) or mapNum
    if isAscension and _ASC_CHAT_CACHE then
        local e = _ASC_CHAT_CACHE[mapNum]
        if e and e.grade and e.grade ~= "?" then return e.grade end
    end
    if isAscension and _runeGradeCache then
        local cg = _runeGradeCache[-mapNum] or _runeGradeCache[cacheKey]
        if cg and cg ~= "?" then return cg end
    end
    for _, ent in pairs(RAID_LIVE) do
        local mm = (ent.mapId == mapId)
        local am = (isAscension and ent.isAscension) or (not isAscension and not ent.isAscension)
        if mm and am and ent.raidId and ent.raidId > 0 then
            local g = RAID_CONFIG_GRADE and RAID_CONFIG_GRADE[ent.raidId]
            if g and g ~= "?" then return g end
        end
    end
    if not isAscension and _runeGradeCache then
        if _runeGradeCache[cacheKey] and _runeGradeCache[cacheKey] ~= "?" then
            return _runeGradeCache[cacheKey]
        end
    end
    for _, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId and ent.grade and ent.grade ~= "?" then
            if isAscension and ent.isAscension then return ent.grade end
            if not isAscension and not ent.isAscension then return ent.grade end
        end
    end
    return nil
end

function GetCurrentMapId()
    -- [FIX v1.lua PORT] File 1 pakai pcall + cek 3 attribute + return nil jika gagal
    -- bukan hanya workspace:GetAttribute("MapId") or 0 yang return 0 saat tidak ada
    local ok, wm = pcall(function()
        return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
    end)
    return (ok and type(wm) == "number") and wm or nil
end

--  REBUILD RAID LIST 
RebuildRaidList = function()
    local sorted = {}
    for _, e in pairs(RAID_LIVE) do
        local ridAbs = e.raidId and (e.raidId < 0 and math.abs(e.raidId) or e.raidId) or 0
        if ridAbs == 937101 then continue end
        if ridAbs >= 935001 and not e.isAscension then e.isAscension = true end
        local mn = e.mapId and (e.mapId - 50000) or 0
        if e.isAscension or (e.mapId and mn >= 1 and mn <= 21) then
            table.insert(sorted, e)
        end
    end
    table.sort(sorted, function(a,b)
        local aA = a.isAscension and true or false
        local bA = b.isAscension and true or false
        if aA ~= bA then return not aA end
        return (a.mapId or 0) < (b.mapId or 0)
    end)
    RAID_ID_LIST = {}
    for _, e in ipairs(sorted) do
        local mn = e.mapId and (e.mapId - 50000) or 0
        local lbl
        if e.isAscension then
            local bn = e.bossName and (e.bossName:gsub("^%l",string.upper)) or nil
            lbl = "Ascension Tower "..mn..(bn and (" - "..bn) or "").." ["..(e.grade or "?").."]"
        else
            lbl = "Map "..mn.." - "..(MAP_NAMES[mn] or "Map "..mn).." - "..(RANK_LABEL[e.rank] or (e.spawnName or "?")).." (ID:"..e.raidId..")"
        end
        table.insert(RAID_ID_LIST,{
            label=lbl,id=e.raidId,rank=e.rank,mapId=e.mapId,
            spawnName=e.spawnName,isAscension=e.isAscension,bossName=e.bossName,
        })
    end
    if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end
end

--  TRIGGER ENTRY WAKEUP 
TriggerEntryWakeup = function()
    if _entryWakeupTimer then
        pcall(function() task.cancel(_entryWakeupTimer) end)
        _entryWakeupTimer = nil
    end
    _entryWakeupTimer = task.delay(_ENTRY_DEBOUNCE_SEC, function()
        _entryWakeupTimer = nil
        _ascMatchedThisCycle = false; _raidFallbackActive = false
        if RAID and RAID._listVisitedMaps then
            local _lc=0; for _ in pairs(RAID_LIVE) do _lc=_lc+1 end
            local _vc=0; for _ in pairs(RAID._listVisitedMaps) do _vc=_vc+1 end
            local _ae=true
            if _vc > 0 then
                for mapId in pairs(RAID._listVisitedMaps) do
                    for _,r in ipairs(RAID_ID_LIST) do
                        if r.mapId == mapId then _ae=false; break end
                    end
                    if not _ae then break end
                end
            end
            if _vc == 0 or _ae then
                for k in pairs(RAID._listVisitedMaps) do RAID._listVisitedMaps[k]=nil end
            end
        end
        local _hasAsc = false
        if ASC and ASC.running then
            for rid, ent in pairs(RAID_LIVE) do
                local rA = rid < 0 and math.abs(rid) or rid
                if rA == 937101 then continue end
                if ent.isAscension or rA >= 935001 or (ent.mapId and ent.mapId >= 50301 and ent.mapId <= 50326) then
                    _hasAsc = true; break
                end
            end
        end
        if _hasAsc then
            _eventOwner = "asc"; _raidFallbackActive = false
            if _ascWakeup then pcall(function() _ascWakeup:Fire() end) end
        else
            _eventOwner = "raid"; _raidFallbackActive = true
            if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
        end
    end)
end

--  WORKSPACE WATCHER (RE1001/RE1002 ChildAdded) 
local function _parseRaidEnterName(name)
    local n = name:match("^RaidEnter(%d+)$")
    return n and tonumber(n) or nil
end

local function _onRaidChildAdded(child, slotName)
    local mapNum = _parseRaidEnterName(child.Name)
    if not mapNum or mapNum < 1 or mapNum > 26 then return end
    local mapId = 50000 + mapNum
    if mapId == 50401 then return end
    for _, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId and not ent._tempEntry then return end
    end
    local tempKey = -(mapId)
    local _prevIsAsc=false; local _prevBn=nil; local _prevGr="?"
    if RAID_LIVE[tempKey] and RAID_LIVE[tempKey].isAscension then
        _prevIsAsc=true; _prevBn=RAID_LIVE[tempKey].bossName; _prevGr=RAID_LIVE[tempKey].grade or "?"
    end
    RAID_LIVE[tempKey] = {
        raidId=tempKey,mapId=mapId,spawnName=slotName or "RE1001",rank=0,grade=_prevGr,
        endTime=nil,_tempEntry=true,isAscension=_prevIsAsc,bossName=_prevBn,
        label=_prevIsAsc
            and ("Ascension Tower "..mapNum..(_prevBn and (" - "..(_prevBn:gsub("^%l",string.upper))) or "").." [".._prevGr.."]")
            or ("Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." [?]"),
    }
    RebuildRaidList()
    if TriggerEntryWakeup then TriggerEntryWakeup() end
end

local function _onRaidChildRemoved(child)
    local mapNum = _parseRaidEnterName(child.Name); if not mapNum then return end
    local mapId = 50000 + mapNum; local changed = false
    for rid, ent in pairs(RAID_LIVE) do
        if ent.mapId == mapId then RAID_LIVE[rid]=nil; changed=true end
    end
    if changed then RebuildRaidList() end
end

local function _watchRaidSlot(reFolder)
    if not reFolder then return end
    for _, child in ipairs(reFolder:GetChildren()) do _onRaidChildAdded(child, reFolder.Name) end
    reFolder.ChildAdded:Connect(function(child) _onRaidChildAdded(child, reFolder.Name) end)
    reFolder.ChildRemoved:Connect(function(child) _onRaidChildRemoved(child) end)
end

task.spawn(function()
    local ok,mapsF = pcall(function() return workspace:WaitForChild("Maps",15) end)
    if not ok or not mapsF then return end
    local ok2,mapF = pcall(function() return mapsF:WaitForChild("Map",10) end)
    if not ok2 or not mapF then return end
    local ok3,reF = pcall(function() return mapF:WaitForChild("RaidEnter",10) end)
    if not ok3 or not reF then return end
    local re1 = reF:WaitForChild("RE1001",5)
    local re2 = reF:WaitForChild("RE1002",5)
    _watchRaidSlot(re1); _watchRaidSlot(re2)
end)

--  CONNECT RAID LISTENERS (UpdateRaidInfo + EnterRaidsUpdateInfo) 
_WH = _WH or {}
_WH.raidConns = _WH.raidConns or {}

DisconnectRaidConns = function()
    for _, c in ipairs(_WH.raidConns) do pcall(function() c:Disconnect() end) end
    _WH.raidConns = {}
end

ConnectRaidListeners = function()
    DisconnectRaidConns()
    local _RE_Update = Remotes:FindFirstChild("UpdateRaidInfo")
    local _RE_Enter  = Remotes:FindFirstChild("EnterRaidsUpdateInfo")
    if _RE_Update then
        local conn = _RE_Update.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local action = data.action; local raidInfos = data.raidInfos
            if type(raidInfos) ~= "table" then return end
            if action == "RemoveRaidEnters" then
                for k, info in pairs(raidInfos) do
                    local raidId = type(k)=="number" and k or tonumber(k)
                    if raidId and raidId ~= 937101 then RAID_LIVE[raidId] = nil end
                end
                RebuildRaidList()
            else
                for k, info in pairs(raidInfos) do
                    repeat
                        if type(info) ~= "table" then break end
                        local raidId = info.raidId or (type(k)=="number" and k) or tonumber(k)
                        local mapId = info.mapId
                        if not raidId or not mapId then break end
                        if raidId == 937101 then break end
                        if mapId >= 50101 and mapId <= 50121 then mapId = mapId - 100 end
                        local _isAscMapId = (mapId >= 50301 and mapId <= 50326)
                        local _isAnniversary = (raidId == 937101)
                        local _isAscById = (raidId >= 935001) and not _isAnniversary
                        if not _isAscMapId and not _isAscById and (mapId < 50001 or mapId > 50021) then break end
                        if _isAscById and not _isAscMapId then
                            if mapId >= 50001 and mapId <= 50026 then mapId = mapId + 300 end
                            if mapId >= 50101 and mapId <= 50126 then mapId = mapId + 200 end
                            if mapId >= 50401 and mapId <= 50426 then mapId = mapId - 100 end
                            if mapId >= 50201 and mapId <= 50226 then mapId = mapId + 100 end
                            if not (mapId >= 50301 and mapId <= 50326) then
                                local _mn = math.max(1,math.min(26,math.abs(mapId-50300)))
                                mapId = 50300 + _mn
                            end
                            _isAscMapId = true
                        end
                        local mapNum = _isAscMapId and (mapId-50300) or (mapId-50000)
                        local spawnName = info.spawnName or "RE1001"
                        local rank = SPAWN_RANK[spawnName] or 0
                        local _grCacheKey = _isAscMapId and (-mapNum) or mapNum
                        local grade = (RAID_CONFIG_GRADE and RAID_CONFIG_GRADE[raidId])
                            or (_runeGradeCache and _runeGradeCache[_grCacheKey])
                            or (_ASC_CHAT_CACHE and _isAscMapId and _ASC_CHAT_CACHE[mapNum] and _ASC_CHAT_CACHE[mapNum].grade)
                            or "?"
                        local tempKey = -(mapId)
                        local _isAsc = false; local _bnAsc = nil
                        if raidId >= 935001 and not _isAnniversary then
                            _isAsc = true
                            if RAID_LIVE[tempKey] and RAID_LIVE[tempKey].bossName then _bnAsc = RAID_LIVE[tempKey].bossName
                            elseif RAID_LIVE[raidId] and RAID_LIVE[raidId].bossName then _bnAsc = RAID_LIVE[raidId].bossName end
                        elseif RAID_LIVE[tempKey] and RAID_LIVE[tempKey].isAscension then
                            _isAsc = true; _bnAsc = RAID_LIVE[tempKey].bossName
                        elseif RAID_LIVE[raidId] and RAID_LIVE[raidId].isAscension then
                            _isAsc = true; _bnAsc = RAID_LIVE[raidId].bossName
                        end
                        local _lbl = _isAsc
                            and ("Ascension Tower "..mapNum..(_bnAsc and (" - "..(_bnAsc:gsub("^%l",string.upper))) or "").." ["..grade.."]")
                            or ("Map "..mapNum.." - "..(MAP_NAMES[mapNum] or "Map "..mapNum).." ["..grade.."](ID:"..raidId..")")
                        local entryData = {raidId=raidId,mapId=mapId,spawnName=spawnName,rank=rank,grade=grade,isAscension=_isAsc,bossName=_bnAsc,endTime=info.endTime,label=_lbl}
                        if RAID_LIVE[tempKey] then
                            if grade == "?" and RAID_LIVE[tempKey].grade and RAID_LIVE[tempKey].grade ~= "?" then
                                entryData.grade = RAID_LIVE[tempKey].grade
                            end
                            RAID_LIVE[raidId] = entryData; RAID_LIVE[tempKey] = nil
                        elseif not RAID_LIVE[raidId] then
                            RAID_LIVE[raidId] = entryData
                        else
                            RAID_LIVE[raidId].grade = grade; RAID_LIVE[raidId].rank = rank; RAID_LIVE[raidId].label = _lbl
                            if _isAsc then RAID_LIVE[raidId].isAscension = true; if _bnAsc then RAID_LIVE[raidId].bossName = _bnAsc end end
                        end
                    until true
                end
                RebuildRaidList()
                if TriggerEntryWakeup then TriggerEntryWakeup() end
            end
        end)
        table.insert(_WH.raidConns, conn)
    end
    if _RE_Enter then
        local conn = _RE_Enter.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            if data.slotIndex == nil and data.fromMapId == nil and data.mapId == nil then return end
            local evMapId = data.mapId or data.fromMapId or 0
            if evMapId >= 50300 then
                if evMapId >= 50301 and evMapId <= 50326 and ASC and (ASC.running or ASC.inMap) then
                    ASC.serverMapId = evMapId
                end
                return
            end
            if ASC.inMap then return end
            if data.slotIndex then RAID.slotIndex = data.slotIndex end
            if data.fromMapId then RAID.fromMapId = data.fromMapId end
            if data.mapId then
                local mid = data.mapId
                if mid >= 50101 and mid <= 50120 then RAID.serverMapId = mid end
            end
        end)
        table.insert(_WH.raidConns, conn)
    end
end

task.spawn(function() ConnectRaidListeners() end)

-- [FIX v1.lua PORT] Auto-reconnect kalau Remotes refresh (mis. setelah rejoin)
-- File 1 baris 10423-10434 punya ini, file 2 hilang -> listener mati setelah rejoin
-- [FIXED zombie] pakai flag _raidReconnectAlive agar loop mati kalau nil-kan flag
_raidReconnectAlive = true
task.spawn(function()
    local lastRef = Remotes:FindFirstChild("UpdateRaidInfo")
    while _raidReconnectAlive do
        task.wait(3)
        local cur = Remotes:FindFirstChild("UpdateRaidInfo")
        if cur ~= lastRef then
            lastRef = cur
            if cur then ConnectRaidListeners() end
        end
    end
end)
-- [FIX v1.lua PORT] RaidCollectAll - dipakai di STEP 5 StartRaidLoop tapi tidak pernah didefinisikan di file 2!
-- Port dari file 1 baris 11918-11969 (v73 FIX: scan agresif + retry)
function RaidCollectAll()
    local collected_guids = {}
    local function collectFolder(folder)
        if not folder then return end
        for _, obj in ipairs(folder:GetChildren()) do
            local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid") or obj:GetAttribute("ItemGuid")
            if guid and not collected_guids[guid] then
                collected_guids[guid] = true
                RAID.collected = RAID.collected + 1
                pcall(function() RE.CollectItem:InvokeServer(guid) end)
                if RE.ExtraReward then
                    pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                end
                task.wait(0.05)
            end
        end
    end
    -- Round 1: scan semua folder reward standar
    local folders = {"Golds","Items","Drops","Rewards","Loot","Chests","RewardItems","DropItems"}
    for _, folderName in ipairs(folders) do
        collectFolder(workspace:FindFirstChild(folderName))
    end
    -- Scan workspace root untuk item loose (tidak dalam folder)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") or obj:IsA("Part") or obj:IsA("BasePart") then
            local guid = obj:GetAttribute("GUID") or obj:GetAttribute("Guid") or obj:GetAttribute("guid") or obj:GetAttribute("ItemGuid")
            if guid and not collected_guids[guid] then
                collected_guids[guid] = true
                RAID.collected = RAID.collected + 1
                pcall(function() RE.CollectItem:InvokeServer(guid) end)
                if RE.ExtraReward then
                    pcall(function() RE.ExtraReward:FireServer({isSell=true, guid=guid}) end)
                end
                task.wait(0.05)
            end
        end
    end
    -- Round 2: tunggu 1.5 detik lalu scan ulang (item spawn delayed)
    task.wait(1.5)
    for _, folderName in ipairs(folders) do
        collectFolder(workspace:FindFirstChild(folderName))
    end
end

-- [FIX v1.lua PORT] GetRaidEnemies - override/define ulang sebagai global tanpa guard
-- Port dari file 1 baris 11975-12048. Di file 2 sebelumnya hanya ada di "if not GetRaidEnemies" guard
-- yang bisa dilewati jika fungsi sudah ada dari script master (versi berbeda/salah)
-- Dengan mendefinisikan ulang di sini, kita pastikan versi yang BENAR selalu dipakai
function GetRaidEnemies()
    local list = {}
    local seen = {}
    local currentMapId = GetCurrentMapId()
    local _inNormalRaid = currentMapId and (currentMapId >= 50101 and currentMapId <= 50120)
    local _inAscTower   = currentMapId and (currentMapId >= 50301 and currentMapId <= 50326)
    -- [BUG FIX] Jangan scan saat di Siege, Dungeon, atau Anniversary
    if currentMapId then
        local _inSiege   = currentMapId >= 50201 and currentMapId <= 50204
        local _inAnniv   = currentMapId == 50401
        if _inSiege or _inAnniv then return list end
    end
    local playerPos
    pcall(function()
        local char = LP and LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        playerPos = hrp and hrp.Position or nil
    end)
    local activeMapId = _inNormalRaid and (RAID and RAID.serverMapId) or
        (not _inNormalRaid and not _inAscTower and RAID and RAID.inMap and RAID.serverMapId) or nil
    local spawnPos = activeMapId and RAID_SPAWN_POS and RAID_SPAWN_POS[activeMapId]
    local refPos = (playerPos and playerPos.Magnitude > 1) and playerPos
                or (spawnPos and spawnPos.Magnitude > 1) and spawnPos
                or nil
    local MAX_DIST = 4000
    local useDistFilter = refPos ~= nil
    local function addEnemy(e)
        if not e:IsA("Model") then return end
        if not e:IsDescendantOf(workspace) then return end
        local g = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid") or e:GetAttribute("Guid") or e:GetAttribute("GUID")
        if not g or seen[g] then return end
        local hrp = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
                 or e:FindFirstChild("Torso") or e:FindFirstChild("UpperTorso")
                 or e:FindFirstChildWhichIsA("BasePart")
        local hum = e:FindFirstChildOfClass("Humanoid")
        if not (hrp and hum) then return end
        if hum.Health <= 0 then return end
        if hum.MaxHealth <= 0 then return end
        local _ep = hrp.Position
        if _ep.Magnitude <= 10 then return end
        if _ep.Y < -200 or _ep.Y > 1500 then return end
        if not hrp:IsDescendantOf(workspace) then return end
        if useDistFilter then
            local dist = (_ep - refPos).Magnitude
            if dist > MAX_DIST then return end
        end
        seen[g] = true
        table.insert(list, {guid=g, hrp=hrp, model=e})
    end
    -- [FIX V51] Scan semua folder enemy standar
    for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
        local folder = workspace:FindFirstChild(fname)
        if folder then
            for _, e in ipairs(folder:GetChildren()) do addEnemy(e) end
        end
    end
    return list
end

_raidSessionStart = nil

function StopRaid()
    _raidInterrupt = false
    if MODE then MODE:Release("raid") end
    RAID.running = false; RAID.inMap = false
    ReleaseMapLock("raid")
    if RAID.thread then pcall(function() task.cancel(RAID.thread) end); RAID.thread = nil end
    if _raidWakeup then pcall(function() _raidWakeup:Destroy() end); _raidWakeup = nil end
    RAID.raidId=nil; RAID.raidMapId=nil; RAID.serverMapId=nil; RAID.fromMapId=nil
    RAID.slotIndex=2; RAID._raidDone=false; RAID._cooldownActive=false
    RAID_LIVE={}; _defaultRRIdx=0; RAID_ID_LIST={}
    if RAID._listVisitedMaps then for k in pairs(RAID._listVisitedMaps) do RAID._listVisitedMaps[k]=nil end end
    if _runeGradeCache then for k in pairs(_runeGradeCache) do _runeGradeCache[k]=nil end end
    if RebuildRaidList then pcall(RebuildRaidList) end
end

function RaidStatusUpdate(msg, color)
    if RAID.statusLbl then
        local ts = ""
        if _raidSessionStart then
            local dur = os.time() - _raidSessionStart
            ts = string.format("[%02d:%02d:%02d] ", math.floor(dur/3600), math.floor(dur/60)%60, dur%60)
        end
        RAID.statusLbl.Text = ts..msg
        RAID.statusLbl.TextColor3 = color or Color3.fromRGB(255,210,160)
    end
    if RAID.dot then RAID.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100) end
end

function RaidCounterUpdate()
    if RAID.suksesLbl then RAID.suksesLbl.Text = tostring(RAID.sukses) end
end

function AscStatusUpdate(msg, color)
    if ASC.statusLbl then
        ASC.statusLbl.Text = msg
        ASC.statusLbl.TextColor3 = color or Color3.fromRGB(255,200,100)
    end
    if ASC.dot then ASC.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100) end
end

end -- end do: AUTO RAID DATA & STATE


-- ============================================================================
-- AUTO RAID: StartRaidLoop (port dari 1.lua baris 12218-13571)
-- ============================================================================
function StartRaidLoop()
 StopRaid()
 RAID.running = true
 RAID.sukses = 0
 RAID.collected = 0
 RAID.fromMapId = nil
 RaidCounterUpdate()
 _raidSessionStart = os.time()
 -- [FIX] Buat _raidWakeup BindableEvent agar chat/UpdateRaidInfo bisa bangunkan waiting loop
 if _raidWakeup then pcall(function() _raidWakeup:Destroy() end) end
 _raidWakeup = Instance.new("BindableEvent")

 -- [FIX] Bersihkan sisa runeMapTarget kalau runeEnabled OFF
 if not RAID.runeEnabled and RAID.runeMapTarget ~= 0 then
 RAID.runeMapTarget = 0
 end

 -- Workspace watcher sudah menjaga RAID_LIVE real-time
 -- Tidak perlu fetch manual - langsung mulai loop
 RaidStatusUpdate("Siap. Menunggu raid...", Color3.fromRGB(180,180,60))

 RAID.thread = task.spawn(function()
 pcall(function()
 while RAID.running do
 repeat

 -- [v252] Cek semua interrupt via MODE dispatcher

 -- [FIX] Cek ST2 (Single/Ascension Tower) - pause Auto Raid selama Tower berjalan
 if ST2 and (ST2.running or ST2.inMap) then
 RAID.inMap = false
 RaidStatusUpdate("[||] Tower aktif - Auto Raid pause...", Color3.fromRGB(255,140,0))
 while ST2 and (ST2.running or ST2.inMap) and RAID.running do
 task.wait(0.5)
 end
 if not RAID.running then break end
 RaidStatusUpdate("> Tower selesai - lanjut raid...", C.ACC3)
 task.wait(0.1)
 end

 -- [v56 FIX] Guard RAID: tunggu fitur lain selesai
 -- ASC: RAID boleh lolos guard HANYA jika ResolveAscEntry() = nil (tidak ada Tower match)
 -- Jika ASC.inMap = true (di Tower) -> tetap tunggu ASC keluar dulu sebelum cek ResolveAscEntry
 do
  -- RAID pause selama _ascBusy=true (ASC sedang inMap atau cooldown)
  -- _ascBusy diset false oleh ASC hanya saat benar-benar tidak ada Tower lagi
  local _rGuard = 0
  while RAID.running and _rGuard < 90 do
   -- Cek ASC busy dulu (prioritas)
   if ASC and ASC.running and _ascBusy then
    RaidStatusUpdate("[||] ASC aktif - RAID standby...", Color3.fromRGB(180,100,255))
    task.wait(0.5); _rGuard = _rGuard + 0.5
    continue
   end
   -- Cek fitur lain (Siege, Dungeon)
   local _busy, _who = IsAnyMapActive()
   local _selfBusy = (_who == "raid")
   if not _busy or _selfBusy then break end
   RaidStatusUpdate("[||] Tunggu "..(_who or "?").." selesai dulu...", Color3.fromRGB(255,140,0))
   task.wait(0.5); _rGuard = _rGuard + 0.5
  end
  if not RAID.running then break end
 end

        -- Prioritas: Rune Map + Pick Rank > Rune Map saja > Pick Rank > Difficulty
 -- Selalu baca RAID.runeEnabled / runeGrades / runeMapTarget live
 -- sehingga kalau user ganti setting di tengah, iterasi berikutnya langsung ikut

-- [RAID LIST ENTRY] ResolveEntryFromList
-- Resolver independen: bypass manual mode, scan entry dari bawah ke atas.
-- Return: raidEntry yang match, atau nil jika tidak ada yg match (caller fallback ke Easy)
local function ResolveEntryFromList()
    if not RAID.listEnabled then return nil end
    if #RAID.listEntries == 0 then return nil end
    if #RAID_ID_LIST == 0 then return nil end

    -- Filter Ascension keluar (sama seperti ResolveEntry)
    local normalList = {}
    for _, r in ipairs(RAID_ID_LIST) do
        local isAsc = r.isAscension == true or (r.id and r.id >= 935001)
        if not isAsc then
            local live = r.id and RAID_LIVE[r.id]
            if not (live and live.isAscension == true) then
                table.insert(normalList, r)
            end
        end
    end
    if #normalList == 0 then return nil end

    -- Helper ambil grade terbaik
    local function _getGrade(r)
        return GetBestGrade(r.mapId - 50000, false)
    end

    -- Kumpulkan semua lobby yang match dari semua entry sekaligus
    local function collectAllMatched(skipVisited)
        local allMatched = {}
        local seen = {}
        for i = 1, #RAID.listEntries do
            local ent = RAID.listEntries[i]
            local hasMaps  = next(ent.maps)  ~= nil
            local hasRanks = next(ent.ranks) ~= nil
            for _, r in ipairs(normalList) do
                if seen[r.mapId] then continue end
                -- Skip map yang sudah dikunjungi di siklus ini (kecuali sedang reset)
                if skipVisited and RAID._listVisitedMaps[r.mapId] then continue end
                local mn = r.mapId - 50000
                local mapsOk = (not hasMaps) or ent.maps[mn]
                if not mapsOk then continue end
                if hasRanks then
                    local grade = _getGrade(r)
                    if grade and ent.ranks[grade] then
                        table.insert(allMatched, r)
                        seen[r.mapId] = true
                    end
                else
                    table.insert(allMatched, r)
                    seen[r.mapId] = true
                end
            end
        end
        return allMatched
    end

    -- Tahap 1: cari match yang belum dikunjungi
    local allMatched = collectAllMatched(true)

    -- Tahap 2: kalau semua sudah dikunjungi -> reset visited dan loop ulang dari awal
    if #allMatched == 0 then
        for k in pairs(RAID._listVisitedMaps) do RAID._listVisitedMaps[k] = nil end
        allMatched = collectAllMatched(true)
    end

    if #allMatched == 0 then return nil end

    -- Pilih mapId terkecil dari semua yang match
    table.sort(allMatched, function(a, b) return a.mapId < b.mapId end)
    return allMatched[1]
end

local function ResolveEntry()
                if #RAID_ID_LIST == 0 then return nil end

                -- [LIST FALLBACK v3] Exclude {1,3,8} berlaku di SEMUA tahap — didefinisikan di GLOBAL_EXCLUDE bawah
                -- [RAID LIST ENTRY] Cek List Entry dulu sebelum logika normal
                -- [LIST FALLBACK v3] Kalau List Entry gagal match:
                --   Stage 2 → jalankan Pick Mode aktif (bukan langsung Easy)
                --   Stage 3 → Easy fallback terakhir, exclude {1,3,8}
                --   Kalau Stage 3 juga nil → return nil (Waiting loop)
                local _listFailed = false
                if RAID.listEnabled and #RAID.listEntries > 0 then
                    local listResult = ResolveEntryFromList()
                    if listResult then
                        return listResult
                    end
                    -- List Entry tidak match -> tandai, lanjut ke Pick Mode aktif (fall-through)
                    _listFailed = true
                end

                -- [v46] Auto Raid selalu filter Normal saja (Ascension ditangani Auto Ascension)
                local function _ascFilter(entry)
                    if not entry then return false end
                    -- Cek flag isAscension dari entry RAID_ID_LIST itu sendiri
                    if entry.isAscension == true then return false end
                    -- Cek raidId range Ascension Tower (confirmed SimpleSPY: 936501+)
                    -- Server pakai raidId >= 935001 untuk semua Ascension Tower event
                    if entry.id and entry.id >= 935001 then return false end
                    -- Cek dari RAID_LIVE via id entry
                    local live = entry.id and RAID_LIVE[entry.id]
                    if live and live.isAscension == true then return false end
                    -- Safety net: cek RAID_LIVE[-(mapId)] - entry chat Ascension yang belum di-resolve
                    if entry.mapId then
                        local chatKey = -(entry.mapId)
                        local chatEnt = RAID_LIVE[chatKey]
                        if chatEnt and chatEnt.isAscension == true then return false end
                    end
                    -- Lolos semua cek = RAID Normal
                    return true
                end
                local _now0 = os.time()
                local _pruned0 = false
                for rid, ent in pairs(RAID_LIVE) do
                    if ent.endTime and ent.endTime < (_now0 - 10) then
                        RAID_LIVE[rid] = nil; _pruned0 = true
                    end
                end
                if _pruned0 then
                    if RebuildRaidList then pcall(RebuildRaidList) end
                end
                if #RAID_ID_LIST == 0 then return nil end

                local pm = RAID.pickMode or "default"
                local runeOn = RAID.runeEnabled
                local runeTarget = runeOn and RAID.runeMapTarget or 0
                local hasPick = (pm == "byrank" or pm == "manual") and next(RAID.runeGrades) ~= nil

                -- [FIX] Helper grade yang sadar Ascension (pakai key cache negatif untuk AT)
                local function _getGrade(r)
                    return GetBestGrade(r.mapId - 50000, r.isAscension == true)
                end

                -- [Ascension Mode] Filter RAID_ID_LIST sesuai mode sebelum dipakai pick mode apapun
                local _filteredList = {}
                for _, r in ipairs(RAID_ID_LIST) do
                    if _ascFilter(r) then
                        table.insert(_filteredList, r)
                    end
                end
                -- Gunakan filtered list sebagai sumber utama semua pick mode
                local RAID_ID_LIST = _filteredList

                local function pickLowest(list)
                    table.sort(list, function(a, b) return a.mapId < b.mapId end)
                    return list[1]
                end

                -- [LIST FALLBACK v3] GLOBAL_EXCLUDE: semua tahap dan semua mode exclude {1,3,8}
                -- Dideklarasikan di sini agar bisa dipakai Manual mode dan pickByDiff
                local GLOBAL_EXCLUDE = {[1]=true, [3]=true, [8]=true}

-- [LOGIKA MANUAL MODE DEWA]
                if pm == "manual" then
                    RAID.manualMatchMode = "none" -- Status: "primary" atau "fallback"
                    local valid_raids = {}
                    local hasPreferMaps = next(RAID.preferMaps) ~= nil

                    -- 1. Wadah/Gerbang: Ambil semua map yang diizinkan
                    for _, r in ipairs(RAID_ID_LIST) do
                        local mn = r.mapId - 50000
                        if not hasPreferMaps or RAID.preferMaps[mn] then
                            table.insert(valid_raids, r)
                        end
                    end
                    if #valid_raids == 0 then return nil end

                    -- Helper: Sort dari Rank tertinggi ke terendah
                    local function sortHighestRank(list)
                        table.sort(list, function(a, b)
                            local ga = _getGrade(a) or "?"
                            local gb = _getGrade(b) or "?"
                            local ra = GRADE_RANK[ga] or 0
                            local rb = GRADE_RANK[gb] or 0
                            if ra == rb then return a.mapId < b.mapId end 
                            return ra > rb 
                        end)
                    end

                    -- 2. TAHAP 1: Cari kecocokan Preferred Rank
                    -- [FIX] Kalau Preferred Rank KOSONG (-- NOT SELECTED --), semua Rank valid
                    -- untuk map yang sudah dipilih (simetris dengan hasPreferMaps di Tahap 1:
                    -- kosong = semua diterima). Sebelumnya matched tetap kosong kalau
                    -- hasPreferRank=false, jadi malah lompat ke fallback padahal
                    -- valid_raids sudah ada isinya.
                    local matched = {}
                    local hasPreferRank = next(RAID.runeGrades) ~= nil
                    if hasPreferRank then
                        for _, r in ipairs(valid_raids) do
                            local grade = _getGrade(r)
                            if grade and RAID.runeGrades[grade] then
                                table.insert(matched, r)
                            end
                        end
                    else
                        for _, r in ipairs(valid_raids) do
                            table.insert(matched, r)
                        end
                    end

                    if #matched > 0 then
                        -- MATCH UTAMA KETEMU
                        sortHighestRank(matched)
                        RAID.manualMatchMode = "primary"
                        return matched[1]
                    end

                    -- 3. TAHAP 2 [FIX]: Preferred Map+Rank TIDAK match.
                    -- Manual mode WAJIB berhenti di sini -- TIDAK BOLEH masuk raid dengan Rank
                    -- yang tidak sesuai Preferred Rank hanya karena mapnya kebetulan cocok.
                    -- (Bug lama: fallback ini pakai valid_raids yang cuma difilter Map, jadi
                    --  Rank apapun keikutan lolos selama mapnya match Preferred Maps.)
                    -- Fallback SATU-SATUNYA yang sah dari sini adalah Easy otomatis: cari map
                    -- terkecil dari SEMUA raid yang hidup di game (abaikan Preferred Maps sama
                    -- sekali di tahap ini), exclude {1,3,8}. Kalau itu juga kosong -> Waiting.
                    RAID.manualMatchMode = "fallback"
                    local easyAutoFallback = {}
                    for _, r in ipairs(RAID_ID_LIST) do
                        local mn = r.mapId - 50000
                        if not GLOBAL_EXCLUDE[mn] then table.insert(easyAutoFallback, r) end
                    end
                    if #easyAutoFallback == 0 then return nil end
                    table.sort(easyAutoFallback, function(a, b) return a.mapId < b.mapId end)
                    return easyAutoFallback[1]
                end

                -- [LIST FALLBACK v3] Semua mode dan semua fallback pakai GLOBAL_EXCLUDE {1,3,8}
                -- (EASY_EXCLUDE_MAPS / DEFAULT_EXCLUDE_MAPS dihapus — digantikan GLOBAL_EXCLUDE di atas)

                local function pickByDiff(list)
                    if #list == 0 then return nil end
                    -- [LIST FALLBACK v3] Filter exclude {1,3,8} berlaku di SEMUA mode
                    local filtered = {}
                    for _, r in ipairs(list) do
                        local mn = r.mapId - 50000
                        if not GLOBAL_EXCLUDE[mn] then table.insert(filtered, r) end
                    end
                    if #filtered == 0 then return nil end
                    if pm == "easy" then
                        table.sort(filtered, function(a, b) return a.mapId < b.mapId end)
                        return filtered[1]
                    elseif pm == "hard" then
                        table.sort(filtered, function(a, b) return a.mapId > b.mapId end)
                        return filtered[1]
                    elseif pm == "default" then
                        local maps1to8 = {}
                        for _, r in ipairs(filtered) do
                            local mn = r.mapId - 50000
                            if mn >= 1 and mn <= 8 then
                                table.insert(maps1to8, r)
                            end
                        end
                        if #maps1to8 == 0 then return nil end
                        table.sort(maps1to8, function(a, b) return a.mapId < b.mapId end)
                        _defaultRRIdx = _defaultRRIdx + 1
                        if _defaultRRIdx > #maps1to8 then _defaultRRIdx = 1 end
                        return maps1to8[_defaultRRIdx]
                    elseif pm == "byrank" then
                        -- [FIX] Filter preferMaps dulu sebelum sort grade
                        local _prefMapsActive = next(RAID.preferMaps) ~= nil
                        if _prefMapsActive then
                            local _prefFiltered = {}
                            for _, r in ipairs(filtered) do
                                if RAID.preferMaps[r.mapId - 50000] then
                                    table.insert(_prefFiltered, r)
                                end
                            end
                            filtered = #_prefFiltered > 0 and _prefFiltered or filtered
                        end
                        table.sort(filtered, function(a, b)
                            local ga = _getGrade(a) or "?"
                            local gb = _getGrade(b) or "?"
                            local ra = GRADE_RANK[ga] or 0
                            local rb = GRADE_RANK[gb] or 0
                            if ra == rb then return a.mapId < b.mapId end
                            return ra > rb
                        end)
                        return filtered[1]
                    elseif pm == "bymap" then
                        table.sort(filtered, function(a, b) return a.mapId < b.mapId end)
                        for _, r in ipairs(filtered) do
                            if RAID.preferMaps[r.mapId - 50000] then return r end
                        end
                        return filtered[1]
                    end
                    -- fallback: terkecil dari filtered
                    table.sort(filtered, function(a, b) return a.mapId < b.mapId end)
                    return filtered[1]
                end

                if not IsRaidLiveInGame() then
                    RAID_LIVE = {}; RAID_ID_LIST = {}; _defaultRRIdx = 0
                    if RebuildRaidList then pcall(RebuildRaidList) end
                    return nil
                end

                if hasPick then
                    local matched2 = {}
                    local _hasPrefMaps = next(RAID.preferMaps) ~= nil
                    for _, r in ipairs(RAID_ID_LIST) do
                        local mn = r.mapId - 50000
                        -- [FIX] byrank/manual harus respek preferMaps juga
                        if _hasPrefMaps and not RAID.preferMaps[mn] then continue end
                        local grade = _getGrade(r)
                        if grade and RAID.runeGrades[grade] == true then table.insert(matched2, r) end
                    end
                    if #matched2 > 0 then
                        local chosen = pickByDiff(matched2)
                        if chosen then return chosen end
                    end
                    if pm == "byrank" then
                        -- byrank tidak ketemu grade match -> kalau _listFailed lanjut ke Easy final
                        -- kalau normal -> return nil (Waiting)
                        if not _listFailed then return nil end
                    end
                end

                if pm == "bymap" and next(RAID.preferMaps) ~= nil then
                    local mapMatched = {}
                    for _, r in ipairs(RAID_ID_LIST) do
                        if RAID.preferMaps[r.mapId - 50000] then table.insert(mapMatched, r) end
                    end
                    if #mapMatched > 0 then return pickLowest(mapMatched) end
                    -- bymap tidak ketemu preferred map -> kalau _listFailed lanjut ke Easy final
                    -- kalau normal -> return nil (Waiting)
                    if not _listFailed then return nil end
                end

                -- [LIST FALLBACK v3] Stage 2: Pick Mode aktif
                -- Kalau _listFailed=true (List Entry gagal): jalankan Pick Mode aktif dulu.
                -- Kalau Pick Mode juga tidak ketemu -> Stage 3: Easy final exclude {1,3,8} -> Waiting.
                -- Kalau _listFailed=false (List Entry OFF): perilaku normal, pakai Pick Mode.
                local pickResult = pickByDiff(RAID_ID_LIST)
                if pickResult then return pickResult end

                -- [LIST FALLBACK v3] Stage 3: Easy final (hanya dicapai kalau pickByDiff nil)
                -- Exclude {1,3,8} — kalau semua raid yang tersedia hanya Map 1/3/8 -> return nil -> Waiting
                local easyFinal = {}
                for _, r in ipairs(RAID_ID_LIST) do
                    local mn = r.mapId - 50000
                    if not GLOBAL_EXCLUDE[mn] then table.insert(easyFinal, r) end
                end
                if #easyFinal == 0 then return nil end  -- hanya 1/3/8 tersedia -> Waiting
                table.sort(easyFinal, function(a, b) return a.mapId < b.mapId end)
                return easyFinal[1]
            end
 -- [v238 FIX] Cek apakah ada raid yang benar-benar aktif di game sekarang
 -- Jika tidak, langsung masuk waiting loop tanpa coba masuk
 -- Ini mencegah "tindakan palsu" (TP ke enemy random, loop tak berguna)
 -- ketika Rune Map/Pick Rank di-OFF lalu di-ON lagi saat raid sudah habis
 if not IsRaidLiveInGame() then
 RAID.raidId = nil
 RAID.raidMapId = nil
 raidEntry = nil
 -- Paksa reset RAID_LIVE agar ResolveEntry tidak pakai data stale
 RAID_LIVE = {}
 RAID_ID_LIST = {}
 _defaultRRIdx = 0 -- reset RR saat RAID habis
 if RebuildRaidList then pcall(RebuildRaidList) end
 end

 local raidEntry = ResolveEntry()
 -- [v62 RINO/RINI FIX] Keputusan siapa yang "dipanggil" sudah dibuat di TriggerEntryWakeup.
 -- Jika _eventOwner == "asc" berarti siklus ini giliran ASC (Rino), RAID (Rini) tetap duduk.
 -- Fallback: kalau _eventOwner belum diset (nil), pakai cek ResolveAscEntry lama.
 if raidEntry and ASC and ASC.running then
  if _eventOwner == "asc" then
   raidEntry = nil -- giliran ASC, RAID standby
  elseif _eventOwner == nil and ResolveAscEntry and ResolveAscEntry() then
   raidEntry = nil -- belum ada keputusan, cek manual
  end
 end

 while RAID.running and not raidEntry do
 ForceRescanRaidEnter()
 raidEntry = ResolveEntry()
 -- [v62 RINO/RINI FIX] Cek ulang _eventOwner di setiap iterasi waiting loop
 if raidEntry and ASC and ASC.running then
  if _eventOwner == "asc" then
   raidEntry = nil
  elseif _eventOwner == nil and ResolveAscEntry and ResolveAscEntry() then
   raidEntry = nil
  end
 end
 if not raidEntry then
 -- Prune expired entries
 local _now2 = os.time()
 local _pruned2 = 0
 for rid, ent in pairs(RAID_LIVE) do
 if ent.endTime and ent.endTime < (_now2 - 10) then
 RAID_LIVE[rid] = nil; _pruned2 = _pruned2 + 1
 end
 end
 if _pruned2 > 0 then
 if RebuildRaidList then pcall(RebuildRaidList) end
 end
 -- [v262 FIX] Status label sesuai mode aktif (pickMode aware)
 local _pm = RAID.pickMode
 if not IsRaidLiveInGame() then
 RaidStatusUpdate("Empty RAID - Waiting new RAID", Color3.fromRGB(160,100,60))
 elseif ASC and ASC.running and (_eventOwner == "asc" or (ResolveAscEntry and ResolveAscEntry())) then
 -- [v62 RINO/RINI FIX] ASC ON dan siklus ini giliran ASC -> RAID standby
 RaidStatusUpdate("[||] ASC Ascension aktif & ada Tower match - Normal Raid standby...", Color3.fromRGB(180,100,255))
 elseif _pm == "byrank" and next(RAID.runeGrades) ~= nil then
 local _gr = {}
 for _,g in ipairs(GRADE_LIST) do if RAID.runeGrades[g] then table.insert(_gr,g) end end
 RaidStatusUpdate("Waiting Rank: ["..table.concat(_gr,"] [").."]...", Color3.fromRGB(200,120,255))
 elseif _pm == "bymap" and next(RAID.preferMaps) ~= nil then
 local _ms = {}
 for mn in pairs(RAID.preferMaps) do table.insert(_ms,"Map "..mn) end
 table.sort(_ms)
 RaidStatusUpdate("Waiting Map: "..table.concat(_ms,", ").."...", Color3.fromRGB(100,200,100))
 elseif RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 21 and next(RAID.runeGrades) ~= nil then
 RaidStatusUpdate("Waiting grade cocok -> override Map " .. RAID.runeMapTarget .. "...", Color3.fromRGB(200,140,255))
 elseif RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 21 then
 RaidStatusUpdate("Waiting raid apapun -> override Map " .. RAID.runeMapTarget .. "...", Color3.fromRGB(147,197,253))
 elseif next(RAID.runeGrades) ~= nil then
 RaidStatusUpdate("Waiting grade cocok [" .. RAID.difficulty .. "]...", Color3.fromRGB(200,255,150))
 else
 RaidStatusUpdate("Waiting raid [" .. (_pm ~= "default" and _pm or RAID.difficulty) .. "]...", Color3.fromRGB(255,200,60))
 end
 -- [FIX v256] Wakeup CEPAT: poll 0.05s, max 0.5s (bukan 1s)
 if _raidInterrupt and not RAID.running then _raidInterrupt = false end
 local _woken = false
 local _wConn
 if _raidWakeup then
 _wConn = _raidWakeup.Event:Connect(function() _woken = true end)
 end
 local _we = 0
 while not _woken and _we < 1 and RAID.running do
 task.wait(0.1); _we = _we + 0.1
 end
 if _wConn then pcall(function() _wConn:Disconnect() end) end
 end
 end
 if not RAID.running then break end


 -- [v238 FIX] Double-check sebelum masuk: apakah raid di raidEntry
 -- masih valid di server saat ini?
 -- [v245 FIX] Longgarkan: kalau raidEntry ada di RAID_LIVE dan tidak ada endTime
 -- (server tidak kirim endTime), anggap masih valid - jangan blokir masuk
 local _preCheck_ok = true
 if not raidEntry then
 _preCheck_ok = false
 elseif not RAID_LIVE[raidEntry.id] then
 _preCheck_ok = false
 elseif not IsRaidLiveInGame() then
 -- Satu kesempatan lagi: kalau entry ada tapi tidak ada endTime, izinkan
 local _ent = RAID_LIVE[raidEntry.id]
 if _ent and not _ent.endTime then
 _preCheck_ok = true -- server tidak kirim endTime = anggap valid
 else
 _preCheck_ok = false
 end
 end

 if not _preCheck_ok then
 _raidInterrupt = false; RAID.inMap = false; ReleaseMapLock("raid"); MODE:Release("raid")
 RaidStatusUpdate("Raid expired sebelum masuk - tunggu raid baru...", Color3.fromRGB(255,100,60))
 task.wait(2)
 break
 end

 -- [v252] Pause Mass Attack via MODE dispatcher
 
 -- [HUKUM PRIORITAS TERTINGGI - ANTI CULIK]
 -- Jika Siege / Dungeon sedang jalan, RAID WAJIB PAUSE!
 if (SIEGE and (SIEGE.inMap or SIEGE.teleporting)) then
     RaidStatusUpdate("[!] PAUSE: Menunggu Siege Selesai...", Color3.fromRGB(255, 100, 100))
     task.wait(2)
     break
 end
 
 -- [v54] HUKUM PRIORITAS ASC > RAID NORMAL (diperkuat dari v53)
 -- Kasus 1: ASC ON + ada Tower match sekarang -> RAID Normal standby
 -- Kasus 2: ASC ON + sudah pernah dominasi event ini (dominatedThisEvent) -> RAID Normal
 --          tetap diblokir meskipun Tower saat ini tidak match, sampai event benar-benar habis
 -- Kasus 3: ASC ON + tidak pernah dominasi event ini + tidak ada Tower match -> RAID boleh (fallback)
 -- Kasus 4: ASC OFF -> RAID jalan penuh tanpa batasan
 -- [v56 FIX] RAID standby selama ASC.running=true DAN masih ada Tower match di event saat ini
 -- Tidak diblokir oleh ASC.inMap atau _ascDominatedThisEvent
 -- RAID hanya boleh jalan kalau ResolveAscEntry() = nil (tidak ada Tower match sama sekali)
 if ASC and ASC.running then
     local _ascEntry = ResolveAscEntry and ResolveAscEntry()
     if _ascEntry then
         RaidStatusUpdate("[||] AUTO RAID ASCENSION aktif & ada Tower match - Normal Raid standby...", Color3.fromRGB(180,100,255))
         task.wait(1)
         break
     end
     -- ResolveAscEntry() = nil -> tidak ada Tower match -> RAID boleh jalan sebagai fallback
     -- [v61 CYCLEFIX] Tandai bahwa RAID jalan sebagai fallback di siklus ini
     -- ASC harus standby dan tidak boleh mencuri sampai siklus baru datang
     _raidFallbackActive = true
 end

 local currentWm = workspace:GetAttribute("MapId") or 0
 -- [FIX] Blokir Auto Raid saat di dalam Map Siege atau Dungeon
 if (currentWm >= 50201 and currentWm <= 50204) then
     task.wait(2)
     break
 end
 -- [v56 FIX] Jika player masih secara fisik di dalam Tower (seharusnya tidak terjadi karena ASC.inMap sudah cover)
 -- Tapi sebagai safety net: tunggu sampai keluar, jangan langsung break
 if currentWm >= 50301 and currentWm <= 50326 then
     RaidStatusUpdate("[||] Masih di dalam Ascension Tower - tunggu keluar...", Color3.fromRGB(180,100,255))
     while (workspace:GetAttribute("MapId") or 0) >= 50301 and RAID.running do
         task.wait(0.5)
     end
     if not RAID.running then break end
 end
 -- [FIX] Pause Auto Raid jika ST2 (Single Tower) sedang aktif di dalam map
 if ST2 and ST2.inMap then
     RaidStatusUpdate("[||] Tower aktif - Auto Raid pause...", Color3.fromRGB(255,140,0))
     while ST2 and ST2.inMap and RAID.running do
         task.wait(0.5)
     end
     if not RAID.running then break end
     RaidStatusUpdate("> Tower selesai - lanjut raid...", C.ACC3)
     task.wait(0.1)
 end

 -- Siege cek tetap pakai flag lama (siege sudah pakai MODE juga via alias)
 -- Tunggu SIEGE selesai dulu jika sedang inMap
 if SIEGE and (SIEGE.inMap or SIEGE.teleporting) then
     RaidStatusUpdate("[||] Tunggu SIEGE selesai...", Color3.fromRGB(255,180,50))
     local _ws = 0
     while (SIEGE.inMap or SIEGE.teleporting) and RAID.running and _ws < 120 do
         task.wait(0.5); _ws = _ws + 0.5
     end
     if not RAID.running then break end
 end

 -- Tunggu ASC selesai dulu jika sedang inMap
 if ASC and ASC.inMap then
     RaidStatusUpdate("[||] Tunggu ASC selesai...", Color3.fromRGB(255,180,50))
     local _wa = 0
     while ASC.inMap and RAID.running and _wa < 120 do
         task.wait(0.5); _wa = _wa + 0.5
     end
     if not RAID.running then break end
 end

 _raidInterrupt = true -- signal MA untuk pause (MA cek di guard tiap iterasi)

 -- [v12 EDIT] RAID match ditemukan -- hard-stop Mass Attack SEGERA + delay 2s
 -- sebelum lanjut masuk RAID, cegah race condition rebutan musuh (lihat
 -- _MA_HardStopForMatch di panel Mass Attack).
 if _MA_HardStopForMatch then _MA_HardStopForMatch(function(msg) RaidStatusUpdate(msg, Color3.fromRGB(255,180,50)) end) end

 -- [v52 FIX] Atomic lock: cegah ASC masuk bersamaan saat RAID baru lolos guard
 do
  local _rLockWait = 0
  while RAID.running and _rLockWait < 15 do
   if TryClaimMapLock("raid") then break end
   RaidStatusUpdate("[||] Tunggu slot masuk map bebas...", Color3.fromRGB(200,200,100))
   task.wait(0.2); _rLockWait = _rLockWait + 0.2
  end
  if not RAID.running then ReleaseMapLock("raid"); break end
 end
 
-- [v262 FIX] JANGAN set inMap=true dulu sebelum raidMapId di-assign
                    -- [FIX Ascension] raidEntry.id negatif = Ascension entry (chat-only id)
                    -- CreateRaidTeam butuh raidId positif dari server -> ambil dari RAID_LIVE jika tersedia
                    local _resolvedRaidId = raidEntry.id
                    if raidEntry.isAscension and _resolvedRaidId < 0 then
                        -- Cari raidId positif dari RAID_LIVE entry yang sama mapId & isAscension
                        for _rid, _ent in pairs(RAID_LIVE) do
                            if _ent.isAscension and _ent.mapId == raidEntry.mapId and _rid > 0 then
                                _resolvedRaidId = _rid; break
                            end
                        end
                        -- Jika masih negatif: pakai abs (fallback darurat, mungkin tidak work tapi tidak crash)
                        if _resolvedRaidId < 0 then _resolvedRaidId = math.abs(_resolvedRaidId) end
                    end
                    RAID.raidId = _resolvedRaidId
                    RAID.raidMapId = raidEntry.mapId
                    RAID.inMap = true
                    SafeReequipAfterTeleport("AutoRaid")
                    ReleaseMapLock("raid") -- [v52 FIX] inMap=true sudah di-set, IsAnyMapActive sudah cover
                    if RAID.updateActiveLabel then pcall(RAID.updateActiveLabel) end


                    
                    RAID.slotIndex = 2
                    if _raidIdRefreshCb then pcall(_raidIdRefreshCb) end
                    
                    local mn = raidEntry.mapId - 50000
                    if RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 21 then mn = RAID.runeMapTarget end
                    local mapLabel = MAP_NAMES[mn] or ("Map " .. mn)

                    local _liveEntry = RAID_LIVE[RAID.raidId]
                    if not _liveEntry then
                        _raidInterrupt = false; RAID.inMap = false; MODE:Release("raid")
                        task.wait(1); break
                    end
                    RAID.serverMapId = nil
                    if not RAID.running then break end

                    -- [LOGIKA KEPUTUSAN]
                    local pm = RAID.pickMode or "default"
                    local useRune = false
                    
                    if pm == "manual" then
                        if RAID.manualMatchMode == "primary" then
                            -- TAHAP 1: MATCH PREFERRED RANK -> HANYA RUNE YANG BOLEH JALAN!
                            if RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 21 then 
                                -- [SISTEM ANTI-MUBAZIR]
                                if (raidEntry.mapId - 50000) == RAID.runeMapTarget then
                                    useRune = false -- Map sudah sama, simpan Rune-nya!
                                else
                                    useRune = true 
                                end
                            else
                                useRune = false
                            end
                            
                        elseif RAID.manualMatchMode == "fallback" then
                            -- TAHAP 2: JANGAN MAKSA!
                            useRune = false
                        end
                    else
                        -- Mode selain Manual (ByRank, dll)
                        if RAID.runeEnabled and RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 21 then 
                            if (raidEntry.mapId - 50000) == RAID.runeMapTarget then
                                useRune = false
                            else
                                useRune = true 
                            end
                        end
                    end

                    -- [Auto Item Rune Map] Fire UseRaidItem sesuai hasil
                    -- Slot Manager (max 2 slot, format WAJIB {slotIndex=N, itemId=ID}
                    -- sesuai contoh SimpleSpy - BUKAN angka polos seperti sebelumnya).
                    -- runeItemId = itemId rune yang mau dipakai (nil kalau Rune Map OFF
                    -- atau sedang di cabang non-rune).
                    local function FireItemSlots(runeItemId)
                        if not RE.UseRaidItem then return end
                        local fireList = SlotManager_ResolveFireList(RAID, runeItemId)
                        for _, entry in ipairs(fireList) do
                            RaidStatusUpdate("[~] Use Item slot" .. entry.slotIndex .. " (" .. entry.name .. ")...", Color3.fromRGB(200,140,255))
                            pcall(function()
                                RE.UseRaidItem:FireServer({ slotIndex = entry.slotIndex, itemId = entry.itemId })
                            end)
                            task.wait(0.3)
                        end
                        return fireList
                    end

                    -- [EKSEKUSI]
                    if useRune then
                        -- >>> MODE RUNE MAP OVERRIDE <<<
                        local targetMap = RAID.runeMapTarget
                        RaidStatusUpdate("Create Team...", C.ACC2)
                        if not RAID.fromMapId then RAID.fromMapId = RAID.raidMapId end
                        if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end) end
                        task.wait(0.2)
                        
                        
                        RaidStatusUpdate("Use Item (Map "..targetMap..")...", Color3.fromRGB(255,200,60))
                        local RUNE_IDS = {
                            [1]=10265,[2]=10266,[3]=10267,[4]=10268,[5]=10269, [6]=10314,[7]=10315,[8]=10316,
                            [9]=10357,[10]=10358,[11]=10359,[12]=10360,[13]=10361, [14]=10362,[15]=10363,[16]=10364,[17]=10365,[18]=10366,
                            [19]=10367,[20]=10368,
                        }
                        local itemId = RUNE_IDS[targetMap]
                        -- [FIX] Fire rank (upA/upB/down) + rune SEKALIGUS lewat Slot Manager,
                        -- supaya slotIndex tidak rebutan (dulu fire rank dulu lalu rune belakangan
                        -- dengan slotIndex ngasal / angka polos - sekarang terkoordinasi).
                        FireItemSlots(itemId)
                        
                        if RE.StartChallengeRaidMap then
                            local _runeMapId = 50100 + targetMap
                            pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = _runeMapId}) end)
                        end
                        
                        local _wR = 0
                        while RAID.serverMapId == nil and _wR < 10 and RAID.running do
                            task.wait(0.1); _wR = _wR + 0.1
                        end
                        
                        -- Fallback jika tiket Rune Map ternyata habis di inventory
                        if RAID.serverMapId == nil and RAID.running then
                            RaidStatusUpdate("[!] Material Kosong - Fallback...", Color3.fromRGB(255,140,0))
                            local _fbTargetMapId = raidEntry.mapId + 100
                            if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end) end
                            task.wait(0.2)
                            if RE.StartChallengeRaidMap then pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = _fbTargetMapId}) end) end
                            local _wFb = 0; while RAID.serverMapId == nil and _wFb < 5 and RAID.running do task.wait(0.05); _wFb = _wFb + 0.05 end
                        end
                        
                    else
                        -- >>> MODE NORMAL / FALLBACK <<<
                        local targetMapId = raidEntry.mapId + 100
                        RaidStatusUpdate("Enter Map " .. (targetMapId-50100) .. "...", C.ACC3)

                        if not RAID.fromMapId then RAID.fromMapId = RAID.raidMapId end
                        if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(RAID.raidId) end) end
                        task.wait(0.2)
                        if not RAID.running then break end

                        FireItemSlots(nil)

                        local _cfail = false
                        local _cfConn
                        local _cfRe = Remotes:FindFirstChild("ChallengeRaidsFail")
                        if _cfRe then _cfConn = _cfRe.OnClientEvent:Connect(function() _cfail = true end) end

                        if RE.StartChallengeRaidMap then
                            pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = targetMapId}) end)
                        end

                        local _w2 = 0
                        while RAID.serverMapId == nil and _w2 < 5 and RAID.running and not _cfail do task.wait(0.05); _w2 = _w2 + 0.05 end

                        if _cfConn then pcall(function() _cfConn:Disconnect() end) end
                        if _cfail then
                            RAID_LIVE[RAID.raidId] = nil; RebuildRaidList()
                            _raidInterrupt = false; RAID.inMap = false; MODE:Release("raid")
                            task.wait(1); break
                        end
                    end
 -- STEP 3: Tunggu masuk map (max 10s) - flow sama persis v41
 RaidStatusUpdate("[~] Waiting...", Color3.fromRGB(180,100,255))
 local _tpOk = false
 local _tpWait = 0
 while not _tpOk and _tpWait < 2 and RAID.running do
  task.wait(0.3); _tpWait = _tpWait + 0.3
  pcall(function()
   local wMapId = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
   if wMapId then
    if RAID.serverMapId and wMapId == RAID.serverMapId then
     _tpOk = true
    elseif RAID.runeEnabled then
     local ok = (wMapId >= 50101 and wMapId <= 50120)
     if ok then RAID.serverMapId = wMapId; _tpOk = true end
    elseif (wMapId >= 50101 and wMapId <= 50120) then
     _tpOk = true
    end
   end
  end)
  -- Fallback: kalau enemy sudah ada, berarti sudah di dalam map
  if not _tpOk and #GetRaidEnemies() > 0 then _tpOk = true end
 end

 if not _tpOk and RAID.running then
  -- Gagal masuk map: hapus entry dan retry
  RAID_LIVE[RAID.raidId] = nil; RebuildRaidList()
  _raidInterrupt = false; RAID.inMap = false; ReleaseMapLock("raid"); MODE:Release("raid"); RAID.fromMapId = nil
  task.wait(1); break
 end

 -- [FIX] Equip hero ke map ini agar hero spawn di sebelah player
 -- Tanpa ini hero tidak muncul di map raid meski GUID sudah ada
 if #HERO_GUIDS > 0 then
 task.spawn(function()
 task.wait(0.5)
 -- EquipHeroWithData: daftarkan hero ke map saat ini
 if RE.EquipHeroWithData then
 for _, hGuid in ipairs(HERO_GUIDS) do
 pcall(function()
 RE.EquipHeroWithData:FireServer({
 heroGuid = hGuid,
 userId = MY_USER_ID,
 })
 end)
 PG_Wait(0.1) -- [PingGuard] equip hero loop
 end
 end
 -- HeroStandTo ke posisi player sekarang
 if RE.HeroStand then
 local char = LP.Character
 local hrp = char and char:FindFirstChild("HumanoidRootPart")
 local spawnPos = (hrp and hrp.Position) or Vector3.new(0, 0, 0)
 pcall(function()
 RE.HeroStand:FireServer({
 userId = MY_USER_ID,
 standPos = spawnPos,
 })
 end)
 for _, hGuid in ipairs(HERO_GUIDS) do
 pcall(function()
 RE.HeroStand:FireServer({
 heroGuid = hGuid,
 userId = MY_USER_ID,
 standPos = spawnPos,
 })
 end)
 end
 end
 end)
 end

 -- STEP 4: Di dalam raid - cari boss, TP, serang
 -- [FIX v260] Jika sebelumnya Siege baru saja selesai, tunggu workspace bersih dulu.
 -- Cek aktif sampai 5 detik: jika masih ada enemy Siege di workspace, tunggu terus.
 -- Tanpa ini scan boss bisa menemukan sisa enemy Siege dan salah TP ke sana.
 if SIEGE and SIEGE._lastExitTime and (os.time() - SIEGE._lastExitTime) < 5 then
  RaidStatusUpdate("[~] Clearing Siege remnants...", Color3.fromRGB(160,148,135))
  local _siegeWait = 0
  while _siegeWait < 5 and RAID.running do
   local _curMId = GetCurrentMapId()
   -- Selama mapId masih di range Siege, tunggu
   if _curMId and (_curMId >= 50201 and _curMId <= 50204) then
    task.wait(0.5); _siegeWait = _siegeWait + 0.5
   else
    break -- mapId sudah bersih, lanjut
   end
  end
 end

 RAID._raidDone = false
 local _raidSuccess = false

 local connS, connF
 -- _raidServerDone = flag bahwa server sudah bilang sukses
 -- (attack loop tetap jalan sampai boss model hilang dari workspace)
 local _raidServerDone = false
 local _reS = Remotes:FindFirstChild("ChallengeRaidsSuccess")
 local _reF = Remotes:FindFirstChild("ChallengeRaidsFail")
 if _reS then connS = _reS.OnClientEvent:Connect(function()
  _raidServerDone = true; _raidSuccess = true
 end) end
 if _reF then connF = _reF.OnClientEvent:Connect(function()
  RAID._raidDone = true
 end) end

 --  HELPER: Cleanup semua koneksi + unfreeze player 
 -- Dipanggil di SETIAP jalur keluar dari STEP 4 (boss mati, boss tidak ketemu,
 local _freezeConn  = nil  -- RunService.Heartbeat conn untuk lock posisi player
 local _frozenCFrame = nil -- CFrame terkunci saat attack
 local function _step4Cleanup()
  -- 1) Lepas freeze player - pastikan Anchored = false
  pcall(function()
   local char = LP.Character
   local hrp  = char and char:FindFirstChild("HumanoidRootPart")
   if hrp then hrp.Anchored = false end
  end)
  -- 2) Disconnect Heartbeat freeze (idempoten - aman dipanggil berkali-kali)
  if _freezeConn then
   pcall(function() _freezeConn:Disconnect() end)
   _freezeConn  = nil
   _frozenCFrame = nil
  end
  -- 3) Disconnect server event listeners
  if connS then pcall(function() connS:Disconnect() end); connS = nil end
  if connF then pcall(function() connF:Disconnect() end); connF = nil end
 end

 --  LOADING WAIT: tunggu enemies muncul via ChildAdded 
 -- ChildAdded murni untuk deteksi instan + polling ringan sebagai safety net.
 RaidStatusUpdate("[..] Enter Map - loading...", Color3.fromRGB(160,148,135))

 -- [FIX v261] Snapshot mapId diambil SETELAH jeda singkat agar workspace.MapId
 -- sempat update dari server sebelum dipakai untuk validasi.
 task.wait(0.3) -- beri server 1 tick untuk update workspace.MapId

 local function _isValidRaidMap(mId)
  if not mId then return false end
  return (mId >= 50101 and mId <= 50120) or (mId >= 50301 and mId <= 50326)
 end

 local function _isValidRaidMapByInstance()
  local mf = workspace:FindFirstChild("Maps")
  if not mf then return false end
  -- Map1 dan Map3 instance-nya Map101/Map103 (beda sendiri)
  if mf:FindFirstChild("Map101") or mf:FindFirstChild("Map103") then return true end
  for i = 2, 20 do
   if i ~= 3 and mf:FindFirstChild("Map"..i) then return true end
  end
  return false
 end

 -- Tunggu mapId valid (max 3s) - cek via workspace.Maps instance ATAU numerik
 local _raidMapIdSnapshot = GetCurrentMapId()
 local _snapWait = 0
 while not (_isValidRaidMapByInstance() or _isValidRaidMap(_raidMapIdSnapshot)) and _snapWait < 3 and RAID.running do
  task.wait(0.3); _snapWait = _snapWait + 0.3
  _raidMapIdSnapshot = GetCurrentMapId()
 end

 -- [CUSTOM v54.1] Render delay sederhana - TANPA scan nama boss sama sekali.
 -- Mode TP DIRECT tidak butuh tahu siapa boss-nya; target diambil murni dari
 -- scan radius di titik TP (lihat blok AUTO BOSS KILL di bawah). Loading wait
 -- ini hanya untuk memberi waktu render server sebelum TP+scan dilakukan.
 RaidStatusUpdate("[..] Render delay...", Color3.fromRGB(160,148,135))
 local _preMapNum = GetRaidMapNum(raidEntry and raidEntry.mapId)
 local _renderDelay = (_preMapNum == 1) and 4 or 2
 task.wait(_renderDelay) -- Map1: 4s, lainnya: 2s

 if RAID.running and not RAID._raidDone and RAID.autoKillBoss then
  -- [v56] AUTO BOSS KILL - TP KE ROOTPART BOSS (REALTIME)
  -- Teleport player+hero langsung ke CFrame RootPart boss di workspace.Maps.
  -- Path: workspace.Maps.[instanceName].Map.RaidsEnemys.[rootPartName]
  -- Mapping instance+rootPart per mapNum ada di RAID_MAP_INFO.
  -- Setelah TP, scan musuh radius 50 studs dari posisi RootPart tersebut.

  -- Resolve mapNum via workspace.Maps instance (primary) lalu fallback numerik.
  local _mapNumNow = GetRaidMapNum(raidEntry and raidEntry.mapId)

  -- Ambil CFrame realtime dari RootPart boss
  local _tpTargetCF  = _mapNumNow and GetBossRootPartCFrame(_mapNumNow) or nil
  local _tpTargetPos = _tpTargetCF and _tpTargetCF.Position or nil

  -- [v56] FALLBACK BOSS NAME khusus Map 1 dan Map 3:
  -- RootPart di kedua map ini tidak bisa dideteksi via workspace.Maps,
  -- scan workspace.Enemys berdasarkan nama boss (Goblin King / Igris).
  if not _tpTargetPos and (_mapNumNow == 1 or _mapNumNow == 3) then
   local _bossName = BOSS_NAME_BY_MAP[_mapNumNow]
   local _enemysFolder = workspace:FindFirstChild("Enemys")
   if _enemysFolder and _bossName then
    for _, e in ipairs(_enemysFolder:GetChildren()) do
     if e:IsA("Model") and e.Name:find(_bossName, 1, true) then
      local _bHrp = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
      local _bHum = e:FindFirstChildOfClass("Humanoid")
      if _bHrp and _bHum and _bHum.Health > 0 then
       _tpTargetPos = _bHrp.Position
       _tpTargetCF  = _bHrp.CFrame
       break
      end
     end
    end
   end
  end

  if not _tpTargetPos then
   local _info = _mapNumNow and RAID_MAP_INFO[_mapNumNow]
   local _detail = _info and ("Maps."..(_info.instance)..".Map.RaidsEnemys.".._info.rootPart) or ("mapNum="..tostring(_mapNumNow))
   RaidStatusUpdate("[!] RootPart boss tidak ditemukan - " .. _detail .. " - skip", Color3.fromRGB(255,80,80))
   _step4Cleanup()
   task.wait(2)
  else
   -- Countdown delay sebelum TP (1-10s, user-controlled, sama seperti sebelumnya)
   local _bd = math.max(1, math.min(10, RAID.bossDelay or 3))
   for _ci = _bd, 1, -1 do
    if not RAID.running or RAID._raidDone then break end
    RaidStatusUpdate("[K] TP ke Boss Map " .. tostring(_mapNumNow) .. " - " .. _ci .. "s...", Color3.fromRGB(255,160,60))
    task.wait(1)
   end

   if RAID.running and not RAID._raidDone then
    -- Refresh CFrame boss tepat sebelum TP (posisi bisa saja bergerak)
    _tpTargetCF  = GetBossRootPartCFrame(_mapNumNow) or _tpTargetCF
    _tpTargetPos = _tpTargetCF.Position

    -- 1) TP Player ke posisi RootPart boss
    pcall(function()
     local char = LP.Character
     local hrp  = char and char:FindFirstChild("HumanoidRootPart")
     if hrp then hrp.CFrame = _tpTargetCF end
    end)

    -- 2) UnEquip -> EquipBest (timing: UnEquip, wait 1s, EquipBest, wait 2s)
    if RE.UnEquipHero  then pcall(function() RE.UnEquipHero:FireServer()  end) end
    task.wait(1)
    if RE.EquipBestHero then pcall(function() RE.EquipBestHero:FireServer() end) end
    task.wait(2)

    -- [FIX BOSS-KILL] Pastikan HERO_GUIDS terisi independen (jangan bergantung RA/TA/fitur lain).
    -- RE.HeroUseSkill butuh heroGuid eksplisit; tanpa ini hero diam walau EquipBestHero sukses.
    if #HERO_GUIDS == 0 then
     pcall(function()
      for _, obj in ipairs(LP.PlayerGui:GetChildren()) do
       local g = obj:GetAttribute("heroGuid") or obj:GetAttribute("guid")
       if type(g) == "string" and IsValidUUID(g) then
        local dup = false
        for _, ex in ipairs(HERO_GUIDS) do if ex == g then dup = true; break end end
        if not dup then table.insert(HERO_GUIDS, g) end
       end
      end
     end)
     if #HERO_GUIDS > 0 then
      RaidStatusUpdate("[HERO] "..#HERO_GUIDS.." hero guid ter-scan dari PlayerGui", Color3.fromRGB(120,220,255))
     else
      RaidStatusUpdate("[!] HERO_GUIDS masih kosong - hero mungkin tidak menyerang", Color3.fromRGB(255,140,0))
     end
    end

    -- 5) Kunci posisi player selama scan+attack (Heartbeat freeze)
    -- [TA-STYLE] Reposisi mengikuti target real-time (bukan statis di titik TP awal),
    -- identik pola ReassertFreeze/TpToF milik TARGET ATTACK: tiap frame CFrame
    -- direfresh ke 3 stud di depan HRP musuh terkini (_bossFollowTarget, diisi
    -- setelah target hasil scan radius ditemukan di bawah).
    local _bossFollowTarget = nil -- diisi = {hrp=...} setelah target ditemukan (lihat blok scan di bawah)
    pcall(function()
     local char = LP.Character
     local hrp  = char and char:FindFirstChild("HumanoidRootPart")
     if hrp then
      _frozenCFrame = _tpTargetCF
      hrp.Anchored  = true
      hrp.CFrame    = _frozenCFrame
      _freezeConn = RunService.Heartbeat:Connect(function()
       -- [FLa CPU] skip frame ganjil  efektif ~30fps
       if not _freezeFrame then _freezeFrame = 0 end
       _freezeFrame = _freezeFrame + 1
       if _freezeFrame % 2 ~= 0 then return end
       if not RAID.running or RAID._raidDone then
        pcall(function() if hrp and hrp.Parent then hrp.Anchored = false end end)
        if _freezeConn then _freezeConn:Disconnect(); _freezeConn = nil end
        _frozenCFrame = nil
        return
       end
       if hrp and hrp.Parent then
        -- [TA-STYLE] Kalau target sudah ada & hidup, ikuti posisinya (3 stud di depan).
        -- Kalau belum ada target (masih fase scan awal), tetap pakai _frozenCFrame lama.
        local _bt = _bossFollowTarget
        if _bt and _bt.hrp and _bt.hrp.Parent then
         local ok = pcall(function()
          _frozenCFrame = _bt.hrp.CFrame * CFrame.new(0, 0, -3)
          hrp.CFrame     = _frozenCFrame
         end)
         if not ok and _frozenCFrame then hrp.CFrame = _frozenCFrame end
        elseif _frozenCFrame then
         hrp.CFrame = _frozenCFrame
        end
       end
      end)
     end
    end)

    --  SCAN RADIUS 10 STUDS - cari 1 musuh terdekat dari posisi RootPart boss 
    -- Timeout 3 detik (sesuai keputusan): scan tiap 0.5s, total 6x percobaan.
    local TP_SCAN_RADIUS = 50
    local function _scanNearbyEnemy()
     local best, bestDist = nil, nil
     for _, e in ipairs(GetRaidEnemies()) do
      local hum = e.model:FindFirstChildOfClass("Humanoid")
      if hum and hum.Health > 0 and e.hrp and e.hrp.Parent then
       local d = (e.hrp.Position - _tpTargetPos).Magnitude
       if d <= TP_SCAN_RADIUS and (not bestDist or d < bestDist) then
        best = e; bestDist = d
       end
      end
     end
     return best
    end

    local target = _scanNearbyEnemy()
    local _scanWait = 0
    while not target and _scanWait < 3 and RAID.running and not RAID._raidDone do
     task.wait(0.5); _scanWait = _scanWait + 0.5
     target = _scanNearbyEnemy()
    end

    if not target then
     -- Tidak ada musuh dalam radius setelah timeout - anggap gagal, skip map ini
     RaidStatusUpdate("[!] Tidak ada musuh dalam radius " .. TP_SCAN_RADIUS .. " studs - Go Out...", Color3.fromRGB(255,150,50))
     _step4Cleanup()
     task.wait(2)
    else
     -- Musuh ketemu - attack loop pakai cara RA+TA (FCharF style)
     local targetGuid = target.guid
     RaidStatusUpdate("[FLa] Attack: " .. target.model.Name, Color3.fromRGB(255,80,60))

     -- [TA-STYLE] Aktifkan follow-target untuk Heartbeat freeze di atas: mulai
     -- sekarang player akan direposisi 3 stud di depan HRP boss setiap frame,
     -- mengikuti gerak boss (bukan lagi diam di titik TP awal).
     _bossFollowTarget = target

     -- Helper: hitung posisi 10 stud dari musuh ke arah player (sama seperti GetAtkPosF di Farm)
     local function _getBossAtkPos(enemyHRP)
      local char = LP and LP.Character
      local pHRP = char and char:FindFirstChild("HumanoidRootPart")
      if not pHRP or not enemyHRP then return enemyHRP and enemyHRP.Position or _tpTargetPos end
      local ePos = enemyHRP.Position
      local dir = pHRP.Position - ePos
      local dir2 = Vector3.new(dir.X, 0, dir.Z)
      if dir2.Magnitude < 0.1 then return ePos + Vector3.new(10,0,0) end
      return ePos + dir2.Unit * 10
     end

     -- [RA+TA HYBRID] Attack loop STEP4 diganti pakai mekanisme asli RA & TA
     -- (RE.Atk + RE.Click + EnsureHeroAtkThreadFor), BUKAN FireAttack/FireAllDamage/FireHeroRemotes.
     -- Tahap 1 (RA-style): begitu masuk radius 50 studs, fire ke GUID musuh RANDOM dari hasil scan
     --   (memicu combat state, identik cara kerja RA saat memilih musuh acak).
     -- Tahap 2 (TA-style): fire ke GUID boss hasil scan 50 studs, DIKUNCI terus tiap loop
     --   sampai target itu mati (identik cara kerja TA saat lock 1 target by GUID).
     local function _fireOnce(guid)
      if not guid then return end
      if RE.Atk then
       pcall(function() RE.Atk:FireServer({attackEnemyGUID=guid}) end)
      end
      if RE.Click then
       task.spawn(function()
        pcall(function() RE.Click:InvokeServer({enemyGuid=guid}) end)
       end)
      end
      EnsureHeroAtkThreadFor(guid)
     end

     -- Ambil GUID musuh random lain (selain target boss) dari radius 50 studs untuk tahap RA.
     -- Kalau tidak ada musuh lain, fallback pakai GUID boss itu sendiri sebagai RA (tidak masalah).
     local function _pickRandomGuidNearby(excludeGuid)
      local pool = {}
      for _, e in ipairs(GetRaidEnemies()) do
       local hum = e.model:FindFirstChildOfClass("Humanoid")
       if hum and hum.Health > 0 and e.hrp and e.hrp.Parent then
        local d = (e.hrp.Position - _tpTargetPos).Magnitude
        if d <= TP_SCAN_RADIUS then table.insert(pool, e) end
       end
      end
      if #pool == 0 then return excludeGuid end
      local pick = pool[math.random(1, #pool)]
      return pick.guid
     end

     -- Helper: attack 1 cycle = RA (random guid) lalu TA (locked target guid)
     local function _attackBoss(guid, enemyHRP)
      -- Tahap 1: RA-style ke guid random dalam radius
      local _raGuid = _pickRandomGuidNearby(guid)
      _fireOnce(_raGuid)
      -- Tahap 2: TA-style ke guid target boss (locked)
      _fireOnce(guid)
     end

     local _outOfMapCount = 0
     local _bossTimeout   = false          -- [v5] flag timeout 4 menit
     local _atkStart      = tick()         -- [v5] waktu mulai attack
     local BOSS_TIMEOUT   = 240            -- [v5] 4 menit (detik)
     while RAID.running do
      -- [v5] TIMEOUT: 4 menit tanpa boss mati → anggap sukses, keluar seperti kill normal
      if tick() - _atkStart >= BOSS_TIMEOUT then
       _bossTimeout = true
       RaidStatusUpdate("[T] Boss timeout 4min - Dianggap Sukses, keluar...", Color3.fromRGB(255,200,60))
       break
      end
      if _raidServerDone then break end
      local _curMap = GetCurrentMapId()
      if _curMap and (_curMap < 50101 or _curMap > 50120) then
       _outOfMapCount = _outOfMapCount + 1
       if _outOfMapCount >= 3 then
        RaidStatusUpdate("[!] Player keluar raid map - stop attack", Color3.fromRGB(255,140,0))
        break
       end
      else
       _outOfMapCount = 0
      end
      if not target.model or not target.model.Parent then break end
      local hum = target.model:FindFirstChildOfClass("Humanoid")
      if not hum or hum.Health <= 0 then break end
      if not target.hrp or not target.hrp.Parent then
       task.wait() -- [TA-STYLE] no-delay, sama seperti TA
       if not target.model or not target.model.Parent then break end
       local hum2 = target.model:FindFirstChildOfClass("Humanoid")
       if not hum2 or hum2.Health <= 0 then break end
       continue
      end
      -- Scan ulang musuh terdekat dalam radius (jaga-jaga boss ganti/spawn baru)
      local _nearNow = _scanNearbyEnemy()
      if _nearNow and _nearNow.guid ~= targetGuid then
       target = _nearNow
       targetGuid = target.guid
       _bossFollowTarget = target -- [TA-STYLE] update follow-target juga saat target berganti
       RaidStatusUpdate("[FLa] Target baru: " .. target.model.Name, Color3.fromRGB(255,80,60))
      end
      pcall(function() _attackBoss(targetGuid, target.hrp) end)
      task.wait() -- [TA-STYLE] no-delay, sama seperti TA (bukan PG_Wait(0.1))
     end

     _step4Cleanup()
     _raidSuccess = true
     RAID._raidDone = true
     if _bossTimeout then
      RaidStatusUpdate("[T] Timeout 4min - Raid Sukses (forced)", Color3.fromRGB(255,200,60))
     else
      RaidStatusUpdate("[FLa] Target Dead!", Color3.fromRGB(100,255,150))
     end
    end -- if target
   end -- if RAID.running (setelah countdown)
  end -- if _tpTargetPos valid
 elseif RAID.running and not RAID._raidDone then
 -- Auto Kill Boss OFF - tunggu event ChallengeRaidsSuccess max 5 menit
 local _wt = 0
 while RAID.running and not RAID._raidDone and _wt < 300 do
  task.wait(1); _wt = _wt + 1
 end
 end

 -- [FIX v260] Cleanup terpusat (idempoten - aman meski sudah dipanggil dari dalam autoKillBoss path)
 _step4Cleanup()

 if _raidSuccess then
 RAID.sukses = RAID.sukses + 1
 RaidCounterUpdate()
 RaidStatusUpdate("[OK] Succes-" .. RAID.sukses .. " Map " .. mn, Color3.fromRGB(100,255,150))
 -- [RAID LIST ENTRY] Catat map ini sudah dikunjungi setelah sukses keluar
 if RAID.listEnabled and RAID.raidMapId then
  RAID._listVisitedMaps[RAID.raidMapId] = true
 end
 end
 if not RAID.running then break end

 if _raidSuccess then
  RaidStatusUpdate("[..] Wait 1s (Get reward)...", Color3.fromRGB(100,255,150))
  task.wait(1)
 end
 if not RAID.running then break end

 -- STEP 5: Collect + Exit raid
 task.spawn(function() pcall(RaidCollectAll) end)
 RaidStatusUpdate("[FLa] Go Out raid...", Color3.fromRGB(100,200,255))

 RAID_LIVE[RAID.raidId] = nil
 RebuildRaidList()

 -- [v11 EDIT] STEP 6: TP kembali ke MAP TERAKHIR player berada (bukan
 -- selalu Map 1 lagi). Prioritas sumber: MR.lastMapId (map terakhir Mass
 -- Attack TP ke sana) -> RAID.fromMapId (map sebelum masuk raid, dikirim
 -- server) -> fallback Map 1 (50001) kalau keduanya kosong / di luar range
 -- basemap normal (50001-50020). Reward sudah di-collect bersamaan saat
 -- boss mati (RaidCollectAll di atas).
 local _toMapId = 50001
 do
     local _cand = MR and MR.lastMapId or nil
     if not (_cand and _cand >= 50001 and _cand <= 50021) then
         _cand = RAID.fromMapId
     end
     if _cand and _cand >= 50001 and _cand <= 50021 then
         _toMapId = _cand
     end
 end
 RaidStatusUpdate("[FLa] Go Out -> Map ".. (_toMapId-50000) .."...", Color3.fromRGB(200,100,100))

 -- Helper TP -- [v11 EDIT] selalu pakai remote StartLocalPlayerTeleport
 -- (RE.StartTp) untuk semua map, sesuai capture manual SimpleSpy user.
 -- Tidak lagi branching berdasarkan range map (index<=4 vs lainnya).
 local function _fireTpRaid(mapId)
 pcall(function() RE.StartTp:FireServer({ mapId = mapId }) end)
 end

 -- Cek masih di area raid
 local function _inRaidArea()
 local ok = false
 pcall(function()
 local wm = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
 if wm then
 ok = (wm >= 50101 and wm <= 50120) -- [FIX v17] cover Map 19 & 20
 end
 end)
 return ok
 end

 if true then -- [INDEPENDEN] tidak cek siege
 -- Kirim QuitRaidsMap + TpRemote berlapis
 local _quitRe = Remotes:FindFirstChild("QuitRaidsMap")
 if _quitRe then
 pcall(function() _quitRe:FireServer({ currentSlotIndex = RAID.slotIndex or 2, toMapId = _toMapId }) end)
 end
 task.wait(0.3)
 _fireTpRaid(_toMapId)

 -- Retry max 5x kalau masih di raid area
 local _exitTry = 0
 while _inRaidArea() and _exitTry < 5 and RAID.running do
 _exitTry = _exitTry + 1
 task.wait(1)
 if _quitRe then
 pcall(function() _quitRe:FireServer({ currentSlotIndex = RAID.slotIndex or 2, toMapId = _toMapId }) end)
 end
 task.wait(0.2)
 _fireTpRaid(_toMapId)
 end
 end

 RAID.fromMapId = nil
 RAID.inMap = false

 -- STEP 6: Resume MA -> cooldown
 _raidInterrupt = false
 MODE:Release("raid") -- [FIX v257] MA HARUS resume saat player di luar raid
 -- [FIX v256] Cooldown 12s: server butuh ~12s sebelum bisa masuk Raid lagi
 -- TAPI: selama cooldown, tetap scan workspace agar RAID_LIVE siap
 -- Saat cooldown habis, langsung masuk tanpa delay tambahan
 -- [BUG FIX 3] Tandai cooldown aktif agar standby loop tidak terburu-buru masuk
 RAID._cooldownActive = true
 for cd = 14, 1, -1 do
 if not RAID.running then break end
 -- [INDEPENDEN] tidak tunggu siege setelah exit raid
 -- Scan workspace selama cooldown agar data siap
 if cd % 3 == 0 then ForceRescanRaidEnter() end
 RaidStatusUpdate("[..] Cooldown " .. cd .. "s...", Color3.fromRGB(160,148,135))
 if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
 task.wait(1)
 end
 RAID._cooldownActive = false -- [BUG FIX 3] Cooldown selesai, standby loop boleh masuk

 -- [FIX BUG 2 LIST ENTRY] Buffer 2s tambahan setelah cooldown 14s
 -- Mencegah "terlalu cepat masuk raid lagi" notif dari server
 if RAID.listEnabled and #RAID.listEntries > 0 then
  RaidStatusUpdate("[..] List Entry buffer 2s...", Color3.fromRGB(160,148,135))
  for _bf = 2, 1, -1 do
   if not RAID.running then break end
   task.wait(1)
  end
 end

 -- [v247] STEP 7: Setelah cooldown selesai:
 -- 1. Jika SIEGE aktif/running -> tunggu SIEGE selesai total dulu (PRIORITAS atas MA)
 -- 2. Setelah SIEGE selesai -> baru MA bisa resume (via _raidInterrupt=false)
 -- 3. Jika tidak ada SIEGE -> MA langsung resume
 if RAID.running then
 RaidStatusUpdate("[>>] Waiting & Cooldown...", Color3.fromRGB(100,255,150))
 if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
 local _fw = 0
 while RAID.running do
 -- [FIX v256] Agresif: manual scan workspace tiap cycle
            ForceRescanRaidEnter()

            -- [HUKUM PRIORITAS TERTINGGI DI FASE STANDBY]
            local isBusy = false
            if (SIEGE and (SIEGE.inMap or SIEGE.teleporting)) then
                isBusy = true
            end
            local mapId = workspace:GetAttribute("MapId") or 0
            if (mapId >= 50201 and mapId <= 50204) then
                isBusy = true
            end
            -- RAID standby selama _ascBusy=true (ASC inMap atau cooldown dengan Tower tersedia)
            local _ascBlocking = ASC and ASC.running and _ascBusy

            if isBusy or _ascBlocking then
                if _ascBlocking then
                    RaidStatusUpdate("[||] ASC aktif & ada Tower match - Normal Raid standby...", Color3.fromRGB(180, 100, 255))
                else
                    RaidStatusUpdate("[!] PAUSE: Menunggu Siege/Dungeon Selesai...", Color3.fromRGB(255, 100, 100))
                end
            else
                -- Jika aman, baru boleh cari Raid
                -- Cek IsRaidLiveInGame DULU sebelum ResolveEntry
                -- [BUG FIX 3] Jangan break jika cooldown masih aktif
                if not RAID._cooldownActive and IsRaidLiveInGame() then
                    local _newEntry = ResolveEntry and ResolveEntry()
                    if _newEntry then raidEntry = _newEntry; break end
                    RaidStatusUpdate("[FLa] Waiting grade filter... (" .. _fw .. "s)", Color3.fromRGB(200,255,150))
                else
                    RaidStatusUpdate("[FLa] Empty RAID - Waiting event baru... (" .. _fw .. "s)", Color3.fromRGB(160,120,60))
                end
            end
 -- [FIX v256] Wakeup CEPAT: poll 0.05s, max 0.5s
 local _woken2 = false
 local _wConn2
 if _raidWakeup then
 _wConn2 = _raidWakeup.Event:Connect(function() _woken2 = true end)
 end
 local _we2 = 0
 while not _woken2 and _we2 < 1 and RAID.running do
 task.wait(0.1); _we2 = _we2 + 0.1
 end
 if _wConn2 then pcall(function() _wConn2:Disconnect() end) end
 _fw = _fw + 1
 end
 end

 until true
 end -- while RAID.running
 end) -- pcall

 -- [v63 FIX] Cleanup dijamin jalan meskipun ada Lua error di dalam loop
 _raidInterrupt = false
 RAID.running = false
 RAID.inMap = false
 _raidOn = false
 _raidFallbackActive = false  -- [v61 CYCLEFIX] reset saat RAID stop
 MODE:Release("raid") -- [v257] pastikan MA bisa resume
 RaidStatusUpdate("[FLa] Auto Raid STOP", Color3.fromRGB(160,148,135))
 if RAID.dot then RAID.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
 end)
end

-- ============================================================================
-- AUTO ASCENSION: LOGIC (port dari 1.lua baris 10499-11916)
-- ResolveAscEntry & ResolveAscEntryFromList dibuat GLOBAL (bukan nested), independen dari RAID Normal
-- AUTO BOSS KILL: pakai metode lama 1.lua (scan nama boss + ChildAdded), damage call diganti
-- RaidFireDamage -> FireAttack+FireAllDamage+FireHeroRemotes (RaidFireDamage tidak ada di 2.lua)
-- ============================================================================
-- AUTO ASCENSION : LOGIC
function StopAscension()
 ASC.running = false
 ASC.inMap   = false
 _ascBusy    = false
 _eventOwner = nil
 ReleaseMapLock("asc")
 -- [v62 FIX] Reset status label agar tidak nyantol di "Dalam Tower x"
 AscStatusUpdate("OFF", Color3.fromRGB(120,120,120))
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 if ASC.thread then
  pcall(function() task.cancel(ASC.thread) end)
  ASC.thread = nil
 end
 if _ascWakeup then
  pcall(function() _ascWakeup:Destroy() end)
  _ascWakeup = nil
 end
end

function AscCounterUpdate()
 if ASC.suksesLbl then ASC.suksesLbl.Text = tostring(ASC.sukses) end
end

-- Helper: ambil semua entry Ascension dari RAID_LIVE (sorted)
local function GetAscensionList()
 local list = {}
 for rid, ent in pairs(RAID_LIVE) do
  -- isAscension == true ATAU raidId >= 935001 (range Ascension Tower dari server)
  local ridAbs = rid < 0 and math.abs(rid) or rid
  -- [v34 FIX] Kecuali Anniversary Celebration (raidId 937101) - BUKAN ASC Tower
  -- Sebelumnya Anniversary masuk ke ASC list karena ridAbs >= 935001
  local _isAnniversaryEntry = (ridAbs == 937101)
  if _isAnniversaryEntry then continue end -- skip Anniversary, bukan ASC
  if ent.isAscension == true or ridAbs >= 935001 then
   if not ent.isAscension then ent.isAscension = true end -- auto-mark
   -- Resolve raidId positif jika entry chat (negatif)
   local resolvedId = rid
   if rid < 0 then
    -- Cari raidId positif dari RAID_LIVE yang sama mapId & isAscension
    for rid2, ent2 in pairs(RAID_LIVE) do
     if rid2 > 0 and ent2.isAscension and ent2.mapId == ent.mapId then
      resolvedId = rid2; break
     end
    end
    -- Jika masih negatif, berarti raidId dari server belum datang
    -- Gunakan nilai absolut sebagai ID sementara supaya CreateRaidTeam bisa dicoba
    -- (server akan reject jika ID tidak valid, dan loop akan retry)
    if resolvedId < 0 then resolvedId = math.abs(resolvedId) end
   end
   -- ASC mapId 50301-50326 -> mapNum 1-26; RAID mapId 50001-50020 -> mapNum 1-20
   local _mId = ent.mapId or 50000
   local mn = (_mId >= 50301 and _mId <= 50326) and (_mId - 50300) or (_mId - 50000)
   -- [FIX] Grade resolution: prioritas chat cache -> runeGradeCache -> ent.grade -> "?"
   -- ent.grade bisa nil jika workspace event datang sebelum chat notif
   local _resolvedGrade = ent.grade
   if (not _resolvedGrade or _resolvedGrade == "?") and _ASC_CHAT_CACHE and _ASC_CHAT_CACHE[mn] then
    _resolvedGrade = _ASC_CHAT_CACHE[mn].grade or _resolvedGrade
   end
   if (not _resolvedGrade or _resolvedGrade == "?") and _runeGradeCache then
    _resolvedGrade = _runeGradeCache[-mn] or _runeGradeCache[mn] or _resolvedGrade
   end
   _resolvedGrade = _resolvedGrade or "?"
   table.insert(list, {
    id      = resolvedId,
    rawId   = rid,
    mapId   = ent.mapId,
    mapNum  = mn,
    grade   = _resolvedGrade,
    bossName= ent.bossName,
    isAscension = true,
   })
  end
 end
 return list
end

-- [ADAPT 2.lua] GetCurrentMapId & GetPlayerPos sudah ada sebagai fungsi global di 2.lua, tidak perlu didefinisikan ulang

-- ResolveAscEntry / ResolveAscEntryFromList dibuat GLOBAL (bukan nested di StartAscensionLoop)
-- agar bisa diakses dari luar (independen, sesuai keputusan salflo)
 function ResolveAscEntryFromList()
  if not ASC.listEnabled then return nil end
  if #ASC.listEntries == 0 then return nil end
  local ascList = GetAscensionList()
  if #ascList == 0 then return nil end

  -- Grade helper
  local function _getGradeL(r)
   local g = GetBestGrade(r.mapNum, true)
   if not g or g == "?" then g = r.grade end
   return (g and g ~= "?") and g or nil
  end

  -- Kumpulkan semua tower yang match dari semua entry
  local function collectAllMatched(skipVisited)
   local allMatched = {}
   local seen = {}
   for i = 1, #ASC.listEntries do
    local ent = ASC.listEntries[i]
    local hasMaps  = next(ent.maps)  ~= nil
    local hasRanks = next(ent.ranks) ~= nil
    for _, r in ipairs(ascList) do
     if seen[r.mapNum] then continue end
     if skipVisited and ASC._listVisitedMaps[r.mapNum] then continue end
     local mapsOk = (not hasMaps) or ent.maps[r.mapNum]
     if not mapsOk then continue end
     if hasRanks then
      local grade = _getGradeL(r)
      if grade and ent.ranks[grade] then
       table.insert(allMatched, r); seen[r.mapNum] = true
      end
     else
      table.insert(allMatched, r); seen[r.mapNum] = true
     end
    end
   end
   return allMatched
  end

  -- Tahap 1: cari yang belum dikunjungi
  local allMatched = collectAllMatched(true)
  -- Tahap 2: kalau semua sudah dikunjungi -> reset visited dan loop ulang
  if #allMatched == 0 then
   for k in pairs(ASC._listVisitedMaps) do ASC._listVisitedMaps[k] = nil end
   allMatched = collectAllMatched(true)
  end
  if #allMatched == 0 then return nil end
  -- Pilih mapNum terkecil dari semua yang match
  table.sort(allMatched, function(a, b) return a.mapNum < b.mapNum end)
  return allMatched[1]
 end

function ResolveAscEntry()
  local ascList = GetAscensionList()
  if #ascList == 0 then return nil, "no_tower" end

  -- [LIST ENTRY ASC] Cek List Entry dulu sebelum logika Pick Mode
  if ASC.listEnabled and #ASC.listEntries > 0 then
   local listResult = ResolveAscEntryFromList()
   if listResult then return listResult end
   -- Tidak ada match -> fallback ke Pick Mode normal (lanjut ke bawah)
  end

  -- Prune expired entries (sama seperti RAID)
  local _now0 = os.time()
  local _pruned0 = false
  for rid, ent in pairs(RAID_LIVE) do
   if ent.isAscension and ent.endTime and ent.endTime < (_now0 - 10) then
    RAID_LIVE[rid] = nil; _pruned0 = true
   end
  end
  if _pruned0 then
   ascList = GetAscensionList()
   if #ascList == 0 then return nil, "no_tower" end
  end

  local pm = ASC.pickMode or "easy"
  local hasPick = (pm == "byrank" or pm == "manual") and next(ASC.runeGrades or {}) ~= nil

  -- Grade helper: GetBestGrade dulu, fallback ke r.grade (sudah di-resolve di GetAscensionList)
  local function _getGrade(r)
   local g = GetBestGrade(r.mapNum, true)
   if not g or g == "?" then g = r.grade end
   return (g and g ~= "?") and g or nil
  end

  -- pickLowest: ambil tower dengan mapNum terkecil
  local function pickLowest(list)
   table.sort(list, function(a, b) return a.mapNum < b.mapNum end)
   return list[1]
  end

  -- sortHighestRank: sort rank tertinggi, tie-break mapNum terkecil (identik RAID)
  local function sortHighestRank(list)
   table.sort(list, function(a, b)
    local ga = _getGrade(a) or "?"
    local gb = _getGrade(b) or "?"
    local ra = GRADE_RANK[ga] or 0
    local rb = GRADE_RANK[gb] or 0
    if ra == rb then return a.mapNum < b.mapNum end
    return ra > rb
   end)
  end

  -- pickByDiff: identik RAID pickByDiff, adaptasi mapNum
  local function pickByDiff(list)
   if #list == 0 then return nil end
   if pm == "easy" then
    table.sort(list, function(a, b) return a.mapNum < b.mapNum end)
    return list[1]
   elseif pm == "hard" then
    table.sort(list, function(a, b) return a.mapNum > b.mapNum end)
    return list[1]
   elseif pm == "default" then
    -- Round-robin Tower 1-8, fallback ke terkecil (identik RAID map 1-8)
    local low = {}
    for _, r in ipairs(list) do
     if r.mapNum >= 1 and r.mapNum <= 8 then table.insert(low, r) end
    end
    if #low == 0 then return pickLowest(list) end
    table.sort(low, function(a, b) return a.mapNum < b.mapNum end)
    ASC._rrIdx = (ASC._rrIdx or 0) + 1
    if ASC._rrIdx > #low then ASC._rrIdx = 1 end
    return low[ASC._rrIdx]
   elseif pm == "byrank" then
    sortHighestRank(list)
    return list[1]
   elseif pm == "bymap" then
    table.sort(list, function(a, b) return a.mapNum < b.mapNum end)
    for _, r in ipairs(list) do
     if ASC.preferMaps[r.mapNum] then return r end
    end
    return list[1]
   end
   return pickLowest(list)
  end

  -- MANUAL MODE — identik RAID: 3 tahap, fallback ke terkecil
  if pm == "manual" then
   ASC.manualMatchMode = "none"
   local valid_asc = {}
   local hasPreferMaps = next(ASC.preferMaps or {}) ~= nil

   -- [FIX] Tahap 0: kumpulkan kandidat, filter PreferMap jika di-set.
   -- Kalau Preferred Map diset dan TIDAK ADA yang cocok -> STOP di sini,
   -- return no_match murni. TIDAK boleh diam-diam fallback ke Map lain
   -- (itu yang bikin script "nyasar" masuk map yang user tidak pilih).
   -- Fallback EASY (Map 1-10, rank bebas) HANYA terjadi di paling akhir
   -- fungsi ini, sebagai langkah terpisah - bukan disembunyikan di sini.
   for _, r in ipairs(ascList) do
    local mn = r.mapNum
    if not hasPreferMaps or ASC.preferMaps[mn] then
     table.insert(valid_asc, r)
    end
   end
   if #valid_asc == 0 then
    ASC.manualMatchMode = "none"
    return nil, "no_match"
   end

   -- Helper sort
   local function sortHighestRankLocal(list)
    table.sort(list, function(a, b)
     local ga = _getGrade(a) or "?"
     local gb = _getGrade(b) or "?"
     local ra = GRADE_RANK[ga] or 0
     local rb = GRADE_RANK[gb] or 0
     if ra == rb then return a.mapNum < b.mapNum end
     return ra > rb
    end)
   end

   -- TAHAP 1: Cari kecocokan Preferred Rank
   local matched = {}
   local hasPreferRank = next(ASC.runeGrades or {}) ~= nil
   if hasPreferRank then
    for _, r in ipairs(valid_asc) do
     local grade = _getGrade(r)
     if grade and ASC.runeGrades[grade] then
      table.insert(matched, r)
     end
    end
    if #matched > 0 then
     sortHighestRankLocal(matched)
     ASC.manualMatchMode = "primary"
     return matched[1]
    end
    -- [FIX] Rank diset tapi tidak ada tower yang cocok -> STOP, no_match murni.
    -- Sebelumnya di sini ada fallback diam2 ke Map 1-16 rank bebas -- itu akar
    -- masalah kenapa Rune Map bisa "nyasar" masuk ke tower yang rank-nya tidak
    -- dipilih user. Sekarang: kalau Rank tidak match, manual mode GAGAL total.
    ASC.manualMatchMode = "none"
    return nil, "no_match"
   end

   -- Tidak ada Preferred Rank diset -> fallback ke tower terkecil dari kandidat
   -- (ini beda kasus: user memang tidak set Preferred Rank sama sekali, jadi
   -- rank apapun sah-sah saja selama Map-nya match Preferred Map / semua Map)
   ASC.manualMatchMode = "fallback"
   table.sort(valid_asc, function(a, b) return a.mapNum < b.mapNum end)
   return valid_asc[1]
  end

  -- BYRANK + BYMAP + hasPick: identik RAID
  if hasPick then
   local matched2 = {}
   for _, r in ipairs(ascList) do
    local grade = _getGrade(r)
    if grade and ASC.runeGrades[grade] == true then table.insert(matched2, r) end
   end
   if #matched2 > 0 then
    local chosen = pickByDiff(matched2)
    if chosen then return chosen end
   end
   if pm == "byrank" then return nil, "no_match" end  -- byrank: ada tower tapi rank tidak cocok
  end

  if pm == "bymap" and next(ASC.preferMaps or {}) ~= nil then
   local mapMatched = {}
   for _, r in ipairs(ascList) do
    if ASC.preferMaps[r.mapNum] then table.insert(mapMatched, r) end
   end
   if #mapMatched > 0 then return pickLowest(mapMatched) end
   return nil, "no_match"  -- bymap: ada tower tapi map tidak cocok
  end

  return pickByDiff(ascList)
 end

-- ============================================================================
-- [FIX v2] FALLBACK EASY FINAL (Map 1-10, rank bebas)
-- Dipanggil setelah ResolveAscEntry() gagal total (return nil, "no_match"),
-- TANPA PEDULI status RAID Normal. Prioritas: Fallback EASY dicoba DULUAN --
-- baru kalau Fallback EASY juga gagal (tidak ada ASC di Map 1-10 sama sekali),
-- barulah ASC mundur dan kasih giliran ke RAID Normal (kalau RAID.running).
-- Ini menggantikan fallback 1-16 lama yang dulu tersembunyi di dalam blok
-- Manual -- sekarang eksplisit, terpisah, dan konsisten dipakai di semua
-- titik pemanggilan ResolveAscEntry (bukan cuma di satu tempat).
-- ============================================================================
function ResolveAscEntryFallbackEasy()
 local ascList = GetAscensionList()
 if #ascList == 0 then return nil end
 local low10 = {}
 for _, r in ipairs(ascList) do
  if r.mapNum >= 1 and r.mapNum <= 10 then table.insert(low10, r) end
 end
 if #low10 == 0 then return nil end
 table.sort(low10, function(a, b) return a.mapNum < b.mapNum end)
 ASC.manualMatchMode = "fallback_easy"
 return low10[1]
end

-- [FIX BUG] ResolveAscTargetMapId tertinggal saat port (asalnya di 1.lua baris 1697,
-- di luar range StartAscensionLoop yang diekstrak) - tanpa ini, StartAscensionLoop
-- crash setiap kali mau ENTER Tower (ResolveAscTargetMapId = nil value), pcall
-- menelan error-nya diam-diam -> ASC keluar loop -> "Auto Ascension STOP".
-- Inilah sebab kedua bug: deteksi sebenarnya jalan, tapi begitu mau masuk Tower
-- langsung crash sebelum sempat TP, jadi user lihatnya "tidak masuk" / "STOP".
function ResolveAscTargetMapId(mapNum)
 -- mapNum = nomor Tower (1-26) dari chat "Ascension Tower X"
 -- Return: mapId untuk StartChallengeRaidMap (50301-50326)
 if not mapNum or mapNum < 1 or mapNum > 26 then return 50301 end
 return 50300 + mapNum
end

function StartAscensionLoop()
 StopAscension()
 ASC.running = true
 ASC.sukses  = 0
 AscCounterUpdate()
 -- [v56 FIX] Wakeup RAID segera saat ASC di-ON
 -- RAID yang lagi di waiting loop harus langsung sadar ASC aktif dan mundur
 -- (fire SETELAH ASC.running = true agar kondisi ASC.running and ResolveAscEntry() terbaca benar)
 if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
 if _ascWakeup then pcall(function() _ascWakeup:Destroy() end) end
 _ascWakeup = Instance.new("BindableEvent")

 AscStatusUpdate("Siap. Menunggu Ascension Tower...", Color3.fromRGB(180,180,60))

 -- ResolveAscEntry: Pick Mode logic IDENTIK dengan AUTO RAID
 -- Semua mode locked kecuali Manual -> hanya masuk Tower terkecil
 -- Manual: PREFERRED MAP + PREFERRED RANK aktif, fallback ke terkecil jika tidak match
 -- ResolveAscEntry: 100% IDENTIK dengan ResolveEntry (Auto Raid Normal)
 -- Satu-satunya perbedaan: pakai ASC.* dan ascList (mapNum) bukan RAID_ID_LIST (mapId)
 -- MapId masuk ke tower tetap 503xx — tidak diubah di sini
 -- Return: entry (match), nil+"no_tower" (tidak ada tower), nil+"no_match" (ada tower tapi filter tidak cocok)
 -- LIST ENTRY ASC: cari tower yang match list, fallback ke Pick Mode

 ASC.thread = task.spawn(function()
  pcall(function()
  while ASC.running do
   repeat

    -- [v48] Cek semua interrupt (sama seperti RAID)

    if ST2 and (ST2.running or ST2.inMap) then
     ASC.inMap = false
     AscStatusUpdate("[||] Tower aktif - Ascension pause...", Color3.fromRGB(255,140,0))
     while ST2 and (ST2.running or ST2.inMap) and ASC.running do task.wait(0.5) end
     if not ASC.running then break end
     AscStatusUpdate("> Tower selesai - lanjut Ascension...", C.ACC3)
     task.wait(0.1)
    end

    if (SIEGE and (SIEGE.inMap or SIEGE.teleporting)) or _siegeInterrupt then
     ASC.inMap = false
     AscStatusUpdate("[||] Siege aktif - Ascension pause...", Color3.fromRGB(255,140,0))
     while ((SIEGE and (SIEGE.inMap or SIEGE.teleporting)) or _siegeInterrupt) and ASC.running do task.wait(0.5) end
     if not ASC.running then break end
     AscStatusUpdate("> Siege selesai - lanjut Ascension...", C.ACC3)
     task.wait(0.1)
    end

    -- Blokir jika di dalam map RAID Normal atau Siege (bukan Ascension Tower sendiri)
    local curWm = workspace:GetAttribute("MapId") or 0
    if (curWm >= 50101 and curWm <= 50120) or (curWm >= 50201 and curWm <= 50205) then
     AscStatusUpdate("[||] Sedang di dalam map lain - tunggu...", Color3.fromRGB(255,140,0))
     task.wait(3); break
    end

    -- [v48] Resolve entry berdasarkan Pick Mode
    local raidEntry, _ascReason = ResolveAscEntry()

    -- [FIX v2] Prioritas dibalik: Fallback EASY (Map 1-10, rank bebas) DICOBA
    -- DULUAN kalau List Entry + Manual gagal total. Baru kalau Fallback EASY
    -- juga tidak ada hasil (tidak ada ASC apapun di Map 1-10 saat ini), barulah
    -- ASC mundur dan kasih giliran ke RAID Normal (kalau RAID.running).
    if not raidEntry and _ascReason == "no_match" then
     local _fbEasy = ResolveAscEntryFallbackEasy and ResolveAscEntryFallbackEasy()
     if _fbEasy then
      raidEntry = _fbEasy
      AscStatusUpdate("[Fallback Easy] Filter tidak match -> Tower "..raidEntry.mapNum.." (Map 1-10)...", Color3.fromRGB(80,180,255))
     end
    end

    -- [FALLBACK FIX] Fallback EASY juga gagal (tidak ada ASC di Map 1-10) +
    -- RAID.running -> giliran Auto Raid Normal siklus ini
    if not raidEntry and _ascReason == "no_match" and RAID and RAID.running then
     AscStatusUpdate("[Fallback] Filter tidak match - giliran Auto Raid siklus ini...", Color3.fromRGB(140,80,200))
     if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
     _eventOwner = "raid"
     -- Tunggu sampai RAID selesai satu siklus atau ada tower baru yang match
     local _fbConn
     local _fbDone = false
     if _ascWakeup then
      _fbConn = _ascWakeup.Event:Connect(function()
       _fbDone = true  -- ada event baru, coba resolve lagi
      end)
     end
     while ASC.running and not _fbDone do
      task.wait(0.5)
      -- Cek apakah sekarang ada match (event baru bisa datang)
      local _recheck, _recheckReason = ResolveAscEntry()
      if _recheck then _fbDone = true; raidEntry = _recheck end
     end
     if _fbConn then pcall(function() _fbConn:Disconnect() end) end
     if not raidEntry then
      break  -- kembali ke outer while loop, cek kondisi fresh
     end
    end

    -- Waiting loop jika tidak ada Ascension Tower tersedia (no_tower atau ASC-only)
    while ASC.running and not raidEntry do
     local ascList = GetAscensionList()
     local _pm = ASC.pickMode or "easy"
     local _, _curReason = ResolveAscEntry()
     -- Jika ada tower tapi filter tidak match dan RAID running -> fallback
     -- (ini handle kasus dimana tower muncul SAAT waiting loop berjalan)
     if _curReason == "no_match" and RAID and RAID.running then
      AscStatusUpdate("[Fallback] Filter tidak match - giliran Auto Raid...", Color3.fromRGB(140,80,200))
      if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
      _eventOwner = "raid"
      break
     elseif _raidFallbackActive and RAID.running then
      AscStatusUpdate("[Standby] RAID fallback aktif siklus ini - tunggu siklus event baru...", Color3.fromRGB(140,80,200))
     elseif #ascList == 0 then
      if RAID.running then
       AscStatusUpdate("[Standby] Fallback ke Auto Raid - tunggu Ascension Tower...", Color3.fromRGB(140,100,200))
      else
       AscStatusUpdate("Waiting Ascension Tower [".._pm.."]...", Color3.fromRGB(140,140,60))
      end
     elseif _pm == "manual" then
      -- Manual mode: tampilkan filter aktif
      local _parts = {}
      local _hasMap = next(ASC.preferMaps or {}) ~= nil
      local _hasRank = next(ASC.runeGrades or {}) ~= nil
      if _hasMap then
       local _ms = {}
       for mn=1,26 do if ASC.preferMaps and ASC.preferMaps[mn] then table.insert(_ms,"T"..mn) end end
       table.insert(_parts, "Map["..table.concat(_ms,"|").."]")
      end
      if _hasRank then
       local _gr = {}
       for _, g in ipairs(GRADE_LIST) do if ASC.runeGrades[g] then table.insert(_gr, g) end end
       table.insert(_parts, "Rank["..table.concat(_gr,"||").."]")
      end
      if _hasRank and ASC.runeEnabled and ASC.runeMapTarget >= 1 and ASC.runeMapTarget <= 26 then
       table.insert(_parts, "Rune->T"..ASC.runeMapTarget)
      end
      local _filterStr = #_parts > 0 and table.concat(_parts," | ") or "no filter"
      -- Jika ada tower tapi tidak cocok filter rank -> beri keterangan lebih jelas
      local _ascListNow = GetAscensionList()
      local _noMatchNote = (#_ascListNow > 0 and _hasRank) and " [no rank match]" or "..."
      AscStatusUpdate("Waiting [Manual] "..(_filterStr).._noMatchNote, Color3.fromRGB(255,180,50))
     elseif _pm == "bymap" then
      local _ms = {}
      for mn=1,26 do if ASC.preferMaps and ASC.preferMaps[mn] then table.insert(_ms,"T"..mn) end end
      local _mapStr = #_ms > 0 and table.concat(_ms,"|") or "NOT SET"
      AscStatusUpdate("Waiting [ByMap] "..(_mapStr).." (fallback: terkecil)...", Color3.fromRGB(100,200,100))
     elseif _pm == "byrank" then
      local _gr = {}
      for _, g in ipairs(GRADE_LIST) do if ASC.runeGrades[g] then table.insert(_gr, g) end end
      local _rankStr = #_gr > 0 and table.concat(_gr,"||") or "NOT SET"
      AscStatusUpdate("Waiting [ByRank] "..(_rankStr).." (fallback: terkecil)...", Color3.fromRGB(200,120,255))
     elseif _pm == "hard" then
      AscStatusUpdate("Waiting Ascension Tower [Hard - Tower Terbesar]...", Color3.fromRGB(255,80,80))
     elseif _pm == "easy" then
      AscStatusUpdate("Waiting Ascension Tower [Easy - Tower Terkecil]...", Color3.fromRGB(80,220,80))
     else
      AscStatusUpdate("Waiting Ascension Tower [".._pm.."]...", Color3.fromRGB(255,200,60))
     end
     -- Wakeup cepat
     local _woken = false
     local _wConn
     if _ascWakeup then
      _wConn = _ascWakeup.Event:Connect(function() _woken = true end)
     end
     local _we = 0
     while not _woken and _we < 1 and ASC.running do
      task.wait(0.1); _we = _we + 0.1
     end
     if _wConn then pcall(function() _wConn:Disconnect() end) end
     -- [v62 RINO/RINI FIX] Jika TriggerEntryWakeup memutuskan ini giliran RAID ("rini"),
     -- ASC ("rino") tetap duduk. Tidak mencoba resolve apapun sampai siklus berikutnya.
     if _eventOwner == "raid" and RAID.running then
      raidEntry = nil  -- ASC standby, RAID yang jalan siklus ini
     elseif _raidFallbackActive and RAID.running then
      raidEntry = nil  -- fallback lama (v61 compat)
     else
      local _re2, _reason2 = ResolveAscEntry()
      raidEntry = _re2
      -- [FIX v2] Fallback EASY DICOBA DULUAN kalau no_match, tanpa peduli RAID.running
      if not raidEntry and _reason2 == "no_match" then
       local _fbEasy2 = ResolveAscEntryFallbackEasy and ResolveAscEntryFallbackEasy()
       if _fbEasy2 then
        raidEntry = _fbEasy2
        AscStatusUpdate("[Fallback Easy] Filter tidak match -> Tower "..raidEntry.mapNum.." (Map 1-10)...", Color3.fromRGB(80,180,255))
       end
      end
      -- Fallback EASY juga gagal (tidak ada ASC di Map 1-10) + RAID running -> giliran RAID
      if not raidEntry and _reason2 == "no_match" and RAID and RAID.running then
       AscStatusUpdate("[Fallback] Filter tidak match - giliran Auto Raid...", Color3.fromRGB(140,80,200))
       if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
       _eventOwner = "raid"
       break  -- keluar waiting loop, biarkan RAID jalan
      end
     end
    end
    if not ASC.running then break end
    if not raidEntry then break end

    -- [v56 FIX] ASC guard: tunggu fitur lain selesai sebelum masuk Tower
    -- RAID: tunggu sampai RAID.inMap = false (keluar dari map), lalu ASC boleh masuk
    do
     local _aWait = 0
     while ASC.running and _aWait < 90 do
      local _busy, _who = IsAnyMapActive()
      local _selfBusy = (_who == "asc")
      if not _busy or _selfBusy then break end
      AscStatusUpdate("[||] Tunggu "..(_who or "?").." selesai dulu...", Color3.fromRGB(255,140,0))
      task.wait(0.5); _aWait = _aWait + 0.5
     end
     if not ASC.running then break end
    end

    -- [v52 FIX] Atomic lock: cegah RAID masuk bersamaan saat ASC baru lolos guard
    -- Tanpa lock ini: RAID dan ASC bisa lolos guard hampir bersamaan (keduanya lihat inMap=false)
    -- lalu keduanya coba TP player ke map berbeda dalam waktu bersamaan
    do
     local _lockWait = 0
     while ASC.running and _lockWait < 15 do
      if TryClaimMapLock("asc") then break end
      AscStatusUpdate("[||] Tunggu slot masuk map bebas...", Color3.fromRGB(200,160,255))
      task.wait(0.2); _lockWait = _lockWait + 0.2
     end
     if not ASC.running then ReleaseMapLock("asc"); break end
    end

    local mn = raidEntry.mapNum
    -- [LIST ENTRY ASC] Tandai tower ini sudah dikunjungi di siklus ini
    if ASC.listEnabled and #ASC.listEntries > 0 then
     ASC._listVisitedMaps[mn] = true
    end
    local bossHint = raidEntry.bossName and (" - "..raidEntry.bossName) or ""
    AscStatusUpdate("Masuk: Tower "..mn..bossHint.." ["..raidEntry.grade.."]", Color3.fromRGB(100,200,255))

    -- Tunggu SIEGE selesai dulu jika sedang inMap
    if SIEGE and (SIEGE.inMap or SIEGE.teleporting) then
        AscStatusUpdate("[||] Tunggu SIEGE selesai...", Color3.fromRGB(255,180,50))
        local _ws = 0
        while (SIEGE.inMap or SIEGE.teleporting) and ASC.running and _ws < 120 do
            task.wait(0.5); _ws = _ws + 0.5
        end
        if not ASC.running then return end
    end

    -- Tunggu RAID selesai dulu jika sedang inMap
    if RAID and RAID.inMap then
        AscStatusUpdate("[||] Tunggu RAID selesai...", Color3.fromRGB(255,180,50))
        local _wr = 0
        while RAID.inMap and ASC.running and _wr < 120 do
            task.wait(0.5); _wr = _wr + 0.5
        end
        if not ASC.running then return end
    end

    _ascInterrupt = true  -- signal MA untuk pause (MA cek di guard tiap iterasi)

    -- [v12 EDIT] ASC match ditemukan -- hard-stop Mass Attack SEGERA + delay 2s
    -- sebelum lanjut masuk Ascension Tower, cegah race condition rebutan musuh.
    if _MA_HardStopForMatch then _MA_HardStopForMatch(function(msg) AscStatusUpdate(msg, Color3.fromRGB(255,180,50)) end) end

    ASC.inMap = true
    SafeReequipAfterTeleport("AutoRaidAscension")
    _ascInterrupt = false  -- inMap=true sudah aktif, WaitRaidDone cek ASC.inMap langsung
    _ascBusy  = true  -- RAID harus pause total selama ASC aktif (inMap+cooldown)
    _ascMatchedThisCycle = true   -- [v61 CYCLEFIX] ASC sudah match di siklus ini
    _raidFallbackActive  = false  -- [v61 CYCLEFIX] RAID tidak boleh fallback di siklus ini
    _ascPending = false -- [v57 FIX] inMap=true sudah cover, tidak perlu pending lagi
    -- [v52 FIX] Setelah inMap=true di-set, lock tidak diperlukan lagi (IsAnyMapActive sudah cover)
    ReleaseMapLock("asc")

    -- Entry ASC = identik RAID normal, beda hanya mapId dan RUNE_IDS:
    -- RAID: StartChallengeRaidMap({mapId = raidEntry.mapId + 100}) → 50101-50120
    -- ASC : StartChallengeRaidMap({mapId = 50300+mn})              → Tower X = 50301-50326
    -- mapNum sudah di-resolve oleh ResolveAscEntry (termasuk Preferred Map / Rank filter + fallback)
    local targetMapId = ResolveAscTargetMapId(mn)
    local _pm_now = ASC.pickMode or "easy"
    local mn_label = mn
    if _pm_now == "manual" and ASC.manualMatchMode == "primary" then
     mn_label = mn.." [Match]"
    elseif _pm_now == "manual" and ASC.manualMatchMode == "fallback" then
     mn_label = mn.." [Fallback]"
    elseif _pm_now == "manual" and ASC.manualMatchMode == "fallback_easy" then
     mn_label = mn.." [Fallback Easy]"
    elseif _pm_now == "bymap" then
     mn_label = mn.." [ByMap]"
    elseif _pm_now == "byrank" then
     mn_label = mn.." [ByRank]"
    end

    AscStatusUpdate("[~] Enter Tower "..mn_label.."...", Color3.fromRGB(100,200,255))

    -- [v64] ASC RUNE IDS (Preferred Rune / Item) - 26 Tower Ascension
    local ASC_RUNE_IDS = {
     [1]=10265,  -- Baran
     [2]=10266,  -- Baran+1
     [3]=10267,  -- Grendal
     [4]=10268,  -- Grendal+1
     [5]=10269,  -- Plague
     [6]=10314,  -- Plague+1
     [7]=10315,  -- Frostborne
     [8]=10316,  -- Frostborne+1
     [9]=10357,  -- Legia
     [10]=10358, -- Legia+1
     [11]=10359, -- Silas
     [12]=10360, -- Silas+1
     [13]=10361, -- Yogumunt
     [14]=10362, -- Yogumunt+1
     [15]=10363, -- Antares
     [16]=10364, -- Antares+1
     [17]=10365, -- Ashborn
     [18]=10366, -- Ashborn+1
     [19]=10367, -- Dominion
     [20]=10368, -- Dominion+1
     [21]=10369, -- Absolute
     [22]=10370, -- Absolute+1
     [23]=10371, -- Broly
     [24]=10372, -- Broly+1
     [25]=10373, -- Goku Super 4
     [26]=10374, -- Goku Super 4+1
    }

    -- [FIX] LOGIKA KEPUTUSAN (disesuaikan untuk Tower 1-26)
    -- [BUGFIX] Sebelumnya Rune Map dianggap "aktif di semua mode" tanpa syarat --
    -- ini yang menyebabkan Rune Map override paksa masuk ke tower manapun
    -- (rank apapun) begitu ASC.runeEnabled=true, TIDAK PEDULI apakah entry yang
    -- dipilih itu benar2 lolos Preferred Rank atau cuma hasil fallback rank-bebas.
    -- FIX: khusus Pick Mode MANUAL, Rune Map HANYA boleh dieksekusi kalau
    -- ASC.manualMatchMode == "primary" (Preferred Rank BENAR2 match), ATAU
    -- "fallback" TAPI Preferred Rank memang SENGAJA tidak di-set sama sekali
    -- (tidak ada aturan rank untuk dilanggar). Rune TETAP diblok kalau hasilnya
    -- "fallback_easy" (map darurat 1-10 di luar Preferred Map/Rank user) atau
    -- "none". Mode lain (default/byrank/bymap/hard/easy) tidak diubah.
    local useRune = false

    local _hasPreferRankSet = next(ASC.runeGrades or {}) ~= nil
    local _runeAllowedByMode
    if _pm_now == "manual" then
     _runeAllowedByMode = (ASC.manualMatchMode == "primary")
        or (ASC.manualMatchMode == "fallback" and not _hasPreferRankSet)
    else
     _runeAllowedByMode = true -- perilaku lama dipertahankan untuk mode selain manual
    end

    if _runeAllowedByMode and ASC.runeEnabled and ASC.runeMapTarget >= 1 and ASC.runeMapTarget <= 26 then
     -- Anti-mubazir: kalau tower yang akan dimasuki sudah sama dengan target, simpan rune
     if mn == ASC.runeMapTarget then
      useRune = false
     else
      useRune = true
     end
    end

    -- [Auto Item Rune Tower] Fire UseRaidItem sesuai hasil Slot
    -- Manager (max 2 slot, format {slotIndex=N, itemId=ID}) - sama seperti RAID.
    local function AscFireItemSlots(runeItemId)
        if not RE.UseRaidItem then return end
        local fireList = SlotManager_ResolveFireList(ASC, runeItemId)
        for _, entry in ipairs(fireList) do
            AscStatusUpdate("[~] Use Item slot" .. entry.slotIndex .. " (" .. entry.name .. ")...", Color3.fromRGB(200,140,255))
            pcall(function()
                RE.UseRaidItem:FireServer({ slotIndex = entry.slotIndex, itemId = entry.itemId })
            end)
            task.wait(0.3)
        end
        return fireList
    end

    -- [FIX] _displayTower = nomor tower yang BENAR-BENAR dimasuki server saat
    -- ini (target rune kalau useRune aktif, atau mn asli kalau tidak). Dipakai
    -- untuk semua status label SETELAH titik ini supaya tidak nyantol nunjukin
    -- tower asal padahal server sudah override ke tower hasil Rune Tower.
    local _displayTower = mn
    local _displayTowerLabel = mn_label

    -- [v64] EKSEKUSI (identik RAID - hanya RUNE_IDS dan mapId berbeda)
    if useRune then
     -- >>> MODE RUNE TOWER OVERRIDE <<<
     local targetTower = ASC.runeMapTarget
     _displayTower = targetTower
     _displayTowerLabel = tostring(targetTower).." [Rune]"
     AscStatusUpdate("Create Team...", C.ACC2)
     if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(raidEntry.id) end) end
     task.wait(0.2)

     AscStatusUpdate("Use Item (Tower "..targetTower..")...", Color3.fromRGB(255,200,60))
     local itemId = ASC_RUNE_IDS[targetTower]
     -- [FIX] Fire rank + rune sekaligus lewat Slot Manager (slotIndex terkoordinasi)
     AscFireItemSlots(itemId)
     task.wait(0.3)

     local _runeTargetMapId = 50300 + targetTower
     if RE.StartChallengeRaidMap then
      pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = _runeTargetMapId}) end)
     end

     ASC.serverMapId = nil
     local _wR = 0
     while ASC.serverMapId == nil and _wR < 10 and ASC.running do
      task.wait(0.1); _wR = _wR + 0.1
     end

     -- Jika serverMapId nil setelah timeout: material habis atau server reject
     if ASC.serverMapId == nil and ASC.running then
      -- Di Manual mode: JANGAN fallback masuk tower lain. Lapor dan nganggur.
      local _pm_rune = ASC.pickMode or "easy"
      if _pm_rune == "manual" then
       AscStatusUpdate("[!] Material Habis - Nganggur (Manual mode)...", Color3.fromRGB(255,80,80))
       ASC.inMap = false
       _ascBusy = false
       _ascInterrupt = false
       ReleaseMapLock("asc")
       -- Tunggu sampai wakeup event berikutnya (material diisi ulang / event baru)
       local _woken = false
       local _wConn
       if _ascWakeup then
        _wConn = _ascWakeup.Event:Connect(function() _woken = true end)
       end
       local _wt = 0
       while not _woken and _wt < 30 and ASC.running do
        task.wait(1); _wt = _wt + 1
        AscStatusUpdate("[!] Material Habis - Menunggu... ("..tostring(30-_wt).."s)", Color3.fromRGB(255,80,80))
       end
       if _wConn then pcall(function() _wConn:Disconnect() end) end
       break
      else
       -- Mode lain: fallback masuk tower original
       AscStatusUpdate("[!] Item Kosong - Fallback ke Tower "..mn.."...", Color3.fromRGB(255,140,0))
       if RE.CreateRaidTeam then pcall(function() RE.CreateRaidTeam:InvokeServer(raidEntry.id) end) end
       task.wait(0.2)
       if RE.StartChallengeRaidMap then pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = targetMapId}) end) end
       local _wFb = 0
       while ASC.serverMapId == nil and _wFb < 5 and ASC.running do
        task.wait(0.05); _wFb = _wFb + 0.05
       end
      end
     end

    else
     -- >>> MODE NORMAL / FALLBACK <<<
     AscStatusUpdate("[~] Enter Tower "..mn_label.."...", Color3.fromRGB(100,200,255))
     -- Sama persis RAID: CreateRaidTeam(raidId)
     if RE.CreateRaidTeam then
      pcall(function() RE.CreateRaidTeam:InvokeServer(raidEntry.id) end)
     end
     task.wait(0.2)
     if not ASC.running then ASC.inMap = false; break end

     AscFireItemSlots(nil)

     -- Sama persis RAID: StartChallengeRaidMap({mapId=targetMapId})
     local _cfail = false
     local _cfConn
     local _cfRe = Remotes:FindFirstChild("ChallengeRaidsFail")
     if _cfRe then _cfConn = _cfRe.OnClientEvent:Connect(function() _cfail = true end) end

     if RE.StartChallengeRaidMap then
      pcall(function() RE.StartChallengeRaidMap:FireServer({mapId = targetMapId}) end)
     end

     -- [v64 FIX] Tunggu ASC.serverMapId (bukan RAID.serverMapId!) max 5s
     ASC.serverMapId = nil
     local _w2 = 0
     while ASC.serverMapId == nil and _w2 < 5 and ASC.running and not _cfail do
      task.wait(0.05); _w2 = _w2 + 0.05
     end
     if _cfConn then pcall(function() _cfConn:Disconnect() end) end

     if _cfail then
      RAID_LIVE[raidEntry.rawId] = nil
      if raidEntry.rawId ~= raidEntry.id then RAID_LIVE[raidEntry.id] = nil end
      if RebuildRaidList then pcall(RebuildRaidList) end
      ASC.inMap = false; ReleaseMapLock("asc")
      -- [v64 FIX] Jangan biarkan _ascBusy=true saat gagal masuk -> RAID/MA akan stuck pause
      _ascBusy = false
      _ascInterrupt = false  -- [FIX] reset jika gagal masuk
      AscStatusUpdate("[!] Server reject (ChallengeRaidsFail) - retry...", Color3.fromRGB(255,80,80))
      task.wait(1); break
     end
    end

    -- Tunggu masuk Tower (max 10s) - sama persis RAID tapi cek range 50301-50326
    AscStatusUpdate("[~] Waiting Tower ".._displayTowerLabel.."...", Color3.fromRGB(180,100,255))
    local _tpOk = false
    local _tpW  = 0
    while not _tpOk and _tpW < 10 and ASC.running do
     task.wait(0.3); _tpW = _tpW + 0.3
     pcall(function()
      local wm = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or workspace:GetAttribute("CurrentMapId")
      if wm then
       if wm >= 50301 and wm <= 50326 then _tpOk = true end
      end
     end)
     if not _tpOk and #GetRaidEnemies() > 0 then _tpOk = true end
    end

    if not _tpOk and ASC.running then
     RAID_LIVE[raidEntry.rawId] = nil
     if raidEntry.rawId ~= raidEntry.id then RAID_LIVE[raidEntry.id] = nil end
     if RebuildRaidList then pcall(RebuildRaidList) end
     ASC.inMap = false; ReleaseMapLock("asc")
     -- [v64 FIX] Reset _ascBusy agar RAID/MA tidak stuck pause selamanya saat gagal TP
     _ascBusy = false
     _ascInterrupt = false  -- [FIX] reset pada gagal TP
     AscStatusUpdate("[!] Gagal masuk Tower - retry...", Color3.fromRGB(255,80,80))
     task.wait(1); break
    end

    -- Setup event listener boss/done
    local _ascDone = false
    local _ascSuccess = false
    local connAS, connAF
    -- [BUG FIX 1&2] _ascServerDone = server bilang sukses, tapi TIDAK interrupt attack loop.
    -- _ascDone hanya di-set true dari Fail event (batal total) atau setelah attack loop selesai.
    local _ascServerDone = false
    local _reAS = Remotes:FindFirstChild("ChallengeRaidsSuccess")
    local _reAF = Remotes:FindFirstChild("ChallengeRaidsFail")
    if _reAS then connAS = _reAS.OnClientEvent:Connect(function() _ascServerDone = true; _ascSuccess = true end) end
    if _reAF then connAF = _reAF.OnClientEvent:Connect(function() _ascDone = true end) end

    -- STEP 4: Dalam map - equip hero
    if #HERO_GUIDS > 0 then
     task.spawn(function()
      task.wait(0.5)
      if RE.EquipHeroWithData then
       for _, hGuid in ipairs(HERO_GUIDS) do
        pcall(function() RE.EquipHeroWithData:FireServer({ heroGuid = hGuid, userId = MY_USER_ID }) end)
        task.wait(0.1)
       end
      end
      if RE.HeroStand then
       local char = LP.Character
       local hrp = char and char:FindFirstChild("HumanoidRootPart")
       local spawnPos = (hrp and hrp.Position) or Vector3.new(0,0,0)
       pcall(function() RE.HeroStand:FireServer({ userId=MY_USER_ID, standPos=spawnPos }) end)
      end
     end)
    end

    AscStatusUpdate("[~] Dalam Tower ".._displayTower.." - loading...", Color3.fromRGB(100,200,255))

    -- [v64 FIX] Watchdog: reset ASC.inMap + _ascBusy jika player terdeteksi keluar Tower
    -- Ini handle kasus race condition: MA/RAID TP player keluar saat ASC masih "inMap=true"
    -- Tanpa ini: ASC stuck "Dalam Tower... Loading" selamanya karena state tidak pernah direset
    local _watchdogTh = task.spawn(function()
     while ASC.inMap and ASC.running do
      task.wait(1)
      local ok, wm = pcall(function()
       return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or 0
      end)
      if ok and type(wm) == "number" then
       -- Jika player tidak di Ascension Tower range, berarti sudah keluar secara paksa
       if wm > 0 and (wm < 50301 or wm > 50326) then
        -- Jangan langsung reset jika masih di fase loading awal (beri waktu 3s)
        task.wait(3)
        local ok2, wm2 = pcall(function()
         return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or 0
        end)
        if ok2 and type(wm2) == "number" and (wm2 < 50301 or wm2 > 50326) and wm2 > 0 then
         AscStatusUpdate("[!] Watchdog: Player keluar Tower paksa - reset state", Color3.fromRGB(255,80,80))
         ASC.inMap = false
         _ascBusy = false
         _ascInterrupt = false  -- [FIX] reset pada watchdog exit
         ReleaseMapLock("asc")
         break
        end
       end
      end
     end
    end)



    -- [v48] AUTO BOSS KILL - sama persis dengan AUTO RAID
    if ASC.autoKillBoss then
     -- BOSS_KEYS untuk Ascension Tower (semua boss AT + boss normal)
     local BOSS_KEYS_ASC = {
      -- Tower 1-2
      "baran",
      -- Tower 3-4 (nama model asli "Giant Monarch", diverifikasi via sniff - BUKAN "grendal")
      "monarch",
      -- Tower 5-6
      "plague",
      -- Tower 7-8
      "frostborne",
      -- Tower 9-10
      "legia",
      -- Tower 11-12
      "silas",
      -- Tower 13-14
      "yogumunt",
      -- Tower 15-16
      "antares",
      -- Tower 17-18
      "ashborn",
      -- Tower 19-20
      "dominion",
      -- Tower 21-26 (belum rilis - siap update)
     }
     local function IsBossAsc(name)
      local n = name:lower()
      for _, k in ipairs(BOSS_KEYS_ASC) do if n:find(k,1,true) then return true end end
      return false
     end
     -- Prioritaskan nama boss dari entry jika ada
     local _ascHintName = raidEntry.bossName and raidEntry.bossName:lower() or nil
     local function IsBossAscWithHint(name)
      local n = name:lower()
      if _ascHintName and n:find(_ascHintName,1,true) then return true end
      return IsBossAsc(name)
     end

     -- [FIX v50] Tunggu mapId ASC valid sebelum mulai scan boss
     -- Identik pola RAID: snapshot mapId + anchor posisi player diambil SETELAH mapId valid
     -- Tanpa ini: filter mapId di _tryAddBoss terlalu cepat return saat ChildAdded fire
     task.wait(0.3) -- beri server 1 tick untuk update workspace.MapId
     local _ascMapIdSnapshot = GetCurrentMapId()
     local _ascSnapWait = 0
     while (_ascMapIdSnapshot == nil or _ascMapIdSnapshot < 50301 or _ascMapIdSnapshot > 50326)
      and _ascSnapWait < 3 and ASC.running and not _ascDone do
      task.wait(0.3); _ascSnapWait = _ascSnapWait + 0.3
      _ascMapIdSnapshot = GetCurrentMapId()
     end
     -- _ascMapIdFilterActive: hanya aktifkan filter mapId jika snapshot benar-benar valid
     -- Jika server lambat update, filter dimatikan agar boss tidak ditolak salah
     local _ascMapIdFilterActive = _ascMapIdSnapshot ~= nil
      and (_ascMapIdSnapshot >= 50301 and _ascMapIdSnapshot <= 50326)
     -- Anchor posisi player diambil setelah mapId valid
     -- Jika diambil terlalu awal posisi masih di map lama -> semua enemy ditolak karena jarak
     local _ascAnchorPos = GetPlayerPos()
     local _ascAnchorValid = _ascAnchorPos and _ascAnchorPos.Magnitude > 10
     local MAX_DIST_ASC_BOSS = 2000

     -- [FIX v50] Early boss detection ASC - scan agresif semua sumber
     local _earlyBoss = nil
     local _loadWait = 0
     while _loadWait < 5 and ASC.running and not _ascDone do
      task.wait(0.5); _loadWait = _loadWait + 0.5
      if _loadWait >= 1 and not _earlyBoss then
       local _pp = GetPlayerPos()
       -- Sumber 1: GetRaidEnemies()
       local _eList = GetRaidEnemies()
       -- [ADAPT 2.lua] GetEnemiesLocal tidak ada di 2.lua, GetRaidEnemies() sudah cukup + fallback folder scan di bawah
       for _, e in ipairs(_eList) do
        if IsBossAscWithHint(e.model.Name) then
         -- [FIX] Validasi jarak 500 studs - cegah boss dari map lain
         local _hrp = e.model and e.model:FindFirstChild("HumanoidRootPart")
         if _hrp and _pp and _pp.Magnitude > 1 then
          if (_hrp.Position - _pp).Magnitude <= 500 then _earlyBoss = e; break end
         elseif _hrp then
          _earlyBoss = e; break
         end
        end
       end
       -- Sumber 3: scan folder langsung kalau masih belum ketemu
       if not _earlyBoss then
        pcall(function()
         for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
          local f = workspace:FindFirstChild(fname)
          if f then
           for _, obj in ipairs(f:GetChildren()) do
            if obj:IsA("Model") and IsBossAscWithHint(obj.Name) then
             local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("BossGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID")
             local hrp = obj:FindFirstChild("HumanoidRootPart")
             local hum = obj:FindFirstChildOfClass("Humanoid")
             if g and hrp and hum and hum.Health > 0 then
              -- [FIX] Validasi jarak 500 studs - cegah boss dari map lain
              if _pp and _pp.Magnitude > 1 then
               if (hrp.Position - _pp).Magnitude <= 500 then
                _earlyBoss = {guid=g, hrp=hrp, model=obj}; break
               end
              else
               _earlyBoss = {guid=g, hrp=hrp, model=obj}; break
              end
             end
            end
           end
          end
          if _earlyBoss then break end
         end
        end)
       end
      end
      if _earlyBoss then
       local _ep = _earlyBoss.hrp and _earlyBoss.hrp.Parent and _earlyBoss.hrp.Position
       if _ep and _ep.Y > -200 and _ep.Magnitude > 1 and _loadWait >= 1.5 then break end
       if _ep and (_ep.Y <= -200 or _ep.Magnitude <= 1) then _earlyBoss = nil end
      end
     end

     -- [FIX v50] Event-based boss detection - identik dengan RAID
     -- Tambah _bossFoundViaEvent flag + scan existing children tiap folder
     local boss = (_earlyBoss and IsBossAscWithHint(_earlyBoss.model.Name)) and _earlyBoss or nil
     local _bossEventConns = {}
     local _bossFoundViaEvent = false
     local function _tryAddBoss(obj)
      if boss or not obj:IsA("Model") then return end
      if IsBossAscWithHint(obj.Name) then
       -- [FIX v50] Filter mapId toleran: hanya blokir jika filter aktif DAN mapId jelas di luar range
       -- Sebelumnya: hard reject jika mapId nil/belum update -> boss dari ChildAdded diabaikan
       -- Sekarang: jika _ascMapIdFilterActive=false (server belum update), biarkan lolos dulu
       if _ascMapIdFilterActive then
        local _curMap = GetCurrentMapId()
        if _curMap and (_curMap < 50301 or _curMap > 50326) then return end
       end
       local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("BossGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID")
       local hrp = obj:FindFirstChild("HumanoidRootPart")
       local hum = obj:FindFirstChildOfClass("Humanoid")
       if not (g and hrp and hum) then return end
       -- [FIX ZOMBIE] Validasi zombie: health, maxhealth, posisi
       if hum.Health <= 0 then return end
       if hum.MaxHealth <= 0 then return end
       local _ap = hrp.Position
       if _ap.Magnitude <= 10 then return end
       if _ap.Y < -200 or _ap.Y > 1500 then return end
       if not hrp:IsDescendantOf(workspace) then return end
       -- [FIX v50] Gunakan anchor posisi yang sudah divalidasi post-TP (identik pola RAID)
       -- Sebelumnya: GetPlayerPos() on-the-fly, bisa masih transit -> filter jarak tidak akurat
       if _ascAnchorValid then
        if (_ap - _ascAnchorPos).Magnitude > MAX_DIST_ASC_BOSS then return end
       else
        -- Anchor belum valid: fallback ke GetPlayerPos() on-the-fly
        local _pp = GetPlayerPos()
        if _pp and _pp.Magnitude > 1 then
         if (_ap - _pp).Magnitude > MAX_DIST_ASC_BOSS then return end
        end
       end
       boss = {guid=g, hrp=hrp, model=obj}
       _bossFoundViaEvent = true
      end
     end
     -- Pasang ChildAdded di semua folder enemy + scan existing children sekarang
     for _, fname in ipairs({"Bosses","Boss","RaidBoss","Enemys","Enemy","Enemies","RaidEnemys","Monsters","Monster"}) do
      local folder = workspace:FindFirstChild(fname)
      if folder then
       table.insert(_bossEventConns, folder.ChildAdded:Connect(_tryAddBoss))
       -- [FIX] Scan existing children - boss mungkin sudah ada sebelum listener dipasang
       for _, child in ipairs(folder:GetChildren()) do _tryAddBoss(child) end
      end
     end
     -- Listen workspace.ChildAdded untuk folder yang baru muncul
     table.insert(_bossEventConns, workspace.ChildAdded:Connect(function(obj)
      if obj:IsA("Folder") or obj:IsA("Model") then
       _tryAddBoss(obj)
       pcall(function()
        table.insert(_bossEventConns, obj.ChildAdded:Connect(_tryAddBoss))
        for _, child in ipairs(obj:GetChildren()) do _tryAddBoss(child) end
       end)
      end
     end))

     -- [FIX v50] Cari boss - max 5s
     -- [ADAPT 2.lua] Pakai GetRaidEnemies() (GetEnemiesLocal tidak ada di 2.lua)
     local waitBoss = 0
     while ASC.running and not boss and waitBoss < 5 and not _ascDone do
      local _pp = GetPlayerPos()
      -- Coba GetRaidEnemies() dulu
      local _bList = GetRaidEnemies()
      for _, e in ipairs(_bList) do
       if IsBossAscWithHint(e.model.Name) then
        -- [FIX] Validasi jarak 500 studs - cegah boss dari map lain
        local _hrp = e.model and e.model:FindFirstChild("HumanoidRootPart")
        if _hrp and _pp and _pp.Magnitude > 1 then
         if (_hrp.Position - _pp).Magnitude <= 500 then boss = e; break end
        elseif _hrp then
         boss = e; break
        end
       end
      end
      -- Fallback terakhir: scan workspace:GetDescendants() setelah 15s (dead code - waitBoss max 5s)
      if not boss and waitBoss >= 15 and waitBoss % 5 < 0.4 then
       pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
         if obj:IsA("Model") and IsBossAscWithHint(obj.Name) then
          local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("BossGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID")
          local hrp = obj:FindFirstChild("HumanoidRootPart")
          local hum = obj:FindFirstChildOfClass("Humanoid")
          if g and hrp and hum and hum.Health > 0 then
           -- [FIX] Validasi jarak 500 studs - cegah boss dari map lain
           if _pp and _pp.Magnitude > 1 then
            if (hrp.Position - _pp).Magnitude <= 500 then
             boss = {guid=g, hrp=hrp, model=obj}; break
            end
           else
            boss = {guid=g, hrp=hrp, model=obj}; break
           end
          end
         end
        end
       end)
      end
      if not boss then
       AscStatusUpdate("Find Boss... ("..math.floor(waitBoss).."s/5s)", Color3.fromRGB(160,148,135))
       task.wait(0.3); waitBoss = waitBoss + 0.3
      end
     end
     for _, c in ipairs(_bossEventConns) do pcall(function() c:Disconnect() end) end
     _bossEventConns = {}

     -- Helper bossPos yang aman - [v34 FIX] prioritas HumanoidRootPart bukan Head
     local function GetSafeAscBossPos()
      -- [v34 FIX] HumanoidRootPart adalah anchor fisik yang benar untuk TP
      -- Head bisa floating di atas terrain / trigger animasi salah
      local headPart = boss and (
       boss.model:FindFirstChild("HumanoidRootPart")
       or boss.model.PrimaryPart
       or boss.model:FindFirstChild("Head")
      )
      if headPart and headPart.Parent then
       local p = headPart.Position
       -- [FIX ZOMBIE] Tolak: void (Y<-200), langit (Y>1500), posisi default (Magnitude<=10)
       if p.Y > -200 and p.Y < 1500 and p.Magnitude > 10 then return p end
      end
      return nil
     end

     -- [v35] Helper: offset posisi TP agar player tidak menindih HRP boss
     -- Berdiri 3 unit ke samping dari boss -> cegah part boss hilang/terpush physics
     local function _offsetFromBoss(basePos)
      if not basePos then return nil end
      local char = LP.Character
      local pHrp = char and char:FindFirstChild("HumanoidRootPart")
      local dir
      if pHrp then
       local d = (pHrp.Position - basePos)
       local dFlat = Vector3.new(d.X, 0, d.Z)
       dir = dFlat.Magnitude > 0.5 and dFlat.Unit or Vector3.new(1, 0, 0)
      else
       dir = Vector3.new(1, 0, 0)
      end
      return basePos + dir * 3
     end

     if boss and ASC.running and not _ascDone then
      local bossGuid = boss.guid
      local bossPos = GetSafeAscBossPos()
      if not bossPos then
       local _waitPos = 0
       while not bossPos and _waitPos < 3 and ASC.running and not _ascDone do
        task.wait(0.3); _waitPos = _waitPos + 0.3
        bossPos = GetSafeAscBossPos()
       end
      end

      -- [v48] Countdown bossDelay user-controlled (sama dengan RAID)
      local _bd = math.max(1, math.min(10, ASC.bossDelay or 3))
      for _ci = _bd, 1, -1 do
       if not ASC.running or _ascDone then break end
       AscStatusUpdate("[K] Boss: "..boss.model.Name.." - TP ".._ci.."s...", Color3.fromRGB(255,160,60))
       task.wait(1)
      end

      -- Refresh bossPos setelah countdown
      bossPos = GetSafeAscBossPos()
      local _refreshWait = 0
      while not bossPos and _refreshWait < 3 and ASC.running and not _ascDone do
       task.wait(0.3); _refreshWait = _refreshWait + 0.3
       bossPos = GetSafeAscBossPos()
      end

      if ASC.running and not _ascDone and bossPos then
       AscStatusUpdate("[K] Boss: "..boss.model.Name.." - Attack!", Color3.fromRGB(255,80,80))

       -- 1) TP Player ke posisi offset dari boss (3u samping) - cegah part boss hilang
       pcall(function()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local safePos = _offsetFromBoss(GetSafeAscBossPos())
        if hrp and safePos then hrp.CFrame = CFrame.new(safePos) end
       end)

       -- 2) TP semua hero client-side ke posisi offset dari boss
       pcall(function()
        local safePos2 = _offsetFromBoss(GetSafeAscBossPos())
        if not safePos2 then return end
        local heroFolder = workspace:FindFirstChild("Heros")
        if heroFolder then
         for _, hModel in ipairs(heroFolder:GetChildren()) do
          local hHrp = hModel:FindFirstChild("HumanoidRootPart")
          if hHrp then hHrp.CFrame = CFrame.new(safePos2) end
         end
        end
       end)

       -- 3) Fire hero remotes (pakai posisi boss asli untuk server-side damage)
       pcall(function()
        local safePos3 = GetSafeAscBossPos()
        if safePos3 then FireHeroRemotes(bossGuid, safePos3) end
       end)
       if RE.HeroStand and #HERO_GUIDS > 0 then
        local safePos3b = GetSafeAscBossPos()
        if safePos3b then
         for _, hGuid in ipairs(HERO_GUIDS) do
          pcall(function() RE.HeroStand:FireServer({ heroGuid=hGuid, userId=MY_USER_ID, standPos=safePos3b+Vector3.new(1,0,1) }) end)
         end
        end
       end

       -- 4) UnEquip -> EquipBest
       task.wait(0.3)
       if RE.UnEquipHero then pcall(function() RE.UnEquipHero:FireServer() end) end
       task.wait(0.3)
       if RE.EquipBestHero then pcall(function() RE.EquipBestHero:FireServer() end) end
       task.wait(0.3)

       -- 5) TP ulang hero setelah re-equip - offset dari boss
       pcall(function()
        local safePos5 = _offsetFromBoss(GetSafeAscBossPos())
        if not safePos5 then return end
        local heroFolder = workspace:FindFirstChild("Heros")
        if heroFolder then
         for _, hModel in ipairs(heroFolder:GetChildren()) do
          local hHrp = hModel:FindFirstChild("HumanoidRootPart")
          if hHrp then hHrp.CFrame = CFrame.new(safePos5) end
         end
        end
       end)
       pcall(function()
        local safePos5b = GetSafeAscBossPos()
        if safePos5b then FireHeroRemotes(bossGuid, safePos5b) end
       end)

       -- 6) KUNCI posisi player di titik offset dari boss - cegah physics overlap
       local _ascFrozenCFrame = nil
       local _ascFreezeConn = nil
       pcall(function()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local safePos6 = _offsetFromBoss(GetSafeAscBossPos())
        if hrp and safePos6 then
         _ascFrozenCFrame = CFrame.new(safePos6)
         hrp.Anchored = true
         hrp.CFrame = _ascFrozenCFrame
         _ascFreezeConn = RunService.Heartbeat:Connect(function()
          -- [FLa CPU] skip frame ganjil → efektif ~30fps
          if not _ascFreezeFrame then _ascFreezeFrame = 0 end
          _ascFreezeFrame = _ascFreezeFrame + 1
          if _ascFreezeFrame % 2 ~= 0 then return end
          if not ASC.running or _ascDone then
           pcall(function() hrp.Anchored = false end)
           if _ascFreezeConn then _ascFreezeConn:Disconnect(); _ascFreezeConn = nil end
           return
          end
          if hrp and hrp.Parent and _ascFrozenCFrame then
           hrp.CFrame = _ascFrozenCFrame
          end
         end)
        end
       end)

       local function UnfreezeAscPlayer()
        pcall(function()
         local char = LP.Character
         local hrp = char and char:FindFirstChild("HumanoidRootPart")
         if hrp then hrp.Anchored = false end
        end)
        if _ascFreezeConn then _ascFreezeConn:Disconnect(); _ascFreezeConn = nil end
       end

       local _tpTh = nil -- tidak ada background TP thread

       -- [IDENTIK RAID NORMAL] _fireOnce dan _pickRandomGuidNearby untuk ASC
       local _ascTpAnchor = GetSafeAscBossPos() or Vector3.new(0,0,0)
       local ASC_SCAN_RADIUS = 50
       local function _fireOnceAsc(guid)
        if not guid then return end
        if RE.Atk then
         pcall(function() RE.Atk:FireServer({attackEnemyGUID=guid}) end)
        end
        if RE.Click then
         task.spawn(function()
          pcall(function() RE.Click:InvokeServer({enemyGuid=guid}) end)
         end)
        end
       end
       local function _pickRandomGuidNearbyAsc(excludeGuid)
        local pool = {}
        for _, e in ipairs(GetRaidEnemies()) do
         local hum = e.model:FindFirstChildOfClass("Humanoid")
         if hum and hum.Health > 0 and e.hrp and e.hrp.Parent then
          local d = (e.hrp.Position - _ascTpAnchor).Magnitude
          if d <= ASC_SCAN_RADIUS then table.insert(pool, e) end
         end
        end
        if #pool == 0 then return excludeGuid end
        return pool[math.random(1, #pool)].guid
       end
       local function _attackBossAsc(guid)
        -- Tahap 1: RA-style ke guid random dalam radius
        local _raGuid = _pickRandomGuidNearbyAsc(guid)
        _fireOnceAsc(_raGuid)
        -- Tahap 2: TA-style ke guid target boss (locked)
        _fireOnceAsc(guid)
       end

       -- 7) Serang boss (identik RAID Normal - task.wait() no delay)
       local _ascOutOfMapCount = 0
       local _ascAtkStart = tick()
       local ASC_BOSS_TIMEOUT = 240 -- 4 menit
       AscStatusUpdate("[FLa] Attack: "..boss.model.Name, Color3.fromRGB(255,80,80))
       while ASC.running do
        -- Timeout 4 menit
        if tick() - _ascAtkStart >= ASC_BOSS_TIMEOUT then
         AscStatusUpdate("[T] Boss timeout 4min - Dianggap Sukses, keluar...", Color3.fromRGB(255,200,60))
         break
        end
        -- Stop jika server sudah konfirmasi sukses
        if _ascServerDone then break end
        local _curMap = GetCurrentMapId()
        if _curMap and (_curMap < 50301 or _curMap > 50326) then
         _ascOutOfMapCount = _ascOutOfMapCount + 1
         if _ascOutOfMapCount >= 3 then
          AscStatusUpdate("[!] Player keluar Tower - stop attack", Color3.fromRGB(255,140,0))
          break
         end
        else
         _ascOutOfMapCount = 0
        end
        if not boss.model or not boss.model.Parent then break end
        local hum = boss.model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then break end
        if not boss.hrp or not boss.hrp.Parent then
         task.wait()
         if not boss.model or not boss.model.Parent then break end
         local hum2 = boss.model:FindFirstChildOfClass("Humanoid")
         if not hum2 or hum2.Health <= 0 then break end
         continue
        end
        -- Refresh anchor posisi boss
        local _freshPos = GetSafeAscBossPos()
        if _freshPos then _ascTpAnchor = _freshPos end
        pcall(function() _attackBossAsc(bossGuid) end)
        task.wait() -- [identik RAID Normal] no-delay
       end

       pcall(function() task.cancel(_tpTh) end)
       UnfreezeAscPlayer() -- lepas freeze player setelah boss mati
       -- Boss mati. _ascSuccess selalu true setelah attack loop selesai dari dalam tower.
       _ascSuccess = true
       if _ascServerDone then _ascSuccess = true end
       _ascDone = true
       AscStatusUpdate("[FLa] Boss Dead!", Color3.fromRGB(100,255,150))
      end -- if bossPos
     else
      -- Boss tidak ditemukan setelah 30s - last chance scan
      if not boss then
       pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
         if obj:IsA("Model") and IsBossAscWithHint(obj.Name) then
          local g = obj:GetAttribute("EnemyGuid") or obj:GetAttribute("BossGuid") or obj:GetAttribute("Guid") or obj:GetAttribute("GUID")
          local hrp = obj:FindFirstChild("HumanoidRootPart")
          local hum = obj:FindFirstChildOfClass("Humanoid")
          if g and hrp and hum and hum.Health > 0 then
           boss = {guid=g, hrp=hrp, model=obj}; break
          end
         end
        end
       end)
      end
      if not boss and ASC.running then
       AscStatusUpdate("[FLa] Boss not found (30s) - Go Out...", Color3.fromRGB(255,150,50))
       task.wait(3)
      end
     end
    else
     -- Auto Kill Boss OFF - tunggu event ChallengeRaidsSuccess max 5 menit
     local _wt = 0
     while ASC.running and not _ascDone and _wt < 300 do
      task.wait(1); _wt = _wt + 1
      -- [v64 FIX] Guard keluar Tower: cek lebih komprehensif
      -- Jika player sudah tidak di Ascension Tower (50301-50326), berarti sudah keluar
      -- (bisa karena MA/RAID TP player keluar, atau server kick, atau kolisi event)
      local wm = workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or 0
      if wm == 0 or (wm >= 50001 and wm <= 50028) then
       AscStatusUpdate("[!] Player keluar Tower (ext) - abort wait", Color3.fromRGB(255,140,0))
       break
      end
      -- Jika player tiba-tiba di map RAID normal atau Siege, juga keluar
      if (wm >= 50101 and wm <= 50120) or (wm >= 50201 and wm <= 50204) then
       AscStatusUpdate("[!] Player di map lain - abort wait", Color3.fromRGB(255,140,0))
       break
      end
     end
    end

    if connAS then pcall(function() connAS:Disconnect() end) end
    if connAF then pcall(function() connAF:Disconnect() end) end
    -- [v64 FIX] Cancel watchdog setelah keluar Tower normal
    if _watchdogTh then pcall(function() task.cancel(_watchdogTh) end) end

    if _ascSuccess then
     ASC.sukses = ASC.sukses + 1
     AscCounterUpdate()
     AscStatusUpdate("[OK] Sukses-"..ASC.sukses.." Tower ".._displayTower, Color3.fromRGB(100,255,150))
    end
    if not ASC.running then break end

    -- Wait reward
    if _ascSuccess then
     AscStatusUpdate("[..] Wait 1s (Get reward)...", Color3.fromRGB(100,255,150))
     task.wait(1)
    end
    if not ASC.running then break end

    -- STEP 5: Collect + Exit Tower
    task.spawn(function() pcall(RaidCollectAll) end)
    AscStatusUpdate("[FLa] Go Out Tower...", Color3.fromRGB(100,200,255))

    RAID_LIVE[raidEntry.rawId] = nil
    if raidEntry.rawId ~= raidEntry.id then RAID_LIVE[raidEntry.id] = nil end
    if RebuildRaidList then pcall(RebuildRaidList) end

    -- [v11 EDIT] Keluar dari Ascension Tower -> kembali ke MAP TERAKHIR player
    -- berada (bukan selalu Map 1). Sumber: MR.lastMapId (map terakhir Mass
    -- Attack TP ke sana), fallback Map 1 (50001) kalau kosong / di luar range
    -- basemap normal (50001-50020). ASC tidak punya tracking "fromMapId" dari
    -- server seperti RAID, jadi MR.lastMapId satu-satunya sumber selain default.
    local _ascToMapId = 50001
    do
        local _cand = MR and MR.lastMapId or nil
        if _cand and _cand >= 50001 and _cand <= 50021 then
            _ascToMapId = _cand
        end
    end
    local _exitRe = Remotes:FindFirstChild("QuitRaidsMap")
    if _exitRe then
     pcall(function() _exitRe:FireServer({ currentSlotIndex = 2, toMapId = _ascToMapId }) end)
    end
    task.wait(0.3)
    -- [v11 EDIT] Selalu pakai remote StartLocalPlayerTeleport (RE.StartTp)
    pcall(function() RE.StartTp:FireServer({ mapId = _ascToMapId }) end)
    -- Retry exit jika masih di Ascension Tower
    local _exitTry = 0
    local function _inAscArea()
     local ok, wm = pcall(function()
      return workspace:GetAttribute("MapId") or workspace:GetAttribute("mapId") or 0
     end)
     return (ok and wm >= 50301 and wm <= 50326)
    end
    while _inAscArea() and _exitTry < 5 and ASC.running do
     _exitTry = _exitTry + 1
     task.wait(1)
     if _exitRe then pcall(function() _exitRe:FireServer({ currentSlotIndex=2, toMapId=_ascToMapId }) end) end
     task.wait(0.2)
     pcall(function() RE.StartTp:FireServer({ mapId=_ascToMapId }) end)
    end

    ASC.inMap = false
    ASC.serverMapId = nil -- [v64 FIX] Reset agar run berikutnya tidak pakai data stale
    ReleaseMapLock("asc") -- [v52 FIX] Pastikan lock selalu dilepas saat keluar map
    -- [v62 FIX] Reset status agar tidak nyantol di "Dalam Tower x" saat sudah di Lobby
    AscStatusUpdate("[>>] Keluar Tower - cooldown...", Color3.fromRGB(160,148,135))
    for cd = 14, 1, -1 do
     if not ASC.running then break end
     AscStatusUpdate("[..] Cooldown "..cd.."s...", Color3.fromRGB(160,148,135))
     if ASC.dot then ASC.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
     task.wait(1)
    end

    -- [v48] STEP 7: Standby loop setelah cooldown (sama dengan RAID)
    if ASC.running then
     AscStatusUpdate("[>>] Waiting & Cooldown...", Color3.fromRGB(100,255,150))
     if ASC.dot then ASC.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
     local _fw = 0
     while ASC.running do
      -- Cek busy (Siege / Dungeon)
      local isBusy = false
      if (SIEGE and (SIEGE.inMap or SIEGE.teleporting)) then isBusy = true end
      local _wm2 = workspace:GetAttribute("MapId") or 0
      if (_wm2 >= 50201 and _wm2 <= 50204) then isBusy = true end

      -- ASC cooldown loop tidak perlu reset flag ini lagi
      -- RAID sekarang independen: jalan saat ASC.inMap = false, pause saat ASC.inMap = true

      if isBusy then
       AscStatusUpdate("[!] PAUSE: Menunggu Siege/Dungeon Selesai...", Color3.fromRGB(255,100,100))
      else
       local nextEntry = ResolveAscEntry()
       if nextEntry then
        -- [FIX] Jangan set _ascBusy di sini -> MA bebas jalan selama cooldown
        -- _ascBusy di-set nanti saat ASC benar-benar masuk tower (setelah _ascInterrupt)
        -- Tapi RAID tetap perlu pause -> set _ascBusy agar RAID tidak rebutan masuk
        _ascBusy = true  -- RAID pause (tapi MA boleh jalan, MA cek ASC.inMap/_ascInterrupt)
        break
       end
       -- Tidak ada Tower yang cocok
       if #RAID_ID_LIST == 0 then
        -- Event habis total -> RAID boleh jalan, reset cycle flag
        _ascBusy = false
        _ascMatchedThisCycle = false  -- [v61 CYCLEFIX] siklus habis, reset
        _raidFallbackActive  = false
        _eventOwner = nil             -- [v62] reset penentu siapa yang dipanggil
        AscStatusUpdate("[>>] Menunggu event RAID baru dari server...", Color3.fromRGB(120,120,120))
       elseif #GetAscensionList() > 0 then
        -- Ada Ascension tapi tidak cocok filter (grade/map)
        -- [v61 CYCLEFIX] Jika ASC pernah match di siklus ini, pertahankan _ascBusy
        -- sampai siklus event benar-benar habis (RAID_LIVE kosong)
        if _ascMatchedThisCycle then
         _ascBusy = true  -- siklus ASC belum selesai, RAID tetap pause
         AscStatusUpdate("[||] ASC cycle aktif - RAID standby sampai event habis (".._fw.."s)", Color3.fromRGB(180,100,255))
        else
         AscStatusUpdate("[FLa] Waiting grade filter... (".._fw.."s)", Color3.fromRGB(200,255,150))
        end
       else
        -- Tidak ada Ascension, tapi masih ada Raid Normal di event ini
        -- [v61 CYCLEFIX] Jika ASC sudah dominasi siklus ini (pernah match),
        -- pertahankan _ascBusy sampai RAID_LIVE kosong (siklus habis)
        if _ascMatchedThisCycle then
         _ascBusy = true  -- siklus ASC belum habis, RAID tetap pause
         AscStatusUpdate("[||] Menunggu siklus event habis - RAID standby (".._fw.."s)", Color3.fromRGB(180,100,255))
        else
         -- ASC tidak pernah match di siklus ini -> lepas _ascBusy, RAID boleh fallback
         _ascBusy = false
         _raidFallbackActive = true   -- [v61 CYCLEFIX] tandai RAID sedang fallback
         _eventOwner = "raid"         -- [v62] giliran RAID di siklus ini
         if RAID.running then
          AscStatusUpdate("[Standby] Fallback ke Auto Raid (".._fw.."s)", Color3.fromRGB(140,100,200))
         else
          -- RAID OFF -> diam saja sampai event baru
          AscStatusUpdate("[FLa] Waiting Ascension Tower... (".._fw.."s)", Color3.fromRGB(160,120,60))
         end
        end
       end
      end
      -- Wakeup cepat
      local _woken2 = false
      local _wConn2
      if _ascWakeup then
       _wConn2 = _ascWakeup.Event:Connect(function() _woken2 = true end)
      end
      local _we2 = 0
      while not _woken2 and _we2 < 1 and ASC.running do
       task.wait(0.1); _we2 = _we2 + 0.1
      end
      if _wConn2 then pcall(function() _wConn2:Disconnect() end) end
      _fw = _fw + 1
     end
    end

   until true
  end -- while ASC.running
  end) -- pcall

  -- [v63 FIX] Cleanup dijamin jalan meskipun pcall catch error di dalam loop
  ASC.running = false
  ASC.inMap   = false
  _ascBusy    = false
  _ascInterrupt = false  -- [FIX] reset cleanup
  _ascOn      = false
  _ascDominatedThisEvent = false -- [v56 DEPRECATED] tidak dipakai lagi
  _ascMatchedThisCycle  = false  -- [v61 CYCLEFIX] reset saat ASC stop
  _raidFallbackActive   = false  -- [v61 CYCLEFIX] reset saat ASC stop
  ASC._rrIdx  = 0
  AscStatusUpdate("Auto Ascension STOP", Color3.fromRGB(160,148,135))
  if ASC.dot then ASC.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
 end)
end


-- ============================================================================
-- PANEL: AUTOMATION - AUTO RAID UI (WindUI Section accordion, identik 1.lua)
-- ============================================================================
do

-- Variabel state untuk Section collapse (slide up/down)
-- WindUI Section built-in sudah support collapse, tapi untuk full control
-- kita buat Section manual dengan callback seperti 1.lua (raidOpen/raidBody)

--  Warna grade untuk dropdown 
local GRADE_COLORS_UI = {
    ["E"]=Color3.fromRGB(150,150,150),["D"]=Color3.fromRGB(100,200,100),
    ["C"]=Color3.fromRGB(80,200,120),["B"]=Color3.fromRGB(100,140,255),
    ["A"]=Color3.fromRGB(180,100,255),["S"]=Color3.fromRGB(255,180,50),
    ["SS"]=Color3.fromRGB(255,220,0),["G"]=Color3.fromRGB(255,60,60),
    ["N"]=Color3.fromRGB(255,100,200),["M"]=Color3.fromRGB(255,0,0),
    ["M+"]=Color3.fromRGB(255,50,50),["M++"]=Color3.fromRGB(255,100,100),
    ["XM"]=Color3.fromRGB(180,0,0),["ULT"]=Color3.fromRGB(255,255,255),
}

--  PM (Pick Mode) config 
local PM_OPTS  = {"Default","By Rank","By Map","Hard","Easy","Manual"}
local PM_KEYS  = {"default","byrank","bymap","hard","easy","manual"}
local PM_TO_DIFF = {default="easy",byrank="easy",bymap="easy",hard="hard",easy="easy",manual="easy"}
local PM_UNLOCK = {
    -- map=Preferred Maps, rank=Preferred Rank, rune=Auto Item(Rune Map), list=Raid List Entry
    default={map=false,rank=false,rune=false,list=false},
    byrank ={map=false,rank=true, rune=false,list=false},
    bymap  ={map=true, rank=false,rune=false,list=false},
    hard   ={map=false,rank=false,rune=false,list=false},
    easy   ={map=false,rank=false,rune=false,list=false},
    manual ={map=true, rank=true, rune=true, list=true },
}

--  WindUI Section: AUTO RAID (slide up/down) 
-- WindUI Tab:Section() sudah punya built-in collapse behavior (klik header = toggle)
-- Kita daftarkan semua elemen di dalam section yang sama

local raidSection = AutomationTab:Section({ Title = "Auto Raid", Icon = "sword", Opened = false, Box = true })

-- Status paragraph
local raidStatusPara = raidSection:Paragraph({
    Title = "Status",
    Desc  = "Disabled",
})
-- Expose ke RAID.statusLbl via wrapper (WindUI Paragraph tidak punya .Text property langsung)
-- Kita buat proxy: simpan ref ke Paragraph dan gunakan :Set()
local _raidStatusParaRef = raidStatusPara
RAID.statusLbl = {
    Text = "Disabled",
    TextColor3 = Color3.fromRGB(160,148,135),
}
-- Override RaidStatusUpdate agar update Paragraph WindUI
local _origRaidStatusUpdate = RaidStatusUpdate
RaidStatusUpdate = function(msg, color)
    if _raidStatusParaRef then
        pcall(function() _raidStatusParaRef:SetDesc(msg) end)
    end
    RAID.statusLbl.Text = msg
    RAID.statusLbl.TextColor3 = color or Color3.fromRGB(255,210,160)
end

-- Active Raid paragraph
local raidActivePara = raidSection:Paragraph({
    Title = "Active Raid",
    Desc  = "Waiting",
})
RAID.activeRaidLbl = {
    Text = "Waiting",
    TextColor3 = Color3.fromRGB(160,160,160),
}
local function UpdateActiveRaidLabel()
    pcall(function()
        if RAID.inMap and RAID.raidMapId then
            local rawMn = RAID.raidMapId - 50000
            local mn = RAID.serverMapId and (RAID.serverMapId - 50100) or rawMn
            local nm = MAP_NAMES and MAP_NAMES[mn] or ("Map "..tostring(mn))
            local grade = (_runeGradeCache and _runeGradeCache[mn]) or ""
            local gs = grade ~= "" and grade ~= "?" and (" ["..grade.."]") or ""
            local txt = "Map "..mn.." - "..nm..gs
            if _raidStatusParaRef then pcall(function() raidActivePara:SetDesc(txt) end) end
            RAID.activeRaidLbl.Text = txt
        else
            pcall(function() raidActivePara:SetDesc("Waiting") end)
            RAID.activeRaidLbl.Text = "Waiting"
        end
    end)
end
RAID.updateActiveLabel = UpdateActiveRaidLabel
-- [FIXED zombie] _raidReconnectAlive dijadikan flag bersama untuk loop-loop
-- tingkat atas yang seharusnya hidup sepanjang lifecycle script
task.spawn(function() while _raidReconnectAlive do task.wait(0.3); UpdateActiveRaidLabel() end end)

-- Raid Completed paragraph
local raidCompletedPara = raidSection:Paragraph({
    Title = "Raid Completed",
    Desc  = "0",
})
RAID.suksesLbl = {
    Text = "0",
    Parent = true, -- dummy agar RaidCounterUpdate tidak crash
}
local _origRaidCounterUpdate = RaidCounterUpdate
RaidCounterUpdate = function()
    RAID.suksesLbl.Text = tostring(RAID.sukses)
    pcall(function() raidCompletedPara:SetDesc(tostring(RAID.sukses)) end)
end

--  Enable Auto Raid Toggle 
local raidEnableToggle = raidSection:Toggle({
    Flag     = "raidEnable",
    Title    = "Enable Auto Raid",
    Desc     = "Aktifkan/matikan loop Auto Raid",
    Default  = false,
    Callback = function(on)
        _raidOn = on
        if on then StartRaidLoop()
        else StopRaid(); RaidStatusUpdate("Disabled", Color3.fromRGB(160,148,135)) end
    end,
})
_setRaidToggle = function(on)
    if on == _raidOn then return end
    _raidOn = on
    pcall(function() raidEnableToggle:Set(on, false) end)
    if on then StartRaidLoop()
    else StopRaid(); RaidStatusUpdate("Disabled", Color3.fromRGB(160,148,135)) end
end
-- Visual-only setter tanpa guard (untuk Config restore)
_visRaidToggle = function(on)
    pcall(function() raidEnableToggle:Set(on, false) end)
end

--  PICK MODE 
local curPM = 1
RAID.pickMode = PM_KEYS[curPM]

local raidPickModeDD = raidSection:Dropdown({
    Flag     = "raidPickMode",
    Title    = "Pick Mode",
    Desc     = "Pilih strategi pemilihan raid",
    Multi    = false,
    Value    = PM_OPTS[curPM],
    Values   = PM_OPTS,
    Callback = function(val)
        for i, opt in ipairs(PM_OPTS) do
            if opt == val then
                curPM = i
                RAID.pickMode = PM_KEYS[i]
                RAID.difficulty = PM_TO_DIFF[PM_KEYS[i]]
                RAID.snapshotMapId = nil
                if _applyPickModeLock then _applyPickModeLock(PM_KEYS[i]) end
                break
            end
        end
    end,
})
_setRaidPMIdx = function(ii)
    if ii < 1 or ii > #PM_KEYS then return end
    curPM = ii; RAID.pickMode = PM_KEYS[ii]
    RAID.difficulty = PM_TO_DIFF[PM_KEYS[ii]]; RAID.snapshotMapId = nil
    pcall(function() raidPickModeDD:Select(PM_OPTS[ii]) end)
    if _applyPickModeLock then _applyPickModeLock(PM_KEYS[ii]) end
end

--  PREFERRED MAPS
-- Default: KOSONG (tidak ada map terpilih = masuk semua map)
-- JANGAN pre-fill semua map - user tidak bisa unselect di WindUI multi dropdown kalau semua dipilih

local _mapOptNames = {"-- NOT SELECTED --"}
for i = 1, 21 do table.insert(_mapOptNames, "Map "..i) end
local _mapInitVal = {}
for i = 1, 21 do if RAID.preferMaps[i] then table.insert(_mapInitVal, "Map "..i) end end
if #_mapInitVal == 0 then _mapInitVal = {"-- NOT SELECTED --"} end

local raidPrefMapDD = raidSection:Dropdown({
    Flag     = "raidPrefMaps",
    Title    = "Preferred Maps",
    Desc     = "Pilih map yang ingin dimasuki (kosong = semua)",
    Multi    = true,
    Value    = _mapInitVal,
    Values   = _mapOptNames,
    Callback = function(val)
        for mn = 1, 21 do RAID.preferMaps[mn] = nil end
        if type(val) == "table" then
            -- Jika user pilih NOT SELECTED, clear semua dan reset visual
            local hasNotSel = false
            for _, v in ipairs(val) do
                if v == "-- NOT SELECTED --" then hasNotSel = true; break end
            end
            if hasNotSel then
                pcall(function() raidPrefMapDD:Select({"-- NOT SELECTED --"}) end)
                return
            end
            for _, v in ipairs(val) do
                local mi = tonumber(v:match("Map (%d+)"))
                if mi then RAID.preferMaps[mi] = true end
            end
        end
    end,
})
local function UpdatePrefLabel()
    local n = 0; local ns = {}
    for mn in pairs(RAID.preferMaps) do n=n+1; table.insert(ns,"Map "..mn) end
    table.sort(ns)
    if n == 0 then
        pcall(function() raidPrefMapDD:Select({"-- NOT SELECTED --"}) end)
    else
        pcall(function() raidPrefMapDD:Select(ns) end)
    end
end
_raidUpdatePrefLabel = UpdatePrefLabel

--  PREFERRED RANK 
local _rankInitVal = {}
for _, g in ipairs(GRADE_LIST) do
    if RAID.runeGrades[g] then table.insert(_rankInitVal, g) end
end

local _rankOptNames = {"-- NOT SELECTED --"}
for _, g in ipairs(GRADE_LIST) do table.insert(_rankOptNames, g) end
if #_rankInitVal == 0 then _rankInitVal = {"-- NOT SELECTED --"} end

local raidRankDD = raidSection:Dropdown({
    Flag     = "raidRank",
    Title    = "Preferred Rank",
    Desc     = "Filter rank raid yang ingin dimasuki",
    Multi    = true,
    Value    = _rankInitVal,
    Values   = _rankOptNames,
    Callback = function(val)
        for _, g in ipairs(GRADE_LIST) do RAID.runeGrades[g] = nil end
        if type(val) == "table" then
            -- Jika user pilih NOT SELECTED, clear semua dan reset visual
            local hasNotSel = false
            for _, v in ipairs(val) do
                if v == "-- NOT SELECTED --" then hasNotSel = true; break end
            end
            if hasNotSel then
                pcall(function() raidRankDD:Select({"-- NOT SELECTED --"}) end)
                if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
                return
            end
            for _, v in ipairs(val) do
                if GRADE_RANK[v] then RAID.runeGrades[v] = true end
            end
        end
        if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
    end,
})
local function RefreshRankDDLabel()
    local ns = {}
    for _, g in ipairs(GRADE_LIST) do
        if RAID.runeGrades[g] then table.insert(ns, g) end
    end
    if #ns == 0 then
        pcall(function() raidRankDD:Select({"-- NOT SELECTED --"}) end)
    else
        pcall(function() raidRankDD:Select(ns) end)
    end
end
_raidUpdateRankLabel = RefreshRankDDLabel

--  PREFERRED RUNE (Auto Item) 
local _runeOptNames = {"-- NOT SELECTED --"}
for mn = 1, 21 do
    table.insert(_runeOptNames, "Map "..mn.." - "..(MAP_NAMES[mn] or "Map "..mn))
end

local _runeInitVal = nil
if RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 21 then
    _runeInitVal = "Map "..RAID.runeMapTarget.." - "..(MAP_NAMES[RAID.runeMapTarget] or "Map "..RAID.runeMapTarget)
end

local raidRuneDD = raidSection:Dropdown({
    Flag     = "raidRune",
    Title    = "Auto Item (Rune Map)",
    Desc     = "Pilih map target item rune (opsional)",
    Multi    = false,
    Value    = _runeInitVal,
    Values   = _runeOptNames,
    Callback = function(val)
        if not val or val == "-- NOT SELECTED --" then
            RAID.runeMapTarget = 0; RAID.runeEnabled = false
        else
            local mi = tonumber(val:match("Map (%d+)"))
            if mi and mi >= 1 and mi <= 21 then
                RAID.runeMapTarget = mi; RAID.runeEnabled = true
            end
        end
    end,
})
local function SyncRuneState()
    if RAID.runeMapTarget >= 1 and RAID.runeMapTarget <= 21 then RAID.runeEnabled = true
    else RAID.runeEnabled = false end
end
_syncRaidRuneState = SyncRuneState
_setRaidRuneMapTarget = function(ml)
    RAID.runeMapTarget = ml or 0; SyncRuneState()
    if ml and ml >= 1 and ml <= 21 then
        local txt = "Map "..ml.." - "..(MAP_NAMES[ml] or "Map "..ml)
        pcall(function() raidRuneDD:Select(txt) end)
    else
        pcall(function() raidRuneDD:Select("-- NOT SELECTED --") end)
    end
end

--  AUTO KILL BOSS 
local raidBossToggle = raidSection:Toggle({
    Flag     = "raidBoss",
    Title    = "AUTO KILL BOSS",
    Desc     = "Teleport ke boss dan auto attack sampai mati",
    Default  = RAID.autoKillBoss or false,
    Callback = function(on)
        RAID.autoKillBoss = on
    end,
})
_raidBossToggleVis = function(on)
    RAID.autoKillBoss = on
    pcall(function() raidBossToggle:Set(on, false) end)
end

--  TELEPORT DELAY SLIDER 
local raidBossDelaySlider = raidSection:Slider({
    Flag     = "raidBossDelay",
    Title    = "Teleport Delay (s)",
    Desc     = "Delay sebelum teleport ke boss (1-10 detik)",
    Value    = { Min = 1, Max = 10, Default = RAID.bossDelay or 3 },
    Step     = 1,
    Callback = function(val)
        RAID.bossDelay = math.clamp(math.floor(val + 0.5), 1, 10)
    end,
})
_raidBossDelaySet = function(val)
    RAID.bossDelay = math.clamp(math.round(val), 1, 10)
    pcall(function() raidBossDelaySlider:Set(RAID.bossDelay) end)
end

--  RAID LIST ENTRY 
local raidListSection = raidSection:Section({ Title = "Raid List Entry", Icon = "list", Opened = false, Box = true })

local raidListToggle = raidListSection:Toggle({
    Flag     = "raidListEnabled",
    Title    = "List Entry",
    Desc     = "Aktifkan sistem antrian entry map+rank",
    Default  = RAID.listEnabled or false,
    Callback = function(on)
        RAID.listEnabled = on
        if _raidWakeup then pcall(function() _raidWakeup:Fire() end) end
    end,
})
_setRaidListEnabledVis = function(on)
    RAID.listEnabled = on
    pcall(function() raidListToggle:Set(on, false) end)
end

-- Save Entry button: snapshot maps + rank sekarang ke list
local raidListSaveBtn = raidListSection:Button({
    Title    = "+ Save Entry",
    Desc     = "Simpan kombinasi map+rank sekarang ke list",
    Callback = function()
        local snapMaps = {}; for mn,v in pairs(RAID.preferMaps) do snapMaps[mn]=v end
        local snapRanks = {}; for g,v in pairs(RAID.runeGrades) do snapRanks[g]=v end
        table.insert(RAID.listEntries, {maps=snapMaps, ranks=snapRanks})
        -- Rebuild display
        if _raidRebuildListRows then _raidRebuildListRows() end
    end,
})

-- Entry list paragraph (tampilkan daftar entry)
local _raidListPara = raidListSection:Paragraph({
    Title = "Saved Entries",
    Desc  = "(kosong)",
})
local function RebuildListDisplay()
    if #RAID.listEntries == 0 then
        pcall(function() _raidListPara:SetDesc("(kosong)") end)
        return
    end
    local lines = {}
    for i, ent in ipairs(RAID.listEntries) do
        local mapsStr
        if not next(ent.maps) then mapsStr = "All Maps"
        else
            local ms = {}; for mn in pairs(ent.maps) do table.insert(ms,mn) end
            table.sort(ms); local parts = {}
            for _, mn in ipairs(ms) do table.insert(parts, "M"..mn) end
            mapsStr = table.concat(parts,",")
        end
        local ranksStr
        if not next(ent.ranks) then ranksStr = "All"
        else
            local rs = {}
            for _, g in ipairs(GRADE_LIST) do if ent.ranks[g] then table.insert(rs,g) end end
            ranksStr = table.concat(rs,"/")
        end
        table.insert(lines, "#"..i.." "..mapsStr.." | "..ranksStr)
    end
    pcall(function() _raidListPara:SetDesc(table.concat(lines,"\n")) end)
end
_raidRebuildListRows = RebuildListDisplay

-- Tombol hapus entry terakhir
local raidListDeleteBtn = raidListSection:Button({
    Title    = "- Hapus Entry Terakhir",
    Desc     = "Hapus entry paling bawah dari list",
    Callback = function()
        if #RAID.listEntries > 0 then
            table.remove(RAID.listEntries)
            RebuildListDisplay()
        end
    end,
})

--  APPLY PICK MODE LOCK 
-- Dipanggil saat Pick Mode berubah.
-- Lock = clear data + reset UI ke NOT SELECTED + update Desc sebagai indikator visual.
-- WindUI tidak punya :SetEnabled() native, jadi kita gunakan flag guard + Desc label.

local function _doApplyLock(pm)
    local u = PM_UNLOCK[pm] or {map=false,rank=false,rune=false,list=false}
    local lockMsg = "Tidak tersedia di mode " .. pm

    -- Preferred Maps
    _prefLocked = not u.map
    if _prefLocked then
        for k in pairs(RAID.preferMaps) do RAID.preferMaps[k] = nil end
        pcall(function() raidPrefMapDD:Select({}) end)
        pcall(function() raidPrefMapDD:Lock(lockMsg) end)
    else
        pcall(function() raidPrefMapDD:Unlock() end)
    end

    -- Preferred Rank
    _rankLocked = not u.rank
    if _rankLocked then
        for _, g in ipairs(GRADE_LIST) do RAID.runeGrades[g] = nil end
        pcall(function() raidRankDD:Select({}) end)
        pcall(function() raidRankDD:Lock(lockMsg) end)
    else
        pcall(function() raidRankDD:Unlock() end)
    end

    -- Auto Item (Rune)
    _runeLocked = not u.rune
    if _runeLocked then
        RAID.runeMapTarget = 0; RAID.runeEnabled = false
        pcall(function() raidRuneDD:Select("-- NOT SELECTED --") end)
        pcall(function() raidRuneDD:Lock(lockMsg) end)
    else
        pcall(function() raidRuneDD:Unlock() end)
    end

    -- Raid List Entry
    _listLocked = not u.list
    if _listLocked then
        RAID.listEnabled = false
        pcall(function() raidListToggle:Set(false, false) end)
        pcall(function() raidListToggle:Lock(lockMsg) end)
        pcall(function() raidListSaveBtn:Lock(lockMsg) end)
        pcall(function() raidListDeleteBtn:Lock(lockMsg) end)
    else
        pcall(function() raidListToggle:Unlock() end)
        pcall(function() raidListSaveBtn:Unlock() end)
        pcall(function() raidListDeleteBtn:Unlock() end)
    end
end

_applyPickModeLock = _doApplyLock

-- Inisialisasi flag lock sesuai pickMode awal
_prefLocked   = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).map
_rankLocked   = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).rank
_runeLocked   = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).rune
_listLocked   = not (PM_UNLOCK[RAID.pickMode or "default"] or {}).list

-- Apply lock saat script load (defer agar semua elemen sudah terdaftar ke WindUI)
task.defer(function() _doApplyLock(RAID.pickMode or "default") end)

RebuildListDisplay()

end -- end do: AUTO RAID UI


-- ============================================================================
-- PANEL: AUTOMATION - AUTO RAID ASCENSION UI (WindUI Section accordion)
-- Port dari 1.lua baris 14700-15506 ke WindUI, mengikuti pattern raidSection
-- Ditaruh DI BAWAH Auto Raid (AutomationTab:Section sendiri, slide up/down
-- bawaan WindUI Section), independen dari RAID Normal (sesuai keputusan)
-- ============================================================================
do

local ascSection = AutomationTab:Section({ Title = "Auto Raid Ascension", Icon = "swords", Opened = false, Box = true })

--  STATUS 
local ascStatusPara = ascSection:Paragraph({
    Title = "Status",
    Desc  = "Disabled",
})
ASC.statusLbl = {
    Text = "Disabled",
    TextColor3 = Color3.fromRGB(160,148,135),
}
local _origAscStatusUpdate = AscStatusUpdate
AscStatusUpdate = function(msg, color)
    pcall(function() ascStatusPara:SetDesc(msg) end)
    ASC.statusLbl.Text = msg
    ASC.statusLbl.TextColor3 = color or Color3.fromRGB(255,200,100)
end

--  ASCENSION COMPLETED 
local ascCompletedPara = ascSection:Paragraph({
    Title = "Ascension Completed",
    Desc  = "0",
})
ASC.suksesLbl = {
    Text = "0",
}
local _origAscCounterUpdate = AscCounterUpdate
AscCounterUpdate = function()
    ASC.suksesLbl.Text = tostring(ASC.sukses)
    pcall(function() ascCompletedPara:SetDesc(tostring(ASC.sukses)) end)
end

--  ENABLE AUTO ASCENSION TOGGLE 
local ascEnableToggle = ascSection:Toggle({
    Flag     = "ascEnable",
    Title    = "Enable Auto Ascension",
    Desc     = "Aktifkan/matikan loop Auto Raid Ascension",
    Default  = false,
    Callback = function(on)
        _ascOn = on
        if on then StartAscensionLoop()
        else StopAscension(); AscStatusUpdate("Disabled", Color3.fromRGB(160,148,135)) end
    end,
})
_setAscToggle = function(on)
    if on == _ascOn then return end
    _ascOn = on
    pcall(function() ascEnableToggle:Set(on, false) end)
    if on then StartAscensionLoop()
    else StopAscension(); AscStatusUpdate("Disabled", Color3.fromRGB(160,148,135)) end
end
-- Visual-only setter tanpa guard (untuk Config restore)
_visAscToggle = function(on)
    pcall(function() ascEnableToggle:Set(on, false) end)
end

--  PICK MODE 
local APM_OPTS   = {"Default","By Rank","By Map","Hard","Easy","Manual"}
local APM_KEYS   = {"default","byrank","bymap","hard","easy","manual"}
local APM_TO_DESC = {
    default = "Join Tower apapun tanpa filter",
    byrank  = "Filter by Preferred Rank",
    bymap   = "Filter by Preferred Map",
    hard    = "Selalu pilih Tower terbesar",
    easy    = "Selalu pilih Tower terkecil",
    manual  = "Setting manual: Map, Rank, Rune",
}
-- Unlock rule per mode (identik 1.lua APM_UNLOCK):
local APM_UNLOCK = {
    default = {map=false, rank=false, rune=false},
    byrank  = {map=false, rank=true,  rune=false},
    bymap   = {map=true,  rank=false, rune=false},
    hard    = {map=false, rank=false, rune=false},
    easy    = {map=false, rank=false, rune=false},
    manual  = {map=true,  rank=true,  rune=true },
}
local curAPM = 5 -- default: "easy" (sama seperti 1.lua)
ASC.pickMode = APM_KEYS[curAPM]

local ascPickModeDD = ascSection:Dropdown({
    Flag     = "ascPickMode",
    Title    = "Pick Mode",
    Desc     = APM_TO_DESC[ASC.pickMode],
    Multi    = false,
    Value    = APM_OPTS[curAPM],
    Values   = APM_OPTS,
    Callback = function(val)
        for i, opt in ipairs(APM_OPTS) do
            if opt == val then
                curAPM = i
                ASC.pickMode = APM_KEYS[i]
                pcall(function() ascPickModeDD:SetDesc(APM_TO_DESC[ASC.pickMode]) end)
                if _applyAscPickModeLock then _applyAscPickModeLock(ASC.pickMode) end
                break
            end
        end
    end,
})
_setAscPMIdx = function(ii)
    if ii < 1 or ii > #APM_KEYS then return end
    curAPM = ii; ASC.pickMode = APM_KEYS[ii]
    pcall(function() ascPickModeDD:Select(APM_OPTS[ii]) end)
    if _applyAscPickModeLock then _applyAscPickModeLock(ASC.pickMode) end
end

--  PREFERRED MAP (Tower tujuan masuk, 1-26) 
-- Default: KOSONG (tidak ada Tower terpilih = masuk semua Tower)
local ASC_TOWER_NAMES = {
    [1]="Baran",       [2]="Baran+1",
    [3]="Grendal",     [4]="Grendal+1",
    [5]="Plague",      [6]="Plague+1",
    [7]="Frostborne",  [8]="Frostborne+1",
    [9]="Legia",       [10]="Legia+1",
    [11]="Silas",      [12]="Silas+1",
    [13]="Yogumunt",   [14]="Yogumunt+1",
    [15]="Antares",    [16]="Antares+1",
    [17]="Ashborn",    [18]="Ashborn+1",
    [19]="Dominion",   [20]="Dominion+1",
    [21]="Absolute",   [22]="Absolute+1",
    [23]="Broly",      [24]="Broly+1",
    [25]="Goku Super 4", [26]="Goku Super 4+1",
}

local _ascMapOptNames = {"-- NOT SELECTED --"}
for i = 1, 26 do table.insert(_ascMapOptNames, "Tower "..i.." - "..(ASC_TOWER_NAMES[i] or ("Tower "..i))) end
local _ascMapInitVal = {}
for i = 1, 26 do if ASC.preferMaps[i] then table.insert(_ascMapInitVal, "Tower "..i.." - "..(ASC_TOWER_NAMES[i] or ("Tower "..i))) end end
if #_ascMapInitVal == 0 then _ascMapInitVal = {"-- NOT SELECTED --"} end

local ascPrefMapDD = ascSection:Dropdown({
    Flag     = "ascPrefMap",
    Title    = "Preferred Map",
    Desc     = "Pilih Tower yang ingin dimasuki (kosong = semua)",
    Multi    = true,
    Value    = _ascMapInitVal,
    Values   = _ascMapOptNames,
    Callback = function(val)
        for mn = 1, 26 do ASC.preferMaps[mn] = nil end
        if type(val) == "table" then
            local hasNotSel = false
            for _, v in ipairs(val) do
                if v == "-- NOT SELECTED --" then hasNotSel = true; break end
            end
            if hasNotSel then
                pcall(function() ascPrefMapDD:Select({"-- NOT SELECTED --"}) end)
                return
            end
            for _, v in ipairs(val) do
                local mi = tonumber(v:match("Tower (%d+)"))
                if mi then ASC.preferMaps[mi] = true end
            end
        end
    end,
})
local function UpdateAscPrefMapLabel()
    local ns = {}
    for mn = 1, 26 do
        if ASC.preferMaps[mn] then table.insert(ns, "Tower "..mn.." - "..(ASC_TOWER_NAMES[mn] or ("Tower "..mn))) end
    end
    if #ns == 0 then
        pcall(function() ascPrefMapDD:Select({"-- NOT SELECTED --"}) end)
    else
        pcall(function() ascPrefMapDD:Select(ns) end)
    end
end
_ascUpdatePrefLabel = UpdateAscPrefMapLabel

--  PREFERRED RANK 
local _ascRankInitVal = {}
for _, g in ipairs(GRADE_LIST) do
    if ASC.runeGrades[g] then table.insert(_ascRankInitVal, g) end
end
local _ascRankOptNames = {"-- NOT SELECTED --"}
for _, g in ipairs(GRADE_LIST) do table.insert(_ascRankOptNames, g) end
if #_ascRankInitVal == 0 then _ascRankInitVal = {"-- NOT SELECTED --"} end

local ascRankDD = ascSection:Dropdown({
    Flag     = "ascRank",
    Title    = "Preferred Rank",
    Desc     = "Filter rank Tower yang ingin dimasuki",
    Multi    = true,
    Value    = _ascRankInitVal,
    Values   = _ascRankOptNames,
    Callback = function(val)
        for _, g in ipairs(GRADE_LIST) do ASC.runeGrades[g] = nil end
        if type(val) == "table" then
            local hasNotSel = false
            for _, v in ipairs(val) do
                if v == "-- NOT SELECTED --" then hasNotSel = true; break end
            end
            if hasNotSel then
                pcall(function() ascRankDD:Select({"-- NOT SELECTED --"}) end)
                if _ascWakeup then pcall(function() _ascWakeup:Fire() end) end
                return
            end
            for _, v in ipairs(val) do
                if GRADE_RANK[v] then ASC.runeGrades[v] = true end
            end
        end
        if _ascWakeup then pcall(function() _ascWakeup:Fire() end) end
    end,
})
local function RefreshAscRankLabel()
    local ns = {}
    for _, g in ipairs(GRADE_LIST) do if ASC.runeGrades[g] then table.insert(ns, g) end end
    if #ns == 0 then
        pcall(function() ascRankDD:Select({"-- NOT SELECTED --"}) end)
    else
        pcall(function() ascRankDD:Select(ns) end)
    end
end
_ascUpdateRankLabel = RefreshAscRankLabel

--  PREFERRED RUNE (Auto Item) 
local _ascRuneOptNames = {"-- NOT SELECTED --"}
for mn = 1, 26 do
    table.insert(_ascRuneOptNames, "Tower "..mn.." - "..(ASC_TOWER_NAMES[mn] or ("Tower "..mn)))
end
local _ascRuneInitVal = nil
if ASC.runeMapTarget >= 1 and ASC.runeMapTarget <= 26 then
    _ascRuneInitVal = "Tower "..ASC.runeMapTarget.." - "..(ASC_TOWER_NAMES[ASC.runeMapTarget] or ("Tower "..ASC.runeMapTarget))
end

local ascRuneDD = ascSection:Dropdown({
    Flag     = "ascRune",
    Title    = "Auto Item (Rune Tower)",
    Desc     = "Pilih Tower target item rune (opsional)",
    Multi    = false,
    Value    = _ascRuneInitVal,
    Values   = _ascRuneOptNames,
    Callback = function(val)
        if not val or val == "-- NOT SELECTED --" then
            ASC.runeMapTarget = 0; ASC.runeEnabled = false
        else
            local mi = tonumber(val:match("Tower (%d+)"))
            if mi and mi >= 1 and mi <= 26 then
                ASC.runeMapTarget = mi; ASC.runeEnabled = true
            end
        end
    end,
})
local function AscSyncRuneState()
    if ASC.runeMapTarget >= 1 and ASC.runeMapTarget <= 26 then ASC.runeEnabled = true
    else ASC.runeEnabled = false end
end
AscSyncRuneState()
_setAscRuneMapTarget = function(ml)
    ASC.runeMapTarget = ml or 0; AscSyncRuneState()
    if ml and ml >= 1 and ml <= 26 then
        local txt = "Tower "..ml.." - "..(ASC_TOWER_NAMES[ml] or ("Tower "..ml))
        pcall(function() ascRuneDD:Select(txt) end)
    else
        pcall(function() ascRuneDD:Select("-- NOT SELECTED --") end)
    end
end

--  AUTO KILL BOSS 
local ascBossToggle = ascSection:Toggle({
    Flag     = "ascBoss",
    Title    = "AUTO KILL BOSS",
    Desc     = "Teleport ke boss dan auto attack sampai mati",
    Default  = ASC.autoKillBoss or false,
    Callback = function(on)
        ASC.autoKillBoss = on
    end,
})
_ascBossToggleVis = function(on)
    ASC.autoKillBoss = on
    pcall(function() ascBossToggle:Set(on, false) end)
end

--  TELEPORT DELAY SLIDER 
local ascBossDelaySlider = ascSection:Slider({
    Flag     = "ascBossDelay",
    Title    = "Teleport Delay (s)",
    Desc     = "Delay sebelum teleport ke boss (1-10 detik)",
    Value    = { Min = 1, Max = 10, Default = ASC.bossDelay or 3 },
    Step     = 1,
    Callback = function(val)
        ASC.bossDelay = math.clamp(math.floor(val + 0.5), 1, 10)
    end,
})
_ascBossDelaySet = function(val)
    ASC.bossDelay = math.clamp(math.round(val), 1, 10)
    pcall(function() ascBossDelaySlider:Set(ASC.bossDelay) end)
end

--  LIST ENTRY ASC 
local ascListSection = ascSection:Section({ Title = "Ascension List Entry", Icon = "list", Opened = false, Box = true })

local ascListToggle = ascListSection:Toggle({
    Flag     = "ascListEnabled",
    Title    = "List Entry",
    Desc     = "Aktifkan sistem antrian entry Tower+rank",
    Default  = ASC.listEnabled or false,
    Callback = function(on)
        ASC.listEnabled = on
        if _ascWakeup then pcall(function() _ascWakeup:Fire() end) end
    end,
})
_setAscListEnabledVis = function(on)
    ASC.listEnabled = on
    pcall(function() ascListToggle:Set(on, false) end)
end

local ascListSaveBtn = ascListSection:Button({
    Title    = "+ Save Entry",
    Desc     = "Simpan kombinasi Tower+rank sekarang ke list",
    Callback = function()
        local snapMaps = {}
        for mn = 1, 26 do if ASC.preferMaps[mn] then snapMaps[mn] = true end end
        local snapRanks = {}
        for _, g in ipairs(GRADE_LIST) do if ASC.runeGrades[g] then snapRanks[g] = true end end
        -- Cegah duplikat (identik 1.lua)
        for _, ent in ipairs(ASC.listEntries) do
            local dupMap, dupRank = true, true
            for mn = 1, 26 do
                if (snapMaps[mn] ~= nil) ~= (ent.maps[mn] ~= nil) then dupMap = false; break end
            end
            for _, g in ipairs(GRADE_LIST) do
                if (snapRanks[g] ~= nil) ~= (ent.ranks[g] ~= nil) then dupRank = false; break end
            end
            if dupMap and dupRank then return end
        end
        table.insert(ASC.listEntries, {maps=snapMaps, ranks=snapRanks})
        if _ascRebuildListRows then _ascRebuildListRows() end
    end,
})

local _ascListPara = ascListSection:Paragraph({
    Title = "Saved Entries",
    Desc  = "(kosong)",
})
local function AscRebuildListDisplay()
    if #ASC.listEntries == 0 then
        pcall(function() _ascListPara:SetDesc("(kosong)") end)
        return
    end
    local lines = {}
    for i, ent in ipairs(ASC.listEntries) do
        local mapsStr
        if not next(ent.maps) then mapsStr = "All Tower"
        else
            local ms = {}; for mn in pairs(ent.maps) do table.insert(ms, mn) end
            table.sort(ms); local parts = {}
            for _, mn in ipairs(ms) do table.insert(parts, "T"..mn) end
            mapsStr = table.concat(parts, ",")
        end
        local ranksStr
        if not next(ent.ranks) then ranksStr = "All"
        else
            local rs = {}
            for _, g in ipairs(GRADE_LIST) do if ent.ranks[g] then table.insert(rs, g) end end
            ranksStr = table.concat(rs, "/")
        end
        table.insert(lines, "#"..i.." "..mapsStr.." | "..ranksStr)
    end
    pcall(function() _ascListPara:SetDesc(table.concat(lines, "\n")) end)
end
_ascRebuildListRows = AscRebuildListDisplay

local ascListDeleteBtn = ascListSection:Button({
    Title    = "- Hapus Entry Terakhir",
    Desc     = "Hapus entry paling bawah dari list",
    Callback = function()
        if #ASC.listEntries > 0 then
            table.remove(ASC.listEntries)
            AscRebuildListDisplay()
        end
    end,
})

--  APPLY ASC PICK MODE LOCK 
-- Dipanggil saat Pick Mode berubah. Identik pattern RAID: lock = clear data + Lock()/Unlock()
_ascPrefLocked, _ascRankLocked, _ascRuneLocked = false, false, false

local function _doApplyAscLock(pm)
    local u = APM_UNLOCK[pm] or {map=false, rank=false, rune=false}
    local lockMsg = "Tidak tersedia di mode " .. pm

    -- Preferred Map
    _ascPrefLocked = not u.map
    if _ascPrefLocked then
        for mn = 1, 26 do ASC.preferMaps[mn] = nil end
        pcall(function() ascPrefMapDD:Select({}) end)
        pcall(function() ascPrefMapDD:Lock(lockMsg) end)
    else
        pcall(function() ascPrefMapDD:Unlock() end)
    end

    -- Preferred Rank
    _ascRankLocked = not u.rank
    if _ascRankLocked then
        for _, g in ipairs(GRADE_LIST) do ASC.runeGrades[g] = nil end
        pcall(function() ascRankDD:Select({}) end)
        pcall(function() ascRankDD:Lock(lockMsg) end)
    else
        pcall(function() ascRankDD:Unlock() end)
    end

    -- Auto Item (Rune)
    _ascRuneLocked = not u.rune
    if _ascRuneLocked then
        ASC.runeMapTarget = 0; ASC.runeEnabled = false
        pcall(function() ascRuneDD:Select("-- NOT SELECTED --") end)
        pcall(function() ascRuneDD:Lock(lockMsg) end)
    else
        pcall(function() ascRuneDD:Unlock() end)
    end

end

_applyAscPickModeLock = _doApplyAscLock

-- Inisialisasi flag lock sesuai pickMode awal
_ascPrefLocked = not (APM_UNLOCK[ASC.pickMode or "easy"] or {}).map
_ascRankLocked = not (APM_UNLOCK[ASC.pickMode or "easy"] or {}).rank
_ascRuneLocked = not (APM_UNLOCK[ASC.pickMode or "easy"] or {}).rune

-- Apply lock saat script load (defer agar semua elemen sudah terdaftar ke WindUI)
task.defer(function() _doApplyAscLock(ASC.pickMode or "easy") end)

AscRebuildListDisplay()

end -- end do: AUTO RAID ASCENSION UI



-- ============================================================================
-- AUTO SIEGE - v102 [SIMPLIFIED ENTRY + BASEMAP TP BYPASS]
-- Flow:
--   1. Toggle ON -> tunggu UpdateCityRaidInfo dari server (SIEGE.live diisi scanner)
--   2. Notif masuk -> cek apakah player SUDAH di basemap siege yang benar:
--      - SUDAH di basemap    -> bypass TP, delay 2 detik
--      - BELUM di basemap    -> LocalTp ke baseMapId dulu, delay 2 detik
--   3. Fire EnterCityRaidMap(cityRaidId) SAJA (cukup 1 remote entry,
--      terverifikasi manual test: tidak perlu StartLocalPlayerTeleport/
--      LocalPlayerTeleportSuccess lagi)
--   4. Poll workspace cari Map201-Map205 (max 15 detik)
--   5. Map muncul -> Fire EquipHeroWithData
--   6. Delay 4 detik (render musuh)
--   7. Serang semua musuh, pantau Map201-Map205 masih ada. Jika hilang -> stop
--   8. QuitCityRaidMap -> cleanup -> count -> tunggu notif berikutnya
-- ============================================================================

-- DATA & CONSTANTS
local SIEGE_DATA = {
    [3]  = {name="Map 3  - Shadow Castle",       cityRaidId=1000001, tpMapId=50201, baseMapId=50003, mapFolder="Map201"},
    [7]  = {name="Map 7  - Demon Castle Tier 2",  cityRaidId=1000002, tpMapId=50202, baseMapId=50007, mapFolder="Map202"},
    [10] = {name="Map 10 - Plagueheart",          cityRaidId=1000003, tpMapId=50203, baseMapId=50010, mapFolder="Map203"},
    [13] = {name="Map 13 - Lava Hell",            cityRaidId=1000004, tpMapId=50204, baseMapId=50013, mapFolder="Map204"},
    [18] = {name="Map 18 - Golden Throne",        cityRaidId=1000005, tpMapId=50205, baseMapId=50018, mapFolder="Map205"},
}
local SIEGE_MAP_NUMS = {3, 7, 10, 13, 18}

-- Kill target semua map Siege (paten)
local SIEGE_KILL_TARGET  = 30
-- Radius serang dari posisi player (studs)
local SIEGE_ATTACK_RADIUS = 2000

-- STATE TABLE
if not SIEGE then
    SIEGE = {
        running      = false,
        thread       = nil,
        inMap        = false,
        teleporting  = false,
        excludeMaps  = {[3]=false,[7]=false,[10]=false,[13]=false,[18]=false},
        statusLbl    = nil,
        dot          = nil,
        countSummaryLbl = nil,
        count        = {[3]=0,[7]=0,[10]=0,[13]=0,[18]=0},
        killed       = 0,
        live         = {},
        _lastExitTime = 0,
    }
end

_siegeToggleState = _siegeToggleState or false
_siegeSessionStart = _siegeSessionStart or nil
local _siegeWakeup = nil

-- Forward declare UI helpers (diisi oleh panel)
_setSiegeToggle      = _setSiegeToggle      or nil
_updateSiegeDdLabel  = _updateSiegeDdLabel  or nil

-- Status helper
SiegeStatus = function(msg, color)
    if SIEGE.statusLbl then
        local ts = ""
        if _siegeSessionStart then
            local dur = os.time() - _siegeSessionStart
            ts = string.format("[%02d:%02d:%02d] ", math.floor(dur/3600), math.floor(dur/60)%60, dur%60)
        end
        SIEGE.statusLbl.Text = ts .. msg
        SIEGE.statusLbl.TextColor3 = color or Color3.fromRGB(160,148,135)
    end
    if SIEGE.dot then
        SIEGE.dot.BackgroundColor3 = color or Color3.fromRGB(100,100,100)
    end
end

SiegeCounterUpdate = function()
    if SIEGE.countSummaryLbl then
        local parts = {}
        for _, mn in ipairs(SIEGE_MAP_NUMS) do
            table.insert(parts, "M"..mn..":"..(SIEGE.count[mn] or 0))
        end
        SIEGE.countSummaryLbl.Text = table.concat(parts, "  ")
    end
end

-- Forward declare (diisi fungsi sesungguhnya di bawah, dekat pull worker Siege)
local _StopSiegeEnemyPullWorker

-- Stop
StopSiege = function()
    SIEGE.running     = false
    SIEGE.inMap       = false
    SIEGE.teleporting = false
    SIEGE._lastExitTime = os.time()
    _siegeInterrupt   = false
    MODE:Release("siege")
    if MODE.current == "siege" then MODE.current = "idle" end
    if SIEGE.thread then
        pcall(function() task.cancel(SIEGE.thread) end)
        SIEGE.thread = nil
    end
    if _StopSiegeEnemyPullWorker then
        pcall(_StopSiegeEnemyPullWorker)
    end
    SiegeStatus("[FLa] Idle", Color3.fromRGB(100,100,100))
end

-- Helper: cek player masih di Siege map (workspace scan)
local function IsInSiegeMapNow()
    for _, obj in ipairs(workspace:GetChildren()) do
        local n = obj.Name
        if n == "Map201" or n == "Map202" or n == "Map203"
        or n == "Map204" or n == "Map205" then
            return true
        end
    end
    local mf = workspace:FindFirstChild("Maps")
    if mf then
        for i = 1, 5 do
            if mf:FindFirstChild("Map20"..i) then return true end
        end
    end
    local ok, wm = pcall(function()
        return workspace:GetAttribute("MapId")
            or workspace:GetAttribute("mapId")
            or workspace:GetAttribute("CurrentMapId")
    end)
    if ok and type(wm) == "number" and wm >= 50201 and wm <= 50205 then
        return true
    end
    return false
end

-- Helper: scan musuh Siege dalam radius SIEGE_ATTACK_RADIUS dari posisi player
local function GetSiegeEnemies(mapFolder)
    local list, seen = {}, {}
    local FOLDERS = {"Enemys","EnemyCityRaid","CityRaidEnemys","Enemies","Enemy"}

    -- Ambil posisi player untuk filter radius
    local _playerPos = nil
    local _lp = game:GetService("Players").LocalPlayer
    if _lp and _lp.Character then
        local _hrp = _lp.Character:FindFirstChild("HumanoidRootPart")
        if _hrp then _playerPos = _hrp.Position end
    end

    local function _add(e)
        if not e:IsA("Model") then return end
        if not e:IsDescendantOf(workspace) then return end
        local g   = e:GetAttribute("EnemyGuid") or e:GetAttribute("BossGuid")
                 or e:GetAttribute("Guid")       or e:GetAttribute("GUID")
        local h   = e:FindFirstChild("HumanoidRootPart")
        local hum = e:FindFirstChildOfClass("Humanoid")
        if not (g and h and hum) then return end
        if seen[g] then return end
        if hum.Health <= 0 then return end
        if hum.MaxHealth <= 0 then return end
        local p = h.Position
        if p.Magnitude <= 10 then return end
        if p.Y < -200 or p.Y > 1500 then return end
        if not h:IsDescendantOf(workspace) then return end
        -- Filter radius: skip enemy yang lebih jauh dari SIEGE_ATTACK_RADIUS
        if _playerPos and (p - _playerPos).Magnitude > SIEGE_ATTACK_RADIUS then return end
        seen[g] = true
        table.insert(list, {model=e, guid=g, hrp=h})
    end
    -- Prioritas 1: nested di map folder aktif (anti-kontaminasi enemy Raid/ASC)
    if mapFolder then
        local mf = workspace:FindFirstChild(mapFolder)
        if mf then
            for _, fname in ipairs(FOLDERS) do
                local f = mf:FindFirstChild(fname)
                if f then for _, e in ipairs(f:GetChildren()) do _add(e) end end
            end
        end
    end
    -- Prioritas 2: fallback top-level workspace
    if #list == 0 then
        for _, fname in ipairs(FOLDERS) do
            local f = workspace:FindFirstChild(fname)
            if f then for _, e in ipairs(f:GetChildren()) do _add(e) end end
        end
    end
    if #list == 0 then
        for _, obj in ipairs(workspace:GetChildren()) do _add(obj) end
    end
    return list
end

-- [REMOVED] _SiegeFireDamage & _SiegeFireHeroMoves (pola single-loop lama) —
-- digantikan sepenuhnya oleh sistem RA/TA dual-thread (_SGMA_*) di bawah,
-- yang identik dengan Mass Attack (_MA_*). Lihat blok "SIEGE — 2 THREAD
-- INDEPENDEN HP-RANKED" setelah SIEGE ENEMY PULL WORKER.

-- =========================================================================
--  SIEGE ENEMY PULL WORKER
--  Identik dengan Enemy Pull Worker Mass Attack: Heartbeat loop yang menarik
--  musuh (sejumlah Kill Target) ke 1 titik kumpul di depan player, dengan
--  jitter kecil supaya tidak saling tindih. Dipakai SETELAH delay render
--  musuh (4 detik), SEBELUM SiegeAttackLoop mulai menyerang.
-- =========================================================================
local _siegePullWorkerConn  = nil
local _siegePullTargets     = {}
local _siegePullDestroyedG  = {}
local _siegePullOwnerSet    = {}
local _siegePullRand        = Random.new()
local _siegePullMapFolder   = nil
local _siegePullSeenG       = {}  -- guid -> true, supaya tidak dobel insert saat re-scan
local _siegePullRescanTick  = 0

function _StopSiegeEnemyPullWorker()
    if _siegePullWorkerConn then
        pcall(function() _siegePullWorkerConn:Disconnect() end)
        _siegePullWorkerConn = nil
    end
    _siegePullTargets    = {}
    _siegePullDestroyedG = {}
    _siegePullSeenG      = {}
    _siegePullMapFolder  = nil
end

-- Sama persis dengan _clusterOffset() Mass Attack: SEMUA musuh ditarik ke 1
-- titik yang PERSIS SAMA (tanpa jitter, boleh saling bertumpuk), 5 studs di
-- depan player.
local function _siegeClusterOffset()
    local FORWARD = 5
    return 0, FORWARD
end

local function _StartSiegeEnemyPullWorker(targets, mapFolder)
    _StopSiegeEnemyPullWorker()
    _siegePullTargets    = targets  -- array {model=..., guid=...}
    _siegePullDestroyedG = {}
    _siegePullOwnerSet   = {}
    _siegePullMapFolder  = mapFolder
    _siegePullSeenG       = {}
    _siegePullRescanTick  = 0
    for _, t in ipairs(_siegePullTargets) do
        _siegePullSeenG[t.guid] = true
    end

    for _, t in ipairs(_siegePullTargets) do
        t.jitterSide, t.jitterFwd = _siegeClusterOffset()
    end

    _siegePullWorkerConn = game:GetService("RunService").Heartbeat:Connect(function()
        local lp   = game:GetService("Players").LocalPlayer
        local char = lp and lp.Character
        local pHRP = char and char:FindFirstChild("HumanoidRootPart")
        if not pHRP then return end

        -- [EDIT] Re-scan periodik (tiap ~0.5 detik) supaya musuh BARU yang
        -- muncul belakangan -- termasuk musuh nyasar/bug dari luar map --
        -- ikut ditambahkan ke daftar tarikan, tanpa perlu restart worker.
        _siegePullRescanTick = _siegePullRescanTick + 1
        if _siegePullRescanTick >= 30 then  -- ~30 frame Heartbeat (~0.5s di 60fps)
            _siegePullRescanTick = 0
            local ok, _newEnemies = pcall(GetSiegeEnemies, _siegePullMapFolder)
            if ok and _newEnemies then
                for _, e in ipairs(_newEnemies) do
                    if not _siegePullSeenG[e.guid] then
                        _siegePullSeenG[e.guid] = true
                        local t = { model = e.model, guid = e.guid }
                        t.jitterSide, t.jitterFwd = _siegeClusterOffset()
                        table.insert(_siegePullTargets, t)
                    end
                end
            end
        end

        local cf    = pHRP.CFrame
        local right = cf.RightVector
        local fwd   = cf.LookVector

        for _, t in ipairs(_siegePullTargets) do
            if _siegePullDestroyedG[t.guid] then continue end

            local model = t.model
            if not model or not model.Parent then
                _siegePullDestroyedG[t.guid] = true
                continue
            end
            local hum = model:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then
                _siegePullDestroyedG[t.guid] = true
                pcall(function() model:Destroy() end)
                continue
            end

            local targetPos = pHRP.Position
                + fwd   * t.jitterFwd
                + right * t.jitterSide

            local eHRP = model:FindFirstChild("HumanoidRootPart")
            if eHRP then
                if not _siegePullOwnerSet[t.guid] then
                    _siegePullOwnerSet[t.guid] = true
                    pcall(function()
                        eHRP:SetNetworkOwner(lp)
                    end)
                end
                local _ok = pcall(function()
                    eHRP.CFrame = CFrame.new(targetPos, pHRP.Position)
                end)
                -- [FIX RACE CONDITION] Tandai settled setelah snap CFrame pertama
                -- berhasil -- SiegeAttackLoop hanya boleh menyerang target yang
                -- sudah settled=true (sama pola dengan Mass Attack).
                if _ok then t.settled = true end
            end
        end
    end)
end

-- =========================================================================
--  SIEGE — 2 THREAD INDEPENDEN HP-RANKED (RA-style + TA-style)
--  [FIX] Sebelumnya SiegeAttackLoop pakai 1 loop tunggal yang menyerang
--  SEMUA target sekaligus tiap PG_Wait(0.08) -- TIDAK SAMA dengan Mass Attack
--  yang pakai 2 thread independen (RA = HP tertinggi, TA = HP terendah sticky)
--  yang masing-masing loop per-frame (task.wait() tanpa jeda besar).
--  Blok ini port persis _MA_GetAliveRanked/_MA_FireAtGuid/_MA_StartRAThread/
--  _MA_StartTAThread/_MA_StopAllSpam dari Mass Attack, diadaptasi untuk
--  membaca _siegePullTargets (bukan pullList lokal Mass Attack) supaya
--  ritme & strategi target 100% identik.
-- =========================================================================
local _SGMA_RA = {running = false, guid = nil, thread = nil}
local _SGMA_TA = {running = false, guid = nil, thread = nil}

-- Sama persis _MA_GetAliveRanked: ambil musuh alive & settled dari pullList,
-- HP realtime langsung dari Humanoid.Health.
local function _SGMA_GetAliveRanked(pullList)
    local out = {}
    for _, t in ipairs(pullList) do
        if not _siegePullDestroyedG[t.guid] and t.settled then
            local model = t.model
            if model and model.Parent then
                local hum = model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    out[#out + 1] = {guid = t.guid, model = model, hp = hum.Health}
                end
            end
        end
    end
    return out
end

-- Sama persis _MA_FireAtGuid: RE.Click:InvokeServer + RE.Atk:FireServer 1x ke 1 guid,
-- plus hero attack thread per-guid (targetPos realtime).
local function _SGMA_FireAtGuid(guid, model)
    local eHRP = model and model:FindFirstChild("HumanoidRootPart")
    local ePos = eHRP and eHRP.Position or nil
    local _atkPos = ePos
    if ePos then
        local _char = LP and LP.Character
        local _pHRP = _char and _char:FindFirstChild("HumanoidRootPart")
        if _pHRP then
            local _dir  = (_pHRP.Position - ePos)
            local _dir2 = Vector3.new(_dir.X, 0, _dir.Z)
            if _dir2.Magnitude > 0.1 then
                _atkPos = ePos + _dir2.Unit * 5
            else
                _atkPos = ePos + Vector3.new(1,0,0) * 5
            end
        end
    end

    if RE.Click then
        pcall(function()
            if _atkPos then
                RE.Click:InvokeServer({enemyGuid = guid, enemyPos = _atkPos})
            else
                RE.Click:InvokeServer({enemyGuid = guid})
            end
        end)
    end
    if RE.Atk then
        pcall(function() RE.Atk:FireServer({attackEnemyGUID = guid}) end)
    end
    pcall(function() EnsureSiegeHeroAtkThreadFor(guid) end)
end

-- Sama persis _MA_StopAllSpam
local function _SGMA_StopAllSpam()
    _SGMA_RA.running = false
    _SGMA_TA.running = false
    _SGMA_RA.guid = nil
    _SGMA_TA.guid = nil
end

-- ALL-GUID STYLE thread: BUKAN RA (HP tertinggi) atau TA (HP terendah) lagi.
-- Tiap iterasi, tembak SEMUA guid alive di pullList satu per satu (loop for)
-- supaya tidak ada musuh yang "nyangkut" tertarik ke depan player tapi
-- tidak pernah diserang gara-gara tidak pernah kepilih jadi best/lowest.
local function _SGMA_StartAllThread(getPullList)
    if _SGMA_RA.running then return end
    _SGMA_RA.running = true
    _SGMA_RA.thread = task.spawn(function()
        while _SGMA_RA.running and SIEGE.running and SIEGE.inMap do
            local ranked = _SGMA_GetAliveRanked(getPullList())
            if #ranked == 0 then
                task.wait()
            else
                for _, e in ipairs(ranked) do
                    if not (_SGMA_RA.running and SIEGE.running and SIEGE.inMap) then break end
                    _SGMA_FireAtGuid(e.guid, e.model)
                end
                task.wait()
            end
        end
        _SGMA_RA.running = false
        _SGMA_RA.guid = nil
    end)
end

-- =========================================================================
--  SIEGE HERO ATTACK THREAD per-GUID — port persis EnsureHeroAtkThreadFor_MA
--  (targetPos dihitung REALTIME tiap fire, interval 1 detik per hero,
--  0.5 detik antar-cek per guid -- identik Mass Attack).
-- =========================================================================
local _siegeHeroAtkThreads = {}
local function _findSiegeEnemyHRP(g)
    for _, t in ipairs(_siegePullTargets) do
        if t.guid == g then
            local model = t.model
            return model and model:FindFirstChild("HumanoidRootPart")
        end
    end
    return nil
end
function EnsureSiegeHeroAtkThreadFor(g)
    if not g then return end
    if _siegeHeroAtkThreads[g] and _siegeHeroAtkThreads[g].running then return end
    local handle = {running=true, tick=0}
    _siegeHeroAtkThreads[g] = handle
    task.spawn(function()
        local _lastFire = {}
        while handle.running and SIEGE.running and SIEGE.inMap do
            if #HERO_GUIDS > 0 and (tick()-handle.tick) >= 0.5 and not _siegePullDestroyedG[g] then
                handle.tick = tick()
                local _atkPos = nil
                do
                    local eHRP = _findSiegeEnemyHRP(g)
                    local _char = LP and LP.Character
                    local _pHRP = _char and _char:FindFirstChild("HumanoidRootPart")
                    if eHRP and _pHRP then
                        local ePos  = eHRP.Position
                        local _dir  = (_pHRP.Position - ePos)
                        local _dir2 = Vector3.new(_dir.X, 0, _dir.Z)
                        if _dir2.Magnitude > 0.1 then
                            _atkPos = ePos + _dir2.Unit * 5
                        else
                            _atkPos = ePos + Vector3.new(1,0,0) * 5
                        end
                    end
                end
                for _, hGuid in ipairs(HERO_GUIDS) do
                    local last = _lastFire[hGuid] or 0
                    if (tick()-last) >= 1.0 then
                        _lastFire[hGuid] = tick()
                        if RE.HeroUseSkill then
                            pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g,targetPos=_atkPos}) end)
                            PG_Wait(0.1)
                            pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g,targetPos=_atkPos}) end)
                            PG_Wait(0.1)
                            pcall(function() RE.HeroUseSkill:FireServer({heroGuid=hGuid,attackType=1,userId=MY_USER_ID,enemyGuid=g,targetPos=_atkPos}) end)
                        end
                    end
                    PG_Wait(0.05)
                end
            end
            PG_Wait(0.05)
            if _siegePullDestroyedG[g] then
                handle.running = false
            end
        end
        _siegeHeroAtkThreads[g] = nil
    end)
end

-- Core: SiegeAttackLoop
-- [EDIT] Sekarang menyerang musuh dari _siegePullTargets (hasil pull worker,
-- sudah ditarik ke depan player) via 2 thread independen RA+TA -- persis pola
-- Mass Attack (AttackLoop_Mass): musuh ditarik dulu, baru diserang saat sudah
-- benar-benar dekat player (bukan scan ulang seluruh musuh di map), dengan
-- RA-thread (HP tertinggi) + TA-thread (HP terendah sticky) jalan paralel.
local function SiegeAttackLoop(onStatus, d)
    local MAX_TIME   = 120
    local totalTime  = 0
    local deadGuids  = {}
    local killCount  = 0

    local _deathConn = nil
    if RE.Death then
        _deathConn = RE.Death.OnClientEvent:Connect(function(dd)
            if not dd then return end
            local g = dd.enemyGuid or dd.guid
            if g and not deadGuids[g] then
                deadGuids[g] = true
                killCount = killCount + 1
                SIEGE.killed = SIEGE.killed + 1
            end
        end)
    end

    local function cleanup()
        if _deathConn then _deathConn:Disconnect(); _deathConn = nil end
        _SGMA_StopAllSpam()
    end

    -- getPullList: sumber target sama seperti Mass Attack (getPullList() di
    -- AttackLoop_Mass) -- filter deadGuids di sini, filter settled/destroyed
    -- ada di dalam _SGMA_GetAliveRanked (identik _MA_GetAliveRanked).
    local function getPullList()
        local out = {}
        for _, t in ipairs(_siegePullTargets) do
            if not deadGuids[t.guid] then out[#out+1] = t end
        end
        return out
    end

    -- Start 1 thread ALL-GUID SEKALI di awal -- tembak semua musuh alive tiap
    -- iterasi, bukan lagi RA (HP tertinggi) + TA (HP terendah) terpisah.
    _SGMA_StartAllThread(getPullList)

    while SIEGE.running and SIEGE.inMap do
        totalTime = totalTime + 0.08

        if totalTime >= MAX_TIME then
            if onStatus then onStatus("[!] Timeout - paksa keluar") end
            cleanup(); return "timeout"
        end

        if not IsInSiegeMapNow() then
            if onStatus then onStatus("[OK] Player keluar Siege map - stop serang") end
            cleanup(); return "exited"
        end

        -- [EDIT] Kondisi stop berdasar killCount (30 musuh) DIHAPUS.
        -- STOP sepenuhnya ditentukan oleh IsInSiegeMapNow() (keluar map) atau
        -- MAX_TIME (timeout) di atas -- supaya semua musuh (termasuk musuh
        -- nyasar/bug dari luar map yang terus muncul) tetap diserang sampai
        -- player benar-benar keluar dari Siege map.

        -- Hitung target aktif hanya untuk status display (attack sudah
        -- dihandle mandiri oleh thread RA+TA di background).
        local activeCount = 0
        for _, t in ipairs(_siegePullTargets) do
            if not deadGuids[t.guid] and not _siegePullDestroyedG[t.guid] and t.settled then
                local model = t.model
                if model and model.Parent then
                    local hum = model:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then activeCount = activeCount + 1 end
                end
            end
        end

        if activeCount == 0 then
            if onStatus then onStatus(string.format("[~] Tunggu musuh... kill: %d", killCount)) end
        else
            if onStatus then
                onStatus(string.format("[ATK] %d target | kill: %d", activeCount, killCount))
            end
        end

        PG_Wait(0.08)
    end

    cleanup()
    return "loop_ended"
end

-- Main Loop
StartSiegeLoop = function()
    if SIEGE.running then StopSiege() end

    SIEGE.running      = true
    SIEGE.inMap        = false
    SIEGE.teleporting  = false
    SIEGE.killed       = 0
    _siegeSessionStart = os.time()
    for _, mn in ipairs(SIEGE_MAP_NUMS) do SIEGE.count[mn] = 0 end
    SiegeCounterUpdate()
    SiegeStatus("[.] Waiting notif SIEGE...", Color3.fromRGB(255,200,60))

    if _siegeWakeup then pcall(function() _siegeWakeup:Destroy() end) end
    _siegeWakeup = Instance.new("BindableEvent")
    pcall(function() _siegeWakeup:Fire() end)

    -- Helper: satu siklus penuh masuk-serang-keluar map untuk targetMap tertentu
    -- Mengembalikan true = berhasil selesai siklus, false = harus break loop utama
    local function _SiegeDoEntry(targetMap)
        -- [v12 EDIT] SIEGE match ditemukan -- hard-stop Mass Attack SEGERA +
        -- delay 2s, cegah race condition rebutan musuh. Dipasang paling awal
        -- (sebelum cek RAID/ASC, sebelum set _siegeInterrupt) supaya MA benar-
        -- benar berhenti sedini mungkin, baik nanti masuk lewat jalur "TP ke
        -- basemap" maupun "Bypass TP ke basemap" (keduanya lewat fungsi ini).
        if _MA_HardStopForMatch then _MA_HardStopForMatch(function(msg) SiegeStatus(msg, Color3.fromRGB(255,180,50)) end) end

        -- [v60] Kesadaran diri: tunggu RAID/ASC keluar map dulu
        if (RAID and RAID.inMap) or (ASC and ASC.inMap) then
            local _waitWho = (RAID and RAID.inMap) and "RAID" or "ASC"
            SiegeStatus("[..] " .. _waitWho .. " masih di Map - SIEGE menunggu...", Color3.fromRGB(255,200,60))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
            local _wg = 0
            while ((RAID and RAID.inMap) or (ASC and ASC.inMap)) and SIEGE.running and _wg < 600 do
                task.wait(0.5); _wg = _wg + 0.5
            end
            if not SIEGE.running then return false end
        end

        -- SIEGE sudah tunggu RAID/ASC selesai di blok atas (baris 9101-9110)
        -- Tidak perlu tunggu lagi di sini, langsung set interrupt
        _siegeInterrupt = true  -- signal MA untuk pause (MA cek di guard tiap iterasi)
        if not MODE:WaitAndRequest("siege", 15) then
            _siegeInterrupt = false
            task.wait(1)
            return true -- retry loop utama
        end

        local d = SIEGE_DATA[targetMap]
        SIEGE.teleporting = true
        SIEGE.live[d.cityRaidId] = nil

        -- PRE-ENTRY: pastikan player di BaseMap siege yang benar dulu.
        -- [PATCH v2] Deteksi via workspace.Maps folder, bukan MapId attribute.
        -- Jika player sudah berada di base map siege yang sesuai (Map3/Map7/
        -- Map10/Map13/Map18) -> skip TP, langsung delay 2s lalu EnterCityRaidMap.
        -- Jika BELUM di base map itu (misal masih di map lain / map siege
        -- berbeda) -> WAJIB LocalTp ke baseMapId dulu, baru EnterCityRaidMap --
        -- kalau tidak, poll map folder nanti gagal validasi karena player
        -- masih nyangkut di map yang salah.
        local _BASEMAP_FOLDERS = {[3]="Map3",[7]="Map7",[10]="Map10",[13]="Map13",[18]="Map18"}
        local _baseFolder = _BASEMAP_FOLDERS[targetMap]
        local _alreadyAtBase = false
        if _baseFolder then
            local _mapsRoot = workspace:FindFirstChild("Maps")
            if _mapsRoot and _mapsRoot:FindFirstChild(_baseFolder) then
                _alreadyAtBase = true
            end
        end

        if _alreadyAtBase then
            -- Player sudah di basemap yang benar: bypass TP, langsung delay 2s
            SiegeStatus("[>>] Sudah di "..(_baseFolder or "basemap").." - bypass TP, delay 2s...", Color3.fromRGB(120,180,255))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(120,180,255) end
            task.wait(2)
        else
            -- Player belum di basemap yang benar: TP dulu sebelum EnterCityRaidMap
            SiegeStatus("[>>] TP ke BaseMap "..d.baseMapId.."...", Color3.fromRGB(120,180,255))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(120,180,255) end
            -- [v11 EDIT] Selalu pakai remote StartLocalPlayerTeleport (RE.StartTp)
            pcall(function()
                if RE.StartTp then RE.StartTp:FireServer({ mapId = d.baseMapId }) end
            end)
            SiegeStatus("[2s] Delay post-TP BaseMap...", Color3.fromRGB(120,180,255))
            task.wait(2)
        end

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        -- [SIMPLIFIED ENTRY] Setelah dipastikan di basemap yang benar, cukup 1
        -- remote saja: EnterCityRaidMap(cityRaidId). Tidak perlu lagi
        -- StartLocalPlayerTeleport atau LocalPlayerTeleportSuccess -- server
        -- langsung handle entry dari 1 remote ini saja (terverifikasi manual
        -- test di game).
        local _RE = Remotes

        SiegeStatus("[>>] Fire EnterCityRaidMap("..d.cityRaidId..")...", Color3.fromRGB(180,120,255))
        if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(180,120,255) end
        pcall(function()
            local re = _RE:FindFirstChild("EnterCityRaidMap")
            if re then re:FireServer(d.cityRaidId) end
        end)
        PG_Wait(0.8)

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        -- Poll workspace.Maps.[mapFolder] max 15s
        SiegeStatus("[..] Poll "..d.mapFolder.." (max 15s)...", Color3.fromRGB(255,200,60))
        local mapAppeared = false
        local mapWait = 0
        while mapWait < 15 and SIEGE.running do
            if workspace:FindFirstChild(d.mapFolder) then
                mapAppeared = true; break
            end
            local mapsFolder = workspace:FindFirstChild("Maps")
            if mapsFolder and mapsFolder:FindFirstChild(d.mapFolder) then
                mapAppeared = true; break
            end
            task.wait(0.5); mapWait = mapWait + 0.5
        end

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        if not mapAppeared then
            SiegeStatus("[!] "..d.mapFolder.." tidak muncul - retry...", Color3.fromRGB(255,100,60))
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege")
            task.wait(2)
            return true -- retry
        end

        SiegeStatus("[OK] "..d.mapFolder.." muncul! (+"..string.format("%.1f", mapWait).."s)", Color3.fromRGB(80,220,80))

        -- EquipHeroWithData setelah map muncul
        SiegeStatus("[>>] Fire EquipHeroWithData...", Color3.fromRGB(180,120,255))
        pcall(function()
            local re = _RE:FindFirstChild("EquipHeroWithData")
            if re then re:FireServer() end
        end)
        PG_Wait(0.5)

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        -- Delay render musuh
        SiegeStatus("[4s] Delay render musuh...", Color3.fromRGB(255,200,60))
        task.wait(4)

        if not SIEGE.running then
            SIEGE.teleporting = false; _siegeInterrupt = false; MODE:Release("siege"); return false
        end

        SIEGE.teleporting = false
        SIEGE.inMap = true
        SafeReequipAfterTeleport("AutoSiege")
        SiegeStatus("[S] "..d.name.." - ATTACK!", Color3.fromRGB(80,220,80))
        if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(80,220,80) end

        -- [EDIT] Tarik SEMUA musuh yang ada (bukan cuma SIEGE_KILL_TARGET) ke 1
        -- titik kumpul di depan player, SEBELUM SiegeAttackLoop mulai menyerang.
        -- STOP sepenuhnya ditentukan oleh kondisi keluar map (IsInSiegeMapNow)
        -- atau timeout, BUKAN oleh jumlah kill -- supaya musuh nyasar/bug yang
        -- terus muncul juga ikut ditarik & diserang sampai player benar-benar
        -- keluar dari Siege map.
        do
            local _enemies = GetSiegeEnemies(d.mapFolder)
            local _pullList = {}
            for i = 1, #_enemies do
                _pullList[i] = { model = _enemies[i].model, guid = _enemies[i].guid }
            end
            if #_pullList > 0 then
                _StartSiegeEnemyPullWorker(_pullList, d.mapFolder)
                -- [FIX RACE CONDITION] Tunggu SAMPAI semua musuh di _pullList benar-benar
                -- settled (sudah di-snap CFrame minimal 1x), bukan cuma delay buta --
                -- konsisten dengan Mass Attack (AttackLoop_Mass). Timeout 2 detik
                -- sebagai fallback safety.
                local _settleWait = 0
                while SIEGE.running and _settleWait < 2.0 do
                    local _allSettled = true
                    for _, t in ipairs(_pullList) do
                        if not t.settled then _allSettled = false; break end
                    end
                    if _allSettled then break end
                    task.wait(0.03)
                    _settleWait = _settleWait + 0.03
                end
            else
                -- Belum ada musuh sama sekali -- tetap start worker kosong,
                -- supaya re-scan periodik (di dalamnya) bisa menangkap musuh
                -- yang muncul belakangan.
                _StartSiegeEnemyPullWorker({}, d.mapFolder)
            end
        end

        local result = SiegeAttackLoop(function(msg)
            SiegeStatus("[S] "..msg, Color3.fromRGB(80,220,80))
        end, d)

        _StopSiegeEnemyPullWorker()

        -- Exit phase
        if result == "timeout" then
            SiegeStatus("[!] Timeout 2m - Force TP basemap...", Color3.fromRGB(255,100,60))
            pcall(function()
                local reQuit = Remotes:FindFirstChild("QuitCityRaidMap")
                if reQuit then reQuit:FireServer(d.cityRaidId) end
            end)
            pcall(function()
                -- [v11 EDIT] Selalu pakai remote StartLocalPlayerTeleport (RE.StartTp)
                if RE.StartTp then RE.StartTp:FireServer({ mapId = d.baseMapId }) end
            end)
            task.wait(3)
        else
            SiegeStatus("[<<] QuitCityRaidMap("..d.cityRaidId..")...", Color3.fromRGB(100,200,255))
            pcall(function()
                local re = Remotes:FindFirstChild("QuitCityRaidMap")
                if re then re:FireServer(d.cityRaidId) end
            end)
            local _exitWait = 0
            while IsInSiegeMapNow() and _exitWait < 8 and SIEGE.running do
                task.wait(0.3); _exitWait = _exitWait + 0.3
            end
        end

        SIEGE.inMap       = false
        SIEGE.teleporting = false
        SIEGE._lastExitTime = os.time()
        _siegeInterrupt   = false
        pcall(function() if MODE.current == "siege" then MODE:Release("siege") end end)

        if not SIEGE.running then return false end

        SIEGE.live[d.cityRaidId] = nil
        if _siegeChatOpen then _siegeChatOpen[targetMap] = false end
        SIEGE.count[targetMap] = (SIEGE.count[targetMap] or 0) + 1
        SiegeCounterUpdate()

        if result == "success" or result == "exited" then
            SiegeStatus("[OK] "..d.name.." SUCCESS! Waiting notif berikutnya...", Color3.fromRGB(100,255,150))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
        else
            SiegeStatus("[~] "..d.name.." ("..result..") - Waiting notif berikutnya...", Color3.fromRGB(255,200,60))
            if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end
        end
        task.wait(1)
        return true
    end

    SIEGE.thread = task.spawn(function()
        while SIEGE.running do

            -- Cari map siege tersedia, urut mapNum terkecil dulu
            local targetMap = nil
            for _, mn in ipairs(SIEGE_MAP_NUMS) do
                if not (SIEGE.excludeMaps and SIEGE.excludeMaps[mn]) then
                    local cid = SIEGE_DATA[mn].cityRaidId
                    if SIEGE.live[cid] then targetMap = mn; break end
                end
            end

            -- Kalau tidak ada, tunggu wakeup dari scanner (max 90 detik per cycle)
            if not targetMap then
                local exNames = {}
                for _, mn in ipairs(SIEGE_MAP_NUMS) do
                    if SIEGE.excludeMaps and SIEGE.excludeMaps[mn] then
                        table.insert(exNames, "M"..mn)
                    end
                end
                local exStr = #exNames > 0 and (" | Skip: "..table.concat(exNames,",")) or ""
                SiegeStatus("[.] Waiting OpenCityRaid..."..exStr, Color3.fromRGB(255,200,60))
                if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(255,200,60) end

                local _waitConn = _siegeWakeup.Event:Connect(function() end)
                local guard = 0
                while SIEGE.running and guard < 90 do
                    for _, mn in ipairs(SIEGE_MAP_NUMS) do
                        if not (SIEGE.excludeMaps and SIEGE.excludeMaps[mn]) then
                            if SIEGE.live[SIEGE_DATA[mn].cityRaidId] then
                                targetMap = mn; break
                            end
                        end
                    end
                    if targetMap then break end
                    task.wait(0.5); guard = guard + 0.5
                end
                pcall(function() _waitConn:Disconnect() end)
                if not SIEGE.running then break end
            end

            if targetMap then
                local ok = _SiegeDoEntry(targetMap)
                if not ok then break end
            end

        end -- while SIEGE.running

        -- Cleanup akhir saat toggle OFF
        _siegeInterrupt   = false
        SIEGE.inMap       = false
        SIEGE.teleporting = false
        MODE:Release("siege")
        if MODE.current == "siege" then MODE.current = "idle" end
        SIEGE.running = false
        SiegeStatus("[.] Idle", Color3.fromRGB(100,100,100))
        if SIEGE.dot then SIEGE.dot.BackgroundColor3 = Color3.fromRGB(100,100,100) end
    end)
end


-- ============================================================================
-- PANEL: AUTO SIEGE (WindUI Section - di bawah Auto Raid Ascension)
-- ============================================================================
do

local siegeSection = AutomationTab:Section({ Title = "Auto Siege", Icon = "shield", Opened = false, Box = true })

-- Status
local siegeStatusPara = siegeSection:Paragraph({
    Title = "Status",
    Desc  = "Idle - SELECT MAP",
})
SIEGE.statusLbl = {
    Text = "Idle - SELECT MAP",
    TextColor3 = Color3.fromRGB(160,148,135),
}
local _origSiegeStatus = SiegeStatus
SiegeStatus = function(msg, color)
    pcall(function() siegeStatusPara:SetDesc(msg) end)
    SIEGE.statusLbl.Text = msg
    SIEGE.statusLbl.TextColor3 = color or Color3.fromRGB(160,148,135)
end

-- Counter ringkas
local siegeCountPara = siegeSection:Paragraph({
    Title = "Count",
    Desc  = "M3:0  M7:0  M10:0  M13:0  M18:0",
})
SIEGE.countSummaryLbl = {
    Text = "M3:0  M7:0  M10:0  M13:0  M18:0",
}
local _origSiegeCounterUpdate = SiegeCounterUpdate
SiegeCounterUpdate = function()
    local parts = {}
    for _, mn in ipairs(SIEGE_MAP_NUMS) do
        table.insert(parts, "M"..mn..":"..(SIEGE.count[mn] or 0))
    end
    local txt = table.concat(parts, "  ")
    SIEGE.countSummaryLbl.Text = txt
    pcall(function() siegeCountPara:SetDesc(txt) end)
end

-- Toggle utama
local siegeEnableToggle = siegeSection:Toggle({
    Flag     = "siegeEnable",
    Title    = "Enable Auto Siege",
    Desc     = "ON = Menunggu notif EnterCityRaid dari server",
    Default  = false,
    Callback = function(on)
        _siegeToggleState = on
        if on then StartSiegeLoop() else StopSiege() end
    end,
})
_setSiegeToggle = function(on)
    if on == _siegeToggleState then return end
    _siegeToggleState = on
    pcall(function() siegeEnableToggle:Set(on, false) end)
    if on then StartSiegeLoop() else StopSiege() end
end
-- Visual-only setter (tidak trigger logika, hanya sync UI)
_visSiege = function(on)
    pcall(function() siegeEnableToggle:Set(on, false) end)
end

-- Exclude Map Dropdown (multi-select style via Dropdown)
local MAP_NAMES_SIEGE = {
    [3]  = "Map 3  - Shadow Castle",
    [7]  = "Map 7  - Demon Castle Tier 2",
    [10] = "Map 10 - Plagueheart",
    [13] = "Map 13 - Lava Hell",
    [18] = "Map 18 - Golden Throne",
}
local MAP_LABEL_TO_NUM = {}
local DD_OPTIONS = {}
for _, mn in ipairs(SIEGE_MAP_NUMS) do
    local lbl = MAP_NAMES_SIEGE[mn]
    table.insert(DD_OPTIONS, lbl)
    MAP_LABEL_TO_NUM[lbl] = mn
end

local siegeExcludeDD = siegeSection:Dropdown({
    Flag     = "siegeExclude",
    Title    = "Exclude Map (Skip Siege)",
    Desc     = "Pilih map yang ingin di-SKIP (tidak dimasuki)",
    Values   = DD_OPTIONS,
    Multi    = true,
    Default  = {},
    Callback = function(selected)
        -- Reset semua ke false dulu
        for _, mn in ipairs(SIEGE_MAP_NUMS) do
            SIEGE.excludeMaps[mn] = false
        end
        -- Set yang dipilih jadi true (skip)
        if type(selected) == "table" then
            for lbl, active in pairs(selected) do
                if active then
                    local mn = MAP_LABEL_TO_NUM[lbl]
                    if mn then SIEGE.excludeMaps[mn] = true end
                end
            end
        end
    end,
})

-- Expose setter visual-only untuk restore dropdown exclude map Siege saat Load Config
-- ApplyConfig restore SIEGE.excludeMaps datanya, lalu panggil ini untuk sync tampilan DD
_visSiegeExcludeDD = function()
    if not siegeExcludeDD then return end
    pcall(function()
        -- Bangun tabel selected: { [label] = true } untuk setiap map yang di-exclude
        local sel = {}
        for _, mn in ipairs(SIEGE_MAP_NUMS) do
            if SIEGE.excludeMaps and SIEGE.excludeMaps[mn] then
                local lbl = MAP_NAMES_SIEGE[mn]
                if lbl then sel[lbl] = true end
            end
        end
        siegeExcludeDD:Set(sel)
    end)
end

end -- end do: AUTO SIEGE UI


-- ============================================================================
-- SIEGE SCANNER v102 - Hook UpdateCityRaidInfo
-- action=StartChallenge/OpenCityRaid -> SIEGE.live -> wakeup loop
-- action=CloseCityRaid/LeaveCityRaid -> hapus dari SIEGE.live
-- ============================================================================
task.spawn(function()
    task.wait(3)
    if not SIEGE then return end
    if not SIEGE.live then SIEGE.live = {} end

    local _cidToMap = {
        [1000001] = 3,
        [1000002] = 7,
        [1000003] = 10,
        [1000004] = 13,
        [1000005] = 18,
    }

    local _reCity = Remotes:FindFirstChild("UpdateCityRaidInfo")
    if not _reCity then
        task.wait(5)
        _reCity = Remotes:FindFirstChild("UpdateCityRaidInfo")
    end

    if _reCity then
        _reCity.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            local id     = data.id
            local action = data.action
            local mn     = _cidToMap[id]
            if not id or not action or not mn then return end

            if action == "StartChallenge" or action == "OpenCityRaid" then
                if not SIEGE.live[id] then
                    SIEGE.live[id] = mn
                    if _siegeWakeup then
                        pcall(function() _siegeWakeup:Fire() end)
                    end
                end
            elseif action == "CloseCityRaid" or action == "LeaveCityRaid" then
                SIEGE.live[id] = nil
                if _siegeChatOpen then _siegeChatOpen[mn] = false end
            end
        end)
    end
end)



-- ============================================================================
-- JOIN TO RAID PLAYER (JTR)
-- SCAN  = ambil semua player di server (Players:GetPlayers())
-- JOIN  = StartLocalPlayerTeleport {hostId, mapId}
--         + EquipHeroWithData + LocalPlayerTeleportSuccess
-- Port dari 1.lua baris 17800-18157 ke WindUI AutomationTab
-- ============================================================================
do

local jtrSection = AutomationTab:Section({ Title = "Join To Raid Player", Icon = "users", Opened = false, Box = true })

-- State
local JTR_players = {}     -- { {name, userId} }
local JTR_selIdx  = nil
local JTR_joining = false
local JTR_mapId   = 50101  -- default: Normal Map 1
local JTR_isAsc   = false
local JTR_mapNum  = 1

local MAP_NORMAL_BASE = 50101
local MAP_NORMAL_MAX  = 20
local MAP_ASC_BASE    = 50302
local MAP_ASC_MAX     = 18

-- Status Paragraph
local jtrStatusPara = jtrSection:Paragraph({
    Title = "Status",
    Desc  = "Tekan SCAN untuk muat daftar player.",
})

local function JTRStat(msg)
    pcall(function() jtrStatusPara:SetDesc(msg) end)
end

-- Info Paragraph
jtrSection:Paragraph({
    Title = "Cara Pakai",
    Desc  = "SCAN -> Pilih Player -> Pilih Map -> JOIN.\nSetelah keluar dari Raid, tekan SCAN ulang.",
})

-- Player List Paragraph (hasil SCAN)
local jtrListPara = jtrSection:Paragraph({
    Title = "Daftar Player",
    Desc  = "(belum di-scan)",
})

local function RenderPlayerList()
    if #JTR_players == 0 then
        pcall(function() jtrListPara:SetDesc("(tidak ada player lain di server ini)") end)
        return
    end
    local lines = {}
    for i, entry in ipairs(JTR_players) do
        local marker = (i == JTR_selIdx) and "[v] " or "[ ] "
        table.insert(lines, marker .. i .. ". " .. entry.name .. "  (UID:" .. tostring(entry.userId) .. ")")
    end
    pcall(function() jtrListPara:SetDesc(table.concat(lines, "\n")) end)
end

-- Tombol SCAN
local _jtrBusy = false

jtrSection:Button({
    Title    = "SCAN Player",
    Desc     = "Ambil daftar semua player di server ini",
    Callback = function()
        if _jtrBusy then JTRStat("[~] Sedang scanning..."); return end
        _jtrBusy = true
        JTRStat("[~] Mengambil daftar player di server...")
        JTR_selIdx = nil

        task.spawn(function()
            local found = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP then
                    table.insert(found, {name = plr.Name, userId = plr.UserId})
                end
            end
            JTR_players = found
            _jtrBusy = false

            if #found == 0 then
                JTRStat("[!] Tidak ada player lain di server ini.")
                pcall(function() jtrListPara:SetDesc("(tidak ada player lain)") end)
            else
                JTRStat("[OK] " .. #found .. " player ditemukan. Pilih nomor -> JOIN.")
                RenderPlayerList()
            end
        end)
    end,
})

-- Input: Pilih nomor player dari daftar
jtrSection:Input({
    Title       = "Pilih Player (Nomor)",
    Desc        = "Ketik nomor urut player dari daftar SCAN di atas",
    Placeholder = "Contoh: 1",
    Value       = "",
    Callback    = function(val)
        local n = tonumber(val)
        if n and n >= 1 and n <= #JTR_players then
            JTR_selIdx = math.floor(n)
            local entry = JTR_players[JTR_selIdx]
            JTRStat("[v] Dipilih: " .. entry.name .. "  (hostId=" .. entry.userId .. ")")
            RenderPlayerList()
        else
            JTR_selIdx = nil
            if #JTR_players > 0 then
                JTRStat("[!] Nomor tidak valid. Masukkan angka 1-" .. #JTR_players)
            else
                JTRStat("[!] Scan dulu sebelum memilih player.")
            end
        end
    end,
})

-- Map Target Paragraph (info mapId aktif)
local jtrMapTypePara = jtrSection:Paragraph({
    Title = "Map Target",
    Desc  = "Mode: Normal Raid | Map 1  (mapId=50101)",
})

local function UpdateJTRMapDisplay()
    if JTR_isAsc then
        JTR_mapId = MAP_ASC_BASE
        pcall(function() jtrMapTypePara:SetDesc(
            "Mode: Ascension | Tower " .. JTR_mapNum .. "  (mapId=" .. JTR_mapId .. ")"
        ) end)
    else
        JTR_mapId = MAP_NORMAL_BASE + (JTR_mapNum - 1)
        pcall(function() jtrMapTypePara:SetDesc(
            "Mode: Normal Raid | Map " .. JTR_mapNum .. "  (mapId=" .. JTR_mapId .. ")"
        ) end)
    end
end

-- Toggle: Normal / Ascension
jtrSection:Toggle({
    Title    = "Mode Ascension",
    Desc     = "OFF = Normal Raid |  ON = Ascension",
    Default  = false,
    Callback = function(on)
        JTR_isAsc = on
        local maxMap = on and MAP_ASC_MAX or MAP_NORMAL_MAX
        if JTR_mapNum > maxMap then JTR_mapNum = maxMap end
        UpdateJTRMapDisplay()
    end,
})

-- Input: Nomor Map atau Tower
jtrSection:Input({
    Title       = "Nomor Map / Tower",
    Desc        = "Normal: 1-20  |  Ascension: 1-18",
    Placeholder = "Contoh: 1",
    Value       = "1",
    Callback    = function(val)
        local n = tonumber(val)
        if not n then return end
        n = math.floor(n)
        local maxMap = JTR_isAsc and MAP_ASC_MAX or MAP_NORMAL_MAX
        if n < 1 then n = 1 end
        if n > maxMap then n = maxMap end
        JTR_mapNum = n
        UpdateJTRMapDisplay()
    end,
})

UpdateJTRMapDisplay()

-- Tombol JOIN
jtrSection:Button({
    Title    = "JOIN to Raid Player",
    Desc     = "Teleport masuk ke Raid player yang dipilih",
    Callback = function()
        if JTR_joining then JTRStat("[~] Sedang proses JOIN..."); return end
        if not JTR_selIdx then
            JTRStat("[!] Belum ada player yang dipilih! SCAN lalu ketik nomor.")
            return
        end
        local entry = JTR_players[JTR_selIdx]
        if not entry then
            JTRStat("[!] Data tidak valid, coba SCAN ulang.")
            return
        end

        JTR_joining = true
        local mapId   = JTR_mapId
        local mapType = JTR_isAsc and "ASC" or "NORMAL"
        JTRStat("[JOIN] -> " .. entry.name .. " | hostId=" .. entry.userId .. " | mapId=" .. mapId .. " (" .. mapType .. ")")

        task.spawn(function()
            local ok, err = pcall(function()
                local reStartTp = Remotes:FindFirstChild("StartLocalPlayerTeleport")
                local reEquip   = Remotes:FindFirstChild("EquipHeroWithData")
                local reTpSucc  = Remotes:FindFirstChild("LocalPlayerTeleportSuccess")

                if not reStartTp then error("Remote StartLocalPlayerTeleport tidak ditemukan!") end

                -- Step 1: StartLocalPlayerTeleport {hostId, mapId}
                JTRStat("[1/3] Teleport ke raid " .. entry.name .. "...")
                reStartTp:FireServer({hostId = entry.userId, mapId = mapId})
                task.wait(0.5)

                -- Step 2: EquipHeroWithData
                if reEquip then pcall(function() reEquip:FireServer() end) end
                task.wait(0.3)

                -- Step 3: LocalPlayerTeleportSuccess
                if reTpSucc then
                    pcall(function() reTpSucc:InvokeServer() end)
                end
            end)

            JTR_joining = false

            if ok then
                JTRStat("[OK] Berhasil join " .. entry.name .. "! (mapId=" .. mapId .. ")")
                SafeReequipAfterTeleport("JoinToRaidPlayer")
            else
                JTRStat("[ERR] " .. (tostring(err):sub(1, 80)))
            end
        end)
    end,
})

-- Tombol BACK TO MAP 2
-- Remote: StartLocalPlayerTeleport:FireServer({mapId=50002})
-- Identik dengan 1.lua baris 17691-17726 (JTP panel)
local _jtrBackBusy = false
jtrSection:Button({
    Title    = "BACK TO MAP 2  (Lobby)",
    Desc     = "Teleport keluar ke Map 2 Lobby",
    Callback = function()
        if _jtrBackBusy then JTRStat("[~] Sedang teleport ke Map 2..."); return end
        _jtrBackBusy = true
        JTRStat("[~] Kembali ke Map Lobby 2...")

        task.spawn(function()
            local ok, err = pcall(function()
                local reStartTp = Remotes:FindFirstChild("StartLocalPlayerTeleport")
                if not reStartTp then error("Remote StartLocalPlayerTeleport tidak ditemukan!") end
                reStartTp:FireServer({mapId = 50002})
            end)

            _jtrBackBusy = false

            if ok then
                JTRStat("[OK] Berhasil teleport ke Map Lobby 2.")
            else
                JTRStat("[ERR] Gagal: " .. (tostring(err):sub(1, 80)))
            end
        end)
    end,
})

end -- do JTR






-- ============================================================================
-- STUB SETTERS — panel belum diconvert ke 2.lua
-- Dipanggil oleh ApplyConfig saat Load Config. Tanpa definisi ini script crash
-- karena memanggil nil. Stub ini mencegah crash dan menyimpan state di variabel
-- backing sehingga logika tetap konsisten ketika panel akhirnya diconvert nanti.
-- ============================================================================

-- ── Dungeon toggle stub ───────────────────────────────────────────────────────
-- Panel Dungeon (JTR punya tombol join, bukan toggle persistent ON/OFF)
-- Belum diconvert ke 2.lua — stub simpan state saja, tidak ada visual.
if not _dungeonToggleState then _dungeonToggleState = false end
_setDungeonToggle = _setDungeonToggle or function(v)
    _dungeonToggleState = v == true
end
_visDungeon = _visDungeon or function(_v)
    -- tidak ada toggle visual di JTR panel — no-op
end

-- ── ST2 toggle stub ───────────────────────────────────────────────────────
-- ST2 di 1.lua adalah panel terpisah yang belum diconvert ke 2.lua.
-- Fitur Anniversary Celebration sudah dihapus (event berakhir); ST2 tetap
-- dipertahankan sebagai flag guard karena masih dibaca RAID/ASC/SIEGE lain
-- (mis. ST2.running / ST2.inMap dipakai untuk interrupt check).
if not ST2 then
    ST2 = {
        running       = false,
        inMap         = false,
        enabled       = false,
        attackEnabled = false,
        waveCount     = 0,
        setAttackToggle = function(_v) end,
    }
end
_setST2Toggle = _setST2Toggle or function(v)
    ST2.enabled = v == true
    ST2.running = v == true
end
_visST2 = _visST2 or function(_v)
    -- tidak ada toggle visual ST2 di 2.lua — no-op
end

-- ── Transparency slider ───────────────────────────────────────────────────────
-- Implementasi nyata ada di PANEL THEME (bawah). Stub ini hanya placeholder
-- agar CollectConfig tidak crash jika ThemeTab belum diload.
if not _G then _G = {} end
_G.ThemeTransparency = _G.ThemeTransparency or 50  -- default 50
_G.CurrentTheme      = _G.CurrentTheme or "Dark"   -- default Dark
_setTransSlider    = _setTransSlider    or function(v) _G.ThemeTransparency = v end
_setTransparencyVis = _setTransparencyVis or function(v) _setTransSlider(v) end
_setThemeVis        = _setThemeVis       or function(n) _G.CurrentTheme = n end

-- ── Webhook mode dropdown stub ────────────────────────────────────────────────
-- WebhookTab di 2.lua belum punya dropdown mode (By ID / By Name).
-- Stub simpan index ke _webhookMode agar CollectConfig bisa baca kembali.
-- PENTING: urutan harus sama persis dengan MODE_KEYS di CollectConfig: {"raid","siege","both"}
local _WH_MODE_KEYS = {"raid","siege","both"}
_webhookModeSetIdx = _webhookModeSetIdx or function(idx)
    if _WH_MODE_KEYS[idx] then
        _webhookMode = _WH_MODE_KEYS[idx]
    end
end


-- ============================================================
-- PLAYER TAB: Speed Run, No Clip, Anti Idle
-- Port dari 1.lua baris 7055-7237
-- Ditaruh di PlayerTab (tab Player)
-- ============================================================

-- ── State global ─────────────────────────────────────────────
local _walkSpeedState  = 160        -- default 1000%
local _noClipState     = false
local _antiIdleState   = false
local _noClipConn      = nil        -- RBXScriptConnection RunService.Stepped
local _antiIdleThread  = nil        -- task.spawn handle
local _antiIdleStart   = nil        -- os.time() saat aktif

-- ── Pastikan FLa_PressKey tersedia (guard — mungkin sudah ada dari MA block) ──
if not FLa_PressKey then
    local _FLa_VIM = nil
    pcall(function() _FLa_VIM = game:GetService("VirtualInputManager") end)
    local _FLa_VIM_ok = false
    if _FLa_VIM then
        local testOk = pcall(function() local _ = _FLa_VIM.SendKeyEvent; return type(_) == "function" end)
        _FLa_VIM_ok = testOk
    end
    local _FLa_keypress = nil
    if type(keypress) == "function" then
        _FLa_keypress = keypress
    elseif type(keyboard) == "table" and type(keyboard.press) == "function" then
        _FLa_keypress = function(kc) keyboard.press(kc); task.wait(0.05); keyboard.release(kc) end
    end
    local _FLa_keyrelease = nil
    if type(keyrelease) == "function" then _FLa_keyrelease = keyrelease end
    local _KC_MAP = {
        [Enum.KeyCode.Space] = 0x20,
        [Enum.KeyCode.W]     = 0x57,
        [Enum.KeyCode.A]     = 0x41,
        [Enum.KeyCode.S]     = 0x53,
        [Enum.KeyCode.D]     = 0x44,
    }
    function FLa_PressKey(keyCode)
        -- Method 1: VirtualInputManager (Delta Android, Xeno, Solara)
        if _FLa_VIM_ok and _FLa_VIM then
            local ok = pcall(function()
                _FLa_VIM:SendKeyEvent(true,  keyCode, false, game)
                task.wait(0.05)
                _FLa_VIM:SendKeyEvent(false, keyCode, false, game)
            end)
            if ok then return true end
        end
        -- Method 2: keypress/keyrelease UNC (KRNL, Xeno, Solara, Synapse)
        if _FLa_keypress then
            local kc = _KC_MAP[keyCode]
            if kc then
                local ok = pcall(function()
                    _FLa_keypress(kc)
                    if _FLa_keyrelease then task.wait(0.05); _FLa_keyrelease(kc) end
                end)
                if ok then return true end
            end
        end
        -- Method 3: UserInputService fire (mobile-friendly)
        local ok3 = pcall(function()
            local UIS = game:GetService("UserInputService")
            local io  = Instance.new("InputObject")
            io.KeyCode        = keyCode
            io.UserInputType  = Enum.UserInputType.Keyboard
            io.UserInputState = Enum.UserInputState.Begin
            UIS.InputBegan:Fire(io, false)
            task.wait(0.05)
            io.UserInputState = Enum.UserInputState.End
            UIS.InputEnded:Fire(io, false)
        end)
        if ok3 then return true end
        -- Method 4: no-op fallback — tidak crash, silent
        return false
    end
end

do
    -- ── Speed Run (langsung di luar, tanpa box slide-up/down) ──────
    -- Paragraph untuk menampilkan speed saat ini
    local speedPara = PlayerTab:Paragraph({
        Title = "WalkSpeed",
        Desc  = "160 (1000%)",
    })

    local function SetSpeedValue(spd)
        spd = math.clamp(math.floor(spd), 0, 160)
        _walkSpeedState = spd
        local pct = math.floor(spd / 16 * 100)
        pcall(function() speedPara:SetDesc(spd .. " (" .. pct .. "%)") end)
        local char = LP.Character
        if char then
            local hum = char:FindFirstChild("Humanoid")
            if hum then hum.WalkSpeed = spd end
        end
    end

    -- Slider 0% - 1000% (WalkSpeed 0-160), geser bebas menggantikan tombol preset
    local speedSlider = PlayerTab:Slider({
        Flag     = "playerSpeedPct",
        Title    = "Speed (%)",
        Desc     = "Geser untuk atur WalkSpeed (0% - 1000%)",
        Value    = { Min = 0, Max = 1000, Default = 1000 },
        Step     = 10,
        Callback = function(pct)
            local spd = pct / 100 * 16 -- 100% = WalkSpeed 16 (default Roblox)
            SetSpeedValue(spd)
        end,
    })

    -- Terapkan default speed 1000% saat karakter ready
    task.spawn(function()
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum  = char:WaitForChild("Humanoid", 5)
        if hum then hum.WalkSpeed = _walkSpeedState end
    end)
    -- Pertahankan speed saat respawn
    LP.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then hum.WalkSpeed = _walkSpeedState end
    end)

    -- ── No Clip (langsung di luar, tanpa box slide-up/down) ────────
    local _noClipToggleEl = PlayerTab:Toggle({
        Flag     = "playerNoClip",
        Title    = "No Clip",
        Desc     = "Tembus tembok & objek apapun selama aktif",
        Default  = false,
        Callback = function(on)
            _noClipState = on
            -- Putus koneksi lama jika ada
            if _noClipConn then _noClipConn:Disconnect(); _noClipConn = nil end
            if on then
                -- [FLa CPU] Cache BasePart karakter, rebuild hanya saat karakter ganti
                local _ncCachedChar  = nil
                local _ncCachedParts = {}
                local _ncFrame       = 0
                local function _ncRebuildCache(char)
                    _ncCachedChar  = char
                    _ncCachedParts = {}
                    if not char then return end
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            table.insert(_ncCachedParts, part)
                        end
                    end
                end
                -- [FLa CPU] Throttle: jalan tiap 3 frame (~20fps), cukup untuk NoClip
                _noClipConn = RunService.Stepped:Connect(function()
                    _ncFrame = _ncFrame + 1
                    if _ncFrame % 3 ~= 0 then return end
                    local char = LP.Character; if not char then return end
                    -- Rebuild cache hanya saat karakter berubah
                    if char ~= _ncCachedChar then _ncRebuildCache(char) end
                    for _, part in ipairs(_ncCachedParts) do
                        if part and part.Parent and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end)
            else
                -- Restore state karakter saat NoClip dimatikan
                local char = LP.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hrp and hum then
                        local pos = hrp.CFrame
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                        task.wait(0.1)
                        hrp.CFrame = pos
                    end
                end
            end
        end,
    })

    -- Expose setter NoClip ke global (dibaca Config panel saat restore)
    _setNoClipToggle = function(v)
        _noClipState = v
        if _noClipToggleEl then pcall(function() _noClipToggleEl:Set(v) end) end
    end
    _visNoClip = function(v)
        if _noClipToggleEl then pcall(function() _noClipToggleEl:Set(v, false) end) end
    end

    -- ── Section: Anti Idle ───────────────────────────────────────
    -- Logika: bukan sekedar Anti AFK (cegah kick), tapi ANTI IDLE —
    -- simulasi aktivitas nyata agar server tidak mendeteksi player diam:
    --   1. Humanoid:Move() micro-movement setiap interval acak (180-300s)
    --   2. HumanoidRootPart CFrame micro-nudge + restore (tidak visible)
    --   3. Camera CFrame micro-rotate + restore
    --   4. Remote benign (GetRaidTeamInfos / GetCityRaidInfos) setiap 60s
    --   5. FLa_PressKey(Z) simulasi input keyboard
    --   6. CharacterController: FireServer dummy movement setiap 30s via
    --      workspace.Physics / Humanoid:SetStateEnabled toggle (paksa engine
    --      kirim network update ke server — ini yang paling efektif mencegah
    --      server-side idle detection)
    -- ── Anti Idle (langsung di luar, tanpa box slide-up/down) ──────
    -- Status paragraph dihapus agar hemat tempat -- cukup toggle saja.
    local function AntiIdleStat(msg) end -- no-op (dipanggil di banyak tempat internal, dibiarkan aman)

    local _antiIdleToggleEl = PlayerTab:Toggle({
        Flag     = "playerAntiIdle",
        Title    = "Anti Idle",
        Desc     = "Simulasi aktivitas nyata agar server tidak deteksi player diam",
        Default  = false,
        Callback = function(on)
            _antiIdleState = on
            if _antiIdleThread then
                pcall(function() task.cancel(_antiIdleThread) end)
                _antiIdleThread = nil
            end
            if on then
                _antiIdleStart  = os.time()
                _antiIdleThread = task.spawn(function()
                    local _rng           = Random.new()
                    local _lastRemote    = 0   -- tick() tracker untuk remote benign
                    local _lastNetUpdate = 0   -- tick() tracker untuk force network update
                    local RS = game:GetService("ReplicatedStorage")

                    while _antiIdleState do
                        -- Interval acak 180-300 detik antar "aksi" utama
                        local interval = 180 + _rng:NextInteger(0, 120)
                        local waited   = 0
                        while waited < interval and _antiIdleState do
                            task.wait(1); waited = waited + 1
                            -- Update status timer setiap 10 detik
                            if waited % 10 == 0 then
                                local dur = os.time() - _antiIdleStart
                                AntiIdleStat(string.format(
                                    "[ON] Active %02d:%02d:%02d | next action: %ds",
                                    math.floor(dur/3600), math.floor(dur/60)%60, dur%60,
                                    interval - waited
                                ))
                            end

                            -- [ANTI IDLE 6] Force network update setiap 30 detik:
                            -- Toggle Humanoid StateEnabled sebentar — memaksa engine
                            -- mengirim network packet ke server, server tidak anggap idle
                            local now = tick()
                            if (now - _lastNetUpdate) >= 30 then
                                _lastNetUpdate = now
                                pcall(function()
                                    local char = LP.Character; if not char then return end
                                    local hum  = char:FindFirstChildOfClass("Humanoid")
                                    if not hum or hum.Health <= 0 then return end
                                    -- Toggle state briefly — tidak visible ke player, tapi server terima update
                                    hum:SetStateEnabled(Enum.HumanoidStateType.Running, false)
                                    task.wait(0.016) -- 1 frame
                                    hum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
                                end)
                            end
                        end
                        if not _antiIdleState then break end

                        -- ── Aksi utama: simulasi aktivitas nyata ──────────────

                        pcall(function()
                            local char = LP.Character; if not char then return end
                            local hum  = char:FindFirstChildOfClass("Humanoid")
                            local hrp  = char:FindFirstChild("HumanoidRootPart")
                            if not hum or hum.Health <= 0 then return end

                            -- [ANTI IDLE 1] Humanoid:Move() micro-movement
                            pcall(function()
                                hum:Move(Vector3.new(0.001, 0, 0))
                                task.wait(0.05)
                                hum:Move(Vector3.new(0, 0, 0))
                            end)

                            -- [ANTI IDLE 2] HRP micro-nudge + restore (tidak terlihat)
                            pcall(function()
                                if hrp then
                                    local cf = hrp.CFrame
                                    local dx = (_rng:NextNumber() - 0.5) * 0.05
                                    local dz = (_rng:NextNumber() - 0.5) * 0.05
                                    hrp.CFrame = cf * CFrame.new(dx, 0, dz)
                                    task.wait(0.05)
                                    hrp.CFrame = cf
                                end
                            end)

                            task.wait(0.1)

                            -- [ANTI IDLE 3] Camera micro-rotate + restore
                            pcall(function()
                                local cam = workspace.CurrentCamera
                                if cam and cam.CameraType == Enum.CameraType.Custom then
                                    local cf = cam.CFrame
                                    cam.CFrame = cf * CFrame.Angles(0, 0.0001 * (_rng:NextNumber() - 0.5), 0)
                                    task.wait(0.05)
                                    cam.CFrame = cf
                                end
                            end)

                            task.wait(0.05)

                            -- [ANTI IDLE 4] Remote benign setiap 60 detik
                            pcall(function()
                                local now = tick()
                                if (now - _lastRemote) >= 60 then
                                    _lastRemote = now
                                    local Remotes = RS:FindFirstChild("Remotes")
                                    if Remotes then
                                        local safe = Remotes:FindFirstChild("GetRaidTeamInfos")
                                                  or Remotes:FindFirstChild("GetCityRaidInfos")
                                        if safe then pcall(function() safe:InvokeServer() end) end
                                    end
                                end
                            end)

                            -- [ANTI IDLE 5] Simulasi tekan Z via FLa_PressKey
                            pcall(function()
                                FLa_PressKey(Enum.KeyCode.Z)
                            end)
                        end)

                        AntiIdleStat("[ON] Aksi anti-idle dieksekusi!")
                    end -- end while

                    _antiIdleThread = nil
                    AntiIdleStat("Idle - Toggle OFF")
                end)
            else
                _antiIdleStart = nil
                AntiIdleStat("Idle - Enable untuk START")
            end
        end,
    })

    -- Expose setter Anti Idle ke global (dibaca Config panel saat restore)
    _setAntiAfkToggle = function(v)
        _antiIdleState = v
        if _antiIdleToggleEl then pcall(function() _antiIdleToggleEl:Set(v) end) end
    end
    _visAntiAfk = function(v)
        if _antiIdleToggleEl then pcall(function() _antiIdleToggleEl:Set(v, false) end) end
    end

    -- Expose setter WalkSpeed ke global (dibaca Config panel saat restore)
    _setSpeedSlider = function(v)
        pcall(function() SetSpeedValue(v) end)
        pcall(function() speedSlider:Set(math.floor(v / 16 * 100)) end)
    end

    -- ── Fly (langsung di luar, tanpa box slide-up/down) ────────────
    -- [FIX MOBILE] Sebelumnya gerak horizontal dibaca dari UserInputService
    -- KeyCode W/A/S/D -- itu CUMA kepicu dari keyboard fisik. Di executor
    -- mobile (Delta dkk) gerak pakai thumbstick layar yang TIDAK PERNAH
    -- mengirim event KeyCode, jadi _flyKeys selalu false -> BodyVelocity
    -- selalu nol -> karakter cuma diam ngambang (PlatformStand nyala tapi
    -- gak ada velocity). Sekarang horizontal dibaca dari Humanoid.MoveDirection
    -- yang otomatis ke-update dari WASD (PC), thumbstick (mobile), maupun
    -- gamepad -- jadi cross-platform tanpa perlu deteksi device manual.
    -- Untuk naik/turun ditambah 2 tombol layar (▲/▼) karena Space/Shift
    -- juga gak ada di mobile; Space/Shift tetap dipertahankan untuk PC.
    local UserInputService = game:GetService("UserInputService")

    local _flyState    = false
    local _flySpeed    = 50          -- studs/detik, default
    local _flyConn      = nil        -- RunService.RenderStepped connection
    local _flyBV        = nil        -- BodyVelocity dipasang di HumanoidRootPart
    local _flyGyro       = nil       -- BodyGyro biar orientasi ngikut kamera
    local _flyKeys      = {Space=false, Shift=false}  -- vertical only (PC keyboard)
    local _flyTouchUp   = false      -- vertical via tombol layar (semua platform)
    local _flyTouchDown = false

    -- ── Tombol layar Up/Down (touch & mouse, jadi jalan di semua platform) ──
    local _flyGui = Instance.new("ScreenGui")
    _flyGui.Name = "FlaFlyControls"
    _flyGui.ResetOnSpawn = false
    _flyGui.IgnoreGuiInset = true
    _flyGui.Enabled = false
    _flyGui.DisplayOrder = 999
    pcall(function()
        _flyGui.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")
    end)

    local function _makeFlyBtn(label, yOffset)
        local btn = Instance.new("TextButton")
        btn.Name = "Fly" .. label
        btn.Size = UDim2.new(0, 64, 0, 64)
        btn.Position = UDim2.new(1, -84, 1, yOffset)
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
        btn.BackgroundTransparency = 0.25
        btn.BorderSizePixel = 0
        btn.Text = label
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextScaled = true
        btn.Font = Enum.Font.GothamBold
        btn.AutoButtonColor = false
        btn.Parent = _flyGui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = btn
        return btn
    end

    local _flyBtnUp   = _makeFlyBtn("▲", -164)
    local _flyBtnDown = _makeFlyBtn("▼", -90)

    local function _flyBtnBind(btn, setFn)
        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1 then
                setFn(true)
            end
        end)
        btn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1 then
                setFn(false)
            end
        end)
    end
    _flyBtnBind(_flyBtnUp,   function(v) _flyTouchUp = v end)
    _flyBtnBind(_flyBtnDown, function(v) _flyTouchDown = v end)

    local function _flyCleanup()
        if _flyConn then _flyConn:Disconnect(); _flyConn = nil end
        if _flyBV then _flyBV:Destroy(); _flyBV = nil end
        if _flyGyro then _flyGyro:Destroy(); _flyGyro = nil end
        _flyTouchUp, _flyTouchDown = false, false
        pcall(function() _flyGui.Enabled = false end)
        local char = LP.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end
    end

    local function StartFly()
        local char = LP.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then return end

        _flyCleanup() -- pastikan bersih sebelum pasang ulang

        hum.PlatformStand = true
        pcall(function() _flyGui.Enabled = true end)

        _flyBV = Instance.new("BodyVelocity")
        _flyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        _flyBV.Velocity = Vector3.new(0, 0, 0)
        _flyBV.Parent = hrp

        _flyGyro = Instance.new("BodyGyro")
        _flyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        _flyGyro.P = 3000
        _flyGyro.CFrame = hrp.CFrame
        _flyGyro.Parent = hrp

        local camera = workspace.CurrentCamera

        _flyConn = RunService.RenderStepped:Connect(function()
            if not _flyState then return end
            local c = LP.Character
            local h = c and c:FindFirstChild("HumanoidRootPart")
            local humNow = c and c:FindFirstChildOfClass("Humanoid")
            if not h or not _flyBV or not humNow then return end

            local camCF = camera.CFrame
            local moveDir = Vector3.new(0, 0, 0)

            -- [FIX] Horizontal: pakai MoveDirection Humanoid, bukan KeyCode
            -- mentah -- otomatis kebaca dari WASD (PC), thumbstick (mobile),
            -- ATAU gamepad, arahnya sudah relatif kamera secara otomatis.
            local md = humNow.MoveDirection
            if md.Magnitude > 0.01 then
                moveDir = moveDir + Vector3.new(md.X, 0, md.Z)
            end

            -- Vertical: keyboard (PC) ATAU tombol layar (semua platform)
            if _flyKeys.Space or _flyTouchUp   then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if _flyKeys.Shift or _flyTouchDown then moveDir = moveDir - Vector3.new(0, 1, 0) end

            if moveDir.Magnitude > 0 then
                moveDir = moveDir.Unit
            end

            _flyBV.Velocity = moveDir * _flySpeed
            _flyGyro.CFrame = camCF
        end)
    end

    local function StopFly()
        _flyCleanup()
    end

    -- Space/Shift tetap ada buat kenyamanan naik/turun di PC (opsional,
    -- gak dipakai di mobile tapi gak ganggu -- gak akan fire di mobile).
    local _flyKeyDownConn = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe or not _flyState then return end
        if input.KeyCode == Enum.KeyCode.Space then _flyKeys.Space = true
        elseif input.KeyCode == Enum.KeyCode.LeftShift then _flyKeys.Shift = true
        end
    end)
    local _flyKeyUpConn = UserInputService.InputEnded:Connect(function(input, gpe)
        if input.KeyCode == Enum.KeyCode.Space then _flyKeys.Space = false
        elseif input.KeyCode == Enum.KeyCode.LeftShift then _flyKeys.Shift = false
        end
    end)

    local _flyToggleEl = PlayerTab:Toggle({
        Flag     = "playerFly",
        Title    = "Fly",
        Desc     = "Terbang bebas -- gerak pakai W/A/S/D, naik Space, turun Shift",
        Default  = false,
        Callback = function(on)
            _flyState = on
            if on then
                StartFly()
            else
                for k in pairs(_flyKeys) do _flyKeys[k] = false end
                StopFly()
            end
        end,
    })

    -- Slider speed Fly (studs/detik), pola sama seperti Speed Run
    local _flySpeedSlider = PlayerTab:Slider({
        Flag     = "playerFlySpeed",
        Title    = "Fly Speed",
        Desc     = "Geser untuk atur kecepatan terbang (studs/detik)",
        Value    = { Min = 10, Max = 300, Default = 50 },
        Step     = 10,
        Callback = function(val)
            _flySpeed = math.clamp(math.floor(val), 10, 300)
        end,
    })

    -- Pastikan Fly mati bersih & restart otomatis saat karakter respawn
    LP.CharacterAdded:Connect(function()
        _flyCleanup()
        if _flyState then
            task.wait(1) -- kasih waktu HumanoidRootPart siap
            StartFly()
        end
    end)

    -- Expose setter Fly ke global (dibaca Config panel saat restore)
    _setFlyToggle = function(v)
        _flyState = v
        if _flyToggleEl then pcall(function() _flyToggleEl:Set(v) end) end
    end
    _visFly = function(v)
        if _flyToggleEl then pcall(function() _flyToggleEl:Set(v, false) end) end
    end
    _setFlySpeedSlider = function(v)
        _flySpeed = math.clamp(math.floor(v), 10, 300)
        if _flySpeedSlider then pcall(function() _flySpeedSlider:Set(_flySpeed) end) end
    end

    -- ── ESP Player Name (langsung di luar, tanpa box slide-up/down) ─
    local _espState    = false
    local _espTags     = {} -- [Player] = BillboardGui
    local ESP_COLOR    = Color3.fromRGB(255, 0, 0) -- merah

    local function _espRemoveTag(plr)
        local tag = _espTags[plr]
        if tag then
            pcall(function() tag:Destroy() end)
            _espTags[plr] = nil
        end
    end

    local function _espAddTag(plr)
        if plr == LP then return end -- jangan tampilkan diri sendiri
        if _espTags[plr] then return end

        local function attach(char)
            if not _espState then return end
            local head = char:WaitForChild("Head", 5)
            if not head then return end

            local bill = Instance.new("BillboardGui")
            bill.Name             = "FLa_ESP_NameTag"
            bill.Adornee          = head
            bill.Size             = UDim2.new(0, 160, 0, 30)
            bill.StudsOffset      = Vector3.new(0, 2.2, 0)
            bill.AlwaysOnTop      = true
            bill.MaxDistance      = 1000

            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.Size          = UDim2.new(1, 0, 1, 0)
            label.Font          = Enum.Font.GothamBold
            label.Text           = plr.Name
            label.TextColor3    = ESP_COLOR
            label.TextStrokeTransparency = 0
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.TextScaled    = true
            label.Parent          = bill

            bill.Parent = head
            _espTags[plr] = bill
        end

        if plr.Character then attach(plr.Character) end
        plr.CharacterAdded:Connect(function(char)
            _espRemoveTag(plr)
            if _espState then attach(char) end
        end)
    end

    local function EnableESP()
        for _, plr in ipairs(Players:GetPlayers()) do
            _espAddTag(plr)
        end
    end

    local function DisableESP()
        for plr, _ in pairs(_espTags) do
            _espRemoveTag(plr)
        end
    end

    Players.PlayerAdded:Connect(function(plr)
        if _espState then _espAddTag(plr) end
    end)
    Players.PlayerRemoving:Connect(function(plr)
        _espRemoveTag(plr)
    end)

    local _espToggleEl = PlayerTab:Toggle({
        Flag     = "playerESP",
        Title    = "ESP Player Name",
        Desc     = "Tampilkan nama semua player (warna merah) tembus tembok",
        Default  = false,
        Callback = function(on)
            _espState = on
            if on then EnableESP() else DisableESP() end
        end,
    })

    -- Expose setter ESP ke global (dibaca Config panel saat restore)
    _setESPToggle = function(v)
        _espState = v
        if _espToggleEl then pcall(function() _espToggleEl:Set(v) end) end
    end
    _visESP = function(v)
        if _espToggleEl then pcall(function() _espToggleEl:Set(v, false) end) end
    end

end -- do Player Tab



-- ============================================================================
-- HERO FASTROLL - WindUI Native API
-- Slide Up/Down: Section({ Opened=false, Box=true }) persis AutomationTab
-- GUID BUG FIX: spy intercept RandomHeroQuirk + HeroUseSkill, capture
--               arg1.heroGuid SEBELUM check _ourCall (manual reroll bukan ourCall)
-- ============================================================================

-- ── DATA: QUIRK LIST PER SLOT (persis 1.lua baris 3086-3120) ─────────────────
QUIRK_LIST_PER_SLOT = QUIRK_LIST_PER_SLOT or {
    {   -- Slot 1 (drawId=920001)
        {id=99013, name="Midas Touch"},
        {id=99014, name="Hyper Sprint"},
        {id=99015, name="Time Skipper"},
        {id=99016, name="Cosmic Luck"},
        {id=99017, name="Destiny Rewrite"},
        {id=99018, name="Final Judgment"},
        {id=99109, name="Golden Era"},
        {id=99110, name="The Chosen Singularity"},
        {id=99111, name="Axiom of Value"},
    },
    {   -- Slot 2 (drawId=920002)
        {id=99031, name="Resource Conqueror"},
        {id=99032, name="Elemental Overload"},
        {id=99033, name="Crimson Executioner"},
        {id=99034, name="God's Gift"},
        {id=99035, name="Apocalypse Carnival"},
        {id=99036, name="Divine Judgment"},
        {id=99112, name="Celestial Benediction"},
        {id=99113, name="Eclipse Masquerade"},
        {id=99114, name="Sovereign Verdict"},
    },
    {   -- Slot 3 (drawId=920003)
        {id=99049, name="Slayer's Instinct"},
        {id=99050, name="Harbinger of Ruin"},
        {id=99052, name="Godslayer's Fury"},
        {id=99053, name="Deicide's Endgame"},
        {id=99054, name="Final Arbiter"},
        {id=99115, name="Cosmic Cataclysm"},
        {id=99116, name="Omega Oblivion"},
        {id=99117, name="Sovereign Axiom"},
    },
}
MAX_PER_SLOT = math.huge

QUIRK_MAP = QUIRK_MAP or {}
for _, _ql in ipairs(QUIRK_LIST_PER_SLOT) do
    for _, _qq in ipairs(_ql) do QUIRK_MAP[_qq.id] = _qq.name end
end

-- ── GLOBALS ──────────────────────────────────────────────────────────────────
_HR_RPT            = _HR_RPT            or nil
_ourCall           = _ourCall           or false
DoAutoRollHero     = DoAutoRollHero     or nil
_setHeroRollToggle = _setHeroRollToggle or nil
_setHeroX100Toggle = _setHeroX100Toggle or nil
_layer0Active      = _layer0Active      or false
-- Weapon Fastroll globals
_WR_RPT              = _WR_RPT              or nil
DoAutoRollWeapon     = DoAutoRollWeapon     or nil
_setWeaponRollToggle = _setWeaponRollToggle or nil
_setWeaponX100Toggle = _setWeaponX100Toggle or nil

-- Pet Gear Fastroll globals
_PGR_RPT             = _PGR_RPT             or nil
DoAutoRollPetGear    = DoAutoRollPetGear    or nil
_setPetGearRollToggle= _setPetGearRollToggle or nil
_setPetGearX100Toggle= _setPetGearX100Toggle or nil
StartPG100Loop       = StartPG100Loop       or nil
StopPG100            = StopPG100            or nil

-- PG_GRADES_PER_MACHINE (confirmed DEX - includes GM/MM/M++)
-- R-Pet (980001): 990001-990010 + 990031 + 990032(GM) + 990033(MM) + 990034(M++)
-- Y-Pet (980002): 990011-990020 + 990041 + 990042(GM) + 990043(MM) + 990044(M++)
-- B-Pet (980003): 990021-990030 + 990051 + 990052(GM) + 990053(MM) + 990054(M++)
PG_DRAW_IDS = PG_DRAW_IDS or {980001, 980002, 980003}
PG_MACHINE_NAMES = PG_MACHINE_NAMES or {"R-Pet Gear", "Y-Pet Gear", "B-Pet Gear"}
PG_GRADES_PER_MACHINE = {  -- selalu overwrite agar grade baru selalu masuk
    -- [1] R-Pet Gear (drawId 980001)
    {
        {id=990001, name="E"}, {id=990002, name="D"}, {id=990003, name="C"},
        {id=990004, name="B"}, {id=990005, name="A"}, {id=990006, name="S"},
        {id=990007, name="SS"}, {id=990008, name="G"}, {id=990009, name="N"},
        {id=990010, name="M"}, {id=990031, name="M+"},
        {id=990032, name="GM"}, {id=990033, name="MM"}, {id=990034, name="M++"},
    },
    -- [2] Y-Pet Gear (drawId 980002)
    {
        {id=990011, name="E"}, {id=990012, name="D"}, {id=990013, name="C"},
        {id=990014, name="B"}, {id=990015, name="A"}, {id=990016, name="S"},
        {id=990017, name="SS"}, {id=990018, name="G"}, {id=990019, name="N"},
        {id=990020, name="M"}, {id=990041, name="M+"},
        {id=990042, name="GM"}, {id=990043, name="MM"}, {id=990044, name="M++"},
    },
    -- [3] B-Pet Gear (drawId 980003)
    {
        {id=990021, name="E"}, {id=990022, name="D"}, {id=990023, name="C"},
        {id=990024, name="B"}, {id=990025, name="A"}, {id=990026, name="S"},
        {id=990027, name="SS"}, {id=990028, name="G"}, {id=990029, name="N"},
        {id=990030, name="M"}, {id=990051, name="M+"},
        {id=990052, name="GM"}, {id=990053, name="MM"}, {id=990054, name="M++"},
    },
}
PG_GRADE_MAP = {}  -- [FIX] selalu overwrite, rebuild dari PG_GRADES_PER_MACHINE
for _, _pgl in ipairs(PG_GRADES_PER_MACHINE) do
    for _, _pgg in ipairs(_pgl) do PG_GRADE_MAP[_pgg.id] = _pgg.name end
end

-- W_QUIRK_LIST_PER_SLOT (dari 1.lua baris 3131)
W_QUIRK_LIST_PER_SLOT = W_QUIRK_LIST_PER_SLOT or {
    -- Slot 1
    {
        {id=99067,name="Celestial Onslaught"},
        {id=99068,name="Lucky Scavenger"},
        {id=99069,name="Titan's Wrath"},
        {id=99070,name="Omnipotent Benefactor"},
        {id=99071,name="Archangel's Judgment"},
        {id=99072,name="Avatar of Destruction"},
        {id=99118,name="Eternal Sovereign"},
        {id=99119,name="Seraphic Verdict"},
        {id=99120,name="Doombringer Ascendant"},
    },
    -- Slot 2
    {
        {id=99085,name="Celestial Onslaught"},
        {id=99086,name="Lucky Scavenger"},
        {id=99087,name="Titan's Wrath"},
        {id=99088,name="Omnipotent Benefactor"},
        {id=99089,name="Archangel's Judgment"},
        {id=99090,name="Avatar of Destruction"},
        {id=99121,name="Eternal Sovereign"},
        {id=99122,name="Seraphic Verdict"},
        {id=99123,name="Doombringer Ascendant"},
    },
    -- Slot 3
    {
        {id=99103,name="Celestial Onslaught"},
        {id=99104,name="Lucky Scavenger"},
        {id=99105,name="Titan's Wrath"},
        {id=99106,name="Omnipotent Benefactor"},
        {id=99107,name="Archangel's Judgment"},
        {id=99108,name="Avatar of Destruction"},
        {id=99124,name="Eternal Sovereign"},
        {id=99125,name="Seraphic Verdict"},
        {id=99126,name="Doombringer Ascendant"},
    },
}
W_MAX_PER_SLOT = math.huge  -- tidak ada batasan jumlah target
W_QUIRK_MAP = W_QUIRK_MAP or {}
for _, _wl in ipairs(W_QUIRK_LIST_PER_SLOT) do
    for _, _wq in ipairs(_wl) do W_QUIRK_MAP[_wq.id] = _wq.name end
end

if not FLa_CanHook then
    FLa_CanHook = function()
        return type(getrawmetatable)    == "function"
            and type(setreadonly)       == "function"
            and type(newcclosure)       == "function"
            and type(getnamecallmethod) == "function"
    end
end

-- ============================================================================
-- PANEL: CONFIG
-- Diconvert dari 1.lua: PANEL CONFIG (baris 20199-21362)
-- Ditulis ulang pakai WindUI native API (ConfigTab:Section/Paragraph/Button)
-- Karena WindUI tidak punya TextBox native yang bisa di-embed bebas,
-- UI sub-panel (save/load/delete) dibangun via Frame + Instance Roblox biasa
-- yang di-parent ke dalam sebuah WindUI "host frame" via ConfigTab:Custom()
-- atau diletakkan langsung di bawah ConfigTab's ScrollingFrame via Parent inject.
-- ============================================================================
do

    -- ─── CONFIG FILE PATH ────────────────────────────────────────────────────
    local CONFIG_FOLDER = "FLaConfigs"

    -- Helper: pastikan folder ada (aman di semua executor via polyfill)
    local function _ensureFolder()
        local ok, exists = pcall(isfolder, CONFIG_FOLDER)
        if not ok or not exists then
            pcall(makefolder, CONFIG_FOLDER)
        end
    end

    local function _cfgPath(name)
        return CONFIG_FOLDER .. "/" .. name .. ".json"
    end

    local function ListConfigs()
        _ensureFolder()
        local ok, files = pcall(listfiles, CONFIG_FOLDER)
        if not ok or type(files) ~= "table" then return {} end
        local names = {}
        for _, f in ipairs(files) do
            local n = tostring(f):match("([^/\\]+)%.json$")
            if n and n ~= "" then table.insert(names, n) end
        end
        table.sort(names)
        return names
    end

    -- ─── JSON ENCODE / DECODE MINIMAL (Luau tanpa loadstring) ────────────────
    local function jsonEncode(t, indent)
        indent = indent or 0
        local pad  = string.rep(" ", indent)
        local padI = string.rep(" ", indent + 2)
        if type(t) == "boolean" then return t and "true" or "false" end
        if type(t) == "number"  then return tostring(t) end
        if type(t) == "string"  then
            local s = t:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n"):gsub("\r","\\r")
            return '"' .. s .. '"'
        end
        if type(t) ~= "table" then return '"[unsupported]"' end
        local isArr = true; local n = 0
        for k in pairs(t) do n = n + 1; if type(k) ~= "number" then isArr = false; break end end
        if isArr and n == 0 then return "[]" end
        if isArr then
            local parts = {}
            for i = 1, #t do parts[i] = padI .. jsonEncode(t[i], indent + 2) end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        else
            local parts = {}
            for k, v in pairs(t) do
                if type(k) == "string" or type(k) == "number" then
                    table.insert(parts, padI .. '"' .. tostring(k) .. '": ' .. jsonEncode(v, indent + 2))
                end
            end
            table.sort(parts)
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        end
    end

    local function jsonDecodeVal(s, pos)
        while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
        local c = s:sub(pos, pos)
        if c == '"' then
            local i = pos + 1; local res = {}
            while i <= #s do
                local ch = s:sub(i, i)
                if ch == '"' then return table.concat(res), i + 1 end
                if ch == '\\' then
                    local nx = s:sub(i + 1, i + 1)
                    if     nx == '"'  then table.insert(res, '"')
                    elseif nx == '\\' then table.insert(res, '\\')
                    elseif nx == 'n'  then table.insert(res, '\n')
                    elseif nx == 'r'  then table.insert(res, '\r')
                    else                   table.insert(res, nx) end
                    i = i + 2
                else
                    table.insert(res, ch); i = i + 1
                end
            end
            return "", pos
        end
        if c == '{' then
            local obj = {}; pos = pos + 1
            while pos <= #s do
                while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
                if s:sub(pos, pos) == '}' then return obj, pos + 1 end
                if s:sub(pos, pos) == ',' then pos = pos + 1 end
                while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
                local key, p2 = jsonDecodeVal(s, pos); pos = p2
                while pos <= #s and s:sub(pos, pos):match("[%s:]") do pos = pos + 1 end
                local val, p3 = jsonDecodeVal(s, pos); pos = p3
                obj[key] = val
            end
            return obj, pos
        end
        if c == '[' then
            local arr = {}; pos = pos + 1
            while pos <= #s do
                while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
                if s:sub(pos, pos) == ']' then return arr, pos + 1 end
                if s:sub(pos, pos) == ',' then pos = pos + 1 end
                local val, p2 = jsonDecodeVal(s, pos); pos = p2
                table.insert(arr, val)
            end
            return arr, pos
        end
        if s:sub(pos, pos + 3) == "true"  then return true,  pos + 4 end
        if s:sub(pos, pos + 4) == "false" then return false, pos + 5 end
        if s:sub(pos, pos + 3) == "null"  then return nil,   pos + 4 end
        local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
        if num then return tonumber(num), pos + #num end
        return nil, pos + 1
    end

    local function jsonDecode(s)
        local ok, val = pcall(function()
            local v, _ = jsonDecodeVal(s, 1)
            return v
        end)
        if ok then return val else return nil end
    end

    -- ─── COLLECT CONFIG STATE (snapshot semua state aktif saat ini) ──────────
    local function CollectConfig()
        local cfg = {}

        -- ── MAIN TAB ──────────────────────────────────────────────────────
        cfg.sellHeroOn        = _autoSellOnState or false
        cfg.autoCollectOn     = _autoCollectState or false
        cfg.sellWeaponOn      = _autoSellWeaponState or false
        cfg.swSelectAll       = _swSelectAllRef and _swSelectAllRef() or true
        cfg.swSelectedIds     = {}
        cfg.swSelNames        = {}
        if _swSelectedIdsGlobal then
            for k, v in pairs(_swSelectedIdsGlobal) do if v then cfg.swSelectedIds[tostring(k)] = true end end
        end
        if _swSelNamesGlobal then
            for k, v in pairs(_swSelNamesGlobal) do cfg.swSelNames[tostring(k)] = v end
        end
        cfg.decompGemOn       = _autoDecompGemState or false
        cfg.gemMinLevel       = _gemMinLevelState or 1
        cfg.gemMaxLevel       = _gemMaxLevelState or 1

        -- ── HIDE TAB ──────────────────────────────────────────────────────
        cfg.hideRerollChat    = _hideRerollChatState or false
        cfg.hideAllUI         = _hideAllUIState or false
        cfg.hideAllAnim       = _hideAllAnimState or false

        -- ── FARM TAB ──────────────────────────────────────────────────────
        cfg.randomAttackOn    = _raRunningState or false

        -- ── ATTACK TAB ────────────────────────────────────────────────────
        cfg.hideReward        = _hideRewardState or false
        cfg.massAttackOn      = MA and MA.running or false
        cfg.killDDIdx         = _killDDIdxState or 1
        cfg.delayDDIdx        = _delayDDIdxState or 2
        cfg.maMapSel          = {}
        if _maMapSelState then
            for k, v in pairs(_maMapSelState) do if v then cfg.maMapSel[tostring(k)] = true end end
        end
        cfg.skillZ = SKL and SKL.Z and SKL.Z.on or false
        cfg.skillX = SKL and SKL.X and SKL.X.on or false
        cfg.skillC = SKL and SKL.C and SKL.C.on or false
        cfg.skillV = SKL and SKL.V and SKL.V.on or false
        cfg.skillF = SKL and SKL.F and SKL.F.on or false

        -- ── PLAYER TAB ────────────────────────────────────────────────────
        cfg.noClipOn      = _noClipState or false
        cfg.antiAfkOn     = _antiIdleState or false
        cfg.walkSpeed     = _walkSpeedState or 16

        -- ── AUTOMATION TAB ────────────────────────────────────────────────
        cfg.raidOn        = _raidOn or false
        cfg.raidPMIdx     = 1
        cfg.raidPreferMaps  = {}
        cfg.raidRuneGrades  = {}
        cfg.raidRuneEnabled   = RAID and RAID.runeEnabled or false
        cfg.raidRuneMapTarget = RAID and RAID.runeMapTarget or 0
        cfg.raidListEnabled   = RAID and RAID.listEnabled or false
        cfg.raidAutoKillBoss  = RAID and RAID.autoKillBoss or false
        cfg.raidBossDelay     = RAID and RAID.bossDelay or 3
        cfg.raidListEntries   = {}
        if RAID and RAID.listEntries then
            for i, ent in ipairs(RAID.listEntries) do
                local saveMaps = {}; local saveRanks = {}
                if ent.maps  then for mn, v in pairs(ent.maps)  do if v then saveMaps[tostring(mn)] = true end end end
                if ent.ranks then for g,  v in pairs(ent.ranks) do if v then saveRanks[g] = true end end end
                cfg.raidListEntries[i] = { maps = saveMaps, ranks = saveRanks }
            end
        end
        if RAID and RAID.preferMaps then
            for k, v in pairs(RAID.preferMaps) do if v then cfg.raidPreferMaps[tostring(k)] = true end end
        end
        if RAID and RAID.runeGrades then
            for k, v in pairs(RAID.runeGrades) do if v then cfg.raidRuneGrades[tostring(k)] = true end end
        end
        pcall(function()
            local PM_KEYS = {"default","byrank","bymap","hard","easy","manual"}
            for i, k in ipairs(PM_KEYS) do if RAID and k == RAID.pickMode then cfg.raidPMIdx = i; break end end
        end)

        cfg.ascOn        = _ascOn or false
        cfg.ascPMIdx     = 1
        cfg.ascPreferMaps= {}
        cfg.ascRuneGrades= {}
        cfg.ascRuneEnabled    = ASC and ASC.runeEnabled or false
        cfg.ascRuneMapTarget  = ASC and ASC.runeMapTarget or 0
        cfg.ascPreferMapTarget= ASC and ASC.preferMapTarget or 0
        cfg.ascAutoKillBoss   = ASC and ASC.autoKillBoss or false
        cfg.ascBossDelay      = ASC and ASC.bossDelay or 3
        if ASC and ASC.preferMaps then
            for k, v in pairs(ASC.preferMaps) do if v then cfg.ascPreferMaps[tostring(k)] = true end end
        end
        if ASC and ASC.runeGrades then
            for k, v in pairs(ASC.runeGrades) do if v then cfg.ascRuneGrades[tostring(k)] = true end end
        end
        pcall(function()
            local APM_KEYS = {"default","byrank","bymap","hard","easy","manual"}
            for i, k in ipairs(APM_KEYS) do if ASC and k == ASC.pickMode then cfg.ascPMIdx = i; break end end
        end)
        cfg.ascListEnabled = ASC and ASC.listEnabled or false
        cfg.ascListEntries = {}
        if ASC and ASC.listEntries then
            for i, ent in ipairs(ASC.listEntries) do
                local saveMaps = {}; local saveRanks = {}
                for k, v in pairs(ent.maps)  do if v then saveMaps[tostring(k)] = true end end
                for k, v in pairs(ent.ranks) do if v then saveRanks[tostring(k)] = true end end
                cfg.ascListEntries[i] = { maps = saveMaps, ranks = saveRanks }
            end
        end

        cfg.siegeOn      = _siegeToggleState or false
        cfg.siegeExclude = {}
        if SIEGE and SIEGE.excludeMaps then
            for k, v in pairs(SIEGE.excludeMaps) do cfg.siegeExclude[tostring(k)] = v end
        end

        cfg.dungeonOn    = _dungeonToggleState or false

        cfg.st2On        = ST2 and ST2.enabled or false
        cfg.st2AttackOn  = ST2 and ST2.attackEnabled or false
        cfg.st2WaveCount = ST2 and ST2.waveCount or 0

        -- ── REROLL TAB ────────────────────────────────────────────────────
        -- Hero Fastroll
        cfg.heroRollOn   = _HR_RPT and _HR_RPT.running or false
        cfg.heroX100On   = _HR_RPT and _HR_RPT.x100 or false
        cfg.heroSlotTarget = {{},{},{}}
        if _HR_RPT and _HR_RPT.slotTarget then
            for si = 1, 3 do
                for qid, v in pairs(_HR_RPT.slotTarget[si]) do
                    if v then cfg.heroSlotTarget[si][tostring(qid)] = true end
                end
            end
        end
        -- Weapon Fastroll
        cfg.weaponRollOn = _WR_RPT and _WR_RPT.running or false
        cfg.weaponX100On = _WR_RPT and _WR_RPT.x100 or false
        cfg.weaponSlotTarget = {{},{},{}}
        if _WR_RPT and _WR_RPT.slotTarget then
            for si = 1, 3 do
                for qid, v in pairs(_WR_RPT.slotTarget[si]) do
                    if v then cfg.weaponSlotTarget[si][tostring(qid)] = true end
                end
            end
        end
        -- PetGear
        cfg.pgrOn      = {false, false, false}
        cfg.pgr100On   = {false, false, false}
        cfg.pgrTargets = {{},{},{}}
        if PGR then
            for i = 1, 3 do
                cfg.pgrOn[i]  = PGR.enOnFlags[i] or false
                cfg.pgr100On[i] = PGR100 and PGR100.enOnFlags[i] or false
                for gid, v in pairs(PGR.targets[i]) do
                    if v then cfg.pgrTargets[i][tostring(gid)] = true end
                end
            end
        end
        -- Halo
        cfg.haloOn = {false, false, false}
        if HALO then
            for i = 1, 3 do cfg.haloOn[i] = HALO.enOnFlags[i] or false end
        end
        -- Ornament
        cfg.ornOn      = {}
        cfg.ornTargets = {}
        if ORN then
            local nm = #_ASH_ORN.MACHINES
            for i = 1, nm do
                cfg.ornOn[i]      = ORN.enOnFlags[i] or false
                cfg.ornTargets[i] = {}
                for qid, v in pairs(ORN.targets[i]) do
                    if v then cfg.ornTargets[i][tostring(qid)] = true end
                end
            end
        end
        -- Merge & Use Potion
        cfg.mergeOn = _mergeRunningState or false
        cfg.useOn   = _useRunningState or false

        -- ── SETTINGS / WEBHOOK TAB ────────────────────────────────────────
        cfg.webhookEnabled  = _webhookEnabled or false
        cfg.webhookUrl      = _webhookUrl or ""
        cfg.webhookMode     = _webhookMode or "both"
        cfg.webhookModeIdx  = 3
        pcall(function()
            local MODE_KEYS = {"raid","siege","both"}
            for i, k in ipairs(MODE_KEYS) do
                if k == (_webhookMode or "both") then cfg.webhookModeIdx = i; break end
            end
        end)

        -- ── WHATSAPP NOTIF ────────────────────────────────────────────────
        cfg.waEnabled      = _waEnabled or false
        cfg.waTargetNumber = _waTargetNumber or ""

        -- ── THEME ─────────────────────────────────────────────────────────
        cfg.themeTransparency = _G.ThemeTransparency or 50   -- default 50
        cfg.themeName         = _G.CurrentTheme or "Dark"

        return cfg
    end

    -- ─── SAVE CONFIG ─────────────────────────────────────────────────────────
    local function SaveConfigAs(name)
        _ensureFolder()
        local ok, err = pcall(function()
            local cfg = CollectConfig()
            writefile(_cfgPath(name), jsonEncode(cfg))
        end)
        return ok, err
    end

    -- ─── APPLY CONFIG (restore semua state + visual) ─────────────────────────
    local function ApplyConfig(cfg)
        if type(cfg) ~= "table" then return false end

        -- ── ATURAN PANGGILAN ──────────────────────────────────────────────
        -- Setiap setter (_setXxx) sudah memanggil:
        --   1. logika backend (start/stop loop, flag)
        --   2. el:Set(v)  →  trigger Callback WindUI + sync visual
        -- _visXxx TIDAK dipanggil lagi untuk toggle yang setter-nya sudah
        -- lengkap — agar tidak double-fire callback + logika.
        -- _visXxx hanya dipakai di tempat yang MEMANG butuh visual-only
        -- (label refresh, sub-toggle boss, dll).
        -- -----------------------------------------------------------------

        -- ── MAIN TAB ──────────────────────────────────────────────────────
        pcall(function()
            -- setter panggil el:Set(v) -> callback -> logika+visual ✓
            if _setSellHeroToggle    then _setSellHeroToggle(cfg.sellHeroOn == true) end
            if _setAutoCollectToggle then _setAutoCollectToggle(cfg.autoCollectOn == true) end
            if _swRestoreFromConfig then
                local isAll = cfg.swSelectAll ~= false
                _swRestoreFromConfig(isAll, cfg.swSelectedIds, cfg.swSelNames)
            end
            if _autoSellWeaponSet then _autoSellWeaponSet(cfg.sellWeaponOn == true) end
            -- internal guard (v==state), el:Set(v) ✓
            if _autoDecompGemSet then _autoDecompGemSet(cfg.decompGemOn == true) end
            if _setGemLevelRange and cfg.gemMinLevel and cfg.gemMaxLevel then
                _setGemLevelRange(cfg.gemMinLevel, cfg.gemMaxLevel)
            end
        end)

        -- ── HIDE TAB ──────────────────────────────────────────────────────
        -- Delay 0.3s agar PlayerGui sudah stabil sebelum hook dipasang
        task.delay(0.3, function()
            pcall(function()
                -- ApplyHideReroll(v) + _hrcrToggle:Set(v) — tidak perlu _vis* ✓
                if _setHideRerollChat then _setHideRerollChat(cfg.hideRerollChat == true) end
            end)
            pcall(function()
                if _setHideAllUI   then _setHideAllUI(cfg.hideAllUI == true) end
            end)
            pcall(function()
                if _setHideAllAnim then _setHideAllAnim(cfg.hideAllAnim == true) end
            end)
        end)

        -- ── FARM TAB ──────────────────────────────────────────────────────
        pcall(function()
            -- flag + el:Set(v) ✓
            if _setRAToggle then _setRAToggle(cfg.randomAttackOn == true) end
        end)

        -- ── ATTACK TAB ────────────────────────────────────────────────────
        pcall(function()
            -- Restore data map selection ke mapSelSet dan MR.selected
            if _maMapSelState and cfg.maMapSel then
                for k in pairs(_maMapSelState) do _maMapSelState[k] = nil end
                if MR and MR.selected then for k in pairs(MR.selected) do MR.selected[k] = nil end end
                for k, v in pairs(cfg.maMapSel) do
                    local n = tonumber(k)
                    if n then
                        _maMapSelState[n] = true
                        if MR then MR.selected[n] = true end
                    end
                end
                -- [FIX] _maMapItemRefs kosong di 2.lua (legacy 1.lua) — skip blok itu.
                -- _maUpdateMapDDLbl pakai mapDD:Select() yang butuh frame baru → task.defer
                task.defer(function()
                    if _maUpdateMapDDLbl then pcall(_maUpdateMapDDLbl) end
                end)
            end
            -- Kill/Delay dropdown ✓
            task.delay(0.1, function()
                pcall(function() if _setKillDDGlobal  and cfg.killDDIdx  then _setKillDDGlobal(cfg.killDDIdx)   end end)
                pcall(function() if _setDelayDDGlobal and cfg.delayDDIdx then _setDelayDDGlobal(cfg.delayDDIdx) end end)
            end)
            -- Skill Z/X/C/V/F: logika via SkOn/Off, visual via _setSkillToggleVis
            for _, n in ipairs({"Z","X","C","V","F"}) do
                local key   = "skill" .. n
                local wantOn = cfg[key] == true
                if wantOn and not SKL[n].on then
                    SkOn(n)
                elseif not wantOn and SKL[n].on then
                    SkOff(n)
                end
                if _setSkillToggleVis then
                    pcall(function() _setSkillToggleVis(n, wantOn) end)
                end
            end
            -- Hide Reward + Mass Attack setelah map applied
            task.delay(0.5, function()
                -- ApplyHideReward + el:Set(v) — tidak perlu _vis* ✓
                if _setHideReward     then _setHideReward(cfg.hideReward == true) end
                if _setMaToggleGlobal then _setMaToggleGlobal(cfg.massAttackOn == true) end
            end)
        end)

        -- ── PLAYER TAB ────────────────────────────────────────────────────
        pcall(function()
            -- flag + el:Set(v) — tidak perlu _vis* ✓
            if _setNoClipToggle  then _setNoClipToggle(cfg.noClipOn == true) end
            if _setAntiAfkToggle then _setAntiAfkToggle(cfg.antiAfkOn == true) end
            if _setSpeedSlider and cfg.walkSpeed then _setSpeedSlider(cfg.walkSpeed) end
        end)

        -- ── AUTOMATION: RAID ──────────────────────────────────────────────
        pcall(function()
            -- Tulis state data dulu SEBELUM visual/logika
            if cfg.raidPMIdx then
                local PM_KEYS = {"default","byrank","bymap","hard","easy","manual"}
                local ii = math.clamp(cfg.raidPMIdx, 1, #PM_KEYS)
                RAID.pickMode = PM_KEYS[ii]
                local PM_TO_DIFF = {default="easy",byrank="easy",bymap="easy",hard="hard",easy="easy",manual="easy"}
                RAID.difficulty = PM_TO_DIFF[PM_KEYS[ii]] or "easy"
                RAID.snapshotMapId = nil
            end
            if RAID.preferMaps and cfg.raidPreferMaps then
                for k in pairs(RAID.preferMaps) do RAID.preferMaps[k] = nil end
                for k, v in pairs(cfg.raidPreferMaps) do
                    local n = tonumber(k); if n then RAID.preferMaps[n] = true end
                end
            end
            if RAID.runeGrades and cfg.raidRuneGrades then
                for k in pairs(RAID.runeGrades) do RAID.runeGrades[k] = nil end
                for k, v in pairs(cfg.raidRuneGrades) do RAID.runeGrades[k] = true end
            end
            RAID.runeEnabled   = cfg.raidRuneEnabled   == true
            RAID.runeMapTarget = cfg.raidRuneMapTarget or 0
            RAID._slotOrder = {}

            task.delay(0.05, function()
                -- STEP 1: Terapkan Pick Mode dulu. Ini akan memicu _applyPickModeLock
                -- yang bisa clear+Lock() dropdown Preferred Map/Rank/Rune
                -- tergantung mode. Semua restore data HARUS terjadi SETELAH ini.
                pcall(function()
                    if _setRaidPMIdx and cfg.raidPMIdx then _setRaidPMIdx(cfg.raidPMIdx) end
                end)

                -- STEP 2: Restore data ke RAID state (sumber kebenaran)
                pcall(function()
                    if RAID.preferMaps and cfg.raidPreferMaps then
                        for k in pairs(RAID.preferMaps) do RAID.preferMaps[k] = nil end
                        for k, v in pairs(cfg.raidPreferMaps) do
                            local n = tonumber(k); if n then RAID.preferMaps[n] = true end
                        end
                    end
                    if RAID.runeGrades and cfg.raidRuneGrades then
                        for k in pairs(RAID.runeGrades) do RAID.runeGrades[k] = nil end
                        for k, v in pairs(cfg.raidRuneGrades) do RAID.runeGrades[k] = true end
                    end
                    RAID.runeMapTarget    = cfg.raidRuneMapTarget    or 0
                end)

                -- STEP 3: Refresh SEMUA visual dropdown/toggle, hormati status lock
                -- (kalau field terkunci di mode ini, biarkan tetap "-- NOT SELECTED --"/OFF
                --  sesuai perilaku _doApplyLock, jangan dipaksa restore)
                pcall(function()
                    if not _prefLocked then
                        if _raidUpdatePrefLabel then _raidUpdatePrefLabel() end
                    end
                    if not _rankLocked then
                        if _raidUpdateRankLabel then _raidUpdateRankLabel() end
                    end
                    if not _runeLocked then
                        if _setRaidRuneMapTarget then _setRaidRuneMapTarget(RAID.runeMapTarget) end
                    end
                    if _raidBossToggleVis     then _raidBossToggleVis(cfg.raidAutoKillBoss == true) end
                    if _raidBossDelaySet      then _raidBossDelaySet(cfg.raidBossDelay or 3) end
                    if _setRaidListEnabledVis then
                        _setRaidListEnabledVis(cfg.raidListEnabled == true)
                    else
                        RAID.listEnabled = cfg.raidListEnabled == true
                    end
                    if RAID.listEntries and cfg.raidListEntries then
                        for k in pairs(RAID.listEntries) do RAID.listEntries[k] = nil end
                        for i, ent in ipairs(cfg.raidListEntries) do
                            local maps = {}; local ranks = {}
                            if type(ent.maps)  == "table" then
                                for mk, mv in pairs(ent.maps)  do if mv then maps[tonumber(mk) or mk] = true end end
                            end
                            if type(ent.ranks) == "table" then
                                for rk, rv in pairs(ent.ranks) do if rv then ranks[rk] = true end end
                            end
                            RAID.listEntries[i] = { maps = maps, ranks = ranks }
                        end
                        if _raidRebuildListRows then pcall(_raidRebuildListRows) end
                    end
                end)
                -- Main toggle RAID: _setRaidToggle handle visual (el:Set silently) + logika
                -- _visRaidToggle tidak dipanggil agar tidak double-fire StartRaidLoop ✓
                task.delay(0.5, function()
                    if _setRaidToggle then _setRaidToggle(cfg.raidOn == true) end
                end)
            end)
        end)

        -- ── AUTOMATION: ASC ───────────────────────────────────────────────
        pcall(function()
            -- STEP 1: Terapkan Pick Mode dulu. Ini memicu _applyAscPickModeLock
            -- yang bisa clear+Lock() dropdown Preferred Map/Rank/Rune tergantung mode.
            if _setAscPMIdx and cfg.ascPMIdx then _setAscPMIdx(cfg.ascPMIdx) end

            -- STEP 2: Restore data ke ASC state
            if ASC.preferMaps and cfg.ascPreferMaps then
                for k in pairs(ASC.preferMaps) do ASC.preferMaps[k] = nil end
                for k, v in pairs(cfg.ascPreferMaps) do
                    local n = tonumber(k); if n then ASC.preferMaps[n] = true end
                end
            end
            if ASC.runeGrades and cfg.ascRuneGrades then
                for k in pairs(ASC.runeGrades) do ASC.runeGrades[k] = nil end
                for k, v in pairs(cfg.ascRuneGrades) do ASC.runeGrades[k] = true end
            end
            ASC.runeEnabled     = cfg.ascRuneEnabled     == true
            ASC.runeMapTarget   = cfg.ascRuneMapTarget   or 0
            ASC.preferMapTarget = cfg.ascPreferMapTarget or 0
            ASC._slotOrder = {}

            -- STEP 3: Refresh visual dropdown, hormati status lock dari pick mode
            if not _ascPrefLocked then
                if _ascUpdatePrefLabel then _ascUpdatePrefLabel() end
            end
            if not _ascRankLocked then
                if _ascUpdateRankLabel then _ascUpdateRankLabel() end
            end
            if not _ascRuneLocked then
                if _setAscRuneMapTarget then _setAscRuneMapTarget(ASC.runeMapTarget) end
            end

            if _ascBossToggleVis then
                _ascBossToggleVis(cfg.ascAutoKillBoss == true)
            else
                ASC.autoKillBoss = cfg.ascAutoKillBoss == true
            end
            if _ascBossDelaySet then
                _ascBossDelaySet(cfg.ascBossDelay or 3)
            else
                ASC.bossDelay = cfg.ascBossDelay or 3
            end
            if ASC.listEntries and cfg.ascListEntries then
                for k in pairs(ASC.listEntries) do ASC.listEntries[k] = nil end
                for i, ent in ipairs(cfg.ascListEntries) do
                    local maps = {}; local ranks = {}
                    if ent.maps  then for k, v in pairs(ent.maps)  do local n = tonumber(k); if n then maps[n] = true end end end
                    if ent.ranks then for k, v in pairs(ent.ranks) do ranks[k] = true end end
                    ASC.listEntries[i] = { maps = maps, ranks = ranks }
                end
            end
            if _setAscListEnabledVis then
                _setAscListEnabledVis(cfg.ascListEnabled == true)
            else
                ASC.listEnabled = cfg.ascListEnabled == true
            end
            if _ascRebuildListRows then _ascRebuildListRows() end
            -- _setAscToggle handle visual + logika — tidak perlu _vis* ✓
            task.delay(0.7, function()
                if _setAscToggle then _setAscToggle(cfg.ascOn == true) end
            end)
        end)

        -- ── AUTOMATION: SIEGE ─────────────────────────────────────────────
        pcall(function()
            if SIEGE.excludeMaps and cfg.siegeExclude then
                for k, v in pairs(cfg.siegeExclude) do
                    local n = tonumber(k); if n then SIEGE.excludeMaps[n] = v end
                end
            end
            if _visSiegeExcludeDD then pcall(_visSiegeExcludeDD) end
            -- _setSiegeToggle: el:Set silently + StartSiegeLoop/StopSiege ✓
            task.delay(0.9, function()
                if _setSiegeToggle then _setSiegeToggle(cfg.siegeOn == true) end
            end)
        end)

        -- ── AUTOMATION: DUNGEON ───────────────────────────────────────────
        pcall(function()
            -- Tidak ada visual toggle di JTR; setter hanya update flag
            task.delay(1.1, function()
                if _setDungeonToggle then _setDungeonToggle(cfg.dungeonOn == true) end
            end)
        end)

        -- ── REROLL TAB ────────────────────────────────────────────────────
        task.delay(0.3, function()
            pcall(function()
                -- Restore slotTarget dulu SEBELUM nyalakan toggle
                if _HR_RPT and _HR_RPT.slotTarget and cfg.heroSlotTarget then
                    for si = 1, 3 do
                        for k in pairs(_HR_RPT.slotTarget[si]) do _HR_RPT.slotTarget[si][k] = nil end
                        if type(cfg.heroSlotTarget[si]) == "table" then
                            for qid, v in pairs(cfg.heroSlotTarget[si]) do
                                if v then _HR_RPT.slotTarget[si][tonumber(qid) or qid] = true end
                            end
                        end
                    end
                end
                -- x100 dulu, baru running (urutan penting)
                if _setHeroX100Toggle then _setHeroX100Toggle(cfg.heroX100On == true) end
                task.delay(0.2, function()
                    if not cfg.heroX100On then
                        if _setHeroRollToggle then _setHeroRollToggle(cfg.heroRollOn == true) end
                    end
                end)
            end)
            pcall(function()
                if _WR_RPT and _WR_RPT.slotTarget and cfg.weaponSlotTarget then
                    for si = 1, 3 do
                        for k in pairs(_WR_RPT.slotTarget[si]) do _WR_RPT.slotTarget[si][k] = nil end
                        if type(cfg.weaponSlotTarget[si]) == "table" then
                            for qid, v in pairs(cfg.weaponSlotTarget[si]) do
                                if v then _WR_RPT.slotTarget[si][tonumber(qid) or qid] = true end
                            end
                        end
                    end
                end
                if _setWeaponX100Toggle then _setWeaponX100Toggle(cfg.weaponX100On == true) end
                task.delay(0.2, function()
                    if not cfg.weaponX100On then
                        if _setWeaponRollToggle then _setWeaponRollToggle(cfg.weaponRollOn == true) end
                    end
                end)
            end)
        end)

        -- ── WEBHOOK TAB ───────────────────────────────────────────────────
        pcall(function()
            -- [FIX] URL harus di-restore ke textbox dulu via _setWebhookUrlVis,
            -- bukan cuma tulis ke variabel global — agar input WindUI ikut update
            if _setWebhookUrlVis then
                _setWebhookUrlVis(cfg.webhookUrl or "")
            else
                _webhookUrl = (cfg.webhookUrl or ""):match("^%s*(.-)%s*$") or ""
            end

            -- [FIX v5] Gunakan _visWebhookToggle (visual-only, tanpa callback URL check).
            -- _setWebhookToggle memanggil :Set(v) WITH callback → callback validasi URL
            -- → jika URL belum siap atau kosong, callback paksa :Set(false,false) → visual
            -- balik OFF meski config punya webhookEnabled=true.
            -- Set _webhookEnabled langsung + update visual saja, tanpa trigger callback.
            local wantEnabled = cfg.webhookEnabled == true
            _webhookEnabled = wantEnabled
            if _visWebhookToggle then _visWebhookToggle(wantEnabled) end

            if _webhookModeSetIdx and cfg.webhookModeIdx then
                _webhookModeSetIdx(cfg.webhookModeIdx)
            end
        end)

        -- ── WHATSAPP NOTIF ───────────────────────────────────────────────
        pcall(function()
            -- Nomor harus di-restore ke textbox dulu via _setWaNumberVis,
            -- sama seperti pola _setWebhookUrlVis, agar input WindUI ikut update
            if _setWaNumberVis then
                _setWaNumberVis(cfg.waTargetNumber or "")
            else
                _waTargetNumber = (cfg.waTargetNumber or ""):match("^%s*(.-)%s*$") or ""
            end

            local wantWaEnabled = cfg.waEnabled == true
            _waEnabled = wantWaEnabled
            if _setWaToggle then _setWaToggle(wantWaEnabled) end
        end)

        -- ── THEME TAB ────────────────────────────────────────────────────
        pcall(function()
            if type(cfg.themeTransparency) == "number" and _setTransparencyVis then
                _setTransparencyVis(math.clamp(math.floor(cfg.themeTransparency + 0.5), 0, 100))
            end
        end)
        pcall(function()
            if type(cfg.themeName) == "string" and _setThemeVis then
                _setThemeVis(cfg.themeName)
            end
        end)

        return true
    end

    -- ─── LOAD / DELETE CONFIG ─────────────────────────────────────────────────
    local function LoadConfigByName(name)
        local ok, result = pcall(function()
            local path = _cfgPath(name)
            local fileExists = false
            pcall(function() fileExists = isfile(path) end)
            if not fileExists then return nil end
            local raw = nil
            pcall(function() raw = readfile(path) end)
            if not raw or raw == "" then return nil end
            return jsonDecode(raw)
        end)
        if not ok then return nil end
        if type(result) ~= "table" then return nil end
        return result
    end

    local function DeleteConfigByName(name)
        local ok = pcall(function()
            local path = _cfgPath(name)
            local exists = pcall(isfile, path)
            if exists then pcall(delfile, path) end
        end)
        return ok
    end

    -- ─── SINGLE CONFIG SLOT (tidak multi-save lagi) ──────────────────────────
    -- Semua save/load/delete sekarang mengarah ke SATU file config tetap.
    -- Tidak ada lagi input nama, dropdown pilih config, atau tombol refresh.
    local SINGLE_CONFIG_NAME = "config"

    -- ─── PARAGRAPH STATUS (WindUI native) ────────────────────────────────────
    ConfigTab:Section({ Title = "Config Manager", Icon = "save" })

    local _statusPara = ConfigTab:Paragraph({
        Title = "Status",
        Desc  = "Pilih aksi di bawah.",
    })

    local function SetStatus(msg)
        pcall(function() _statusPara:SetDesc(msg) end)
    end

    -- ─── INISIALISASI STATUS AWAL ─────────────────────────────────────────────
    do
        local exists = false
        pcall(function() exists = isfile(_cfgPath(SINGLE_CONFIG_NAME)) end)
        if exists then
            SetStatus("Config tersimpan ditemukan. Klik LOAD CONFIG untuk menerapkan.")
        else
            SetStatus("Belum ada config tersimpan. Atur fitur lalu klik SAVE CONFIG.")
        end
    end

    -- ─── TOMBOL: SAVE CONFIG ──────────────────────────────────────────────────
    -- Menyimpan semua state/visual fitur yang sedang di-set user saat ini.
    -- Selalu menimpa (overwrite) file config tunggal yang sama -> tidak ada multi-save.
    ConfigTab:Button({
        Title    = "SAVE CONFIG",
        Desc     = "Simpan semua setting & fitur script saat ini (menimpa config sebelumnya)",
        Callback = function()
            SetStatus("Menyimpan config...")
            task.delay(0.05, function()
                local ok, err = SaveConfigAs(SINGLE_CONFIG_NAME)
                if ok then
                    SetStatus("Config tersimpan. (" .. os.date("%H:%M:%S") .. ")")
                else
                    SetStatus("[!] Gagal simpan: " .. tostring(err):sub(1, 60))
                end
            end)
        end,
    })

    -- ─── TOMBOL: LOAD CONFIG ──────────────────────────────────────────────────
    -- Restore sempurna semua state & tampilan menu/fitur sesuai config yang tersimpan.
    ConfigTab:Button({
        Title    = "LOAD CONFIG",
        Desc     = "Restore semua setting & fitur script sesuai config yang tersimpan",
        Callback = function()
            SetStatus("Memuat config...")
            task.delay(0.05, function()
                local cfg = LoadConfigByName(SINGLE_CONFIG_NAME)
                if type(cfg) == "table" then
                    ApplyConfig(cfg)
                    SetStatus("Config dimuat. (" .. os.date("%H:%M:%S") .. ")")
                else
                    SetStatus("[!] Tidak ada config tersimpan / gagal load.")
                end
            end)
        end,
    })

    -- ─── TOMBOL: DELETE CONFIG (double-confirm) ───────────────────────────────
    -- Klik pertama = konfirmasi, klik kedua (dalam 5 detik) = hapus permanen dari folder.
    local _pendingDel   = false
    local _pendingTimer = nil

    ConfigTab:Button({
        Title    = "DELETE CONFIG",
        Desc     = "Klik sekali untuk konfirmasi, klik lagi untuk hapus permanen",
        Callback = function()
            if _pendingDel then
                if _pendingTimer then pcall(task.cancel, _pendingTimer) end
                _pendingDel   = false
                _pendingTimer = nil
                local ok = DeleteConfigByName(SINGLE_CONFIG_NAME)
                if ok then
                    SetStatus("Config dihapus permanen.")
                else
                    SetStatus("[!] Gagal hapus config (mungkin belum ada yang tersimpan).")
                end
            else
                _pendingDel = true
                SetStatus("[!] YAKIN hapus config? Klik DELETE CONFIG sekali lagi untuk konfirmasi. (auto-cancel 5 detik)")
                _pendingTimer = task.delay(5, function()
                    _pendingDel   = false
                    _pendingTimer = nil
                    SetStatus("Hapus dibatalkan (timeout).")
                end)
            end
        end,
    })

end -- end do PANEL CONFIG

-- ============================================================================
-- CAPTURE LAYER INIT (dipindah ke akhir script standalone ini)
-- Sama seperti source asli: dipasang paling akhir supaya hook __namecall
-- WindUI jadi yang teratas di chain.
-- ============================================================================
do
    if InitAllCaptureLayers then
        InitAllCaptureLayers()
    end
end
