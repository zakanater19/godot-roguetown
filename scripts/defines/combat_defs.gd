# res://scripts/defines/combat_defs.gd
# Central definitions for all combat, movement, and action tuning values.
# Reference via CombatDefs.UNARMED_BASE_DAMAGE, CombatDefs.DODGE_BASE_CHANCE, etc.
class_name CombatDefs

# ---------------------------------------------------------------------------
# Damage
# ---------------------------------------------------------------------------
const UNARMED_BASE_DAMAGE:     int   = 5
const STRENGTH_DAMAGE_SCALE:   float = 0.05   # modifier per stat point above/below 10

# ---------------------------------------------------------------------------
# Fall damage
# ---------------------------------------------------------------------------
const FALL_DAMAGE_MIN:         int   = 20
const FALL_DAMAGE_MAX:         int   = 30

# ---------------------------------------------------------------------------
# Parry (defender in parry stance with a sword)
# ---------------------------------------------------------------------------
const PARRY_AVOIDANCE_SCALE:   float = 17.0   # avoidance % per skill diff (defender - attacker)
const PARRY_AVOIDANCE_MAX:     float = 98.0

# ---------------------------------------------------------------------------
# Dodge (defender in dodge stance)
# ---------------------------------------------------------------------------
const DODGE_BASE_CHANCE:       float = 20.0
const DODGE_AGILITY_SCALE:     float = 5.0    # avoidance % per agility point above/below 10
const DODGE_AVOIDANCE_MAX:     float = 85.0

# ---------------------------------------------------------------------------
# Directional attack avoidance multipliers
# ---------------------------------------------------------------------------
const BACK_ATTACK_AVOIDANCE_MULT: float = 0.1
const SIDE_ATTACK_AVOIDANCE_MULT: float = 0.5

# ---------------------------------------------------------------------------
# Stamina
# ---------------------------------------------------------------------------
const STAMINA_MIN_TO_DEFEND:   float = 3.0    # stamina floor below which defense is disabled
const STAMINA_BLOCK_COST:      float = 3.0    # stamina drained on a successful block/dodge
const STAMINA_RESIST_BASE:     float = 20.0   # base stamina pool used in resist chance math

# ---------------------------------------------------------------------------
# Lying-down penalty
# ---------------------------------------------------------------------------
const LYING_DOWN_RESIST_MULT:  float = 0.2    # resist break_chance multiplier when lying down

# ---------------------------------------------------------------------------
# Grab / resist cooldowns (milliseconds)
# ---------------------------------------------------------------------------
const GRAB_COOLDOWN_MS:        int   = 1000
const RESIST_COOLDOWN_MS:      int   = 1000

# ---------------------------------------------------------------------------
# Action / attack cooldowns
# ---------------------------------------------------------------------------
const DEFAULT_ACTION_DELAY:    float = 0.5    # seconds between generic actions
const MIN_ATTACK_DELAY:        float = 1.0    # minimum seconds between attacks
const EXHAUSTED_DELAY_MULT:    float = 3.0    # action delay multiplier when exhausted

# ---------------------------------------------------------------------------
# Stamina — player stamina pool and regeneration
# ---------------------------------------------------------------------------
const STAMINA_MAX:                  float = 100.0  # starting and maximum stamina
const STAMINA_REGEN_DELAY:          float = 5.0    # seconds after exertion before regen starts
const STAMINA_REGEN_RATE:           float = 4.0    # stamina per second during regen
const STAMINA_EXHAUSTION_THRESHOLD: float = 10.0   # stamina must reach this to clear exhausted
const STAMINA_EXERTION_COST:        float = 5.0    # stamina spent per physical action

# ---------------------------------------------------------------------------
# Limb HP — each limb starts at LIMB_HP_MAX; damage taken = LIMB_HP_MAX - current
# ---------------------------------------------------------------------------
const LIMB_HP_MAX:     int = 70
const LIMB_BROKEN:     int = 70   # damage_taken >= this → "broken"
const LIMB_MANGLED:    int = 60   # damage_taken >= this → "mangled"
const LIMB_SEVERE:     int = 40   # damage_taken >= this → "severely injured"
const LIMB_INJURED:    int = 20   # damage_taken >= this → "injured"