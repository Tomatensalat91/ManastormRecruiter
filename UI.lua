local MSR = ManastormRecruiter

local UI = {
    applicantOffset = 0,
    applicantPageSize = 10,
    applicantView = "waiting",
    phase = "recruitment",
}
MSR.UI = UI

local COLORS = {
    panel = { 0.035, 0.045, 0.065, 0.96 },
    inset = { 0.07, 0.08, 0.11, 0.96 },
    border = { 0.36, 0.46, 0.60, 1 },
    gold = { 1.0, 0.78, 0.22, 1 },
    muted = { 0.62, 0.67, 0.75, 1 },
    green = { 0.35, 1.0, 0.55, 1 },
    red = { 1.0, 0.35, 0.35, 1 },
    blue = { 0.35, 0.75, 1.0, 1 },
}

local ROLE_COLORS = {
    TANK = "|cff66aaff",
    HEAL = "|cff55ff77",
    DPS = "|cffffcc55",
    UNKNOWN = "|cffff6666",
}

local ROLE_ICONS = {
    TANK = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    HEAL = "Interface\\Icons\\Spell_Holy_HolyBolt",
    DPS = "Interface\\Icons\\Ability_DualWield",
    UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local MESSAGE_FIELDS = {
    { key = "recruitment", label = "Recruitment message" },
    { key = "reservationSuffix", label = "Aura reservation suffix" },
    { key = "invalidApplicationReply", label = "Incomplete application reply" },
    { key = "missingAuraReply", label = "Missing Aura question" },
    { key = "missingLevelReply", label = "Missing level question" },
    { key = "acceptedApplicationReply", label = "Accepted application reply" },
    { key = "inviteReminder", label = "Pending invite reminder" },
    { key = "inManastormReply", label = "Already in Manastorm reply" },
    { key = "raidFullReply", label = "Raid full reply" },
    { key = "roleFullReply", label = "Role full reply" },
    { key = "auraRequiredReply", label = "Aura required reply" },
    { key = "rosterSummary", label = "Roster summary" },
    { key = "rosterComplete", label = "Roster complete suffix" },
    { key = "rosterNeeded", label = "Roster missing suffix" },
    { key = "rebuildAnnouncement", label = "Rebuild raid warning" },
    { key = "level60Warning", label = "Level 60 raid warning" },
    { key = "level59Warning", label = "Level 59 raid warning" },
    { key = "level60StatusPost", label = "Post & Leave - Level 60" },
    { key = "level59StatusPost", label = "Post & Leave - Level 59" },
    { key = "belowLevel59StatusPost", label = "Post & Leave - Below Level 59" },
}

local MESSAGE_SECTIONS = {
    {
        title = "Recruitment and replies",
        x = 18,
        y = -82,
        keys = {
            "recruitment", "reservationSuffix", "invalidApplicationReply", "missingAuraReply", "missingLevelReply", "acceptedApplicationReply",
            "inManastormReply", "raidFullReply", "roleFullReply", "auraRequiredReply",
        },
    },
    {
        title = "Roster and raid warnings",
        x = 292,
        y = -82,
        keys = {
            "rosterSummary", "rosterComplete", "rosterNeeded", "rebuildAnnouncement",
            "level60Warning", "level59Warning",
        },
    },
    {
        title = "Post & Leave",
        x = 292,
        y = -304,
        keys = { "level60StatusPost", "level59StatusPost", "belowLevel59StatusPost" },
    },
}

local function GetMessageDefinition(key)
    for _, definition in ipairs(MESSAGE_FIELDS) do
        if definition.key == key then return definition end
    end
    return nil
end

local function SetBackdrop(frame, background, border)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local bg = background or COLORS.panel
    local edge = border or COLORS.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4])
end

local function CreateLabel(parent, text, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY", size and "GameFontNormalLarge" or "GameFontNormal")
    label:SetText(text or "")
    if color then label:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    label:SetJustifyH("LEFT")
    return label
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width or 90)
    button:SetHeight(height or 24)
    button:SetText(text or "Button")
    return button
end

local function CreateEditBox(parent, width, numeric)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetWidth(width or 60)
    edit:SetHeight(24)
    edit:SetAutoFocus(false)
    if numeric then edit:SetNumeric(true) end
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() UI:RefreshSettings() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() UI:CommitSettings() end)
    edit:SetScript("OnEditFocusLost", function() UI:CommitSettings() end)
    return edit
end

local function Truncate(text, length)
    text = tostring(text or "")
    if string.len(text) <= length then return text end
    return string.sub(text, 1, math.max(1, length - 2)) .. ".."
end

local function LevelColor(level)
    level = tonumber(level) or 0
    if level >= 59 then return "|cffff4444" end
    if level >= 51 then return "|cffffaa33" end
    if level >= 10 then return "|cff55ff77" end
    return "|cffaaaaaa"
end

function UI:CreateMainFrame()
    local frame = CreateFrame("Frame", "ManastormRecruiterMainFrame", UIParent)
    frame:SetWidth(1200)
    frame:SetHeight(680)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    SetBackdrop(frame)

    local title = CreateLabel(frame, "Manastorm Recruiter", true, COLORS.gold)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -14)

    local version = CreateLabel(frame, "v" .. MSR.VERSION, false, COLORS.muted)
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local status = CreateLabel(frame, "", false, COLORS.green)
    status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -20)
    status:SetJustifyH("RIGHT")
    self.statusText = status

    self.frame = frame
end

function UI:ApplyWindowScale()
    if not self.frame then return end
    local screenWidth = UIParent.GetWidth and UIParent:GetWidth() or 1200
    local screenHeight = UIParent.GetHeight and UIParent:GetHeight() or 680
    local frameHeight = self.currentFrameHeight or 680
    local fitScale = math.min(1, math.max(0.55, (screenWidth - 24) / 1200), math.max(0.55, (screenHeight - 24) / frameHeight))
    local compactMultiplier = MSR.db and MSR.db.settings.compactMode and 0.78 or 1
    self.frame:SetScale(fitScale * compactMultiplier)
    if self.compactButton then
        self.compactButton:SetText(MSR.db.settings.compactMode and "Full size" or "Compact")
    end
end

function UI:GetDesiredFrameHeight(phase, settingsOpen)
    settingsOpen = settingsOpen == true
    return settingsOpen and 680 or 610
end

function UI:ToggleCompactMode()
    MSR.db.settings.compactMode = not (MSR.db.settings.compactMode == true)
    self:ApplyWindowScale()
end

function UI:CreatePhaseBar()
    self.phaseButtons = {}
    local settings = CreateButton(self.frame, "Settings", 92, 23)
    settings:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -338, -10)
    settings:SetScript("OnClick", function()
        UI.settingsOpen = not UI.settingsOpen
        UI:ApplyPhaseVisibility()
    end)
    self.settingsButton = settings

    local compact = CreateButton(self.frame, "Compact", 92, 23)
    compact:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -238, -10)
    compact:SetScript("OnClick", function() UI:ToggleCompactMode() end)
    self.compactButton = compact
end

function UI:GetSuggestedPhase()
    if MSR.runtime and MSR.runtime.rebuild or MSR:HasRebuildRecovery() then return "rebuild" end
    if MSR:IsInManastorm() then return "manastorm" end
    local grouped = (GetNumRaidMembers and GetNumRaidMembers() > 0)
        or (GetNumPartyMembers and GetNumPartyMembers() > 0)
    return grouped and "raid" or "recruitment"
end

