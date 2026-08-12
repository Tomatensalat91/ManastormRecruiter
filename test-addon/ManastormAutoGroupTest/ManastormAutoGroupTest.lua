local Test = {}
ManastormAutoGroupTest = Test

local PREFIX = "|cff66ccff[MS AutoGroup Test]|r "
local VERSION = "0.1.1"
local UPDATE_INTERVAL = 0.20
local MOVE_CONFIRM_DELAY = 0.75
local MAX_LOG_ENTRIES = 100

Test.pending = {}
Test.knownRaid = {}
Test.scanElapsed = 0
Test.nextProcessAt = nil
Test.initialized = false

local function Now()
    if type(GetTime) == "function" then return GetTime() end
    return 0
end

local function NormalizeName(name)
    if ManastormRecruiter and type(ManastormRecruiter.NormalizeName) == "function" then
        return ManastormRecruiter:NormalizeName(name)
    end
    local shortName = tostring(name or ""):match("^([^%-]+)") or tostring(name or "")
    return string.lower(shortName), shortName
end

local function IsRaidManager()
    if type(IsRaidLeader) == "function" and IsRaidLeader() then return true end
    if type(IsRaidOfficer) == "function" and IsRaidOfficer() then return true end
    return false
end

function Test:Print(message)
    local text = PREFIX .. tostring(message)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    elseif type(print) == "function" then
        print(text)
    end
end

function Test:Log(message, quiet)
    local stamp = type(date) == "function" and date("%H:%M:%S") or "--:--:--"
    local entry = stamp .. " " .. tostring(message)
    local logs = ManastormAutoGroupTestDB and ManastormAutoGroupTestDB.logs
    if type(logs) == "table" then
        table.insert(logs, entry)
        while #logs > MAX_LOG_ENTRIES do table.remove(logs, 1) end
    end
    if not quiet then self:Print(message) end
end

function Test:Schedule(delay)
    local due = Now() + (tonumber(delay) or 0)
    if not self.nextProcessAt or due < self.nextProcessAt then self.nextProcessAt = due end
end

function Test:GetRaidMembers()
    local members = {}
    local count = type(GetNumRaidMembers) == "function" and GetNumRaidMembers() or 0
    for index = 1, count do
        local name, _, subgroup = GetRaidRosterInfo(index)
        if name then
            local key, shortName = NormalizeName(name)
            members[key] = {
                key = key,
                name = shortName,
                raidIndex = index,
                subgroup = tonumber(subgroup) or 1,
            }
        end
    end
    return members
end

function Test:GetGroupSize(group, members)
    local count = 0
    for _, member in pairs(members or self:GetRaidMembers()) do
        if member.subgroup == group then count = count + 1 end
    end
    return count
end

function Test:GetAuraTarget(applicant, roster)
    if not applicant or applicant.aura ~= true then return nil end
    local msr = ManastormRecruiter
    local slots = msr and msr.db and msr.db.settings and msr.db.settings.slots
    local requiredGroups = math.min(3, tonumber(slots and slots.aura) or 0)
    if requiredGroups < 1 then return nil end

    local applicantKey = NormalizeName(applicant.name)
    local auraCounts = {}
    local groupSizes = {}
    for group = 1, requiredGroups do
        auraCounts[group] = 0
        groupSizes[group] = 0
    end
    for _, member in ipairs(roster or {}) do
        local group = tonumber(member.subgroup) or 1
        if group >= 1 and group <= requiredGroups and member.key ~= applicantKey then
            groupSizes[group] = groupSizes[group] + 1
            if member.aura == true then auraCounts[group] = auraCounts[group] + 1 end
        end
    end

    for group = 1, requiredGroups do
        if auraCounts[group] == 0 and groupSizes[group] < 5 then return group end
    end
    return nil
end

