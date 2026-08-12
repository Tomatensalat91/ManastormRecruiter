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

CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
    }
end
local monotonicNow = 100
GetTime = function() return monotonicNow end
local epochNow = 1000
time = function() return epochNow end
date = function() return "12:34" end
UnitName = function(unit) return unit == "player" and "Leader" or nil end
local playerLevel = 60
UnitLevel = function() return playerLevel end
GetNumRaidMembers = function() return 0 end
GetNumPartyMembers = function() return 0 end
LeaveParty = function() return true end
SlashCmdList = {}

dofile("Core.lua")
dofile("Parser.lua")
dofile("Roster.lua")
dofile("Recruitment.lua")
dofile("Manastorm.lua")
dofile("Rebuild.lua")

local MSR = ManastormRecruiter
assertEqual(MSR.VERSION, "0.6.20", "runtime version matches addon release")
MSR.db = {
    settings = {
        channel = "8",
        autoPost = true,
        autoPostInterval = 90,
        autoReply = true,
        inviteReminderDelay = 5,
        inviteTimeout = 10,
        slots = { tank = 2, heal = 3, dps = 10, aura = 3 },
        auraReservation = {
            enabled = true,
            roles = { tank = false, heal = false, dps = true },
        },
        messages = {},
    },
}
MSR.char = { session = { applicants = {} } }
MSR.runtime = { roster = {}, rosterByKey = {}, groupChat = {} }

local counts = { tank = 0, heal = 0, dps = 8, aura = 1, unknown = 0, total = 9 }
local active, missing, free = MSR:GetAuraReservationState(counts)
assertEqual(active, true, "default DPS reservation active")
assertEqual(missing, 2, "missing Auras")
assertEqual(free, 2, "free selected slots")

local issue = MSR:GetApplicantCapacityIssue({ role = "DPS", aura = false }, counts)
assertEqual(issue, "AURA_REQUIRED", "DPS without Aura is reserved")
issue = MSR:GetApplicantCapacityIssue({ role = "TANK", aura = false }, counts)
assertEqual(issue, nil, "unselected Tank role is not reserved")

MSR.db.settings.auraReservation.roles = { tank = true, heal = false, dps = false }
counts = { tank = 1, heal = 3, dps = 10, aura = 2, unknown = 0, total = 14 }
issue = MSR:GetApplicantCapacityIssue({ role = "TANK", aura = false }, counts)
assertEqual(issue, "AURA_REQUIRED", "Tank reservation can be selected")

MSR.db.settings.auraReservation.enabled = false
issue = MSR:GetApplicantCapacityIssue({ role = "TANK", aura = false }, counts)
assertEqual(issue, nil, "reservation can be disabled")

MSR.db.settings.auraReservation.enabled = true
MSR.db.settings.auraReservation.roles = { tank = false, heal = false, dps = true }
counts = { tank = 0, heal = 0, dps = 8, aura = 1, unknown = 0, total = 9 }
MSR.GetCommittedCounts = function() return counts end
local recruitment = MSR:BuildRecruitmentMessage()
assertContains(recruitment, "LFM MS - 0/2 Tanks - 0/3 Healer - 8/10 DPS - Aura 1/3 - 9/15 Total", "full recruitment counters")
assertContains(recruitment, "Need: 2 Tanks - 3 Healers - 2 DPS - 2 Auras", "missing-slot recruitment")
assertContains(recruitment, "Aura required for remaining DPS slots", "reservation suffix")

local originalGetChannelName = GetChannelName
local originalSendChatMessage = SendChatMessage
local recruitmentPosts = 0
GetChannelName = function() return 8 end
SendChatMessage = function(_, channel)
    if channel == "CHANNEL" then recruitmentPosts = recruitmentPosts + 1 end
    return true
end
MSR.char.session.listening = false
MSR.db.settings.autoPost = false
assertEqual(MSR:ToggleRecruitment(), true, "recruitment toggle starts")
assertEqual(MSR.char.session.listening, true, "start enables applicant listening")
assertEqual(MSR.db.settings.autoPost, false, "listener start preserves disabled Auto-Post setting")
assertEqual(recruitmentPosts, 0, "start does not send a recruitment post")
assertEqual(MSR:ToggleRecruitment(), true, "recruitment toggle stops")
assertEqual(MSR.char.session.listening, false, "stop pauses applicant listening and scanner")
assertEqual(MSR.db.settings.autoPost, false, "listener stop preserves disabled Auto-Post setting")
assertEqual(recruitmentPosts, 0, "stop does not send a recruitment post")
assertEqual(MSR:PostRecruitment(false), true, "manual recruitment message can be posted while listener is off")
assertEqual(recruitmentPosts, 1, "manual recruitment button sends exactly one message")
assertEqual(MSR.char.session.listening, false, "manual recruitment post does not enable listener")
MSR.db.settings.autoPost = true
assertEqual(MSR:ToggleRecruitment(), true, "listener starts with Auto-Post setting enabled")
assertEqual(MSR.db.settings.autoPost, true, "listener start preserves enabled Auto-Post setting")
assertEqual(MSR.char.session.lastPostAt, epochNow, "enabled Auto-Post begins a fresh interval")
assertEqual(MSR:ToggleRecruitment(), true, "listener stops with Auto-Post setting enabled")
assertEqual(MSR.db.settings.autoPost, true, "listener stop preserves enabled Auto-Post setting")
MSR.db.settings.autoPost = false
GetChannelName = originalGetChannelName
SendChatMessage = originalSendChatMessage