function UI:ApplyPhaseVisibility()
    if not self.frame then return end
    local phase = self.phase or "recruitment"
    local settingsOpen = self.settingsOpen == true
    self.currentFrameHeight = self:GetDesiredFrameHeight(phase, settingsOpen)
    self.frame:SetHeight(self.currentFrameHeight)
    if self.settingsPanel then
        if settingsOpen then
            self.settingsPanel:SetAlpha(1)
            self.settingsPanel:Show()
        else
            self.settingsPanel:SetAlpha(0)
            self.settingsPanel:Hide()
        end
    end
    if self.settingsButton then self.settingsButton:SetText(settingsOpen and "Close setup" or "Settings") end
    for _, widget in ipairs(self.recruitmentWidgets or {}) do
        widget:Show()
    end
    for _, widget in ipairs(self.recruitmentInlineButtons or {}) do widget:Hide() end
    if self.recruitmentPreviewLabel then
        local previewY = settingsOpen and -122 or -52
        local textY = settingsOpen and -141 or -71
        local actionY = settingsOpen and -164 or -94
        self.recruitmentPreviewLabel:ClearAllPoints()
        self.recruitmentPreviewLabel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, previewY)
        self.previewText:ClearAllPoints()
        self.previewText:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, textY)
        self.previewText:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -18, textY)
        self.recruitmentHint:ClearAllPoints()
        self.recruitmentHint:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, actionY)
    end
    local panelY = settingsOpen and -198 or -128
    if self.applicantsPanel then
        self.applicantsPanel:ClearAllPoints()
        self.applicantsPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, panelY)
        self.applicantsPanel:Show()
    end
    if self.groupsPanel then
        self.groupsPanel:ClearAllPoints()
        self.groupsPanel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 502, panelY)
        self.groupsPanel:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -14, panelY)
        self.groupsPanel:Show()
    end
    if self.rebuildPanel then
        self.rebuildPanel:Hide()
    end
    self:ApplyWindowScale()
end

function UI:UpdateAutomaticPhase()
    self.phase = self:GetSuggestedPhase()
    self:ApplyPhaseVisibility()
end

local function Atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

function UI:UpdateMinimapButtonPosition()
    if not self.minimapButton or not Minimap then return end
    local angle = tonumber(MSR.db.settings.minimapAngle) or 225
    local radians = math.rad(angle)
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * 80, math.sin(radians) * 80)
end

function UI:CreateMinimapButton()
    if not Minimap then return end
    local button = CreateFrame("Button", "ManastormRecruiterMinimapButton", Minimap)
    button:SetWidth(32)
    button:SetHeight(32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetWidth(22)
    background:SetHeight(22)
    background:SetPoint("CENTER", button, "CENTER", 0, 0)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(54)
    border:SetHeight(54)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints(button)

    button:SetScript("OnClick", function() UI:Toggle() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Manastorm Recruiter", 1, 0.78, 0.22)
        GameTooltip:AddLine("Left-click to show or hide the window.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this button.", 0.65, 0.7, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local minimapX, minimapY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cursorX, cursorY = cursorX / scale, cursorY / scale
            MSR.db.settings.minimapAngle = math.deg(Atan2(cursorY - minimapY, cursorX - minimapX))
            UI:UpdateMinimapButtonPosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    self.minimapButton = button
    self:UpdateMinimapButtonPosition()
end

function UI:CreateMessageTemplatesFrame()
    local frame = CreateFrame("Frame", "ManastormRecruiterMessageTemplatesFrame", UIParent)
    frame:SetWidth(560)
    frame:SetHeight(450)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    SetBackdrop(frame)

    local title = CreateLabel(frame, "Message templates", true, COLORS.gold)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -14)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local help = CreateLabel(frame, "Choose a message to edit. An asterisk (*) marks a customized message.", false, COLORS.muted)
    help:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -43)
    help:SetWidth(524)
    help:SetJustifyH("LEFT")

    self.messageButtons = {}
    for _, section in ipairs(MESSAGE_SECTIONS) do
        local sectionLabel = CreateLabel(frame, section.title, false, COLORS.gold)
        sectionLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", section.x, section.y)
        for index, key in ipairs(section.keys) do
            local definition = GetMessageDefinition(key)
            local messageKey = key
            local messageDefinition = definition
            local button = CreateButton(frame, messageDefinition and messageDefinition.label or messageKey, 250, 25)
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", section.x, section.y - 23 - ((index - 1) * 29))
            button:SetScript("OnClick", function() UI:ShowMessageTemplateEditor(messageKey) end)
            button:SetScript("OnEnter", function(messageButton)
                GameTooltip:SetOwner(messageButton, "ANCHOR_RIGHT")
                GameTooltip:SetText(messageDefinition and messageDefinition.label or messageKey, 1, 0.82, 0.25)
                GameTooltip:AddLine(MSR:GetMessageTemplate(messageKey), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            self.messageButtons[messageKey] = button
        end
    end

    self.messageTemplatesFrame = frame
    frame:Hide()

    local editor = CreateFrame("Frame", "ManastormRecruiterMessageEditorFrame", UIParent)
    editor:SetWidth(720)
    editor:SetHeight(370)
    editor:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    editor:SetFrameStrata("FULLSCREEN_DIALOG")
    editor:SetClampedToScreen(true)
    editor:EnableMouse(true)
    SetBackdrop(editor)

    local editorTitle = CreateLabel(editor, "Edit message", true, COLORS.gold)
    editorTitle:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -14)
    self.messageEditorTitle = editorTitle

    local editorClose = CreateFrame("Button", nil, editor, "UIPanelCloseButton")
    editorClose:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -4, -4)
    editorClose:SetScript("OnClick", function() UI:CloseMessageTemplateEditor() end)

    local editorHelp = CreateLabel(editor,
        "Available placeholders: {needed}, {tankNeeded}, {healNeeded}, {dpsNeeded}, {auraNeeded}, {tank}, {tankMax}, {heal}, {healMax}, {dps}, {dpsMax}, {aura}, {auraMax}, {total}, {totalMax}, {role}, {rolePlural}, {roles}, {player}, {level}, {seconds}, {auraPlayers}, {missingAura}, {reservation}, {status}",
        false, COLORS.muted)
    editorHelp:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -48)
    editorHelp:SetWidth(684)
    editorHelp:SetHeight(54)
    editorHelp:SetJustifyH("LEFT")

    local editBorder = CreateFrame("Frame", nil, editor)
    editBorder:SetPoint("TOPLEFT", editor, "TOPLEFT", 18, -112)
    editBorder:SetWidth(684)
    editBorder:SetHeight(170)
    SetBackdrop(editBorder, COLORS.inset, COLORS.border)

    local edit = CreateFrame("EditBox", nil, editBorder)
    edit:SetPoint("TOPLEFT", editBorder, "TOPLEFT", 10, -10)
    edit:SetWidth(664)
    edit:SetHeight(150)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontNormal)
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    self.messageEditorInput = edit

    local defaultButton = CreateButton(editor, "Use default", 112, 25)
    defaultButton:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 18, 16)
    defaultButton:SetScript("OnClick", function()
        local key = UI.messageEditorKey
        if key then edit:SetText(MSR.MESSAGE_DEFAULTS[key] or "") end
    end)

    local cancelButton = CreateButton(editor, "Cancel", 90, 25)
    cancelButton:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -116, 16)
    cancelButton:SetScript("OnClick", function() UI:CloseMessageTemplateEditor() end)

    local saveButton = CreateButton(editor, "Save", 90, 25)
    saveButton:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -18, 16)
    saveButton:SetScript("OnClick", function() UI:CommitMessageTemplate() end)

    self.messageEditorFrame = editor
    editor:Hide()
end

function UI:ShowMessageTemplates()
    self:RefreshMessageTemplateButtons()
    self.messageTemplatesFrame:Show()
end

function UI:RefreshMessageTemplateButtons()
    for _, definition in ipairs(MESSAGE_FIELDS) do
        local button = self.messageButtons and self.messageButtons[definition.key]
        if button then
            local current = MSR:GetMessageTemplate(definition.key)
            local default = tostring(MSR.MESSAGE_DEFAULTS[definition.key] or "")
            button:SetText(definition.label .. (current ~= default and " *" or ""))
        end
    end
end

function UI:ShowMessageTemplateEditor(key)
    local definition = GetMessageDefinition(key)
    if not definition then return end
    self.messageEditorKey = key
    self.messageEditorTitle:SetText(definition.label)
    self.messageEditorInput:SetText(MSR:GetMessageTemplate(key))
    self.messageEditorInput:ClearFocus()
    self.messageTemplatesFrame:Hide()
    self.messageEditorFrame:Show()
end

function UI:CloseMessageTemplateEditor()
    self.messageEditorInput:ClearFocus()
    self.messageEditorFrame:Hide()
    self.messageEditorKey = nil
    self:RefreshMessageTemplateButtons()
    self.messageTemplatesFrame:Show()
end

function UI:CommitMessageTemplate()
    local key = self.messageEditorKey
    if not key then return end
    MSR.db.settings.messages[key] = self.messageEditorInput:GetText()
    self.messageEditorInput:ClearFocus()
    self.messageEditorFrame:Hide()
    self.messageEditorKey = nil
    self:RefreshMessageTemplateButtons()
    self.messageTemplatesFrame:Show()
    self:Refresh()
