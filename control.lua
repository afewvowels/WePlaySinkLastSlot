-- WePlay: Sink Last Slot — runtime
-- Every chest (regular and logistic) and every storage tank gets a toggle in its GUI.
--   Chests: fill normally; anything in the last usable slot (just before the red
--           limit bar, if set) is deleted.
--   Tanks:  keep the top `headroom` units of capacity free by voiding any fluid
--           above that line.
-- Entities nobody has toggled follow the per-kind "by default" map settings.

local KIND = {
  ["container"] = "chest",
  ["logistic-container"] = "chest",
  ["storage-tank"] = "tank"
}
local TYPES = { "container", "logistic-container", "storage-tank" }
local FRAME = "wp_sink_last_slot_frame"
local CHECK = "wp_sink_last_slot_checkbox"

-- storage.overrides : unit_number -> bool   (explicit per-entity choice)
-- storage.active    : unit_number -> entity (entities currently sinking)
-- storage.list      : array of unit_numbers (round-robin order)
-- storage.in_list   : unit_number -> true
-- storage.cursor    : round-robin position
-- storage.open      : player_index -> entity (entity whose GUI is open)

local function init_storage()
  storage.overrides = storage.overrides or {}
  storage.active = storage.active or {}
  storage.list = storage.list or {}
  storage.in_list = storage.in_list or {}
  storage.cursor = storage.cursor or 1
  storage.open = storage.open or {}
  storage.float_location = storage.float_location or {}
end

local function setting(name)
  return settings.global["wp-sink-last-slot-" .. name].value
end

local function kind_of(entity)
  return KIND[entity.type]
end

local function is_supported(entity)
  return entity and entity.valid and KIND[entity.type] ~= nil and entity.unit_number ~= nil
end

local function default_on(entity)
  if kind_of(entity) == "tank" then return setting("tanks-default-on") end
  return setting("chests-default-on")
end

local function is_on(entity)
  local o = storage.overrides[entity.unit_number]
  if o == nil then return default_on(entity) end
  return o
end

local function activate(entity)
  local id = entity.unit_number
  storage.active[id] = entity
  if not storage.in_list[id] then
    storage.in_list[id] = true
    storage.list[#storage.list + 1] = id
  end
end

local function refresh_active(entity)
  if not is_supported(entity) then return end
  if is_on(entity) then
    activate(entity)
  else
    storage.active[entity.unit_number] = nil  -- pruned from the list lazily
  end
end

local function set_override(entity, value)
  storage.overrides[entity.unit_number] = value
  script.register_on_object_destroyed(entity)
  refresh_active(entity)
end

local function rebuild()
  storage.active, storage.list, storage.in_list, storage.cursor = {}, {}, {}, 1
  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered({ type = TYPES })) do
      if e.unit_number and is_on(e) then activate(e) end
    end
  end
end

-- Sinking ------------------------------------------------------------

