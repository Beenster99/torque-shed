class_name ShedTv
extends Node3D
## A wall TV in the shed: a Dashboard screen on a bracket. Like the screens built into the shed
## it has channels (see TvChannels): live riding from a chase camera, the crew board, XP goals,
## how to play, money and contracts. The Workshop tunes it to what Shed.screens says.

var board: Dashboard


func _init(width: float, _height: float) -> void:
	board = Dashboard.new("crew", width)
	add_child(board)


## Shows the live picture (null for the page underneath) with a caption such as "LIVE: Simon on Old Faithful".
func show_feed(texture: Texture2D, caption: String) -> void:
	board.show_feed(texture, caption)


func is_live() -> bool:
	return board.is_live()