end

function UI:CreateSettingsPanel()
    local panel = CreateFrame("Frame", nil, self.frame)
    panel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -44)
    panel:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -14, -44)
    panel:SetHeight(68)
    SetBackdrop(panel, COLORS.inset)
    self.settingsPanel = panel

    local channelLabel = CreateLabel(panel, "Channel (name or number)", false, COLORS.muted)
    channelLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -8)
    local channel = CreateEditBox(panel, 132, false)
    channel:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", 4, -2)
    self.channelEdit = channel

    local selfLabel = CreateLabel(panel, "Your slot", false, COLORS.muted)
    selfLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 170, -8)
    local selfRole = CreateButton(panel, "DPS", 68, 23)
    selfRole:SetPoint("TOPLEFT", selfLabel, "BOTTOMLEFT", 0, -2)
    selfRole:SetScript("OnClick", function()
        MSR.char.selfRole = MSR.char.selfRole == "TANK" and "HEAL" or MSR.char.selfRole == "HEAL" and "DPS" or "TANK"
        MSR.runtime.groupOptimization = nil
        MSR:BuildRoster()
        UI:Refresh()
    end)
    self.selfRoleButton = selfRole

    local selfAura = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    selfAura:SetPoint("LEFT", selfRole, "RIGHT", 6, 0)
    local selfAuraText = CreateLabel(panel, "Aura", false, COLORS.muted)
    selfAuraText:SetPoint("LEFT", selfAura, "RIGHT", -2, 0)
    selfAura:SetScript("OnClick", function(button)
        MSR.char.selfAura = button:GetChecked() == 1
        MSR.runtime.groupOptimization = nil
        MSR:BuildRoster()
        UI:Refresh()
    end)
    self.selfAuraCheck = selfAura

    local slotX = 300
    local slotDefinitions = {
        { key = "tank", label = "Tanks", width = 44 },
        { key = "heal", label = "Heals", width = 44 },
        { key = "dps", label = "DPS", width = 44 },
        { key = "aura", label = "Auras", width = 44 },
    }
    self.slotEdits = {}
    for _, definition in ipairs(slotDefinitions) do
        local label = CreateLabel(panel, definition.label, false, COLORS.muted)
        label:SetPoint("TOPLEFT", panel, "TOPLEFT", slotX, -8)
        local edit = CreateEditBox(panel, definition.width, true)
        edit:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -2)
        self.slotEdits[definition.key] = edit
        slotX = slotX + 66
    end

    local intervalLabel = CreateLabel(panel, "Post interval", false, COLORS.muted)
    intervalLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 575, -8)
    local interval = CreateEditBox(panel, 52, true)
    interval:SetPoint("TOPLEFT", intervalLabel, "BOTTOMLEFT", 4, -2)
    self.intervalEdit = interval
    local seconds = CreateLabel(panel, "sec", false, COLORS.muted)
    seconds:SetPoint("LEFT", interval, "RIGHT", 4, 0)

    local autoPost = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    autoPost:SetPoint("TOPLEFT", panel, "TOPLEFT", 700, -12)
    local autoPostText = CreateLabel(panel, "Auto post", false, COLORS.muted)
    autoPostText:SetPoint("LEFT", autoPost, "RIGHT", -1, 0)
    autoPost:SetScript("OnClick", function(button)
        MSR.db.settings.autoPost = button:GetChecked() == 1
        if MSR.db.settings.autoPost then MSR.char.session.listening = true end
        UI:Refresh()
    end)
    self.autoPostCheck = autoPost

    local autoReply = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    autoReply:SetPoint("TOPLEFT", panel, "TOPLEFT", 810, -12)
    local autoReplyText = CreateLabel(panel, "Auto reply", false, COLORS.muted)
    autoReplyText:SetPoint("LEFT", autoReply, "RIGHT", -1, 0)
    autoReply:SetScript("OnClick", function(button)
        MSR.db.settings.autoReply = button:GetChecked() == 1
    end)
    self.autoReplyCheck = autoReply

    local auraReservation = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    auraReservation:SetPoint("TOPLEFT", panel, "TOPLEFT", 680, -38)
    local auraReservationText = CreateLabel(panel, "Aura reserve", false, COLORS.muted)
    auraReservationText:SetPoint("LEFT", auraReservation, "RIGHT", -1, 0)
    auraReservation:SetScript("OnClick", function(button)
        MSR.db.settings.auraReservation.enabled = button:GetChecked() == 1
        UI:Refresh()
    end)
    self.auraReservationCheck = auraReservation

    local roleLabel = CreateLabel(panel, "Roles", false, COLORS.muted)
    roleLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 800, -43)
    self.auraReservationRoleButtons = {}
    local roleX = 838
    for _, definition in ipairs({ { key = "tank", label = "T" }, { key = "heal", label = "H" }, { key = "dps", label = "D" } }) do
        local roleKey = definition.key
        local roleText = definition.label
        local roleButton = CreateButton(panel, roleText, 31, 21)
        roleButton:SetPoint("TOPLEFT", panel, "TOPLEFT", roleX, -39)
        roleButton:SetScript("OnClick", function()
            local roles = MSR.db.settings.auraReservation.roles
            roles[roleKey] = not roles[roleKey]
            UI:Refresh()
        end)
        roleButton.roleKey = roleKey
        roleButton.roleLabel = roleText
        self.auraReservationRoleButtons[roleKey] = roleButton
        roleX = roleX + 34
    end

    local editMessages = CreateButton(panel, "Edit messages", 126, 25)
    editMessages:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    editMessages:SetScript("OnClick", function() UI:ShowMessageTemplates() end)
    self.settingsEditMessagesButton = editMessages
    panel:SetAlpha(0)
    panel:Hide()
end

function UI:CreateRecruitmentPanel()
    local previewLabel = CreateLabel(self.frame, "Recruitment message", false, COLORS.muted)
    previewLabel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -122)

    local preview = CreateLabel(self.frame, "", false, { 1, 1, 1, 1 })
    preview:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -141)
    preview:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -18, -141)
    preview:SetJustifyH("LEFT")
    self.previewText = preview
    self.recruitmentPreviewLabel = previewLabel

    local post = CreateButton(self.frame, "Post recruitment", 126, 25)
    post:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 18, -164)
    post:SetScript("OnClick", function() MSR:PostRecruitment(false) end)
    self.postButton = post

    local listen = CreateButton(self.frame, "Listening: OFF", 116, 25)
    listen:SetPoint("LEFT", post, "RIGHT", 8, 0)
    listen:SetScript("OnClick", function()
        MSR.char.session.listening = not MSR.char.session.listening
        UI:Refresh()
    end)
    self.listenButton = listen

    local hint = CreateLabel(self.frame, "Accepted whisper format: Tank/Heal/DPS + Aura yes/no + Level", false, COLORS.muted)
    hint:SetPoint("LEFT", listen, "RIGHT", 12, 0)

    local messages = CreateButton(self.frame, "Edit messages", 108, 25)
    messages:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -18, -164)
    messages:SetScript("OnClick", function() UI:ShowMessageTemplates() end)
    self.recruitmentHint = hint
    self.editMessagesButton = messages
    self.recruitmentWidgets = { previewLabel, preview, hint }
    self.recruitmentInlineButtons = { post, listen, messages }
end

function UI:FreezeApplicantOrder()
    if self.frozenApplicantOrder and GetTime() < (self.frozenApplicantOrderUntil or 0) then
        self.frozenApplicantOrderUntil = GetTime() + 5
        return
    end
    local applicants = MSR:GetApplicantsForDisplay(self.applicantView)
    self.frozenApplicantOrder = {}
    for index, applicant in ipairs(applicants) do self.frozenApplicantOrder[applicant.key] = index end
    self.frozenApplicantOrderUntil = GetTime() + 5
end

function UI:ApplyFrozenApplicantOrder(applicants)
    if not self.frozenApplicantOrder or GetTime() >= (self.frozenApplicantOrderUntil or 0) then
        self.frozenApplicantOrder = nil
        return applicants
    end
    table.sort(applicants, function(left, right)
        local leftIndex = self.frozenApplicantOrder[left.key] or 9999
        local rightIndex = self.frozenApplicantOrder[right.key] or 9999
        if leftIndex ~= rightIndex then return leftIndex < rightIndex end
        return tostring(left.name or "") < tostring(right.name or "")
    end)
    return applicants
