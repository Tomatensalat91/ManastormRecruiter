local function assertTrue(value, label)
    if not value then error(label .. ": expected a truthy value") end
end

local function assertContains(value, expected, label)
    if not string.find(tostring(value), expected, 1, true) then
        error(string.format("%s: expected %q in %q", label, expected, tostring(value)))
    end
end

local function NewFrame()
    local frame = { shown = true, text = "", messages = {} }
    function frame:CreateFontString() return NewFrame() end
    function frame:CreateTexture() return NewFrame() end
    function frame:SetText(value) self.text = tostring(value or "") end
    function frame:GetText() return self.text end
    function frame:SetTexture(value) self.texture = value end
    function frame:SetChecked(value) self.checked = value end
    function frame:GetChecked() return self.checked and 1 or nil end
    function frame:SetAttribute(key, value)
        local attributes = rawget(self, "attributes")
        if type(attributes) ~= "table" then
            attributes = {}
            rawset(self, "attributes", attributes)
        end
        attributes[key] = value
    end
    function frame:GetAttribute(key)
        local attributes = rawget(self, "attributes")
        return type(attributes) == "table" and attributes[key] or nil
    end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetAlpha() return rawget(self, "alpha") == nil and 1 or rawget(self, "alpha") end
    function frame:SetWidth(value) self.width = value end
    function frame:GetWidth() return rawget(self, "width") or 0 end
    function frame:SetHeight(value) self.height = value end
    function frame:GetHeight() return rawget(self, "height") or 0 end
    function frame:SetMovable(value) self.movable = value end
    function frame:StartMoving() self.moving = true end
    function frame:StopMovingOrSizing() self.moving = false self.stoppedMoving = true end
    function frame:SetBackdropColor(...) self.backdropColor = { ... } end
    function frame:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
    function frame:SetPoint(...)
        local points = rawget(self, "points")
        if type(points) ~= "table" then
            points = {}
            rawset(self, "points", points)
        end
        table.insert(points, { ... })
    end
    function frame:ClearAllPoints() rawset(self, "points", {}) end
    function frame:Enable() self.enabled = true end
    function frame:Disable() self.enabled = false end
    function frame:IsEnabled() return self.enabled ~= false end
    function frame:GetFrameLevel() return 1 end
    function frame:GetCenter() return rawget(self, "centerX") or 0, rawget(self, "centerY") or 0 end
    function frame:GetEffectiveScale() return rawget(self, "effectiveScale") or 1 end
    function frame:SetScale(value) self.scale = value end
    function frame:SetScript(name, handler)
        local scripts = rawget(self, "scripts")
        if type(scripts) ~= "table" then
            scripts = {}
            rawset(self, "scripts", scripts)
        end
        scripts[name] = handler
    end
    function frame:AddMessage(value) table.insert(self.messages, value) end
    function frame:Clear() self.messages = {} end
    setmetatable(frame, {
        __index = function(_, key)
            if key == "EnableMouseWheel" then return nil end
            return function() end
        end,
    })
    return frame
end

CreateFrame = function(_, _, parent, template)
    local frame = NewFrame()
    frame.parent = parent
    frame.template = template
    return frame
end
UIParent = NewFrame()
UIParent:SetWidth(1200)
UIParent:SetHeight(680)
Minimap = NewFrame()
GameTooltip = NewFrame()
GameFontNormal = NewFrame()
GameFontNormalSmall = NewFrame()
DEFAULT_CHAT_FRAME = NewFrame()
UIErrorsFrame = NewFrame()
RaidWarningFrame = NewFrame()
ChatTypeInfo = { RAID_WARNING = {} }
StaticPopupDialogs = {}
StaticPopup_Show = function() end
SlashCmdList = {}

GetTime = function() return 100 end
time = function() return 1000 end
date = function() return "12:34" end
UnitName = function(unit) return unit == "player" and "Leader" or nil end
UnitLevel = function() return 20 end
UnitExists = function() return false end
UnitIsConnected = function() return true end
GetNumRaidMembers = function() return 0 end
GetNumPartyMembers = function() return 0 end
GetChannelName = function() return 8 end
GetCursorPosition = function() return 0, 0 end
InCombatLockdown = function() return false end

