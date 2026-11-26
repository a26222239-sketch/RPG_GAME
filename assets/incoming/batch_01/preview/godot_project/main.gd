extends Node2D

var players: Array[AnimationPlayer] = []
var sprites: Array[Sprite2D] = []
var actions := ["idle","attack_light","hit"]
var labels := ["待機循環","出劍與收招","受擊反應"]
var batch := ""
var font := SystemFont.new()
var captured := false

func require_ok(value: bool,message: String) -> bool:
	if not value:
		push_error(message)
		get_tree().quit(1)
	return value

func _ready() -> void:
	batch = ProjectSettings.globalize_path("res://../..").simplify_path()
	font.font_names = PackedStringArray(["Microsoft JhengHei","PMingLiU"])
	var image := Image.load_from_file(batch+"/characters/shen_peak/frames/preview_atlas.png")
	if not require_ok(image != null and image.get_size() == Vector2i(7680,512),"Atlas dimensions"):
		return
	var actor_scene := load("res://shen_actor.tscn") as PackedScene
	for i in range(3):
		var actor := actor_scene.instantiate() as Node2D
		actor.name = "Actor"+str(i)
		actor.position = Vector2(256+i*512,600)
		add_child(actor)
		var sprite := actor.get_node("Visual/Sprite") as Sprite2D
		sprites.append(sprite)
		var player := actor.get_node("AnimationPlayer") as AnimationPlayer
		player.play(actions[i])
		player.advance(0)
		players.append(player)
	var controls := HBoxContainer.new()
	controls.position = Vector2(460,665)
	controls.add_theme_constant_override("separation",24)
	add_child(controls)
	for entry in [["重新播放",1.0],["慢速 0.5×",0.5],["正常速度",1.0]]:
		var button := Button.new()
		button.text = entry[0]
		button.add_theme_font_override("font",font)
		button.add_theme_font_size_override("font_size",22)
		button.custom_minimum_size = Vector2(185,44)
		var speed: float = entry[1]
		button.pressed.connect(func() -> void:
			for j in range(3):
				players[j].speed_scale = speed
				players[j].stop()
				players[j].play(actions[j]))
		controls.add_child(button)
	if OS.get_cmdline_user_args().has("--test"):
		run_checks()
		get_tree().quit()
		return
	var timer := Timer.new()
	timer.wait_time = 1.8
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		for i in range(1,3):
			players[i].stop()
			players[i].play(actions[i]))
	add_child(timer)
	if OS.get_cmdline_user_args().has("--capture"):
		for p in players:
			p.pause()
		players[0].seek(0.6,true)
		players[1].seek(0.20,true)
		players[2].seek(0.10,true)
		capture.call_deferred()
	queue_redraw()

func run_checks() -> void:
	var checks := 0
	var cases := [
		["idle",0.0,0],["idle",0.6,3],["idle",1.05,5],
		["attack_light",0.0,6],["attack_light",0.08,7],
		["attack_light",0.15,8],["attack_light",0.20,9],
		["attack_light",0.32,10],["attack_light",0.50,11],
		["hit",0.0,12],["hit",0.10,13],["hit",0.25,14]]
	for c in cases:
		players[0].play(c[0])
		players[0].advance(0)
		players[0].seek(c[1],true)
		if not require_ok(sprites[0].frame == c[2],str(c)):
			return
		checks += 1
	for action in ["idle","attack_light","hit"]:
		var img := Image.load_from_file(batch+"/characters/shen_peak/frames/"+action+".png")
		var frames := 3 if action == "hit" else 6
		if not require_ok(img.get_size() == Vector2i(frames*512,512),"Strip "+action):
			return
		checks += 1
		for f in range(frames):
			var transparent := 0
			var floor := -1
			for y in range(512):
				for x in range(f*512,(f+1)*512):
					var alpha := img.get_pixel(x,y).a
					if alpha == 0.0:
						transparent += 1
					if alpha >= 0.5:
						floor = maxi(floor,y)
			if not require_ok(transparent > 60000 and floor == 479,"Alpha/floor "+action+" "+str(f)):
				return
			checks += 1
	if not require_ok(players[0].get_animation("idle").loop_mode == Animation.LOOP_LINEAR,"Idle loop"):
		return
	checks += 1
	var result := {"engine":Engine.get_version_info().string,"checks_passed":checks,"result":"pass","animations":["idle","attack_light","hit"],"frames":15}
	var out := FileAccess.open(batch+"/characters/shen_peak/frames/godot_test_results.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(result,"\t"))
	out.close()
	print("GODOT_ANIMATION_PASS "+JSON.stringify(result))

func capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := batch+"/preview/shen_godot.png"
	if img.save_png(path) != OK:
		get_tree().quit(1)
		return
	print("GODOT_GPU_CAPTURE "+path)
	get_tree().quit()

func _draw() -> void:
	draw_rect(Rect2(0,0,1536,720),Color("#172C34"))
	draw_string(font,Vector2(54,55),"沈清禾｜Godot AnimationPlayer 動畫試做",HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color("#EAE3CF"))
	draw_string(font,Vector2(54,91),"同一套造型 · 512×512 每格 · 腳底固定 · 0.20 秒出劍命中",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("#AAD0C3"))
	for i in range(3):
		draw_rect(Rect2(i*512+16,120,480,518),Color("#20383D"))
		draw_line(Vector2(i*512+48,600),Vector2(i*512+464,600),Color("#B89A66"),1.0)
		draw_string(font,Vector2(i*512+180,150),labels[i],HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("#EAE3CF"))

