local ADDON_NAME = ...

local MACRO_NAME = "DynamicTargetPing"
local MACRO_ICON = "INV_Misc_QuestionMark"
local MACRO_MAX_LENGTH = 255
local MAX_CHAR_MACROS = MAX_CHARACTER_MACROS or 30
local PING_LINE = "/ping [@target,exists,nodead] attack"

local pendingRebuild = false

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

local function ApplyMacro(silent)
    if InCombatLockdown() then
        if not pendingRebuild and not silent then
            Print("In combat - macro will update when combat ends.")
        end
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
        Print("Created character macro '" .. MACRO_NAME .. "'. Open /macro and drag it to your action bar.")
    elseif GetMacroBody(index) ~= body then
        EditMacro(index, nil, nil, body)
    end
end

local function SafeTargetName(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return nil end
    local name = UnitName(unit)
    if name == nil or (issecretvalue and issecretvalue(name)) then return nil end
    return name
end

local function AddName(name)
    local names = DB().names
    if IndexOf(names, name) then
        Print("'" .. name .. "' is already in the list.")
        return
    end
    local candidate = { unpack(names) }
    candidate[#candidate + 1] = name
    local len = #BuildBody(candidate)
    if len > MACRO_MAX_LENGTH then
        Print(("Can't add '%s': macro would be %d/%d characters. Remove a name first."):format(name, len, MACRO_MAX_LENGTH))
        return
    end
    names[#names + 1] = name
    Print(("Added '%s' (%d/%d chars)."):format(name, len, MACRO_MAX_LENGTH))
    ApplyMacro()
end

local function RemoveAt(i)
    local names = DB().names
    local name = table.remove(names, i)
    if name then
        Print("Removed '" .. name .. "'.")
        ApplyMacro()
    end
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

local HELP = {
    "/dtp or /dtp list - show the list",
    "/dtp add [name] - add a name (default: current target)",
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

    if cmd == "" or cmd == "list" then
        ListNames()
        ApplyMacro(true)
    elseif cmd == "add" then
        local name = arg ~= "" and arg or SafeTargetName("target")
        if not name then
                Print("No target. Use /dtp add <name> or target something first.")
            return
        end
        AddName(name)
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
            names[n - 1], names[n] = names[n], names[n - 1]
            ApplyMacro()
            ListNames()
        else
                Print("Usage: /dtp up <#> (2.." .. #names .. ")")
        end
    elseif cmd == "clear" then
        wipe(DB().names)
        Print("List cleared.")
        ApplyMacro()
    elseif cmd == "priority" then
        if arg == "on" or arg == "off" then
            DB().priority = (arg == "on")
            local len = #BuildBody(DB().names)
            if len > MACRO_MAX_LENGTH then
                DB().priority = not DB().priority
                Print(("Can't switch: macro would be %d/%d characters. Remove a name first."):format(len, MACRO_MAX_LENGTH))
                return
            end
            Print("Priority mode " .. arg .. ".")
            ApplyMacro()
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
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Macros aren't reliably available until after the first world load.
        C_Timer.After(1, function() ApplyMacro(true) end)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_REGEN_ENABLED" and pendingRebuild then
        ApplyMacro()
        Print("Macro updated.")
    end
end)
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
