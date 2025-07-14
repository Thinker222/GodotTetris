extends Node2D

@export var mino_width = 48
@export var update_wait_time = 0.2 
@export var update_wait_time_speedup = 0.05

enum {START_GAME,
	WAIT_TO_DEPLOY, 
	DEPLOY, 
	WAIT_TO_UPDATE_TETRAMINO, 
	UPDATE_TETRAMINO, 
	WAIT_TO_CLEAR_ROW, 
	CLEAR_ROW,
	WAIT_TO_SHIFT_AFTER_CLEAR_ROW, 
	SHIFT_AFTER_CLEAR_ROW,
	WAIT_FOR_GAME_END,
	END_GAME}

# Globals
var columns = 10 
var rows = 20
var score = 0
var rng = RandomNumberGenerator.new()
var tetramino 
var tetramino_root
var tetramino_on_deck
var grid = []
var mutex = Mutex.new()
var row_to_clear
var state = START_GAME
var can_rotate = true
var down_pressed = false

# Callbacks
func _ready(): 
	for i in range(columns):
		var row = []	   
		for j in range(rows):
			row.append(null)
		grid.append(row)
	if tetramino != null: 
		for mino in tetramino: 
			mino[0].queue_free()
	tetramino = null 
	tetramino_on_deck = null
	score = 0 
	$Hud/ScoreLabel.text = "Score: " + str(score)
	state = START_GAME

func _process(delta):
	if state == START_GAME:
		pass 
	elif state == WAIT_TO_DEPLOY:
		if $DeployTimer.is_stopped():
			$DeployTimer.start() 
	elif state == DEPLOY:
		state = create_and_verify_tetramino()
	elif state == WAIT_TO_UPDATE_TETRAMINO:
		if down_pressed:
			$UpdateTimer.wait_time = update_wait_time_speedup
		else:
			$UpdateTimer.wait_time = update_wait_time
		if $UpdateTimer.is_stopped():
			$UpdateTimer.start() 
	elif state == UPDATE_TETRAMINO: 
		state = update_tetramino()
	elif state == WAIT_TO_CLEAR_ROW: 
		if $ClearRowTimer.is_stopped():
			$ClearRowTimer.start()
	elif state == CLEAR_ROW:
		clear_row()
		score += 10
		$Hud/ScoreLabel.text = "Score: " + str(score)
		state = WAIT_TO_SHIFT_AFTER_CLEAR_ROW
	elif state == WAIT_TO_SHIFT_AFTER_CLEAR_ROW: 
		if $ShiftAfterClearTimer.is_stopped():
			$ShiftAfterClearTimer.start()
	elif state == SHIFT_AFTER_CLEAR_ROW: 
		shift_rows()
		if check_can_clear_any_row():
			state = WAIT_TO_CLEAR_ROW
		else: 
			state = WAIT_TO_DEPLOY
	elif state == WAIT_FOR_GAME_END:
		if $GameEndTimer.is_stopped():
			$GameEndTimer.start()
	elif state == END_GAME: 
		cleanup()
		state = START_GAME
		
	if Input.is_action_just_pressed("Right"):
		if !check_tetramino_collision(0, 1, false):
			tetramino_root[0] += 1
	if Input.is_action_just_pressed("Left"):
		if !check_tetramino_collision(0, -1, false): 
			tetramino_root[0] -= 1
	if Input.is_action_pressed("Down"):
		if !check_tetramino_collision(1, 0, false):  
			tetramino_root[1] +=1
		down_pressed = true
	else:
		down_pressed = false 
	if Input.is_action_just_pressed("Up"): 
		if !check_tetramino_collision(0, 0, true): 
			rotate_tetramino()
	update_tetramino_position_transforms()

func _on_deploy_timer_timeout() -> void:
	state = DEPLOY

func _on_update_timer_timeout() -> void:
	state = UPDATE_TETRAMINO

func _on_game_end_timer_timeout() -> void:
	state = END_GAME

func _on_clear_row_timer_timeout() -> void:
	state = CLEAR_ROW

func _on_shift_after_clear_timer_timeout() -> void:
	state = SHIFT_AFTER_CLEAR_ROW

# Functions used by _process
func create_and_verify_tetramino():
	# Generate a random number between 0 and 4 inclusive 
	var tetramino_idx = rng.randi_range(0,4) 
	# Set root position of tetramino 
	tetramino_root = Vector2(5,0)
	# Create list of lists where the members are a ColorRect and relative coordinates
	tetramino = create_tetramino(tetramino_idx)
	# Check for collision and bail if there is
	if check_tetramino_collision():
		# End game 
		cleanup()
		return END_GAME
	else:
		# Add all children
		for mino in tetramino: 
			add_child(mino[0])
		update_tetramino_position_transforms()
		$UpdateTimer.start()
	return WAIT_TO_UPDATE_TETRAMINO

func update_tetramino():
	if tetramino != null: 
		update_tetramino_position_transforms()
		if check_tetramino_collision(1):
			for mino in tetramino: 
				var translate = tetramino_root + mino[1]
				if translate[0] < 0 or translate[1] < 0:
					return WAIT_FOR_GAME_END
					
				else:
					grid[translate[0]][translate[1]] = mino 
			# Check if can clear row 
			tetramino = null
			if check_can_clear_any_row():
				return WAIT_TO_CLEAR_ROW 
			else:
				return WAIT_TO_DEPLOY
		else:
			tetramino_root[1] += 1
			update_tetramino_position_transforms()
			return WAIT_TO_UPDATE_TETRAMINO