end

function UI:CreateApplicantRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(460)
    row:SetHeight(31)
    row.normalBackground = index % 2 == 0 and { 0.055, 0.065, 0.09, 0.92 } or { 0.075, 0.085, 0.11, 0.92 }
    row.normalBorder = { 0.18, 0.22, 0.29, 1 }
    SetBackdrop(row, row.normalBackground, row.normalBorder)

    local name = CreateLabel(row, "", false, { 1, 1, 1, 1 })
    name:SetPoint("LEFT", row, "LEFT", 7, 0)
    name:SetWidth(80)
    row.nameText = name

    local level = CreateLabel(row, "", false, COLORS.muted)
    level:SetPoint("LEFT", row, "LEFT", 91, 0)
    level:SetWidth(40)
    row.levelText = level

    local role = CreateButton(row, "DPS", 58, 21)
    role:SetPoint("LEFT", row, "LEFT", 136, 0)
    role:SetScript("OnClick", function(button)
        UI:FreezeApplicantOrder()
        MSR:CycleApplicantRole(button.applicant)
    end)
    row.roleButton = role

    local aura = CreateButton(row, "A?", 40, 21)
    aura:SetPoint("LEFT", row, "LEFT", 199, 0)
    aura:SetScript("OnClick", function(button)
        UI:FreezeApplicantOrder()
        MSR:ToggleApplicantAura(button.applicant)
    end)
    row.auraButton = aura

    local status = CreateLabel(row, "", false, COLORS.muted)
    status:SetPoint("LEFT", row, "LEFT", 244, 0)
    status:SetWidth(55)
    row.statusText = status

    local invite = CreateButton(row, "Invite", 53, 21)
    invite:SetPoint("LEFT", row, "LEFT", 303, 0)
    invite:SetScript("OnClick", function(button) MSR:InviteApplicant(button.applicant) end)
    row.inviteButton = invite

    local reserve = CreateButton(row, "Reserve", 63, 21)
    reserve:SetPoint("LEFT", row, "LEFT", 359, 0)
    reserve:SetScript("OnClick", function(button)
        local applicant = button.applicant
        UI:FreezeApplicantOrder()
        if applicant.status == "Invited" then
            MSR:ReleaseApplicantSlot(applicant, false)
        else
            MSR:SetApplicantStatus(applicant, applicant.status == "Reserve" and "New" or "Reserve")
        end
    end)
    row.reserveButton = reserve

    local reject = CreateButton(row, "X", 27, 21)
    reject:SetPoint("LEFT", row, "LEFT", 426, 0)
    reject:SetScript("OnClick", function(button)
        UI:FreezeApplicantOrder()
        MSR:SetApplicantStatus(button.applicant, "Rejected")
    end)
    row.rejectButton = reject

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.applicant then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.applicant.name, 1, 0.82, 0.25)
        local applicantLevel = tonumber(self.applicant.level)
        GameTooltip:AddLine(applicantLevel and ("Level " .. applicantLevel) or "Level unknown", 0.75, 0.8, 0.9)
        if self.capacityReason then GameTooltip:AddLine(self.capacityReason, 1, 0.25, 0.25, true) end
        local history = self.applicant.messageHistory
        if type(history) == "table" and #history > 0 then
            GameTooltip:AddLine("Recent whispers:", 0.55, 0.8, 1, true)
            local first = math.max(1, #history - 4)
            for index = first, #history do
                GameTooltip:AddLine(tostring(history[index].message or ""), 1, 1, 1, true)
            end
        else
            GameTooltip:AddLine(self.applicant.message ~= "" and self.applicant.message or "No whisper text stored.", 1, 1, 1, true)
        end
        if self.applicant.needsReview then GameTooltip:AddLine("Role or Aura needs manual review.", 1, 0.25, 0.25, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function UI:CreateApplicantsPanel()
    local panel = CreateFrame("Frame", nil, self.frame)
    panel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -198)
    panel:SetWidth(480)
    panel:SetHeight(418)
    SetBackdrop(panel, COLORS.inset)
    self.applicantsPanel = panel

    local title = CreateLabel(panel, "Waiting players", true, COLORS.gold)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    self.applicantsTitle = title

    local waitingTab = CreateButton(panel, "Waiting 0", 88, 22)
    waitingTab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -100, -8)
    waitingTab:SetScript("OnClick", function()
        UI.applicantView = "waiting"
        UI.applicantOffset = 0
        UI:RefreshApplicants()
    end)
    self.waitingApplicantsTab = waitingTab

    local joinedTab = CreateButton(panel, "In raid 0", 84, 22)
    joinedTab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -8)
    joinedTab:SetScript("OnClick", function()
        UI.applicantView = "joined"
        UI.applicantOffset = 0
        UI:RefreshApplicants()
    end)
    self.joinedApplicantsTab = joinedTab

    for _, column in ipairs({
        { text = "Player", x = 11 },
        { text = "Lv", x = 100 },
        { text = "Role", x = 145 },
        { text = "Aura", x = 207 },
        { text = "Status", x = 254 },
    }) do
        local label = CreateLabel(panel, column.text, false, COLORS.muted)
        label:SetPoint("TOPLEFT", panel, "TOPLEFT", column.x, -34)
    end

    self.applicantRows = {}
    for index = 1, self.applicantPageSize do
        local row = self:CreateApplicantRow(panel, index)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 9, -52 - ((index - 1) * 33))
        self.applicantRows[index] = row
    end

    local previous = CreateButton(panel, "<", 32, 22)
    previous:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 8)
    previous:SetScript("OnClick", function()
        UI.applicantOffset = math.max(0, UI.applicantOffset - UI.applicantPageSize)
        UI:RefreshApplicants()
    end)
    self.previousApplicants = previous

    local page = CreateLabel(panel, "", false, COLORS.muted)
    page:SetPoint("LEFT", previous, "RIGHT", 8, 0)
    self.applicantPageText = page

    local nextButton = CreateButton(panel, ">", 32, 22)
    nextButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    nextButton:SetScript("OnClick", function()
        local count = #MSR:GetApplicantsForDisplay(UI.applicantView)
        if UI.applicantOffset + UI.applicantPageSize < count then
            UI.applicantOffset = UI.applicantOffset + UI.applicantPageSize
            UI:RefreshApplicants()
        end
    end)
    self.nextApplicants = nextButton

    local reset = CreateButton(panel, "Reset session", 104, 22)
    reset:SetPoint("BOTTOM", panel, "BOTTOM", 0, 8)
    reset:SetScript("OnClick", function() UI:ShowResetConfirmation() end)
end

