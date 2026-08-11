local MSR = ManastormRecruiter

local function MissingLabel(count, singular, plural)
    count = tonumber(count) or 0
    if count == 1 then return "1 " .. singular end
    return tostring(count) .. " " .. (plural or (singular .. "s"))
end

function MSR:BuildRecruitmentMessage()
    local counts = self:GetCommittedCounts()
    local reservationActive, missingAuras = self:GetAuraReservationState(counts)
    local reservation = ""
    if reservationActive then
        reservation = self:BuildConfiguredMessage("reservationSuffix", {
            roles = self:GetAuraReservationRoleLabel(true, counts),
            missingAura = missingAuras,
        })
    end
    return self:PrepareChatMessage(self:BuildConfiguredMessage(
        "recruitment",
        self:BuildMessageValues(counts, { reservation = reservation })
    ))
end

function MSR:BuildRaidRosterSummary(roster)
    local counts = self:GetCounts(roster or self:BuildRoster())
    local slots = self.db.settings.slots
    local tankMissing = math.max(0, (tonumber(slots.tank) or 0) - counts.tank)
    local healMissing = math.max(0, (tonumber(slots.heal) or 0) - counts.heal)
    local dpsMissing = math.max(0, (tonumber(slots.dps) or 0) - counts.dps)
    local auraMissing = math.max(0, (tonumber(slots.aura) or 0) - counts.aura)
    local needed = {}
    if tankMissing > 0 then table.insert(needed, MissingLabel(tankMissing, "Tank")) end
    if healMissing > 0 then table.insert(needed, MissingLabel(healMissing, "Healer")) end
    if dpsMissing > 0 then table.insert(needed, MissingLabel(dpsMissing, "DPS", "DPS")) end
    if auraMissing > 0 then table.insert(needed, MissingLabel(auraMissing, "Aura player")) end

    local status
    if #needed == 0 then
        status = self:BuildConfiguredMessage("rosterComplete")
    else
        status = self:BuildConfiguredMessage("rosterNeeded", { needed = table.concat(needed, ", ") })
    end
    return self:PrepareChatMessage(self:BuildConfiguredMessage(
        "rosterSummary",
        self:BuildMessageValues(counts, { status = status, needed = table.concat(needed, ", ") })
    ))
end

function MSR:PostRaidRosterSummary()
    local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
    local inParty = GetNumPartyMembers and GetNumPartyMembers() > 0
    if not inRaid and not inParty then
        self:PrivateWarning("You must be in a group to post the roster summary.")
        return false
    end
    if type(SendChatMessage) ~= "function" then
        self:PrivateWarning("Raid chat is unavailable.")
        return false
    end
    local message = self:BuildRaidRosterSummary()
    local chatType = inRaid and "RAID" or "PARTY"
    local ok, result = pcall(SendChatMessage, message, chatType)
    if not ok or result == false then
        local detail = not ok and (": " .. tostring(result)) or "."
        self:PrivateWarning("The roster summary could not be posted to group chat" .. detail)
        return false
    end
    self:Print("Current role and Aura requirements posted to group chat.")
    return true
end

function MSR:RecordGroupChat(event, message, sender)
    local labels = {
        CHAT_MSG_PARTY = "Party",
        CHAT_MSG_PARTY_LEADER = "Party",
        CHAT_MSG_RAID = "Raid",
        CHAT_MSG_RAID_LEADER = "Raid",
        CHAT_MSG_RAID_WARNING = "Warning",
    }
    local label = labels[event]
    if not label then return end
    local _, shortName = self:NormalizeName(sender or "Unknown")
    local entry = {
        channel = label,
        sender = shortName,
        message = tostring(message or ""),
        timestamp = date and date("%H:%M") or "",
    }
    self.runtime.groupChat = self.runtime.groupChat or {}
    table.insert(self.runtime.groupChat, entry)
    while #self.runtime.groupChat > 100 do table.remove(self.runtime.groupChat, 1) end
    if self.UI and self.UI.AddGroupChatMessage then self.UI:AddGroupChatMessage(entry) end
end

function MSR:SendGroupChat(message)
    message = self:PrepareChatMessage(message)
    if message == "" then return false end
    local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
    local inParty = GetNumPartyMembers and GetNumPartyMembers() > 0
    if not inRaid and not inParty then
        self:PrivateWarning("Join a party or raid before sending a group message.")
        return false
    end
    if type(SendChatMessage) ~= "function" then
        self:PrivateWarning("Group chat is unavailable.")
        return false
    end
    local ok, result = pcall(SendChatMessage, message, inRaid and "RAID" or "PARTY")
    if not ok or result == false then
        self:PrivateWarning("The group message could not be sent.")
        return false
    end
    return true
end

