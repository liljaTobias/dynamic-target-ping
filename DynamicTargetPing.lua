local ADDON_NAME, ns = ...

local MACRO_NAME = "DynamicTargetPing"
local MACRO_ICON = "INV_Misc_QuestionMark"
local MACRO_MAX_LENGTH = 255
local MAX_CHAR_MACROS = MAX_CHARACTER_MACROS or 30
local PING_LINE = "/ping [@target,exists,nodead] attack"

local pendingRebuild = false
local notifyOnRegen = false

local function Print(msg)
    print("|cff33ff99DynamicTargetPing|r: " .. msg)
end

local function DB()
    DynamicTargetPingDB = DynamicTargetPingDB or {}
    local d = DynamicTargetPingDB
    d.names = d.names or {}
    if d.priority == nil then d.priority = true end
    return d
end

local function IndexOf(list, name)
    local lower = name:lower()
    for i, n in ipairs(list) do
        if n:lower() == lower then return i end
    end
end

local function BuildBody(names)
    local lines = { "/cleartarget" }
    for i, name in ipairs(names) do
        -- [noexists] makes earlier entries win when several are in range.
        if i > 1 and DB().priority then
            lines[#lines + 1] = "/targetexact [noexists] " .. name
        else
            lines[#lines + 1] = "/targetexact " .. name
        end
    end
    lines[#lines + 1] = PING_LINE
    return table.concat(lines, "\n")
end

local function WriteMacro(quiet)
    if InCombatLockdown() then
        if not pendingRebuild and not quiet then
            Print("In combat - macro will update when combat ends.")
        end
        notifyOnRegen = notifyOnRegen or not quiet
        pendingRebuild = true
        return
    end
    pendingRebuild = false

    local body = BuildBody(DB().names)
    if #body > MACRO_MAX_LENGTH then
            Print(("Macro would be %d/%d characters - remove a name (/dtp remove <#>)."):format(#body, MACRO_MAX_LENGTH))
        return
    end
    local index = GetMacroIndexByName(MACRO_NAME)
    if index == 0 then
        local _, numCharMacros = GetNumMacros()
        if numCharMacros >= MAX_CHAR_MACROS then
            Print("Character macro slots are full - free one up and type /dtp to create '" .. MACRO_NAME .. "'.")
            return
        end
        CreateMacro(MACRO_NAME, MACRO_ICON, body, true)
        Print("Created character macro '" .. MACRO_NAME .. "'. Drag it from the /dtp window to your action bar.")
    elseif GetMacroBody(index) ~= body then
        EditMacro(index, nil, nil, body)
    end
end

local function ApplyMacro(quiet)
    WriteMacro(quiet)
    if ns.Refresh then ns.Refresh() end
end

local function GetStatus()
    if pendingRebuild then return "pending" end
    local index = GetMacroIndexByName(MACRO_NAME)
    if index == 0 then return "missing" end
    if GetMacroBody(index) ~= BuildBody(DB().names) then return "stale" end
    return "ok"
end

local function SafeTargetName(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return nil end
    local name = UnitName(unit)
    if name == nil or (issecretvalue and issecretvalue(name)) then return nil end
    return name
end

local function AddName(name, quiet)
    local names = DB().names
    if IndexOf(names, name) then
        Print("'" .. name .. "' is already in the list.")
        return false
    end
    local candidate = { unpack(names) }
    candidate[#candidate + 1] = name
    local len = #BuildBody(candidate)
    if len > MACRO_MAX_LENGTH then
        Print(("Can't add '%s': macro would be %d/%d characters. Remove a name first."):format(name, len, MACRO_MAX_LENGTH))
        return false
    end
    names[#names + 1] = name
    if not quiet then
        Print(("Added '%s' (%d/%d chars)."):format(name, len, MACRO_MAX_LENGTH))
    end
    ApplyMacro(quiet)
    return true
end

local SCAN_OBJECTIVE_TYPES = { monster = true, item = true }

-- Tooltip and quest log format objectives differently, so compare without counts/punctuation.
local function NormalizeObjective(text)
    text = text:lower():gsub("%d+%s*/%s*%d+", ""):gsub("[%-:]", " "):gsub("%s+", " ")
    return strtrim(text)
end

local function WantedObjectives()
    local wanted = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden then
            for _, obj in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                if SCAN_OBJECTIVE_TYPES[obj.type] and not obj.finished and obj.text and obj.text ~= "" then
                    wanted[NormalizeObjective(obj.text)] = true
                end
            end
        end
    end
    return wanted
end

local function UnitHasWantedObjective(unit, wanted)
    local data = C_TooltipInfo.GetUnit(unit)
    if not (data and data.lines) then return false end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if line.type == Enum.TooltipDataLineType.QuestObjective and type(text) == "string"
            and not (issecretvalue and issecretvalue(text))
            and wanted[NormalizeObjective(text)] then
            return true
        end
    end
    return false
end

local function ScanQuestMobs()
    local wanted = WantedObjectives()
    if not next(wanted) then
        Print("No unfinished kill or loot objectives in your quest log.")
        return
    end

    local units = { "target" }
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        units[#units + 1] = plate.namePlateUnitToken
    end

    local names, seen = DB().names, {}
    local added, full = {}, false
    for _, unit in ipairs(units) do
        local name = SafeTargetName(unit)
        if name and not seen[name] and not IndexOf(names, name)
            and UnitCanAttack("player", unit) and not UnitIsPlayer(unit) and not UnitIsDead(unit)
            and UnitHasWantedObjective(unit, wanted) then
            seen[name] = true
            if not AddName(name, true) then
                full = true
                break
            end
            added[#added + 1] = name
        end
    end

    if #added > 0 then
        Print("Added quest mobs: " .. table.concat(added, ", ") .. ".")
    elseif not full then
        Print("No new quest mobs nearby. Enemy nameplates must be visible to scan.")
    end
end

local function RemoveAt(i, quiet)
    local names = DB().names
    local name = table.remove(names, i)
    if name then
        if not quiet then Print("Removed '" .. name .. "'.") end
        ApplyMacro(quiet)
    end
end

local function Move(from, to)
    local names = DB().names
    if from == to or not names[from] or not names[to] then return end
    table.insert(names, to, table.remove(names, from))
    ApplyMacro(true)
end

local function Clear(quiet)
    wipe(DB().names)
    if not quiet then Print("List cleared.") end
    ApplyMacro(quiet)
end

local function SetPriority(on, quiet)
    local d = DB()
    local old = d.priority
    d.priority = on
    local len = #BuildBody(d.names)
    if len > MACRO_MAX_LENGTH then
        d.priority = old
        Print(("Can't switch: macro would be %d/%d characters. Remove a name first."):format(len, MACRO_MAX_LENGTH))
        return false
    end
    if not quiet then Print("Priority mode " .. (on and "on" or "off") .. ".") end
    ApplyMacro(quiet)
    return true
end

local function RemoveName(name)
    local i = IndexOf(DB().names, name)
    if i then
        RemoveAt(i)
    else
        Print("'" .. name .. "' is not in the list.")
    end
end

local function ListNames()
    local names = DB().names
    if #names == 0 then
            Print("List is empty. Right-click a target portrait or use /dtp add.")
        return
    end
    Print("Targets (first match wins):")
    for i, n in ipairs(names) do
        print(("  %d. %s"):format(i, n))
    end
end

-- Right-click menu on the target portrait (NPC targets use MENU_UNIT_TARGET).
local function SetupMenu()
    if not (Menu and Menu.ModifyMenu) then
        Print("Menu API not available - use /dtp add instead.")
        return
    end
    Menu.ModifyMenu("MENU_UNIT_TARGET", function(_, rootDescription, contextData)
        local unit = (contextData and contextData.unit) or "target"
        local name = SafeTargetName(unit)
        if not name then return end

        rootDescription:CreateDivider()
        rootDescription:CreateTitle("DynamicTargetPing")
        if IndexOf(DB().names, name) then
            rootDescription:CreateButton("Remove \"" .. name .. "\" from DynamicTargetPing", function()
                RemoveName(name)
            end)
        else
            rootDescription:CreateButton("Add \"" .. name .. "\" to DynamicTargetPing", function()
                AddName(name)
            end)
        end
    end)
end

ns.DB, ns.Print, ns.BuildBody, ns.SafeTargetName = DB, Print, BuildBody, SafeTargetName
ns.AddName, ns.RemoveAt, ns.Move, ns.Clear, ns.SetPriority = AddName, RemoveAt, Move, Clear, SetPriority
ns.GetStatus, ns.ScanQuestMobs = GetStatus, ScanQuestMobs
ns.MACRO_NAME, ns.MACRO_MAX_LENGTH = MACRO_NAME, MACRO_MAX_LENGTH

local HELP = {
    "/dtp - toggle the window",
    "/dtp list - print the list",
    "/dtp add [name] - add a name (default: current target)",
    "/dtp scan - add nearby enemies needed for kill/loot quest objectives",
    "/dtp remove <name|#> - remove by name or list number",
    "/dtp up <#> - move an entry up (higher priority)",
    "/dtp clear - empty the list",
    "/dtp priority on|off - first-match-wins via [noexists] (default on)",
    "/dtp test - print the generated macro and its length",
}

SLASH_DYNAMICTARGETPING1 = "/dtp"
SlashCmdList.DYNAMICTARGETPING = function(msg)
    msg = strtrim(msg or "")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        ApplyMacro(true)
        ns.ToggleWindow()
    elseif cmd == "list" then
        ListNames()
        ApplyMacro(true)
    elseif cmd == "add" then
        local name = arg ~= "" and arg or SafeTargetName("target")
        if not name then
                Print("No target. Use /dtp add <name> or target something first.")
            return
        end
        AddName(name)
    elseif cmd == "scan" then
        ScanQuestMobs()
    elseif cmd == "remove" or cmd == "rm" or cmd == "del" then
        local n = tonumber(arg)
        if n then
            if DB().names[n] then RemoveAt(n) else Print("No entry #" .. n .. ".") end
        elseif arg ~= "" then
            RemoveName(arg)
        else
                Print("Usage: /dtp remove <name|#>")
        end
    elseif cmd == "up" then
        local n = tonumber(arg)
        local names = DB().names
        if n and n > 1 and names[n] then
            Move(n, n - 1)
            ListNames()
        else
                Print("Usage: /dtp up <#> (2.." .. #names .. ")")
        end
    elseif cmd == "clear" then
        Clear()
    elseif cmd == "priority" then
        if arg == "on" or arg == "off" then
            SetPriority(arg == "on")
        else
                Print("Priority mode is " .. (DB().priority and "on" or "off") .. ". Usage: /dtp priority on|off")
        end
    elseif cmd == "test" then
        local body = BuildBody(DB().names)
        Print(("Macro body (%d/%d chars):"):format(#body, MACRO_MAX_LENGTH))
        for line in body:gmatch("[^\n]+") do print("  " .. line) end
        local index = GetMacroIndexByName(MACRO_NAME)
        if index == 0 then
            Print("Macro '" .. MACRO_NAME .. "' does not exist yet.")
        elseif GetMacroBody(index) ~= body then
            Print("Macro is out of date" .. (pendingRebuild and " (pending: in combat)." or "."))
        else
            Print("Macro is up to date.")
        end
        if C_Ping and C_Ping.IsPingSystemEnabled then
            Print("Ping system enabled: " .. tostring(C_Ping.IsPingSystemEnabled()))
        end
    else
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        DB()
        SetupMenu()
        ns.InitUI()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Macros aren't reliably available until after the first world load.
        C_Timer.After(1, function() ApplyMacro(true) end)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_REGEN_ENABLED" and pendingRebuild then
        ApplyMacro(true)
        if notifyOnRegen then Print("Macro updated.") end
        notifyOnRegen = false
    end
end)
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
