extends CanvasLayer

@onready var joystick = $TouchScreenJoystick
@onready var health_display = $HealthDisplay
@onready var health_fill = null
@onready var stats_display = $StatsDisplay
@onready var kill_feed = $KillFeed

const MAX_KILL_FEED_ENTRIES = 5
const KILL_FEED_DISPLAY_TIME = 5.0 # Time in seconds to display kill feed messages

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

# Update the kill/death stats display
func update_stats_display(kills, deaths):
	if stats_display:
		stats_display.text = "KILLS: " + str(kills) + " | DEATHS: " + str(deaths)

# Add a kill message to the kill feed
func add_kill_feed_message(killer_name, killer_color, victim_name, victim_color):
	if !kill_feed:
		return
		
	# Create the kill feed entry
	var kill_entry = HBoxContainer.new()
	kill_entry.size_flags_horizontal = Control.SIZE_FILL
	kill_entry.alignment = BoxContainer.ALIGNMENT_END
	
	# Create killer label with color
	var killer_label = Label.new()
	killer_label.text = killer_name
	killer_label.modulate = killer_color
	killer_label.set("theme_override_font_sizes/font_size", 14)
	kill_entry.add_child(killer_label)
	
	# Add killed text
	var killed_label = Label.new()
	killed_label.text = " killed "
	killed_label.set("theme_override_font_sizes/font_size", 14)
	kill_entry.add_child(killed_label)
	
	# Create victim label with color
	var victim_label = Label.new()
	victim_label.text = victim_name
	victim_label.modulate = victim_color
	victim_label.set("theme_override_font_sizes/font_size", 14)
	kill_entry.add_child(victim_label)
	
	# Add to kill feed
	kill_feed.add_child(kill_entry)
	
	# Limit the number of entries
	while kill_feed.get_child_count() > MAX_KILL_FEED_ENTRIES:
		var oldest_entry = kill_feed.get_child(0)
		kill_feed.remove_child(oldest_entry)
		oldest_entry.queue_free()
	
	# Set up auto-removal timer
	var timer = Timer.new()
	timer.wait_time = KILL_FEED_DISPLAY_TIME
	timer.one_shot = true
	kill_entry.add_child(timer)
	timer.timeout.connect(func(): remove_kill_feed_entry(kill_entry))
	timer.start()

# Remove a kill feed entry
func remove_kill_feed_entry(entry):
	if kill_feed and kill_feed.has_node(entry.get_path()):
		kill_feed.remove_child(entry)
		entry.queue_free()