function MSR:DisbandCurrentGroup()
    if self.runtime and self.runtime.rebuild then
        self:PrivateWarning("Cancel or finish the active rebuild before disbanding the group.")
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        self:PrivateWarning("The group cannot be disbanded during combat.")
        return false
    end
    if not self:CanManageRaid() then
        self:PrivateWarning("You must be group leader or raid assistant to disband the group.")
        return false
    end
    if type(UninviteUnit) ~= "function" then
        self:PrivateWarning("The remove-player API is unavailable.")
        return false
    end

    local playerKey = self:NormalizeName(UnitName("player") or "")
    local members = {}
    for _, member in ipairs(self:BuildRoster()) do
        if member.key ~= playerKey then table.insert(members, member.name) end
    end
    if #members == 0 then
        self:Print("There are no other group members to remove.")
        return false
    end

    local requested, failed = 0, 0
    for _, name in ipairs(members) do
        local ok, result = pcall(UninviteUnit, name)
        if ok and result ~= false then requested = requested + 1 else failed = failed + 1 end
    end
    self.runtime.readyCheck = nil
    self.runtime.groupOptimization = nil
    if failed > 0 then
        self:PrivateWarning(string.format("Removal requested for %d player(s); %d request(s) failed.", requested, failed))
    else
        self:Print(string.format("Group disband requested for %d player(s). No reinvites will be sent.", requested))
    end
    self:RefreshUI()
    return requested > 0
end