function Test:BuildTargetForApplicant(applicant)
    local msr = ManastormRecruiter
    if not msr or type(msr.BuildGroupOptimizationPlan) ~= "function" then
        return nil, "Manastorm Recruiter group planning is unavailable."
    end

    local roster
    if type(msr.BuildRoster) == "function" then roster = msr:BuildRoster() end
    roster = roster or (msr.runtime and msr.runtime.roster) or {}

    local key, shortName = NormalizeName(applicant and applicant.name)
    local planningRoster = {}
    local alreadyPresent = false
    for _, member in ipairs(roster) do
        local copy = {}
        for field, value in pairs(member) do copy[field] = value end
        table.insert(planningRoster, copy)
        if member.key == key then alreadyPresent = true end
    end
    if not alreadyPresent then
        table.insert(planningRoster, {
            key = key,
            name = shortName,
            role = applicant.role or "UNKNOWN",
            aura = applicant.aura,
            subgroup = 1,
        })
    end

    -- Aura coverage is the first placement rule. The production partial-raid
    -- planner normally activates only ceil(playerCount / 5) groups; that would
    -- keep two Aura players together in Group 1. For this test, an invited Aura
    -- player must instead cover the first still-uncovered configured group.
    local auraTarget = self:GetAuraTarget(applicant, planningRoster)
    if auraTarget then return auraTarget, nil end

    local plan, reason = msr:BuildGroupOptimizationPlan(planningRoster)
    if not plan then return nil, reason or "No group plan could be built." end
    return plan.desired and plan.desired[key], nil
end

function Test:ScanAuraCollisions()
    local msr = ManastormRecruiter
    if not msr or type(msr.BuildRoster) ~= "function" then return end
    local roster = msr:BuildRoster() or {}
    local playerKey = NormalizeName(type(UnitName) == "function" and UnitName("player") or "")
    local auraByGroup = {}
    for group = 1, 3 do auraByGroup[group] = {} end
    for _, member in ipairs(roster) do
        local group = tonumber(member.subgroup) or 1
        if group >= 1 and group <= 3 and member.aura == true then
            table.insert(auraByGroup[group], member)
        end
    end

    for group = 1, 3 do
        if #auraByGroup[group] > 1 then
            for _, member in ipairs(auraByGroup[group]) do
                if member.key ~= playerKey and not self.pending[member.key] then
                    local applicant = msr.char and msr.char.session and msr.char.session.applicants
                        and msr.char.session.applicants[member.key]
                    applicant = applicant or member
                    local target = self:GetAuraTarget(applicant, roster)
                    if target and target ~= group then
                        self.pending[member.key] = {
                            key = member.key,
                            name = member.name,
                            target = target,
                            source = "existing Aura collision",
                            state = "waiting",
                            attempts = 0,
                            nextAttemptAt = 0,
                        }
                        self:Log(string.format("Aura collision detected: %s will move from Group %d to uncovered Group %d.", member.name, group, target))
                        self:Schedule(0)
                        return
                    end
                end
            end
        end
    end
end

function Test:QueueApplicant(applicant, source)
    if not applicant or not applicant.name then return false end
    local key, shortName = NormalizeName(applicant.name)
    if key == "" then return false end

    local existing = self.pending[key]
    if existing and existing.state ~= "failed" then return true end

    local target, reason = self:BuildTargetForApplicant(applicant)
    if not target then
        self:Log("Could not plan " .. shortName .. ": " .. tostring(reason))
        return false
    end

    self.pending[key] = {
        key = key,
        name = shortName,
        target = target,
        source = source or "invite",
        state = "waiting",
        attempts = 0,
        nextAttemptAt = 0,
    }
    self:Log(string.format("Planned %s for Group %d (%s). Waiting for the player to join.", shortName, target, source or "invite"))
    self:Schedule(0)
    return true
end

function Test:QueueExplicit(name, target)
    local key, shortName = NormalizeName(name)
    target = tonumber(target)
    if key == "" or not target or target < 1 or target > 8 then return false end
    self.pending[key] = {
        key = key,
        name = shortName,
        target = target,
        source = "manual test plan",
        state = "waiting",
        attempts = 0,
        nextAttemptAt = 0,
    }
    self:Log(string.format("Explicit test plan: %s -> Group %d. No post-invite click will be needed.", shortName, target))
    self:Schedule(0)
    return true
end

