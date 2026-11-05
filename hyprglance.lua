local M = {}

local MODIFIER_KEYCODES = {
  SUPER = { 133, 134 },
  ALT = { 64, 108 },
  CTRL = { 37, 105 },
}

local SUBMAP = "hyprglance"

function HYPRGLANCE_UNDIM(undim)
  if undim and HYPRGLANCE_DIM == nil then
    HYPRGLANCE_DIM = hl.get_config("decoration.dim_inactive")
    hl.config({ decoration = { dim_inactive = false } })
  elseif not undim and HYPRGLANCE_DIM ~= nil then
    hl.config({ decoration = { dim_inactive = HYPRGLANCE_DIM } })
    HYPRGLANCE_DIM = nil
  end
end

local function send(command)
  hl.dispatch(hl.dsp.event("hyprglance " .. command))
end

local function close(command)
  send(command)
  hl.dispatch(hl.dsp.submap("reset"))
end

function M.setup(opts)
  opts = opts or {}
  local mod = (opts.mod or "SUPER"):upper()
  local keycodes = MODIFIER_KEYCODES[mod] or error("hyprglance: mod must be SUPER, ALT or CTRL")
  local key = opts.key or "Tab"
  local timeout = opts.timeout or 30000
  local overviewKey = opts.overviewKey == nil and "F3" or opts.overviewKey
  local closeKey = opts.closeKey == nil and "Q" or opts.closeKey

  local released = {}
  for _, code in ipairs(keycodes) do
    released[code] = true
  end

  hl.define_submap(SUBMAP, function()
    hl.bind(mod .. " + " .. key, function() send("next") end, { repeating = true })
    hl.bind(mod .. " + SHIFT + " .. key, function() send("prev") end, { repeating = true })
    hl.bind(mod .. " + Escape", function() close("cancel") end)
    hl.bind("Escape", function() close("cancel") end)
    if closeKey then
      hl.bind(mod .. " + " .. closeKey, function() send("close") end)
    end
  end)

  if HYPRGLANCE_RELEASE then HYPRGLANCE_RELEASE:remove() end
  HYPRGLANCE_RELEASE = hl.on("input.keyboard.key", function(code, _, state)
    if state == 0 and released[code] and hl.get_current_submap() == SUBMAP then close("commit") end
  end)

  local session = 0
  local function open(command)
    session = session + 1
    local current = session
    send(command)
    hl.dispatch(hl.dsp.submap(SUBMAP))
    hl.timer(function()
      if current == session and hl.get_current_submap() == SUBMAP then close("cancel") end
    end, { timeout = timeout, type = "oneshot" })
  end

  hl.bind(mod .. " + " .. key, function() open("next") end)
  hl.bind(mod .. " + SHIFT + " .. key, function() open("prev") end)

  hl.layer_rule({ name = "hyprglance-overview", match = { namespace = "^hyprglance-overview$" }, blur = true })

  if overviewKey then
    hl.bind(overviewKey, function() send("overview") end)
  end
end

return M
