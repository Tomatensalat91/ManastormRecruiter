# Manastorm Auto Group Test

Small Project Ascension / WoW 3.3.5 test addon for one question: can an invited
player be moved to the Manastorm Recruiter target group immediately after joining,
without clicking another button?

The addon is intentionally separate from the production addon. It observes normal
Manastorm Recruiter invitations, calculates the invited player's target with the
existing group planner, waits for `RAID_ROSTER_UPDATE`, calls `SetRaidSubgroup`,
and verifies the result against the next real raid roster.

Aura placement has priority over the generic partial-raid planner: if Group 1 is
already covered by an Aura, the next invited Aura is planned for Group 2, then
Group 3. On reload, the addon also detects an existing duplicate Aura in one group
so the API behavior can be retested without another invite.

## Install

Copy the `ManastormAutoGroupTest` directory next to `ManastormRecruiter`:

```text
E:\ascension-live\Interface\AddOns\ManastormAutoGroupTest\
```

Restart Ascension or reload the UI. The addon requires Manastorm Recruiter and is
enabled by default.

## Test

1. Be raid leader or raid assistant and stay out of combat.
2. Run `/magt status`. It should report `SetRaidSubgroup available`.
3. Make sure the calculated destination group has fewer than five players.
4. Invite a reviewed applicant normally from Manastorm Recruiter.
5. After the player accepts, do not click any group or optimization button.
6. Watch the chat for these messages:

```text
Planned Player for Group 2 ...
Automatic API call sent: Player, Group 1 -> Group 2 ...
CONFIRMED: Player is in Group 2 without an extra button click.
```

`CONFIRMED` is the successful proof. An accepted Lua call alone is not treated as
success; the group must also be visible in a later raid roster update.

For a controlled test target, run `/magt plan Playername 2` before inviting. This
does not add a post-invite click; it only overrides the calculated destination.

## Commands

- `/magt status` shows API, permissions, raid size, and all move states.
- `/magt plan <player> <1-8>` sets an explicit target for a controlled test.
- `/magt retry` retries failed moves from the start.
- `/magt log` prints the last 15 persistent test messages.
- `/magt clear` clears the session plans and persistent test log.
- `/magt on` and `/magt off` enable or disable automatic moves.

The addon only moves a planned invite or one duplicate Aura player used by this
test, and never moves anyone during combat. If the target group is full, it waits
instead of displacing a player.
