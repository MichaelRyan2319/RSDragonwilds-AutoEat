-- Auto Eat for RuneScape: Dragonwilds
--
-- Adds a fifth tab to the inventory, next to Items, Runes, Ammunition and Quest Items. The tab
-- has two slots, one for a food and one for a drink, and lists the food and drink in the bag.
-- Click one in the list to put it in its slot. When hunger or thirst falls to the level set on
-- the tab, the mod uses one of the chosen item from the bag, through the game's own "use item"
-- call, so it is exactly what clicking Eat or Drink does.
--
-- The slots hold a choice, not the items: the food stays in the bag, and the slot shows how
-- much of it the bag has.

local config = require("config")
local UEHelpers = require("UEHelpers")

local TAG = "[AutoEat] "
local function Log(msg) print(TAG .. tostring(msg) .. "\n") end
local function Debug(msg) if config.DebugLogging then Log(msg) end end

-- A second copy of this script (a reload while developing) first stops the one before it.
if AutoEatShutdown then pcall(AutoEatShutdown) end

-- ESlateVisibility
local VISIBLE, COLLAPSED, HIDDEN, HIT_TEST_INVISIBLE, SELF_HIT_TEST_INVISIBLE = 0, 1, 2, 3, 4
-- EHorizontalAlignment / EVerticalAlignment (0 is Fill)
local FILL, LEFT, CENTER, RIGHT, BOTTOM = 0, 1, 2, 3, 3
-- ESlateSizeRule
local SIZE_FILL = 1
-- ESlateBrushDrawType
local DRAW_NONE = 0
local ART = "/Game/Art/UI/"
local TEX_FOOD = ART .. "HUD/Survival_Core/Upkeep/T_Icon_Upkeep_Sustenance.T_Icon_Upkeep_Sustenance"
local TEX_DRINK = ART .. "HUD/Survival_Core/Upkeep/T_Icon_Upkeep_Hydration.T_Icon_Upkeep_Hydration"
local TEX_TAB = TEX_FOOD
-- The material the game draws its own inventory slots with: the background, the item's picture
-- and the orange highlight are all parameters of it.
local MAT_SLOT = "/Game/Materials/UI/MI_Item_Selected.MI_Item_Selected"
-- The gold line under the game's chosen tab.
local MAT_UNDERLINE = "/Game/Materials/UI/UI_Library_MM/MI_Menu_Underline.MI_Menu_Underline"
local FONT_HEADER = "/Game/UI/Fonts/Amiri-Regular_Font.Amiri-Regular_Font"
local FONT_TEXT = "/Game/UI/Fonts/Poppins-Regular_Font.Poppins-Regular_Font"

local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local CREAM = { R = 0.88, G = 0.84, B = 0.79, A = 1 }
local GOLD = { R = 0.93, G = 0.78, B = 0.45, A = 1 }
local DIM = { R = 0.60, G = 0.57, B = 0.53, A = 1 }
local RED = { R = 0.95, G = 0.40, B = 0.35, A = 1 }
local GREEN = { R = 0.55, G = 0.85, B = 0.45, A = 1 }

-- A colour as it looks on screen (0-255), for the values measured from the game's own tabs.
local function Screen(r, g, b)
    local function linear(v)
        v = v / 255
        if v <= 0.04045 then return v / 12.92 end
        return ((v + 0.055) / 1.055) ^ 2.4
    end
    return { R = linear(r), G = linear(g), B = linear(b), A = 1 }
end

-- The game's tab buttons: a dark box with a thin edge and a grey picture, gold when chosen.
local TAB_LOOKS = {
    normal = { fill = Screen(46, 44, 43), edge = Screen(62, 59, 52), icon = Screen(150, 150, 148) },
    hover = { fill = Screen(38, 36, 36), edge = Screen(52, 49, 44), icon = Screen(125, 125, 123) },
    chosen = { fill = Screen(108, 87, 56), edge = Screen(168, 148, 90), icon = Screen(206, 190, 156) },
}

-- The game's inventory slots are 60 wide and 66 high, 8 to a row, with these gaps around each.
local SLOT_W, SLOT_H = 60, 66
local SLOT_PAD = { Left = 2.5, Top = 2, Right = 2.5, Bottom = 1 }
local GRID_COLUMNS, GRID_ROWS = 8, 2
-- The game's tab icons are 62 x 32 pictures that overlap their neighbour by 8. The box drawn in
-- them is smaller, 46.5 x 29, and sits a little below the middle (measured from screenshots).
local TAB_W, TAB_H, TAB_OVERLAP = 62, 32, -8
local TAB_BOX = { Left = 7.75, Top = 2.9, Right = 7.75, Bottom = 0.1 }
-- The hunger icon's picture is mostly empty space, so it is drawn larger than the box.
local TAB_ICON = 46

local LEVEL_MIN, LEVEL_MAX, LEVEL_STEP = 5, 95, 5

local KINDS = {
    food = { class = "/Script/Dominion.FoodItemData", title = "FOOD", verb = "Eat", none = "No food chosen", icon = TEX_FOOD },
    drink = { class = "/Script/Dominion.DrinkItemData", title = "DRINK", verb = "Drink", none = "No drink chosen", icon = TEX_DRINK },
}
local KIND_ORDER = { "food", "drink" }