dofile("Core.lua")
dofile("Parser.lua")
dofile("Roster.lua")
dofile("Recruitment.lua")
dofile("Manastorm.lua")
dofile("Rebuild.lua")
ManastormRecruiterDB = nil
ManastormRecruiterCharDB = nil
ManastormRecruiter:InitializeDatabase()
dofile("UI.lua")
ManastormRecruiter:CreateUI()

local UI = ManastormRecruiter.UI
assertTrue(UI.frame, "main frame")
assertTrue(UI.minimapButton.icon.texture == "Interface\\AddOns\\ManastormRecruiter\\Assets\\ManastormRecruiterLogo.tga",
    "minimap button uses the custom Manastorm Recruiter logo")
assertTrue(UI.messageTemplatesFrame, "message template frame")
assertTrue(UI.messageTemplatesFrame.movable, "message template frame is movable")
assertTrue(UI.messageEditorFrame.movable, "message editor frame is movable")
assertTrue(UI.messageButtons.recruitment, "recruitment template button")
assertTrue(UI.messageButtons.missingLevelReply, "missing level question template button")
assertTrue(UI.messageEditorFrame, "single-message editor frame")
assertTrue(UI.messageEditorInput, "single-message editor input")
assertTrue(UI.groupChatMessages, "embedded chat history")
assertTrue(UI.groupChatInput, "embedded chat input")
assertTrue(UI.level60StatusButton, "manual Level 60 status button")
assertTrue(UI.groupCards[1].rows[1].roleButton, "editable roster role button")
assertTrue(UI.groupCards[1].rows[1].auraButton, "editable roster Aura button")
assertTrue(UI.groupCards[1].rows[1].readyText, "per-player ready status")
assertTrue(UI.groupCards[1].rows[1].kickButton, "per-player kick button")
assertTrue(UI.phaseButtons.applicants, "applicants navigation tab")
assertTrue(UI.phaseButtons.raid, "raid navigation tab")
assertTrue(UI.phaseButtons.settings, "settings navigation tab")
assertTrue(UI.phaseButtons.messages == nil, "message editing is kept inside settings")
assertTrue(UI.channelEdit.inputStyle == "flat", "channel uses a flat custom input")
assertTrue(UI.intervalEdit.inputStyle == "stepper", "post interval uses a stepper")
assertTrue(UI.slotEdits.tank.inputStyle == "stepper", "raid targets use steppers")
assertTrue(UI.groupChatInput.inputStyle == "flat", "raid chat uses a flat custom input")
assertTrue(UI.activePage == "applicants", "applicants is the initial page")
assertTrue(UI.applicantsPanel:IsShown(), "applicants page shows the waiting list")
assertTrue(UI.chatScannerPanel:IsShown(), "applicants page shows the public chat scanner")
assertTrue(not UI.groupsPanel:IsShown(), "applicants page keeps raid groups separate")
assertTrue(UI.waitingCountText, "waiting count is displayed as a passive badge")
assertTrue(UI.rosterOverview:IsShown(), "large roster overview is visible on operational pages")
assertTrue(UI.rosterOverviewCards.tank.icon.width == 36, "roster overview uses large role icons")
assertTrue(UI.rosterOverviewCards.aura.icon.texture == "Interface\\AddOns\\ManastormRecruiter\\Assets\\AuraBonusXP.tga",
    "roster overview uses the custom Aura icon")
