-- Suffix Sniffer - Cari sistem suffix yang dipakai game ini
-- Jalankan, lalu lihat output

local RS = game:GetService("ReplicatedStorage")

print("=== SUFFIX SNIFFER STARTED ===")

-- ============================================================
-- Metode 1: Cari fungsi format angka di ModuleScript
-- Biasanya game simpan di ReplicatedStorage atau shared module
-- ============================================================
local function scanModule(obj, depth)
    depth = depth or 0
    if depth > 5 then return end
    if obj:IsA("ModuleScript") then
        local name = obj.Name:lower()
        -- Cari module yang kemungkinan handle format angka
        if name:find("util") or name:find("format") or name:find("number")
        or name:find("math") or name:find("abbreviat") or name:find("suffix")
        or name:find("display") or name:find("convert") or name:find("string")
        or name:find("helper") or name:find("tool") or name:find("lib") then
            print("[MODULE FOUND] " .. obj:GetFullName())
            -- Coba require dan cek isinya
            local ok, result = pcall(require, obj)
            if ok and type(result) == "table" then
                print("  -> Required OK, keys: ")
                local keys = {}
                for k in pairs(result) do table.insert(keys, tostring(k)) end
                print("     " .. table.concat(keys, ", "))
            end
        end
    end
    for _, child in ipairs(obj:GetChildren()) do
        pcall(scanModule, child, depth + 1)
    end
end

print("--- Scan ModuleScript di ReplicatedStorage ---")
scanModule(RS)

-- ============================================================
-- Metode 2: Cari array suffix langsung dari semua ModuleScript
-- dengan cara baca source code-nya
-- ============================================================
print("")
print("--- Scan source code ModuleScript untuk keyword suffix ---")

local keywords = {"Sp","Oc","No","Dc","suffix","abbrev","format","shorten"}

local function deepScan(obj, depth)
    depth = depth or 0
    if depth > 6 then return end
    if obj:IsA("ModuleScript") then
        local ok, src = pcall(function()
            return game:GetService("ScriptEditorService"):GetEditorSource(obj)
        end)
        if not ok or not src then
            -- Fallback: coba require dan inspect
            local ok2, mod = pcall(require, obj)
            if ok2 and type(mod) == "table" then
                local str = tostring(mod)
                for _, kw in ipairs(keywords) do
                    if str:find(kw) then
                        print("[MATCH] " .. obj:GetFullName() .. " contains: " .. kw)
                        break
                    end
                end
            end
            return
        end
        for _, kw in ipairs(keywords) do
            if src:find(kw, 1, true) then
                print("[SOURCE MATCH] " .. obj:GetFullName())
                -- Print baris yang mengandung suffix
                for line in src:gmatch("[^\n]+") do
                    if line:find("Sp") or line:find("Oc") or line:find("suffix")
                    or line:find("abbrev") or line:find("{") and line:find('"') then
                        print("  >> " .. line:sub(1, 120))
                    end
                end
                break
            end
        end
    end
    for _, child in ipairs(obj:GetChildren()) do
        pcall(deepScan, child, depth + 1)
    end
end

deepScan(RS)

-- ============================================================
-- Metode 3: Hook fungsi yang dipanggil saat display angka
-- Tangkap TextLabel yang updatenya berisi suffix
-- ============================================================
print("")
print("--- Monitor TextLabel yang tampilkan angka besar ---")

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local seenSuffixes = {}

local function checkText(text)
    if not text or text == "" then return end
    -- Cari pola: angka + huruf (suffix)
    local suffix = text:match("[%d%.]+([A-Za-z]+)$")
    if suffix and #suffix >= 1 and #suffix <= 5 then
        if not seenSuffixes[suffix] then
            seenSuffixes[suffix] = true
            print("[SUFFIX FOUND] '" .. suffix .. "' dalam teks: " .. text:sub(1,30))
        end
    end
end

-- Watch semua TextLabel yang ada
local function watchLabel(lbl)
    if not (lbl:IsA("TextLabel") or lbl:IsA("TextButton")) then return end
    checkText(lbl.Text)
    lbl:GetPropertyChangedSignal("Text"):Connect(function()
        checkText(lbl.Text)
    end)
end

-- Scan PlayerGui sekarang
for _, obj in ipairs(PG:GetDescendants()) do
    pcall(watchLabel, obj)
end

-- Watch yang baru muncul
PG.DescendantAdded:Connect(function(obj)
    pcall(watchLabel, obj)
end)

-- Juga scan workspace (floating damage number)
for _, obj in ipairs(workspace:GetDescendants()) do
    pcall(watchLabel, obj)
end
workspace.DescendantAdded:Connect(function(obj)
    task.defer(function()
        pcall(watchLabel, obj)
    end)
end)

-- ============================================================
-- Metode 4: Cari di _G atau shared
-- ============================================================
print("")
print("--- Cek _G dan shared untuk format function ---")
for k, v in pairs(_G) do
    local sk = tostring(k):lower()
    if sk:find("format") or sk:find("number") or sk:find("abbrev") or sk:find("suffix") then
        print("[_G FOUND] _G." .. tostring(k) .. " = " .. type(v))
    end
end

print("=== SNIFFER AKTIF - Mainkan game, lihat suffix yang muncul! ===")
print("Suffix akan otomatis terdeteksi dari TextLabel yang ada di layar")
