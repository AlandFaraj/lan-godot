extends CanvasLayer

@onready var joystick = $TouchScreenJoystick
@onready var health_display = $HealthDisplay
@onready var health_fill = null

func _ready():
	var is_mobile = OS.get_name() in ["Android", "iOS"]
	joystick.visible = is_mobile
	if is_mobile:
		joystick.use_input_actions = true
		joystick.action_left = "move_left"
		joystick.action_right = "move_right"
		joystick.action_up = "move_forward"
		joystick.action_down = "move_back"
	
	# Cache the health fill style for color updates
	if health_display:
		health_fill = health_display.get_theme_stylebox("fill")

# Update the health display when player health changes
func update_health_display(value, color = null):
	if health_display:
		health_display.value = value
		
		# Update the health bar color if a color is provided
		if color and health_fill:
			health_fill.bg_color = Color(color.r, color.g, color.b, 1.0)
