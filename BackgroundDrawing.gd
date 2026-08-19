extends Control

@export var is_victory_screen: bool = false

func _draw():
	var rect_area = Rect2(Vector2(100, 100), size - Vector2(200, 200))
	
	# Draw an Adeptus Mechanicus style technical border frame
	var border_color = Color(0.2, 0.8, 0.4, 0.8) if is_victory_screen else Color(0.9, 0.2, 0.2, 0.8)
	draw_rect(rect_area, Color(0.05, 0.05, 0.08, 0.9), true) # Dark core background
	draw_rect(rect_area, border_color, false, 4.0)          # Outer tactical border
	
	# Draw corner technical crosshairs
	draw_line(rect_area.position, rect_area.position + Vector2(20, 0), border_color, 3.0)
	draw_line(rect_area.position, rect_area.position + Vector2(0, 20), border_color, 3.0)
