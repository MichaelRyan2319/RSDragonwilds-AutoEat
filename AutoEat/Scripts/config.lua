-- Auto Eat settings. Edit in Notepad, then restart the game.
--
-- Which food and drink are used, the "eat at" and "drink at" levels and the on/off switch are
-- set in the game, on the Auto Eat tab of the inventory. They are saved per character in
-- saved_<character>.txt next to this mod's Scripts folder, not here.
return {
    -- The levels a new character starts with: eat or drink when the bar is at or below this
    -- many percent. The game's own "low" warning comes at 25.
    FoodAt = 50,
    DrinkAt = 50,

    -- How often hunger and thirst are checked, in seconds.
    CheckSeconds = 2,

    -- How long to wait after using an item before checking whether it worked, in seconds.
    -- Eating and drinking take a few seconds in the game.
    SettleSeconds = 6,

    -- How often the open inventory is checked for clicks on the Auto Eat tab, in milliseconds.
    PollMs = 100,

    -- Extra lines in UE4SS.log.
    DebugLogging = false,
}
