extends RefCounted
## Font helpers for the SKYRUSH UI. Three OFL families ship with the game:
##   - Smiley Sans / 得意黑 (oblique) — display text, Chinese headings, banners.
##   - Noto Sans SC (variable) — body / UI text, Chinese first.
##   - Oxanium (variable) — the upright squarish techno face of the Roadster reveal livestream
##     (roadster dossier §6.4), used for the flight telemetry values.
## All are under SIL OFL 1.1; the licences sit next to the files.

const SmileySansPath := "res://assets/fonts/SmileySans-Oblique.ttf"
const NotoSansScPath := "res://assets/fonts/NotoSansSC-Variable.ttf"
const OxaniumPath := "res://ui/theme/fonts/Oxanium-Variable.ttf"

## Weights of the Noto Sans SC variable font used by the UI.
const WEIGHT_TEXT := 500
const WEIGHT_BOLD := 800
const WEIGHT_BLACK := 900

static var _display: FontVariation = null
static var _text: FontVariation = null
static var _text_bold: FontVariation = null
static var _text_black: FontVariation = null
static var _techno: FontVariation = null
static var _tracked: Dictionary = {}


## The OpenType axis tag for "wght". Godot 4.7 ignores the *string* key "wght" in
## `variation_opentype` — the axis has to be addressed by its integer tag, otherwise the
## variable font stays at its default instance (Thin, wght 100).
static func _wght_tag() -> int:
	return TextServerManager.get_primary_interface().name_to_tag("wght")


## Display face: Smiley Sans 得意黑 (already oblique). Used for numbers and titles.
static func display() -> FontVariation:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = load(SmileySansPath) as FontFile
		_display.spacing_glyph = 0
	return _display


## UI face: Noto Sans SC, regular weight (500).
static func text() -> FontVariation:
	if _text == null:
		_text = _noto(WEIGHT_TEXT)
	return _text


## UI face, heavy weight (800) — Chinese headings and emphasis.
static func text_bold() -> FontVariation:
	if _text_bold == null:
		_text_bold = _noto(WEIGHT_BOLD)
	return _text_bold


## UI face, black weight (900) — the takedown banner's CJK line (dossier §3.5).
static func text_black() -> FontVariation:
	if _text_black == null:
		_text_black = _noto(WEIGHT_BLACK)
	return _text_black


## Upright squarish techno face for the reveal livestream gauges. Oxanium ships the OpenType
## "zero" feature, so the slashed zero of the livestream is a real glyph and not a drawn stroke.
static func techno() -> FontVariation:
	if _techno == null:
		_techno = FontVariation.new()
		_techno.base_font = load(OxaniumPath) as FontFile
		_techno.variation_opentype = {_wght_tag(): 500}
		_techno.opentype_features = {_feature_tag("zero"): true}
	return _techno


## The OpenType feature tag of a feature ("zero", "pnum", ...).
static func _feature_tag(name: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(name)


## The UI face with extra letter spacing (for wide-tracked small caps labels).
## The cache is keyed by the spacing: a later call with another spacing must not reuse this face.
static func text_tracked(spacing: int = 2) -> FontVariation:
	if not _tracked.has(spacing):
		var fv := _noto(WEIGHT_TEXT)
		fv.spacing_glyph = spacing
		_tracked[spacing] = fv
	return _tracked[spacing]


static func _noto(weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(NotoSansScPath) as FontFile
	fv.variation_opentype = {_wght_tag(): weight}
	return fv
