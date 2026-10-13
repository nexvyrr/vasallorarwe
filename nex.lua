local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local CoreGui = game:GetService("CoreGui")
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local lp = Players.LocalPlayer
local genv = getgenv()

if genv.__NEXVYR_STOP then pcall(genv.__NEXVYR_STOP) end

local WindUI
local _version = "1.6.66"
local uiFileName = "WindUI_Cache_v" .. _version .. ".txt"
local timeFileName = "WindUI_Cache_v" .. _version .. "_Time.txt"

local ok, result = pcall(function()
    local cacheValido = false
    if isfile and isfile(timeFileName) and readfile then
        local savedTime = tonumber(readfile(timeFileName))
        if savedTime and (os.time() - savedTime) < 86400 then
            cacheValido = true
        end
    end
    if cacheValido and isfile and isfile(uiFileName) then
        local code = readfile(uiFileName)
        local fn = loadstring(code)
        if fn then
            return fn()
        else
            if delfile then
                pcall(delfile, uiFileName)
                pcall(delfile, timeFileName)
            end
        end
    end
    local codigoUi = game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/" .. _version .. "/main.lua")
    if writefile then
        writefile(uiFileName, codigoUi)
        writefile(timeFileName, tostring(os.time()))
    end
    return loadstring(codigoUi)()
end)

if ok and result and type(result) == "table" then
    WindUI = result
else
    warn("Error al cargar WindUI: " .. tostring(result))
    return
end

