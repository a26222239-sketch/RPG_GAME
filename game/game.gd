extends Node
## 全域單例（自動載入，名稱為 Game）。
## 負責載入資料、提供文字，以及讀取開發用的啟動參數。
##
## 開發用參數寫在 `--` 之後，例如：
##   godot --path . -- --autoplay --shots=/tmp/shots
##   --autoplay        自動按下所有該按的東西，用來快速跑完整段流程
##   --input=方式      自動播放時怎麼按：direct（直接呼叫，預設）、clicks（模擬滑鼠點擊）、keys（模擬 Enter 鍵）
##   --shots=資料夾    搭配 --autoplay，在每個等待點存一張截圖
##   --speed=倍數      加快時間
##   --read=倍數       自動播放時留給人閱讀的時間；0 是立刻按（預設），1 是正常閱讀速度。錄影時使用
##   --skip-at=拍數    播到第幾拍時按下「跳過」
##   --replay          播完後按一次「重看」，第二次播完才結束（戰鬥試煉是「再戰一次」）
##   --encounter=識別碼  搭配 --autoplay：從標題畫面點進「戰鬥試煉」，打這一場（例如 test_d）
##   --seed=數字       戰鬥試煉的亂數種子（不給的話每場隨機）
##   --auto-party      戰鬥試煉一開始就讓四個人全部自動

const GameData := preload("res://core/data/game_data.gd")

var data: GameData = GameData.new()
var data_ok: bool = false

var autoplay: bool = false
var input_mode: String = "direct"
var read_scale: float = 0.0
var shots_dir: String = ""
var skip_at: int = -1
var replays_left: int = 0
var dev_encounter: String = ""
var dev_seed: int = -1
var auto_party: bool = false
## 標題畫面選好的戰鬥試煉，換到戰鬥畫面後由它讀取。
var pending_encounter: String = ""
## 從戰鬥試煉按「回到選單」時，標題畫面直接打開試煉清單。
var open_trials: bool = false
var _shot_count: int = 0
var _injecting: bool = false


func _ready() -> void:
	data_ok = data.load_all()
	if not data_ok:
		for message in data.errors:
			push_error(message)
	_install_translation()
	_read_args()


## 取得文字。找不到鍵時回傳鍵本身。
func t(key: String) -> String:
	return data.text(key)


## 開發用：存一張目前畫面的截圖。沒有指定 --shots 時什麼都不做。
func take_shot(label: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_shot_count += 1
	var path := "%s/%03d_%s.png" % [shots_dir, _shot_count, label]
	image.save_png(path)


func _install_translation() -> void:
	var translation := Translation.new()
	translation.locale = "zh_TW"
	for key: String in data.texts:
		translation.add_message(key, str(data.texts[key]))
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale("zh_TW")


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
		elif arg.begins_with("--speed="):
			Engine.time_scale = maxf(0.1, arg.trim_prefix("--speed=").to_float())
		elif arg.begins_with("--read="):
			read_scale = maxf(0.0, arg.trim_prefix("--read=").to_float())
		elif arg.begins_with("--input="):
			input_mode = arg.trim_prefix("--input=")
		elif arg.begins_with("--skip-at="):
			skip_at = arg.trim_prefix("--skip-at=").to_int()
		elif arg == "--replay":
			replays_left = 1
		elif arg.begins_with("--encounter="):
			dev_encounter = arg.trim_prefix("--encounter=")
		elif arg.begins_with("--seed="):
			dev_seed = arg.trim_prefix("--seed=").to_int()
		elif arg == "--auto-party":
			auto_party = true


## 開發用：在畫面上的某一點模擬一次滑鼠左鍵點擊。
## 注意：引擎會在下一個畫格才處理送進去的事件，不是立刻。
## 一次只送一組按下與放開；兩組交錯的話，按鈕會把它當成滑出去放開而不觸發。
## still_wanted 會在真正送出之前再問一次：等待期間畫面已經往下走的話，就不要按了。
func click_at(pos: Vector2, still_wanted: Callable = Callable()) -> void:
	while _injecting:
		await get_tree().process_frame
	if still_wanted.is_valid() and not still_wanted.call():
		return
	_injecting = true
	# pos 是畫面設計座標（1920×1080 那一套）；視窗被縮放時，要先換算成視窗上的實際位置。
	var window_pos: Vector2 = get_viewport().get_final_transform() * pos
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = window_pos
		event.global_position = window_pos
		Input.parse_input_event(event)
		await get_tree().process_frame
		await get_tree().process_frame
	_injecting = false


## 開發用：模擬按一下 Enter。
func press_accept(still_wanted: Callable = Callable()) -> void:
	await press_key(KEY_ENTER, still_wanted)


## 開發用：模擬按一下鍵盤上的某個鍵。
func press_key(keycode: Key, still_wanted: Callable = Callable()) -> void:
	while _injecting:
		await get_tree().process_frame
	if still_wanted.is_valid() and not still_wanted.call():
		return
	_injecting = true
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
		await get_tree().process_frame
	_injecting = false
