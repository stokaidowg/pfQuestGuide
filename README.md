# pfQuest Guide

A small add-on for [pfQuest](https://github.com/shagu/pfQuest) on vanilla (1.12) servers such as **OctoWoW** and **Turtle WoW**.

Pick one quest and pfQuest Guide takes it from there:

- **The arrow follows that quest.** pfQuest's arrow points at the nearest spot that still matters for it: a mob that drops what you need, the vendor that sells it, or the NPC you turn it in to.
- **One click targets the quest's mobs and NPCs.** Each objective gets an icon (or a button in the full window) that targets the nearest living, untapped match.
- **Quest targets get raid icons.** When you target a mob or NPC the guided quest still needs, it's marked automatically: star, circle, diamond, triangle, moon, square, cross, skull. Once all eight are in use, the one used longest ago moves to your new target. Anything unrelated to the quest is left alone.

## Example

On *Beer Basted Boar Ribs* (Dun Morogh) you'd see:

| Objective | Icon | Click it to... |
| --- | --- | --- |
| Crag Boar Rib 2/6 | Crag Boar portrait (rib badge) | target the nearest Crag Boar, Large Crag Boar, ... |
| Rhapsody Malt 0/1 | Innkeeper Belm portrait (coin badge) | target Innkeeper Belm |
| *(quest complete)* | Ragnar Thunderbrew portrait (**?** badge) | target Ragnar Thunderbrew to turn in |

## Requirements

- **pfQuest** (required). Works with **pfQuest-octo** / **pfQuest-turtle**, but doesn't need them.
- **pfUI** (optional). Without it, the window uses Blizzard-style borders.
- **TourGuideVanilla** (optional). pfQuest Guide follows its current step.

## Install

1. Download `pfQuestGuide-x.y.zip` from the [Releases](../../releases) page. Don't use GitHub's green **Code → Download ZIP** button: it gives a folder named `pfQuestGuide-main`, which WoW won't load until you rename it to `pfQuestGuide`.
2. Extract it into `Interface\AddOns`, so you end up with `Interface\AddOns\pfQuestGuide\pfQuestGuide.toc`.
3. Restart the game, or type `/reload` if you're already logged in.

## Usage

**Choosing a quest**

- **Alt-click** a quest in the pfQuest tracker or in the quest log, or
- **Ctrl-click** any icon (or click the title bar of the full window) to pick from a list.

The guided quest gets a yellow `>` in the pfQuest tracker, and your choice is remembered per character.

**With TourGuide**: if [TourGuideVanilla](https://github.com/cralor/TourGuideVanilla) is installed, pfQuest Guide follows its current step automatically. Quest steps (accept, complete, turn in, and kill/note steps tied to a quest) switch the guided quest. *Accept* steps point the arrow at the quest giver with a **!** icon to target them, and switch to the quest's objectives once you've accepted it. Kill, loot and buy steps aim the arrow at the exact objective they're about. Travel, hearth and flight-path steps that have coordinates in their note, like "(30.3, 46.3)", point the arrow there and show a tracking icon. Click that icon to point the arrow back at the quest. Steps without coordinates leave the current quest alone. A quest you pick by hand stays until TourGuide moves on to its next step. Turn this off or on with `/pqg tourguide`.

**Mini view** (default): one icon per objective you still need.

- **Click**: target and raid-mark the nearest matching mob/NPC.
- **Right-click**: point the arrow only at this objective (gold border). Right-click again to follow all objectives.
- **Hover**: see the objective and which mobs/NPCs it will try.
- **Drag**: move. **+**: switch to the full window.

Icons show the creature's portrait once you've targeted or moused over one this session (the game can only draw portraits of creatures that are present). Until then they show the quest item, a sword (kill) or a coin (buy). A small badge in the corner says what the icon is for: the item to collect, a coin to buy, or **?** to turn in.

**Full view**: every objective with a text button per mob/NPC, including zone hints for ones elsewhere. **–** shrinks it back to icons, **x** hides it.

**Key binding**: *Key Bindings → pfQuest Guide → Target next quest mob / NPC* targets the next quest target (the focused objective first).

**Commands**

| Command | Does |
| --- | --- |
| `/pqg` | show or hide the window |
| `/pqg target` | same as the key binding (macro-friendly) |
| `/pqg clear` | stop guiding the current quest |
| `/pqg tourguide` | turn following TourGuide's current quest on or off |
| `/pqg marks` | hand out raid icons from star again |
| `/pqg help` | list the commands |

## Notes

- **Map clicks:** clicking a node on the world map hands pfQuest's arrow back to that node. A map icon appears in the guide. Click it to point the arrow at your quest again.
- **pfUI Mark Tracking:** pfUI shows a health bar for every raid-marked unit, which you'll see a lot once every target is marked. Disable it under `/pfui` → *Components → Modules* → *Disable Module marktracking*, or move it with `/pfui unlock`.
- **pfQuest bug:** pfQuest Guide also fixes a pfQuest error (`map.lua: attempt to perform arithmetic on field 'queue_update'`) that appears when the arrow target changes.
- **Collapsed quest log headers:** if the guided quest's zone is collapsed in your quest log, the guide asks you to expand it, because the game doesn't report objectives for hidden quests.

## Bugs and ideas

Please open an [issue](../../issues) with a screenshot and the quest name.

## License

MIT. See [LICENSE](LICENSE).
