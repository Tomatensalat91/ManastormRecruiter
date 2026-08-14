local MSR = ManastormRecruiter

local AUTO_GROUP_CONFIRM_DELAY = 0.75
local AUTO_GROUP_MAX_ATTEMPTS = 3
local AUTO_GROUP_INVITE_TTL = 180

MSR.AUTOMATIC_GROUP_ASSIGNMENT_VERSION = 4

function MSR:IsAutomaticGroupAssignmentEnabled()
    return not self.db or not self.db.settings or self.db.settings.automaticGroupAssignment ~= false
end

function MSR:SetAutomaticGroupAssignmentEnabled(enabled)
    if not self.db or not self.db.settings then return false end
    self.db.settings.automaticGroupAssignment = enabled and true or false
    if not enabled and self.runtime then
        self.runtime.automaticGroupAssignment = nil
        self.runtime.pendingInviteGroupAssignments = {}
        if self.char and self.char.session then self.char.session.automaticInviteGroupAssignments = {} end
        self:Print("Automatic group assignment disabled; waiting moves were cleared.")
    elseif enabled then
        self:Print("Automatic group assignment enabled.")
    end
    return true
end

function MSR:GetPersistentAutomaticInviteGroupAssignments()
    if not self.char or not self.char.session then return nil end
    if type(self.char.session.automaticInviteGroupAssignments) ~= "table" then
        self.char.session.automaticInviteGroupAssignments = {}
    end
    return self.char.session.automaticInviteGroupAssignments
end

function MSR:ClearAutomaticInviteGroupAssignment(memberKey)
    if not memberKey then return end
    if self.runtime and self.runtime.pendingInviteGroupAssignments then
        self.runtime.pendingInviteGroupAssignments[memberKey] = nil
    end
    local persistent = self:GetPersistentAutomaticInviteGroupAssignments()
    if persistent then persistent[memberKey] = nil end
end

local function JoinWithOr(values)
    if #values == 0 then return "selected roles" end
    if #values == 1 then return values[1] end
    if #values == 2 then return values[1] .. " or " .. values[2] end
    return table.concat(values, ", ", 1, #values - 1) .. ", or " .. values[#values]
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return math.floor(value + 0.5)
end

function MSR:IsGroupLeader()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return IsRaidLeader and IsRaidLeader()
    end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        if IsRealPartyLeader then return IsRealPartyLeader() end
        return IsPartyLeader and IsPartyLeader("player")
    end
    return true
end

function MSR:CanManageRaid()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())
    end
    return self:IsGroupLeader()
end

function MSR:CanKickRosterMember(member)
    if not member or not member.name then return false, "No raid member was selected." end
    local playerKey = self:NormalizeName(UnitName("player") or "")
    if member.key == playerKey then return false, "You cannot remove yourself with this button." end
    if self.runtime and self.runtime.rebuild then
        return false, "Finish or cancel the active raid rebuild first."
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "Players cannot be removed during combat."
    end
    if not self:CanManageRaid() then
        return false, "You must be group leader or raid assistant to remove players."
    end
    if type(UninviteUnit) ~= "function" then return false, "The remove-player API is unavailable." end
    return true
end

function MSR:KickRosterMember(member)
    local allowed, reason = self:CanKickRosterMember(member)
    if not allowed then
        self:PrivateWarning(reason)
        return false
    end
    local ok, result = pcall(UninviteUnit, member.name)
    if not ok or result == false then
        self:PrivateWarning("The removal request for " .. tostring(member.name) .. " failed.")
        return false
    end
    if tonumber(member.level) == 59 then
        local message = self:BuildConfiguredMessage("level59KickWhisper", {
            player = member.name,
            level = member.level,
        })
        if message ~= "" and type(SendChatMessage) == "function" then
            local whisperOk, whisperResult = pcall(SendChatMessage, message, "WHISPER", nil, member.name)
            if not whisperOk or whisperResult == false then
                self:LocalWarning("The Level 59 farewell whisper to " .. tostring(member.name) .. " could not be sent.")
            end
        end
    end
    self:Print("Removal requested for " .. tostring(member.name) .. ".")
    return true
end

function MSR:GetTargetTotal()
    local slots = self.db.settings.slots
    return (slots.tank or 0) + (slots.heal or 0) + (slots.dps or 0)
end

function MSR:ValidateSettings()
    local slots = self.db.settings.slots
    slots.tank = Clamp(slots.tank, 0, 15)
    slots.heal = Clamp(slots.heal, 0, 15)
    slots.dps = Clamp(slots.dps, 0, 15)
    slots.aura = Clamp(slots.aura, 0, 15)
    self.db.settings.autoPostInterval = Clamp(self.db.settings.autoPostInterval, 30, 600)
    self.db.settings.inviteTimeout = Clamp(self.db.settings.inviteTimeout, 5, 30)
    self.db.settings.inviteReminderDelay = Clamp(self.db.settings.inviteReminderDelay, 1, self.db.settings.inviteTimeout - 1)
    local reservation = self.db.settings.auraReservation
    if type(reservation) ~= "table" then
        reservation = { enabled = true, roles = { tank = false, heal = false, dps = true } }
        self.db.settings.auraReservation = reservation
    end
    if type(reservation.roles) ~= "table" then reservation.roles = {} end
    reservation.enabled = reservation.enabled == true
    reservation.roles.tank = reservation.roles.tank == true
    reservation.roles.heal = reservation.roles.heal == true
    reservation.roles.dps = reservation.roles.dps == true
    if type(self.db.settings.messages) ~= "table" then self:ResetMessageTemplates() end
    if self:GetTargetTotal() > 15 then return false, "Role slots cannot exceed 15 players." end
    if self:GetTargetTotal() < 1 then return false, "At least one role slot is required." end
    if slots.aura > self:GetTargetTotal() then return false, "Aura slots cannot exceed total players." end
    return true
end

function MSR:GetRoleForName(name)
    local key = self:NormalizeName(name)
    local playerKey = self:NormalizeName(UnitName("player") or "")
    if key == playerKey then return self.char.selfRole, self.char.selfAura end
    local applicant = self.char.session.applicants[key]
    if applicant then return applicant.role or "UNKNOWN", applicant.aura == true end
    return "UNKNOWN", false
end