function MSR:ResolveChannel()
    local configured = tostring(self.db.settings.channel or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if configured == "" then return 0 end
    local numeric = tonumber(configured)
    local channelId
    if numeric then channelId = select(1, GetChannelName(numeric))
    else channelId = select(1, GetChannelName(configured)) end
    return tonumber(channelId) or 0
end

function MSR:PostRecruitment(isAutomatic)
    local valid, reason = self:ValidateSettings()
    if not valid then self:LocalWarning(reason) return false end
    if self:IsInManastorm() then self:LocalWarning("Recruitment is paused inside Manastorm.") return false end
    if self:IsRosterFull() then
        if not isAutomatic then self:Print("Roster is full; recruitment message was not posted.") end
        return false
    end
    local channelId = self:ResolveChannel()
    if channelId <= 0 then
        self:LocalWarning("Recruitment channel is unavailable. Check the configured number or name.")
        return false
    end
    local message = self:BuildRecruitmentMessage()
    if message == "" then
        self:LocalWarning("The recruitment message is empty. Open Edit messages and configure it first.")
        return false
    end
    local ok, err = pcall(SendChatMessage, message, "CHANNEL", nil, channelId)
    if not ok then self:LocalWarning("Unable to post: " .. tostring(err)) return false end
    self.char.session.listening = true
    self.char.session.lastPostAt = time()
    self:RefreshUI()
    return true
end
function MSR:StartRecruitment()
    if not self:PostRecruitment(false) then return false end
    self.db.settings.autoPost = true
    self:Print("Recruitment started. Automatic posts and applicant whispers are active.")
    self:RefreshUI()
    return true
end

function MSR:StopRecruitment()
    local wasRunning = self.char.session.listening == true or self.db.settings.autoPost == true
    self.char.session.listening = false
    self.db.settings.autoPost = false
    self.runtime.lastAutoPostAttempt = nil
    if wasRunning then self:Print("Recruitment stopped. Automatic posts and applicant whispers are paused.") end
    self:RefreshUI()
    return true
end

function MSR:IsRecruitmentRunning()
    return self.char.session.listening == true and self.db.settings.autoPost == true
end

function MSR:ToggleRecruitment()
    if self:IsRecruitmentRunning() then return self:StopRecruitment() end
    return self:StartRecruitment()
end

function MSR:InviteApplicant(applicant)
    if not applicant then return false end
    if applicant.role == "UNKNOWN" or applicant.aura == nil then
        self:LocalWarning(applicant.name .. " needs a confirmed role and Aura yes/no before inviting.")
        return false
    end
    if not self:IsGroupLeader() then self:LocalWarning("You must be group leader to invite players.") return end
    if self.runtime.rosterByKey[applicant.key] then
        applicant.status = "Joined"
        self:RefreshUI()
        return true
    end
    if applicant.status == "Invited" then
        self:LocalWarning(applicant.name .. " already has a pending invite.")
        return false
    end
    local _, capacityReason = self:GetApplicantCapacityIssue(applicant, self:GetCommittedCounts())
    if capacityReason then
        self:LocalWarning(capacityReason)
        return false
    end
    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    if numRaid == 0 and numParty > 0 and self:GetTargetTotal() > 5 and ConvertToRaid then
        pcall(ConvertToRaid)
    end
    local ok, err = pcall(InviteUnit, applicant.name)
    if ok then
        applicant.status = "Invited"
        applicant.updatedAt = time()
        applicant.inviteSentAt = time()
        applicant.inviteReminderSent = false
        self:Print("Invite sent to " .. applicant.name .. ".")
    else
        self:LocalWarning("Invite failed for " .. applicant.name .. ": " .. tostring(err))
    end
    self:RefreshUI()
    return ok and true or false
end

function MSR:ReleaseApplicantSlot(applicant, automatic)
    if not applicant or applicant.status ~= "Invited" then return false end
    applicant.status = "NoResponse"
    applicant.inviteSentAt = nil
    applicant.inviteReminderSent = nil
    applicant.updatedAt = time()
    self:Print(string.format(
        "%s's pending slot was released%s.",
        applicant.name,
        automatic and " after 10 seconds" or " locally"
    ))
    self:RefreshUI()
    return true
end

function MSR:GetInviteSecondsRemaining(applicant)
    if not applicant or applicant.status ~= "Invited" or not applicant.inviteSentAt then return nil end
    local timeout = tonumber(self.db.settings.inviteTimeout) or 10
    return math.max(0, math.ceil(timeout - (time() - applicant.inviteSentAt)))
end

function MSR:UpdatePendingInvites()
    if not self.char or not self.char.session then return end
    local now = time()
    local reminderDelay = tonumber(self.db.settings.inviteReminderDelay) or 5
    local timeout = tonumber(self.db.settings.inviteTimeout) or 10
    for _, applicant in pairs(self.char.session.applicants or {}) do
        if applicant.status == "Invited" and applicant.inviteSentAt then
            local elapsed = now - applicant.inviteSentAt
            if elapsed >= timeout then
                self:ReleaseApplicantSlot(applicant, true)
            elseif elapsed >= reminderDelay and not applicant.inviteReminderSent then
                applicant.inviteReminderSent = true
                local reminder = self:PrepareChatMessage(self:BuildConfiguredMessage("inviteReminder", {
                    player = applicant.name,
                    seconds = math.max(0, math.ceil(timeout - elapsed)),
                }))
                if reminder ~= "" and type(SendChatMessage) == "function" then
                    pcall(SendChatMessage, reminder, "WHISPER", nil, applicant.name)
                end
            end
        end
    end
end

function MSR:ClearSession()
    local session = self.char.session
    session.applicants = {}
    session.order = {}
    session.level59Alerted = {}
    session.level60Alerted = {}
    session.lastRebuildRoster = {}
    session.whisperHistory = {}
    session.rebuildRecovery = { active = false }
    session.lastPostAt = 0
    session.listening = false
    session.needsRebuild = false
    self.runtime.rebuild = nil
    self.runtime.groupOptimization = nil
    self.runtime.lastValidationSignature = ""
    self:BuildRoster()
    self:RefreshUI()
    self:Print("Recruitment session cleared.")
end

function MSR:GetApplicantPriority(applicant, counts)
    counts = counts or self:GetCommittedCounts()
    local slots = self.db.settings.slots
    local score = 0
    if applicant.status == "Invited" then score = score + 1000
    elseif applicant.status == "New" then score = score + 500
    elseif applicant.status == "NoResponse" then score = score + 250
    elseif applicant.status == "Reserve" then score = score + 100 end

    if applicant.role ~= "UNKNOWN" and applicant.aura ~= nil then score = score + 100
    else score = score - 200 end

    local roleKey = applicant.role == "TANK" and "tank"
        or applicant.role == "HEAL" and "heal"
        or applicant.role == "DPS" and "dps"
    if roleKey then
        local missing = math.max(0, (tonumber(slots[roleKey]) or 0) - (tonumber(counts[roleKey]) or 0))
        score = score + (missing * 40)
    end
    local auraMissing = math.max(0, (tonumber(slots.aura) or 0) - (tonumber(counts.aura) or 0))
    if applicant.aura == true then score = score + (auraMissing * 35) end
    if self:GetApplicantCapacityIssue(applicant, counts) then score = score - 400 end
    return score
end

function MSR:GetApplicantsForDisplay(view)
    view = view == "joined" and "joined" or "waiting"
    local rows = {}
    for _, key in ipairs(self.char.session.order) do
        local applicant = self.char.session.applicants[key]
        -- Rejected applicants remain cached so a later whisper can restore
        -- them, but they should no longer clutter the active applicant list.
        if applicant and applicant.status ~= "Rejected" then
            local isJoined = applicant.status == "Joined"
            if (view == "joined" and isJoined) or (view == "waiting" and not isJoined) then
                table.insert(rows, applicant)
            end
        end
    end
    if view == "waiting" then
        local counts = self:GetCommittedCounts()
        table.sort(rows, function(left, right)
            local leftScore = self:GetApplicantPriority(left, counts)
            local rightScore = self:GetApplicantPriority(right, counts)
            if leftScore ~= rightScore then return leftScore > rightScore end
            local leftUpdated = tonumber(left.updatedAt) or tonumber(left.createdAt) or 0
            local rightUpdated = tonumber(right.updatedAt) or tonumber(right.createdAt) or 0
            if leftUpdated ~= rightUpdated then return leftUpdated > rightUpdated end
            return tostring(left.name or "") < tostring(right.name or "")
        end)
    end
    return rows
end
