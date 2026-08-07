-- Overrides.lua — HAND-AUTHORED corrections and additions.
-- This file holds only the irreducible minimum the client APIs cannot provide:
-- navigation targets for quest/vendor/world sets, classification fixes, and
-- flags for sets that are no longer obtainable.
--
-- `sets` is keyed by baseSetID (applies to the whole group) or by a variant
-- setID (the more specific key wins). Fields, all optional:
--   map, x, y    : navigation target (uiMapID + 0-100 coords) for non-instance sets
--   npc          : vendor/NPC name (English key, translated via ns.L)
--   questID      : quest the set comes from (title resolved live, localized)
--   ct           : content-type correction ("raid", "pvp", ...)
--   j            : journalInstanceID correction (wrongly resolved / unresolved drops)
--   legacy       : true when the set can no longer be obtained
--
-- `instances` is keyed by journalInstanceID:
--   entranceMaps : candidate uiMapIDs scanned live for a moving portal
--   map, x, y    : manual entrance coords, used when the live scan finds nothing
--
-- Use `/esc missing` in game to list sets that still have no navigation target.

EasySetCollectionOverrides = {
  sets = {
  },
  instances = {
  },
}
