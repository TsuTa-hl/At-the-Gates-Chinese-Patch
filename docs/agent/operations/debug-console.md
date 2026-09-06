# In-Game Debug Console

This topic records the built-in console interface and command surface exposed
by `AtTheGatesGame.DebugConsoleNS.DebugConsole`. Use it as an optional
diagnostic aid; it is not a replacement for scenario coordinates, SQLite
source lookup, or visual evidence.

## Source Authority

- Command list: `source/AtTheGatesGame.original.exe`,
  `DebugConsole.BuildCommandList`, token `0x06000412`.
- Command parser: `DebugConsole.TryConsoleCommand`, token `0x06000413`.
- Console input: `DebugConsole.TestConsoleInput` and its helpers, tokens
  `0x06000472` through `0x0600047D`.
- The parser uppercases the complete input before matching it, so commands and
  their game-data arguments reach handlers in normalized uppercase form.
- `help`, `list`, or `commands` prints the game's own command list.

## Opening and Navigation

| Input | Effect |
| --- | --- |
| `~` / OEM8 | Toggle the console. The second key covers keyboard layouts where the tilde key reports as OEM8. |
| `Ctrl+C` | Alternate console toggle. |
| `Esc` | Close the console. |
| `Enter` | Submit the command. |
| `Up` / `Down` | Scroll console output. |
| `Page Up` / `Page Down` | Scroll console output by a larger step. |
| `Left` / `Right` | Move backward or forward through command history. |

For screenshot-assisted UI localization, enable the persistent mouse-coordinate
setting explicitly, close the console, hover the target, and keep the capture
uncropped:

```text
set ShowMousePosition true
```

Restore it when no longer needed:

```text
set ShowMousePosition false
```

The coordinates are relative to the game window. The built-in console does not
expose UI control IDs or names. `debug overlay` is a map-tile data overlay, not
a UI widget inspector.

## Safety Classes

- **Observe** prints information or changes only the current diagnostic view.
- **Setting** changes a user setting and may persist through `Settings.Save()`.
- **Automation** records, replays, or advances gameplay; use only with explicit
  black-box authorization.
- **World mutation** changes game state, ownership, research, resources, map
  objects, or the selected player. Use only on an approved disposable state or
  a scenario that explicitly requires it.
- `quit` terminates the process. `fixed` and `random` rebuild the map.
  `lock settings` changes whether the game can overwrite `Settings.xml`.

## Console and System Commands

| Command | Function | Class |
| --- | --- | --- |
| `help`, `list`, `commands` | Print the built-in command list. | Observe |
| `reload` | Rebuild the console. | Observe |
| `size` | Cycle tiny, normal, and full console sizes. | Observe |
| `quit` | Terminate the application. | Process control |
| `set [SETTING] [VALUE]` | Set a user setting. For a Boolean setting, omitting the value toggles it; prefer explicit `true` or `false`. | Setting |
| `borderlesswindow` | Toggle borderless-window mode. | Setting |
| `debug` | Toggle debug mode. | Setting |
| `art` | Toggle art mode, which allows items to be hidden. | Setting |
| `quickload` | Toggle quickload and disable quickstart. | Setting |
| `quickstart` | Set quickstart to the tiny map size and disable quickload. | Setting |
| `quickstart [SIZE]` | Set the quickstart map size and disable quickload. | Setting |
| `quickstart off` | Disable quickload and quickstart. | Setting |
| `fixed` | Rebuild the standard-size fixed-seed map. | World mutation |
| `fixed [SIZE]` | Rebuild a fixed-seed map of the requested size. | World mutation |
| `random` | Build a standard-size random map. | World mutation |
| `random [SIZE]` | Build a random map of the requested size. | World mutation |
| `hijack` | Toggle the `NeverBlockTurn` setting. | Setting |
| `framerate` | Toggle the frame-rate counter. | Observe |
| `debug texture` | Toggle the world render-target debug texture. | Observe |
| `dirty` | Set every UI dirty bit to `true`. | Observe |
| `lock settings` | Toggle the game's ability to overwrite `Settings.xml`. | Setting |

The hidden command `.` submits `switch player`, `watch The Huns`, and `v` in
sequence. It is a hard-coded developer macro, changes the active state, and
contains no dedicated help entry; do not use it for black-box localization.

## Tile, Input, Camera, and Drawing Commands

