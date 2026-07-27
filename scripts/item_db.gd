class_name ItemDB
extends RefCounted
## All items are DATA. Rarities: C / R / SR / UR (boss relic).
## Effect fields are read by battle.gd:
##   max_hp / atk_flat / heal_flat / def_flat : additive numbers (stack)
##   type_flat: [spell_type, amount]
##   mode: item only drops in that lifeline mode
##   needs_flip: only drops for Virtuosa (the parry character)
##   instant: on-pickup effect ("heart"/"level_random"/"level_choice"/"level_choice2")
## Unique behaviors (power_glove, suit, …) are matched by id in battle.gd.
##
## NOT yet in the pool (systems pending): Clarity Lens (weird monsters),
## Rainbow Stone / Evil Eye (elemental effectiveness), Evil Seed (poison).

const ITEMS := {
	"cupcake": { "name": "Cupcake", "rarity": "C", "desc": "Max HP +20", "max_hp": 20 },
	"short_cake": { "name": "Short Cake", "rarity": "R", "desc": "Max HP +30", "max_hp": 30 },
	"chocolate_cake": { "name": "Chocolate Cake", "rarity": "SR", "desc": "Max HP +50", "max_hp": 50 },
	"protein_cake": { "name": "Protein Cake", "rarity": "UR", "desc": "Max HP +50, attack +10", "max_hp": 50, "atk_flat": 10 },
	"candy": { "name": "Candy", "rarity": "C", "desc": "+1 Life Heart", "mode": "hearts", "instant": "heart" },
	"band_aid": { "name": "Band-aid", "rarity": "R", "desc": "Once: willpower 0 -> 25%", "mode": "willpower" },
	"shiny_rock": { "name": "Shiny Rock", "rarity": "C", "desc": "Healing +10", "heal_flat": 10 },
	"gemstone": { "name": "Gemstone", "rarity": "R", "desc": "Healing +15", "heal_flat": 15 },
	"diamond": { "name": "Diamond", "rarity": "SR", "desc": "Healing +20", "heal_flat": 20 },
	"magical_crystal": { "name": "Magical Crystal", "rarity": "UR", "desc": "Heals also strike the enemy for 200%" },
	"training_weapon": { "name": "Training Weapon", "rarity": "C", "desc": "Attack +5", "atk_flat": 5 },
	"iron_weapon": { "name": "Iron Weapon", "rarity": "R", "desc": "Attack +8", "atk_flat": 8 },
	"platinum_weapon": { "name": "Platinum Weapon", "rarity": "SR", "desc": "Attack +12", "atk_flat": 12 },
	"buckler": { "name": "Buckler", "rarity": "C", "desc": "Damage taken -7", "def_flat": 7 },
	"shield": { "name": "Shield", "rarity": "R", "desc": "Damage taken -10", "def_flat": 10 },
	"armor": { "name": "Armor", "rarity": "SR", "desc": "Damage taken -15", "def_flat": 15 },
	"power_glove": { "name": "Power Glove", "rarity": "SR", "desc": "x1.2 attack at full HP" },
	"berserker_headgear": { "name": "Berserker Headgear", "rarity": "SR", "desc": "x1.5 attack at 0 HP" },
	"fire_stone": { "name": "Fire Stone", "rarity": "R", "desc": "Fire spells +10", "type_flat": ["fire", 10] },
	"water_stone": { "name": "Water Stone", "rarity": "R", "desc": "Water spells +15", "type_flat": ["water", 15] },
	"electric_stone": { "name": "Electric Stone", "rarity": "R", "desc": "Electric spells +15", "type_flat": ["electric", 15] },
	"spellbook_item": { "name": "Spellbook", "rarity": "C", "desc": "Level up a random spell", "instant": "level_random" },
	"ancient_grimoire": { "name": "Ancient Grimoire", "rarity": "R", "desc": "Level up a spell of your choice", "instant": "level_choice" },
	"precious_tome": { "name": "Precious Tome", "rarity": "SR", "desc": "Level up a spell of your choice, twice", "instant": "level_choice2" },
	"dimensional_ring": { "name": "Dimensional Ring", "rarity": "UR", "desc": "Max HP -> 0; willpower stops draining", "mode": "willpower" },
	"spiky_nail": { "name": "Spiky Nail", "rarity": "R", "desc": "Perfect parry deals 100 damage", "needs_flip": true },
	# (needs_flip items are Virtuosa-only)
	"flashy_nail": { "name": "Flashy Nail", "rarity": "SR", "desc": "Stuns last 12 beats", "needs_flip": true },
	"suit": { "name": "Power-Restricting Suit", "rarity": "SR", "desc": "Attack x0.2, +5% per crit (max 300%)" },
	"thunderous_gem": { "name": "Thunderous Gem", "rarity": "UR", "desc": "Attack x0.5, crits x3" },
	"x_matter": { "name": "X-Matter", "rarity": "UR", "desc": "Attack x0.8, wider crit window" },
}

static func has(items: Array, id: String) -> bool:
	return items.has(id)

## Sum an additive effect field across everything the player holds.
static func sum_field(items: Array, field: String) -> int:
	var total := 0
	for id in items:
		total += int(ITEMS.get(id, {}).get(field, 0))
	return total

static func type_flat(items: Array, spell_type: String) -> int:
	var total := 0
	for id in items:
		var tf = ITEMS.get(id, {}).get("type_flat")
		if tf != null and tf[0] == spell_type:
			total += int(tf[1])
	return total

## Would this item do literally nothing if max HP were frozen at 0? Derived
## rather than flagged per item, so a new cake needs no bookkeeping — and
## anything carrying a second effect keeps showing up on its own merits.
const OTHER_EFFECTS := ["atk_flat", "heal_flat", "def_flat", "type_flat", "instant"]

static func _dead_without_max_hp(it: Dictionary) -> bool:
	if not it.has("max_hp"):
		return false
	for field in OTHER_EFFECTS:
		if it.has(field):
			return false
	return true

## Random item of the given rarities, honoring lifeline/character limits.
## Items are unique per run: anything in `owned` never drops again.
static func roll(rarities: Array, life_mode: String, character: String, owned: Array) -> String:
	var pool: Array = []
	for id in ITEMS:
		var it: Dictionary = ITEMS[id]
		if owned.has(id):
			continue
		if not rarities.has(it["rarity"]):
			continue
		if it.has("mode") and it["mode"] != life_mode:
			continue
		if it.get("needs_flip", false) and character != "virtuosa":
			continue
		# The Dimensional Ring pins max HP at 0 for the rest of the run, so a
		# plain cake becomes a blank — stop offering those. Anything that also
		# does something else (Protein Cake's +10 attack) still earns its slot.
		if owned.has("dimensional_ring") and _dead_without_max_hp(it):
			continue
		pool.append(id)
	return pool.pick_random() if not pool.is_empty() else ""
