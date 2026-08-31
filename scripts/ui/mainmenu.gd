extends CanvasLayer


func _on_start_game_pressed() -> void:
	get_tree().change_scene_to_file("res://Polyart/Meadows/demo/demo.tscn")


func _on_exit_game_pressed() -> void:
	get_tree().quit()