local function sink_chest(entity)
  local inv = entity.get_inventory(defines.inventory.chest)
  if not inv or #inv == 0 then return end
  local last = #inv
  if inv.supports_bar() then
    last = math.min(inv.get_bar() - 1, #inv)  -- get_bar() = #inv + 1 when no bar is set
  end
  if last >= 1 then
    local stack = inv[last]
    if stack.valid_for_read then stack.clear() end
  end
end

-- Fluid API access is wrapped in pcall: accessing a key that doesn't exist on
-- LuaEntity raises an error, and the fluid API has changed between versions.
-- Each step tries every known API; the first one that works is remembered.
local capacity_cache = {}   -- entity name -> capacity (not saved; rebuilt on demand)
local tank_api_broken = false
local read_method, remove_method   -- index into the strategy tables below, once one works

local function try(f)
  local ok, result = pcall(f)
  if ok then return true, result end
  return false, tostring(result):gsub("\n.*", "")  -- first line of the error only
end

local function tank_capacity(entity)
  local cap = capacity_cache[entity.name]
  if cap then return cap end
  local attempts = {
    function() return entity.prototype.fluid_capacity end,
    function() return entity.prototype.get_fluid_capacity() end,
    function() return entity.fluidbox.get_capacity(1) end
  }
  cap = 0
  for _, f in ipairs(attempts) do
    local ok, value = try(f)
    if ok and type(value) == "number" and value > 0 then cap = value break end
  end
  capacity_cache[entity.name] = cap
  return cap
end

-- Each reader returns a list of { index = i or nil, name, amount, temperature }
-- Readers that know the fluidbox index come first; get_fluid_contents is the
-- last resort (no index, so removal assumes fluidbox 1).
local READERS = {
  function(entity)
    local list = {}
    for i = 1, entity.fluids_count do
      local f = entity.get_fluid(i)
      if f then list[#list + 1] = { index = i, name = f.name, amount = f.amount, temperature = f.temperature } end
    end
    return list
  end,
  function(entity)
    local list, fb = {}, entity.fluidbox
    for i = 1, #fb do
      local f = fb[i]
      if f then list[#list + 1] = { index = i, name = f.name, amount = f.amount, temperature = f.temperature } end
    end
    return list
  end,
  function(entity)
    local list = {}
    for name, amount in pairs(entity.get_fluid_contents()) do
      list[#list + 1] = { name = name, amount = amount }
    end
    return list
  end
}

-- Each remover takes (entity, fluid, take) and removes `take` units of `fluid`
local REMOVERS = {
  function(entity, fluid, take)   -- 2.1: remove_fluid(fluidbox_index, amount)
    entity.remove_fluid(fluid.index or 1, take)
  end,
  function(entity, fluid, take)   -- 2.0: remove_fluid{name=, amount=}
    entity.remove_fluid({ name = fluid.name, amount = take })
  end,
  function(entity, fluid, take)
    assert(fluid.index, "no fluid index")
    entity.set_fluid(fluid.index, { name = fluid.name, amount = fluid.amount - take, temperature = fluid.temperature })
  end,
  function(entity, fluid, take)
    assert(fluid.index, "no fluid index")
    entity.fluidbox[fluid.index] = { name = fluid.name, amount = fluid.amount - take, temperature = fluid.temperature }
  end
}

local function run_strategies(list, cached, ...)
  local args = { ... }
  if cached then
    local ok, result = try(function() return list[cached](table.unpack(args)) end)
    if ok then return cached, result end
  end
  local errors = {}
  for i, f in ipairs(list) do
    local ok, result = try(function() return f(table.unpack(args)) end)
    if ok then return i, result end
    errors[#errors + 1] = result
  end
  return nil, table.concat(errors, " | ")
end

local function report_broken(reason)
  if tank_api_broken then return end
  tank_api_broken = true
  game.print({ "", "[WePlay: Sink Last Slot] Tank voiding disabled for this session: ", reason,
    ". Chests still work. Please report this on the mod portal!" })
  log("Tank voiding disabled: " .. reason)
end

local function sink_tank(entity, headroom)
  if tank_api_broken then return end

  local cap = tank_capacity(entity)
  if cap <= 0 then return report_broken("couldn't read tank capacity for " .. entity.name) end

  local method, contents = run_strategies(READERS, read_method, entity)
  if not method then return report_broken("couldn't read tank contents (" .. contents .. ")") end
  read_method = method

  local total = 0
  for _, fluid in pairs(contents) do total = total + fluid.amount end

  local keep_free = headroom
  if keep_free >= cap then keep_free = cap * 0.1 end
  local excess = total - (cap - keep_free)
  if excess <= 0 then return end

  for _, fluid in pairs(contents) do
    local take = math.min(fluid.amount, excess)
    local m, err = run_strategies(REMOVERS, remove_method, entity, fluid, take)
    if not m then return report_broken("couldn't remove fluid (" .. err .. ")") end
    remove_method = m
    excess = excess - take
    if excess <= 0 then break end
  end
end

-- Spread the work so every active entity is checked once per `interval` ticks
local function on_tick()
  local list = storage.list
  if #list == 0 then return end

  local per_tick = math.ceil(#list / setting("check-interval"))
  local headroom = setting("fluid-headroom")

  local i = storage.cursor
  for _ = 1, per_tick do
    if #list == 0 then break end
    if i > #list then i = 1 end
    local id = list[i]
    local entity = storage.active[id]
    if entity and entity.valid then
      if kind_of(entity) == "tank" then
        sink_tank(entity, headroom)
      else
        sink_chest(entity)
      end
      i = i + 1
    else
      -- toggled off or removed: swap-remove from the list
      storage.active[id] = nil
      storage.in_list[id] = nil
      list[i] = list[#list]
      list[#list] = nil
    end
  end
  storage.cursor = i
end

-- GUI ----------------------------------------------------------------

-- Candidate relative GUI types per entity type, in order of preference.
-- If none exist in this game version, the panel floats on screen instead.
local ANCHOR_CANDIDATES = {
  ["container"] = { "container_gui" },
  ["logistic-container"] = { "logistic_container_gui", "container_gui" },
  ["storage-tank"] = { "storage_tank_gui", "pipe_gui" }
}

-- If none of the known names exist, scan whatever relative GUI types this game
-- version actually has. Patterns are tried in order; first match wins.
local ANCHOR_PATTERNS = {
  ["storage-tank"] = { "storage_tank", "tank", "fluid" }
}
local EXCLUDE = { "wagon", "turret", "generator", "boiler" }

local anchor_cache = {}   -- entity type -> relative_gui_type value, or false

local function scan_anchor(entity_type)
  local patterns = ANCHOR_PATTERNS[entity_type]
  if not patterns then return nil end
  local keys = {}
  for k in pairs(defines.relative_gui_type) do keys[#keys + 1] = k end
  table.sort(keys)  -- deterministic choice
  for _, pattern in ipairs(patterns) do
    for _, k in ipairs(keys) do
      if k:find(pattern, 1, true) then
        local excluded = false
        for _, bad in ipairs(EXCLUDE) do
          if k:find(bad, 1, true) then excluded = true break end
        end
        if not excluded then return defines.relative_gui_type[k] end
      end
    end
  end
  return nil
end

local function anchor_for(entity)
  local cached = anchor_cache[entity.type]
  if cached == nil then
    cached = false
    local rgt = defines.relative_gui_type
    for _, key in ipairs(ANCHOR_CANDIDATES[entity.type] or {}) do
      if rgt[key] then cached = rgt[key] break end
    end
    if not cached then cached = scan_anchor(entity.type) or false end
    anchor_cache[entity.type] = cached
  end
  if cached then
    return { gui = cached, position = defines.relative_gui_position.right }
  end
  return nil
end

-- The panel lives in either gui.relative (anchored) or gui.screen (floating)
local function find_frame(player)
  return player.gui.relative[FRAME] or player.gui.screen[FRAME]
end

local function destroy_gui(player)
  local frame = player.gui.relative[FRAME]
  if frame then frame.destroy() end
  frame = player.gui.screen[FRAME]
  if frame then frame.destroy() end
  storage.open[player.index] = nil
end

local function build_gui(player, entity)
  destroy_gui(player)
  local tank = kind_of(entity) == "tank"
  local spec = {
    type = "frame",
    name = FRAME,
    caption = { "wp-sink-last-slot.title" },
    direction = "vertical"
  }

  local frame
  local anchor = anchor_for(entity)
  if anchor then
    spec.anchor = anchor
    frame = player.gui.relative.add(spec)
  else
    -- Floating fallback: draggable, remembers where the player put it
    spec.caption = nil
    frame = player.gui.screen.add(spec)
    local bar = frame.add({ type = "flow", direction = "horizontal" })
    bar.drag_target = frame
    bar.add({ type = "label", caption = { "wp-sink-last-slot.title" }, style = "frame_title", ignored_by_interaction = true })
    local handle = bar.add({ type = "empty-widget", style = "draggable_space_header" })
    handle.style.height = 24
    handle.style.minimal_width = 24
    handle.style.horizontally_stretchable = true
    handle.drag_target = frame

    local saved = storage.float_location and storage.float_location[player.index]
    if saved then
      frame.location = saved
    else
      -- Default: just right of the entity window, level with its top
      local res, scale = player.display_resolution, player.display_scale
      frame.location = { x = math.floor(res.width / 2 + 200 * scale), y = math.floor(res.height / 2 - 295 * scale) }
    end
  end
  frame.add({
    type = "checkbox",
    name = CHECK,
    state = is_on(entity),
    caption = tank and { "wp-sink-last-slot.toggle-tank" } or { "wp-sink-last-slot.toggle-chest" },
    tooltip = tank and { "wp-sink-last-slot.toggle-tank-tooltip", setting("fluid-headroom") }
                    or { "wp-sink-last-slot.toggle-chest-tooltip" }
  })
  storage.open[player.index] = entity
end

-- Keep every player who has this entity open in sync
local function sync_open_guis(entity)
  local state = is_on(entity)
  for _, player in pairs(game.connected_players) do
    local open = storage.open[player.index]
    if open and open.valid and open.unit_number == entity.unit_number then
      local frame = find_frame(player)
      if frame and frame[CHECK] then frame[CHECK].state = state end
    end
  end
end

script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.get_player(event.player_index)
  if event.gui_type == defines.gui_type.entity and is_supported(event.entity) then
    build_gui(player, event.entity)
  else
    destroy_gui(player)
  end
end)

script.on_event(defines.events.on_gui_location_changed, function(event)
  local el = event.element
  if el and el.valid and el.name == FRAME then
    storage.float_location = storage.float_location or {}
    storage.float_location[event.player_index] = el.location
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  if event.gui_type == defines.gui_type.entity then
    destroy_gui(game.get_player(event.player_index))
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  if event.element.name ~= CHECK then return end
  local entity = storage.open[event.player_index]
  if not is_supported(entity) then return end
  set_override(entity, event.element.state)
  sync_open_guis(entity)
end)

-- Copy-paste settings carries the toggle between entities of the same kind
script.on_event(defines.events.on_entity_settings_pasted, function(event)
  local src, dst = event.source, event.destination
  if is_supported(src) and is_supported(dst) and kind_of(src) == kind_of(dst) then
    set_override(dst, is_on(src))
    sync_open_guis(dst)
  end
end)

-- Building / removal -------------------------------------------------

local function on_built(event)
  refresh_active(event.entity)
end

local function on_cloned(event)
  local src, dst = event.source, event.destination
  if is_supported(src) and is_supported(dst) then
    local o = storage.overrides[src.unit_number]
    if o ~= nil then set_override(dst, o) else refresh_active(dst) end
  end
end

local build_filter = {
  { filter = "type", type = "container" },
  { filter = "type", type = "logistic-container" },
  { filter = "type", type = "storage-tank" }
}

script.on_event(defines.events.on_built_entity, on_built, build_filter)
script.on_event(defines.events.on_robot_built_entity, on_built, build_filter)
script.on_event(defines.events.on_space_platform_built_entity, on_built, build_filter)
script.on_event(defines.events.script_raised_built, on_built, build_filter)
script.on_event(defines.events.script_raised_revive, on_built, build_filter)
script.on_event(defines.events.on_entity_cloned, on_cloned, build_filter)

-- Forget overrides for entities that no longer exist
script.on_event(defines.events.on_object_destroyed, function(event)
  if event.useful_id then storage.overrides[event.useful_id] = nil end
end)

-- Lifecycle ----------------------------------------------------------

script.on_init(function()
  init_storage()
  rebuild()
end)

script.on_configuration_changed(function()
  init_storage()
  rebuild()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "wp-sink-last-slot-chests-default-on"
      or event.setting == "wp-sink-last-slot-tanks-default-on" then
    rebuild()
    for _, player in pairs(game.connected_players) do
      local open = storage.open[player.index]
      if open and open.valid then sync_open_guis(open) end
    end
  end
end)

script.on_event(defines.events.on_tick, on_tick)