function UI:CreateGroupCard(parent, group)
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(220)
    card:SetHeight(176)
    SetBackdrop(card, { 0.045, 0.055, 0.075, 0.80 }, { 0.20, 0.27, 0.36, 1 })

    local title = CreateLabel(card, "Group " .. group, true, COLORS.gold)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 7, -5)
    card.title = title

    local aura = CreateLabel(card, "", false, COLORS.red)
    aura:SetPoint("TOPRIGHT", card, "TOPRIGHT", -7, -8)
    aura:SetJustifyH("RIGHT")
    card.aura = aura

    card.rows = {}
    for index = 1, 5 do
        local row = CreateFrame("Frame", nil, card)
        row:SetWidth(208)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -34 - ((index - 1) * 27))

        local roleIcon = row:CreateTexture(nil, "ARTWORK")
        roleIcon:SetWidth(16)
        roleIcon:SetHeight(16)
        roleIcon:SetPoint("LEFT", row, "LEFT", 1, 0)
        roleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.roleIcon = roleIcon

        local name = CreateLabel(row, "Empty", false, COLORS.muted)
        name:SetPoint("LEFT", row, "LEFT", 19, 0)
        name:SetWidth(95)
        row.nameText = name

        local level = CreateLabel(row, "", false, COLORS.muted)
        level:SetPoint("LEFT", row, "LEFT", 116, 0)
        level:SetWidth(38)
        level:SetJustifyH("RIGHT")
        row.levelText = level

        local auraText = CreateLabel(row, "", false, COLORS.green)
        auraText:SetPoint("LEFT", row, "LEFT", 156, 0)
        auraText:SetWidth(20)
        auraText:SetJustifyH("CENTER")
        row.auraText = auraText

        local ready = CreateLabel(row, "", false, COLORS.muted)
        ready:SetPoint("LEFT", row, "LEFT", 179, 0)
        ready:SetWidth(12)
        ready:SetJustifyH("CENTER")
        row.readyText = ready

        local kick = CreateButton(row, "X", 16, 19)
        kick:SetPoint("RIGHT", row, "RIGHT", -1, 0)
        kick:SetScript("OnClick", function(button) MSR:KickRosterMember(button.member) end)
        kick:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            if button.member then
                GameTooltip:SetText("Remove " .. tostring(button.member.name), 1, 0.35, 0.35)
                local allowed, reason = MSR:CanKickRosterMember(button.member)
                if not allowed then GameTooltip:AddLine(reason, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        kick:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.kickButton = kick
        card.rows[index] = row
    end
    return card
end

function UI:CreateGroupsPanel()
    local panel = CreateFrame("Frame", nil, self.frame)
    panel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 502, -198)
    panel:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -14, -198)
    panel:SetHeight(418)
    SetBackdrop(panel, COLORS.inset)
    self.groupsPanel = panel

    local title = CreateLabel(panel, "Raid groups", true, COLORS.gold)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)

    local counts = CreateLabel(panel, "", false, { 1, 1, 1, 1 })
    counts:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -14)
    counts:SetJustifyH("RIGHT")
    self.countsText = counts

    self.groupCards = {}
    for group = 1, 3 do
        local card = self:CreateGroupCard(panel, group)
        card:SetPoint("TOPLEFT", panel, "TOPLEFT", 10 + ((group - 1) * 223), -38)
        self.groupCards[group] = card
    end

    local manastormStatus = CreateLabel(panel, "Ready Check is optional. Manastorm Level 1 can be started at any time.", false, COLORS.muted)
    manastormStatus:SetPoint("TOPLEFT", panel, "TOPLEFT", 11, -220)
    manastormStatus:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -11, -220)
    manastormStatus:SetHeight(40)
    self.manastormStatusText = manastormStatus

    local postRoster = CreateButton(panel, "Post roster", 112, 25)
    postRoster:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -265)
    postRoster:SetScript("OnClick", function() MSR:PostRaidRosterSummary() end)
    self.postRosterButton = postRoster

    local disband = CreateButton(panel, "Disband raid", 118, 25)
    disband:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -265)
    disband:SetScript("OnClick", function() UI:ShowDisbandConfirmation() end)
    self.disbandButton = disband

    local levelStatus = CreateButton(panel, "Post & Leave", 128, 25)
    levelStatus:SetPoint("TOP", panel, "TOP", 0, -265)
    levelStatus:SetScript("OnClick", function() MSR:PostLevelStatus() end)
    levelStatus:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Post & Leave", 1, 0.82, 0.25)
        GameTooltip:AddLine("Posts the level-specific roster message, leaves Manastorm when necessary, then leaves the group.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    levelStatus:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.levelStatusButton = levelStatus
    self.level60StatusButton = levelStatus

    local chatTitle = CreateLabel(panel, "Group chat", false, COLORS.gold)
    chatTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 11, -294)
    self.groupChatTitle = chatTitle

    local chat = CreateFrame("ScrollingMessageFrame", nil, panel)
    chat:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -312)
    chat:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -38, -312)
    chat:SetHeight(64)
    chat:SetFontObject(GameFontNormalSmall or GameFontNormal)
    chat:SetJustifyH("LEFT")
    chat:SetFading(false)
    chat:SetMaxLines(100)
    self.groupChatMessages = chat

    local up = CreateButton(panel, "^", 22, 20)
    up:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -311)
    up:SetScript("OnClick", function() chat:ScrollUp() end)
    local down = CreateButton(panel, "v", 22, 20)
    down:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 42)
    down:SetScript("OnClick", function() chat:ScrollDown() end)

    local chatInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    chatInput:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 8)
    chatInput:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -70, 8)
    chatInput:SetHeight(23)
    chatInput:SetAutoFocus(false)
    chatInput:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    chatInput:SetScript("OnEnterPressed", function(box)
        if MSR:SendGroupChat(box:GetText()) then box:SetText("") end
        box:ClearFocus()
    end)
    self.groupChatInput = chatInput

    local send = CreateButton(panel, "Send", 52, 23)
    send:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    send:SetScript("OnClick", function()
        if MSR:SendGroupChat(chatInput:GetText()) then chatInput:SetText("") end
        chatInput:ClearFocus()
    end)
    self.groupChatSendButton = send
end

function UI:CreateRebuildPanel()
    local panel = CreateFrame("Frame", nil, self.frame)
    panel:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -78)
    panel:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -14, -78)
    panel:SetHeight(520)
    SetBackdrop(panel, COLORS.inset)
    self.rebuildPanel = panel

    local title = CreateLabel(panel, "Raid rebuild", true, COLORS.gold)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)

    local status = CreateLabel(panel, "", true, { 1, 1, 1, 1 })
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -54)
    status:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -54)
    status:SetJustifyH("LEFT")
    self.rebuildPhaseStatus = status

    local help = CreateLabel(panel,
        "This guided flow keeps the saved roster through /reload and exposes only the action required for the current step.",
        false, COLORS.muted)
    help:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -84)
    help:SetWidth(760)
    help:SetJustifyH("LEFT")

    self.rebuildStepLabels = {}
    local stepNames = {
        "Roster snapshot saved",
        "Remove former raid members",
        "Leave Manastorm",
        "Send reinvites",
        "Wait for players to return",
    }
    for index, stepName in ipairs(stepNames) do
        local label = CreateLabel(panel, stepName, false, COLORS.muted)
        label:SetPoint("TOPLEFT", panel, "TOPLEFT", 30, -132 - ((index - 1) * 42))
        self.rebuildStepLabels[index] = label
    end

    local roster = CreateLabel(panel, "", false, COLORS.muted)
    roster:SetPoint("TOPLEFT", panel, "TOPLEFT", 420, -132)
    roster:SetWidth(700)
    roster:SetHeight(150)
    roster:SetJustifyH("LEFT")
    self.rebuildRosterSummary = roster

    local note = CreateLabel(panel, "", false, COLORS.gold)
    note:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 24)
    note:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 24)
    note:SetJustifyH("LEFT")
    self.rebuildRecoveryNote = note
    panel:Hide()
end

function UI:RefreshRebuildPanel()
    if not self.rebuildPanel then return end
    local rebuild = MSR.runtime and MSR.runtime.rebuild
    local recovery = MSR.char and MSR.char.session and MSR.char.session.rebuildRecovery
    local status = MSR:GetRebuildStatus()
    if rebuild then
        self.rebuildPhaseStatus:SetText("|cffffd65a" .. (status ~= "" and status or "Rebuild active") .. "|r")
    elseif MSR:HasRebuildRecovery() then
        self.rebuildPhaseStatus:SetText("|cffffd65aSaved rebuild recovery is ready.|r")
    else
        self.rebuildPhaseStatus:SetText("|cff777f8fNo rebuild is active.|r")
    end

    local phase = rebuild and rebuild.phase or "recovery"
    local activeStep = 1
    if phase == "countdown" or phase == "manual-remove-all" or phase == "waiting-bulk-remove"
        or phase == "removing" or phase == "waiting-remove" or phase == "manual-remove" then activeStep = 2
    elseif phase == "waiting-manastorm-exit" or phase == "manual-leave-manastorm" then activeStep = 3
    elseif phase == "waiting-empty" or phase == "inviting" or phase == "manual-invite" then activeStep = 4
    elseif phase == "waiting-return" then activeStep = 5 end
    local stepNames = {
        "Roster snapshot saved",
        "Remove former raid members",
        "Leave Manastorm",
        "Send reinvites",
        "Wait for players to return",
    }
    for index, label in ipairs(self.rebuildStepLabels) do
        local prefix = index < activeStep and "|cff55ff88[done]|r "
            or index == activeStep and "|cffffd65a[current]|r "
            or "|cff777f8f[next]|r "
        label:SetText(prefix .. stepNames[index])
    end

    local removal = rebuild and rebuild.removalSnapshot or recovery and recovery.removalSnapshot or {}
    local reinvite = rebuild and rebuild.reinviteSnapshot or recovery and recovery.reinviteSnapshot or {}
    local excluded = rebuild and rebuild.excluded or recovery and recovery.excluded or {}
    self.rebuildRosterSummary:SetText(string.format(
        "Saved roster\n\nPlayers to remove: %d\nPlayers to reinvite: %d\nLevel 60+ excluded: %d\n\nProgress is checkpointed automatically.",
        #removal, #reinvite, #excluded
    ))
    self.rebuildRecoveryNote:SetText(rebuild and "Do not /reload unless necessary; recovery is available if it happens."
        or MSR:HasRebuildRecovery() and "Choose Resume in the recovery dialog to continue from this checkpoint."
        or "")