func clear_row():
	for column in range(columns):
		grid[column][row_to_clear][0].queue_free()
		grid[column][row_to_clear] = null

func shift_rows():
	var row = row_to_clear - 1
	while row != 0: 
		for column in range(columns):
			if grid[column][row] != null and grid[column][row+1] == null: 
				grid[column][row+1] = grid[column][row]
				grid[column][row] = null 
		row -= 1
	update_grid_position_transforms()

func cleanup():	
	for column in range(columns):
		for row in range(rows):
			if grid[column][row] != null: 
				grid[column][row][0].queue_free()
				grid[column][row] = null 
	if tetramino != null:
		for mino in tetramino: 
			mino[0].queue_free()
		tetramino = null
	$Hud/ScoreLabel.text = "Score: 0000"
	$Hud/StartButton.show()

func _on_hud_start_game() -> void:
	$Hud/StartButton.hide()
	state = WAIT_TO_DEPLOY
	
func check_can_clear_any_row():
	var row = rows - 1
	while row != 0: 
		var row_is_full = true 
		for column in range(columns): 
			if grid[column][row] == null: 
				row_is_full = false 
		if row_is_full: 
			row_to_clear = row 
			return true
		row -= 1;
	return false

func convert_root_and_rel_to_transform(root, rel):
	var x = (root[0] + rel[0]) * mino_width
	var y = (root[1] + rel[1]) * mino_width 
	return Vector2(x,y)

func create_mino(color):
	var rect = ColorRect.new()
	rect.color = color 
	rect.size.x = mino_width 
	rect.size.y = mino_width
	return rect

func create_tetramino(tetramino_idx):
	can_rotate = true
	if tetramino_idx == 0:
		var c = Color.RED
		return [[create_mino(c), Vector2(-2, 0)],
				[create_mino(c), Vector2(-1, 0)],
				[create_mino(c), Vector2(0, 0)],
				[create_mino(c), Vector2(1, 0)]]
	elif tetramino_idx == 1:
		var c = Color.YELLOW
		can_rotate = false
		return [[create_mino(c), Vector2(-1, 0)],
				[create_mino(c), Vector2(0, 0)],
				[create_mino(c), Vector2(-1, 1)],
				[create_mino(c), Vector2(0, 1)]]
	elif tetramino_idx == 2: 
		var c = Color.ORANGE 
		return [[create_mino(c), Vector2(0, -2)],
				[create_mino(c), Vector2(0, -1)],
				[create_mino(c), Vector2(0, 0)],
				[create_mino(c), Vector2(1, 0)]]
	elif tetramino_idx == 3: 
		var c = Color.GREEN 
		return [[create_mino(c), Vector2(0, -1)],
				[create_mino(c), Vector2(0, 0)],
				[create_mino(c), Vector2(1, 0)],
				[create_mino(c), Vector2(1, 1)]]
	elif tetramino_idx == 4: 
		var c = Color.PURPLE 
		return [[create_mino(c), Vector2(-1, 0)],
				[create_mino(c), Vector2(0, 0)],
				[create_mino(c), Vector2(1, 0)],
				[create_mino(c), Vector2(0, 1)]]

func check_tetramino_collision(plus_y = 0, plus_x = 0, rotate=false):
	if tetramino == null:
		return true 
	for mino in tetramino: 
		var pos = mino[1]
		var x = 0 
		var y = 0
		if rotate:
			var tmpx = x
			x = tetramino_root[0] + pos[1] + plus_x   
			y = tetramino_root[1] - pos[0] + plus_y
		else:
			x = tetramino_root[0] + pos[0] + plus_x
			y = tetramino_root[1] + pos[1] + plus_y
		
		# If y is negative then there can be no collision on the grid 
		# NOTE If x is ever negative, that is a bug in the game logic
		if y < 0: 
			continue
		# The tetramino cannot go past the bottom
		if y >= rows:
			return true
		
		if x >= columns: 
			return true 
		if x < 0:
			return true  
		# If the grid is populated at that point, the tetramino cannot go there 
		if grid[x][y] != null: 
			return true
	return false 
	
func rotate_tetramino():
	if tetramino != null and can_rotate: 
		for mino in tetramino:
			var pos = mino[1] 
			var x = pos[0]
			var y = pos[1]
			var newPos = Vector2(-y, x)
			mino[1] = newPos
		update_tetramino_position_transforms()
		
func update_tetramino_position_transforms():
	if tetramino != null:
		for mino in tetramino: 
			var obj = mino[0]
			var rel = mino[1]
			var actual_pos = convert_root_and_rel_to_transform(tetramino_root, rel)
			obj.position = actual_pos

func update_grid_position_transforms():
	for row in range(rows):
		for column in range(columns):
			if grid[column][row] != null: 
				grid[column][row][0].position = convert_root_and_rel_to_transform(Vector2(column, row), Vector2(0,0))
		