assertContains(UI.rosterOverviewCards.tank.needText:GetText(), "NEED", "roster overview shows missing slots")
assertTrue(UI.joinedApplicantsTab == nil, "joined players are shown only on the raid groups page")
assertTrue(UI.recruitToggleActionButton:IsShown(), "recruitment toggle shown")
assertTrue(UI.recruitToggleActionButton.points[1][1] == "BOTTOMLEFT", "recruitment toggle has a fixed anchor")
assertContains(UI.recruitToggleActionButton:GetText(), "Recruit listener", "recruitment toggle describes listeners")
assertTrue(UI.frame:GetHeight() == 680, "mission-control workspace uses a stable height")
assertTrue(UI.recruitToggleActionButton.stateColor == "red", "stopped recruitment toggle is red")
local savedGetChatScanEntries = ManastormRecruiter.GetChatScanEntries
ManastormRecruiter.GetChatScanEntries = nil
UI:RefreshChatScanner()
assertContains(UI.chatScannerStatus:GetText(), "SCANNER UNAVAILABLE", "missing scanner API cannot abort the UI")
ManastormRecruiter.GetChatScanEntries = savedGetChatScanEntries
ManastormRecruiter.char.session.listening = true
ManastormRecruiter.db.settings.autoPost = false
UI:Refresh()
assertTrue(UI.recruitToggleActionButton.stateColor == "green", "active listener toggle is green without Auto-Post")
assertTrue(UI.manualRecruitmentActionButton:IsShown(), "manual recruitment button is shown when Auto-Post is off")
ManastormRecruiter.db.settings.autoPost = true
UI:Refresh()
assertTrue(not UI.manualRecruitmentActionButton:IsShown(), "manual recruitment button is hidden when Auto-Post is on")
assertTrue(ManastormRecruiter:HandlePublicChannelMessage(
    "LFG MS dps loom", "PublicPlayer", "1. Ascension", 1, "Ascension"
), "public recruitment post reaches the scanner")
assertTrue(UI.chatScannerRows[1]:IsShown(), "scanner renders its newest candidate")
assertContains(UI.chatScannerRows[1].messageText:GetText(), "LFG MS dps", "scanner renders public message preview")
assertTrue(UI.chatScannerRows[1].roleButton.roleState == "DPS", "scanner renders inferred role icon")
assertTrue(UI.chatScannerRows[1].metaText:GetText() == "12:34", "scanner metadata shows only the time")
assertTrue(UI.chatScannerRows[1].roleButton.icon.width == UI.chatScannerRows[1].roleButton.icon.height,
    "scanner role texture is square")