end

function UI:FormatGroupChatEntry(entry)
    local color = entry.channel == "Warning" and "|cffff5555"
        or entry.channel == "Raid" and "|cffff7fff"
        or "|cffaaaaff"
    local timestamp = entry.timestamp ~= "" and (entry.timestamp .. " ") or ""
    return string.format("|cff777f8f%s|r%s[%s] %s:|r %s", timestamp, color, entry.channel, entry.sender, entry.message)
end

function UI:AddGroupChatMessage(entry)
    if not self.groupChatMessages then return end
    self.groupChatMessages:AddMessage(self:FormatGroupChatEntry(entry))
    self.groupChatMessages:ScrollToBottom()
end

function UI:RefreshGroupChat()
    if not self.groupChatMessages then return end
    self.groupChatMessages:Clear()
    for _, entry in ipairs(MSR.runtime.groupChat or {}) do self:AddGroupChatMessage(entry) end
    self:RefreshGroupChatState()
end

function UI:RefreshGroupChatState()
    if not self.groupChatMessages then return end
    local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
    local inParty = GetNumPartyMembers and GetNumPartyMembers() > 0
    self.groupChatTitle:SetText("Group chat - " .. (inRaid and "Raid" or inParty and "Party" or "Not grouped"))
    if inRaid or inParty then
        self.groupChatInput:Enable()
        self.groupChatSendButton:Enable()
    else
        self.groupChatInput:Disable()
        self.groupChatSendButton:Disable()
    end
end

function UI:CreateActionBar()
    local optimize = CreateButton(self.frame, "Optimize groups", 126, 27)
    optimize:SetScript("OnClick", function() MSR:OptimizeGroups() end)
    optimize.actionWidth = 126
    self.optimizeButton = optimize

    local rebuild = CreateButton(self.frame, "Rebuild raid", 112, 27)
    rebuild:SetScript("OnClick", function() UI:ShowRebuildConfirmation() end)
    rebuild.actionWidth = 112
    self.rebuildButton = rebuild

    local readyCheck = CreateButton(self.frame, "Ready Check", 108, 27)
    readyCheck:SetScript("OnClick", function() MSR:StartReadyCheck() end)
    readyCheck.actionWidth = 108
    self.readyCheckButton = readyCheck

    local startManastorm = CreateButton(self.frame, "Start MS Lv 1", 112, 27)
    startManastorm:SetScript("OnClick", function() MSR:StartManastormLevelOne() end)
    startManastorm.actionWidth = 112
    self.startManastormButton = startManastorm

    local cancel = CreateButton(self.frame, "Cancel rebuild", 116, 27)
    cancel:SetScript("OnClick", function() MSR:CancelRebuild() end)
    cancel.actionWidth = 116
    cancel:Hide()
    self.cancelRebuildButton = cancel

    local manualAction = CreateButton(self.frame, "Continue rebuild", 230, 27)
    manualAction:SetScript("OnClick", function() MSR:PerformManualRebuildAction() end)
    manualAction.actionWidth = 230
    manualAction:Hide()
    self.manualRebuildButton = manualAction

    local recruitToggle = CreateButton(self.frame, "Recruiting: OFF", 150, 27)
    recruitToggle:SetScript("OnClick", function() MSR:ToggleRecruitment() end)
    recruitToggle.actionWidth = 150
    self.recruitToggleActionButton = recruitToggle

    local postRoster = CreateButton(self.frame, "Post roster", 112, 27)
    postRoster:SetScript("OnClick", function() MSR:PostRaidRosterSummary() end)
    postRoster.actionWidth = 112
    self.postRosterActionButton = postRoster

    local leave = CreateButton(self.frame, "Post & Leave", 128, 27)
    leave:SetScript("OnClick", function() MSR:PostLevelStatus() end)
    leave.actionWidth = 128
    self.leaveActionButton = leave

    local resume = CreateButton(self.frame, "Resume rebuild", 132, 27)
    resume:SetScript("OnClick", function() MSR:ResumeRebuild() end)
    resume.actionWidth = 132
    self.resumeRebuildActionButton = resume

    self.contextActionButtons = {
        optimize, rebuild, readyCheck, startManastorm, cancel, manualAction,
        recruitToggle, postRoster, leave, resume,
    }

    local warning = CreateLabel(self.frame, "", false, COLORS.red)
    warning:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 540, 23)
    warning:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -16, 23)
    warning:SetJustifyH("RIGHT")
    self.warningText = warning
end

function UI:RefreshRecruitmentToggle()
    local button = self.recruitToggleActionButton
    if not button then return end
    local running = MSR:IsRecruitmentRunning()
    local red, green, blue = running and 0.18 or 0.78, running and 0.72 or 0.12, running and 0.24 or 0.12
    button:SetText(running and "Recruiting: ON" or "Recruiting: OFF")
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if normal and normal.SetVertexColor then normal:SetVertexColor(red, green, blue, 1) end
    if pushed and pushed.SetVertexColor then pushed:SetVertexColor(red * 0.8, green * 0.8, blue * 0.8, 1) end
    if highlight and highlight.SetVertexColor then highlight:SetVertexColor(
        math.min(1, red + 0.2), math.min(1, green + 0.2), math.min(1, blue + 0.2), 1
    ) end
    local font = button.GetFontString and button:GetFontString()
    if font and font.SetTextColor then
        if running then font:SetTextColor(0.75, 1, 0.75, 1) else font:SetTextColor(1, 0.72, 0.72, 1) end
    end
    button.stateColor = running and "green" or "red"
end

function UI:ShowActionButtons(buttons)
    for _, button in ipairs(self.contextActionButtons or {}) do button:Hide() end
    local x = 16
    for _, button in ipairs(buttons or {}) do
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, 16)
        button:Show()
        x = x + (button.actionWidth or 100) + 8
    end
end