local oneMissing = MSR:BuildMessageValues({ tank = 2, heal = 2, dps = 10, aura = 3, total = 14 })
assertEqual(oneMissing.needed, "1 Healer", "Need omits fulfilled values")

MSR.db.settings.messages.recruitment = "LFM MS Tank {tank}/{tankMax} Heal {heal}/{healMax} DPS {dps}/{dpsMax} Aura {aura}/{auraMax}. PM me"
assertEqual(MSR:MigrateRecruitmentTemplate(), true, "legacy recruitment template migration")
assertEqual(MSR.db.settings.messages.recruitment, "LFM MS {needed}. PM me", "migrated recruitment template")
MSR.db.settings.messages.recruitment = nil

MSR.db.settings.messages.level60StatusPost = "I am level 60. Tank {tank}/{tankMax}, Heal {heal}/{healMax}, Aura {aura}/{auraMax}. Aura players: {auraPlayers}."
assertEqual(MSR:MigrateLevel60StatusTemplate(), true, "legacy Level 60 status template migration")
assertContains(MSR.db.settings.messages.level60StatusPost, "Thanks, everyone!", "friendly migrated Level 60 status")
MSR.db.settings.messages.level60StatusPost = nil

MSR.db.settings.messages.acceptedApplicationReply = "Welcome {player}: {role}/{aura}"
local configured = MSR:BuildConfiguredMessage("acceptedApplicationReply", {
    player = "Alice",
    role = "Heal",
    aura = "Yes",
})
assertEqual(configured, "Welcome Alice: Heal/Yes", "custom message placeholders")

local roster = {
    { key = "leader", name = "Leader", unit = "player", raidIndex = 1, role = "TANK", aura = true },
    { key = "alice", name = "Alice", unit = "raid2", raidIndex = 2, role = "HEAL", aura = true },
    { key = "bob", name = "Bob", unit = "raid3", raidIndex = 3, role = "DPS", aura = false },
}

local partialRoster = {
    { key = "healer", name = "Healer", unit = "raid1", raidIndex = 1, subgroup = 1, role = "HEAL", aura = true },
    { key = "tank", name = "MainTank", unit = "raid2", raidIndex = 2, subgroup = 2, role = "TANK", aura = false },
    { key = "damage", name = "Damage", unit = "raid3", raidIndex = 3, subgroup = 1, role = "DPS", aura = true },
}
local partialGroups = MSR:BuildPartialDesiredGroups(partialRoster)
assertEqual(partialGroups[1][1].key, "tank", "primary Tank is first in desired Group 1")
local partialPlan = MSR:BuildGroupOptimizationPlan(partialRoster)
assertEqual(partialPlan.primaryTankKey, "tank", "group optimization stores primary Tank")

local twoAuraRoster = {
    { key = "leader", name = "Leader", unit = "raid1", raidIndex = 1, subgroup = 1, role = "DPS", aura = true },
    { key = "kard", name = "Kard", unit = "raid2", raidIndex = 2, subgroup = 1, role = "DPS", aura = true },
}
local auraTarget = MSR:GetAutomaticGroupTarget("kard", twoAuraRoster)
assertEqual(auraTarget, 2, "second Aura is assigned to uncovered Group 2 in a partial raid")
local selfAuraTarget = MSR:GetAutomaticGroupTarget("leader", twoAuraRoster)
assertEqual(selfAuraTarget, 2, "own Aura change can move the raid leader to uncovered Group 2")

local originalBuildRoster = MSR.BuildRoster
local originalGetNumRaidMembers = GetNumRaidMembers
local originalIsRaidLeader = IsRaidLeader
local originalSetRaidSubgroup = SetRaidSubgroup
local automaticMoveCalls = 0
MSR.BuildRoster = function() return twoAuraRoster end
GetNumRaidMembers = function() return #twoAuraRoster end
IsRaidLeader = function() return true end
SetRaidSubgroup = function(index, target)
    automaticMoveCalls = automaticMoveCalls + 1
    twoAuraRoster[index].subgroup = target
    return true
end
MSR.runtime.automaticGroupAssignment = nil
assertEqual(MSR:QueueAutomaticGroupAssignment("kard", "Aura changed"), true, "Aura update queues automatic group assignment")
assertEqual(automaticMoveCalls, 1, "Aura update sends subgroup API without another button")
assertEqual(MSR.runtime.automaticGroupAssignment.target, 2, "automatic move stores Group 2 target until confirmation")
monotonicNow = monotonicNow + 1
assertEqual(MSR:UpdateAutomaticGroupAssignment(twoAuraRoster), true, "updated roster confirms automatic assignment")
assertEqual(MSR.runtime.automaticGroupAssignment, nil, "confirmed automatic assignment is cleared")
MSR.BuildRoster = originalBuildRoster
GetNumRaidMembers = originalGetNumRaidMembers
IsRaidLeader = originalIsRaidLeader
SetRaidSubgroup = originalSetRaidSubgroup

