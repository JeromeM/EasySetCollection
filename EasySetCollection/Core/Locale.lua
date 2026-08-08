-- Locale.lua — localization scaffolding. Loads before everything else.
-- ns.L[key] returns the localized string, falling back to the key itself
-- (the English source) when a locale is missing an entry.

local ADDON, ns = ...

ns.L = setmetatable({}, { __index = function(_, k) return k end })

--- Print a chat-frame message prefixed with the coloured addon tag.
---@param msg any  message to display (coerced to string)
function ns.Print(msg)
  print("|cffffd200ESC|r: " .. tostring(msg))
end
