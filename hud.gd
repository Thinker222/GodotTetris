extends Node2D

signal start_game

func _on_start_button_pressed() -> void:
	$StartButton.hide()
	start_game.emit()
