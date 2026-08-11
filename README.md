# Manastorm Recruiter

Manastorm Recruiter is an unofficial World of Warcraft addon for Project Ascension's WoW 3.3.5 client. It helps a raid leader recruit players, track roles and Manastorm Auras, arrange a 15-player raid, monitor the run, rebuild the raid at level 60, and leave cleanly.

## Compatibility

- Project Ascension
- WoW 3.3.5 interface `30300`
- English client communication

This is an unofficial community project. It is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment or Project Ascension.

## Installation

1. Download the release ZIP.
2. Extract it so the addon directory is named `ManastormRecruiter`.
3. Copy that directory to `ascension-live\Interface\AddOns\`.
4. Restart WoW completely, or reload AddOns from the character selection screen.
5. Enter `/msr` in game.

A movable minimap button can also show or hide the addon window.

## Complete Workflow

The addon keeps recruitment, waiting players, raid groups, group chat, warnings, and the current actions in one window. Follow the steps below from recruiting to leaving.

### 1. Prepare Recruiting

1. Open the addon with `/msr`.
2. Open **Settings**.
3. Enter the recruitment channel as its current number, such as `8`, or as its name.
4. Set **Your slot** to Tank, Heal, or DPS.
5. Enable **Aura** if your own character has a Manastorm Aura. Your character counts toward the roster targets.
6. Check the target values. The defaults are 2 Tanks, 3 Healers, 10 DPS, 3 Auras, and 15 players in total.
7. Set the automatic post interval.
8. Leave **Auto reply** enabled if the addon should answer applicants automatically.
9. Configure **Aura reserve** if the final Tank, Healer, or DPS slots should be held for players with a missing Aura. The T, H, and D buttons select the affected roles.

Use **Edit messages** when you want to change recruitment posts, automatic replies, roster messages, warnings, or leave messages. Customized messages are marked with `*`, and **Use default** restores the selected message.

### 2. Start Recruiting

1. Click the red **Recruiting: OFF** button.
2. The addon immediately posts the current recruitment message to the configured channel.
3. Whisper listening and automatic recruitment posts start together.
4. The button turns green and reads **Recruiting: ON**.

The message always uses the live roster and pending-invite counts. Its **Need** section lists only missing roles and Auras. If Aura reservation is active, the message also explains which remaining role slots require an Aura.

Click the green button again to stop both automatic posts and applicant listening. Recruiting also stops automatically when Manastorm starts.

### 3. Receive Applicant Whispers

Applicants can whisper simple English messages such as:

- `tank aura yes level 42`
- `heal no aura 37`
- `dps yes`
- `rdps aura 51`

The parser recognizes common Tank, Heal, and DPS terms, an Aura yes/no answer, and a level from 1 to 60. If information is missing, the addon asks for it in this order:

1. Role
2. Manastorm Aura
3. Level

Short follow-up answers such as `yes`, `no`, `42`, `level 42`, or `lvl 42` update the same applicant. A missing level is shown as `Lv ?` and does not block an invite.

When automatic replies are enabled, the addon also explains when:

- the raid is full;
- the requested role is full;
- a remaining slot is reserved for an Aura player; or
- the raid is already inside Manastorm.

Duplicate automatic replies are suppressed until the applicant's situation changes.

### 4. Review and Manage Waiting Players

The **Waiting** tab shows each applicant's name, level, role, Aura, and status.

1. Click the role button to cycle between Tank, Heal, and DPS.
2. Click the Aura button to correct Aura Yes/No.
3. Click **Invite** to reserve the slot and send a group invitation.
4. Click **Reserve** to keep the applicant for later without inviting.
5. Click **X** to reject and hide the applicant.

The waiting list prioritizes pending invites, currently needed roles, missing Auras, complete applications, and recent activity. While you edit a role or Aura, the order stays frozen for five seconds so the row does not move under the cursor.

Pending invitations already count as occupied roster slots. The addon blocks invitations that would exceed the raid, role, or Aura-reservation limits. If necessary, it converts an existing party to a raid before inviting.

After five seconds without an answer, the applicant receives the configurable invite reminder. After ten seconds, the local reservation is released and the row offers **Reinvite**. **Release** frees the local reservation immediately; WoW 3.3.5 cannot reliably retract an invitation that has already been sent.

The **In raid** tab shows applicants who joined. Players invited manually outside the addon are added to the same editable roster when detected.

### 5. Check the Raid While It Is Forming

The raid overview displays Groups 1-3 with every player's role, level, Aura, Ready Check state, and subgroup.

- **Post roster** sends the current role and Aura totals plus all missing slots to raid or party chat.
- **Group chat** displays up to 100 recent Party, Raid, and Raid Warning messages for the current login session. Enter text and press Enter or **Send** to reply to the active group channel.
- The small **X** beside a raid member removes that player. It is unavailable for your own row, without leader or assistant permission, during combat, or during an active rebuild.
- **Disband raid** removes every other group member after confirmation. It does not start the reinvite workflow.
- **Reset session** clears applicants, their stored whispers and statuses, alerts, and cached rebuild data after confirmation. It keeps your addon settings and customized messages.

### 6. Optimize the Raid Groups

Click **Optimize groups** as raid leader. The addon supports both partial and complete rosters, but the final 15-player arrangement is:

- Group 1: 1 Tank, 1 Healer, 3 DPS
- Group 2: 1 Tank, 1 Healer, 3 DPS
- Group 3: 1 Healer, 4 DPS
- At least one Aura player in each group

WoW confirms subgroup moves asynchronously, so optimization is intentionally step based:

1. Click **Optimize groups** to send the next move.
2. Click **Verify / next** to confirm it and continue.
3. Repeat until all moves are confirmed.

If a group is full, Groups 4-8 can be used temporarily as a safe move buffer. When optimization finishes, all stored Tanks receive the main-tank assignment equivalent to `/mt`. The primary Tank is placed first in Group 1 and marked with Raid Target 1, the star. If Ascension rejects a protected operation, click the optimization button again to retry.

### 7. Run an Optional Ready Check

1. Click **Ready Check** as group leader.
2. Each raid row shows `R` for ready, `N` for not ready, or `?` for no answer.
3. The summary lists the ready count and outstanding names.

The Ready Check never blocks entry. If the roster changes, the result becomes stale, but **Start MS Lv 1** remains available.

### 8. Start Manastorm Level 1

Click **Start MS Lv 1** as group leader. The action is available when you are not already inside Manastorm and no raid rebuild is active.

The addon sends Ascension's Level 1 entry request even if the optional Ready Check failed or roster warnings remain. After the request succeeds, it:

1. stops automatic posts;
2. stops applicant listening;
3. clears waiting applicants; and
4. keeps joined raid members with their Role and Aura assignments.

While inside Manastorm, later whispers receive the configurable **Already in Manastorm** reply and are not added as applicants.

### 9. Monitor the Manastorm Run

During the run, the addon continuously checks:

- total player count;
- Tank, Healer, and DPS counts;
- missing Auras;
- unknown roles; and
- Groups 1-3 without an Aura player.

Changed problems are shown as local warnings. The raid overview continues to display levels, roles, Auras, and group placement.

When a player first reaches level 59, the addon sends the configurable level 59 Raid Warning once. When a player reaches level 60 or above, it sends the configurable level 60 Raid Warning once and marks the raid as needing a rebuild.

### 10. Rebuild the Raid

Use **Rebuild raid** as raid leader when players need to be replaced after reaching level 60.

1. Confirm the rebuild.
2. The addon saves the current roster and sends the configurable rebuild Raid Warning.
3. A five-second countdown starts. **Cancel rebuild** is available only during this countdown.
4. Click **Remove all** once when prompted. The addon removes every other raid member and verifies the result.
5. If currently inside Manastorm, click **Leave Manastorm** when prompted.
6. After the exit is confirmed, the addon waits three seconds and sends reinvites.
7. Players at level 60 or above are removed but deliberately not reinvited.
8. Failed protected actions remain available as local **Remove**, **Invite**, or **Leave Manastorm** retry buttons.
9. Once reinvites have been sent, recruiting becomes available again so missing players can be replaced immediately.
10. When everyone returns, the addon optimizes the groups again. The final waiting stage ends after ten seconds if players are still missing.

The roster and rebuild stage are stored in SavedVariables. After `/reload` or a client restart, the addon offers to resume or discard an unfinished rebuild.

### 11. Post the Final Status and Leave

**Post & Leave** is the final workflow action and is available while grouped at every level.

1. The addon selects the configured message for Level 60, Level 59, or below Level 59.
2. It posts the message to raid or party chat with the current role totals, Aura totals, Aura-player names, and your level where applicable.
3. It waits one second so Ascension processes the chat message first.
4. If you are inside Manastorm, it requests the Manastorm exit and waits for confirmation.
5. It then leaves the party or raid. Raid leadership passes according to the game's normal rules.

If you are inside Manastorm but no longer grouped, the same action is shown as **Leave MS** and only requests the Manastorm exit. If an exit cannot be confirmed, the addon keeps you in the group and asks you to finish manually instead of risking the wrong order.

## Window Controls

- **Settings** opens or closes the setup panel.
- **Compact** scales the complete window down.
- The window automatically scales to fit smaller resolutions.
- The minimap button opens or hides the window and can be dragged around the minimap.
- The top-right status follows the detected recruitment, raid, Manastorm, and rebuild state.

## Custom Message Placeholders

The message editor supports:

- Missing requirements: `{needed}`, `{tankNeeded}`, `{healNeeded}`, `{dpsNeeded}`, `{auraNeeded}`
- Current and target values: `{tank}`, `{tankMax}`, `{heal}`, `{healMax}`, `{dps}`, `{dpsMax}`, `{aura}`, `{auraMax}`, `{total}`, `{totalMax}`
- Context values: `{role}`, `{rolePlural}`, `{roles}`, `{player}`, `{level}`, `{seconds}`, `{auraPlayers}`, `{missingAura}`, `{reservation}`, `{status}`

`{needed}` creates a compact list containing only values that are still missing.

## Commands

- `/msr` or `/manastormrecruiter` - Show or hide the window
- `/msr post` - Post the recruitment message once
- `/msr listen` - Toggle applicant whisper detection
- `/msr optimize` - Continue raid-group optimization
- `/msr testwhisper dps aura yes` - Simulate an applicant without another player
- `/msr test59 Testplayer` - Test the local level 59 warning
- `/msr test60 Testplayer` - Test the local level 60 warning
- `/msr reset` - Open the session-reset confirmation

## Privacy and Local Data

Manastorm Recruiter has no telemetry, analytics, external network requests, accounts, or API keys. It communicates only through the WoW and Project Ascension APIs available inside the game client.

The addon stores these values locally in WoW SavedVariables:

- settings and customized message templates;
- applicant and raid-member names;
- recent applicant whispers;
- role, Aura, level, and invitation status;
- level-warning state; and
- rebuild recovery data.

Use **Reset session** or `/msr reset` to clear the current applicants, stored whispers, statuses, warnings, and rebuild recovery data. To remove all settings as well, uninstall the addon and delete its `ManastormRecruiter.lua` and `ManastormRecruiter.lua.bak` files from the account and character `WTF` SavedVariables directories.

No SavedVariables, game logs, screenshots, or player data are included in this repository or its release packages.

## Development and Testing

The source is split by responsibility:

- `Core.lua` - database, shared helpers, event dispatch, and update loop
- `Parser.lua` - whisper parsing, applicant history, and reply deduplication
- `Roster.lua` - roster state, capacity rules, and group optimization
- `Recruitment.lua` - recruitment posts, invite timers, applicant ordering, and group chat
- `Manastorm.lua` - Ready Check, entry, monitoring, warnings, and Post & Leave
- `Rebuild.lua` - rebuild checkpoint, recovery, removal, exit, and reinvite state machine
- `UI.lua` - window layout, panels, rows, dialogs, scaling, and contextual actions

Run the automated tests from the repository root with a compatible Lua runner:

```text
lua tests/CoreTests.lua
lua tests/UITests.lua
```

The automated tests cover the core state transitions and the constructed UI. Invitation, subgroup, Ready Check, Manastorm, and protected raid actions must also be validated in the real Project Ascension client with test players before using them on a live raid.

## Release Packaging

A release archive must contain one top-level directory named `ManastormRecruiter`. That directory contains the `.toc` file and all Lua source files. Tests and repository-maintenance files are not required in the installed addon directory.

## License

Copyright (C) 2026 Tomatensalat91

This project is licensed under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