function MSR:BuildRoster()
    local roster = {}
    local present = {}
    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0

    if numRaid > 0 then
        for index = 1, numRaid do
            local name, rank, subgroup, level, class, classFileName, zone, online = GetRaidRosterInfo(index)
            if name then
                local key, shortName = self:NormalizeName(name)
                local role, aura = self:GetRoleForName(name)
                local member = {
                    key = key,
                    name = shortName,
                    unit = "raid" .. index,
                    raidIndex = index,
                    subgroup = subgroup or 1,
                    level = tonumber(level) or UnitLevel("raid" .. index) or 0,
                    online = online ~= false,
                    role = role,
                    aura = aura,
                    rank = rank or 0,
                }
                table.insert(roster, member)
                present[key] = member
            end
        end
    else
        local playerName = UnitName("player")
        if playerName then
            local key, shortName = self:NormalizeName(playerName)
            local member = {
                key = key,
                name = shortName,
                unit = "player",
                raidIndex = nil,
                subgroup = 1,
                level = UnitLevel("player") or 0,
                online = true,
                role = self.char.selfRole,
                aura = self.char.selfAura,
                rank = 2,
            }
            table.insert(roster, member)
            present[key] = member
        end

        local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
        for index = 1, numParty do
            local unit = "party" .. index
            if UnitExists(unit) then
                local name = UnitName(unit)
                local key, shortName = self:NormalizeName(name)
                local role, aura = self:GetRoleForName(name)
                local connected = true
                if UnitIsConnected then connected = UnitIsConnected(unit) and true or false end
                local member = {
                    key = key,
                    name = shortName,
                    unit = unit,
                    raidIndex = nil,
                    subgroup = 1,
                    level = UnitLevel(unit) or 0,
                    online = connected,
                    role = role,
                    aura = aura,
                    rank = 0,
                }
                table.insert(roster, member)
                present[key] = member
            end
        end
    end

    -- A player can also be invited manually, without ever whispering the addon.
    -- Add those group members to the same editable list so role and Aura can be
    -- assigned after they join.
    local playerKey = self:NormalizeName(UnitName("player") or "")
    for _, member in ipairs(roster) do
        if member.key ~= playerKey then
            local applicant = self.char.session.applicants[member.key]
            if not applicant then
                applicant = self:EnsureApplicant(member.name)
                applicant.message = "Added automatically from the current group roster."
                applicant.needsReview = true
            end
            if applicant.status ~= "Joined" then
                applicant.status = "Joined"
                applicant.updatedAt = time()
            end
            applicant.inviteSentAt = nil
            applicant.inviteReminderSent = nil
            self:SetApplicantLevel(applicant, member.level)
            member.role = applicant.role or "UNKNOWN"
            member.aura = applicant.aura
        end
    end

    for key, applicant in pairs(self.char.session.applicants) do
        if present[key] then
            applicant.status = "Joined"
        elseif applicant.status == "Joined" then
            local rebuild = self.runtime.rebuild
            local willBeReinvited = rebuild
                and rebuild.reinviteByKey
                and rebuild.reinviteByKey[applicant.key]
            applicant.status = willBeReinvited and "Invited" or "Left"
        end
    end

    self.runtime.roster = roster
    self.runtime.rosterByKey = present
    return roster
end

