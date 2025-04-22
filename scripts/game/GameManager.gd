extends Node

var Players = {}
var last_joined_ip = ""

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

# Initialize a new player's stats to ensure kills and deaths are set
func init_player_stats(player_id, player_name, color):
	if !Players.has(player_id):
		Players[player_id] = {
			"name": player_name,
			"id": player_id,
			"score": 0,
			"color": color,
			"kills": 0,
			"deaths": 0
		}
	return Players[player_id]

# Reset player data when leaving a game
# This ensures clean state for rejoining
func reset_player_data():
	Players.clear()
	# Keep the last_joined_ip for potential reconnect
	# but ensure any stale references to other game data are cleared
	
	# You can reset other game-related variables here
	# as your game grows in complexity
