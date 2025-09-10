-- jokers/super_gaetano.lua
-- Super Mustard Gaetano — evo-safe ID + proper scoring gates
-- • Primary key = 'super_mustard_gaetano' (working evolution ID)
-- • Alias also registers 'j_gaet_super_mustard_gaetano' to this center (save/mod-order safety)
-- • GOLD that actually SCORES from PLAY -> X2 Mult (requires membership in scoring hand)
-- • GOLD in HAND during scoring -> X1.5 Mult (no membership check; Steel-like behavior)
-- • After scoring, turn all scored cards into GOLD

local function is_gold(card)
  if not card or card.debuff then return false end
  if card.enhancement == 'm_gold' then return true end
  if card.ability then
    if card.ability.enhancement == 'm_gold' then return true end
    if card.ability.key == 'm_gold' then return true end
    if card.ability.config and card.ability.config.center then
      local c = card.ability.config.center
      if c and (c.key == 'm_gold') then return true end
    end
  end
  local cent = (card.config and card.config.center) or card.center
  if cent and cent.key == 'm_gold' then return true end
  return false
end

local function gold_center()
  local P = G and G.P_CENTERS or nil
  return (P and P.m_gold)
      or (P and P['Enhancement'] and P['Enhancement'].m_gold)
      or (P and P['Joker'] and P['Joker'].m_gold)
      or nil
end

local function make_gold(c)
  if not c then return end
  local gc = gold_center()
  if gc and c.set_ability then pcall(function() c:set_ability(gc) end) end
end

local function _member_of(list, card)
  if not list or not card then return false end
  for _, v in ipairs(list) do if v == card then return true end end
  return false
end

local function _in_area(card, area)
  if not card or not area or not area.cards then return false end
  for _, v in ipairs(area.cards) do if v == card then return true end end
  return false
end

-- Register Joker with the working-evo key
local J = SMODS.Joker{
  key = 'super_mustard_gaetano',
  rarity = 4,
  cost = 20,
  blueprint_compat = true,
  eternal_compat = true,
  perishable_compat = false,

  atlas = "SuperGaetanoAtlas",
  pos   = { x = 0, y = 0 },

  effect = "Mult",
  loc_txt = {
    name = "Super Mustard Gaetano",
    text = {
      "After scoring, {C:attention}all scored cards{} become {C:attention}Gold{}",
      "{X:mult,C:white}X2{} Mult for each {C:attention}scoring Gold{} card{}",
      "{X:mult,C:white}X1.5{} Mult for each {C:attention}Gold{} card {C:attention}held in hand{}",
    },
  },
}

-- Back-compat alias so both keys resolve to the same center
local function ensure_aliases()
  SMODS.CENTERS = SMODS.CENTERS or {}; SMODS.CENTERS.Joker = SMODS.CENTERS.Joker or {}
  local primary = SMODS.CENTERS.Joker['super_mustard_gaetano'] or (SMODS.find_center and SMODS.find_center('super_mustard_gaetano'))
  if not primary and G and G.P_CENTERS and G.P_CENTERS.Joker then
    primary = G.P_CENTERS.Joker['super_mustard_gaetano']
  end
  if not primary then return end
  SMODS.CENTERS.Joker['j_gaet_super_mustard_gaetano'] = primary
  if G and G.P_CENTERS then
    G.P_CENTERS.Joker = G.P_CENTERS.Joker or {}
    G.P_CENTERS.Joker['j_gaet_super_mustard_gaetano'] = primary
  end
end

ensure_aliases()
function J:give()  ensure_aliases() end
function J:load()  ensure_aliases() end
function J:reset() end

function J:calculate(card, ctx)
  if card and card.debuff then return end
  if not ctx then return end

  -- Ignore non-per-card scoring hooks
  if ctx.joker_main or ctx.before or ctx.pre_joker then return end

  -- Per-card multiplier ticks
  if ctx.individual and ctx.other_card then
    local oc = ctx.other_card
    if not is_gold(oc) then return end

    -- We must be in a scoring pass
    if not ctx.scoring_hand then return end

    -- x2: only for Gold that is actually **in** the scoring hand and in play
    if (ctx.cardarea == G.play or _in_area(oc, G.play)) and _member_of(ctx.scoring_hand, oc) then
      return { x_mult = 2 }
    end

    -- x1.5: for Gold **in hand** during scoring (Steel-like tick), no membership check
    if (ctx.cardarea == G.hand or _in_area(oc, G.hand)) then
      return { x_mult = 1.5 }
    end

    return
  end

  -- After scoring: convert all scored cards to Gold
  if ctx.after and ctx.scoring_hand then
    local scored = ctx.scoring_hand
    G.E_MANAGER:add_event(Event({
      func = function()
        for _, c in ipairs(scored) do
          if c and not c.debuff and not is_gold(c) then make_gold(c) end
        end
        return true
      end
    }))
  end
end

-- JokerDisplay: ensure X2 shows on top, X1.5 below, without changing global config
J.joker_display_def = function(JD)
  local top_to_bottom = JokerDisplay and JokerDisplay.config and JokerDisplay.config.top_to_bottom
  local text_nodes
  local extra_rows

  if top_to_bottom then
    -- JD stacks top→bottom: first row is 'text'
    text_nodes = {
      { ref_table = "card.joker_display_values", ref_value = "x2_count", retrigger_type = "x_mult" },
      { text = "x", scale = 0.35 },
      { border_nodes = { { text = "X" }, { text = "2" } } },
    }
    extra_rows = {{
      { ref_table = "card.joker_display_values", ref_value = "x15_count", retrigger_type = "x_mult" },
      { text = "x", scale = 0.35 },
      { border_nodes = { { text = "X" }, { text = "1.5" } } },
    }}
  else
    -- JD stacks bottom→top: visual top is 'extra', so flip the content
    text_nodes = {
      { ref_table = "card.joker_display_values", ref_value = "x15_count", retrigger_type = "x_mult" },
      { text = "x", scale = 0.35 },
      { border_nodes = { { text = "X" }, { text = "1.5" } } },
    }
    extra_rows = {{
      { ref_table = "card.joker_display_values", ref_value = "x2_count", retrigger_type = "x_mult" },
      { text = "x", scale = 0.35 },
      { border_nodes = { { text = "X" }, { text = "2" } } },
    }}
  end

  return {
    text = text_nodes,
    text_config = { colour = G.C.UI.TEXT },
    extra = extra_rows,
    reminder_text = {
      { text = "(", colour = G.C.UI.TEXT_DARK, scale = 0.3 },
      { text = "Gold", colour = G.C.ORANGE, scale = 0.3 },
      { text = ")", colour = G.C.UI.TEXT_DARK, scale = 0.3 },
    },
    calc_function = function(card)
      local x2, x15 = 0, 0
      local _, _, scoring_hand = JokerDisplay.evaluate_hand()
      local selected = {}
      if scoring_hand then
        for _, c in ipairs(scoring_hand) do
          if is_gold(c) then x2 = x2 + 1 end
          selected[c] = true
        end
      end
      if G and G.hand and G.hand.cards then
        for _, c in ipairs(G.hand.cards) do
          if is_gold(c) and not selected[c] then x15 = x15 + 1 end
        end
      end
      card.joker_display_values.x2_count = x2
      card.joker_display_values.x15_count = x15
    end
  
}
end

function J:loc_vars() return {} end
return J