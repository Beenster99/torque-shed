class_name QualitySlider
extends HBoxContainer
## The quality slider for ordering a bike, from worn (0) to new (1) in BikeCopy.QUALITY_STEPs,
## with what the quality it's at means written beside it. The "order one of these" card
## (BikeOrderPanel) and the parts computer's project bike order (PartsComputer) both use it; each
## says what a quality means for its own order (`describe`).

signal quality_changed(quality: float)

## What the line beside the slider says for a quality (BikeCopy.quality_text unless told otherwise).
var describe: Callable
var slider: HSlider
var text_label: Label


func _init(title := "QUALITY", start := 1.0) -> void:
	describe = func(q: float) -> String: return BikeCopy.quality_text(q)
	add_theme_constant_override("separation", 10)
	var ends := [UITheme.label(title, 15, UITheme.ACCENT), UITheme.label("Worn", 14, Color(1, 1, 1, 0.6)), UITheme.label("New", 14, Color(1, 1, 1, 0.6))]
	for l: Label in ends:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(ends[0])
	add_child(ends[1])
	slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = BikeCopy.QUALITY_STEP
	slider.value = start
	slider.custom_minimum_size = Vector2(200, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(_v):
		refresh()
		quality_changed.emit(quality()))
	add_child(slider)
	add_child(ends[2])
	text_label = UITheme.label("", 15)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.custom_minimum_size.x = 200.0
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(text_label)


func _ready() -> void:
	refresh()


## The quality it's at (0 worn .. 1 new, in steps).
func quality() -> float:
	return BikeCopy.quality_of(slider.value)


## Moves the slider (and says what it's at now).
func set_quality(q: float) -> void:
	slider.value = q
	refresh()


## Writes out what the quality it's at means.
func refresh() -> void:
	text_label.text = str(describe.call(quality()))
