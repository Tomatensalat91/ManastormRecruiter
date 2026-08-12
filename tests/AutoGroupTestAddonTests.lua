local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function assertContains(value, expected, label)
    if not string.find(tostring(value), expected, 1, true) then
        error(string.format("%s: expected %q in %q", label, expected, tostring(value)))
    end
end

local clock = 100
GetTime = function() return clock end
date = function() return "12:34:56" end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { messages = {} }
DEFAULT_CHAT_FRAME.AddMessage = function(self, message) table.insert(self.messages, message) end
UnitName = function(unit) return unit == "player" and "Leader" or nil end
IsRaidLeader = function() return true end
IsRaidOfficer = function() return false end
InCombatLockdown = function() return false end

local frames = {}
CreateFrame = function()
    local frame = { scripts = {}, events = {} }
    frame.RegisterEvent = function(self, event) self.events[event] = true end
    frame.SetScript = function(self, script, callback) self.scripts[script] = callback end
    table.insert(frames, frame)
    return frame
end

local raid = {
    { name = "Leader", subgroup = 1 },
}
GetNumRaidMembers = function() return #raid end
GetRaidRosterInfo = function(index)
    local member = raid[index]
    if not member then return nil end
    return member.name, 0, member.subgroup
end

local moveCalls = {}
SetRaidSubgroup = function(index, target)
    table.insert(moveCalls, { index = index, target = target })
    raid[index].subgroup = target
end

ManastormRecruiter = {
    db = { settings = { slots = { tank = 2, heal = 3, dps = 10, aura = 3 } } },
    char = {
        session = {
            applicants = {
                alice = { key = "alice", name = "Alice", role = "HEAL", aura = true, status = "Invited" },
            },
        },
    },
    runtime = {
        roster = {
            { key = "leader", name = "Leader", role = "TANK", aura = true, subgroup = 1 },
        },
    },
}
function ManastormRecruiter:NormalizeName(name)
    local shortName = tostring(name or ""):match("^([^%-]+)") or ""
    return string.lower(shortName), shortName
end
function ManastormRecruiter:BuildRoster()
    return self.runtime.roster
end
function ManastormRecruiter:BuildGroupOptimizationPlan()
    -- Reproduce the production partial-plan result for a two-player raid. The
    -- test addon must override Alice's Group 1 result because both players have Aura.
    return { desired = { leader = 1, alice = 1 } }
end

dofile("test-addon/ManastormAutoGroupTest/ManastormAutoGroupTest.lua")

local Test = ManastormAutoGroupTest
Test.frame.scripts.OnEvent(nil, "ADDON_LOADED", "ManastormAutoGroupTest")
assertEqual(ManastormAutoGroupTestDB.enabled, true, "test addon defaults to enabled")
assertEqual(SlashCmdList.MANASTORMAUTOGROUPTEST ~= nil, true, "slash command registered")

Test:ScanPendingInvites()
assertEqual(Test.pending.alice.target, 2, "second Aura overrides partial planner and covers Group 2")
assertEqual(Test.pending.alice.state, "waiting", "invite waits for raid join")

table.insert(raid, { name = "Alice", subgroup = 1 })
Test:ProcessPending()
assertEqual(#moveCalls, 1, "join triggers one automatic subgroup API call")
assertEqual(moveCalls[1].index, 2, "new raid index is passed to subgroup API")
assertEqual(moveCalls[1].target, 2, "planned group is passed to subgroup API")
assertEqual(Test.pending.alice.state, "move-sent", "move waits for roster verification")

clock = clock + 1
Test:ProcessPending()
assertEqual(Test.pending.alice.state, "confirmed", "updated roster confirms automatic move")
assertEqual(#moveCalls, 1, "confirmed move is not repeated")

local combinedLog = table.concat(ManastormAutoGroupTestDB.logs, "\n")
assertContains(combinedLog, "Planned Alice for Group 2", "plan is logged")
assertContains(combinedLog, "Automatic API call sent", "API attempt is logged")
assertContains(combinedLog, "CONFIRMED: Alice is in Group 2", "roster confirmation is logged")

print("AutoGroup test addon: 1 simulated invite/join/move flow passed.")