local conns = {}
local function C(sig, fn)
    local s, c = pcall(function() return sig:Connect(fn) end)
    if s and c then conns[#conns + 1] = c end
    return c
end

local function safeParent(inst)
    pcall(function() inst.Parent = (gethui and gethui()) or CoreGui end)
    if not inst.Parent then inst.Parent = lp:WaitForChild("PlayerGui") end
end

local function inCharacter(p)
    local m = p:FindFirstAncestorOfClass("Model")
    while m do
        if m:FindFirstChildOfClass("Humanoid") then return true end
        m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
    end
    return false
end

local ESP = {
    hl = false,
    box = false,
    pulse = true,
    color = Color3.fromRGB(255, 70, 140),
}

local enemyIds, enemyNames, allyIds, allyNames = {}, {}, {}, {}
local haveTeams = false
local TEAM = {
    check = true,
    ver = 0,
    at = -1e9,
    rel = {},
    discr = false,
}
local function norm(e)
    local t = typeof(e)
    if t == "number" then return e, nil end
    if t == "string" then return tonumber(e), e end
    if t == "Instance" then
        if e:IsA("Player") then return e.UserId, e.Name end
        return nil, e.Name
    end
    if t == "table" then
        local id = e.UserId or e.userId or e.UserID or e.Id or e.id
        local nm = e.Name or e.name or e.Username or e.username
        if type(id) == "string" then id = tonumber(id) end
        return id, nm
    end
end

local function collect(list, ids, names)
    if type(list) ~= "table" then return end
    for k, v in pairs(list) do
        local id, nm
        if v == true then
            id, nm = norm(k)
        else
            id, nm = norm(v)
        end
        if type(id) == "number" then ids[id] = true end
        if type(nm) == "string" then names[nm] = true end
    end
end

local function applyTeams(data)
    local my, teams = data.YourTeam, data.Teams
    if my == nil or type(teams) ~= "table" then return end
    local list, anyHasMe = {}, false
    for key, team in pairs(teams) do
        if type(team) == "table" then
            local ids, names = {}, {}
            collect(team.Players, ids, names)
            local tid = team.Id or team.id or team.Name or team.name or team.TeamId or team.Team
            local byKey = (key == my) or (tostring(key) == tostring(my)) or (tid ~= nil and tostring(tid) == tostring(my))
            local hasMe = (ids[lp.UserId] or names[lp.Name]) and true or false
            if hasMe then anyHasMe = true end
            list[#list + 1] = { ids = ids, names = names, byKey = byKey, hasMe = hasMe }
        end
    end
    table.clear(enemyIds) table.clear(enemyNames)
    table.clear(allyIds) table.clear(allyNames)
    for _, t in ipairs(list) do
        local mine
        if anyHasMe then mine = t.hasMe else mine = t.byKey end
        local tIds = mine and allyIds or enemyIds
        local tNames = mine and allyNames or enemyNames
        for k in pairs(t.ids) do tIds[k] = true end
        for k in pairs(t.names) do tNames[k] = true end
    end
    haveTeams = false
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and (enemyIds[plr.UserId] or enemyNames[plr.Name] or allyIds[plr.UserId] or allyNames[plr.Name]) then
            haveTeams = true
            break
        end
    end
    TEAM.at = -1e9
    TEAM.ver = TEAM.ver + 1
end

local function onDuelState(kind, data)
    if kind ~= "Match" or type(data) ~= "table" then return end
    applyTeams(data)
end

task.spawn(function()
    local net = RS:WaitForChild("DuelNet", 15)
    local ev = net and net:WaitForChild("DuelState", 15)
    if ev then
        C(ev.OnClientEvent, function(kind, data)
            pcall(onDuelState, kind, data)
        end)
    end
end)

do
local TEAM_EXACT = {
    team = true, teamid = true, teamname = true, teamcolor = true, teamindex = true, teamnumber = true,
    duelteam = true, matchteam = true, side = true, squad = true, squadid = true, faction = true,
    alliance = true, party = true,
}
local TEAM_BAD = { "size", "count", "max", "min", "limit", "total", "score", "kill", "point", "win", "rank", "chat", "invite" }

local function teamAttrName(n)
    local l = n:lower()
    if TEAM_EXACT[l] then return true end
    if l:find("team", 1, true) then
        for _, b in ipairs(TEAM_BAD) do
            if l:find(b, 1, true) then return false end
        end
        return true
    end
    return false
end

local function teamVals(inst)
    local out = {}
    if not inst then return out end
    local okA, attrs = pcall(function() return inst:GetAttributes() end)
    if okA and type(attrs) == "table" then
        for n, v in pairs(attrs) do
            if teamAttrName(n) and v ~= nil and v ~= "" then out["a:" .. n] = tostring(v) end
        end
    end
    for _, c in ipairs(inst:GetChildren()) do
        if c:IsA("ValueBase") and TEAM_EXACT[c.Name:lower()] then
            local okV, v = pcall(function() return c.Value end)
            if okV and v ~= nil and tostring(v) ~= "" then out["v:" .. c.Name] = tostring(v) end
        end
    end
    return out
end

local function relFromVals(mine, theirs)
    local same, diff = 0, 0
    for k, v in pairs(mine) do
        local o = theirs[k]
        if o ~= nil then
            if o == v then same = same + 1 else diff = diff + 1 end
        end
    end
    if same > 0 and diff == 0 then return "ally" end
    if diff > 0 and same == 0 then return "enemy" end
    return nil
end

local function refreshGeneric(now)
    if now - TEAM.at < 0.5 then return end
    TEAM.at = now
    local rel, anyEnemy = {}, false
    local myP, myC = teamVals(lp), teamVals(lp.Character)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local r = relFromVals(myP, teamVals(plr)) or relFromVals(myC, teamVals(plr.Character))
            if r == nil and lp.Team ~= nil and plr.Team ~= nil then
                r = (lp.Team == plr.Team) and "ally" or "enemy"
            end
            rel[plr] = r
            if r == "enemy" then anyEnemy = true end
        end
    end
    TEAM.rel = rel
    TEAM.discr = anyEnemy
end

function TEAM.genericAlly(plr)
    refreshGeneric(os.clock())
    return TEAM.discr and TEAM.rel[plr] == "ally"
end
end

local function isEnemy(plr)
    if not TEAM.check then
        if enemyIds[plr.UserId] or enemyNames[plr.Name] or allyIds[plr.UserId] or allyNames[plr.Name] then return true end
        if haveTeams then return false end
        local mid0 = lp:GetAttribute("DuelMatchId")
        return mid0 ~= nil and mid0 ~= "" and plr:GetAttribute("DuelMatchId") == mid0
    end
    if enemyIds[plr.UserId] or enemyNames[plr.Name] then return true end
    if allyIds[plr.UserId] or allyNames[plr.Name] then return false end
    if haveTeams then return false end
    local mid = lp:GetAttribute("DuelMatchId")
    if not (mid ~= nil and mid ~= "" and plr:GetAttribute("DuelMatchId") == mid) then return false end
    return not TEAM.genericAlly(plr)
end

local function enPartida()
    return lp:GetAttribute("DuelStatus") == "IN_MATCH"
end

local function getEnemies()
    local out = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and isEnemy(plr) then out[#out + 1] = plr end
    end
    if #out == 0 and enPartida() then
        local mid = lp:GetAttribute("DuelMatchId")
        local noInfo = next(enemyIds) == nil and next(enemyNames) == nil
        if noInfo and (mid == nil or mid == "") then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= lp and (not TEAM.check or not (allyIds[plr.UserId] or allyNames[plr.Name] or TEAM.genericAlly(plr))) then
                    out[#out + 1] = plr
                end
            end
        end
    end
    return out
end

local holder = Instance.new("Folder")
holder.Name = "NexvyrESP"
safeParent(holder)

local boxGui = Instance.new("ScreenGui")
boxGui.Name = "NexvyrBoxes"
boxGui.IgnoreGuiInset = true
boxGui.ResetOnSpawn = false
boxGui.DisplayOrder = 998
safeParent(boxGui)

local objs = {}
local function getObj(plr)
    local o = objs[plr]
    if o then return o end

    local hl = Instance.new("Highlight")
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled = false
    hl.Parent = holder

    local box = Instance.new("Frame")
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false
    box.Parent = boxGui

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Transparency = 0.35
    stroke.Parent = box

    o = { hl = hl, box = box, stroke = stroke }
    objs[plr] = o
    return o
end

C(Players.PlayerRemoving, function(plr)
    local o = objs[plr]
    if o then
        o.hl:Destroy()
        o.box:Destroy()
        objs[plr] = nil
    end
end)

local function boxBounds(cam, ch)
    local cf, size = ch:GetBoundingBox()
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local any = false
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                local p = cam:WorldToViewportPoint(cf:PointToWorldSpace(Vector3.new(hx * sx, hy * sy, hz * sz)))
                if p.Z > 0 then
                    any = true
                    if p.X < minX then minX = p.X end
                    if p.Y < minY then minY = p.Y end
                    if p.X > maxX then maxX = p.X end
                    if p.Y > maxY then maxY = p.Y end
                end
            end
        end
    end
    if not any then return nil end
    return minX, minY, maxX, maxY
end

local t = 0
C(RunService.RenderStepped, function(dt)
    t = t + dt
    local cam = workspace.CurrentCamera
    local active = cam ~= nil and (ESP.hl or ESP.box) and enPartida()
    if not active then
        for _, o in pairs(objs) do
            o.hl.Enabled = false
            o.box.Visible = false
        end
        return
    end

    local seen = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp and isEnemy(plr) then
            local ch = plr.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                seen[plr] = true
                local o = getObj(plr)

                if ESP.hl then
                    if o.hl.Adornee ~= ch then o.hl.Adornee = ch end
                    o.hl.FillColor = ESP.color
                    o.hl.OutlineColor = ESP.color
                    local s = (math.sin(t * 3) + 1) / 2
                    o.hl.FillTransparency = 0.72
                    o.hl.OutlineTransparency = ESP.pulse and (0.4 + s * 0.2) or 0.5
                    o.hl.Enabled = true
                else
                    o.hl.Enabled = false
                end

                if ESP.box then
                    local x1, y1, x2, y2 = boxBounds(cam, ch)
                    if x1 then
                        o.box.Position = UDim2.fromOffset(x1, y1)
                        o.box.Size = UDim2.fromOffset(x2 - x1, y2 - y1)
                        o.stroke.Color = ESP.color
                        o.box.Visible = true
                    else
                        o.box.Visible = false
                    end
                else
                    o.box.Visible = false
                end
            end
        end
    end

    for plr, o in pairs(objs) do
        if not seen[plr] then
            o.hl.Enabled = false
            o.box.Visible = false
        end
    end
end)

local SILENT = {
    on = false,
    autoshoot = false,
    target = nil,
    part = "Cabeza",
    wall = true,
    minLen = 30,
    lastPlayer = nil,
    lastPart = nil,
    lastSeen = 0,
}

local visParams = RaycastParams.new()
visParams.FilterType = Enum.RaycastFilterType.Exclude
visParams.IgnoreWater = true

local function aimTorso(ch)
    return ch:FindFirstChild("UpperTorso")
        or ch:FindFirstChild("Torso")
        or ch:FindFirstChild("HumanoidRootPart")
end

local function aimParts(ch)
    local head, torso = ch:FindFirstChild("Head"), aimTorso(ch)
    if SILENT.part == "Cabeza" then return head, torso end
    return torso, head
end

local function aimVisible(cam, myCh, enCh, part)
    if not SILENT.wall then return true end
    local origin = cam.CFrame.Position
    local ignore = { myCh }
    for _ = 1, 8 do
        visParams.FilterDescendantsInstances = ignore
        local res = workspace:Raycast(origin, part.Position - origin, visParams)
        if not res then return true end
        local inst = res.Instance
        if inst:IsDescendantOf(enCh) then return true end
        local model = inst:FindFirstAncestorOfClass("Model")
        if model and model:FindFirstChildOfClass("Humanoid") then
            ignore[#ignore + 1] = model
        elseif inst.CanCollide and inst.Transparency < 0.5 then
            return false
        else
            ignore[#ignore + 1] = inst
        end
    end
    return true
end

local function pickTarget()
    local cam = workspace.CurrentCamera
    local myCh = lp.Character
    local myHum = myCh and myCh:FindFirstChildOfClass("Humanoid")
    if not cam or not myHum or myHum.Health <= 0 or not enPartida() then return nil end

    local cf = cam.CFrame
    local origin, look = cf.Position, cf.LookVector
    local best, bestScore, bestPlr = nil, math.huge, nil

    for _, plr in ipairs(getEnemies()) do
        local ch = plr.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local p1, p2 = aimParts(ch)
            local part
            if p1 and aimVisible(cam, myCh, ch, p1) then
                part = p1
            elseif p2 and aimVisible(cam, myCh, ch, p2) then
                part = p2
            end
            if part then
                local to = part.Position - origin
                local m = to.Magnitude
                if m > 0.01 then
                    local score = math.acos(math.clamp(look:Dot(to / m), -1, 1))
                    if plr == SILENT.lastPlayer then score = score * 0.5 end
                    if score < bestScore then
                        best, bestScore, bestPlr = part, score, plr
                    end
                end
            end
        end
    end

    local now = os.clock()
    if best then
        SILENT.lastPlayer, SILENT.lastPart, SILENT.lastSeen = bestPlr, best, now
        return best
    end

    local prev = SILENT.lastPart
    if prev and prev.Parent and now - SILENT.lastSeen < 0.3 then
        local hum = prev.Parent:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then return prev end
    end
    return nil
end

C(RunService.RenderStepped, function()
    if SILENT.on or SILENT.autoshoot then
        local ok, res = pcall(pickTarget)
        SILENT.target = ok and res or nil
    else
        SILENT.target = nil
    end
end)

local function aimFilter(tgt)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    rp.FilterDescendantsInstances = { tgt }
    rp.IgnoreWater = true
    return rp
end

local hooksInstalled = false
local function installHooks()
    if hooksInstalled then return end
    if not (hookmetamethod and newcclosure and getnamecallmethod and checkcaller) then
        warn("NEXVYRHUB: tu executor no soporta hookmetamethod")
        return
    end
    hooksInstalled = true

    local mouse = lp:GetMouse()
    local ws = workspace

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local tgt = (SILENT.on or SILENT.autoshoot) and SILENT.target
        if tgt and self == ws and tgt.Parent and not checkcaller() then
            local method = getnamecallmethod()
            if method == "Raycast" then
                local origin, dir = ...
                if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" and dir.Magnitude >= SILENT.minLen then
                    local to = tgt.Position - origin
                    local m = to.Magnitude
                    if m > 0.01 then
                        local res = oldNamecall(self, origin, to.Unit * math.max(dir.Magnitude, m + 3), aimFilter(tgt))
                        if res then return res end
                    end
                end
            elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                local ray = ...
                if setnamecallmethod and typeof(ray) == "Ray" and ray.Direction.Magnitude >= SILENT.minLen then
                    local to = tgt.Position - ray.Origin
                    local m = to.Magnitude
                    if m > 0.01 then
                        local newRay = Ray.new(ray.Origin, to.Unit * math.max(ray.Direction.Magnitude, m + 3))
                        setnamecallmethod("FindPartOnRayWithWhitelist")
                        local part, pos, normal, mat = oldNamecall(self, newRay, { tgt }, true)
                        setnamecallmethod(method)
                        if part then return part, pos, normal, mat end
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end))

    local oldIndex
    oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
        if self == mouse and not checkcaller() then
            local tgt = (SILENT.on or SILENT.autoshoot) and SILENT.target
            if tgt and tgt.Parent then
                if key == "Hit" then return CFrame.new(tgt.Position) end
                if key == "Target" then return tgt end
                if key == "UnitRay" then
                    local cam = workspace.CurrentCamera
                    if cam then
                        local o = cam.CFrame.Position
                        return Ray.new(o, (tgt.Position - o).Unit)
                    end
                end
            end
        end
        return oldIndex(self, key)
    end))
end

local KILLFX = {
    on = true,
    sound = true,
    onlyMine = true,
    fallback = true,
    debug = false,
}

local function getEffectsFolder()
    local sk = RS:FindFirstChild("Skins")
    return sk and sk:FindFirstChild("Effects")
end

local function effectNames()
    local list = {}
    local f = getEffectsFolder()
    if f then
        for _, c in ipairs(f:GetChildren()) do
            if c:IsA("Folder") or c:IsA("Model") then
                list[#list + 1] = c.Name
            end
        end
    end
    table.sort(list, function(a, b)
        if a == "Frostbite" then return true end
        if b == "Frostbite" then return false end
        return a < b
    end)
    return list
end

local function anchorModel(m)
    for _, bp in ipairs(m:GetDescendants()) do
        if bp:IsA("BasePart") then
            bp.Anchored = true
            bp.CanCollide = false
            bp.CanQuery = false
            bp.CanTouch = false
        end
    end
end

local function emitEmitter(e)
    local count = e:GetAttribute("EmitCount")
    if type(count) ~= "number" then
        local rate = e.Rate
        count = (rate and rate > 0) and math.clamp(math.floor(rate), 5, 60) or 20
    end
    local delay = e:GetAttribute("EmitDelay")
    local duration = e:GetAttribute("EmitDuration")

    local function fire()
        if not e.Parent then return end
        pcall(function() e:Emit(count) end)
        if type(duration) == "number" and duration > 0 then
            e.Enabled = true
            task.delay(duration, function()
                if e.Parent then e.Enabled = false end
            end)
        end
    end

    e.Enabled = false
    if type(delay) == "number" and delay > 0 then
        task.delay(delay, fire)
    else
        fire()
    end
end

local function playEffect(name, baseCF, groundCF, withSound)
    local f = getEffectsFolder()
    local eff = f and f:FindFirstChild(name)
    if not eff then return end

    if not baseCF then
        local ch = lp.Character
        local myHrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end
        baseCF = myHrp.CFrame * CFrame.new(0, 0, -6)
        groundCF = myHrp.CFrame * CFrame.new(0, -2.5, -6)
    end
    groundCF = groundCF or (baseCF * CFrame.new(0, -2.5, 0))

    local origin = baseCF
    local groundOrigin = groundCF

    local container = Instance.new("Folder")
    container.Name = "NexvyrPreview"
    container.Parent = workspace

    local anchor = Instance.new("Part")
    anchor.Name = "Anchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(4, 1, 4)
    anchor.CFrame = origin
    anchor.Parent = container

    local ground = Instance.new("Part")
    ground.Name = "GroundAnchor"
    ground.Anchored = true
    ground.CanCollide = false
    ground.CanQuery = false
    ground.CanTouch = false
    ground.Transparency = 1
    ground.Size = Vector3.new(6, 0.2, 6)
    ground.CFrame = groundOrigin
    ground.Parent = container

    if withSound ~= false then
        for _, d in ipairs(eff:GetDescendants()) do
            if d:IsA("Sound") then
                local s = d:Clone()
                s.Parent = anchor
                pcall(function() s:Play() end)
                Debris:AddItem(s, math.max(s.TimeLength, 4) + 1)
            end
        end
    end

    local particles = eff:FindFirstChild("Particles")
    if particles then
        for _, p in ipairs(particles:GetChildren()) do
            if p:IsA("ParticleEmitter") then
                local c = p:Clone()
                local lname = p.Name:lower()
                if lname:find("ground") then
                    c.Parent = ground
                else
                    c.Parent = anchor
                end
            elseif p:IsA("Attachment") then
                local c = p:Clone()
                c.Parent = anchor
            elseif p:IsA("BasePart") then
                local c = p:Clone()
                c.Anchored = true
                c.CanCollide = false
                c.CFrame = origin
                c.Parent = container
            elseif p:IsA("Model") then
                local c = p:Clone()
                anchorModel(c)
                c.Parent = container
                c:PivotTo(origin)
            elseif p:IsA("Folder") then
                for _, sub in ipairs(p:GetDescendants()) do
                    if sub:IsA("ParticleEmitter") then
                        local c = sub:Clone()
                        c.Parent = anchor
                    end
                end
            end
        end
    end

    local accs = eff:FindFirstChild("Accessories")
    if accs then
        for _, a in ipairs(accs:GetChildren()) do
            local c = a:Clone()
            if c:IsA("Accessory") then
                local handle = c:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") then
                    handle.Anchored = true
                    handle.CanCollide = false
                    handle.CFrame = origin
                    c.Parent = container
                else
                    c:Destroy()
                end
            elseif c:IsA("BasePart") then
                c.Anchored = true
                c.CanCollide = false
                c.CFrame = origin
                c.Parent = container
            elseif c:IsA("Model") then
                anchorModel(c)
                c.Parent = container
                c:PivotTo(origin)
            else
                c.Parent = anchor
            end
        end
    end

    local reps = eff:FindFirstChild("Replacements")
    if reps then
        for _, r in ipairs(reps:GetChildren()) do
            local c = r:Clone()
            if c:IsA("BasePart") then
                c.Anchored = true
                c.CanCollide = false
                c.CFrame = origin
                c.Parent = container
            elseif c:IsA("Model") then
                anchorModel(c)
                c.Parent = container
                c:PivotTo(origin)
            else
                c.Parent = anchor
            end
        end
    end

    local props = eff:FindFirstChild("Props")
    if props then
        for _, p in ipairs(props:GetChildren()) do
            local c = p:Clone()
            if c:IsA("BasePart") then
                c.Anchored = true
                c.CanCollide = false
                c.CFrame = origin
                c.Parent = container
            elseif c:IsA("Model") then
                anchorModel(c)
                c.Parent = container
                c:PivotTo(origin)
            else
                c.Parent = anchor
            end
        end
    end

    for _, e in ipairs(container:GetDescendants()) do
        if e:IsA("ParticleEmitter") then
            emitEmitter(e)
        end
    end

    Debris:AddItem(container, 8)
end

local names = effectNames()
local selectedEffect = names[1]

local lastCF = {}
C(RunService.Heartbeat, function()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local ch = plr.Character
            local hrp = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso") or ch:FindFirstChild("UpperTorso"))
            if hrp then lastCF[plr] = hrp.CFrame end
        end
    end
end)
C(Players.PlayerRemoving, function(plr)
    lastCF[plr] = nil
end)

local fxStamp = {}

local function triggerKill(victim)
    if not KILLFX.on or not selectedEffect then return end
    if not victim or victim == lp then return end

    local now = os.clock()
    if fxStamp[victim] and now - fxStamp[victim] < 2 then return end
    fxStamp[victim] = now

    local cf = lastCF[victim]
    if not cf then
        local ch = victim.Character
        local hrp = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("Torso") or ch:FindFirstChild("UpperTorso"))
        cf = hrp and hrp.CFrame
    end
    if not cf then return end

    pcall(playEffect, selectedEffect, cf, cf * CFrame.new(0, -2.5, 0), KILLFX.sound)
end

local function resolvePlayer(v)
    local tv = typeof(v)
    if tv == "Instance" then
        if v:IsA("Player") then return v end
        if v:IsA("Model") then return Players:GetPlayerFromCharacter(v) end
        return nil
    end
    if tv == "number" then
        return Players:GetPlayerByUserId(v)
    end
    if tv == "string" then
        local n = tonumber(v)
        if n then
            local p = Players:GetPlayerByUserId(n)
            if p then return p end
        end
        local p = Players:FindFirstChild(v)
        if p and p:IsA("Player") then return p end
        local low = v:lower()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Name:lower() == low or plr.DisplayName:lower() == low then
                return plr
            end
        end
        return nil
    end
    if tv == "table" then
        local id, nm = norm(v)
        if type(id) == "number" then
            local p = Players:GetPlayerByUserId(id)
            if p then return p end
        end
        if type(nm) == "string" then
            return resolvePlayer(nm)
        end
    end
    return nil
end

local KILL_WORDS = { "kill", "elim", "death", "dead", "died", "defeat", "feed", "frag", "score", "knock" }

local function killish(s)
    if type(s) ~= "string" then return false end
    s = s:lower()
    for _, w in ipairs(KILL_WORDS) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local function extractKV(tbl, depth)
    if type(tbl) ~= "table" or depth > 2 then return nil, nil end
    local killer = tbl.Killer or tbl.killer or tbl.KillerId or tbl.killerId or tbl.KillerName or tbl.killerName
        or tbl.Attacker or tbl.attacker or tbl.AttackerId or tbl.By or tbl.by or tbl.Murderer
    local victim = tbl.Victim or tbl.victim or tbl.VictimId or tbl.victimId or tbl.VictimName or tbl.victimName
        or tbl.Target or tbl.target or tbl.Died or tbl.Dead or tbl.Eliminated or tbl.Killed
    if killer ~= nil and victim ~= nil then return killer, victim end
    for _, v in pairs(tbl) do
        if type(v) == "table" then
            local k2, v2 = extractKV(v, depth + 1)
            if k2 ~= nil and v2 ~= nil then return k2, v2 end
        end
    end
    return nil, nil
end

local function ser(v, depth)
    depth = depth or 0
    local tv = typeof(v)
    if tv == "table" then
        if depth >= 2 then return "{...}" end
        local parts = {}
        local n = 0
        for k, x in pairs(v) do
            n = n + 1
            if n > 12 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. ser(x, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

local function handleKillPair(killerRaw, victimRaw)
    local killer = resolvePlayer(killerRaw)
    local victim = resolvePlayer(victimRaw)
    if not victim or victim == lp then return end
    if KILLFX.onlyMine and killer ~= lp then return end
    if not KILLFX.onlyMine and not killer then return end
    triggerKill(victim)
end

local function inspectRemote(rname, ...)
    local args = table.pack(...)

    for i = 1, args.n do
        local a = args[i]
        if type(a) == "table" and a.YourTeam ~= nil and type(a.Teams) == "table" then
            pcall(applyTeams, a)
        end
    end

    if KILLFX.debug then
        local out = {}
        for i = 1, args.n do out[#out + 1] = ser(args[i]) end
        print("[Nexvyr kill-debug] " .. rname .. " (" .. table.concat(out, " | ") .. ")")
    end

    local nameKill = killish(rname)
    local firstKill = type(args[1]) == "string" and killish(args[1])

    for i = 1, args.n do
        if type(args[i]) == "table" then
            local k, v = extractKV(args[i], 0)
            if k ~= nil and v ~= nil then
                handleKillPair(k, v)
                return
            end
        end
    end

    if nameKill or firstKill then
        local base = firstKill and 2 or 1
        local a, b = args[base], args[base + 1]
        if a ~= nil and b ~= nil and resolvePlayer(a) and resolvePlayer(b) then
            handleKillPair(a, b)
        end
    end
end

local hookedRemotes = {}
local function hookRemote(r)
    if hookedRemotes[r] then return end
    if not r:IsA("RemoteEvent") then return end
    hookedRemotes[r] = true
    local rname = r.Name
    C(r.OnClientEvent, function(...)
        pcall(inspectRemote, rname, ...)
    end)
end

for _, d in ipairs(RS:GetDescendants()) do hookRemote(d) end
C(RS.DescendantAdded, hookRemote)

local function hookCharacter(plr, ch)
    if plr == lp then return end
    local hum = ch:WaitForChild("Humanoid", 10)
    if not hum then return end

    C(hum.Died, function()
        local tag = hum:FindFirstChild("creator")
        if tag and tag:IsA("ObjectValue") and tag.Value then
            if tag.Value == lp then
                triggerKill(plr)
            elseif not KILLFX.onlyMine then
                triggerKill(plr)
            end
            return
        end

        if not KILLFX.fallback then return end
        local wasEn = isEnemy(plr)
        task.delay(0.4, function()
            if fxStamp[plr] and os.clock() - fxStamp[plr] < 2 then return end
            if wasEn or enemyIds[plr.UserId] or enemyNames[plr.Name] then
                triggerKill(plr)
            end
        end)
    end)
end

local function hookPlayer(plr)
    if plr == lp then return end
    C(plr.CharacterAdded, function(ch)
        task.spawn(hookCharacter, plr, ch)
    end)
    if plr.Character then
        task.spawn(hookCharacter, plr, plr.Character)
    end
end

for _, plr in ipairs(Players:GetPlayers()) do
    hookPlayer(plr)
end
C(Players.PlayerAdded, hookPlayer)

local moveRemote = nil
local function notify(kind, on)
    if not moveRemote then
        local r = RS:FindFirstChild("MovementState")
        if r and r:IsA("RemoteEvent") then moveRemote = r end
    end
    if moveRemote then
        pcall(function() moveRemote:FireServer(kind, on) end)
    end
end

local SPEED = 28.7
local JUMP_POWER = 45
local SMOOTH = 14

local speedConn, jumpConn, requestConn
local smoothDir = Vector3.zero
local jumping = false
local vy = 0

local function getChar()
    local c = lp.Character
    if not c then return end
    return c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart")
end

local function SetSpeed(state)
    if speedConn then speedConn:Disconnect() speedConn = nil end
    smoothDir = Vector3.zero
    if not state then return end

    speedConn = RunService.Stepped:Connect(function(_, dt)
        local hum, root = getChar()
        if not hum or not root or hum.Health <= 0 then return end

        local alpha = 1 - math.exp(-SMOOTH * dt)
        smoothDir = smoothDir:Lerp(hum.MoveDirection, alpha)

        if smoothDir.Magnitude > 0.01 then
            local extra = math.max(SPEED - hum.WalkSpeed, 0)
            root.CFrame = root.CFrame + smoothDir * extra * dt
        end
    end)
end

local function SetInfJump(state)
    if jumpConn then jumpConn:Disconnect() jumpConn = nil end
    if requestConn then requestConn:Disconnect() requestConn = nil end
    jumping = false
    vy = 0
    if not state then return end

    requestConn = UserInputService.JumpRequest:Connect(function()
        jumping = true
    end)

    jumpConn = RunService.Stepped:Connect(function(_, dt)
        local hum, root = getChar()
        if not hum or not root or hum.Health <= 0 then return end

        local held = UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump
        if jumping and not held then jumping = false end

        local target = jumping and JUMP_POWER or 0
        vy = vy + (target - vy) * (1 - math.exp(-SMOOTH * dt))

        if vy > 0.5 then
            root.CFrame = root.CFrame + Vector3.new(0, vy * dt, 0)
            local v = root.AssemblyLinearVelocity
            if v.Y < 0 then
                root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
            end
        end
    end)
end

local ROUND = { labels = {}, scanAt = 0, checkAt = 0, ok = false }

local COUNT_WORDS = { "start", "begin", "ready", "fight", "countdown", "comienza", "empieza", "inicia", "prepar", "listo" }

local function guiShown(g)
    local o = g
    while o do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("ScreenGui") and not o.Enabled then return false end
        o = o.Parent
    end
    return true
end

local function mapVotingOpen()
    local pg = lp:FindFirstChild("PlayerGui")
    local main = pg and pg:FindFirstChild("Main")
    local mv = main and main:FindFirstChild("MapVoting")
    if not mv then return false end
    local vh = mv:FindFirstChild("VotingHolder")
    if vh then
        for _, b in ipairs(vh:GetChildren()) do
            if b:IsA("ImageButton") and b.Name ~= "" and guiShown(b) then return true end
        end
        return false
    end
    return guiShown(mv)
end

local function refreshLabels(now)
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then return end
    if ROUND.pg ~= pg then
        ROUND.pg = pg
        ROUND.scanAt = 0
        C(pg.DescendantAdded, function(d)
            if d:IsA("TextLabel") then ROUND.labels[#ROUND.labels + 1] = d end
        end)
    end
    if now - ROUND.scanAt < 5 then return end
    ROUND.scanAt = now
    local list = {}
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then list[#list + 1] = d end
    end
    ROUND.labels = list
end

local function countdownShowing()
    for _, l in ipairs(ROUND.labels) do
        if l.Parent then
            local t = l.Text
            if t ~= "" and #t < 60 and t:find("%d") then
                local low = t:lower()
                for _, w in ipairs(COUNT_WORDS) do
                    if low:find(w, 1, true) and guiShown(l) then return true end
                end
            end
        end
    end
    return false
end

local function roundActive(hum, root)
    local now = os.clock()
    if now - ROUND.checkAt < 0.2 then return ROUND.ok end
    ROUND.checkAt = now
    refreshLabels(now)
    ROUND.ok = enPartida()
        and not mapVotingOpen()
        and not countdownShowing()
        and not root.Anchored
        and hum.WalkSpeed > 0.5
    return ROUND.ok
end

local KNIFE_WORDS = { "knife", "cuchillo", "blade", "dagger", "daga", "machete", "katana", "sword", "espada", "kunai", "melee" }
local GUN_WORDS = { "gun", "pistol", "rifle", "revolver", "pistola", "shotgun", "sniper", "smg", "uzi", "glock", "launcher", "bow" }

local function nameHas(s, words)
    s = tostring(s):lower()
    for _, w in ipairs(words) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local function toolIsKnife(t)
    if nameHas(t.Name, KNIFE_WORDS) then return true end
    for _, a in ipairs({ "Type", "ItemType", "Category", "Class", "WeaponType", "Slot" }) do
        local v = t:GetAttribute(a)
        if type(v) == "string" and nameHas(v, KNIFE_WORDS) then return true end
    end
    return false
end

local KK = { on = false, stopped = false }

local kkNet = RS:WaitForChild("Packages"):WaitForChild("Net")
local kkKey = game.JobId
genv.__RE_FINDER = genv.__RE_FINDER or {}
local kkManual = {}
local kkFound = genv.__RE_FINDER[kkKey]

local function kkIsEnemy(v)
    if not v or v == lp then return false end
    local a = lp:GetAttribute("Team")
    local b = v:GetAttribute("Team")
    if a ~= nil and b ~= nil then return a ~= b end
    return true
end

local function kkGetTarget()
    local m = lp:GetAttribute("Map")
    local gm = lp:GetAttribute("Game")
    for _, v in ipairs(Players:GetPlayers()) do
        if v ~= lp then
            local c = v.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 and kkIsEnemy(v) and v:GetAttribute("Map") == m and v:GetAttribute("Game") == gm then
                return v
            end
        end
    end
end

local function kkGetList()
    if #kkManual > 0 then return kkManual end
    local t = {}
    for _, o in ipairs(kkNet:GetChildren()) do
        if o:IsA("RemoteEvent") and o.Name:sub(1, 3) == "RE/" then
            t[#t + 1] = o.Name
        end
    end
    return t
end

local function kkFire(name)
    local re = kkNet:FindFirstChild(name)
    local tg = kkGetTarget()
    if re and tg then
        re:FireServer("bb15e94b-1af0-48fe-be2b-b2f9e007565a", tg)
    end
end

local function kkWaitMap()
    while lp:GetAttribute("Map") == nil and not KK.stopped do
        lp:GetAttributeChangedSignal("Map"):Wait()
    end
end

local function kkTest(name)
    local tg = kkGetTarget()
    if not tg then return false end
    local c = tg.Character or tg.CharacterAdded:Wait()
    local h = c:WaitForChild("Humanoid", 5)
    if not h or h.Health <= 0 then return false end
    local dead = false
    local cn = h.Died:Connect(function() dead = true end)
    local t = os.clock()
    while os.clock() - t < 3 do
        if dead or h.Health <= 0 then dead = true break end
        kkFire(name)
        task.wait()
    end
    cn:Disconnect()
    return dead
end

local function kkWaitTg()
    while KK.on and not kkGetTarget() and not KK.stopped do
        task.wait(0.5)
    end
    return kkGetTarget() ~= nil
end

local kkSg = Instance.new("ScreenGui")
kkSg.Name = "kk"
kkSg.ResetOnSpawn = false
kkSg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
safeParent(kkSg)

local kkB = Instance.new("TextButton")
kkB.Size = UDim2.new(0, 160, 0, 45)
kkB.Position = UDim2.new(0, 20, 0, 200)
kkB.BackgroundColor3 = Color3.fromRGB(170, 40, 40)
kkB.TextColor3 = Color3.new(1, 1, 1)
kkB.Font = Enum.Font.GothamBold
kkB.TextSize = 16
kkB.BorderSizePixel = 0
kkB.Active = true
kkB.Draggable = true
kkB.Text = "KillAll: OFF"
kkB.Parent = kkSg

local kkUc = Instance.new("UICorner")
kkUc.CornerRadius = UDim.new(0, 8)
kkUc.Parent = kkB

local kkWindToggle

local function killAllSet(v, fromUI)
    v = v and true or false
    KK.on = v
    kkB.Text = "KillAll: " .. (v and "ON" or "OFF")
    kkB.BackgroundColor3 = v and Color3.fromRGB(40, 170, 70) or Color3.fromRGB(170, 40, 40)
    if not fromUI and kkWindToggle then
        pcall(function() kkWindToggle:Set(v) end)
    end
end

kkB.MouseButton1Click:Connect(function()
    killAllSet(not KK.on, false)
end)

task.spawn(function()
    pcall(kkWaitMap)
    while not KK.stopped do
        if not KK.on then
            task.wait(0.1)
        elseif not kkFound then
            if kkWaitTg() then
                for _, nm in ipairs(kkGetList()) do
                    if not KK.on or KK.stopped then break end
                    if kkTest(nm) then
                        kkFound = nm
                        genv.__RE_FINDER[kkKey] = nm
                        break
                    else
                        kkWaitTg()
                    end
                end
            end
        else
            kkFire(kkFound)
            task.wait()
        end
    end
end)

local SHOOT = { acc = 0 }

local function heldGun(ch)
    local held
    for _, t in ipairs(ch:GetChildren()) do
        if t:IsA("Tool") then held = t break end
    end
    if not held then return nil end
    if nameHas(held.Name, GUN_WORDS) then return held end
    if toolIsKnife(held) then return nil end
    local bp = lp:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and nameHas(t.Name, GUN_WORDS) then return nil end
        end
    end
    return held
end

C(RunService.Heartbeat, function(dt)
    if not SILENT.autoshoot then return end
    SHOOT.acc = SHOOT.acc + dt
    if SHOOT.acc < 0.05 then return end
    SHOOT.acc = 0

    local tgt = SILENT.target
    if KK.on or not tgt or not tgt.Parent then return end
    local ch = lp.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or not enPartida() then return end

    local gun = heldGun(ch)
    if not gun then return end
    pcall(function() gun:Activate() end)
end)

local ARRIVE = 2.4
local ON_PAD = 3.4
local BOOTH_LINK = 14

local AUTO = {
    pos = nil,
    side = "Derecho",
    duel = "1vs1",
    flip = false,
    acc = 0,
    voted = nil,
    lastVote = 0,
    pads = nil,
    booths = nil,
    signs = nil,
    legacy = nil,
    scanAt = 0,
    st = nil,
    confirmed = false,
    bad = {},
    waypoints = nil,
    wpIndex = 1,
    pathDest = nil,
    pathAt = 0,
    pathBusy = false,
    pathVer = 0,
    pathFails = 0,
    progPos = nil,
    progTime = 0,
    stuckN = 0,
    sideDest = nil,
    sideUntil = 0,
    searchDest = nil,
    searchAt = 0,
    searchR = 30,
    warned = false,
}

local PADCACHE = {}

local function autoReset()
    AUTO.pads = nil
    AUTO.booths = nil
    AUTO.signs = nil
    AUTO.legacy = nil
    AUTO.scanAt = 0
    AUTO.st = nil
    AUTO.confirmed = false
    AUTO.bad = {}
    AUTO.pathVer = AUTO.pathVer + 1
    AUTO.waypoints = nil
    AUTO.wpIndex = 1
    AUTO.pathDest = nil
    AUTO.pathAt = 0
    AUTO.pathBusy = false
    AUTO.pathFails = 0
    AUTO.progPos = nil
    AUTO.stuckN = 0
    AUTO.sideUntil = 0
    AUTO.searchDest = nil
    AUTO.warned = false
end

local function autoAttr(name)
    local v = lp:GetAttribute(name)
    if typeof(v) == "string" and v ~= "" then return v end
    return nil
end

local function autoInMatch()
    return enPartida()
end

local function autoFirstPart(inst)
    if inst:IsA("BasePart") then return inst end
    local named = inst:FindFirstChild("Pad", true)
    if named and named:IsA("BasePart") then return named end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function flatDist(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function counterHostPos(label)
    local g = label:FindFirstAncestorOfClass("BillboardGui") or label:FindFirstAncestorOfClass("SurfaceGui")
    if not g then return nil end
    local host = g.Parent
    if g:IsA("BillboardGui") and g.Adornee then host = g.Adornee end
    if not host then return nil end
    if host:IsA("BasePart") then
        if inCharacter(host) then return nil end
        return host.Position
    end
    if host:IsA("Attachment") then
        if host.Parent and host.Parent:IsA("BasePart") and inCharacter(host.Parent) then return nil end
        return host.WorldPosition
    end
    if host:IsA("Model") then
        if host:FindFirstChildOfClass("Humanoid") then return nil end
        local s, cf = pcall(function() return host:GetPivot() end)
        if s then return cf.Position end
    end
    return nil
end

local function groundPoint(x, z, refY)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ex = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then ex[#ex + 1] = pl.Character end
    end
    rp.FilterDescendantsInstances = ex
    rp.IgnoreWater = true
    local res = workspace:Raycast(Vector3.new(x, refY + 4, z), Vector3.new(0, -30, 0), rp)
    if res then return Vector3.new(x, res.Position.Y + 0.5, z) end
    return Vector3.new(x, refY - 2.5, z)
end

local function parseCounter(text)
    text = text:gsub("<[^>]+>", "")
    local a, b = text:match("^%s*(%d+)%s*/%s*(%d+)%s*$")
    return tonumber(a), tonumber(b)
end

local function readPad(pad)
    for _, l in ipairs(pad.labels) do
        if l.Parent then
            local n = parseCounter(l.Text)
            if n then return n end
        end
    end
    return nil
end

local function padLabelsAlive(pad)
    for _, l in ipairs(pad.labels) do
        if l.Parent then return true end
    end
    return false
end

local function scanWorld()
    local pads, signs = {}, {}

    local function add(d)
        local raw = d.Text
        if raw == "" or #raw > 80 then return end
        local txt = raw:gsub("<[^>]+>", "")
        local a, b = txt:match("^%s*(%d+)%s*/%s*(%d+)%s*$")
        if a then
            local cap = tonumber(b)
            if not cap or cap < 1 or cap > 5 then return end
            local p = counterHostPos(d)
            if not p then return end
            for _, e in ipairs(pads) do
                if e.cap == cap and flatDist(e.pos, p) < 3.5 then
                    e.labels[#e.labels + 1] = d
                    return
                end
            end
            pads[#pads + 1] = { cap = cap, pos = p, labels = { d } }
            return
        end
        local x, y = txt:match("^%s*(%d)%s*[vV][sS]?%s*(%d)%s*$")
        if x and x == y then
            local p = counterHostPos(d)
            if not p then return end
            for _, s in ipairs(signs) do
                if s.n == tonumber(x) and flatDist(s.pos, p) < 3.5 then return end
            end
            signs[#signs + 1] = { n = tonumber(x), pos = p }
        end
    end

    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("TextLabel") then add(d) end
    end
    local pg = lp:FindFirstChild("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") then
                local g = d:FindFirstAncestorOfClass("BillboardGui")
                if g and g.Adornee then add(d) end
            end
        end
    end

    for _, e in ipairs(pads) do
        e.key = string.format("%d_%d_%d_%d", e.cap, math.floor(e.pos.X + 0.5), math.floor(e.pos.Y + 0.5), math.floor(e.pos.Z + 0.5))
    end
    return pads, signs
end

local function domAxis(list, getPos)
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, it in ipairs(list) do
        local p = getPos(it)
        if p.X < minX then minX = p.X end
        if p.X > maxX then maxX = p.X end
        if p.Z < minZ then minZ = p.Z end
        if p.Z > maxZ then maxZ = p.Z end
    end
    if (maxX - minX) >= (maxZ - minZ) then return "X" end
    return "Z"
end

local function sortAlong(list, getPos)
    if #list < 2 then return end
    local ax = domAxis(list, getPos)
    table.sort(list, function(a, b) return getPos(a)[ax] < getPos(b)[ax] end)
end

local function buildBooths(pads)
    local booths = {}
    for _, e in ipairs(pads) do
        local target
        for _, b in ipairs(booths) do
            if b.cap == e.cap then
                for _, m in ipairs(b.pads) do
                    if flatDist(m.pos, e.pos) < BOOTH_LINK then
                        target = b
                        break
                    end
                end
            end
            if target then break end
        end
        if target then
            target.pads[#target.pads + 1] = e
        else
            booths[#booths + 1] = { cap = e.cap, pads = { e } }
        end
    end
    for _, b in ipairs(booths) do
        local sum = Vector3.new(0, 0, 0)
        for _, m in ipairs(b.pads) do sum = sum + m.pos end
        b.center = sum / #b.pads
        sortAlong(b.pads, function(e) return e.pos end)
    end
    return booths
end

local function pickBySide(list, getPos)
    if #list == 0 then return nil end
    if #list == 1 then return list[1] end
    sortAlong(list, getPos)
    if AUTO.side == "Izquierdo" then return list[1] end
    return list[#list]
end

local function findLegacyPad(idx)
    local zones = workspace:FindFirstChild("PadZones", true)
    if not zones then return nil end
    local zoneNumber = (AUTO.side == "Izquierdo") and (idx + 4) or idx
    local zone = zones:FindFirstChild("PadZone" .. zoneNumber)
    if not zone then return nil end
    local holder = zone:FindFirstChild("Pad" .. AUTO.pos)
    if not holder then
        for _, d in ipairs(zone:GetDescendants()) do
            if d.Name == "Pad" .. AUTO.pos then
                holder = d
                break
            end
        end
    end
    if not holder then return nil end
    local part = autoFirstPart(holder)
    if not part then return nil end
    local pos = part.Position
    local key = "zone_" .. zoneNumber .. "_" .. AUTO.pos
    PADCACHE[key] = Vector3.new(pos.X, pos.Y + part.Size.Y / 2 + 0.5, pos.Z)
    return { key = key, cap = idx, labels = {}, pos = pos, legacy = true }
end

local function worldExtents(part)
    local cf, s = part.CFrame, part.Size
    local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
    local function ext(c)
        return math.abs(r[c]) * s.X + math.abs(u[c]) * s.Y + math.abs(l[c]) * s.Z
    end
    return ext("X"), ext("Y"), ext("Z")
end

local function refineBooth(booth, rootY)
    local need = false
    for _, p in ipairs(booth.pads) do
        if not PADCACHE[p.key] then need = true end
    end
    if not need then return end

    local cands = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and not inCharacter(d) then
            local pos = d.Position
            if flatDist(pos, booth.center) <= 22 then
                local w, h, dd = worldExtents(d)
                local top = pos.Y + h / 2
                if h <= 1.6 and w >= 2 and w <= 12 and dd >= 2 and dd <= 12
                    and top >= rootY - 7 and top <= rootY + 1.5 then
                    local nm = (d.Name .. " " .. (d.Parent and d.Parent.Name or "")):lower()
                    local named = (nm:find("pad") or nm:find("zone") or nm:find("queue")
                        or nm:find("join") or nm:find("circle") or nm:find("spot")) and true or false
                    cands[#cands + 1] = { top = Vector3.new(pos.X, top + 0.5, pos.Z), named = named }
                end
            end
        end
    end

    local namedList = {}
    for _, c in ipairs(cands) do
        if c.named then namedList[#namedList + 1] = c end
    end
    if #namedList >= #booth.pads then cands = namedList end

    local uniq = {}
    for _, c in ipairs(cands) do
        local dup = false
        for _, u in ipairs(uniq) do
            if flatDist(u.top, c.top) < 1.5 then
                dup = true
                break
            end
        end
        if not dup then uniq[#uniq + 1] = c end
    end

    local pairsList = {}
    for i, p in ipairs(booth.pads) do
        for j, c in ipairs(uniq) do
            pairsList[#pairsList + 1] = { i = i, j = j, d = flatDist(p.pos, c.top) }
        end
    end
    table.sort(pairsList, function(a, b) return a.d < b.d end)
    local usedP, usedC, chosen = {}, {}, {}
    for _, pr in ipairs(pairsList) do
        if pr.d <= 14 and not usedP[pr.i] and not usedC[pr.j] then
            usedP[pr.i] = true
            usedC[pr.j] = true
            chosen[pr.i] = uniq[pr.j].top
        end
    end

    for i, p in ipairs(booth.pads) do
        PADCACHE[p.key] = chosen[i] or groundPoint(p.pos.X, p.pos.Z, rootY)
    end
end

local function orderedPads(booth)
    local n = #booth.pads
    local want = math.min(AUTO.pos, n)
    if AUTO.flip then want = n + 1 - want end
    local out = { booth.pads[want] }
    for i, p in ipairs(booth.pads) do
        if i ~= want then out[#out + 1] = p end
    end
    return out
end

local function autoFindVoteRemote()
    local pk = RS:FindFirstChild("Packages")
    local net = pk and pk:FindFirstChild("Networking")
    local r = net and net:FindFirstChild("RF/Voting/Vote")
    if r and r:IsA("RemoteFunction") then return r end
    return nil
end

local function autoFindVisibleMap()
    local pg = lp:FindFirstChild("PlayerGui")
    local main = pg and pg:FindFirstChild("Main")
    local mv = main and main:FindFirstChild("MapVoting")
    local vh = mv and mv:FindFirstChild("VotingHolder")
    if not vh then return nil end
    for _, b in ipairs(vh:GetChildren()) do
        if b:IsA("ImageButton") and b.Visible and b.Name ~= "" then
            return b.Name
        end
    end
    return nil
end

local function autoVote()
    local gameAttr = autoAttr("Game")
    if not gameAttr then
        AUTO.voted = nil
        return
    end
    if AUTO.voted == gameAttr then return end
    local now = os.clock()
    if now - AUTO.lastVote < 1 then return end
    AUTO.lastVote = now
    local mapName = autoFindVisibleMap()
    local rf = autoFindVoteRemote()
    if not (mapName and rf) then return end
    AUTO.voted = gameAttr
    task.spawn(function()
        pcall(function() rf:InvokeServer(mapName) end)
    end)
end

local function requestPath(root, dest)
    AUTO.pathBusy = true
    AUTO.pathAt = os.clock()
    local ver = AUTO.pathVer
    local from = root.Position
    task.spawn(function()
        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
        })
        local s = pcall(function() path:ComputeAsync(from, dest) end)
        AUTO.pathBusy = false
        if ver ~= AUTO.pathVer then return end
        if s and path.Status == Enum.PathStatus.Success then
            local wps = path:GetWaypoints()
            if #wps > 0 then
                AUTO.waypoints = wps
                AUTO.wpIndex = (#wps >= 2) and 2 or 1
                AUTO.pathDest = dest
                AUTO.pathFails = 0
                return
            end
        end
        AUTO.pathFails = AUTO.pathFails + 1
        AUTO.pathDest = dest
        AUTO.waypoints = nil
    end)
end

local function walkTo(hum, root, dest)
    local now = os.clock()
    local pos = root.Position
    local d = flatDist(pos, dest)

    if not AUTO.progPos or (pos - AUTO.progPos).Magnitude > 1.5 then
        AUTO.progPos = pos
        AUTO.progTime = now
        AUTO.stuckN = 0
    elseif now - AUTO.progTime > 1.3 and d > ARRIVE then
        AUTO.progTime = now
        AUTO.stuckN = AUTO.stuckN + 1
        hum.Jump = true
        AUTO.waypoints = nil
        AUTO.pathAt = 0
        if AUTO.stuckN >= 2 then
            local dx, dz = dest.X - pos.X, dest.Z - pos.Z
            local m = math.sqrt(dx * dx + dz * dz)
            if m > 0.1 then
                local sgn = (AUTO.stuckN % 2 == 0) and 1 or -1
                AUTO.sideDest = pos + Vector3.new(-dz / m, 0, dx / m) * (6 * sgn)
                AUTO.sideUntil = now + 0.9
            end
        end
    end
    if AUTO.sideDest and now < AUTO.sideUntil then
        hum:MoveTo(AUTO.sideDest)
        return
    end

    if d > 8 and AUTO.pathFails < 4 then
        local need = (not AUTO.waypoints) or (not AUTO.pathDest) or flatDist(AUTO.pathDest, dest) > 4
        if need and not AUTO.pathBusy and now - AUTO.pathAt > 1.2 then
            requestPath(root, dest)
        end
        local wps = AUTO.waypoints
        if wps then
            while AUTO.wpIndex <= #wps and flatDist(wps[AUTO.wpIndex].Position, pos) < 3.2 do
                AUTO.wpIndex = AUTO.wpIndex + 1
            end
            if AUTO.wpIndex <= #wps then
                local wp = wps[AUTO.wpIndex]
                local fd = flatDist(wp.Position, pos)
                if fd > 30 then
                    AUTO.waypoints = nil
                else
                    if wp.Action == Enum.PathWaypointAction.Jump and fd < 7 then hum.Jump = true end
                    hum:MoveTo(wp.Position)
                    return
                end
            end
        end
    end
    hum:MoveTo(dest)
end

local function searchTarget(root, idx)
    local rpos = root.Position

    local list = {}
    for _, s in ipairs(AUTO.signs or {}) do
        if s.n == idx then list[#list + 1] = s end
    end
    local s = pickBySide(list, function(x) return x.pos end)
    if s and flatDist(s.pos, rpos) > 8 then
        return groundPoint(s.pos.X, s.pos.Z, rpos.Y)
    end

    local booths = AUTO.booths or {}
    local n1
    for _, b in ipairs(booths) do
        if b.cap ~= idx and (not n1 or flatDist(b.center, rpos) < flatDist(n1.center, rpos)) then n1 = b end
    end
    if n1 then
        local n2
        for _, b in ipairs(booths) do
            if b ~= n1 and b.cap ~= n1.cap and (not n2 or flatDist(b.center, n1.center) < flatDist(n2.center, n1.center)) then
                n2 = b
            end
        end
        local est
        if n2 then
            local step = (n2.center - n1.center) / (n2.cap - n1.cap)
            est = n1.center + step * (idx - n1.cap)
        else
            est = n1.center
        end
        if flatDist(est, rpos) > 8 then
            return groundPoint(est.X, est.Z, rpos.Y)
        end
    end

    AUTO.searchR = math.min(AUTO.searchR + 15, 120)
    local ang = math.random() * math.pi * 2
    return groundPoint(rpos.X + math.cos(ang) * AUTO.searchR, rpos.Z + math.sin(ang) * AUTO.searchR, rpos.Y)
end

local function autoSearch(hum, root, now, idx)
    AUTO.warned = true
    local dest = AUTO.searchDest
    if dest and (flatDist(root.Position, dest) < 5 or now - AUTO.searchAt > 9) then dest = nil end
    if not dest then
        dest = searchTarget(root, idx)
        AUTO.searchDest = dest
        AUTO.searchAt = now
        AUTO.waypoints = nil
        AUTO.pathDest = nil
    end
    walkTo(hum, root, dest)
end

local function choosePad(order, root, now)
    if AUTO.confirmed and AUTO.st then
        for _, p in ipairs(order) do
            if p.key == AUTO.st.key then return p end
        end
    end
    for _, p in ipairs(order) do
        local c = readPad(p)
        local center = PADCACHE[p.key]
        local near = center and flatDist(root.Position, center) <= ON_PAD + 1
        local full = (c ~= nil) and (c >= p.cap) and not near
        local bad = AUTO.bad[p.key] and AUTO.bad[p.key] > now
        if not full and not bad then return p end
    end
    return order[1]
end

local function nudge(hum, root, center, booth, st, now)
    local t = now - st.onSince
    if t < 1.2 then
        hum:MoveTo(center)
        return
    end
    local offs = {
        Vector3.new(0, 0, 0), Vector3.new(1.6, 0, 0), Vector3.new(-1.6, 0, 0),
        Vector3.new(0, 0, 1.6), Vector3.new(0, 0, -1.6),
    }
    local k = math.floor((t - 1.2) / 1.3) + 1
    if k <= #offs then
        if k == 3 then hum.Jump = true end
        hum:MoveTo(center + offs[k])
        return
    end
    st.tries = st.tries + 1
    local from = st.cameFrom
    local ox, oz
    if from and flatDist(from, center) > 1 then
        ox, oz = from.X - center.X, from.Z - center.Z
    else
        ox, oz = center.X - booth.center.X, center.Z - booth.center.Z
    end
    local m = math.sqrt(ox * ox + oz * oz)
    if m < 0.1 then ox, oz, m = 0, 1, 1 end
    st.stepOutDest = Vector3.new(center.X + ox / m * 7, center.Y, center.Z + oz / m * 7)
    st.stepOutUntil = now + 1.8
    st.onSince = nil
    if st.tries >= 2 then AUTO.bad[st.key] = now + 25 end
end

local function autoTick()
    if not AUTO.pos then return end
    if autoInMatch() then
        if AUTO.st or AUTO.confirmed then autoReset() end
        return
    end

    autoVote()

    local ch = lp.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return end

    if autoAttr("Game") then
        hum:MoveTo(root.Position)
        return
    end

    local now = os.clock()
    local idx = tonumber(AUTO.duel:sub(1, 1)) or 1

    local stale = false
    if AUTO.pads then
        for _, p in ipairs(AUTO.pads) do
            if not padLabelsAlive(p) then
                stale = true
                break
            end
        end
    end
    local hasTarget = false
    if AUTO.booths then
        for _, b in ipairs(AUTO.booths) do
            if b.cap == idx then hasTarget = true break end
        end
    end
    local interval = hasTarget and (AUTO.confirmed and 1e9 or 12) or 3
    if not AUTO.pads or stale or now - AUTO.scanAt > interval then
        AUTO.scanAt = now
        AUTO.pads, AUTO.signs = scanWorld()
        AUTO.booths = buildBooths(AUTO.pads)
        AUTO.legacy = nil
        local any = false
        for _, b in ipairs(AUTO.booths) do
            if b.cap == idx then any = true break end
        end
        if not any then AUTO.legacy = findLegacyPad(idx) or false end
    end

    local booth, order
    do
        local list = {}
        for _, b in ipairs(AUTO.booths or {}) do
            if b.cap == idx then list[#list + 1] = b end
        end
        booth = pickBySide(list, function(b) return b.center end)
        if booth then
            refineBooth(booth, root.Position.Y)
            order = orderedPads(booth)
        elseif AUTO.legacy then
            booth = { cap = idx, pads = { AUTO.legacy }, center = AUTO.legacy.pos }
            order = { AUTO.legacy }
        end
    end

    if not booth then
        autoSearch(hum, root, now, idx)
        return
    end
    AUTO.searchDest = nil
    AUTO.warned = false

    local pad = choosePad(order, root, now)
    local center = PADCACHE[pad.key]
    if not center then return end

    local st = AUTO.st
    if not st or st.key ~= pad.key then
        st = { key = pad.key, phase = "go", tries = 0, onSince = nil, base = nil, cameFrom = nil }
        AUTO.st = st
        AUTO.confirmed = false
        AUTO.waypoints = nil
        AUTO.pathDest = nil
        AUTO.pathAt = 0
        AUTO.pathFails = 0
    end

    local count = readPad(pad)
    local rp = root.Position
    local dist = flatDist(rp, center)
    local on = dist <= ON_PAD and math.abs(rp.Y - center.Y) < 10

    if dist > ON_PAD + 2 then
        st.base = count
        st.cameFrom = rp
    end

    if st.phase == "joined" then
        if on and (count == nil or count >= 1) then
            st.lostAt = nil
            hum:MoveTo(rp)
            return
        end
        st.lostAt = st.lostAt or now
        if now - st.lostAt < 1.0 then
            hum:MoveTo(rp)
            return
        end
        st.phase = "go"
        st.onSince = nil
        st.lostAt = nil
        st.base = nil
        AUTO.confirmed = false
    end

    if st.stepOutUntil and now < st.stepOutUntil then
        hum:MoveTo(st.stepOutDest)
        return
    end

    if not on then
        st.onSince = nil
        walkTo(hum, root, center)
        return
    end

    st.onSince = st.onSince or now

    local joined
    if count ~= nil then
        if st.base ~= nil then
            joined = count > st.base
        else
            joined = count >= 1
        end
    else
        joined = (now - st.onSince) > 1.5
    end

    if joined then
        st.phase = "joined"
        st.lostAt = nil
        AUTO.confirmed = true
        hum:MoveTo(rp)
        return
    end

    nudge(hum, root, center, booth, st, now)
end

C(RunService.Heartbeat, function(dt)
    if not AUTO.pos then return end
    AUTO.acc = AUTO.acc + dt
    if AUTO.acc < 0.1 then return end
    AUTO.acc = 0
    local s, e = pcall(autoTick)
    if not s then warn("NEXVYRHUB auto: " .. tostring(e)) end
end)

C(lp.CharacterAdded, function()
    autoReset()
end)

local GFX = { on = false, saved = setmetatable({}, { __mode = "k" }), sa = {}, conns = {}, gen = 0, restoring = false, g = {} }

do
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")

local function save(inst, props)
    local s = GFX.saved[inst]
    if not s then
        s = {}
        GFX.saved[inst] = s
    end
    for _, prop in ipairs(props) do
        if s[prop] == nil then
            local okp, v = pcall(function() return inst[prop] end)
            if okp then s[prop] = v end
        end
    end
end

local function isOther(d)
    local m = d:FindFirstAncestorOfClass("Model")
    return m and m ~= lp.Character and m:FindFirstChildOfClass("Humanoid") ~= nil
end

local function clean(d)
    if d:IsA("ParticleEmitter") then
        save(d, { "Enabled", "Rate", "Lifetime" })
        d.Enabled = false
        d.Rate = 0
        d.Lifetime = NumberRange.new(0, 0)
    elseif d:IsA("Trail") or d:IsA("Beam") or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") or d:IsA("Clouds") then
        save(d, { "Enabled" })
        d.Enabled = false
    elseif d:IsA("Explosion") or d:IsA("ForceField") then
        save(d, { "Visible" })
        d.Visible = false
    elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") or d:IsA("Highlight") or d:IsA("PostEffect") then
        save(d, { "Enabled" })
        d.Enabled = false
    elseif d:IsA("Atmosphere") then
        save(d, { "Density", "Haze", "Glare", "Offset" })
        d.Density = 0
        d.Haze = 0
        d.Glare = 0
        d.Offset = 0
    elseif d:IsA("Sky") then
        save(d, { "StarCount", "CelestialBodiesShown" })
        d.StarCount = 0
        d.CelestialBodiesShown = false
    elseif d:IsA("Decal") or d:IsA("Texture") then
        save(d, { "Transparency" })
        d.Transparency = 1
    elseif d:IsA("SurfaceAppearance") then
        GFX.sa[#GFX.sa + 1] = { d, d.Parent }
        d.Parent = nil
    elseif d:IsA("Humanoid") then
        save(d, { "DisplayDistanceType", "HealthDisplayType", "NameDisplayDistance", "HealthDisplayDistance" })
        d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    elseif d:IsA("MeshPart") then
        save(d, { "Material", "Reflectance", "CastShadow", "RenderFidelity", "DoubleSided" })
        d.Material = Enum.Material.SmoothPlastic
        d.Reflectance = 0
        d.CastShadow = false
        d.RenderFidelity = Enum.RenderFidelity.Performance
        pcall(function() d.DoubleSided = false end)
    elseif d:IsA("BasePart") then
        save(d, { "Material", "Reflectance", "CastShadow" })
        d.Material = Enum.Material.SmoothPlastic
        d.Reflectance = 0
        d.CastShadow = false
    elseif d:IsA("Accessory") and isOther(d) then
        local h = d:FindFirstChild("Handle")
        if h and h:IsA("BasePart") then
            save(h, { "Transparency" })
            h.Transparency = 1
        end
    end
end

local function setG(key, getter, setter)
    pcall(function()
        if GFX.g[key] == nil then GFX.g[key] = { getter() } end
        setter()
    end)
end

local function applyGlobal()
    local r = settings().Rendering
    setG("q", function() return r.QualityLevel end, function() r.QualityLevel = Enum.QualityLevel.Level01 end)
    setG("mesh", function() return r.MeshPartDetailLevel end, function() r.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04 end)
    setG("tex", function() return r.TextureQuality end, function() r.TextureQuality = Enum.TextureQuality.Low end)
    setG("shadows", function() return Lighting.GlobalShadows end, function() Lighting.GlobalShadows = false end)
    setG("soft", function() return Lighting.ShadowSoftness end, function() Lighting.ShadowSoftness = 0 end)
    setG("mat22", function() return MaterialService.Use2022Materials end, function() MaterialService.Use2022Materials = false end)
    if sethiddenproperty and gethiddenproperty then
        setG("tech", function() return (gethiddenproperty(Lighting, "Technology")) end, function()
            sethiddenproperty(Lighting, "Technology", Enum.Technology.Compatibility)
        end)
    end
    local terr = workspace:FindFirstChildOfClass("Terrain")
    if terr then
        setG("w1", function() return terr.WaterWaveSize end, function() terr.WaterWaveSize = 0 end)
        setG("w2", function() return terr.WaterWaveSpeed end, function() terr.WaterWaveSpeed = 0 end)
        setG("w3", function() return terr.WaterReflectance end, function() terr.WaterReflectance = 0 end)
        if sethiddenproperty and gethiddenproperty then
            setG("deco", function() return (gethiddenproperty(terr, "Decoration")) end, function()
                sethiddenproperty(terr, "Decoration", false)
            end)
        end
    end
end

local function restoreGlobal()
    local g = GFX.g
    GFX.g = {}
    local r = settings().Rendering
    local terr = workspace:FindFirstChildOfClass("Terrain")
    local function put(key, setter)
        if g[key] ~= nil then pcall(function() setter(g[key][1]) end) end
    end
    put("q", function(v) r.QualityLevel = v end)
    put("mesh", function(v) r.MeshPartDetailLevel = v end)
    put("tex", function(v) r.TextureQuality = v end)
    put("shadows", function(v) Lighting.GlobalShadows = v end)
    put("soft", function(v) Lighting.ShadowSoftness = v end)
    put("mat22", function(v) MaterialService.Use2022Materials = v end)
    put("tech", function(v) sethiddenproperty(Lighting, "Technology", v) end)
    if terr then
        put("w1", function(v) terr.WaterWaveSize = v end)
        put("w2", function(v) terr.WaterWaveSpeed = v end)
        put("w3", function(v) terr.WaterReflectance = v end)
        put("deco", function(v) sethiddenproperty(terr, "Decoration", v) end)
    end
end

function GFX.set(v)
    v = v and true or false
    if v == GFX.on then return end
    GFX.on = v
    GFX.gen = GFX.gen + 1
    local gen = GFX.gen

    if v then
        task.spawn(function()
            while GFX.restoring do task.wait() end
            if gen ~= GFX.gen then return end
            applyGlobal()
            local function watch(root)
                GFX.conns[#GFX.conns + 1] = root.DescendantAdded:Connect(function(d)
                    task.defer(function()
                        if GFX.on then pcall(clean, d) end
                    end)
                end)
            end
            watch(workspace)
            watch(Lighting)
            local n = 0
            local function sweep(root)
                for _, d in ipairs(root:GetDescendants()) do
                    if gen ~= GFX.gen then return false end
                    pcall(clean, d)
                    n = n + 1
                    if n % 500 == 0 then task.wait() end
                end
                return true
            end
            if sweep(Lighting) and sweep(workspace) then
                pcall(collectgarbage, "collect")
            end
        end)
    else
        for _, c in ipairs(GFX.conns) do pcall(function() c:Disconnect() end) end
        GFX.conns = {}
        local snap, sa = GFX.saved, GFX.sa
        GFX.saved = setmetatable({}, { __mode = "k" })
        GFX.sa = {}
        GFX.restoring = true
        task.spawn(function()
            restoreGlobal()
            for _, e in ipairs(sa) do
                pcall(function() e[1].Parent = e[2] end)
            end
            local n = 0
            for inst, props in pairs(snap) do
                for prop, val in pairs(props) do
                    pcall(function() inst[prop] = val end)
                end
                n = n + 1
                if n % 500 == 0 then task.wait() end
            end
            GFX.restoring = false
        end)
    end
end
end

local TITLE_RICH = 'NEXVYRHUB | DUELS <font color="#FFD700">[v2.9] </font>'

local Window = WindUI:CreateWindow({
    Title = TITLE_RICH,
    Author = "By 7.dui, void, jos1k, fabnx1",
    Folder = "Nexvyr_WindUI",
    Acrylic = false,
    Transparent = false,
    NewElements = true,
    HideSearchBar = false,
    Background = "rbxthumb://type=Asset&id=9405835683&w=420&h=420",
    BackgroundImageTransparency = 0.35,
    OpenButton = {
        Title = "Open HUB",
        Icon = "rbxthumb://type=Asset&id=118232139384203&w=420&h=420",
        IconSize = 9,
        CornerRadius = UDim.new(1),
        StrokeThickness = 2,
        Enabled = true,
        Draggable = true,
        Scale = 0.9,
        Color = ColorSequence.new(Color3.fromHex("#110070"), Color3.fromHex("#300364"))
    },
    Topbar = { Height = 44, ButtonsType = "Default" }
})

local TabKill = Window:Tab({ Title = "Matar a todos" })
local TabAim = Window:Tab({ Title = "Aimbot" })
local TabEsp = Window:Tab({ Title = "ESP" })
local TabTramposo = Window:Tab({ Title = "Tramposo" })
local TabAuto = Window:Tab({ Title = "Auto" })
local TabSonidos = Window:Tab({ Title = "Sonidos" })
local TabFps = Window:Tab({ Title = "Fps" })

task.spawn(function()
    local t0 = os.clock()
    while os.clock() - t0 < 6 do
        for _, root in ipairs({ (gethui and gethui()) or CoreGui, CoreGui }) do
            pcall(function()
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text == TITLE_RICH and not d.RichText then
                        d.RichText = true
                    end
                end
            end)
        end
        task.wait(0.5)
    end
end)

TabEsp:Toggle({
    Title = "Highlight con resplandor",
    Value = false,
    Callback = function(v) ESP.hl = v end,
})

TabEsp:Toggle({
    Title = "Cuadro ESP",
    Value = false,
    Callback = function(v) ESP.box = v end,
})

TabEsp:Toggle({
    Title = "Resplandor pulsante",
    Value = true,
    Callback = function(v) ESP.pulse = v end,
})

TabEsp:Colorpicker({
    Title = "Color",
    Default = ESP.color,
    Callback = function(c) ESP.color = c end,
})

TabAim:Toggle({
    Title = "Autoshoot",
    Value = false,
    Callback = function(v)
        SILENT.autoshoot = v
        if v then
            local s, e = pcall(installHooks)
            if not s then warn("NEXVYRHUB: error al instalar hooks: " .. tostring(e)) end
        elseif not SILENT.on then
            SILENT.target = nil
        end
    end,
})

TabAim:Toggle({
    Title = "Silent Aim",
    Value = false,
    Callback = function(v)
        SILENT.on = v
        if v then
            local s, e = pcall(installHooks)
            if not s then warn("NEXVYRHUB: error al instalar hooks: " .. tostring(e)) end
        else
            SILENT.target = nil
        end
    end,
})

TabAim:Dropdown({
    Title = "Parte del cuerpo",
    Values = { "Cabeza", "Torso" },
    Value = "Cabeza",
    Callback = function(v) SILENT.part = v end,
})

TabTramposo:Toggle({
    Title = "Speed",
    Value = false,
    Callback = function(state)
        SetSpeed(state)
        notify("Speed", state)
    end,
})

TabTramposo:Slider({
    Title = "Ajuste Speed",
    Step = 1,
    Value = { Min = 1, Max = 100, Default = 29 },
    Callback = function(v) SPEED = v end,
})

TabTramposo:Toggle({
    Title = "Salto Inf",
    Value = false,
    Callback = function(state)
        SetInfJump(state)
        notify("Jump", state)
    end,
})

TabTramposo:Slider({
    Title = "Ajuste Salto",
    Step = 1,
    Value = { Min = 1, Max = 100, Default = 45 },
    Callback = function(v) JUMP_POWER = v end,
})

TabAuto:Dropdown({
    Title = "Plataforma",
    Values = { "1vs1", "2vs2", "3vs3", "4vs4", "5vs5" },
    Value = "1vs1",
    Callback = function(v)
        AUTO.duel = v
        autoReset()
    end,
})

TabAuto:Dropdown({
    Title = "Lado",
    Values = { "Izquierdo", "Derecho" },
    Value = "Derecho",
    Callback = function(v)
        AUTO.side = v
        autoReset()
    end,
})

TabAuto:Toggle({
    Title = "Invertir posiciones (1 <-> 2)",
    Value = false,
    Callback = function(v)
        AUTO.flip = v
        autoReset()
    end,
})

local togPos1, togPos2
local suppress = false

togPos1 = TabAuto:Toggle({
    Title = "Ir a la posición 1",
    Value = false,
    Callback = function(v)
        if suppress then return end
        if v then
            AUTO.pos = 1
            AUTO.voted = nil
            autoReset()
            if togPos2 then
                suppress = true
                pcall(function() togPos2:Set(false) end)
                suppress = false
            end
        elseif AUTO.pos == 1 then
            AUTO.pos = nil
            autoReset()
        end
    end,
})

togPos2 = TabAuto:Toggle({
    Title = "Ir a la posición 2",
    Value = false,
    Callback = function(v)
        if suppress then return end
        if v then
            AUTO.pos = 2
            AUTO.voted = nil
            autoReset()
            if togPos1 then
                suppress = true
                pcall(function() togPos1:Set(false) end)
                suppress = false
            end
        elseif AUTO.pos == 2 then
            AUTO.pos = nil
            autoReset()
        end
    end,
})

kkWindToggle = TabKill:Toggle({
    Title = "Kill all",
    Value = false,
    Callback = function(v) killAllSet(v, true) end,
})

TabSonidos:Dropdown({
    Title = "Efecto",
    Values = #names > 0 and names or { "(ninguno)" },
    Value = names[1] or "(ninguno)",
    Callback = function(v) selectedEffect = v end,
})

TabFps:Toggle({
    Title = "Gráficos",
    Value = false,
    Callback = function(v) GFX.set(v) end,
})

genv.__NEXVYR_STOP = function()
    pcall(GFX.set, false)
    ESP.hl = false
    ESP.box = false
    SILENT.on = false
    SILENT.target = nil
    KILLFX.on = false
    KILLFX.debug = false
    AUTO.pos = nil
    KK.on = false
    KK.stopped = true
    pcall(function() kkSg:Destroy() end)
    SILENT.autoshoot = false
    pcall(SetSpeed, false)
    pcall(SetInfJump, false)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() holder:Destroy() end)
    pcall(function() boxGui:Destroy() end)
    for _, c in ipairs(workspace:GetChildren()) do
        if c.Name == "NexvyrPreview" then pcall(function() c:Destroy() end) end
    end
    pcall(function() Window:Destroy() end)
    genv.__NEXVYR_STOP = nil
end

pcall(function() Window:SelectTab(1) end)