function Test:ScanPendingInvites()
    if not ManastormAutoGroupTestDB.enabled then return end
    if ManastormRecruiter and ManastormRecruiter.AUTOMATIC_GROUP_ASSIGNMENT_VERSION then return end
    local session = ManastormRecruiter and ManastormRecruiter.char and ManastormRecruiter.char.session
    local applicants = session and session.applicants
    if type(applicants) ~= "table" then return end
    for key, applicant in pairs(applicants) do
        if applicant.status == "Invited" and not self.pending[key] then
            self:QueueApplicant(applicant, "Manastorm Recruiter invite")
        end
    end
    self:ScanAuraCollisions()
end

function Test:DetectUnplannedJoins(members)
    if not ManastormAutoGroupTestDB.enabled then return end
    local playerKey = NormalizeName(type(UnitName) == "function" and UnitName("player") or "")
    for key, member in pairs(members) do
        if key ~= playerKey and not self.knownRaid[key] and not self.pending[key] then
            local applicants = ManastormRecruiter and ManastormRecruiter.char
                and ManastormRecruiter.char.session and ManastormRecruiter.char.session.applicants
            local applicant = applicants and applicants[key]
            if applicant then
                self:QueueApplicant(applicant, "new raid member fallback")
            else
                self:Log("Detected new raid member " .. member.name .. ", but no Manastorm applicant data exists; no target was guessed.")
            end
        end
    end
end

function Test:ProcessPending()
    self.nextProcessAt = nil
    if not ManastormAutoGroupTestDB.enabled then return end

    local members = self:GetRaidMembers()
    self:DetectUnplannedJoins(members)
    local now = Now()
    local needsAnotherCheck = false

    for key, pending in pairs(self.pending) do
        if pending.state ~= "confirmed" and pending.state ~= "failed" then
            local member = members[key]
            if not member then
                needsAnotherCheck = true
            elseif member.subgroup == pending.target then
                pending.state = "confirmed"
                self:Log(string.format("CONFIRMED: %s is in Group %d without an extra button click.", pending.name, pending.target))
            elseif now < (pending.nextAttemptAt or 0) then
                needsAnotherCheck = true
            elseif type(InCombatLockdown) == "function" and InCombatLockdown() then
                pending.state = "waiting-combat"
                pending.nextAttemptAt = now + 1
                needsAnotherCheck = true
            elseif not IsRaidManager() then
                pending.state = "waiting-permission"
                pending.nextAttemptAt = now + 1
                needsAnotherCheck = true
                if not pending.permissionLogged then
                    pending.permissionLogged = true
                    self:Log("Waiting to move " .. pending.name .. ": you must be raid leader or assistant.")
                end
            elseif type(SetRaidSubgroup) ~= "function" then
                pending.state = "failed"
                self:Log("FAILED: SetRaidSubgroup is unavailable in this client.")
            elseif self:GetGroupSize(pending.target, members) >= 5 then
                pending.state = "waiting-space"
                pending.nextAttemptAt = now + 1
                needsAnotherCheck = true
                if not pending.spaceLogged then
                    pending.spaceLogged = true
                    self:Log(string.format("Waiting to move %s: Group %d is full.", pending.name, pending.target))
                end
            elseif pending.attempts >= (tonumber(ManastormAutoGroupTestDB.maxAttempts) or 3) then
                pending.state = "failed"
                self:Log(string.format("FAILED: %s did not reach Group %d after %d automatic attempt(s).", pending.name, pending.target, pending.attempts))
            else
                pending.attempts = pending.attempts + 1
                pending.state = "move-sent"
                local ok, result = pcall(SetRaidSubgroup, member.raidIndex, pending.target)
                if not ok or result == false then
                    pending.state = "failed"
                    self:Log(string.format("FAILED: Ascension rejected automatic move %s -> Group %d (%s).", pending.name, pending.target, tostring(result)))
                else
                    pending.nextAttemptAt = now + MOVE_CONFIRM_DELAY
                    needsAnotherCheck = true
                    self:Log(string.format("Automatic API call sent: %s, Group %d -> Group %d (attempt %d).", pending.name, member.subgroup, pending.target, pending.attempts))
                end
            end
        end
    end

    self.knownRaid = members
    if needsAnotherCheck then self:Schedule(MOVE_CONFIRM_DELAY) end
end