local fullTargetRoster = {
    { key = "mover", name = "AuraMover", unit = "raid1", raidIndex = 1, subgroup = 1, role = "HEAL", aura = true },
    { key = "aura1", name = "AuraOne", unit = "raid2", raidIndex = 2, subgroup = 1, role = "DPS", aura = true },
    { key = "target1", name = "TargetOne", unit = "raid3", raidIndex = 3, subgroup = 2, role = "HEAL", aura = false },
    { key = "target2", name = "TargetTwo", unit = "raid4", raidIndex = 4, subgroup = 2, role = "DPS", aura = false },
    { key = "target3", name = "TargetThree", unit = "raid5", raidIndex = 5, subgroup = 2, role = "DPS", aura = false },
    { key = "target4", name = "TargetFour", unit = "raid6", raidIndex = 6, subgroup = 2, role = "DPS", aura = false },
    { key = "target5", name = "TargetFive", unit = "raid7", raidIndex = 7, subgroup = 2, role = "DPS", aura = false },
}
local originalSwapRaidSubgroup = SwapRaidSubgroup
local swapCalls = 0
MSR.BuildRoster = function() return fullTargetRoster end
GetNumRaidMembers = function() return #fullTargetRoster end
IsRaidLeader = function() return true end
SwapRaidSubgroup = function(first, second)
    swapCalls = swapCalls + 1
    local group = fullTargetRoster[first].subgroup
    fullTargetRoster[first].subgroup = fullTargetRoster[second].subgroup
    fullTargetRoster[second].subgroup = group
    return true
end
MSR.runtime.automaticGroupAssignment = nil
assertEqual(MSR:GetAutomaticGroupTarget("mover", fullTargetRoster), 2,
    "Aura mover targets uncovered full Group 2")
assertEqual(MSR:QueueAutomaticGroupAssignment("mover", "Aura changed"), true,
    "full target group uses automatic swap path")
assertEqual(swapCalls, 1, "SwapRaidSubgroup is called once for a full target group")
local swappedOut = 0
for index = 3, 7 do
    if fullTargetRoster[index].subgroup == 1 then swappedOut = swappedOut + 1 end
end
assertEqual(swappedOut, 1, "one full-target member is exchanged into the source group")
assertEqual(fullTargetRoster[1].subgroup, 2, "Aura mover enters the previously full target group")
monotonicNow = monotonicNow + 1
assertEqual(MSR:UpdateAutomaticGroupAssignment(fullTargetRoster), true,
    "full-group swap is confirmed from roster")
MSR.BuildRoster = originalBuildRoster
GetNumRaidMembers = originalGetNumRaidMembers
IsRaidLeader = originalIsRaidLeader
SwapRaidSubgroup = originalSwapRaidSubgroup

local inviteRoster = {
    { key = "leader", name = "Leader", unit = "raid1", raidIndex = 1, subgroup = 1, role = "DPS", aura = true },
}
local inviteRaidConverted = false
local invitee = { key = "invitee", name = "Invitee", role = "HEAL", aura = true, status = "Invited" }
MSR.char.session.applicants.invitee = invitee
MSR.BuildRoster = function() return inviteRoster end
GetNumRaidMembers = function() return inviteRaidConverted and #inviteRoster or 0 end
IsRaidLeader = function() return true end
automaticMoveCalls = 0
SetRaidSubgroup = function(index, target)
    automaticMoveCalls = automaticMoveCalls + 1
    inviteRoster[index].subgroup = target
    return true
end
MSR.runtime.automaticGroupAssignment = nil
MSR.runtime.pendingInviteGroupAssignments = {}
assertEqual(MSR:PlanAutomaticInviteGroupAssignment(invitee), true, "successful invite arms automatic assignment")
assertEqual(MSR.runtime.pendingInviteGroupAssignments.invitee ~= nil, true, "invite waits in assignment queue")
assertEqual(MSR:UpdateAutomaticGroupAssignment(inviteRoster), false, "pending invite does not move before joining")
assertEqual(automaticMoveCalls, 0, "no subgroup API call is sent before invite acceptance")
table.insert(inviteRoster, {
    key = "invitee", name = "Invitee", unit = "raid2", raidIndex = 2,
    subgroup = 1, role = "HEAL", aura = true,
})
invitee.status = "Joined"
assertEqual(MSR:UpdateAutomaticGroupAssignment(inviteRoster), false, "accepted invite waits during intermediate party state")
assertEqual(MSR.runtime.pendingInviteGroupAssignments.invitee ~= nil, true, "party state retains invite assignment plan")
assertEqual(automaticMoveCalls, 0, "party state cannot consume subgroup API call")
inviteRoster = { inviteRoster[1] }
invitee.status = "NoResponse"
assertEqual(MSR:UpdateAutomaticGroupAssignment(inviteRoster), false, "NoResponse timeout does not discard assignment plan")
assertEqual(MSR.runtime.pendingInviteGroupAssignments.invitee ~= nil, true, "late invite acceptance remains armed")
table.insert(inviteRoster, {
    key = "invitee", name = "Invitee", unit = "raid2", raidIndex = 2,
    subgroup = 1, role = "HEAL", aura = true,
})
invitee.status = "Joined"
inviteRaidConverted = true
assertEqual(MSR:UpdateAutomaticGroupAssignment(inviteRoster), true, "joined invite activates automatic assignment")
assertEqual(automaticMoveCalls, 1, "invite acceptance sends subgroup API without another button")
assertEqual(MSR.runtime.automaticGroupAssignment.target, 2, "joined second Aura targets Group 2")
monotonicNow = monotonicNow + 1
assertEqual(MSR:UpdateAutomaticGroupAssignment(inviteRoster), true, "invite move is confirmed from updated roster")
assertEqual(MSR.runtime.automaticGroupAssignment, nil, "confirmed invite assignment is cleared")
MSR.BuildRoster = originalBuildRoster
GetNumRaidMembers = originalGetNumRaidMembers
IsRaidLeader = originalIsRaidLeader
SetRaidSubgroup = originalSetRaidSubgroup
MSR.char.session.applicants.invitee = nil

