@tool
class_name SerikaSdk
extends RefCounted

## Small config/facade for the SDK. API base + session token live in ProjectSettings
## (per-project) so a creator points the SDK at prod or a local server without editing code.

const SETTING_API_BASE := "serika/sdk/api_base_url"
const SETTING_TOKEN := "serika/sdk/session_token"
const DEFAULT_API_BASE := "https://api-social.ado.ink"

static func api_base() -> String:
	var v := String(ProjectSettings.get_setting(SETTING_API_BASE, DEFAULT_API_BASE))
	return v.strip_edges().trim_suffix("/")

static func session_token() -> String:
	return String(ProjectSettings.get_setting(SETTING_TOKEN, "")).strip_edges()

static func ensure_settings() -> void:
	if not ProjectSettings.has_setting(SETTING_API_BASE):
		ProjectSettings.set_setting(SETTING_API_BASE, DEFAULT_API_BASE)
		ProjectSettings.set_initial_value(SETTING_API_BASE, DEFAULT_API_BASE)
		ProjectSettings.add_property_info({
			"name": SETTING_API_BASE, "type": TYPE_STRING,
		})
	if not ProjectSettings.has_setting(SETTING_TOKEN):
		ProjectSettings.set_setting(SETTING_TOKEN, "")
		ProjectSettings.add_property_info({
			"name": SETTING_TOKEN, "type": TYPE_STRING,
			"hint": PROPERTY_HINT_PASSWORD,
		})
	ProjectSettings.save()