ManastormRecruiter:HandlePublicChannelMessage(
    "new LFG MS dps", "PublicPlayer", "1. Ascension", 1, "Ascension"
)
assertTrue(#ManastormRecruiter:GetChatScanEntries() == 1, "scanner deduplicates repeated players")
ManastormRecruiter:ClearChatScan()
ManastormRecruiter.char.session.listening = false
ManastormRecruiter.db.settings.autoPost = false
UI:Refresh()
assertTrue(UI.manualRecruitmentActionButton:IsShown(), "manual recruitment button remains available with listener off")
UI.autoPostCheck:SetChecked(true)
UI.autoPostCheck.scripts.OnClick(UI.autoPostCheck)
assertTrue(ManastormRecruiter.char.session.listening == false,
    "enabling Auto-Post in settings does not enable the listener")
UI.autoPostCheck:SetChecked(false)
UI.autoPostCheck.scripts.OnClick(UI.autoPostCheck)
assertTrue(UI.settingsEditMessagesButton, "message editor action lives in settings")
assertTrue(UI.settingsPanel:GetAlpha() == 0, "closed settings backdrop is transparent")
assertTrue(not UI.optimizeButton:IsShown(), "raid actions hidden during recruitment")
UI.settingsOpen = true
UI:ApplyPhaseVisibility()
assertTrue(UI.settingsPanel:GetAlpha() == 1, "open settings backdrop is opaque")
assertTrue(UI.activePage == "settings", "settings navigation activates the settings workspace")
assertTrue(not UI.applicantsPanel:IsShown(), "settings hides applicant operations")
assertTrue(not UI.chatScannerPanel:IsShown(), "settings hides the chat scanner")
assertTrue(not UI.groupsPanel:IsShown(), "settings hides raid operations")
assertTrue(UI.compactButton:IsShown(), "appearance control lives in settings")
UI.settingsOpen = false
UI:ApplyPhaseVisibility()
assertTrue(UI.activePage == "applicants", "closing settings returns to the previous operational page")
assertTrue(UI.applicantsPanel:IsShown(), "applicants page restores applicant operations")
assertTrue(not UI.groupsPanel:IsShown(), "applicants and raid groups remain separate")
UI.phaseButtons.raid.scripts.OnClick()
assertTrue(UI.activePage == "raid", "raid navigation opens the raid page")
assertTrue(not UI.applicantsPanel:IsShown(), "raid page hides applicant operations")
assertTrue(not UI.chatScannerPanel:IsShown(), "raid page hides the chat scanner")
assertTrue(UI.groupsPanel:IsShown(), "raid page shows raid groups")
assertTrue(UI.optimizeButton:IsShown(), "raid page always shows optimize groups")
assertTrue(UI.readyCheckButton:IsShown(), "raid page always shows ready check")
assertTrue(UI.startManastormButton:IsShown(), "raid page always shows start Manastorm")
UI.phaseButtons.applicants.scripts.OnClick()
UI:ToggleCompactMode()
assertTrue(ManastormRecruiter.db.settings.compactMode, "compact mode persisted")
UI:ToggleCompactMode()
UI:FreezeApplicantOrder()
local frozenOrder = UI.frozenApplicantOrder
UI:FreezeApplicantOrder()
assertTrue(UI.frozenApplicantOrder == frozenOrder, "applicant order remains frozen across repeated edits")

UI:ShowMessageTemplates()
assertTrue(UI.messageTemplatesFrame:IsShown(), "message overview shown")
UI.messageTemplatesFrame.scripts.OnDragStart(UI.messageTemplatesFrame)
assertTrue(UI.messageTemplatesFrame.moving, "message overview starts dragging")
UI.messageTemplatesFrame.scripts.OnDragStop(UI.messageTemplatesFrame)
assertTrue(UI.messageTemplatesFrame.stoppedMoving, "message overview stops dragging")
assertTrue(UI.messageRouteButtons.rosterSummary.RAID, "roster summary has a Raid output button")
assertTrue(UI.messageRouteButtons.rosterSummary.RAID_WARNING, "roster summary has a Raid Warning output button")
assertTrue(UI.messageRouteButtons.rosterSummary.LOCAL, "roster summary has a local output button")
assertTrue(UI.messageRouteButtons.recruitment == nil, "recruitment keeps its fixed channel output")
UI.messageRouteButtons.rosterSummary.LOCAL.scripts.OnClick()
assertTrue(ManastormRecruiter:GetMessageRoute("rosterSummary") == "LOCAL", "local route is persisted from the mini button")
assertTrue(UI.messageRouteButtons.rosterSummary.LOCAL.stateColor == "green", "active route button is highlighted")
UI.messageRouteButtons.rosterSummary.LOCAL.scripts.OnClick()
assertTrue(ManastormRecruiter:GetMessageRoute("rosterSummary") == "OFF", "clicking the active route disables the message")
UI.messageRouteButtons.rosterSummary.RAID.scripts.OnClick()
UI:ShowMessageTemplateEditor("recruitment")
assertTrue(UI.messageEditorFrame:IsShown(), "message editor shown")
assertContains(UI.messageEditorInput:GetText(), "LFM MS", "message template load")
UI.messageEditorInput:SetText("Custom recruitment {needed}")
UI:CommitMessageTemplate()
assertContains(ManastormRecruiter.db.settings.messages.recruitment, "Custom recruitment", "single message saved")
assertContains(UI.messageButtons.recruitment:GetText(), "*", "customized message marker")
ManastormRecruiter.db.settings.messages.recruitment = ManastormRecruiter.MESSAGE_DEFAULTS.recruitment
UI:RefreshMessageTemplateButtons()

ManastormRecruiter:RecordGroupChat("CHAT_MSG_RAID", "Ready?", "Alice-Realm")
assertTrue(#UI.groupChatMessages.messages == 1, "chat message rendered")

UI:Refresh()

local editableApplicant = ManastormRecruiter:EnsureApplicant("EditablePlayer")
editableApplicant.role = "DPS"
editableApplicant.aura = false
editableApplicant.message = "dps aura yes level 42 ready for manastorm"
local editableMember = { key = "editableplayer", name = "EditablePlayer", role = "DPS", aura = false }
UI:CycleRosterMemberRole(editableMember)
assertTrue(editableApplicant.role == "TANK", "raid row cycles a grouped player's role")
UI:ToggleRosterMemberAura(editableMember)
assertTrue(editableApplicant.aura == true, "raid row toggles a grouped player's Aura")
UI:RefreshApplicants()
local messagePreviewFound = false
local applicantIconsFound = false
for _, row in ipairs(UI.applicantRows) do
    if string.find(row.messageText:GetText(), "ready for manastorm", 1, true) then
        messagePreviewFound = true
        applicantIconsFound = row.roleButton.roleState == "TANK"
            and row.auraButton.auraState == "yes"
            and row.auraButton.icon.texture == "Interface\\AddOns\\ManastormRecruiter\\Assets\\AuraBonusXP.tga"
    end
end
assertTrue(messagePreviewFound, "applicant page previews the most recent message")
assertTrue(applicantIconsFound, "applicant page uses role and custom Aura icons")
editableApplicant.aura = false
UI:RefreshApplicants()
local noAuraIconFound = false
local editableApplicantRow
for _, row in ipairs(UI.applicantRows) do
    if row.applicant == editableApplicant then
        editableApplicantRow = row
        noAuraIconFound = row.auraButton.auraState == "no"
            and row.auraButton.icon.texture == "Interface\\AddOns\\ManastormRecruiter\\Assets\\AuraBonusXP.tga"
            and row.auraButton.icon.width == row.auraButton.icon.height
            and row.auraButton.noAuraSlashes[1]:IsShown()
            and row.auraButton.noAuraSlashes[2]:IsShown()
    end
end
assertTrue(noAuraIconFound, "default no-Aura state uses the square crossed-out Aura icon")
local restingRoleBorder = editableApplicantRow.roleButton.backdropBorderColor[1]
editableApplicantRow.roleButton.scripts.OnEnter(editableApplicantRow.roleButton)
assertTrue(editableApplicantRow.roleButton.backdropBorderColor[1] ~= restingRoleBorder,
    "waiting-player role keeps its hover animation")
editableApplicantRow.roleButton.scripts.OnLeave(editableApplicantRow.roleButton)
assertTrue(editableApplicantRow.roleButton.backdropBorderColor[1] == restingRoleBorder,
    "waiting-player role restores its normal border")
local restingAuraBorder = editableApplicantRow.auraButton.backdropBorderColor[1]
editableApplicantRow.auraButton.scripts.OnEnter(editableApplicantRow.auraButton)
assertTrue(editableApplicantRow.auraButton.backdropBorderColor[1] ~= restingAuraBorder,
    "waiting-player Aura keeps its hover animation")
editableApplicantRow.auraButton.scripts.OnLeave(editableApplicantRow.auraButton)
editableApplicant.aura = true

local member = {
    key = "leader",
    name = "Longplayername",
    unit = "player",
    subgroup = 1,
    level = 59,
    online = true,
    role = "TANK",
    aura = true,
    rank = 2,
}
ManastormRecruiter.BuildRoster = function() return { member } end
ManastormRecruiter.runtime.readyCheck = ManastormRecruiter:CreateReadyCheckState({ member }, "Leader")
local pageBeforeSecureMainTankTest = UI.activePage
UI.activePage = "raid"
UI.frame:Show()
local secureMainTankButton = UI.groupCards[1].rows[1].mainTankButton
secureMainTankButton.positionAnchor.centerX = 420
secureMainTankButton.positionAnchor.centerY = 310
secureMainTankButton.positionAnchor.effectiveScale = 0.8
UIParent.effectiveScale = 0.64
UI:RefreshGroups()
assertContains(UI.groupCards[1].rows[1].nameText:GetText(), "Longplayername", "full raid-row player name")
assertContains(UI.groupCards[1].rows[1].readyText:GetText(), "R", "ready result shown in player row")
assertTrue(UI.groupCards[1].rows[1].roleButton.roleState == "TANK", "raid row uses a Tank icon")
assertTrue(UI.groupCards[1].rows[1].auraButton.auraState == "yes", "raid row uses an Aura icon")
assertTrue(UI.groupCards[1].auraIcon.texture == "Interface\\AddOns\\ManastormRecruiter\\Assets\\AuraBonusXP.tga",
    "raid group Aura status uses the custom Aura icon")
assertTrue(UI.groupCards[1].rows[1].readyState == "ready", "ready player colors the complete row green")
assertTrue(UI.groupCards[1].rows[1].backdropColor[2] > UI.groupCards[1].rows[1].backdropColor[1],
    "ready row uses a green-dominant background")
ManastormRecruiter.runtime.readyCheck.members.leader.status = "notready"
UI:RefreshGroups()
assertTrue(UI.groupCards[1].rows[1].readyState == "notready", "not-ready player colors the complete row red")
assertTrue(UI.groupCards[1].rows[1].backdropColor[1] > UI.groupCards[1].rows[1].backdropColor[2],
    "not-ready row uses a red-dominant background")
ManastormRecruiter.runtime.readyCheck.members.leader.status = "waiting"
UI:RefreshGroups()
assertTrue(UI.groupCards[1].rows[1].readyState == "waiting", "waiting player colors the complete row yellow")
ManastormRecruiter.runtime.readyCheck = nil
UI:RefreshGroups()
assertTrue(UI.groupCards[1].rows[1].readyState == "neutral", "clearing Ready Check restores the neutral row")
assertTrue(UI.groupCards[1].rows[1].roleButton.width == 30
    and UI.groupCards[1].rows[1].roleButton.height == 30,
    "raid role control is square")
assertTrue(UI.groupCards[1].rows[1].auraButton.icon.width == UI.groupCards[1].rows[1].auraButton.icon.height,
    "raid Aura texture is square")
assertTrue(UI.groupCards[1].rows[1].mainTankButton ~= nil,
    "Tank rows expose a secure MT button")
assertTrue(rawget(UI.groupCards[1].rows[1].mainTankButton, "template") == "SecureActionButtonTemplate",
    "MT assignment uses a secure action button")
assertTrue(UI.groupCards[1].rows[1].mainTankButton.parent == UIParent,
    "secure MT button stays detached from the movable addon frame")
assertTrue(UI.groupCards[1].rows[1].mainTankButton:GetAttribute("type") == "macro",
    "secure MT button executes a macro")
assertContains(UI.groupCards[1].rows[1].mainTankButton:GetAttribute("macrotext"), "/mt Longplayername",
    "secure MT macro targets the selected Tank")
assertTrue(UI.groupCards[1].rows[1].mainTankButton.points[1][4] == 420
    and UI.groupCards[1].rows[1].mainTankButton.points[1][5] == 310,
    "secure MT position keeps the anchor's UIParent coordinates")
assertTrue(UI.groupCards[1].rows[1].mainTankButton.scale == 1.25,
    "secure MT size follows the source row's effective scale")
assertTrue(UI.groupCards[1].rows[1].mainTankButton.scripts.OnClick == nil,
    "secure MT button does not call protected APIs from insecure Lua")
assertTrue(UI.groupCards[1].rows[1].mainTankButton:IsShown(), "MT button is shown for Tanks")
assertTrue(not UI.groupCards[1].rows[1].kickButton:IsEnabled(), "self kick button disabled")
local originalMtGetNumRaidMembers = GetNumRaidMembers
local originalMtIsRaidLeader = IsRaidLeader
local originalMtIsRaidOfficer = IsRaidOfficer
GetNumRaidMembers = function() return 1 end
IsRaidLeader = function() return false end
IsRaidOfficer = function() return false end
UI:RefreshGroups()
assertTrue(secureMainTankButton:IsShown(),
    "MT button remains visible while rebuild raid permissions are settling")
assertTrue(not secureMainTankButton:IsEnabled(),
    "MT button is disabled without raid management rights")
IsRaidOfficer = function() return true end
UI:RefreshGroups()
assertTrue(secureMainTankButton:IsShown() and secureMainTankButton:IsEnabled(),
    "raid assistants can use the visible secure MT button")
GetNumRaidMembers = originalMtGetNumRaidMembers
IsRaidLeader = originalMtIsRaidLeader
IsRaidOfficer = originalMtIsRaidOfficer
UI.activePage = pageBeforeSecureMainTankTest
UI:HideSecureMainTankButtons()
UIParent.effectiveScale = 1

local ownAssignmentReason
local originalQueueSelfAutomaticGroupAssignment = ManastormRecruiter.QueueSelfAutomaticGroupAssignment
ManastormRecruiter.QueueSelfAutomaticGroupAssignment = function(_, reason)
    ownAssignmentReason = reason
    return true
end
UI:CycleRosterMemberRole(member)
assertTrue(ownAssignmentReason == "own role changed", "own raid-row role edit queues automatic assignment")
UI:ToggleRosterMemberAura(member)
assertTrue(ownAssignmentReason == "own Aura changed", "own raid-row Aura edit queues automatic assignment")
ManastormRecruiter.QueueSelfAutomaticGroupAssignment = originalQueueSelfAutomaticGroupAssignment

assertTrue(UI.automaticGroupsCheck ~= nil, "settings expose automatic group assignment toggle")
UI.automaticGroupsCheck:SetChecked(false)
UI.automaticGroupsCheck.scripts.OnClick(UI.automaticGroupsCheck)
assertTrue(ManastormRecruiter.db.settings.automaticGroupAssignment == false,
    "settings toggle disables automatic group assignment")
UI.automaticGroupsCheck:SetChecked(true)
UI.automaticGroupsCheck.scripts.OnClick(UI.automaticGroupsCheck)
assertTrue(ManastormRecruiter.db.settings.automaticGroupAssignment == true,
    "settings toggle enables automatic group assignment")

UnitLevel = function() return 59 end
GetNumPartyMembers = function() return 1 end
UI:Refresh()
assertTrue(UI.phase == "raid", "group automatically activates build-raid phase")
assertTrue(UI.frame:GetHeight() == 680, "mission-control workspace stays stable while grouped")
assertTrue(UI.optimizeButton:IsShown(), "optimize action shown while building raid")
assertTrue(UI.rosterOverview:IsShown(), "large roster overview remains visible across operational pages")
assertTrue(UI.postRosterButton:IsShown(), "post roster remains visible outside Manastorm while grouped")
assertContains(UI.levelStatusButton:GetText(), "Post & Leave", "Level 59 leave button label")
assertTrue(UI.levelStatusButton:IsEnabled(), "Level 59 info button enabled")

UnitLevel = function() return 42 end
UI:Refresh()
assertContains(UI.levelStatusButton:GetText(), "Post & Leave", "below-Level-59 leave button label")
assertTrue(UI.levelStatusButton:IsEnabled(), "below-Level-59 info button enabled")

ManastormRecruiter.IsInManastorm = function() return true end
UI:Refresh()
assertTrue(UI.phase == "manastorm", "Manastorm state activates monitoring phase")
assertTrue(UI.frame:GetHeight() == 680, "mission-control workspace remains stable in Manastorm")
assertTrue(UI.postRosterButton:IsShown(), "post-roster action remains in the raid panel during Manastorm")
assertTrue(UI.applicantsPanel:IsShown(), "the selected applicants page remains visible in Manastorm")
GetNumPartyMembers = function() return 0 end
UI:Refresh()
assertContains(UI.leaveActionButton:GetText(), "Leave MS", "solo Manastorm exit button label")
assertTrue(UI.leaveActionButton:IsEnabled(), "solo Manastorm exit button remains enabled")
GetNumPartyMembers = function() return 1 end

ManastormRecruiter.IsInManastorm = function() return false end
ManastormRecruiter.runtime.rebuild = {
    phase = "waiting-return",
    expectedTotal = 15,
    deadline = GetTime() + 10,
}
UI:Refresh()
assertTrue(UI.phase == "rebuild", "waiting-return remains part of rebuild state")
assertTrue(UI.recruitToggleActionButton:IsShown(), "recruiting can restart while waiting for rebuild returns")
ManastormRecruiter.runtime.rebuild = nil
ManastormRecruiter.char.session.rebuildRecovery = {
    active = true,
    removalSnapshot = {},
    reinviteSnapshot = {},
    excluded = {},
}
UI:Refresh()
assertTrue(UI.phase == "rebuild", "saved recovery activates rebuild phase")
assertTrue(UI.frame:GetHeight() == 680, "rebuild remains in the stable workspace")
assertTrue(not UI.rebuildPanel:IsShown(), "separate rebuild page stays hidden")
assertTrue(UI.resumeRebuildActionButton:IsShown(), "resume action shown for saved recovery")
print("UITests: all assertions passed")