function Test:PrintStatus()
    local enabled = ManastormAutoGroupTestDB.enabled and "ON" or "OFF"
    local api = type(SetRaidSubgroup) == "function" and "available" or "missing"
    local raidCount = type(GetNumRaidMembers) == "function" and GetNumRaidMembers() or 0
    self:Print(string.format("Status: %s, SetRaidSubgroup %s, raid members %d, raid manager %s.", enabled, api, raidCount, IsRaidManager() and "yes" or "no"))
    local count = 0
    for _, pending in pairs(self.pending) do
        count = count + 1
        self:Print(string.format("%s -> Group %d: %s, attempts %d", pending.name, pending.target, pending.state, pending.attempts))
    end
    if count == 0 then self:Print("No planned or completed player moves in this session.") end
end

function Test:PrintLog()
    local logs = ManastormAutoGroupTestDB.logs or {}
    if #logs == 0 then self:Print("The test log is empty.") return end
    self:Print("Last test log entries:")
    for index = math.max(1, #logs - 14), #logs do self:Print(logs[index]) end
end

function Test:HandleSlash(message)
    local command, rest = tostring(message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if command == "on" then
        ManastormAutoGroupTestDB.enabled = true
        self:Log("Automatic test enabled.")
        self:Schedule(0)
    elseif command == "off" then
        ManastormAutoGroupTestDB.enabled = false
        self:Log("Automatic test disabled.")
    elseif command == "status" or command == "" then
        self:PrintStatus()
    elseif command == "log" then
        self:PrintLog()
    elseif command == "clear" then
        self.pending = {}
        ManastormAutoGroupTestDB.logs = {}
        self:Print("Plans and test log cleared.")
    elseif command == "retry" then
        for _, pending in pairs(self.pending) do
            if pending.state == "failed" then
                pending.state = "waiting"
                pending.attempts = 0
                pending.nextAttemptAt = 0
            end
        end
        self:Log("Failed moves reset for another automatic test.")
        self:Schedule(0)
    elseif command == "plan" then
        local name, group = rest:match("^(%S+)%s+(%d+)$")
        if not self:QueueExplicit(name, group) then self:Print("Usage: /magt plan <player> <group 1-8>") end
    else
        self:Print("Commands: /magt status, on, off, plan <player> <group>, retry, log, clear")
    end
end

function Test:Initialize()
    if self.initialized then return end
    self.initialized = true
    ManastormAutoGroupTestDB = ManastormAutoGroupTestDB or {}
    if ManastormAutoGroupTestDB.enabled == nil then ManastormAutoGroupTestDB.enabled = true end
    ManastormAutoGroupTestDB.maxAttempts = tonumber(ManastormAutoGroupTestDB.maxAttempts) or 3
    ManastormAutoGroupTestDB.logs = ManastormAutoGroupTestDB.logs or {}
    if ManastormRecruiter and ManastormRecruiter.AUTOMATIC_GROUP_ASSIGNMENT_VERSION then
        ManastormAutoGroupTestDB.enabled = false
    end
    self.knownRaid = self:GetRaidMembers()

    SLASH_MANASTORMAUTOGROUPTEST1 = "/magt"
    SlashCmdList.MANASTORMAUTOGROUPTEST = function(message) Test:HandleSlash(message) end
    if ManastormAutoGroupTestDB.enabled then
        self:Log("Loaded v" .. VERSION .. " and enabled. Invite normally through Manastorm Recruiter; no post-invite button is required.")
    else
        self:Log("Disabled because Manastorm Recruiter now contains the verified automatic group assignment.")
    end
end

local frame = CreateFrame("Frame", "ManastormAutoGroupTestEventFrame")
Test.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= "ManastormAutoGroupTest" then return end
        Test:Initialize()
        frame:RegisterEvent("PLAYER_LOGIN")
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
        frame:RegisterEvent("RAID_ROSTER_UPDATE")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Test.knownRaid = Test:GetRaidMembers()
        Test:Schedule(0.25)
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
        Test:Schedule(0.15)
    end
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    if not Test.initialized then return end
    Test.scanElapsed = Test.scanElapsed + elapsed
    if Test.scanElapsed >= UPDATE_INTERVAL then
        Test.scanElapsed = 0
        Test:ScanPendingInvites()
    end
    if Test.nextProcessAt and Now() >= Test.nextProcessAt then Test:ProcessPending() end
end)