function UI:RefreshActionBar(phase, inManastorm, inGroup, rebuildStatus, optimizationStatus)
    local readyCheck = MSR.runtime and MSR.runtime.readyCheck
    self.optimizeButton:SetText(MSR:GetGroupOptimizationButtonLabel())
    self.readyCheckButton:SetText(readyCheck and readyCheck.state == "running"
        and string.format("Ready %d/%d", readyCheck.ready or 0, readyCheck.total or 0)
        or "Ready Check")
    self:RefreshRecruitmentToggle()
    local leavePending = MSR.runtime and MSR.runtime.pendingLeave
    local soloInManastorm = inManastorm and not inGroup
    self.leaveActionButton:SetText(leavePending and "Leaving..." or soloInManastorm and "Leave MS" or "Post & Leave")

    if self.postRosterButton then
        if inGroup then
            self.postRosterButton:Show()
            self.postRosterButton:Enable()
        else
            self.postRosterButton:Hide()
        end
    end
    if self.levelStatusButton then self.levelStatusButton:Hide() end
    if self.disbandButton then
        if phase == "raid" then self.disbandButton:Show() else self.disbandButton:Hide() end
    end

    if phase == "rebuild" then
        local manualLabel = MSR:GetManualRebuildActionLabel()
        local activeRebuild = MSR.runtime and MSR.runtime.rebuild
        if activeRebuild and activeRebuild.phase == "waiting-return" then
            self.recruitToggleActionButton:Enable()
            self:ShowActionButtons({ self.recruitToggleActionButton })
        elseif manualLabel then
            self.manualRebuildButton:SetText(manualLabel)
            self.manualRebuildButton:Enable()
            self:ShowActionButtons({ self.manualRebuildButton })
        elseif MSR.runtime and MSR.runtime.rebuild and MSR.runtime.rebuild.phase == "countdown" then
            self.cancelRebuildButton:Enable()
            self:ShowActionButtons({ self.cancelRebuildButton })
        elseif not (MSR.runtime and MSR.runtime.rebuild) and MSR:HasRebuildRecovery() then
            self.resumeRebuildActionButton:Enable()
            self:ShowActionButtons({ self.resumeRebuildActionButton })
        else
            self:ShowActionButtons({})
        end
        local rebuildHint = activeRebuild and activeRebuild.phase == "waiting-return"
            and " | You can restart recruiting for missing players."
            or ""
        self.warningText:SetText("|cffffaa33" .. (rebuildStatus ~= "" and rebuildStatus or "Saved rebuild recovery available") .. rebuildHint .. "|r")
        return
    end

    if phase == "recruitment" then
        self.recruitToggleActionButton:Enable()
        self:ShowActionButtons({ self.recruitToggleActionButton })
        self.warningText:SetText(MSR:IsRecruitmentRunning()
            and "|cff55ff88Recruiting is running: posts and applicant whispers are active.|r"
            or "|cff777f8fStart recruiting to post once and collect applicant whispers.|r")
        return
    end

    if phase == "raid" then
        self.recruitToggleActionButton:Enable()
        self.optimizeButton:Enable()
        if (readyCheck and readyCheck.state == "running") or not MSR:IsGroupLeader() then self.readyCheckButton:Disable()
        else self.readyCheckButton:Enable() end
        local canStart = MSR:CanStartManastormLevelOne()
        if canStart then self.startManastormButton:Enable() else self.startManastormButton:Disable() end
        self:ShowActionButtons({ self.recruitToggleActionButton, self.optimizeButton, self.readyCheckButton, self.startManastormButton })
        self.warningText:SetText(optimizationStatus ~= ""
            and ("|cffffaa33" .. optimizationStatus .. "|r")
            or "|cff777f8fFill the roster, optimize groups, then start Manastorm.|r")
        return
    end

    self.optimizeButton:Enable()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 and IsRaidLeader and IsRaidLeader() then self.rebuildButton:Enable()
    else self.rebuildButton:Disable() end
    if (inGroup or inManastorm) and not leavePending then self.leaveActionButton:Enable() else self.leaveActionButton:Disable() end
    self:ShowActionButtons({ self.optimizeButton, self.rebuildButton, self.leaveActionButton })
    local issues = MSR:GetValidationIssues(MSR.runtime.roster)
    if #issues > 0 then self.warningText:SetText("|cffff6666" .. table.concat(issues, " | ") .. "|r")
    elseif MSR.char.session.needsRebuild then self.warningText:SetText("|cffff6666Level 60 detected - rebuild required.|r")
    else self.warningText:SetText("|cff777f8fMonitor levels and Aura coverage during Manastorm.|r") end
end

function UI:RefreshSettings()
    if not self.frame then return end
    self.channelEdit:SetText(tostring(MSR.db.settings.channel or ""))
    for key, edit in pairs(self.slotEdits) do edit:SetText(tostring(MSR.db.settings.slots[key] or 0)) end
    self.intervalEdit:SetText(tostring(MSR.db.settings.autoPostInterval or 90))
    self.selfRoleButton:SetText(MSR.ROLE_LABELS[MSR.char.selfRole] or "DPS")
    self.selfAuraCheck:SetChecked(MSR.char.selfAura == true)
    self.autoPostCheck:SetChecked(MSR.db.settings.autoPost == true)
    self.autoReplyCheck:SetChecked(MSR.db.settings.autoReply == true)
    self.auraReservationCheck:SetChecked(MSR.db.settings.auraReservation.enabled == true)
    for key, button in pairs(self.auraReservationRoleButtons) do
        button:SetText(MSR.db.settings.auraReservation.roles[key] and ("[" .. button.roleLabel .. "]") or button.roleLabel)
    end
end

function UI:CommitSettings()
    if not self.frame or not MSR.db then return end
    MSR.db.settings.channel = self.channelEdit:GetText()
    for key, edit in pairs(self.slotEdits) do MSR.db.settings.slots[key] = tonumber(edit:GetText()) or 0 end
    MSR.db.settings.autoPostInterval = tonumber(self.intervalEdit:GetText()) or 90
    local valid, reason = MSR:ValidateSettings()
    if not valid then MSR:LocalWarning(reason) end
    MSR.runtime.groupOptimization = nil
    MSR:BuildRoster()
    self:Refresh()
end