| Command | Function | Class |
| --- | --- | --- |
| `debug overlay` | Toggle the tile debug overlay. | Observe |
| `debug overlay [#]-[#]` | Set the tile-overlay tree-depth range. | Observe |
| `debug overlay cycle [#]` | Cycle overlay mode 1 through 3 at the requested tree depth. | Observe |
| `debug overlay extra info` | Toggle extra overlay details where supported. | Observe |
| `debug overlay alternate info` | Toggle alternate overlay details where supported. | Observe |
| `debug overlay simple info` | Toggle simplified overlay details where supported. | Observe |
| `recordings` | List files in the `Recordings` folder. | Observe |
| `record` | Record input to a timestamped file. Close the console and press `Pause` to stop. | Automation |
| `record [FILE]` | Record input to the named file. Close the console and press `Pause` to stop. | Automation |
| `play` | Replay the most recent input recording. | Automation |
| `play [FILE]` | Replay the named input recording. | Automation |
| `play x[#] [FILE]` | Replay the optional file at the requested speed, such as `x0.5`. | Automation |
| `play max [FILE]` | Replay the optional file at maximum speed. | Automation |
| `look [X],[Y]` | Move the camera to the tile coordinates. | Observe |
| `look center` | Move the camera to the map center. | Observe |
| `zoom in [#]` | Zoom in by the requested number of steps. | Observe |
| `zoom out [#]` | Zoom out by the requested number of steps. | Observe |
| `watch [FACTION]` | Center the camera on the faction capital. | Observe |
| `switch player` | Switch the human controller to the next player. | World mutation |
| `switch player [FACTION]` | Switch the human controller to the named faction. | World mutation |
| `rng` | Print the random-number seed and call count. | Observe |
| `skip [#]` | Skip the requested number of turns for all players. | Automation |
| `hide ui` | Toggle drawing of the UI, including the cursor. | Observe |
| `hide cursor` | Toggle cursor drawing. | Observe |
| `hide world` | Toggle `AtGWorldScreen.Draw()`. | Observe |

The help output also shows `[ PAUSE KEY ]` as a reminder row. It is not a
typed command; with the console closed, press `Pause` to stop input recording.

## Tile Highlight Commands

An optional color-name prefix can be added to highlight commands with
`hl [COLOR] ...`.

| Command | Function |
| --- | --- |
| `hl off` | Remove all tile highlights. |
| `hl players` | Highlight tiles containing owned structures. |
| `hl control` | Highlight player-controlled tiles. |
| `hl bandits` | Highlight tiles containing bandit camps. |
| `hl trait [TRAIT_ID]` | Highlight tiles containing the zone-trait ID. |
| `hl trait valid [TRAIT_ID]` | Highlight tiles valid for the zone-trait ID. |
| `hl dtype [DTYPE_ID]` | Highlight tiles containing the deposit-type ID. |
| `hl food` | Highlight tiles containing food. |
| `hl visible food` | Highlight food visible at game start. |
| `hl hidden food` | Highlight food hidden at game start. |
| `hl food except [RES_ID]` | Highlight food except the specified resource ID. |

These are Observe commands, but they apply to map tiles rather than UI
controls.

## AI, Vision, and Clan Commands

These commands change gameplay state or advance simulation and therefore
require explicit black-box authorization.

| Command | Function |
| --- | --- |
| `autoplay` | Give AI control until the current turn is exhausted. |
| `autoplay to first series` | Let the AI play the turn plus one directive series. |
| `autoplay one series` | Execute one AI directive series. |
| `autoplay [#]` | Give AI control of the tribe for the requested number of turns. |
| `reveal` | Toggle map visibility. |
| `reveal start` | Reveal the three zone rings around the capital. |
| `unshroud` | Cycle shroud state for the selected deposit. |
| `unshroud all` | Cycle global deposit vision: default, reveal, or complete. |
| `level [CLAN] [DSPLN] [#]` | Increase the clan's discipline level by the requested amount. |
| `xp [CLAN] [DSPLN] [#]` | Change the clan's discipline experience by the requested amount. |
| `families [CLAN] [#]` | Set the clan's number of families. |
| `trait [CLAN] [TRAIT]` | Add and apply a trait to the clan. |
| `trait [CLAN] [TRAIT] remove` | Remove and unapply a trait from the clan. |
| `ennoble [CLAN]` | Make the clan noble. |
| `ennoble [CLAN] remove` | Remove noble status from the clan. |

## Training and Technology Commands