function MSR:GetCounts(roster)
    roster = roster or self.runtime.roster or self:BuildRoster()
    local counts = { tank = 0, heal = 0, dps = 0, aura = 0, unknown = 0, total = #roster }
    for _, member in ipairs(roster) do
        if member.role == "TANK" then counts.tank = counts.tank + 1
        elseif member.role == "HEAL" then counts.heal = counts.heal + 1
        elseif member.role == "DPS" then counts.dps = counts.dps + 1
        else counts.unknown = counts.unknown + 1 end
        if member.aura == true then counts.aura = counts.aura + 1 end
    end
    return counts
end

function MSR:GetCommittedCounts(roster)
    roster = roster or self:BuildRoster()
    local counts = self:GetCounts(roster)
    local present = {}
    for _, member in ipairs(roster) do present[member.key] = true end

    -- Pending invites already consume a planned slot even though the player is
    -- not visible in the group roster yet. Counting them prevents overbooking.
    for key, applicant in pairs(self.char.session.applicants) do
        if applicant.status == "Invited" and not present[key] then
            counts.total = counts.total + 1
            if applicant.role == "TANK" then counts.tank = counts.tank + 1
            elseif applicant.role == "HEAL" then counts.heal = counts.heal + 1
            elseif applicant.role == "DPS" then counts.dps = counts.dps + 1
            else counts.unknown = counts.unknown + 1 end
            if applicant.aura == true then counts.aura = counts.aura + 1 end
        end
    end
    return counts
end

function MSR:GetAuraReservationRoles()
    local reservation = self.db.settings.auraReservation or {}
    local configured = reservation.roles or {}
    local roles = {}
    for _, role in ipairs(self.ROLE_ORDER) do
        if configured[string.lower(role)] == true then table.insert(roles, role) end
    end
    return roles
end

function MSR:GetAuraReservationRoleLabel(onlyOpen, counts)
    counts = counts or self:GetCommittedCounts()
    local slots = self.db.settings.slots
    local labels = {}
    for _, role in ipairs(self:GetAuraReservationRoles()) do
        local key = string.lower(role)
        if not onlyOpen or (tonumber(slots[key]) or 0) > (tonumber(counts[key]) or 0) then
            table.insert(labels, self.ROLE_LABELS[role] or role)
        end
    end
    return JoinWithOr(labels)
end

function MSR:GetAuraReservationState(counts)
    counts = counts or self:GetCounts(self:BuildRoster())
    local reservation = self.db.settings.auraReservation or {}
    if reservation.enabled ~= true then return false, 0, 0 end
    local slots = self.db.settings.slots
    local missingAuras = math.max(0, (tonumber(slots.aura) or 0) - (tonumber(counts.aura) or 0))
    local freeSelectedSlots = 0
    for _, role in ipairs(self:GetAuraReservationRoles()) do
        local key = string.lower(role)
        freeSelectedSlots = freeSelectedSlots + math.max(
            0,
            (tonumber(slots[key]) or 0) - (tonumber(counts[key]) or 0)
        )
    end
    local active = missingAuras > 0 and freeSelectedSlots > 0 and freeSelectedSlots <= missingAuras
    return active, missingAuras, freeSelectedSlots
end

function MSR:ShouldRequireAuraForDPS()
    local roles = self.db.settings.auraReservation and self.db.settings.auraReservation.roles or {}
    return roles.dps == true and self:GetAuraReservationState()
end

function MSR:GetApplicantCapacityIssue(applicant, counts)
    counts = counts or self:GetCommittedCounts()
    local slots = self.db.settings.slots
    if (tonumber(counts.total) or 0) >= self:GetTargetTotal() then
        return "RAID_FULL", self:BuildConfiguredMessage("raidFullReply")
    end

    local role = applicant and applicant.role or "UNKNOWN"
    local roleCount, roleLimit, roleName
    if role == "TANK" then
        roleCount, roleLimit, roleName = counts.tank, slots.tank, "Tanks"
    elseif role == "HEAL" then
        roleCount, roleLimit, roleName = counts.heal, slots.heal, "Healers"
    elseif role == "DPS" then
        roleCount, roleLimit, roleName = counts.dps, slots.dps, "DPS"
    end
    if roleName and (tonumber(roleCount) or 0) >= (tonumber(roleLimit) or 0) then
        return "ROLE_FULL", self:BuildConfiguredMessage("roleFullReply", {
            role = self.ROLE_LABELS[role] or role,
            rolePlural = roleName,
        })
    end

    local reservationRoles = self.db.settings.auraReservation and self.db.settings.auraReservation.roles or {}
    if applicant and applicant.aura == false and reservationRoles[string.lower(role)] == true
        and self:GetAuraReservationState(counts) then
        local _, missingAuras = self:GetAuraReservationState(counts)
        return "AURA_REQUIRED", self:BuildConfiguredMessage("auraRequiredReply", {
            roles = self:GetAuraReservationRoleLabel(true, counts),
            missingAura = missingAuras,
        })
    end
    return nil
end

function MSR:GetApplicationCapacityReply(applicant, counts)
    if self:IsInManastorm() then
        return self:BuildConfiguredMessage("inManastormReply")
    end
    local _, reply = self:GetApplicantCapacityIssue(applicant, counts)
    return reply
end

function MSR:IsRosterFull()
    local counts = self:GetCommittedCounts()
    local slots = self.db.settings.slots
    return counts.total == self:GetTargetTotal()
        and counts.tank == slots.tank
        and counts.heal == slots.heal
        and counts.dps == slots.dps
        and counts.aura >= slots.aura
        and counts.unknown == 0
end


function MSR:GetRoleCapacities()
    local slots = self.db.settings.slots
    local capacities = {
        [1] = { TANK = 0, HEAL = 0, DPS = 0, total = 0 },
        [2] = { TANK = 0, HEAL = 0, DPS = 0, total = 0 },
        [3] = { TANK = 0, HEAL = 0, DPS = 0, total = 0 },
    }
    local counts = { TANK = slots.tank, HEAL = slots.heal, DPS = slots.dps }
    for _, role in ipairs(self.ROLE_ORDER) do
        local group = 1
        for _ = 1, counts[role] do
            local attempts = 0
            while capacities[group].total >= 5 and attempts < 3 do
                group = group % 3 + 1
                attempts = attempts + 1
            end
            if capacities[group].total < 5 then
                capacities[group][role] = capacities[group][role] + 1
                capacities[group].total = capacities[group].total + 1
            end
            group = group % 3 + 1
        end
    end
    return capacities
end

function MSR:BuildDesiredGroups(roster)
    local capacities = self:GetRoleCapacities()
    local assignments = { [1] = {}, [2] = {}, [3] = {} }
    local used = {}
    local auraGroups = math.min(3, self.db.settings.slots.aura or 0)

    local function AssignAura(group)
        if group > auraGroups then return true end
        for index, member in ipairs(roster) do
            if not used[index] and member.aura == true and capacities[group][member.role] and capacities[group][member.role] > 0 then
                used[index] = true
                capacities[group][member.role] = capacities[group][member.role] - 1
                table.insert(assignments[group], member)
                if AssignAura(group + 1) then return true end
                table.remove(assignments[group])
                capacities[group][member.role] = capacities[group][member.role] + 1
                used[index] = nil
            end
        end
        return false
    end

    if not AssignAura(1) then return nil, "No valid arrangement can place an Aura player in every required group." end

    for _, role in ipairs(self.ROLE_ORDER) do
        for index, member in ipairs(roster) do
            if not used[index] and member.role == role then
                local placed = false
                for group = 1, 3 do
                    if capacities[group][role] > 0 then
                        capacities[group][role] = capacities[group][role] - 1
                        table.insert(assignments[group], member)
                        used[index] = true
                        placed = true
                        break
                    end
                end
                if not placed then return nil, "Role distribution does not match the configured slots." end
            end
        end
    end

    for index = 1, #roster do
        if not used[index] then return nil, roster[index].name .. " has no valid group slot." end
    end
    return assignments
end

function MSR:BuildPartialDesiredGroups(roster)
    local playerCount = #(roster or {})
    if playerCount == 0 then return nil, "There are no raid members to optimize." end
    if playerCount > 15 then return nil, "Manastorm groups support at most 15 players." end

    -- Plan against all three final subgroups even while the raid is incomplete.
    -- Compacting solely by player count can fill Groups 1 and 2 with DPS before
    -- their configured Tank/Healer slots arrive.
    local plannedGroups = 3
    local assignments = { [1] = {}, [2] = {}, [3] = {} }
    local roleCounts = {
        [1] = { TANK = 0, HEAL = 0, DPS = 0, UNKNOWN = 0 },
        [2] = { TANK = 0, HEAL = 0, DPS = 0, UNKNOWN = 0 },
        [3] = { TANK = 0, HEAL = 0, DPS = 0, UNKNOWN = 0 },
    }
    local configured = self:GetRoleCapacities()
    local used = {}

    local function AddMember(group, index)
        local member = roster[index]
        local role = member.role or "UNKNOWN"
        table.insert(assignments[group], member)
        roleCounts[group][role] = (roleCounts[group][role] or 0) + 1
        used[index] = true
    end

    local function RemoveMember(group, index)
        local member = roster[index]
        local role = member.role or "UNKNOWN"
        table.remove(assignments[group])
        roleCounts[group][role] = math.max(0, (roleCounts[group][role] or 0) - 1)
        used[index] = nil
    end

    local function HasRoleCapacity(group, role)
        local limit = configured[group] and configured[group][role]
        return limit ~= nil
            and (roleCounts[group][role] or 0) < limit
            and #assignments[group] < 5
    end

    local auraPlayers = 0
    for _, member in ipairs(roster) do
        if member.aura == true then auraPlayers = auraPlayers + 1 end
    end
    local auraGroups = math.min(
        plannedGroups,
        tonumber(self.db.settings.slots.aura) or 0,
        auraPlayers
    )

    -- The primary Tank is anchored in the first slot of Group 1 before Aura
    -- distribution. This keeps partial raids deterministic as well.
    for index, member in ipairs(roster) do
        if member.role == "TANK" then
            AddMember(1, index)
            break
        end
    end

    -- Seed the configured groups with Aura players without consuming a slot
    -- reserved for another role. Backtracking avoids a locally valid Aura pick
    -- that would leave a later group without a compatible Aura role.
    local auraTargets = {}
    for group = 1, auraGroups do
        local alreadyHasAura = false
        for _, assigned in ipairs(assignments[group]) do
            if assigned.aura == true then alreadyHasAura = true break end
        end
        if not alreadyHasAura then table.insert(auraTargets, group) end
    end

    local function AssignAura(targetIndex)
        if targetIndex > #auraTargets then return true end
        local group = auraTargets[targetIndex]
        for index, member in ipairs(roster) do
            local role = member.role or "UNKNOWN"
            if not used[index] and member.aura == true and HasRoleCapacity(group, role) then
                AddMember(group, index)
                if AssignAura(targetIndex + 1) then return true end
                RemoveMember(group, index)
            end
        end
        return false
    end
    AssignAura(1)

    local function FindBestGroup(role)
        local bestGroup
        local bestConfigured = -1
        local bestRoleCount
        local bestTotal
        for group = 1, plannedGroups do
            local total = #assignments[group]
            if HasRoleCapacity(group, role) then
                local configuredNeed = 0
                if configured[group][role] then
                    configuredNeed = math.max(0, configured[group][role] - (roleCounts[group][role] or 0))
                end
                local roleCount = roleCounts[group][role] or 0
                if not bestGroup
                    or configuredNeed > bestConfigured
                    or (configuredNeed == bestConfigured and roleCount < bestRoleCount)
                    or (configuredNeed == bestConfigured and roleCount == bestRoleCount and total < bestTotal) then
                    bestGroup = group
                    bestConfigured = configuredNeed
                    bestRoleCount = roleCount
                    bestTotal = total
                end
            end
        end
        return bestGroup
    end

    local function FindUnknownGroup()
        -- An unreviewed role cannot be matched to a configured slot yet. Keep
        -- Groups 1 and 2 untouched for as long as Group 3 has physical room.
        for group = plannedGroups, 1, -1 do
            if #assignments[group] < 5 then return group end
        end
        return nil
    end

    local roles = { "TANK", "HEAL", "DPS", "UNKNOWN" }
    for _, role in ipairs(roles) do
        for index, member in ipairs(roster) do
            if not used[index] and (member.role or "UNKNOWN") == role then
                local group = role == "UNKNOWN" and FindUnknownGroup() or FindBestGroup(role)
                if not group then return nil, member.name .. " has no available subgroup slot." end
                AddMember(group, index)
            end
        end
    end

    return assignments
end

function MSR:BuildAuraSwapPlan(roster)
    local requiredGroups = math.min(3, tonumber(self.db.settings.slots.aura) or 0)
    local auraCounts = {}
    local membersByGroup = {}
    local usedDonors = {}
    for group = 1, 8 do
        auraCounts[group] = 0
        membersByGroup[group] = {}
    end

    for _, member in ipairs(roster or {}) do
        local group = tonumber(member.subgroup) or 1
        if group >= 1 and group <= 8 then
            table.insert(membersByGroup[group], member)
            if member.aura == true then auraCounts[group] = auraCounts[group] + 1 end
        end
    end

    local swaps = {}
    for targetGroup = 1, requiredGroups do
        if auraCounts[targetGroup] == 0 then
            local donor
            for _, member in ipairs(roster or {}) do
                local sourceGroup = tonumber(member.subgroup) or 1
                if member.aura == true
                    and sourceGroup ~= targetGroup
                    and not usedDonors[member.key]
                    and (sourceGroup > requiredGroups or auraCounts[sourceGroup] > 1) then
                    donor = member
                    break
                end
            end
            if not donor then
                return nil, "Not enough movable Aura players to cover every required group."
            end

            local sameRole
            local fallback
            for _, candidate in ipairs(membersByGroup[targetGroup]) do
                if candidate.aura ~= true then
                    fallback = fallback or candidate
                    if candidate.role == donor.role then sameRole = candidate break end
                end
            end
            local recipient = sameRole or fallback
            if not recipient then
                return nil, "Group " .. targetGroup .. " has no player available for an Aura swap."
            end

            local sourceGroup = tonumber(donor.subgroup) or 1
            table.insert(swaps, {
                donor = donor,
                recipient = recipient,
                sourceGroup = sourceGroup,
                targetGroup = targetGroup,
            })
            usedDonors[donor.key] = true
            auraCounts[sourceGroup] = auraCounts[sourceGroup] - 1
            auraCounts[targetGroup] = auraCounts[targetGroup] + 1
        end
    end
    return swaps
end

function MSR:OptimizeAuraGroups()
    if InCombatLockdown and InCombatLockdown() then self:PrivateWarning("Aura groups cannot be optimized during combat.") return false end
    if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then self:PrivateWarning("Convert the party to a raid first.") return false end
    if not (IsRaidLeader and IsRaidLeader()) then self:PrivateWarning("Only the raid leader can optimize Aura groups.") return false end
    if type(SwapRaidSubgroup) ~= "function" then self:PrivateWarning("SwapRaidSubgroup is unavailable in this client.") return false end

    local roster = self:BuildRoster()
    local swaps, reason = self:BuildAuraSwapPlan(roster)
    if not swaps then self:PrivateWarning(reason) return false end
    if #swaps == 0 then
        self:Print("Aura distribution is already correct.")
        return true
    end

    for _, swap in ipairs(swaps) do
        if not swap.donor.raidIndex or not swap.recipient.raidIndex then
            self:PrivateWarning("Unable to resolve raid indexes for the Aura swap.")
            return false
        end
        local ok, result = pcall(SwapRaidSubgroup, swap.donor.raidIndex, swap.recipient.raidIndex)
        if not ok or result == false then
            self:PrivateWarning("Ascension rejected an Aura subgroup swap.")
            return false
        end
    end

    self:Print(string.format("Aura distribution optimized with %d subgroup swap(s).", #swaps))
    self:BuildRoster()
    self:RefreshUI()
    return true
end

function MSR:GetGroupOptimizationSignature(roster)
    local values = {}
    for _, member in ipairs(roster or {}) do
        table.insert(values, table.concat({
            tostring(member.key or ""),
            tostring(member.role or "UNKNOWN"),
            member.aura and "1" or "0",
        }, ":"))
    end
    table.sort(values)
    return table.concat(values, "|")
end

function MSR:BuildGroupOptimizationPlan(roster)
    local counts = self:GetCounts(roster)
    local slots = self.db.settings.slots
    local isComplete = counts.total == self:GetTargetTotal()
        and counts.tank == slots.tank
        and counts.heal == slots.heal
        and counts.dps == slots.dps
        and counts.aura >= slots.aura
        and counts.unknown == 0

    local assignments, reason
    if isComplete then
        assignments, reason = self:BuildDesiredGroups(roster)
    else
        assignments, reason = self:BuildPartialDesiredGroups(roster)
    end
    if not assignments then return nil, reason end

    local primaryTankKey
    for index, member in ipairs(assignments[1]) do
        if member.role == "TANK" then
            primaryTankKey = member.key
            if index ~= 1 then
                table.remove(assignments[1], index)
                table.insert(assignments[1], 1, member)
            end
            break
        end
    end

    local desired = {}
    for group = 1, 3 do
        for _, member in ipairs(assignments[group]) do desired[member.key] = group end
    end
    return {
        desired = desired,
        signature = self:GetGroupOptimizationSignature(roster),
        isComplete = isComplete,
        playerCount = #roster,
        primaryTankKey = primaryTankKey,
        pending = nil,
    }
end

function MSR:MarkPrimaryTank(roster, primaryTankKey)
    if not primaryTankKey then return true end
    local tank
    for _, member in ipairs(roster or {}) do
        if member.key == primaryTankKey then tank = member break end
    end
    if not tank or tank.role ~= "TANK" or tonumber(tank.subgroup) ~= 1 then
        self:PrivateWarning("The primary Tank is not confirmed in Group 1 yet.")
        return false
    end
    if type(SetRaidTarget) ~= "function" then
        self:PrivateWarning("SetRaidTarget is unavailable in this client; the Tank could not be marked with a star.")
        return false
    end
    local unit = tank.unit or (tank.raidIndex and ("raid" .. tostring(tank.raidIndex)))
    if not unit then
        self:PrivateWarning("Unable to resolve the primary Tank for the star marker.")
        return false
    end
    local ok, result = pcall(SetRaidTarget, unit, 1)
    if not ok or result == false then
        self:PrivateWarning("Ascension rejected the star marker for " .. tostring(tank.name) .. ".")
        return false
    end
    self:Print(tostring(tank.name) .. " is first in Group 1 and marked with the raid star.")
    return true
end

function MSR:MarkTanks(roster)
    if type(SetRaidTarget) ~= "function" then
        self:PrivateWarning("SetRaidTarget is unavailable; Tank markers could not be updated.")
        return false
    end
    local tanks = {}
    for _, member in ipairs(roster or {}) do
        if member.role == "TANK" then table.insert(tanks, member) end
    end
    table.sort(tanks, function(left, right)
        local leftGroup = tonumber(left.subgroup) or 9
        local rightGroup = tonumber(right.subgroup) or 9
        if leftGroup ~= rightGroup then return leftGroup < rightGroup end
        local leftIndex = tonumber(left.raidIndex) or 99
        local rightIndex = tonumber(right.raidIndex) or 99
        if leftIndex ~= rightIndex then return leftIndex < rightIndex end
        return tostring(left.name or "") < tostring(right.name or "")
    end)

    local labels = { "star", "circle" }
    for index = 1, math.min(2, #tanks) do
        local tank = tanks[index]
        local unit = tank.unit or (tank.raidIndex and ("raid" .. tostring(tank.raidIndex)))
        if not unit then
            self:PrivateWarning("Unable to resolve " .. tostring(tank.name) .. " for the Tank marker.")
            return false
        end
        local ok, result = pcall(SetRaidTarget, unit, index)
        if not ok or result == false then
            self:PrivateWarning("Ascension rejected the " .. labels[index] .. " marker for " .. tostring(tank.name) .. ".")
            return false
        end
    end
    if #tanks > 0 then
        local message = tostring(tanks[1].name) .. " marked with star"
        if tanks[2] then message = message .. ", " .. tostring(tanks[2].name) .. " with circle" end
        self:Print(message .. ".")
    end
    return true
end

-- Ascension protects Main-Tank promotion. Never call SetPartyAssignment from
-- addon Lua; the detached secure /mt controls are created in UI.lua instead.

function MSR:GetAutomaticGroupTarget(memberKey, roster)
    roster = roster or self:BuildRoster()
    local member
    for _, candidate in ipairs(roster or {}) do
        if candidate.key == memberKey then member = candidate break end
    end
    if not member then return nil, "The player is not in the raid roster." end

    -- Aura coverage has priority over the compact partial-raid planner. If the
    -- player's current group already has another Aura, use the first configured
    -- group that is still uncovered. This is the behavior proven by the
    -- separate AutoGroup test addon on Ascension.
    if member.aura == true then
        local requiredGroups = math.min(3, tonumber(self.db.settings.slots.aura) or 0)
        local configured = self:GetRoleCapacities()
        local memberRole = member.role or "UNKNOWN"
        local auraCounts = {}
        local roleCounts = {}
        for group = 1, requiredGroups do
            auraCounts[group] = 0
            roleCounts[group] = 0
        end
        for _, candidate in ipairs(roster) do
            local group = tonumber(candidate.subgroup) or 1
            if group >= 1 and group <= requiredGroups and candidate.key ~= memberKey then
                if candidate.aura == true then auraCounts[group] = auraCounts[group] + 1 end
                if (candidate.role or "UNKNOWN") == memberRole then
                    roleCounts[group] = roleCounts[group] + 1
                end
            end
        end
        for group = 1, requiredGroups do
            -- Aura coverage may use a buffered exchange for a physically full
            -- group, but it must never consume a slot reserved for another role.
            local roleLimit = configured[group] and configured[group][memberRole] or 0
            if auraCounts[group] == 0 and roleCounts[group] < roleLimit then return group end
        end
    end

    local plan, reason = self:BuildGroupOptimizationPlan(roster)
    if not plan then return nil, reason end
    return plan.desired and plan.desired[memberKey], nil, plan
end

function MSR:PlanAutomaticInviteGroupAssignment(applicant, reason, silent)
    if not self:IsAutomaticGroupAssignmentEnabled() then return false end
    if not applicant or not applicant.key then return false end
    local persistent = self:GetPersistentAutomaticInviteGroupAssignments()
    local existing = persistent and persistent[applicant.key]
    local plan = {
        key = applicant.key,
        name = applicant.name,
        reason = reason or (existing and existing.reason) or "invite accepted",
        armedAt = tonumber(existing and existing.armedAt) or tonumber(applicant.inviteSentAt) or time(),
    }
    self.runtime.pendingInviteGroupAssignments = self.runtime.pendingInviteGroupAssignments or {}
    self.runtime.pendingInviteGroupAssignments[applicant.key] = plan
    if persistent then
        persistent[applicant.key] = {
            key = plan.key,
            name = plan.name,
            reason = plan.reason,
            armedAt = plan.armedAt,
        }
    end
    if not silent then
        self:Print("Automatic group assignment armed for " .. tostring(applicant.name) .. "; waiting for the player to join.")
    end
    return true
end

function MSR:RestoreAutomaticInviteGroupAssignments(silent)
    if not self:IsAutomaticGroupAssignmentEnabled() then return false end
    if not self.runtime or not self.char or not self.char.session then return false end
    self.runtime.pendingInviteGroupAssignments = self.runtime.pendingInviteGroupAssignments or {}
    local persistent = self:GetPersistentAutomaticInviteGroupAssignments()
    local restored = 0

    -- Older saves only contain the applicant's Invited status. Seed the new
    -- persistent queue from it so the first reload after upgrading is safe too.
    for key, applicant in pairs(self.char.session.applicants or {}) do
        if applicant.status == "Invited" and not persistent[key] then
            persistent[key] = {
                key = key,
                name = applicant.name,
                reason = "invite accepted",
                armedAt = tonumber(applicant.inviteSentAt) or time(),
            }
        end
    end

    for key, stored in pairs(persistent) do
        local applicant = self.char.session.applicants[key]
        local armedAt = tonumber(stored.armedAt) or time()
        local expired = time() - armedAt > AUTO_GROUP_INVITE_TTL
        local cancelled = applicant and (
            applicant.status == "Declined" or applicant.status == "Rejected" or applicant.status == "Left"
        )
        if not applicant or cancelled or expired then
            persistent[key] = nil
            self.runtime.pendingInviteGroupAssignments[key] = nil
        elseif not self.runtime.pendingInviteGroupAssignments[key]
            and not (self.runtime.automaticGroupAssignment and self.runtime.automaticGroupAssignment.key == key) then
            self.runtime.pendingInviteGroupAssignments[key] = {
                key = key,
                name = stored.name or applicant.name,
                reason = stored.reason or "invite accepted",
                armedAt = armedAt,
            }
            restored = restored + 1
        end
    end
    if restored > 0 and not silent then
        self:Print(string.format("Restored %d automatic group assignment%s after reload.", restored, restored == 1 and "" or "s"))
    end
    return restored > 0
end

function MSR:DetectUnplannedAutomaticGroupJoins(roster)
    if not self:IsAutomaticGroupAssignmentEnabled() or not self.runtime then return false end
    local current = {}
    for _, member in ipairs(roster or {}) do current[member.key] = member end
    local known = self.runtime.automaticGroupKnownMembers
    self.runtime.automaticGroupKnownMembers = current
    if type(known) ~= "table" then return false end

    local playerKey = self:NormalizeName(UnitName("player") or "")
    local queued = false
    for key, member in pairs(current) do
        local alreadyPlanned = self.runtime.pendingInviteGroupAssignments
            and self.runtime.pendingInviteGroupAssignments[key]
        local alreadyActive = self.runtime.automaticGroupAssignment
            and self.runtime.automaticGroupAssignment.key == key
        if key ~= playerKey and not known[key] and not alreadyPlanned and not alreadyActive then
            local applicant = self.char and self.char.session and self.char.session.applicants[key]
            if applicant and applicant.role and applicant.role ~= "UNKNOWN" then
                self:PlanAutomaticInviteGroupAssignment(applicant, "new raid member fallback", true)
                self:Print("Recovered automatic group assignment for new raid member " .. tostring(member.name) .. ".")
                queued = true
            end
        end
    end
    return queued
end

function MSR:ActivatePendingInviteGroupAssignment(roster)
    local planned = self.runtime and self.runtime.pendingInviteGroupAssignments
    if type(planned) ~= "table" then return false end
    roster = roster or self:BuildRoster()
    local rosterByKey = {}
    for _, member in ipairs(roster) do rosterByKey[member.key] = member end

    for key, invitePlan in pairs(planned) do
        local member = rosterByKey[key]
        if member then
            -- The first accepted invite joins a party. Keep the plan until the
            -- subsequent party-to-raid conversion is visible to the client;
            -- SetRaidSubgroup cannot run during the intermediate party state.
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                local queued = self:QueueAutomaticGroupAssignment(key, invitePlan.reason or "invite accepted", true)
                if queued then planned[key] = nil end
                if self.runtime.automaticGroupAssignment then return true end
            end
        else
            local applicant = self.char and self.char.session and self.char.session.applicants[key]
            local expired = invitePlan.armedAt and time() - invitePlan.armedAt > AUTO_GROUP_INVITE_TTL
            local cancelled = applicant and (
                applicant.status == "Declined" or applicant.status == "Rejected" or applicant.status == "Left"
            )
            if not applicant or cancelled or expired then
                self:ClearAutomaticInviteGroupAssignment(key)
            end
        end
    end
    return false
end

function MSR:QueueAutomaticGroupAssignment(memberKey, reason, deferUpdate)
    if not self:IsAutomaticGroupAssignmentEnabled() then return false end
    if not memberKey then return false end

    local roster = self:BuildRoster()
    local member
    for _, candidate in ipairs(roster) do
        if candidate.key == memberKey then member = candidate break end
    end
    if not member then return false end

    if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then
        self.runtime.pendingInviteGroupAssignments = self.runtime.pendingInviteGroupAssignments or {}
        self.runtime.pendingInviteGroupAssignments[memberKey] = {
            key = member.key,
            name = member.name,
            reason = reason or "assignment updated",
            armedAt = time(),
        }
        self:Print("Automatic group assignment for " .. tostring(member.name) .. " is waiting for raid conversion.")
        return true
    end
    if not member.raidIndex then return false end

    local target, targetReason = self:GetAutomaticGroupTarget(memberKey, roster)
    if not target then
        self:ClearAutomaticInviteGroupAssignment(memberKey)
        self:PrivateWarning("Automatic group assignment skipped for " .. tostring(member.name) .. ": " .. tostring(targetReason))
        return false
    end
    if tonumber(member.subgroup) == target then
        self.runtime.automaticGroupAssignment = nil
        self:ClearAutomaticInviteGroupAssignment(memberKey)
        self:Print(string.format("%s already matches Group %d after %s.", member.name, target, reason or "assignment update"))
        return true
    end

    self.runtime.automaticGroupAssignment = {
        key = member.key,
        name = member.name,
        target = target,
        reason = reason or "assignment updated",
        attempts = 0,
        nextAttemptAt = 0,
    }
    self:Print(string.format("Automatic group assignment planned: %s -> Group %d (%s).", member.name, target, reason or "assignment updated"))
    if deferUpdate then return true end
    return self:UpdateAutomaticGroupAssignment(roster)
end

function MSR:QueueSelfAutomaticGroupAssignment(reason)
    local playerKey = self:NormalizeName(UnitName("player") or "")
    if not playerKey or playerKey == "" then return false end
    return self:QueueAutomaticGroupAssignment(playerKey, reason or "own assignment changed")
end

function MSR:PrintAutomaticGroupAssignmentStatus()
    local enabled = self:IsAutomaticGroupAssignmentEnabled()
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    local manager = self:CanManageRaid()
    self:Print(string.format(
        "Group assignment: %s | raid %d | manager %s | SetRaidSubgroup %s.",
        enabled and "ON" or "OFF",
        raidCount,
        manager and "yes" or "no",
        type(SetRaidSubgroup) == "function" and "available" or "missing"
    ))

    local active = self.runtime and self.runtime.automaticGroupAssignment
    if active then
        self:Print(string.format(
            "Active: %s -> Group %d | %s | attempts %d.",
            tostring(active.name), tonumber(active.target) or 0,
            tostring(active.reason), tonumber(active.attempts) or 0
        ))
    else
        self:Print("Active: none.")
    end

    local waiting = 0
    for _, plan in pairs(self.runtime and self.runtime.pendingInviteGroupAssignments or {}) do
        waiting = waiting + 1
        self:Print(string.format("Waiting: %s | %s | age %ds.",
            tostring(plan.name), tostring(plan.reason), math.max(0, time() - (tonumber(plan.armedAt) or time()))
        ))
    end
    if waiting == 0 then self:Print("Waiting: none.") end

    local roster = self:BuildRoster()
    for _, member in ipairs(roster) do
        local target, reason = self:GetAutomaticGroupTarget(member.key, roster)
        self:Print(string.format(
            "%s: Group %d -> target %s | %s | Aura %s.",
            tostring(member.name), tonumber(member.subgroup) or 1,
            target and tostring(target) or "none",
            tostring(member.role or "UNKNOWN"),
            member.aura and "yes" or "no"
        ))
        if not target and reason then self:Print("  Target reason: " .. tostring(reason)) end
    end
end

function MSR:FindAutomaticGroupSwapCandidate(member, target, roster)
    local plan = self:BuildGroupOptimizationPlan(roster)
    local desired = plan and plan.desired or {}
    local source = tonumber(member.subgroup) or 1
    local misplacedFallback
    local sameRoleNonAura
    local nonAuraFallback
    for _, candidate in ipairs(roster) do
        if candidate.key ~= member.key and tonumber(candidate.subgroup) == target then
            -- Best case: the normal group plan explicitly wants this player in
            -- the mover's current group, producing a clean two-way exchange.
            if desired[candidate.key] == source then return candidate end
            if desired[candidate.key] ~= nil and desired[candidate.key] ~= target then
                misplacedFallback = misplacedFallback or candidate
            end

            -- Aura coverage can deliberately override the compact partial-raid
            -- plan. In that case the target group may be full without any
            -- plan-marked displacement. Swap out a non-Aura player, preferring
            -- the same role so the group's role balance changes as little as possible.
            if member.aura == true and candidate.aura ~= true then
                if candidate.role == member.role then sameRoleNonAura = sameRoleNonAura or candidate end
                nonAuraFallback = nonAuraFallback or candidate
            end
        end
    end
    return misplacedFallback or sameRoleNonAura or nonAuraFallback
end

function MSR:FindAutomaticGroupBuffer(roster, source, target)
    local groupCounts = {}
    for group = 4, 8 do groupCounts[group] = 0 end
    for _, member in ipairs(roster or {}) do
        local group = tonumber(member.subgroup) or 1
        if groupCounts[group] ~= nil then groupCounts[group] = groupCounts[group] + 1 end
    end
    for group = 4, 8 do
        if group ~= source and group ~= target and groupCounts[group] < 5 then return group end
    end
    return nil
end

function MSR:UpdateAutomaticGroupAssignment(roster)
    if not self:IsAutomaticGroupAssignmentEnabled() then
        if self.runtime then
            self.runtime.automaticGroupAssignment = nil
            self.runtime.pendingInviteGroupAssignments = {}
        end
        if self.char and self.char.session then self.char.session.automaticInviteGroupAssignments = {} end
        return false
    end
    roster = roster or self:BuildRoster()
    self:RestoreAutomaticInviteGroupAssignments(true)
    self:DetectUnplannedAutomaticGroupJoins(roster)
    -- Rebuild reinvites arrive one by one. Do not calculate a destination from
    -- that incomplete roster: keep every rebuild plan waiting until the rebuild
    -- state has ended, then determine each target from the returned raid.
    if self.runtime.rebuild then return false end
    local pending = self.runtime and self.runtime.automaticGroupAssignment
    if not pending then
        if not self:ActivatePendingInviteGroupAssignment(roster) then return false end
        pending = self.runtime.automaticGroupAssignment
        if not pending then return false end
    end

    local member
    local exchangeMember
    local targetCount = 0
    for _, candidate in ipairs(roster) do
        if candidate.key == pending.key then member = candidate end
        if pending.exchange and candidate.key == pending.exchange.key then exchangeMember = candidate end
        if tonumber(candidate.subgroup) == pending.target then targetCount = targetCount + 1 end
    end
    if not member then
        self.runtime.automaticGroupAssignment = nil
        self:ClearAutomaticInviteGroupAssignment(pending.key)
        self:PrivateWarning("Automatic group assignment cancelled because " .. tostring(pending.name) .. " left the raid.")
        return false
    end
    if pending.exchange then
        local exchange = pending.exchange
        if not exchangeMember then
            self.runtime.automaticGroupAssignment = nil
            self:ClearAutomaticInviteGroupAssignment(pending.key)
            self:PrivateWarning("Automatic group exchange cancelled because " .. tostring(exchange.name) .. " left the raid.")
            return false
        end

        local memberGroup = tonumber(member.subgroup) or 1
        local exchangeGroup = tonumber(exchangeMember.subgroup) or 1
        if exchange.stage == "buffer" and exchangeGroup == exchange.buffer then
            exchange.stage = "mover"
            pending.attempts = 0
            pending.nextAttemptAt = 0
            pending.notice = nil
        end
        if exchange.stage == "mover" and memberGroup == pending.target then
            exchange.stage = "restore"
            pending.attempts = 0
            pending.nextAttemptAt = 0
            pending.notice = nil
        end
        if exchange.stage == "restore" and memberGroup == pending.target and exchangeGroup == exchange.source then
            self.runtime.automaticGroupAssignment = nil
            self:ClearAutomaticInviteGroupAssignment(pending.key)
            self:Print(string.format(
                "Automatic group exchange confirmed: %s is now in Group %d and %s is now in Group %d.",
                member.name, pending.target, exchangeMember.name, exchange.source
            ))
            self:RefreshUI()
            return true
        end
    elseif tonumber(member.subgroup) == pending.target then
        self.runtime.automaticGroupAssignment = nil
        self:ClearAutomaticInviteGroupAssignment(pending.key)
        self:Print(string.format("Automatic group assignment confirmed: %s is now in Group %d.", member.name, pending.target))
        self:RefreshUI()
        return true
    end

    local now = GetTime and GetTime() or 0
    if now < (pending.nextAttemptAt or 0) then return false end
    if InCombatLockdown and InCombatLockdown() then
        pending.nextAttemptAt = now + 1
        if pending.notice ~= "combat" then
            pending.notice = "combat"
            self:Print("Automatic group assignment for " .. member.name .. " will continue after combat.")
        end
        return false
    end
    if not self:CanManageRaid() then
        pending.nextAttemptAt = now + 1
        if pending.notice ~= "permission" then
            pending.notice = "permission"
            self:PrivateWarning("Automatic group assignment requires raid leader or assistant rights.")
        end
        return false
    end
    if pending.attempts >= AUTO_GROUP_MAX_ATTEMPTS then
        self.runtime.automaticGroupAssignment = nil
        self:ClearAutomaticInviteGroupAssignment(pending.key)
        self:PrivateWarning(string.format("Automatic group assignment for %s was not confirmed after %d attempts.", member.name, pending.attempts))
        return false
    end

    pending.attempts = pending.attempts + 1
    local from = tonumber(member.subgroup) or 1
    local ok, result
    local action = "move"
    local actionMember = member
    local actionTarget = pending.target
    if pending.exchange then
        local exchange = pending.exchange
        if exchange.stage == "buffer" then
            actionMember = exchangeMember
            actionTarget = exchange.buffer
            action = "exchange buffer move"
        elseif exchange.stage == "mover" then
            if targetCount >= 5 then
                pending.attempts = pending.attempts - 1
                pending.nextAttemptAt = now + 1
                if pending.notice ~= "exchange-target-full" then
                    pending.notice = "exchange-target-full"
                    self:PrivateWarning(string.format("Group %d did not become free yet; the exchange for %s is waiting.", pending.target, member.name))
                end
                return false
            end
            action = "exchange target move"
        elseif exchange.stage == "restore" then
            actionMember = exchangeMember
            actionTarget = exchange.source
            action = "exchange restore move"
        end
        if type(SetRaidSubgroup) ~= "function" then
            self.runtime.automaticGroupAssignment = nil
            self:PrivateWarning("SetRaidSubgroup is unavailable in this client.")
            return false
        end
        ok, result = pcall(SetRaidSubgroup, actionMember.raidIndex, actionTarget)
    elseif targetCount < 5 then
        if type(SetRaidSubgroup) ~= "function" then
            self.runtime.automaticGroupAssignment = nil
            self:PrivateWarning("SetRaidSubgroup is unavailable in this client.")
            return false
        end
        ok, result = pcall(SetRaidSubgroup, member.raidIndex, pending.target)
    else
        local swap = self:FindAutomaticGroupSwapCandidate(member, pending.target, roster)
        local buffer = self:FindAutomaticGroupBuffer(roster, from, pending.target)
        if not swap or not buffer or type(SetRaidSubgroup) ~= "function" then
            pending.attempts = pending.attempts - 1
            pending.nextAttemptAt = now + 1
            if pending.notice ~= "full" then
                pending.notice = "full"
                self:PrivateWarning(string.format("Group %d is full and no safe buffered exchange is available for %s.", pending.target, member.name))
            end
            return false
        end
        pending.exchange = {
            key = swap.key,
            name = swap.name,
            source = from,
            target = pending.target,
            buffer = buffer,
            stage = "buffer",
        }
        exchangeMember = swap
        actionMember = swap
        actionTarget = buffer
        action = "exchange buffer move"
        ok, result = pcall(SetRaidSubgroup, actionMember.raidIndex, actionTarget)
    end

    if not ok or result == false then
        self.runtime.automaticGroupAssignment = nil
        self:ClearAutomaticInviteGroupAssignment(pending.key)
        self:PrivateWarning("Ascension rejected the automatic subgroup " .. action .. " for " .. tostring(actionMember.name) .. ".")
        return false
    end
    pending.notice = nil
    pending.nextAttemptAt = now + AUTO_GROUP_CONFIRM_DELAY
    self:Print(string.format(
        "Automatic group %s sent: %s, Group %d -> Group %d (attempt %d).",
        action, actionMember.name, tonumber(actionMember.subgroup) or 1, actionTarget, pending.attempts
    ))
    return true
end
function MSR:GetGroupOptimizationRemaining(roster, optimization)
    local remaining = 0
    if not optimization then return remaining end
    for _, member in ipairs(roster or {}) do
        if optimization.desired[member.key] ~= member.subgroup then remaining = remaining + 1 end
    end
    return remaining
end

function MSR:FindNextGroupOptimizationAction(roster, desired)
    local groupCounts = {}
    for group = 1, 8 do groupCounts[group] = 0 end
    for _, member in ipairs(roster or {}) do
        local group = tonumber(member.subgroup) or 1
        if group >= 1 and group <= 8 then groupCounts[group] = groupCounts[group] + 1 end
    end

    -- First consume any free destination. Players already parked in a
    -- temporary group receive priority so the buffer never fills needlessly.
    for pass = 1, 2 do
        for _, member in ipairs(roster or {}) do
            local target = desired[member.key]
            local current = tonumber(member.subgroup) or 1
            local isBuffered = current >= 4
            if target and current ~= target and groupCounts[target] < 5
                and ((pass == 1 and isBuffered) or (pass == 2 and not isBuffered)) then
                return { member = member, target = target, kind = "direct" }
            end
        end
    end

    local mover
    for _, member in ipairs(roster or {}) do
        if desired[member.key] and desired[member.key] ~= member.subgroup then
            mover = member
            break
        end
    end
    if not mover then return nil end

    local target = desired[mover.key]
    local displaced
    for _, candidate in ipairs(roster or {}) do
        if candidate.subgroup == target and desired[candidate.key] ~= target then
            displaced = candidate
            break
        end
    end
    if not displaced then return nil, "No displaced player was found in full Group " .. tostring(target) .. "." end

    local bufferGroup
    for group = 4, 8 do
        if groupCounts[group] < 5 then bufferGroup = group break end
    end
    if not bufferGroup then return nil, "No temporary raid group is available as a move buffer." end

    return { member = displaced, target = bufferGroup, kind = "buffer" }
end

function MSR:ApplyGroupOptimizationAction(action, attempt)
    if not action or not action.member or not action.member.raidIndex then
        self:PrivateWarning("Unable to resolve the next raid member for group optimization.")
        return false
    end
    if type(SetRaidSubgroup) ~= "function" then
        self:PrivateWarning("SetRaidSubgroup is unavailable in this client.")
        return false
    end

    local from = tonumber(action.member.subgroup) or 1
    local ok, result = pcall(SetRaidSubgroup, action.member.raidIndex, action.target)
    if not ok or result == false then
        self:PrivateWarning("Ascension rejected the subgroup move for " .. tostring(action.member.name) .. ".")
        return false
    end

    self.runtime.groupOptimization.pending = {
        key = action.member.key,
        name = action.member.name,
        from = from,
        target = action.target,
        kind = action.kind,
        attempts = tonumber(attempt) or 1,
    }
    self:Print(string.format(
        "Group step sent: %s, Group %d -> Group %d. Click Optimize groups again to verify and continue.",
        tostring(action.member.name),
        from,
        action.target
    ))
    self:RefreshUI()
    return true
end

function MSR:GetGroupOptimizationStatus()
    local optimization = self.runtime and self.runtime.groupOptimization
    if not optimization then return "" end
    if optimization.pending then
        return string.format(
            "Group optimization: verify %s -> Group %d, then continue.",
            tostring(optimization.pending.name),
            optimization.pending.target
        )
    end
    if optimization.awaitingProtectedFinalize then
        return "Group positions are ready. Click Verify groups, then use the secure MT buttons for the Tanks."
    end
    return "Group optimization is ready for the next verified step."
end

function MSR:GetGroupOptimizationButtonLabel()
    local optimization = self.runtime and self.runtime.groupOptimization
    if not optimization then return "Optimize groups" end
    if optimization.awaitingProtectedFinalize then return "Verify groups" end
    return optimization.pending and "Verify / next" or "Next group step"
end

function MSR:OptimizeGroups(allowProtectedFinalize)
    if InCombatLockdown and InCombatLockdown() then self:PrivateWarning("Groups cannot be optimized during combat.") return false end
    if self.runtime.rebuild then self:PrivateWarning("Finish or cancel the raid rebuild before optimizing groups.") return false end
    if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then self:PrivateWarning("Convert the party to a raid first.") return false end
    if not (IsRaidLeader and IsRaidLeader()) then self:PrivateWarning("Only the raid leader can optimize groups.") return false end

    local roster = self:BuildRoster()
    local signature = self:GetGroupOptimizationSignature(roster)
    local optimization = self.runtime.groupOptimization
    if optimization and optimization.signature ~= signature then
        self:Print("Raid members, roles or Auras changed. Rebuilding the group optimization plan.")
        optimization = nil
        self.runtime.groupOptimization = nil
    end

    if not optimization then
        local reason
        optimization, reason = self:BuildGroupOptimizationPlan(roster)
        if not optimization then self:PrivateWarning(reason) return false end
        self.runtime.groupOptimization = optimization
    end

    if optimization.pending then
        local pending = optimization.pending
        local currentMember
        for _, member in ipairs(roster) do
            if member.key == pending.key then currentMember = member break end
        end
        if currentMember and currentMember.subgroup == pending.target then
            self:Print(string.format(
                "Group step confirmed: %s is now in Group %d.",
                tostring(currentMember.name),
                pending.target
            ))
            optimization.pending = nil
        else
            if not currentMember then
                self.runtime.groupOptimization = nil
                self:PrivateWarning("The pending player left the raid. Start group optimization again.")
                self:RefreshUI()
                return false
            end
            self:PrivateWarning(string.format(
                "The previous move for %s was not confirmed. Retrying it now.",
                tostring(currentMember.name)
            ))
            return self:ApplyGroupOptimizationAction({
                member = currentMember,
                target = pending.target,
                kind = pending.kind,
            }, (pending.attempts or 1) + 1)
        end
    end

    local remaining = self:GetGroupOptimizationRemaining(roster, optimization)
    if remaining == 0 then
        if not allowProtectedFinalize then
            optimization.awaitingProtectedFinalize = true
            self:Print("Raid groups are positioned. Click Verify groups once, then use the secure MT buttons for the Tanks.")
            self:RefreshUI()
            return true
        end
        if not self:MarkTanks(roster) then
            self:RefreshUI()
            return false
        end
        self.runtime.groupOptimization = nil
        self:Print("Raid groups verified and optimized: primary Tank first in Group 1, roles and Auras distributed across Groups 1-3. Use each Tank's secure MT button to promote them.")
        self:BuildRoster()
        self:RefreshUI()
        return true
    end

    local action, reason = self:FindNextGroupOptimizationAction(roster, optimization.desired)
    if not action then
        self:PrivateWarning(reason or "No valid next group move was found.")
        return false
    end
    return self:ApplyGroupOptimizationAction(action, 1)
end
