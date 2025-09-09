-- jokers/gaetano.lua — DEBUG BUILD (robust Super resolver)
-- Behavior:
--   • Evolves ONLY when **5 Gold cards actually scored** in the current hand (ctx.scoring_hand). Debuffed Gold do not count.
--   • After scoring, the **first scored non-Gold** becomes Gold (once per Joker per hand).
--   • Evolution queued AFTER scoring (popup + sound).
-- Resolver:
--   • Looks for Super by **either** key: 'super_mustard_gaetano' or 'j_gaet_super_mustard_gaetano'.
--   • If found under one, creates an alias for the other in both SMODS and G.P_CENTERS.
-- Debug:
--   • SETTINGS.debug = true (verbose logs, including resolver healing).

---------------------------------------
-- Config
---------------------------------------
local SETTINGS = {
  atlas_key    = "GaetanoAtlas",
  atlas_pos    = { x = 0, y = 0 },
  evolve_msg   = "Transformed!",
  evolve_sound = "tarot1",
  debug = true, -- DEBUG ENABLED
}

---------------------------------------
-- Utilities
---------------------------------------
local function _jid(obj) return tostring(obj):gsub("table: ", "") end

local function _log(obj, msg)
  if not SETTINGS.debug then return end
  local s = ("[Gaetano DEBUG #%s] %s"):format(_jid(obj), tostring(msg))
  if type(sendInfoLog) == "function" then pcall(sendInfoLog, s) end
  if type(print) == "function" then print(s) end
end

local function _current_hand_index()
  if G and G.GAME and G.GAME.current_round then
    return (G.GAME.current_round.hands_played or 0)
  end
  return 0
end

local function _in_area(card, area)
  if not card or not area or not area.cards then return false end
  for _, v in ipairs(area.cards) do if v == card then return true end end
  return false
end

local function _area_name(card)
  if G then
    if _in_area(card, G.play) then return "play" end
    if _in_area(card, G.hand) then return "hand" end
    if _in_area(card, G.discard) then return "discard" end
    if _in_area(card, G.deck) then return "deck" end
  end
  return "unknown"
end

-- Per-instance state accessor (on Joker CARD)
local function _state(card)
  card._gaet = card._gaet or {
    is_base = true,        -- default new instances are base
    evolved = false,
    converted_hand = -1,   -- hand index when first card converted
    enqueued_hand = -1,    -- hand index when evolve was queued
    skip_logged_hand = -1, -- rate-limit skip logs
    last_seen_hand = -1,   -- for gate resets
  }
  return card._gaet
end

---------------------------------------
-- GOLD detection and helpers
---------------------------------------
local function is_gold(c)
  if not c or c.debuff then return false end
  -- direct enhancement flags
  if c.enhancement == 'm_gold' then return true end
  if c.key == 'm_gold' then return true end
  -- ability table hints
  if c.ability then
    if c.ability.enhancement == 'm_gold' then return true end
    if c.ability.key == 'm_gold' then return true end
    if c.ability.name == 'Gold Card' then return true end
    if c.ability.config and c.ability.config.center then
      local cc = c.ability.config.center
      if cc and (cc.key == 'm_gold' or cc.name == 'Gold Card') then return true end
    end
  end
  -- center/config hints
  local cent = (c.config and c.config.center) or c.center
  if cent and (cent.key == 'm_gold' or cent.name == 'Gold Card') then return true end
  return false
end

local function make_gold(c)
  if not c then return end
  local P = G and G.P_CENTERS or {}
  local gc = P.m_gold
          or (P['Enhancement'] and P['Enhancement'].m_gold)
          or (P['Joker'] and P['Joker'].m_gold)
  if gc and c.set_ability then pcall(function() c:set_ability(gc) end) end
end

---------------------------------------
-- Robust Super center resolver + alias healer
---------------------------------------
local SUPER_KEYS = { 'super_mustard_gaetano', 'j_gaet_super_mustard_gaetano' }