function UI:RefreshApplicants()
    local waiting = MSR:GetApplicantsForDisplay("waiting")
    local joined = MSR:GetApplicantsForDisplay("joined")
    local applicants = self.applicantView == "joined" and joined or waiting
    applicants = self:ApplyFrozenApplicantOrder(applicants)
    if self.applicantOffset >= #applicants and self.applicantOffset > 0 then
        self.applicantOffset = math.max(0, self.applicantOffset - self.applicantPageSize)
    end
    self.applicantsTitle:SetText(self.applicantView == "joined" and "Raid members" or "Waiting players")
    self.waitingApplicantsTab:SetText(string.format("Waiting %d", #waiting))
    self.joinedApplicantsTab:SetText(string.format("In raid %d", #joined))
    if self.applicantView == "joined" then
        self.joinedApplicantsTab:Disable()
        self.waitingApplicantsTab:Enable()
    else
        self.waitingApplicantsTab:Disable()
        self.joinedApplicantsTab:Enable()
    end

    local committedCounts = MSR:GetCommittedCounts()
    for rowIndex, row in ipairs(self.applicantRows) do
        local applicant = applicants[self.applicantOffset + rowIndex]
        row.applicant = applicant
        row.roleButton.applicant = applicant
        row.auraButton.applicant = applicant
        row.inviteButton.applicant = applicant
        row.reserveButton.applicant = applicant
        row.rejectButton.applicant = applicant
        if applicant then
            row:Show()
            row.nameText:SetText(Truncate(applicant.name, 11))
            local level = tonumber(applicant.level)
            row.levelText:SetText(LevelColor(level) .. "Lv " .. tostring(level or "?") .. "|r")
            row.roleButton:SetText(MSR.ROLE_LABELS[applicant.role] or "Unknown")
            row.auraButton:SetText(applicant.aura == nil and "A?" or (applicant.aura and "A+" or "A-"))
            local color = MSR.STATUS_COLORS[applicant.status] or "|cffffffff"
            local capacityCode, capacityReason
            if self.applicantView ~= "joined" and applicant.status ~= "Invited" then
                capacityCode, capacityReason = MSR:GetApplicantCapacityIssue(applicant, committedCounts)
            end
            row.capacityReason = capacityReason
            row.inviteButton:SetText("Invite")
            if capacityCode then
                SetBackdrop(row, { 0.22, 0.035, 0.045, 0.96 }, { 0.85, 0.16, 0.20, 1 })
                local warning = capacityCode == "RAID_FULL" and "RAID FULL"
                    or capacityCode == "AURA_REQUIRED" and "AURA!"
                    or "FULL"
                row.statusText:SetText("|cffff5555" .. warning .. "|r")
            else
                SetBackdrop(row, row.normalBackground, row.normalBorder)
            local statusLabel = applicant.pendingQuestion == "role" and "Role?"
                or applicant.pendingQuestion == "aura" and "Aura?"
                or applicant.pendingQuestion == "level" and "Level?"
                or applicant.needsReview and "Review" or applicant.status
            local inviteSeconds = MSR:GetInviteSecondsRemaining(applicant)
            if inviteSeconds then statusLabel = "Invited " .. inviteSeconds .. "s" end
            row.statusText:SetText(color .. statusLabel .. "|r")
            end
            if applicant.status == "Joined" then
                row.inviteButton:Disable()
                row.reserveButton:Disable()
                row.rejectButton:Disable()
            elseif applicant.status == "Invited" then
                row.inviteButton:Disable()
                row.reserveButton:Enable()
                row.rejectButton:Enable()
            elseif capacityCode then
                row.inviteButton:SetText(capacityCode == "AURA_REQUIRED" and "Aura!" or "Full")
                row.inviteButton:Disable()
                row.reserveButton:Enable()
                row.rejectButton:Enable()
            else
                row.inviteButton:Enable()
                row.reserveButton:Enable()
                row.rejectButton:Enable()
            end
            row.inviteButton:SetText(applicant.status == "NoResponse" and "Reinvite" or row.inviteButton:GetText())
            row.reserveButton:SetText(applicant.status == "Invited" and "Release"
                or applicant.status == "Reserve" and "Unreserve" or "Reserve")
        else
            row.capacityReason = nil
            row:Hide()
        end
    end

    local totalPages = math.max(1, math.ceil(#applicants / self.applicantPageSize))
    local currentPage = math.floor(self.applicantOffset / self.applicantPageSize) + 1
    self.applicantPageText:SetText(string.format("Page %d/%d", currentPage, totalPages))
end

function UI:RefreshGroups()
    local roster = MSR:BuildRoster()
    local grouped = { [1] = {}, [2] = {}, [3] = {} }
    for _, member in ipairs(roster) do
        local group = member.subgroup or 1
        if group >= 1 and group <= 3 then table.insert(grouped[group], member) end
    end
    table.sort(grouped[1], function(left, right)
        local leftTank = left.role == "TANK"
        local rightTank = right.role == "TANK"
        if leftTank ~= rightTank then return leftTank end
        return (tonumber(left.raidIndex) or 99) < (tonumber(right.raidIndex) or 99)
    end)
    for group = 1, 3 do
        local card = self.groupCards[group]
        local hasAura = false
        for _, member in ipairs(grouped[group]) do if member.aura == true then hasAura = true break end end
        card.aura:SetText(hasAura and "|cff55ff88AURA|r" or "|cffff5555NO AURA|r")
        for index = 1, 5 do
            local row = card.rows[index]
            local member = grouped[group][index]
            if member then
                row.roleIcon:SetTexture(ROLE_ICONS[member.role] or ROLE_ICONS.UNKNOWN)
                row.roleIcon:Show()
                row.nameText:SetText((ROLE_COLORS[member.role] or ROLE_COLORS.UNKNOWN) .. Truncate(member.name, 15) .. "|r")
                row.levelText:SetText(LevelColor(member.level) .. "Lv " .. tostring(member.level or "?") .. "|r")
                row.auraText:SetText(member.aura == true and "|cff55ff88A+|r"
                    or member.aura == nil and "|cffff6666A?|r"
                    or "|cffbb7777A-|r")
                local readyStatus = MSR:GetReadyCheckMemberStatus(member)
                row.readyText:SetText(readyStatus == "ready" and "|cff55ff77R|r"
                    or readyStatus == "notready" and "|cffff5555N|r"
                    or readyStatus == "waiting" and "|cffffcc55?|r"
                    or "")
                row.kickButton.member = member
                row.kickButton:Show()
                local canKick = MSR:CanKickRosterMember(member)
                if canKick then row.kickButton:Enable() else row.kickButton:Disable() end
                if member.online == false then row.nameText:SetText("|cff777777" .. Truncate(member.name, 15) .. "|r") end
            else
                row.roleIcon:Hide()
                row.nameText:SetText("|cff777777Empty|r")
                row.levelText:SetText("")
                row.auraText:SetText("")
                row.readyText:SetText("")
                row.kickButton.member = nil
                row.kickButton:Hide()
            end
        end
    end

    local counts = MSR:GetCounts(roster)
    local slots = MSR.db.settings.slots
    self.countsText:SetText(string.format(
        "%d/%d  |T%s:14|t%d/%d  |T%s:14|t%d/%d  |T%s:14|t%d/%d  A %d/%d",
        counts.total, MSR:GetTargetTotal(), ROLE_ICONS.TANK, counts.tank, slots.tank,
        ROLE_ICONS.HEAL, counts.heal, slots.heal, ROLE_ICONS.DPS, counts.dps, slots.dps,
        counts.aura, slots.aura
    ))
end

function UI:Refresh()
    if not self.frame or not MSR.db then return end
    self.previewText:SetText(MSR:BuildRecruitmentMessage())
    self.selfRoleButton:SetText(MSR.ROLE_LABELS[MSR.char.selfRole] or "DPS")
    self.selfAuraCheck:SetChecked(MSR.char.selfAura == true)
    self.autoPostCheck:SetChecked(MSR.db.settings.autoPost == true)
    self.autoReplyCheck:SetChecked(MSR.db.settings.autoReply == true)
    self.auraReservationCheck:SetChecked(MSR.db.settings.auraReservation.enabled == true)
    for key, button in pairs(self.auraReservationRoleButtons) do
        button:SetText(MSR.db.settings.auraReservation.roles[key] and ("[" .. button.roleLabel .. "]") or button.roleLabel)
        if MSR.db.settings.auraReservation.enabled then button:Enable() else button:Disable() end
    end
    self.listenButton:SetText("Listening: " .. (MSR.char.session.listening and "ON" or "OFF"))

    local inManastorm = MSR:IsInManastorm()
    self:UpdateAutomaticPhase()
    local phase = self.phase or "recruitment"
    local phaseStatus = phase == "rebuild" and "|cffffaa33REBUILD IN PROGRESS|r"
        or phase == "manastorm" and "|cff55ff88IN MANASTORM|r"
        or phase == "raid" and "|cff66ccffBUILDING RAID|r"
        or "|cffffff66RECRUITMENT MODE|r"
    self.statusText:SetText(phaseStatus)
    if inManastorm then self.postButton:Disable() else self.postButton:Enable() end
    self.manastormStatusText:SetText(MSR:GetReadyCheckStatusText())
    self:RefreshGroupChatState()

    self:RefreshApplicants()
    self:RefreshGroups()
    self:RefreshRebuildPanel()

    local rebuildStatus = MSR:GetRebuildStatus()
    local optimizationStatus = MSR:GetGroupOptimizationStatus()
    local rosterCount = #(MSR.runtime.roster or {})
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then self.postRosterButton:Enable()
    else self.postRosterButton:Disable() end
    local inGroup = (GetNumRaidMembers and GetNumRaidMembers() > 0)
        or (GetNumPartyMembers and GetNumPartyMembers() > 0)
    self.levelStatusButton:SetText("Post & Leave")
    if inGroup then self.levelStatusButton:Enable() else self.levelStatusButton:Disable() end
    if rebuildStatus == "" and rosterCount > 1 and MSR:CanManageRaid()
        and not (InCombatLockdown and InCombatLockdown()) then
        self.disbandButton:Enable()
    else
        self.disbandButton:Disable()
    end
    self:RefreshActionBar(phase, inManastorm, inGroup, rebuildStatus, optimizationStatus)
    self:ApplyWindowScale()
end

function UI:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then self.frame:Hide()
    else self.frame:Show() self:RefreshSettings() self:Refresh() end
end

function UI:ShowResetConfirmation()
    StaticPopup_Show("MSR_RESET_SESSION")
end

function UI:ShowRebuildConfirmation()
    StaticPopup_Show("MSR_REBUILD_RAID")
end

function UI:ShowDisbandConfirmation()
    StaticPopup_Show("MSR_DISBAND_RAID")
end

function MSR:CreateUI()
    UI:CreateMainFrame()
    UI:CreatePhaseBar()
    UI:CreateMinimapButton()
    UI:CreateMessageTemplatesFrame()
    UI:CreateSettingsPanel()
    UI:CreateRecruitmentPanel()
    UI:CreateApplicantsPanel()
    UI:CreateGroupsPanel()
    UI:CreateRebuildPanel()
    UI:CreateActionBar()
    UI:RefreshSettings()
    UI:RefreshGroupChat()
    UI:Refresh()
    UI.frame:Hide()
end

StaticPopupDialogs["MSR_RESUME_REBUILD"] = {
    text = "An unfinished raid rebuild was found. Resume it using the saved roster?",
    button1 = "Resume rebuild",
    button2 = "Discard",
    OnAccept = function() MSR:ResumeRebuild() end,
    OnCancel = function() MSR:DiscardRebuildRecovery() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
}

StaticPopupDialogs["MSR_RESET_SESSION"] = {
    text = "Clear all applicants, statuses and the cached rebuild roster?",
    button1 = "Clear session",
    button2 = "Cancel",
    OnAccept = function() MSR:ClearSession() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MSR_REBUILD_RAID"] = {
    text = "Rebuild the raid? A raid warning is sent immediately. Five seconds later every member except you is removed, then reinvited after three seconds.",
    button1 = "Start rebuild",
    button2 = "Cancel",
    OnAccept = function() MSR:BeginRebuild() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["MSR_DISBAND_RAID"] = {
    text = "Disband the current group? Every other member will be removed immediately and no reinvites will be sent.",
    button1 = "Disband group",
    button2 = "Cancel",
    OnAccept = function() MSR:DisbandCurrentGroup() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
