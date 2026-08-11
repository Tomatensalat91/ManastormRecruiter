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
    function frame:SetChecked(value) self.checked = value end
    function frame:GetChecked() return self.checked and 1 or nil end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:GetAlpha() return rawget(self, "alpha") == nil and 1 or rawget(self, "alpha") end
    function frame:SetWidth(value) self.width = value end
    function frame:GetWidth() return rawget(self, "width") or 0 end
    function frame:SetHeight(value) self.height = value end
    function frame:GetHeight() return rawget(self, "height") or 0 end
    function frame:Enable() self.enabled = true end
    function frame:Disable() self.enabled = false end
    function frame:IsEnabled() return self.enabled ~= false end
    function frame:GetFrameLevel() return 1 end
    function frame:GetCenter() return 0, 0 end
    function frame:GetEffectiveScale() return 1 end
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
        __index = function()
            return function() end
        end,
    })
    return frame
end

CreateFrame = function() return NewFrame() end
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
assertTrue(UI.messageTemplatesFrame, "message template frame")
assertTrue(UI.messageButtons.recruitment, "recruitment template button")
assertTrue(UI.messageButtons.missingAuraReply, "missing Aura question template button")
assertTrue(UI.messageButtons.missingLevelReply, "missing level question template button")
assertTrue(UI.messageEditorFrame, "single-message editor frame")
assertTrue(UI.messageEditorInput, "single-message editor input")
assertTrue(UI.groupChatMessages, "embedded chat history")
assertTrue(UI.groupChatInput, "embedded chat input")
assertTrue(UI.level60StatusButton, "manual Level 60 status button")
assertTrue(UI.groupCards[1].rows[1].roleIcon, "role icon")
assertTrue(UI.groupCards[1].rows[1].readyText, "per-player ready status")
assertTrue(UI.groupCards[1].rows[1].kickButton, "per-player kick button")
assertTrue(next(UI.phaseButtons) == nil, "separate phase tabs are removed")
assertTrue(UI.recruitToggleActionButton:IsShown(), "recruitment toggle shown")
assertTrue(UI.frame:GetHeight() == 610, "recruitment uses compact content height")
assertTrue(UI.recruitToggleActionButton.stateColor == "red", "stopped recruitment toggle is red")
ManastormRecruiter.char.session.listening = true
ManastormRecruiter.db.settings.autoPost = true
UI:Refresh()
assertTrue(UI.recruitToggleActionButton.stateColor == "green", "running recruitment toggle is green")
ManastormRecruiter.char.session.listening = false
ManastormRecruiter.db.settings.autoPost = false
UI:Refresh()
assertTrue(UI.settingsEditMessagesButton, "message editor action lives in settings")
assertTrue(UI.settingsPanel:GetAlpha() == 0, "closed settings backdrop is transparent")
assertTrue(not UI.optimizeButton:IsShown(), "raid actions hidden during recruitment")
UI.settingsOpen = true
UI:ApplyPhaseVisibility()
assertTrue(UI.settingsPanel:GetAlpha() == 1, "open settings backdrop is opaque")
assertTrue(UI.frame:GetHeight() == 680, "open recruitment settings reserve enough height")
UI.settingsOpen = false
UI:ApplyPhaseVisibility()
UI:ToggleCompactMode()
assertTrue(ManastormRecruiter.db.settings.compactMode, "compact mode persisted")
UI:ToggleCompactMode()
UI:FreezeApplicantOrder()
local frozenOrder = UI.frozenApplicantOrder
UI:FreezeApplicantOrder()
assertTrue(UI.frozenApplicantOrder == frozenOrder, "applicant order remains frozen across repeated edits")

UI:ShowMessageTemplates()
assertTrue(UI.messageTemplatesFrame:IsShown(), "message overview shown")
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
UI:RefreshGroups()
assertContains(UI.groupCards[1].rows[1].nameText:GetText(), "Longplayername", "full raid-row player name")
assertContains(UI.groupCards[1].rows[1].readyText:GetText(), "R", "ready result shown in player row")
assertTrue(not UI.groupCards[1].rows[1].kickButton:IsEnabled(), "self kick button disabled")

UnitLevel = function() return 59 end
GetNumPartyMembers = function() return 1 end
UI:Refresh()
assertTrue(UI.phase == "raid", "group automatically activates build-raid phase")
assertTrue(UI.frame:GetHeight() == 610, "single overview keeps its compact height while grouped")
assertTrue(UI.optimizeButton:IsShown(), "optimize action shown while building raid")
assertTrue(UI.recruitmentPreviewLabel:IsShown(), "recruitment preview remains on the single overview")
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
assertTrue(UI.frame:GetHeight() == 610, "single overview remains the same height in Manastorm")
assertTrue(UI.postRosterButton:IsShown(), "post-roster action remains in the raid panel during Manastorm")
assertTrue(UI.applicantsPanel:IsShown(), "applicants remain visible on the single overview")
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
assertTrue(UI.frame:GetHeight() == 610, "rebuild remains on the single overview")
assertTrue(not UI.rebuildPanel:IsShown(), "separate rebuild page stays hidden")
assertTrue(UI.resumeRebuildActionButton:IsShown(), "resume action shown for saved recovery")
print("UITests: all assertions passed")
