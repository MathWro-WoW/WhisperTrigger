# WhisperTrigger

A small World of Warcraft Retail addon that turns an incoming regular whisper into an interrupt reminder during **Rouse the Brood on Mythic The Twin Fangs** in **The Venomous Abyss**.

WhisperTrigger does not assign interrupts or send messages. Use it alongside whatever player or addon sends your interrupt-assignment whispers. It deliberately ignores the whisper's sender and text: **any regular whisper received during the active window triggers the reminder**. Battle.net whispers are not included.

## Installation

1. Download the addon ZIP from [GitHub Releases](https://github.com/MathWro-WoW/WhisperTrigger/releases).
2. Extract the `WhisperTrigger` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Confirm that `WhisperTrigger/WhisperTrigger.toc` is directly inside that folder, rather than an extra nested directory.
4. Enable WhisperTrigger in the game's addon list, then log in or run `/reload`.

Target client: Retail interface `120100` (12.1.0). Classic is not supported.

### Boss-mod requirements

Normal encounter operation requires **BigWigs or Deadly Boss Mods (DBM)** and its Twin Fangs encounter module to emit an identifiable Rouse the Brood timer.

- BigWigs: use its **Enhanced** encounter timers. Native timeline information is used when supplied by the custom bar, including pause/resume and completion updates.
- DBM: its named Rouse cooldown timer must be available. A Blizzard-only fallback that does not emit that timer will not activate WhisperTrigger.
- If both boss mods are loaded, the first matching timer provider owns the pull, preventing duplicate activation windows.
- Without a matching timer, normal alerts stay inactive. `/wt status` reports the current scope; test mode and Edit Mode preview remain available without either boss mod.

LibStub, LibEditMode, and LibCustomGlow are bundled. Falcon, AbilityTimeline, and Northern Sky do not need to be installed for the addon to load.

## When alerts activate

Outside test mode, all of these conditions must hold:

- Whisper alerts are enabled.
- You are fighting **The Twin Fangs on Mythic difficulty** in The Venomous Abyss.
- Your current class, talents, or pet provide a supported interrupt.
- You are inside a Rouse the Brood activation window.

The window opens **5 seconds before** the boss-mod countdown expires and closes **45 seconds afterward** by default. The post-countdown duration is configurable from **5 to 120 seconds**.

This is a timer-based window, **not detection that the broodlings are alive or dead**. Choose a duration that covers your group's interrupt assignments. Whispers received outside the window are ignored rather than queued.

A whisper displays your interrupt icon and plays the selected sound, if any. The reminder clears when:

- Your player or pet successfully casts a supported interrupt; it does not require confirmation that an enemy cast was interrupted.
- The icon timeout expires, **10 seconds** by default. Each new whisper restarts that timeout.
- The mechanic window closes, alerts are disabled, the encounter ends, or you leave the applicable scope.

## Configuration

Open **Esc → Edit Mode**, then click the **WhisperTrigger** preview frame. Drag the frame to reposition it.

| Setting | Behavior |
| --- | --- |
| Enable whisper alerts | Enables normal and test-mode whisper alerts. |
| Alert sound | None, a built-in sound, or a sound registered through LibSharedMedia by an enabled addon, including Northern Sky. Default: None. |
| Sound channel | Master, Effects (SFX), Music, Ambience, or Dialog. Default: Master. Applies to alerts and previews. |
| Glow style | None, Pixel Glow, Autocast Shine, Action Button Glow, or Proc Glow. Default: None. |
| Icon size | 32–160 pixels. Default: 72. |
| Timeout | Time before an individual reminder disappears, from 1–60 seconds. Default: 10. |
| Brood window | Seconds after the Rouse countdown expires during which whispers can trigger alerts, from 5–120 seconds. Default: 45. The lead-in remains 5 seconds. |

Selecting a sound or sound channel previews the current sound immediately. **Preview sound** plays it again. The selected channel follows the game's applicable mute and volume settings; the addon does not override them. A shared-media selection is retained if its provider is unavailable, but cannot play until that provider is loaded.

Settings and position follow named Edit Mode layouts, including layout copy, rename, and deletion. Settings save immediately through LibEditMode; they are not included in Blizzard's layout export or its Save/Revert transaction. Resetting settings and switching layouts do not preview sounds.

## Commands and testing

| Command | Effect |
| --- | --- |
| `/wt` or `/wt status` | Show the current activation status and configuration instructions. |
| `/wt test` | Toggle the scope bypass for this session. |
| `/wt test on` | Allow regular whispers to trigger alerts anywhere, without a boss-mod timer. |
| `/wt test off` | Restore the Mythic encounter and mechanic-window restrictions. |

`/whispertrigger` is the long command name. Test mode resets on reload and still respects **Enable whisper alerts** and interrupt availability.

To check the addon outside the raid, enable alerts, leave Edit Mode, run `/wt test on`, and have another player send a regular whisper. Confirm the icon, sound, timeout, and interrupt-cast dismissal, then run `/wt test off`. Edit Mode itself shows a configuration preview and does not process incoming whispers as alerts.

## Development checks

From the addon directory, with Lua 5.1 installed:

```sh
lua tests/brood-window.lua
luac -p Core.lua BroodWindow.lua EditMode.lua Interrupts.lua tests/brood-window.lua
```

The regression scenarios exercise encounter scope, boss-mod callbacks, timing boundaries, pause/resume, cancellation, overlapping windows, layout persistence, and cleanup using WoW API stand-ins. They do not replace in-game testing of rendering, audio output, or a live encounter.

Bundled libraries retain their own licenses and copyright notices under `Libs/`.
