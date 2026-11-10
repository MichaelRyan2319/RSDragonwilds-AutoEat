# Auto Eat for RuneScape: Dragonwilds

A UE4SS Lua mod for RuneScape: Dragonwilds. It eats and drinks for you when
you get hungry or thirsty.

- The inventory gets a fifth tab, after Items, Runes, Ammunition and Quest
  Items: **Auto Eat** (the fork-and-knife icon).
- The tab has two slots, one for a **food** and one for a **drink**, and under
  them the food and drink you are carrying. Click one in the list to put it in
  its slot. Click a slot to empty it.
- When your hunger falls to the level set next to the food slot, the mod eats
  one of that food from your bag. Thirst and the drink slot work the same way.
  The level starts at 50% and the **-** and **+** next to it change it in steps
  of 5.
- The slots hold a choice, not the items. The food stays in your bag, and the
  slot shows how many you have left. When it runs out the slot keeps your
  choice and says "none left"; it carries on when you pick up more.
- **ON / OFF** in the tab's top right corner switches the whole thing off
  without losing your choices.
- Choices and levels are saved per character.
- Eating and drinking go through the game's own "use item", the same as
  clicking Eat or Drink yourself. If the game won't let you eat at that moment,
  nothing happens and the mod tries again a little later.
- Client-side only. Other players and servers don't need it.
- Doesn't change any world settings, so achievements keep working.

Built for game build 26162923 (Unreal Engine 5.6) with UE4SS v3.0.1-1217.

## Requirements

- [UE4SS for RuneScape: Dragonwilds](https://github.com/MichaelRyan2319/RSDragonwilds-UE4SS).
  Any other UE4SS v3 install works too.

## Install with Mod Loader

[Mod Loader](https://github.com/MichaelRyan2319/ModLoader) installs the mod and
keeps it up to date.

1. **Add game** and pick RuneScape: Dragonwilds. Mod Loader 1.0.1 or later sets
   the mods folder to the game's inner `RSDragonwilds` folder (the one with
   `Binaries` and `Content` in it). If you added the game with an older version,
   edit it and choose that folder.
2. **Add mod** `MichaelRyan2319/RSDragonwilds-AutoEat`. The mod needs UE4SS, so
   Mod Loader 1.1.0 or later offers to add `MichaelRyan2319/RSDragonwilds-UE4SS`
   as well; click **Yes**. With an older Mod Loader, add
   `MichaelRyan2319/RSDragonwilds-UE4SS` yourself first.
3. Start the game, load a world and open your inventory.

## Install by hand

1. Install UE4SS (see Requirements).
2. Download `AutoEat.zip` from the [Releases](../../releases) page.
   In Steam, right-click RuneScape: Dragonwilds > Manage > Browse local files,
   then open the `RSDragonwilds` folder (the one with `Binaries` and `Content`
   in it) and extract the zip there. The mod ends up in
   `Binaries\Win64\ue4ss\Mods\AutoEat`.
3. Start the game, load a world and open your inventory.

The mod folder contains `enabled.txt`, so UE4SS loads it without any change to
`mods.txt`. To install from this repo instead of a release, copy the `AutoEat`
folder into `Win64\ue4ss\Mods\`.

## Using it

1. Open your inventory and click the fifth tab.
2. Click a food in the list at the bottom. It appears in the **Food** slot.
   Do the same for a drink.
3. Set the levels with **-** and **+** if 50% doesn't suit you. "Eat at 50%"
   means: eat when the hunger bar is half empty or emptier. The game's own
   "hungry" warning comes at 25%.

That's all. Close the inventory and play. The mod checks every 2 seconds.

Good to know:

- Only the bag counts (the hotbar and the Items page). Food in chests isn't
  used.
- If hunger and thirst are both low, the emptier one goes first and the other
  follows a few seconds later.
- A food that fills more than you are missing wastes the rest, the same as
  eating it by hand. Lower the level if that bothers you.
- The mod eats whenever the level is reached, in a fight too. Switch it OFF
  on the tab if you don't want that.
- The Auto Eat tab is clicked with the mouse. The game's keys for stepping
  through the inventory tabs go through its own four tabs.

## Settings

Everything you'd normally change is on the tab. A few things are in
`Win64\ue4ss\Mods\AutoEat\Scripts\config.lua`; edit it in Notepad, then restart
the game.

| Setting | Default | What it does |
| --- | --- | --- |
| `FoodAt` | `50` | The "eat at" level a new character starts with, in percent |
| `DrinkAt` | `50` | The "drink at" level a new character starts with, in percent |
| `CheckSeconds` | `2` | How often hunger and thirst are checked |
| `SettleSeconds` | `6` | How long the mod waits after using an item before it checks whether that worked |
| `PollMs` | `50` | How often the inventory screen is checked, in milliseconds: for clicks on the tab, and for the inventory closing while the tab is on show |
| `DebugLogging` | `false` | Extra lines in `UE4SS.log` |

Each character's choices are in `Win64\ue4ss\Mods\AutoEat\saved_<character id>.txt`.
The mod writes that file; updates don't touch it.

## How it works

- Hunger and thirst are the player character's `SustenanceComponent` and
  `HydrationComponent`. The mod reads their current and full values.
- Food is any item whose data is a `FoodItemData`, drink any `DrinkItemData`.
  The mod finds them by walking the bag's slots
  (`PlayerController.InventoryComponent.ItemSlots`).
- Eating is `InventoryController:UseItemFromInventory(bag, slot)`, the call the
  inventory screen makes when you use an item. The game does the rest:
  animation, sounds, buffs, and saying no when it isn't allowed.
- After using an item the mod waits a few seconds, then looks whether the bar
  went up or the stack went down. If neither happened the game refused, and the
  mod waits 15 seconds before trying that slot again, then 30, 60 and 120.
- The tab is added to the game's tab row: a box in the colours of the game's
  four, with the game's hunger icon and the gold line the game draws under its
  chosen tab. The page is added next to the four item pages and shown in their
  place while the tab is chosen. Clicking any of the game's tabs brings its
  page back.
- The slots are drawn with the material the game draws its own inventory slots
  with (`MI_Item_Selected`), so they look and light up the same.
- Everything clickable is an invisible check box. A click flips it, and the mod
  looks twenty times a second for flipped boxes, so no click is lost.
- The inventory screen is never taken down: closed, it is the hotbar, and the
  game hides the rest of it piece by piece. The mod's page follows the game's
  tab row, so it hides and fades with the inventory.
- The mod only reads the game's data and calls the one "use item" function. It
  writes nothing to your save.

### Achievements

The game skips achievement unlocks only in Creative and Custom worlds. This mod
never touches world difficulty or world settings. The game's mod check
(`CheckForMods`) logs a warning and marks the world as modded for people
joining, but achievements still unlocked in testing with other UE4SS mods.

## Troubleshooting

The log is `Win64\ue4ss\UE4SS.log`. Lines from this mod start with `[AutoEat]`.
Set `DebugLogging = true` in `config.lua` to see every item it uses and every
refusal.

- **No fifth tab**: check that UE4SS is installed and that the log has
  `[AutoEat] Loaded`. The tab is added a few seconds after the world loads.
- **It doesn't eat**: check the tab says ON, the slot has an item with a number
  above 0, and your bar is at or below the level shown.

## Uninstall

Delete `Win64\ue4ss\Mods\AutoEat`, or remove the mod in Mod Loader. Nothing is
left in your save. Mod Loader leaves the `saved_*.txt` files behind; delete the
folder by hand if you want them gone too.

## Credits

UE4SS is made by the UE4SS team ([RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS),
MIT licence).