local queuedAssignment
local originalQueueAutomaticGroupAssignment = MSR.QueueAutomaticGroupAssignment
MSR.QueueAutomaticGroupAssignment = function(_, key, reason)
    queuedAssignment = { key = key, reason = reason }
    return true
end
local editedApplicant = { key = "manual", name = "Manual", role = "DPS", aura = false }
MSR:SetApplicantRole(editedApplicant, "HEAL")
assertEqual(queuedAssignment.key, "manual", "role edit queues joined-player group assignment")
assertEqual(queuedAssignment.reason, "role changed", "role edit records assignment reason")
MSR:ToggleApplicantAura(editedApplicant)
assertEqual(queuedAssignment.reason, "Aura changed", "Aura edit queues joined-player group assignment")
MSR:QueueSelfAutomaticGroupAssignment("own Aura changed")
assertEqual(queuedAssignment.key, "leader", "own assignment queues the player raid member")
assertEqual(queuedAssignment.reason, "own Aura changed", "own assignment keeps its update reason")
MSR.QueueAutomaticGroupAssignment = originalQueueAutomaticGroupAssignment

MSR.runtime.automaticGroupAssignment = { key = "old" }
MSR.runtime.pendingInviteGroupAssignments = { old = { key = "old" } }
assertEqual(MSR:SetAutomaticGroupAssignmentEnabled(false), true, "automatic assignment setting can be disabled")
assertEqual(MSR:IsAutomaticGroupAssignmentEnabled(), false, "automatic assignment reports disabled")
assertEqual(MSR.runtime.automaticGroupAssignment, nil, "disabling clears an active automatic move")
assertEqual(next(MSR.runtime.pendingInviteGroupAssignments), nil, "disabling clears waiting invite moves")
assertEqual(MSR:PlanAutomaticInviteGroupAssignment(editedApplicant), false, "disabled setting blocks invite planning")
assertEqual(MSR:SetAutomaticGroupAssignmentEnabled(true), true, "automatic assignment setting can be enabled")
assertEqual(MSR:IsAutomaticGroupAssignmentEnabled(), true, "automatic assignment reports enabled")

local markedUnit, markedIcon, tankMarkerCalls
SetRaidTarget = function(unit, icon)
    markedUnit, markedIcon = unit, icon
    tankMarkerCalls = tankMarkerCalls or {}
    table.insert(tankMarkerCalls, { unit = unit, icon = icon })
    return true
end
partialRoster[2].subgroup = 1
assertEqual(MSR:MarkPrimaryTank(partialRoster, "tank"), true, "primary Tank star marker")
assertEqual(markedUnit, "raid2", "primary Tank marker unit")
assertEqual(markedIcon, 1, "primary Tank receives raid star")

local mainTankAssignments = {}
SetPartyAssignment = function(assignment, unit, name, exactMatch)
    table.insert(mainTankAssignments, {
        assignment = assignment,
        unit = unit,
        name = name,
        exactMatch = exactMatch,
    })
    return true
