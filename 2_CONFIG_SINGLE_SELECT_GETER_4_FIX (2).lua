-- DPS Sniffer - Cari remote yang bawa data damage
-- Jalankan ini dulu, pukul musuh, lalu lihat output

local Players = game:GetService("Players")
local LP      = Players.LocalPlayer

print("=== DPS SNIFFER STARTED ===")
print("Sekarang pukul musuh, lihat output di bawah ini!")
print("==========================================")

-- ============================================================
-- Metode 1: hookmetamethod __namecall
-- Tangkap semua FireServer / InvokeServer yang lewat
-- ============================================================
local mt    = getrawmetatable(game)
local oldNc = mt.__namecall
setreadonly(mt, false)

mt.__namecall = newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args   = {...}

    -- Filter hanya FireServer / InvokeServer
    if method == "FireServer" or method == "InvokeServer" then
        local name = tostring(self.Name):lower()

        -- Tangkap remote yang kemungkinan bawa damage
        local keywords = {
            "atk","attack","dmg","damage","hit","click",
            "skill","hurt","combat","dps","battle","fight"
        }

        local match = false
        for _, kw in ipairs(keywords) do
            if name:find(kw, 1, true) then
                match = true
                break
            end
        end

        if match then
            -- Serialize args
            local function serialize(v, depth)
                depth = depth or 0
                if depth > 3 then return "..." end
                local t = type(v)
                if t == "string"  then return '"'..v..'"' end
                if t == "number"  then return tostring(v) end
                if t == "boolean" then return tostring(v) end
                if t == "table"   then
                    local parts = {}
                    for k, val in pairs(v) do
                        table.insert(parts, tostring(k).."="..serialize(val, depth+1))
                    end
                    return "{"..table.concat(parts, ", ").."}"
                end
                return t
            end

            local argStr = ""
            for i, a in ipairs(args) do
                argStr = argStr .. "[arg"..i.."] " .. serialize(a) .. "  "
            end

            print(string.format(
                "[SNIFFER] %s | %s | %s",
                method, tostring(self:GetFullName()), argStr
            ))
        end
    end

    return oldNc(self, ...)
end)

setreadonly(mt, true)

-- ============================================================
-- Metode 2: Listen OnClientEvent dari semua remote di RS
-- Tangkap data damage yang dikirim SERVER -> CLIENT
-- ============================================================
local function listenRemote(rem)
    local name = rem.Name:lower()
    local keywords = {
        "damage","dmg","hit","dps","atk","attack",
        "hurt","combat","takehit","takedamage","showdamage",
        "enemytake","floatingtext","damagefloat","damagenumber"
    }
    local match = false
    for _, kw in ipairs(keywords) do
        if name:find(kw, 1, true) then match = true; break end
    end

    if match then
        if rem:IsA("RemoteEvent") then
            rem.OnClientEvent:Connect(function(...)
                local function serialize(v, depth)
                    depth = depth or 0
                    if depth > 3 then return "..." end
                    local t = type(v)
                    if t == "string"  then return '"'..v..'"' end
                    if t == "number"  then return tostring(v) end
                    if t == "boolean" then return tostring(v) end
                    if t == "table"   then
                        local parts = {}
                        for k, val in pairs(v) do
                            table.insert(parts, tostring(k).."="..serialize(val, depth+1))
                        end
                        return "{"..table.concat(parts, ", ").."}"
                    end
                    return t
                end
                local argStr = ""
                for i, a in ipairs({...}) do
                    argStr = argStr .. "[arg"..i.."] " .. serialize(a) .. "  "
                end
                print(string.format(
                    "[CLIENT EVENT] %s | %s",
                    rem:GetFullName(), argStr
                ))
            end)
        elseif rem:IsA("RemoteFunction") then
            local oldCB = rem.OnClientInvoke
            rem.OnClientInvoke = function(...)
                print(string.format("[CLIENT INVOKE] %s | called", rem:GetFullName()))
                if oldCB then return oldCB(...) end
            end
        end
        print("[SNIFFER] Listening: " .. rem:GetFullName())
    end
end

-- Scan semua remote yang ada sekarang
local RS = game:GetService("ReplicatedStorage")
for _, obj in ipairs(RS:GetDescendants()) do
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        pcall(function() listenRemote(obj) end)
    end
end

-- Watch remote baru yang muncul nanti
RS.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        pcall(function() listenRemote(obj) end)
    end
end)

print("=== SNIFFER AKTIF — Sekarang pukul musuh! ===")
print("Perhatikan output yang muncul, cari yang ada angka damage-nya")
print("Kirimkan hasil output ke Claude untuk dianalisis!")