local function _get_center_from_anywhere(key)
  -- Prefer SMODS.find_center
  if SMODS and SMODS.find_center then
    local ok, c = pcall(SMODS.find_center, key)
    if ok and c then return c, "SMODS.find_center" end
  end
  -- Try SMODS tables
  if SMODS and SMODS.CENTERS and SMODS.CENTERS.Joker and SMODS.CENTERS.Joker[key] then
    return SMODS.CENTERS.Joker[key], "SMODS.CENTERS.Joker"
  end
  if SMODS and SMODS.CENTERS and SMODS.CENTERS[key] then
    return SMODS.CENTERS[key], "SMODS.CENTERS"
  end
  -- Try game registries
  if G and G.P_CENTERS then
    if G.P_CENTERS.Joker and G.P_CENTERS.Joker[key] then
      return G.P_CENTERS.Joker[key], "G.P_CENTERS.Joker"
    end
    if G.P_CENTERS[key] then
      return G.P_CENTERS[key], "G.P_CENTERS"
    end
  end
  return nil, nil
end

local function _ensure_alias_in_tables(center, key)
  -- Install into SMODS registry
  SMODS.CENTERS = SMODS.CENTERS or {}; SMODS.CENTERS.Joker = SMODS.CENTERS.Joker or {}
  SMODS.CENTERS.Joker[key] = center
  -- Install into Game registry
  if G and G.P_CENTERS then
    G.P_CENTERS.Joker = G.P_CENTERS.Joker or {}
    G.P_CENTERS.Joker[key] = center
  end
end

local function _super_center_resolve(card_for_log)
  local found_center, found_from, found_key = nil, nil, nil
  for _, key in ipairs(SUPER_KEYS) do
    local c, src = _get_center_from_anywhere(key)
    if c then found_center, found_from, found_key = c, src, key; break end
  end
  if not found_center then
    _log(card_for_log or {}, "resolver: Super center NOT found under any known key")
    return nil
  end
  _log(card_for_log or {}, ("resolver: found Super under '%s' via %s"):format(found_key, tostring(found_from)))

  -- Heal aliases for all keys to the found center
  for _, key in ipairs(SUPER_KEYS) do
    if key ~= found_key then
      _ensure_alias_in_tables(found_center, key)
      _log(card_for_log or {}, ("resolver: healed alias %s -> %s object"):format(key, found_key))
    end
  end
  return found_center
end

---------------------------------------
-- Enqueue evolve to run AFTER scoring (post-scoring swap)
---------------------------------------
local function enqueue_evolve_post_scoring(card)
  local s = _state(card)
  local h = _current_hand_index()
  if s.is_base == false then
    if s.skip_logged_hand ~= h then
      s.skip_logged_hand = h
      _log(card, "enqueue_evolve: skip (already evolved)")
    end
    return
  end
  if s.enqueued_hand == h then
    _log(card, "enqueue_evolve: already queued this hand")
    return
  end

  local super = _super_center_resolve(card)
  if not super then
    _log(card, "enqueue_evolve: ERROR Super center not found")
    return
  end

  s.enqueued_hand = h
  _log(card, "enqueue_evolve: queued post-scoring transform")

  G.E_MANAGER:add_event(Event({
    func = function()
      local ok, err = pcall(function()
        card:set_ability(super, true, nil)
        if G and G.jokers and G.jokers.cards then
          local tracked = false
          for _, jc in ipairs(G.jokers.cards) do
            if jc == card then tracked = true; break end
          end
          if not tracked then table.insert(G.jokers.cards, card) end
        end
      end)
      if ok then
        s.is_base = false
        s.evolved = true
        _log(card, "POST-SCORING swap -> Super Mustard (ok)")
        if type(card_eval_status_text) == "function" then
          pcall(card_eval_status_text, card, 'extra', nil, nil, nil, { message = SETTINGS.evolve_msg })
        end
        if type(play_sound) == "function" then
          pcall(play_sound, SETTINGS.evolve_sound, 1.0, 0.95)
        end
      else
        _log(card, "enqueue_evolve: ERROR during swap: "..tostring(err))
      end
      return true
    end
  }))
end

---------------------------------------
-- Joker definition
---------------------------------------
local J = SMODS.Joker {
  key = "gaet_gaetano",
  loc_txt = {
    name = "Gaetano",
    text = {
      "After scoring, the {C:attention}first scored card{} becomes {C:attention}Gold{}.",
      "If {C:attention}5 Gold{} cards are scored,",
      "transform into {C:attention}Super Mustard Gaetano{}."
    }
  },
  rarity = 1,
  cost = 4,
  unlocked = true,
  discovered = true,
  atlas = SETTINGS.atlas_key,
  pos = SETTINGS.atlas_pos,
  blueprint_compat = false,
}