end
local tankRoster = {
    { key = "tank1", name = "MainTank", unit = "raid1", raidIndex = 1, subgroup = 1, role = "TANK" },
    { key = "tank2", name = "OffTank", unit = "raid6", raidIndex = 6, subgroup = 2, role = "TANK" },
    { key = "damage", name = "Damage", unit = "raid2", raidIndex = 2, subgroup = 1, role = "DPS" },
}
tankMarkerCalls = {}
assertEqual(MSR:MarkTanks(tankRoster), true, "Tank markers are assigned from final group order")
assertEqual(#tankMarkerCalls, 2, "first two Tanks receive raid markers")
assertEqual(tankMarkerCalls[1].unit, "raid1", "first Tank is selected by group and raid order")
assertEqual(tankMarkerCalls[1].icon, 1, "first Tank receives the star")
assertEqual(tankMarkerCalls[2].unit, "raid6", "second Tank follows the first Tank")
assertEqual(tankMarkerCalls[2].icon, 2, "second Tank receives the circle")
assertEqual(MSR:AssignMainTanks(tankRoster), true, "verified group click promotes all configured Tanks")
assertEqual(#mainTankAssignments, 2, "only Tank roles receive /mt")
assertEqual(mainTankAssignments[1].assignment, "MAINTANK", "first Tank uses MAINTANK assignment")
assertEqual(mainTankAssignments[1].unit, "raid1", "first Tank unit is forwarded")
assertEqual(mainTankAssignments[2].unit, "raid6", "second Tank unit is forwarded")
assertEqual(mainTankAssignments[2].exactMatch, true, "main-Tank assignment uses exact player matching")
mainTankAssignments = {}
local buildRosterForMarkers = MSR.BuildRoster
MSR.BuildRoster = function() return tankRoster end
tankMarkerCalls = {}
assertEqual(MSR:AssignMainTank(tankRoster[1]), true, "MT button assigns its selected Tank directly")
assertEqual(#mainTankAssignments, 1, "MT button performs one direct assignment")
assertEqual(mainTankAssignments[1].name, "MainTank", "MT button forwards the selected Tank name")
assertEqual(#tankMarkerCalls, 2, "MT button refreshes both Tank markers")
assertEqual(tankMarkerCalls[1].icon, 1, "MT button keeps the first Tank on star")
assertEqual(tankMarkerCalls[2].icon, 2, "MT button keeps the second Tank on circle")
MSR.BuildRoster = buildRosterForMarkers

tankMarkerCalls = {}
MSR.runtime.automaticGroupAssignment = {
    key = "tank2", name = "OffTank", target = 2, reason = "role changed", attempts = 1,
}
assertEqual(MSR:UpdateAutomaticGroupAssignment(tankRoster), true,
    "confirmed automatic assignment refreshes Tank markers")
assertEqual(#tankMarkerCalls, 2, "automatic assignment marks both Tanks")
assertEqual(tankMarkerCalls[1].icon, 1, "automatic assignment gives first Tank the star")
assertEqual(tankMarkerCalls[2].icon, 2, "automatic assignment gives second Tank the circle")

local statuses = { player = "ready", raid2 = "notready", raid3 = "waiting" }
GetReadyCheckStatus = function(unit) return statuses[unit] end
MSR.runtime.readyCheck = MSR:CreateReadyCheckState(roster, "Leader")
MSR:RefreshReadyCheckMemberStatuses(MSR.runtime.readyCheck)
local readyText = MSR:GetReadyCheckStatusText()
assertContains(readyText, "1/3 ready", "ready count")
assertContains(readyText, "Not ready: Alice", "not-ready name")
assertContains(readyText, "Waiting: Bob", "waiting name")

MSR:HandleReadyCheckEvent("READY_CHECK_CONFIRM", "raid3", true)
assertEqual(MSR.runtime.readyCheck.ready, 2, "live ready confirmation")
assertEqual(MSR:GetReadyCheckMemberStatus(roster[2]), "notready", "per-player not-ready status")
assertEqual(MSR:GetReadyCheckMemberStatus(roster[3]), "ready", "per-player ready status")

MSR.char.session.applicants = {
    alice = { key = "alice", name = "Alice", status = "Joined", role = "HEAL", aura = true },
    waiter = { key = "waiter", name = "Waiter", status = "New", role = "DPS", aura = false },
}
MSR.char.session.order = { "alice", "waiter" }
MSR.char.session.listening = true
MSR.db.settings.autoPost = true
C_Manastorm = {
    IsInManastorm = function() return false end,
    Enter = function(level) return level == 1 end,
}
local originalBuildRoster = MSR.BuildRoster
MSR.BuildRoster = function() return roster end
assertEqual(MSR:StartManastormLevelOne(), true, "Manastorm start request")
MSR.BuildRoster = originalBuildRoster
assertEqual(MSR.char.session.listening, false, "listening stops when Manastorm starts")
assertEqual(MSR.db.settings.autoPost, true, "Manastorm start preserves enabled Auto-Post setting")
assertEqual(MSR.char.session.applicants.waiter, nil, "waiting applicant cleared on Manastorm start")
assertEqual(MSR.char.session.applicants.alice.name, "Alice", "joined applicant retained on Manastorm start")
assertEqual(#MSR.char.session.order, 1, "only joined applicants remain ordered")

MSR.db.settings.autoPost = false
MSR.char.session.listening = true
MSR:StopRecruitmentForManastorm()
assertEqual(MSR.char.session.listening, false, "Manastorm stop helper always disables listener")
assertEqual(MSR.db.settings.autoPost, false, "Manastorm stop helper preserves disabled Auto-Post setting")

local sentMessage, sentChannel
GetNumRaidMembers = function() return 3 end
SendChatMessage = function(message, channel)
    sentMessage, sentChannel = message, channel
    return true
end
local leavePartyCalls = 0
LeaveParty = function()
    leavePartyCalls = leavePartyCalls + 1
    return true
end
assertEqual(MSR:SendGroupChat("Hello raid"), true, "embedded chat send")
assertEqual(sentMessage, "Hello raid", "embedded chat message")
assertEqual(sentChannel, "RAID", "embedded chat channel")
assertEqual(MSR:GetMessageRoute("rosterSummary"), "RAID", "roster summary keeps its legacy raid-chat default")
assertEqual(MSR:GetMessageRoute("level60Warning"), "RAID_WARNING", "level warning keeps its legacy raid-warning default")
assertEqual(MSR:GetMessageRoute("recruitment"), nil, "recruitment output remains fixed to its recruitment channel")
local localConfiguredOutput
local originalPrint = MSR.Print
MSR.Print = function(_, message) localConfiguredOutput = message end
assertEqual(MSR:SetMessageRoute("rosterSummary", "LOCAL"), true, "roster route can be changed")
assertEqual(MSR:SendConfiguredMessage("rosterSummary", "Local roster"), true, "local configured message is delivered")
assertEqual(localConfiguredOutput, "Local roster", "local configured message remains private")
localConfiguredOutput = nil
assertEqual(MSR:SetMessageRoute("rosterSummary", "OFF"), true, "configured message can be disabled")
assertEqual(MSR:SendConfiguredMessage("rosterSummary", "Hidden roster"), true, "disabled message is intentionally skipped")
assertEqual(localConfiguredOutput, nil, "disabled message produces no local output")
assertEqual(MSR:SetMessageRoute("rosterSummary", "RAID"), true, "roster route can be restored")
MSR.Print = originalPrint

local reminderTarget
MSR.char.session.applicants.pending = {
    key = "pending", name = "Pending", role = "DPS", aura = true,
    status = "Invited", inviteSentAt = 1000, inviteReminderSent = false,
}
SendChatMessage = function(message, channel, _, target)
    sentMessage, sentChannel, reminderTarget = message, channel, target
    return true
end
epochNow = 1005
MSR:UpdatePendingInvites()
assertEqual(sentChannel, "WHISPER", "pending invite reminder channel")
assertEqual(reminderTarget, "Pending", "pending invite reminder target")
epochNow = 1010
MSR:UpdatePendingInvites()
assertEqual(MSR.char.session.applicants.pending.status, "NoResponse", "pending invite releases after ten seconds")
epochNow = 1000

local automaticReplies, lastAutomaticReply = 0, nil
SendChatMessage = function(message, channel)
    if channel == "WHISPER" then
        automaticReplies = automaticReplies + 1
        lastAutomaticReply = message
    end
    return true
end
MSR.char.session.listening = true
MSR.db.settings.autoReply = true
MSR:HandleWhisper("tank aura yes", "Dedupe")
MSR:HandleWhisper("tank aura yes", "Dedupe")
assertEqual(automaticReplies, 1, "unchanged application reply is deduplicated")
MSR:HandleWhisper("heal aura yes", "Dedupe")
assertEqual(automaticReplies, 2, "changed application receives a new reply")

MSR:HandleWhisper("dps", "Clarify")
assertEqual(MSR.char.session.applicants.clarify.aura, false, "missing Aura defaults to no Aura")
assertEqual(MSR.char.session.applicants.clarify.pendingQuestion, "level", "missing Aura does not start clarification")
assertContains(lastAutomaticReply, "level", "missing level question is whispered")
MSR:HandleWhisper("42", "Clarify")
assertEqual(MSR.char.session.applicants.clarify.level, 42, "level-only answer updates applicant")
assertEqual(MSR.char.session.applicants.clarify.pendingQuestion, nil, "clarification completes after level")
assertContains(lastAutomaticReply, "only need players with Aura", "no-Aura applicant receives the configured Aura reservation reply")
assertEqual(automaticReplies, 4, "level question and completion each receive one reply")

MSR:HandleWhisper("dps aura yes level 42", "ExplicitAura")
assertEqual(MSR.char.session.applicants.explicitaura.aura, true, "explicit Aura marks the applicant as Aura")
assertEqual(automaticReplies, 5, "explicit Aura application receives one reply")

MSR.char.session.chatScanEntries = {}
MSR.char.session.chatScanOrder = {}
MSR.char.session.order = MSR.char.session.order or {}
MSR.char.session.listening = true
assertEqual(MSR:IsChatScanCandidate("LF Manastorm"), true, "LF plus Manastorm is accepted")
assertEqual(MSR:IsChatScanCandidate("LFG Manastorms"), true, "LFG plus Manastorms is accepted")
assertEqual(MSR:IsChatScanCandidate("LFM MS need healer"), false, "other groups looking for members are ignored")
assertEqual(MSR:IsChatScanCandidate("LFG looms dps"), false, "loom gear terms do not identify Manastorm")
assertEqual(MSR:IsChatScanCandidate("MS need tank healer dps"), false, "roles without LF or LFG are ignored")
assertEqual(MSR:IsChatScanCandidate("LFG dungeon dps"), false, "LFG without Manastorm is ignored")
assertEqual(MSR:HandlePublicChannelMessage("LFG MS dps loom", "ScanGuy", "1. Ascension", 1, "Ascension"), true, "public Manastorm post is scanned")
assertEqual(#MSR:GetChatScanEntries(), 1, "scanner records one candidate")
assertEqual(MSR:GetChatScanEntries()[1].role, "DPS", "scanner infers public-post role")
assertEqual(MSR:GetChatScanEntries()[1].aura, false, "scanner defaults missing Aura to no Aura")
assertEqual(MSR:HandlePublicChannelMessage("new LFG MS dps", "ScanGuy", "1. Ascension", 1, "Ascension"), true, "repeated candidate updates")
assertEqual(#MSR:GetChatScanEntries(), 1, "repeated player is deduplicated")
assertEqual(MSR:HandlePublicChannelMessage("WTS materials", "Trader", "2. Trade", 2, "Trade"), false, "unrelated public post is ignored")
local scannerInviteName
InviteUnit = function(name) scannerInviteName = name return true end
local originalIsGroupLeader = MSR.IsGroupLeader
MSR.IsGroupLeader = function() return true end
assertEqual(MSR:InviteChatScanEntry(MSR:GetChatScanEntries()[1]), true, "scanner candidate can be invited without an Aura declaration")
assertEqual(scannerInviteName, "ScanGuy", "scanner invites the detected player")
assertEqual(MSR.char.session.applicants.scanguy.status, "Invited", "scanner invite enters applicant workflow")
MSR.IsGroupLeader = originalIsGroupLeader

local originalIsInManastorm = MSR.IsInManastorm
local lateReplyMessage, lateReplyChannel, lateReplyTarget, lateReplyCount
lateReplyCount = 0
MSR.IsInManastorm = function() return true end
MSR.char.session.listening = false
SendChatMessage = function(message, channel, _, target)
    lateReplyMessage, lateReplyChannel, lateReplyTarget = message, channel, target
    lateReplyCount = lateReplyCount + 1
    return true
end
MSR:HandleWhisper("Are you still recruiting?", "Lateplayer")
assertEqual(lateReplyChannel, "WHISPER", "Manastorm reply bypasses stopped listening")
assertEqual(lateReplyTarget, "Lateplayer", "Manastorm reply targets the late whisper sender")
assertContains(lateReplyMessage, "already inside Manastorm", "late whisper receives Manastorm status")
assertEqual(MSR.char.session.applicants.lateplayer, nil, "late Manastorm whisper is not added as applicant")
MSR:HandleWhisper("Any free slot?", "Lateplayer")
assertEqual(lateReplyTarget, "Lateplayer", "later whispers still receive the Manastorm reply")
assertEqual(lateReplyCount, 2, "every later Manastorm whisper is answered")
MSR.IsInManastorm = originalIsInManastorm
SendChatMessage = function(message, channel)
    sentMessage, sentChannel = message, channel
    return true
end

MSR.BuildRoster = function() return roster end
local level60Status = MSR:BuildLevel60StatusMessage(roster)
assertContains(level60Status, "Thanks, everyone! I have reached level 60", "friendly manual Level 60 status")
assertContains(level60Status, "Raid lead will pass automatically when I leave", "automatic lead handoff information")
assertContains(level60Status, "The current roster is", "current roster introduction")
assertContains(level60Status, "Tank 1/2, Heal 1/3, Aura 2/3", "configured Level 60 roster counts")
assertContains(level60Status, "Aura players: Leader, Alice", "Aura player names")
assertEqual(MSR:PostLevel60Status(), true, "manual Level 60 post")
assertEqual(sentMessage, level60Status, "manual Level 60 group message")
assertEqual(leavePartyCalls, 0, "Level 60 post waits before leaving the group")
monotonicNow = monotonicNow + 1
MSR:UpdatePendingLeave()
assertEqual(leavePartyCalls, 1, "Level 60 group leave starts after the post delay")

playerLevel = 59
local level59Status = MSR:BuildLevelStatusMessage(roster)
assertContains(level59Status, "I am level 59 and close to level 60", "manual Level 59 status")
assertEqual(MSR:PostLevelStatus(), true, "manual Level 59 post")
assertEqual(sentMessage, level59Status, "manual Level 59 group message")
assertEqual(leavePartyCalls, 1, "Level 59 post waits before leaving the group")
monotonicNow = monotonicNow + 1
MSR:UpdatePendingLeave()

playerLevel = 42
local below59Status = MSR:BuildLevelStatusMessage(roster)
assertContains(below59Status, "leaving the raid at level 42", "manual below-Level-59 status")
assertEqual(MSR:PostLevelStatus(), true, "manual below-Level-59 post")
assertEqual(sentMessage, below59Status, "manual below-Level-59 group message")
assertEqual(leavePartyCalls, 2, "below-Level-59 post waits before leaving the group")
monotonicNow = monotonicNow + 1
MSR:UpdatePendingLeave()
assertEqual(leavePartyCalls, 3, "Post and Leave exits the group outside Manastorm")

local insideManastorm = true
local leaveManastormCalls = 0
MSR.IsInManastorm = function() return insideManastorm end
C_Manastorm.Leave = function()
    leaveManastormCalls = leaveManastormCalls + 1
    return true
end
assertEqual(MSR:PostLevelStatus(), true, "Post and Leave starts inside Manastorm")
assertEqual(leaveManastormCalls, 0, "Manastorm exit waits for the chat post delay")
monotonicNow = monotonicNow + 1
MSR:UpdatePendingLeave()
assertEqual(leaveManastormCalls, 1, "Manastorm is left after the chat post delay")
assertEqual(leavePartyCalls, 3, "group remains until Manastorm exit confirmation")
insideManastorm = false
MSR:UpdatePendingLeave()
assertEqual(leavePartyCalls, 4, "group leaves after Manastorm exit confirmation")

insideManastorm = true
GetNumRaidMembers = function() return 0 end
GetNumPartyMembers = function() return 0 end
assertEqual(MSR:PostLevelStatus(), true, "solo Manastorm exit remains available without a group")
assertEqual(leaveManastormCalls, 2, "solo Manastorm exit uses only the Manastorm leave API")
assertEqual(leavePartyCalls, 4, "solo Manastorm exit does not call LeaveParty")
GetNumRaidMembers = function() return 3 end

local removedName
IsRaidLeader = function() return true end
InCombatLockdown = function() return false end
roster[2].level = 59
MSR.char.session.level59Alerted = {}
MSR.char.session.level60Alerted = {}
MSR.IsInManastorm = function() return true end
MSR:ScanForLevel60()
assertEqual(sentChannel, "RAID_WARNING", "Level 59 uses a real raid warning")
assertContains(sentMessage, "Alice", "Level 59 raid warning player")

UninviteUnit = function(name) removedName = name return true end
assertEqual(MSR:KickRosterMember(roster[2]), true, "single-player removal")
assertEqual(removedName, "Alice", "selected player removal target")
assertEqual(MSR:KickRosterMember(roster[1]), false, "self removal is blocked")

MSR:RecordGroupChat("CHAT_MSG_RAID", "Ready?", "Alice-Realm")
assertEqual(#MSR.runtime.groupChat, 1, "embedded chat history")
assertEqual(MSR.runtime.groupChat[1].sender, "Alice", "chat sender normalization")

MSR.runtime.rebuild = { phase = "inviting", snapshot = {}, index = 1 }
assertEqual(MSR:AttemptRebuildInvite(false), true, "finished reinvites enter return wait")
assertEqual(MSR.runtime.rebuild.phase, "waiting-return", "rebuild waits for returning players")
assertEqual(MSR.runtime.rebuild.deadline - GetTime(), 10, "rebuild return wait is limited to ten seconds")

local originalGetRemainingRebuildMembers = MSR.GetRemainingRebuildMembers
local automaticRemaining = { { key = "alice", name = "Alice" } }
local automaticRemovalCalls, automaticRebuildLeaveCalls = 0, 0
MSR.GetRemainingRebuildMembers = function() return automaticRemaining end
UninviteUnit = function()
    automaticRemovalCalls = automaticRemovalCalls + 1
    return true
end
MSR.IsInManastorm = function() return true end
C_Manastorm.Leave = function()
    automaticRebuildLeaveCalls = automaticRebuildLeaveCalls + 1
    return true
end
MSR.char.session.rebuildRecovery = { active = true, stage = "removing" }
MSR.runtime.rebuild = {
    phase = "countdown",
    deadline = GetTime(),
    snapshot = automaticRemaining,
    removalSnapshot = automaticRemaining,
    reinviteSnapshot = {},
    index = 1,
}
MSR:UpdateRebuild()
assertEqual(automaticRemovalCalls, 1, "rebuild removes stored members automatically after countdown")
assertEqual(MSR.runtime.rebuild.phase, "waiting-bulk-remove", "automatic rebuild waits for removal confirmation")
automaticRemaining = {}
MSR:UpdateRebuild()
assertEqual(automaticRebuildLeaveCalls, 1, "rebuild leaves Manastorm automatically after removals")
assertEqual(MSR.runtime.rebuild.phase, "waiting-manastorm-exit", "automatic rebuild waits for Manastorm exit")
MSR.IsInManastorm = function() return false end
MSR:UpdateRebuild()
assertEqual(MSR.runtime.rebuild.phase, "waiting-empty", "automatic rebuild advances to reinvite delay")
MSR.GetRemainingRebuildMembers = originalGetRemainingRebuildMembers

MSR.runtime.rebuild = nil
MSR.runtime.rosterByKey = {}
MSR.char.session.rebuildRecovery = {
    active = true,
    stage = "reinviting",
    removalSnapshot = { { key = "alice", name = "Alice" } },
    reinviteSnapshot = { { key = "alice", name = "Alice", role = "HEAL", aura = true } },
    excluded = {},
}
MSR.IsInManastorm = function() return false end
assertEqual(MSR:ResumeRebuild(), true, "unfinished rebuild can be resumed")
assertEqual(MSR.runtime.rebuild.phase, "inviting", "rebuild recovery resumes at reinvites")

MSR.char.session.applicants.legacyaura = {
    key = "legacyaura",
    name = "LegacyAura",
    role = "DPS",
    aura = nil,
    level = 42,
    needsReview = true,
    pendingQuestion = "aura",
    messageHistory = { { message = "dps 42", parsedAura = nil } },
}
MSR.char.session.chatScanEntries = {
    legacychat = { name = "LegacyChat", role = "DPS", roleMatches = 1, aura = nil, needsReview = true },
}
MSR.char.session.whisperHistory = {
    { sender = "LegacyWhisper", role = "DPS", aura = nil, needsReview = true },
}
MSR:NormalizeAuraDefaults()
assertEqual(MSR.char.session.applicants.legacyaura.aura, false, "legacy applicant Aura migrates to no Aura")
assertEqual(MSR.char.session.applicants.legacyaura.needsReview, false, "legacy applicant no longer needs Aura review")
assertEqual(MSR.char.session.applicants.legacyaura.pendingQuestion, nil, "legacy Aura question is cleared")
assertEqual(MSR.char.session.applicants.legacyaura.messageHistory[1].parsedAura, false,
    "legacy applicant history migrates to no Aura")
assertEqual(MSR.char.session.chatScanEntries.legacychat.aura, false, "legacy scanner Aura migrates to no Aura")
assertEqual(MSR.char.session.whisperHistory[1].aura, false, "legacy whisper Aura migrates to no Aura")

MSR.char.session.applicants = { private = { name = "Privateplayer" } }
MSR.char.session.order = { "private" }
MSR.char.session.whisperHistory = { { sender = "Privateplayer", message = "dps aura yes" } }
MSR:ClearSession()
assertEqual(next(MSR.char.session.applicants), nil, "session reset clears applicants")
assertEqual(next(MSR.char.session.whisperHistory), nil, "session reset clears stored whispers")
assertEqual(MSR.char.session.rebuildRecovery.active, false, "session reset clears rebuild recovery")

print("CoreTests: all assertions passed")
