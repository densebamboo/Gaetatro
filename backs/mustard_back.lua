-- Register atlas for Mustard Deck back (71x95 tiles). Requires assets at:
-- Mods/<YourMod>/assets/1x/mustard_back.png and assets/2x/mustard_back.png
local _MustardAtlas = SMODS.Atlas{
  key = "MustardAtlas",
  path = "MustardAtlas.png",
  px = 71,
  py = 95,
}:register()

-- backs/mustard.lua
-- Mustard Deck (Back): start each run with Gaetano in a proper Joker slot

local B = SMODS.Back{
  key = "gaet_mustard_back",
  loc_txt = {
    name = "Mustard Vigilante Deck",
    text = {
      "Start run with {C:attention}Gaetano{}"
    }
  },
  atlas = "MustardAtlas",
  pos   = { x = 0, y = 0 },
  unlocked = true,
  discovered = true,
  config = {}
}

local function give_gaetano()
  -- Ensure the center exists: SMODS key "gaet_gaetano" → center "j_gaet_gaetano"
  local center = G and G.P_CENTERS and G.P_CENTERS.j_gaet_gaetano
  if not center then return end

  -- create_card(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append)
  --            1       2       3          4          5                6        7           8
  local card = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_gaet_gaetano', nil)

  if card then
    card:add_to_deck()
    if G.jokers and G.jokers.emplace then
      G.jokers:emplace(card)
    else
      card:set_card_area(G.jokers)
    end
  end
end

function B:apply()
  -- Defer one tick so areas & centers are ready
  G.E_MANAGER:add_event(Event({
    trigger = 'after',
    func = function()
      give_gaetano()
      return true
    end
  }))
  return true
end