------------------------------------------------------------------ small helpers

local function Valid(obj)
    if obj == nil then return false end
    local ok, res = pcall(function() return obj:IsValid() end)
    return ok and res == true
end

local function Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Folder that holds this mod's Scripts folder, e.g. ".../Mods/AutoEat/".
local MOD_FOLDER = (function()
    local source = debug.getinfo(1, "S").source or ""
    local dir = source:match("^@(.*[\\/])") or ""
    return (dir:gsub("[\\/]Scripts[\\/]$", "/"))
end)()

-- StaticConstructObject silently makes nothing when the name is already taken in that outer, so
-- every object gets a name of its own.
local SESSION = tostring(os.time())
local nameCount = 0
local function New(classPath, outer, name)
    nameCount = nameCount + 1
    local class = StaticFindObject(classPath)
    return StaticConstructObject(class, outer, FName(string.format("AE_%s_%s_%d", name, SESSION, nameCount)))
end

local assets = {}
local function Asset(path)
    local asset = assets[path]
    if asset == false then return nil end   -- it didn't load before; don't try on every tick
    if Valid(asset) then return asset end
    local ok, found = pcall(StaticFindObject, path)
    if ok and Valid(found) then
        asset = found
    else
        local okLoad, loaded = pcall(LoadAsset, path)
        asset = (okLoad and Valid(loaded)) and loaded or nil
    end
    assets[path] = asset or false
    return asset
end

local errors = 0
local function Report(ok, err)
    if ok or errors >= 8 then return end
    errors = errors + 1
    Log("Error: " .. tostring(err))
end

------------------------------------------------------------------ the player

local World = {
    pc = nil,           -- the player controller the rest was read from
    key = nil,          -- the character's id, used in the settings file name
    kindOf = {},        -- item data address -> "food", "drink" or false
    pathOf = {},        -- item data address -> its asset path
}

local nextControllerSearch = 0
local function Controller()
    if Valid(World.pc) then return World.pc end
    local now = os.clock()
    if now < nextControllerSearch then return nil end
    nextControllerSearch = now + 1
    local pc = UEHelpers.GetPlayerController()
    if not Valid(pc) then return nil end
    -- The title screen has a player controller too; it has no bag.
    local ok, bag = pcall(function() return pc.InventoryComponent end)
    if not ok or not Valid(bag) then return nil end
    World.pc, World.key, World.kindOf, World.pathOf = pc, nil, {}, {}
    return pc
end

local function CharacterKey(pc)
    local ok, key = pcall(function()
        local g = pc:GetCharacterGuid().InnerGuid
        return string.format("%08X%08X%08X%08X", g.A & 0xFFFFFFFF, g.B & 0xFFFFFFFF, g.C & 0xFFFFFFFF, g.D & 0xFFFFFFFF)
    end)
    if ok and key and key ~= "00000000000000000000000000000000" then return key end
    return nil
end

local kindClasses = {}
local function KindOf(data)
    local address = data:GetAddress()
    local kind = World.kindOf[address]
    if kind ~= nil then return kind end
    kind = false
    for _, name in ipairs(KIND_ORDER) do
        local class = kindClasses[name]
        if not Valid(class) then
            class = StaticFindObject(KINDS[name].class)
            kindClasses[name] = class
        end
        if Valid(class) and data:IsA(class) then kind = name break end
    end
    World.kindOf[address] = kind
    return kind
end

local function PathOf(data)
    local address = data:GetAddress()
    local path = World.pathOf[address]
    if path then return path end
    -- "BP_Consumables_Food_C /Game/.../ITEM_X.ITEM_X" -> "/Game/.../ITEM_X.ITEM_X"
    path = data:GetFullName():match("^%S+%s+(.+)$") or data:GetFullName()
    World.pathOf[address] = path
    return path
end

