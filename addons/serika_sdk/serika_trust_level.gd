## TrustLevel — utility for checking feature gates based on the author's trust level.
##
## Mirrors the trust_level_gates section in world_rules.json and HostCallTrust in the C# VM.
## The server checks at upload time; the client checks again at load time. Both MUST agree.
##
## Trust ladder (0–8):
##   0 Visitor, 1 Newcomer, 2 Member, 3 Regular, 4 Known,
##   5 Creator, 6 Trusted, 7 Partner, 8 Verified Creator
class_name SerikaTrustLevel
extends RefCounted

enum Feature {
	CUSTOM_SHADERS,
	PARTICLE_SYSTEMS,
	SPATIAL_AUDIO_ZONES,
	ADVANCED_NETWORKING,
	USER_INVITE_PORTALS,
	VIDEO_PLAYER,
}

const MIN_TRUST := {
	Feature.CUSTOM_SHADERS: 5,
	Feature.PARTICLE_SYSTEMS: 6,
	Feature.SPATIAL_AUDIO_ZONES: 6,
	Feature.ADVANCED_NETWORKING: 8,
	Feature.USER_INVITE_PORTALS: 5,
	Feature.VIDEO_PLAYER: 3,
}

const LABELS := [
	"Visitor", "Newcomer", "Member", "Regular", "Known",
	"Creator", "Trusted", "Partner", "Verified Creator",
]

static func label(level: int) -> String:
	level = clampi(level, 0, LABELS.size() - 1)
	return LABELS[level]

static func can_use(feature: int, trust_level: int) -> bool:
	return trust_level >= MIN_TRUST.get(feature, 0)

static func min_trust_for(feature: int) -> int:
	return MIN_TRUST.get(feature, 0)