All commands in this section mutate gameplay state.

| Command | Function |
| --- | --- |
| `finish training` | Finish the capital's current training project. |
| `make [UNIT]` | Immediately retrain capital clan index 0 as the unit. |
| `make [UNIT] [i#]` | Immediately retrain the indexed capital clan as the unit. |
| `make [CLAN] [UNIT]` | Immediately retrain the named clan as the unit. |
| `train [UNIT]` | Start training capital clan index 0 as the unit. |
| `train [UNIT] [i#]` | Start training the indexed capital clan as the unit. |
| `train [CLAN] [UNIT]` | Start training the named clan as the unit. |
| `finish research` | Learn the technology currently being researched. |
| `tech [TECH]` | Learn the named technology. |
| `techs` | Learn every technology. |
| `forget tech [TECH]` | Forget the named technology. |
| `forget techs` | Forget every technology. |

## Resource and World-Object Commands

All commands in this section mutate gameplay state. Commands referring to the
mouseover tile require the cursor to be over a valid map tile.

| Command | Function |
| --- | --- |
| `resource [RESOURCE] [#]` | Set the stockpiled resource quantity. |
| `resources [#]` | Set every stockpiled resource quantity. |
| `harvest max [#]` | Set the selected structure or deposit's original harvest quantity. |
| `harvest remaining [#]` | Set its remaining harvest quantity. |
| `harvest max x[#]` | Multiply all original harvest quantities. |
| `unit [UNIT]` | Create the unit on the mouseover tile. |
| `structure [STRUCTURE]` | Create the structure on the mouseover tile. |
| `bandit unit [UNIT]` | Create a bandit unit on the mouseover tile. |
| `bandit structure [STRUCTURE]` | Create a bandit structure on the mouseover tile. |
| `deposit [DEPOSIT]` | Create the deposit on the mouseover tile. |
| `remove road` | Remove the road on the mouseover tile. |
| `move` | Teleport the selected object to the mouseover tile. |
| `split` | Split the selected army. |
| `health [%]` | Change selected-object health by a percentage of 100. |
| `morale [%]` | Change selected-object morale by a percentage of 100. |
| `control [#]` | Set selected-object control range. |

`id` is the read-only exception in this group: it prints the selected object's
world ID. It does not print an ElfTools UI-control ID.

## Lists, Cities, and Diplomacy

| Command | Function | Class |
| --- | --- | --- |
| `count dtypes` | Print the count of each deposit type on the map. | Observe |
| `list units` | Print the unit list. | Observe |
| `list structures` | Print the structure list. | Observe |
| `list techs` | Print the technology list. | Observe |
| `list deposits` | Print the resource-deposit list. | Observe |
| `list resources` | Print the stockpile-resource list. | Observe |
| `list players` | Print the player list. | Observe |
| `list cities` | Print the city list. | Observe |
| `city goto [CITY ID]` | Center the camera on the city. | Observe |
| `city info [CITY ID]` | Print information about the city. | Observe |
| `city occupy [CITY ID] BY [PLAYER]` | Change city ownership by occupation. | World mutation |
| `influence [#]` | Increase active-player influence with the selected object's owner. | World mutation |
| `war status` | Print current wars. | Observe |
| `war declare [DECLARING_PLAYER] [DECLARED_UPON1,DECLARED_UPON2,...|EVERYONE]` | Make one player declare war on the listed players. The help list displays `war decalare [DECLARING_PLAYER] [DECLARED_UPON1,DECLARED_UPON2,...|EVERYONE]`, but the parser accepts only `war declare`. | World mutation |
| `inv status` | Print current invasions. | Observe |
| `inv status [INVASION ID]` | Print details for one invasion. | Observe |

## Black-Box Use

Follow the ordered procedure in
[game-automation.md](game-automation.md#console-assisted-target-triage). This
command reference owns only the following console-specific boundaries:

1. Prefer camera movement, visual toggles, and read-only list/status commands.
   A console command does not expand scenario authorization; Automation and
   World mutation commands require an explicitly selected disposable state.
2. Restore persistent diagnostic settings after capture and close the console
   before localization assertions.
3. Treat `record`/`play` as a temporary aid for a user-authorized manual path.
   Convert a useful path to structured scenario actions instead of retaining
   the recording as test authority.
4. Do not interpret `debug overlay` or `id` as UI-control identification.
   Screenshot coordinates still require static UI-source routing and direct
   SQLite lookup.