-- Every food and drink in the bag: { kind, path, data, count (all stacks), slot (first stack) }.
-- Returns the list in bag order and the same entries by path.
local function ScanBag(bag)
    local list, byPath = {}, {}
    local slots = bag.ItemSlots
    for i = 1, #slots do
        local item = slots[i]
        if item ~= nil and item:IsValid() then
            local data = item.ItemData
            if data ~= nil and data:IsValid() then
                local kind = KindOf(data)
                if kind then
                    local path = PathOf(data)
                    local entry = byPath[path]
                    if not entry then
                        entry = { kind = kind, path = path, data = data, count = 0, slot = i - 1 }
                        byPath[path] = entry
                        list[#list + 1] = entry
                    end
                    entry.count = entry.count + item.Count
                end
            end
        end
    end
    return list, byPath
end

-- Current and full value of the hunger or thirst bar, or nothing when the pawn has none (the
-- player is controlling something that isn't their character).
local function Level(kind, pawn)
    local ok, level, full = pcall(function()
        if kind == "food" then
            local c = pawn.SustenanceComponent
            return c.CurrentSustenance, c.CurrentMaxSustenance
        end
        local c = pawn.HydrationComponent
        return c.CurrentHydration, c.CurrentMaxHydration
    end)
    if ok and type(level) == "number" and type(full) == "number" then return level, full end
    return nil, nil
end

------------------------------------------------------------------ settings (per character)

local Settings = {
    enabled = true,
    food = nil, drink = nil,        -- asset path of the chosen item
    foodAt = Clamp(tonumber(config.FoodAt) or 50, LEVEL_MIN, LEVEL_MAX),
    drinkAt = Clamp(tonumber(config.DrinkAt) or 50, LEVEL_MIN, LEVEL_MAX),
}
local settingsFile = nil

local function SaveSettings()
    if not settingsFile then return end
    local lines = {
        "# Auto Eat: this character's choices. Written by the mod when they change on the Auto Eat tab.",
        "enabled=" .. (Settings.enabled and "1" or "0"),
        "food=" .. (Settings.food or ""),
        "drink=" .. (Settings.drink or ""),
        "food_at=" .. Settings.foodAt,
        "drink_at=" .. Settings.drinkAt,
        "",
    }
    local tmp = settingsFile .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then
        Log("Could not write " .. settingsFile)
        return
    end
    f:write(table.concat(lines, "\n"))
    f:close()
    os.remove(settingsFile)
    os.rename(tmp, settingsFile)
end

local function LoadSettings(key)
    settingsFile = MOD_FOLDER .. "saved_" .. key .. ".txt"
    Settings.enabled = true
    Settings.food, Settings.drink = nil, nil
    Settings.foodAt = Clamp(tonumber(config.FoodAt) or 50, LEVEL_MIN, LEVEL_MAX)
    Settings.drinkAt = Clamp(tonumber(config.DrinkAt) or 50, LEVEL_MIN, LEVEL_MAX)
    local f = io.open(settingsFile, "r")
    if not f then return end
    local text = f:read("*a")
    f:close()
    for name, value in text:gmatch("([%w_]+)=([^\r\n]*)") do
        value = value:gsub("%s+$", "")
        if name == "enabled" then
            Settings.enabled = value ~= "0"
        elseif name == "food" or name == "drink" then
            Settings[name] = value ~= "" and value or nil
        elseif name == "food_at" then
            Settings.foodAt = Clamp(tonumber(value) or Settings.foodAt, LEVEL_MIN, LEVEL_MAX)
        elseif name == "drink_at" then
            Settings.drinkAt = Clamp(tonumber(value) or Settings.drinkAt, LEVEL_MIN, LEVEL_MAX)
        end
    end
    Debug("Loaded settings for character " .. key)
end

------------------------------------------------------------------ eating and drinking

local pending = nil     -- the item just used: { kind, path, count, level, at }
local misses = { food = 0, drink = 0 }          -- uses in a row that changed nothing
local blockedUntil = { food = 0, drink = 0 }

local function CheckHunger(now, pc)
    local pawn = pc.Pawn
    if not Valid(pawn) then return end
    local bag, controller = pc.InventoryComponent, pc.InventoryController
    if not (Valid(bag) and Valid(controller)) then return end
    local okDead, dead = pcall(function() return pawn.HealthComponent:IsDead() end)
    if not okDead or dead then
        pending = nil
        return
    end

    if not pending and not (Settings.enabled and (Settings.food or Settings.drink)) then return end
    local _, byPath = ScanBag(bag)

    if pending then
        if now - pending.at < config.SettleSeconds then return end
        -- Did it work? Either the bar went up or the bag has one less.
        local level = Level(pending.kind, pawn)
        local entry = byPath[pending.path]
        local count = entry and entry.count or 0
        if level == nil then
            -- The bar can't be read right now; neither a hit nor a miss.
        elseif level > pending.level + 0.5 or count < pending.count then
            misses[pending.kind] = 0
        else
            -- The game refused (riding, in a menu, mid-fight...). Try again later, and wait
            -- longer each time so a refusal doesn't repeat every few seconds.
            misses[pending.kind] = misses[pending.kind] + 1
            local wait = math.min(15 * 2 ^ (misses[pending.kind] - 1), 120)
            blockedUntil[pending.kind] = now + wait
            Debug("Using " .. pending.path .. " changed nothing; trying again in " .. wait .. " s")
        end
        pending = nil
    end

    if not Settings.enabled then return end

    -- Whichever bar is emptier goes first.
    local best, bestPercent, bestLevel = nil, nil, nil
    for _, kind in ipairs(KIND_ORDER) do
        local path = Settings[kind]
        local entry = path and byPath[path] or nil
        if entry and now >= blockedUntil[kind] then
            local level, full = Level(kind, pawn)
            if full and full > 0 then
                local percent = level / full * 100
                if percent <= Settings[kind .. "At"] and (not bestPercent or percent < bestPercent) then
                    best, bestPercent, bestLevel = entry, percent, level
                end
            end
        end
    end
    if not best then return end

    pending = { kind = best.kind, path = best.path, count = best.count, level = bestLevel, at = now }
    controller:UseItemFromInventory(bag, best.slot)
    Debug(string.format("%s at %.0f%%: used %s from slot %d", best.kind, bestPercent, best.path, best.slot))
end

------------------------------------------------------------------ building blocks for the tab

local fonts = {}
local function SetFont(text, path, size, spacing)
    pcall(function()
        local font = text.Font
        local object = fonts[path]
        if not Valid(object) then
            object = Asset(path)
            fonts[path] = object
        end
        if Valid(object) then
            font.FontObject = object
            font.TypefaceFontName = FName("Default")
        end
        font.Size = size
        font.LetterSpacing = spacing or 0
        text:SetFont(font)
    end)
end

local function SetColor(text, color)
    text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
end

local function Text(tree, value, header, size, color)
    local text = New("/Script/UMG.TextBlock", tree, "Text")
    text:SetText(FText(value or ""))
    SetColor(text, color or CREAM)
    if header then SetFont(text, FONT_HEADER, size, 150) else SetFont(text, FONT_TEXT, size, 0) end
    text:SetVisibility(HIT_TEST_INVISIBLE)
    return text
end

-- Texts are only set when they change, so an open tab costs nothing while nothing happens.
local shownText = {}
local function ShowText(text, value, color)
    local address = text:GetAddress()
    local key = value .. (color and ("|" .. color.R .. color.G .. color.B) or "")
    if shownText[address] == key then return end
    shownText[address] = key
    text:SetText(FText(value))
    if color then SetColor(text, color) end
end

-- A picture, or with no texture a plain coloured box.
local function Image(tree, texturePath, color)
    local image = New("/Script/UMG.Image", tree, "Image")
    local texture = texturePath and Asset(texturePath) or nil
    if texture then image:SetBrushFromTexture(texture, false) end
    if color then image:SetColorAndOpacity(color) end
    image:SetVisibility(HIT_TEST_INVISIBLE)
    return image
end

local function Show(widget, visible, shown)
    local want = visible and (shown or HIT_TEST_INVISIBLE) or COLLAPSED
    if widget:GetVisibility() ~= want then widget:SetVisibility(want) end
end

local function Padding(left, top, right, bottom)
    return { Left = left or 0, Top = top or 0, Right = right or 0, Bottom = bottom or 0 }
end

-- Adds a child to an overlay, filling it (an overlay puts its children top left otherwise).
local function Layer(overlay, child, padding, horizontal, vertical)
    local slot = overlay:AddChildToOverlay(child)
    slot:SetHorizontalAlignment(horizontal or FILL)
    slot:SetVerticalAlignment(vertical or FILL)
    if padding then slot:SetPadding(padding) end
    return slot
end

local function Sized(tree, child, width, height)
    local box = New("/Script/UMG.SizeBox", tree, "Box")
    if width then box:SetWidthOverride(width) end
    if height then box:SetHeightOverride(height) end
    box:SetContent(child)
    box:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    return box
end

local STYLE_IMAGES = {
    "UncheckedImage", "UncheckedHoveredImage", "UncheckedPressedImage",
    "CheckedImage", "CheckedHoveredImage", "CheckedPressedImage",
    "UndeterminedImage", "UndeterminedHoveredImage", "UndeterminedPressedImage",
    "BackgroundImage", "BackgroundHoveredImage", "BackgroundPressedImage",
}

-- Everything on the tab that can be clicked is a check box: a click flips it, and it stays
-- flipped until this mod looks, so no click is missed between two looks. The box itself draws
-- nothing; what is seen is drawn by the widgets around it.
local function ClickBox(tree)
    local box = New("/Script/UMG.CheckBox", tree, "Click")
    box.IsFocusable = false
    local style = box.WidgetStyle
    for _, name in ipairs(STYLE_IMAGES) do
        pcall(function()
            local brush = style[name]
            brush.DrawAs = DRAW_NONE
            brush.ImageSize.X = 0
            brush.ImageSize.Y = 0
        end)
    end
    pcall(function()
        local padding = style.Padding
        padding.Left, padding.Top, padding.Right, padding.Bottom = 0, 0, 0, 0
    end)
    return box
end

-- True once for each click.
local function Clicked(box)
    if not box:IsChecked() then return false end
    box:SetIsChecked(false)
    return true
end

-- One item slot, drawn by the game's own slot material, so it looks and lights up like the
-- slots on the other tabs.
local function ItemSlot(tree)
    local overlay = New("/Script/UMG.Overlay", tree, "Slot")
    overlay:SetVisibility(SELF_HIT_TEST_INVISIBLE)

    local picture = New("/Script/UMG.Image", tree, "Picture")
    picture:SetBrushFromMaterial(Asset(MAT_SLOT))
    picture:SetVisibility(HIT_TEST_INVISIBLE)
    Layer(overlay, picture)

    -- What belongs in the slot, shown faintly while it's empty.
    local ghost = Image(tree, nil, { R = 1, G = 1, B = 1, A = 0.22 })
    local ghostBox = Sized(tree, ghost, 30, 30)
    Layer(overlay, ghostBox, nil, CENTER, CENTER)
    ghostBox:SetVisibility(COLLAPSED)

    local count = Text(tree, "", true, 10, WHITE)
    SetFont(count, FONT_HEADER, 10, 0)
    Layer(overlay, count, Padding(0, 0, 5, 0.5), RIGHT, BOTTOM)

    local click = ClickBox(tree)
    Layer(overlay, click)

    return {
        root = overlay, click = click, count = count, ghost = ghostBox, ghostImage = ghost,
        paint = picture:GetDynamicMaterial(),   -- this slot's own copy of the material
        painted = {}, texture = nil,
    }
end

local function Paint(slot, name, value)
    if slot.painted[name] == value then return end
    slot.painted[name] = value
    slot.paint:SetScalarParameterValue(FName(name), value)
end

local iconOf = {}   -- item path -> its picture
local function IconFor(entry)
    local texture = iconOf[entry.path]
    if Valid(texture) then return texture end
    local ok, path = pcall(function()
        local library = Asset("/Script/Engine.Default__KismetSystemLibrary")
        return library:Conv_SoftObjectReferenceToString(entry.data.Icon):ToString()
    end)
    texture = (ok and path and path ~= "") and Asset(path) or nil
    iconOf[entry.path] = texture
    return texture
end

-- Fills a slot with an item (or empties it with nil). `lit` shows the game's orange highlight.
local function FillSlot(slot, entry, lit)
    local texture = entry and IconFor(entry) or nil
    if texture and slot.texture ~= entry.path then
        slot.texture = entry.path
        slot.paint:SetTextureParameterValue(FName("Item Image"), texture)
    end
    local filled = texture ~= nil
    local none = filled and entry.count <= 0
    -- The values the game itself gives a slot with an item in it, and an empty one.
    Paint(slot, "Icon Opacity", filled and (none and 0.4 or 1) or 0)
    Paint(slot, "Burnt Desaturation", none and 1 or 0)
    Paint(slot, "Background Texture Opacity", filled and 1 or 0)
    Paint(slot, "Background Opacity", filled and 1 or 0.5)
    Paint(slot, "Selection Opacity", lit and 1 or 0)
    if entry then
        ShowText(slot.count, tostring(entry.count), none and RED or WHITE)
    else
        ShowText(slot.count, "")
    end
end

-- A small text that can be clicked: [-], [+], ON / OFF.
local function TextButton(tree, label, size)
    local click = ClickBox(tree)
    local text = Text(tree, label, false, size, CREAM)
    click:SetContent(text)
    return { click = click, text = text, hovered = false }
end

local function HoverText(button, normal)
    local hovered = button.click:IsHovered() == true
    if hovered ~= button.hovered or button.normal ~= normal then
        button.hovered, button.normal = hovered, normal
        SetColor(button.text, hovered and WHITE or normal)
    end
end

------------------------------------------------------------------ the tab

local ui = nil          -- everything this mod added to the open character's inventory screen

local function UiValid()
    return ui ~= nil and Valid(ui.content) and Valid(ui.tab.root) and Valid(ui.page)
end

-- The tab button: a box like the game's four, with the hunger icon in it.
local function BuildTab(tree)
    local overlay = New("/Script/UMG.Overlay", tree, "Tab")
    overlay:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    local tab = { looks = nil }

    tab.edge = Image(tree, nil, TAB_LOOKS.normal.edge)
    Layer(overlay, tab.edge, TAB_BOX)
    tab.fill = Image(tree, nil, TAB_LOOKS.normal.fill)
    Layer(overlay, tab.fill, Padding(TAB_BOX.Left + 1, TAB_BOX.Top + 1, TAB_BOX.Right + 1, TAB_BOX.Bottom + 1))
    tab.icon = Image(tree, TEX_TAB, TAB_LOOKS.normal.icon)
    Layer(overlay, Sized(tree, tab.icon, TAB_ICON, TAB_ICON), nil, CENTER, CENTER)

    -- The gold line the game draws under its chosen tab, placed the way the game places it.
    tab.line = New("/Script/UMG.Image", tree, "Line")
    local material = Asset(MAT_UNDERLINE)
    if material then tab.line:SetBrushFromMaterial(material) end
    tab.line:SetVisibility(COLLAPSED)
    Layer(overlay, tab.line, Padding(-1, 0, 1, -18), FILL, BOTTOM)

    tab.click = ClickBox(tree)
    Layer(overlay, tab.click, TAB_BOX)

    tab.root = Sized(tree, overlay, TAB_W, TAB_H)
    return tab
end

local function PaintTab(tab, chosen)
    local looks = chosen and TAB_LOOKS.chosen or (tab.click:IsHovered() == true and TAB_LOOKS.hover or TAB_LOOKS.normal)
    if tab.looks == looks then return end
    tab.looks = looks
    tab.edge:SetColorAndOpacity(looks.edge)
    tab.fill:SetColorAndOpacity(looks.fill)
    tab.icon:SetColorAndOpacity(looks.icon)
    Show(tab.line, chosen)
end

-- One half of the top row: a slot, and next to it what it is for, what is in it and the level.
local function BuildChoice(tree, row, kind)
    local info = KINDS[kind]
    local choice = { kind = kind }

    local line = New("/Script/UMG.HorizontalBox", tree, "Choice")
    line:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    local lineSlot = row:AddChildToHorizontalBox(line)
    lineSlot:SetSize({ Value = 1, SizeRule = SIZE_FILL })

    choice.slot = ItemSlot(tree)
    local ghost = Asset(info.icon)
    if ghost then choice.slot.ghostImage:SetBrushFromTexture(ghost, false) end
    local slotSlot = line:AddChildToHorizontalBox(Sized(tree, choice.slot.root, SLOT_W, SLOT_H))
    slotSlot:SetPadding(SLOT_PAD)
    slotSlot:SetVerticalAlignment(CENTER)

    local column = New("/Script/UMG.VerticalBox", tree, "Column")
    column:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    local columnSlot = line:AddChildToHorizontalBox(column)
    columnSlot:SetSize({ Value = 1, SizeRule = SIZE_FILL })
    columnSlot:SetPadding(Padding(7, 0, 4, 0))
    columnSlot:SetVerticalAlignment(CENTER)

    column:AddChildToVerticalBox(Text(tree, info.title, true, 11, GOLD))
    choice.name = Text(tree, info.none, false, 9, DIM)
    column:AddChildToVerticalBox(choice.name)

    local level = New("/Script/UMG.HorizontalBox", tree, "Level")
    level:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    column:AddChildToVerticalBox(level):SetPadding(Padding(0, 3, 0, 0))
    choice.less = TextButton(tree, " - ", 12)
    choice.more = TextButton(tree, " + ", 12)
    choice.level = Text(tree, "", false, 9, CREAM)
    level:AddChildToHorizontalBox(choice.level):SetVerticalAlignment(CENTER)
    level:AddChildToHorizontalBox(choice.less.click):SetPadding(Padding(6, 0, 0, 0))
    level:AddChildToHorizontalBox(choice.more.click):SetPadding(Padding(2, 0, 0, 0))
    return choice
end

-- The game marks its chosen tab twice: the tab's check box is checked (the gold picture), and
-- its SelectionImage is shown (the gold line under it).
local function MarkNative(button, chosen)
    local box = button.RadioCheckBox
    if box:IsChecked() ~= chosen then box:SetIsChecked(chosen) end
    local line = button.SelectionImage
    if Valid(line) then
        local want = chosen and SELF_HIT_TEST_INVISIBLE or COLLAPSED
        if line:GetVisibility() ~= want then line:SetVisibility(want) end
    end
end

-- Removes what an earlier copy of this mod added to a panel. UE4SS can restart its mods while
-- the game runs; the widgets the old copy made stay in the game's screen when it does.
local function RemoveLeftovers(panel)
    for i = panel:GetChildrenCount(), 1, -1 do
        local child = panel:GetChildAt(i - 1)
        if Valid(child) and child:GetFName():ToString():sub(1, 3) == "AE_" then child:RemoveFromParent() end
    end
end

local function BuildUi(content)
    local tree = content.WidgetTree
    local group = content.CategoryButtonGroup
    local scroll = content.ScrollBox_0
    local strip = content.TabGroupOverlay
    if not (Valid(tree) and Valid(group) and Valid(scroll) and Valid(strip)) then return nil end
    -- The four pages sit in a scroll box, in a size box, in an overlay. This mod's page goes
    -- into that overlay, on top, and takes the scroll box's place while its tab is chosen.
    local holder = scroll:GetParent():GetParent()
    if not Valid(holder) or holder:GetClass():GetFName():ToString() ~= "Overlay" then return nil end
    if not (Asset(TEX_TAB) and Asset(MAT_SLOT)) then return nil end

    local built = { content = content, group = group, scroll = scroll, strip = strip, active = false, natives = {}, cells = {}, choices = {} }
    shownText = {}   -- the old screen's texts are gone, and their addresses get used again

    RemoveLeftovers(group)
    RemoveLeftovers(holder)
    for i = 1, group:GetChildrenCount() do
        local button = group:GetChildAt(i - 1)
        if Valid(button) and Valid(button.RadioCheckBox) then built.natives[#built.natives + 1] = button end
    end
    if #built.natives == 0 then return nil end

    if scroll:GetVisibility() == HIDDEN then
        -- An earlier copy had its page open. Put the game's page and its tab's marks back.
        scroll:SetVisibility(VISIBLE)
        local shown = content.InventorySwitcher:GetActiveWidgetIndex()
        for _, button in ipairs(built.natives) do MarkNative(button, button.RadioValue == shown) end
    end

    -- The tab goes after the game's last one, overlapping it the way the game's overlap.
    built.tab = BuildTab(tree)
    built.lastNative = built.natives[#built.natives]
    built.lastNative.Slot:SetPadding(Padding(0, 0, TAB_OVERLAP, 0))
    group:AddChildToHorizontalBox(built.tab.root):SetVerticalAlignment(BOTTOM)

    -- The page.
    local page = New("/Script/UMG.VerticalBox", tree, "Page")
    page:SetVisibility(COLLAPSED)
    Layer(holder, page)
    built.page = page

    local header = New("/Script/UMG.HorizontalBox", tree, "Header")
    header:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    page:AddChildToVerticalBox(header):SetPadding(Padding(9, 0, 8, 2))
    local title = Text(tree, "AUTO EAT", true, 12, WHITE)
    header:AddChildToHorizontalBox(title):SetSize({ Value = 1, SizeRule = SIZE_FILL })
    built.power = TextButton(tree, "ON", 10)
    header:AddChildToHorizontalBox(built.power.click):SetVerticalAlignment(CENTER)

    local row = New("/Script/UMG.HorizontalBox", tree, "Choices")
    row:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    page:AddChildToVerticalBox(row)
    for _, kind in ipairs(KIND_ORDER) do built.choices[kind] = BuildChoice(tree, row, kind) end

    built.hint = Text(tree, "", false, 9, DIM)
    page:AddChildToVerticalBox(built.hint):SetPadding(Padding(9, 7, 8, 2))

    -- Two rows of eight, spread over the width like the game's own rows.
    for _ = 1, GRID_ROWS do
        local line = New("/Script/UMG.HorizontalBox", tree, "Row")
        line:SetVisibility(SELF_HIT_TEST_INVISIBLE)
        page:AddChildToVerticalBox(line)
        for _ = 1, GRID_COLUMNS do
            local cell = ItemSlot(tree)
            local cellSlot = line:AddChildToHorizontalBox(Sized(tree, cell.root, SLOT_W, SLOT_H))
            cellSlot:SetSize({ Value = 1, SizeRule = SIZE_FILL })
            cellSlot:SetPadding(SLOT_PAD)
            cellSlot:SetHorizontalAlignment(LEFT)
            built.cells[#built.cells + 1] = cell
        end
    end

    Debug("Added the Auto Eat tab")
    return built
end

local nextUiSearch = 0
local function FindUi(now)
    if now < nextUiSearch then return end
    nextUiSearch = now + 3
    -- The blueprint's own template turns up here too; its parts are all None, so it's skipped.
    for _, content in ipairs(FindAllOf("InventoryMainPanelContent") or {}) do
        if Valid(content) and Valid(content.CategoryButtonGroup) and Valid(content.InventorySwitcher) then
            local ok, built = pcall(BuildUi, content)
            if ok and built then
                ui = built
                return
            end
            Report(ok, built)
        end
    end
end

local function SetActive(active)
    ui.active = active
    -- UpdateUi shows the page; it knows whether the inventory is open.
    if not active then Show(ui.page, false) end
    -- Hidden, not collapsed: the scroll box still holds the page's place and size.
    local want = active and HIDDEN or VISIBLE
    if ui.scroll:GetVisibility() ~= want then ui.scroll:SetVisibility(want) end
    if ui.tab.click:IsChecked() ~= active then ui.tab.click:SetIsChecked(active) end
    PaintTab(ui.tab, active)

    if active then
        -- The game's chosen tab stops looking chosen. The game still remembers it, and shows
        -- its page again as soon as any of the four is clicked.
        for _, button in ipairs(ui.natives) do MarkNative(button, false) end
        return
    end
    -- Back to the game's tabs. If one was clicked, the game has marked it already; otherwise
    -- mark the one whose page the game has on show.
    local chosen = nil
    for _, button in ipairs(ui.natives) do
        if button.RadioCheckBox:IsChecked() then chosen = button end
    end
    if not chosen then
        local shown = ui.content.InventorySwitcher:GetActiveWidgetIndex()
        for _, button in ipairs(ui.natives) do
            if button.RadioValue == shown then chosen = button end
        end
    end
    for _, button in ipairs(ui.natives) do
        MarkNative(button, chosen ~= nil and button:GetAddress() == chosen:GetAddress())
    end
end

local function RemoveUi()
    if not ui then return end
    if ui.active then pcall(SetActive, false) end
    for _, widget in ipairs({ ui.tab.root, ui.page }) do
        pcall(function() if Valid(widget) then widget:RemoveFromParent() end end)
    end
    pcall(function()
        if Valid(ui.lastNative) then ui.lastNative.Slot:SetPadding(Padding(0, 0, 0, 0)) end
    end)
    ui = nil
end

local function ChangeLevel(kind, by)
    local name = kind .. "At"
    local level = Clamp(Settings[name] + by, LEVEL_MIN, LEVEL_MAX)
    if level == Settings[name] then return end
    Settings[name] = level
    SaveSettings()
end

local function Choose(kind, path)
    if Settings[kind] == path then return end
    Settings[kind] = path
    misses[kind], blockedUntil[kind] = 0, 0
    SaveSettings()
end

-- An entry for a chosen item the bag has none of, so its slot can still show what it was.
local function MissingEntry(kind, path)
    local data = Asset(path)
    if not Valid(data) then return nil end
    return { kind = kind, path = path, data = data, count = 0 }
end

local function NameOf(entry)
    local ok, name = pcall(function() return entry.data.Name:ToString() end)
    return ok and name or "?"
end

local nextRefresh = 0
local function UpdatePage(now, pc)
    local bag = pc.InventoryComponent
    if not Valid(bag) then return end
    if now >= nextRefresh then
        nextRefresh = now + 0.5
        ui.list, ui.byPath = ScanBag(bag)
    end
    local list, byPath = ui.list or {}, ui.byPath or {}
    local hint = nil

    -- The two slots.
    for _, kind in ipairs(KIND_ORDER) do
        local info, choice = KINDS[kind], ui.choices[kind]
        local path = Settings[kind]
        local entry = path and (byPath[path] or MissingEntry(kind, path)) or nil
        local hovered = choice.slot.click:IsHovered() == true
        FillSlot(choice.slot, entry, hovered and entry ~= nil)
        Show(choice.slot.ghost, entry == nil, SELF_HIT_TEST_INVISIBLE)
        if entry then
            if entry.count > 0 then
                ShowText(choice.name, NameOf(entry), CREAM)
            else
                ShowText(choice.name, NameOf(entry) .. " (none left)", RED)
            end
            if hovered then hint = "Click to empty the " .. info.title:lower() .. " slot" end
        else
            ShowText(choice.name, info.none, DIM)
        end
        ShowText(choice.level, string.format("%s at %d%%", info.verb, Settings[kind .. "At"]), Settings.enabled and CREAM or DIM)
        HoverText(choice.less, CREAM)
        HoverText(choice.more, CREAM)
        if Clicked(choice.slot.click) then Choose(kind, nil) end
        if Clicked(choice.less.click) then ChangeLevel(kind, -LEVEL_STEP) end
        if Clicked(choice.more.click) then ChangeLevel(kind, LEVEL_STEP) end
    end

    -- On / off.
    ShowText(ui.power.text, Settings.enabled and "ON" or "OFF")
    HoverText(ui.power, Settings.enabled and GREEN or RED)
    if Clicked(ui.power.click) then
        Settings.enabled = not Settings.enabled
        SaveSettings()
    end
    if ui.power.click:IsHovered() == true then
        hint = Settings.enabled and "Click to switch Auto Eat off" or "Click to switch Auto Eat on"
    end

    -- The food and drink in the bag.
    for i, cell in ipairs(ui.cells) do
        local entry = list[i]
        if entry then
            local chosen = Settings[entry.kind] == entry.path
            local hovered = cell.click:IsHovered() == true
            FillSlot(cell, entry, hovered)
            if hovered then
                local slotName = KINDS[entry.kind].title:lower()
                if chosen then
                    hint = NameOf(entry) .. ": in the " .. slotName .. " slot"
                else
                    hint = NameOf(entry) .. ": click to put it in the " .. slotName .. " slot"
                end
            end
            if Clicked(cell.click) then Choose(entry.kind, entry.path) end
        else
            FillSlot(cell, nil, false)
            Clicked(cell.click)
        end
    end

    if not hint then
        if #list == 0 then
            hint = "No food or drink in your bag"
        else
            hint = "Food and drink in your bag. Click one to choose it."
        end
    end
    ShowText(ui.hint, hint)
end

local function UpdateUi(now, pc)
    -- The inventory screen is always up: closed, it is the hotbar, and the game has hidden the
    -- rest of it piece by piece. This mod's page isn't one of the game's pieces, so it follows
    -- the tab row, which the game hides and fades with the others.
    local open = ui.strip:GetVisibility() ~= COLLAPSED and ui.strip:GetVisibility() ~= HIDDEN
    Show(ui.page, ui.active and open, SELF_HIT_TEST_INVISIBLE)
    if not open then return end
    if ui.active then
        local opacity = ui.strip:GetRenderOpacity()
        if ui.opacity ~= opacity then
            ui.opacity = opacity
            ui.page:SetRenderOpacity(opacity)
        end
        if ui.scroll:GetVisibility() ~= HIDDEN then ui.scroll:SetVisibility(HIDDEN) end
    end

    local tabChecked = ui.tab.click:IsChecked() == true
    if not ui.active then
        if tabChecked then SetActive(true) end
    else
        -- Any of the game's four tabs being chosen (a click, or the tab keys) ends this one.
        local nativeChosen = false
        for _, button in ipairs(ui.natives) do
            if button.RadioCheckBox:IsChecked() then nativeChosen = true end
        end
        if nativeChosen then
            SetActive(false)
        elseif not tabChecked then
            ui.tab.click:SetIsChecked(true)   -- clicking the chosen tab again leaves it chosen
        end
    end

    PaintTab(ui.tab, ui.active)
    if ui.active then UpdatePage(now, pc) end
end

------------------------------------------------------------------ the loop

local nextCheck = 0
local stopped = false

local function Tick()
    -- A loop that has been cancelled can still have one call waiting to run.
    if stopped then return end
    local pc = Controller()
    if not pc then return end
    local now = os.clock()

    if not World.key then
        local key = CharacterKey(pc)
        if not key then return end   -- the character isn't loaded yet
        World.key = key
        LoadSettings(key)
        pending = nil
        misses, blockedUntil = { food = 0, drink = 0 }, { food = 0, drink = 0 }
    end

    if not UiValid() then
        ui = nil
        FindUi(now)
    end
    if UiValid() then Report(pcall(UpdateUi, now, pc)) end

    if now >= nextCheck then
        nextCheck = now + config.CheckSeconds
        Report(pcall(CheckHunger, now, pc))
    end
end

-- One line about what the mod is doing, for the UE4SS console and for testing.
function AutoEatStatus()
    local parts = { "character=" .. tostring(World.key), "tab=" .. (UiValid() and (ui.active and "open" or "added") or "missing") }
    parts[#parts + 1] = "enabled=" .. tostring(Settings.enabled)
    for _, kind in ipairs(KIND_ORDER) do
        parts[#parts + 1] = string.format("%s=%s at %d%%", kind, tostring(Settings[kind] and Settings[kind]:match("([^.]+)$") or nil), Settings[kind .. "At"])
    end
    if pending then parts[#parts + 1] = "just used " .. pending.kind end
    parts[#parts + 1] = "errors=" .. errors
    return table.concat(parts, ", ")
end

function AutoEatShutdown()
    stopped = true
    if AutoEatLoop then pcall(CancelDelayedAction, AutoEatLoop) end
    AutoEatLoop = nil
    pcall(RemoveUi)
end

-- LoopInGameThreadWithDelay keeps all of this on the game thread.
AutoEatLoop = LoopInGameThreadWithDelay(config.PollMs, function() Report(pcall(Tick)) end)
Log("Loaded. The inventory has an Auto Eat tab.")