-- Ensure base Gaetano starts unlocked and discovered in both registries
local function ensure_unlocked_discovered_gaetano()
  local keys = { 'gaet_gaetano' }
  local regs = {}
  if SMODS and SMODS.CENTERS and SMODS.CENTERS.Joker then table.insert(regs, SMODS.CENTERS.Joker) end
  if G and G.P_CENTERS and G.P_CENTERS.Joker then table.insert(regs, G.P_CENTERS.Joker) end
  for _, reg in ipairs(regs) do
    for _, k in ipairs(keys) do
      local c = reg[k]
      if c then
        c.unlocked = true
        c.discovered = true
      end
    end
  end
end

ensure_unlocked_discovered_gaetano()

---------------------------------------
-- Lifecycle
---------------------------------------
function J:give(card, _)
  ensure_unlocked_discovered_gaetano()
  local s = _state(card)
  s.converted_hand = -1
  s.enqueued_hand = -1
  s.skip_logged_hand = -1
  s.last_seen_hand = -1
  _log(card, ("give(): ready (is_base=%s)"):format(tostring(s.is_base)))
end

function J:load(card, _)
  ensure_unlocked_discovered_gaetano() _state(card); _log(card, "load(): state ensured") end

function J:reset(card)
  local s = _state(card)
  s.converted_hand = -1
  s.enqueued_hand = -1
  _log(card, "reset(): hand gates cleared")
end

function J:update(card, _dt)
  local s = _state(card)
  local h = _current_hand_index()
  if s.last_seen_hand ~= h then
    s.last_seen_hand = h
    s.converted_hand = -1
    s.enqueued_hand = -1
    _log(card, ("update(): new hand %d detected, gates cleared (is_base=%s)"):format(h, tostring(s.is_base)))
  end
end

---------------------------------------
-- Scoring hook
---------------------------------------
function J:calculate(card, ctx)
  local s = _state(card)

  -- If already evolved, skip
  if s.is_base == false then
    local h = _current_hand_index()
    if s.skip_logged_hand ~= h then
      s.skip_logged_hand = h
      _log(card, "skip calculate (already evolved)")
    end
    return
  end

  if not ctx then return end

  -- After-scoring logic
  if ctx.after and ctx.scoring_hand then
    -- 1) Count only **Gold that actually scored** (and not debuffed), with a breakdown
    local gold_scored_count = 0
    _log(card, ("after: size=%d, listing scored cards..."):format(#ctx.scoring_hand))
    for i, c in ipairs(ctx.scoring_hand) do
      local enh = (c and c.ability and c.ability.enhancement) or c.enhancement or "nil"
      local cent = (c and c.center and c.center.key) or (c and c.config and c.config.center and c.config.center.key) or "nil"
      local deb = c and c.debuff and "DEBUFFED" or "ok"
      local area = _area_name(c)
      local gold = is_gold(c)
      if gold then gold_scored_count = gold_scored_count + 1 end
      _log(card, ("  [%d] area=%s, enh=%s, center=%s, debuff=%s, gold=%s %s")
        :format(i, area, tostring(enh), tostring(cent), deb, tostring(gold), gold and "[COUNTED]" or ""))
    end
    _log(card, "after: gold_scored_count = "..tostring(gold_scored_count))

    -- 2) Evolve AFTER scoring if >=5
    if (gold_scored_count >= 5) and (not s.evolved) then
      _log(card, "evolving (enqueue post-scoring) -> Super Mustard (>=5 Gold scored)")
      enqueue_evolve_post_scoring(card)
    else
      if not s.evolved then
        _log(card, "no evolve this hand (need >=5 Gold scored)")
      end
    end

    -- 3) Convert ONLY the first scored non-Gold to Gold (once per Joker per hand)
    local h = _current_hand_index()
    if s.converted_hand ~= h then
      s.converted_hand = h
      local sh = ctx.scoring_hand or {}
      G.E_MANAGER:add_event(Event({
        func = function()
          for _, c in ipairs(sh) do
            if c and not c.debuff and not is_gold(c) then
              make_gold(c)
              break
            end
          end
          return true
        end
      }))
    end
  end
end

return J
