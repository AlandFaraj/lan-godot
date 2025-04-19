# Godot LAN Game Rework Plan

This document outlines the steps for reworking the Godot LAN multiplayer game based on the user's requirements.

## 1. Project Setup & Refactoring

*   [x] Rename `scripts/networking/MutiplayerController.gd` to `MultiplayerController.gd` and update all scene/script references.
*   [x] Ensure `GameManager` is set up as an autoload singleton in `Project -> Project Settings -> Autoload` for easy global access.
*   [x] Review `project.godot` (`Project -> Project Settings -> Input Map`) and define necessary actions if missing (e.g., `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `shoot`, `ui_cancel`, `toggle_leaderboard`). Add specific touch actions later.

## 2. UI Overhaul (Hosting & Joining)

*   [ ] Create a new main menu scene: `scenes/ui/MainMenu.tscn`. Set it as the main scene in project settings.
*   [ ] **`MainMenu.tscn` Structure:**
    *   [ ] Add root `Control` node.
    *   [ ] Add `PanelContainer` for main options (Host, Join, Settings, Quit).
    *   [ ] Add separate `PanelContainer` nodes for "Host Game" and "Join Game" sections (initially hidden).
    *   [ ] Add Buttons: "Host Game", "Join Game", "Settings", "Quit".
*   [ ] **Host Game Panel:**
    *   [ ] Add `LineEdit` for Server Name.
    *   [ ] Add `LineEdit` for Player Name.
    *   [ ] Add `ColorPickerButton` for player color selection.
    *   [ ] Add "Start Hosting" button.
    *   [ ] Add "Back" button.
*   [ ] **Join Game Panel:**
    *   [ ] Add `ItemList` or `VBoxContainer` to display discovered LAN games.
    *   [ ] Add "Refresh" button.
    *   [ ] Add `LineEdit` for manual IP entry.
    *   [ ] Add "Join Manual IP" button.
    *   [ ] Add `LineEdit` for Player Name.
    *   [ ] Add `ColorPickerButton` for player color selection.
    *   [ ] Add `Label` for status messages.
    *   [ ] Add "Back" button.
*   [ ] Create `scripts/ui/MainMenu.gd` and attach it to `MainMenu.tscn`.
*   [ ] **`MainMenu.gd` Logic:**
    *   [ ] Implement button signal connections (`pressed`).
    *   [ ] Show/hide Host/Join panels.
    *   [ ] On "Start Hosting": Get player name/color, call `MultiplayerController.hostGame()`, pass necessary info.
    *   [ ] On "Join Game" selection or "Join Manual IP": Get player name/color, call `MultiplayerController.joinGame()`, pass necessary info.
    *   [ ] Integrate with `ServerBrowser.gd` to populate the games list. Connect to `ServerBrowser` signals if needed or call its functions.
    *   [ ] Handle transitions to the game scene upon successful connection.
    *   [ ] Handle "Quit" button (`get_tree().quit()`).

## 3. Player Customization (Color)

*   [ ] **`MultiplayerController.gd`:**
    *   [ ] Modify `SendPlayerInformation` RPC signature: `SendPlayerInformation(player_name, id, player_color)`.
    *   [ ] Update the `GameManager.Players[id]` dictionary structure to include: `"color": player_color`.
    *   [ ] When hosting/joining, get the color from the `MainMenu` UI and pass it to `SendPlayerInformation`.
    *   [ ] In the server's loop inside `SendPlayerInformation` (where it informs others), ensure the color is included: `SendPlayerInformation.rpc(GameManager.Players[i].name, i, GameManager.Players[i].color)`.
*   [ ] **`player3D.gd`:**
    *   [ ] Add `@export var player_color: Color = Color.WHITE`.
    *   [ ] Add `@onready var mesh_instance: MeshInstance3D = $MeshInstance3D` (Adjust path if needed). Ensure the player mesh exists.
    *   [ ] Add RPC function:
        ```gd
        @rpc("any_peer", "call_local")
        func set_player_color(new_color: Color):
            player_color = new_color
            if mesh_instance:
                # Ensure material override exists
                if not mesh_instance.material_override:
                    mesh_instance.material_override = StandardMaterial3D.new()
                # Set albedo color
                if mesh_instance.material_override is StandardMaterial3D:
                    mesh_instance.material_override.albedo_color = new_color
                else:
                    # Handle other material types or create a new StandardMaterial3D
                    push_warning("Player mesh material override is not StandardMaterial3D. Creating new one.")
                    var new_material = StandardMaterial3D.new()
                    new_material.albedo_color = new_color
                    mesh_instance.material_override = new_material
        ```
*   [ ] **`SceneManager.gd`:**
    *   [ ] In `spawn_player(id)`, *after* adding the `character` node:
        ```gd
        if GameManager.Players.has(id) and GameManager.Players[id].has("color"):
            var color = GameManager.Players[id].color
            # Call RPC to sync color to all clients including self
            character.set_player_color.rpc(color)
        else:
            # Fallback or error handling if color info is missing
             character.set_player_color.rpc(Color.WHITE) # Example fallback
        ```

## 4. Mobile Support (Touch UI)

*   [ ] **Input Map:** Define touch actions (`touch_move`, `touch_look`, `touch_jump`, `touch_shoot`) in Project Settings.
*   [ ] Create `scenes/ui/MobileHUD.tscn`.
*   [ ] **`MobileHUD.tscn` Structure:**
    *   [ ] Add `CanvasLayer`.
    *   [ ] Add `TouchScreenButton` for Jump (assign `touch_jump` action).
    *   [ ] Add `TouchScreenButton` for Shoot (assign `touch_shoot` action).
    *   [ ] Add `TouchScreenButton` for movement (virtual joystick - requires custom logic or addon). Set its `visibility_mode` to `TOUCHSCREEN_ONLY`.
    *   [ ] Add a `Control` node or `TextureRect` as a drag area for looking (requires script). Set its `visibility_mode` to `TOUCHSCREEN_ONLY`.
*   [ ] Create `scripts/ui/MobileHUD.gd` (Optional, for joystick/look logic).
*   [ ] **`player3D.gd` Modifications:**
    *   [ ] In `_physics_process`, handle `touch_jump`, `touch_move` actions.
    *   [ ] In `_unhandled_input`, handle `touch_look` input (accumulate drag delta).
    *   [ ] In `_physics_process` or `_input`, handle `touch_shoot` action.
*   [ ] **Loading `MobileHUD`:** In the main game scene script (`SceneManager.gd` or the script attached to `testScene3D.tscn`/`ImprovedLevel.tscn`):
    ```gd
    @export var mobile_hud_scene: PackedScene

    func _ready():
        # ... existing ready code ...
        if OS.has_feature("mobile") and mobile_hud_scene:
            var mobile_hud = mobile_hud_scene.instantiate()
            add_child(mobile_hud) # Add to the game scene or a CanvasLayer
    ```
    *   [ ] Assign the created `MobileHUD.tscn` to the exported variable in the Inspector.

## 5. Map Improvement

*   [ ] Create a new scene `scenes/levels/ImprovedLevel.tscn` or significantly modify `scenes/levels/testScene3D.tscn`.
*   [ ] Add diverse geometry (ramps, platforms, walls, cover) using `MeshInstance3D` with `StaticBody3D` and `CollisionShape3D`.
*   [ ] Improve lighting: Add `WorldEnvironment` (with a background sky/environment), `DirectionalLight3D`. Bake lightmaps (`LightmapGI`) if needed for performance/visuals.
*   [ ] Create/update `Node3D` named `SpawnPoints` within the level scene. Add multiple `Marker3D` nodes as children for spawn locations.
*   [ ] Update `MultiplayerController.gd` (`StartGame` function) to load the new scene path: `load("res://scenes/levels/ImprovedLevel.tscn").instantiate()`.
*   [ ] Update `PauseMenu.gd`'s quit function to correctly reference the *currently* loaded game scene if the name changes.

## 6. Gameplay Feel (Health & Movement)

*   [ ] **`player3D.gd`:**
    *   [ ] Adjust `SPEED`, `JUMP_VELOCITY`, `gravity` values. Experiment.
    *   [ ] Consider adding acceleration:
        ```gd
        # Example acceleration logic (replace direct velocity set)
        var target_velocity = direction * SPEED
        velocity.x = lerp(velocity.x, target_velocity.x, ACCELERATION * delta)
        velocity.z = lerp(velocity.z, target_velocity.z, ACCELERATION * delta)
        # Define ACCELERATION constant, e.g., const ACCELERATION = 10.0
        ```
    *   [ ] Increase initial `health` (e.g., `var health = 200`). Update `respawn` accordingly.
*   [ ] **Bullet Scene/Script (e.g., `Bullet.gd`):**
    *   [ ] Adjust bullet speed and lifetime.
    *   [ ] Adjust damage value dealt in `_on_body_entered` or similar collision handler.
    *   [ ] Add `owner_id` variable to the bullet, set when shooting.
    *   [ ] Add visual effects (particles) and sound effects (`AudioStreamPlayer3D`) for shooting and impact.
*   [ ] **Health Bar (`Player3D.tscn` -> `HealthBar3D/SubViewport/ProgressBar`):**
    *   [ ] Update `max_value` to match the new max health.
    *   [ ] Ensure it's positioned correctly and visible in-game.

## 7. Leaderboard

*   [ ] **`GameManager.gd`:**
    *   [ ] Modify `Players` structure: `Players[id] = {"name": ..., "color": ..., "kills": 0, "deaths": 0}`. Update `SendPlayerInformation` to include these default values.
    *   [ ] Add RPC function `report_kill(killer_id, victim_id)`:
        ```gd
        signal score_updated # Signal to notify UI

        # Only callable by the server
        @rpc("authority", "call_local")
        func report_kill(killer_id, victim_id):
            if Players.has(killer_id):
                 Players[killer_id].kills += 1
            if Players.has(victim_id):
                 Players[victim_id].deaths += 1
            # Notify all clients about the score change
            update_scores_on_clients.rpc(Players)
            score_updated.emit() # Emit locally on server too

        # RPC to send the whole score dictionary to clients
        @rpc("any_peer")
        func update_scores_on_clients(latest_scores):
             if not multiplayer.is_server(): # Clients update their local copy
                  Players = latest_scores
                  score_updated.emit()
        ```
*   [ ] **Damage/Respawn Logic:**
    *   [ ] When damage is dealt (e.g., in bullet collision), get the `owner_id` from the bullet.
    *   [ ] In `player3D.gd`'s `take_damage(amount, attacker_id)`, if health <= 0, call `GameManager.report_kill.rpc_id(1, attacker_id, str(name).to_int())` before respawning. Pass the attacker's ID.
*   [ ] Create `scenes/ui/LeaderboardUI.tscn`.
*   [ ] **`LeaderboardUI.tscn` Structure:**
    *   [ ] `CanvasLayer` -> `PanelContainer` (semi-transparent background).
    *   [ ] `VBoxContainer` inside panel.
    *   [ ] Add header `Label` ("Name Kills Deaths").
*   [ ] Create `scripts/ui/LeaderboardUI.gd`.
*   [ ] **`LeaderboardUI.gd` Logic:**
    *   [ ] `@onready var score_container = $PanelContainer/VBoxContainer`.
    *   [ ] Function `update_display()`:
        *   Clear `score_container`.
        *   Get `GameManager.Players`.
        *   Sort players by kills (descending).
        *   For each player, create a `Label` (or custom scene) with "Name Kills Deaths" and add it to `score_container`.
    *   [ ] In `_ready()`, connect to `GameManager.score_updated`: `GameManager.score_updated.connect(update_display)`. Call `update_display()` initially.
    *   [ ] Implement show/hide logic based on `toggle_leaderboard` input action. Check input in `_process` or `_input`.
*   [ ] Add `LeaderboardUI.tscn` instance to the main game scene (`ImprovedLevel.tscn`).
*   [ ] Add `toggle_leaderboard` action to Input Map (e.g., Tab key). 