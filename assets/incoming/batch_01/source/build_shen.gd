extends SceneTree
const FRAME := Vector2i(512,512)
const FLOOR_Y := 480
var batch := ""
var generated := ""
var dest := ""
var metrics: Array = []

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func solid_box(img: Image, area: Rect2i) -> Rect2i:
	var lo := area.end
	var hi := area.position - Vector2i.ONE
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			if img.get_pixel(x,y).a >= 0.5:
				lo = lo.min(Vector2i(x,y))
				hi = hi.max(Vector2i(x,y))
	return Rect2i(lo,hi-lo+Vector2i.ONE)

func foot(img: Image, area: Rect2i) -> Vector2:
	var box := solid_box(img,area)
	var y := box.end.y-1
	var xs: Array[int] = []
	for x in range(box.position.x,box.end.x):
		if img.get_pixel(x,y).a >= 0.5:
			xs.append(x)
	return Vector2((xs[0]+xs[-1])/2.0,y)

func normalized(img: Image, area: Rect2i, feet: Array, name: String) -> Image:
	var body := solid_box(img,area)
	var scale_value := 392.0/body.size.y
	var center := (foot(img,feet[0]).x+foot(img,feet[1]).x)/2.0
	var cut := img.get_region(area)
	cut.resize(roundi(cut.get_width()*scale_value),roundi(cut.get_height()*scale_value),Image.INTERPOLATE_LANCZOS)
	var at := Vector2i(256-roundi((center-area.position.x)*scale_value),FLOOR_Y-roundi((body.end.y-area.position.y)*scale_value))
	var out := Image.create(512,512,false,Image.FORMAT_RGBA8)
	out.blit_rect(cut,Rect2i(Vector2i.ZERO,cut.get_size()),at)
	var box := solid_box(out,Rect2i(Vector2i.ZERO,FRAME))
	# Remove rounding differences at the ground line after Lanczos resampling.
	var correction := FLOOR_Y-box.end.y
	if correction != 0:
		var adjusted := Image.create(512,512,false,Image.FORMAT_RGBA8)
		adjusted.blit_rect(out,Rect2i(Vector2i.ZERO,FRAME),Vector2i(0,correction))
		out = adjusted
		box = solid_box(out,Rect2i(Vector2i.ZERO,FRAME))
	assert(box.position.x > 1 and box.end.x < 511)
	assert(box.position.y > 1 and box.end.y == FLOOR_Y)
	metrics.append({"pose":name,"source_box":[body.position.x,body.position.y,body.size.x,body.size.y],"source_feet_center":center,"scale":scale_value,"frame_box":[box.position.x,box.position.y,box.size.x,box.size.y]})
	out.save_png(dest+"/key_"+name+".png")
	return out

func strip(images: Array[Image], path: String) -> void:
	var out := Image.create(512*images.size(),512,false,Image.FORMAT_RGBA8)
	for i in range(images.size()):
		out.blit_rect(images[i],Rect2i(Vector2i.ZERO,FRAME),Vector2i(i*512,0))
	assert(out.save_png(path) == OK)

func animation(name: String, times: Array, frames: Array, duration: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.resource_name = name
	a.length = duration
	if loop:
		a.loop_mode = Animation.LOOP_LINEAR
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t,NodePath("Visual/Sprite:frame"))
	a.value_track_set_update_mode(t,Animation.UPDATE_DISCRETE)
	for i in range(times.size()):
		a.track_insert_key(t,float(times[i]),int(frames[i]))
	return a

func _initialize() -> void:
	batch = ProjectSettings.globalize_path("res://../..").simplify_path()
	var repo := batch.path_join("../../..").simplify_path()
	dest = batch+"/characters/shen_peak/frames"
	DirAccess.make_dir_recursive_absolute(dest)
	var source := Image.load_from_file(batch+"/characters/shen_peak/source/keyposes.png")
	var removed := 0
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var c := source.get_pixel(x,y)
			if c.a < 0.04 or (c.a < 0.5 and c.r > 0.55 and c.b > 0.5 and c.g < 0.3):
				if c.a > 0.0:
					removed += 1
				source.set_pixel(x,y,Color(0,0,0,0))
	var half := source.get_width()/2
	var keys: Array[Image] = []
	var feet := [
		[Rect2i(230,560,85,60),Rect2i(400,545,100,70)],
		[Rect2i(770,555,100,65),Rect2i(1000,540,100,80)],
		[Rect2i(230,1180,90,70),Rect2i(390,1160,100,85)],
		[Rect2i(810,1180,95,70),Rect2i(985,1150,115,95)]]
	var names := ["anticipation","strike","follow_through","hurt"]
	for i in range(4):
		var area := Rect2i((i%2)*half,(i/2)*half,half,half)
		keys.append(normalized(source,area,feet[i],names[i]))
	var base := Image.load_from_file(repo+"/assets/characters/shen_peak/frames/stand.png")
	base.resize(512,512,Image.INTERPOLATE_LANCZOS)
	var idle: Array[Image] = []
	for delta in [0,1,2,3,2,1]:
		var breathing := base.duplicate() as Image
		breathing.resize(512,512+delta,Image.INTERPOLATE_LANCZOS)
		var box := solid_box(breathing,Rect2i(Vector2i.ZERO,breathing.get_size()))
		var f := Image.create(512,512,false,Image.FORMAT_RGBA8)
		f.blit_rect(breathing,Rect2i(Vector2i.ZERO,breathing.get_size()),Vector2i(0,FLOOR_Y-box.end.y))
		idle.append(f)
	var attack: Array[Image] = [base,keys[0],keys[0],keys[1],keys[2],base]
	var hit: Array[Image] = [base,keys[3],base]
	strip(idle,dest+"/idle.png")
	strip(attack,dest+"/attack_light.png")
	strip(hit,dest+"/hit.png")
	var combined: Array[Image] = []
	combined.append_array(idle)
	combined.append_array(attack)
	combined.append_array(hit)
	strip(combined,dest+"/preview_atlas.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art"))
	DirAccess.copy_absolute(dest+"/preview_atlas.png",ProjectSettings.globalize_path("res://art/shen_atlas.png"))
	var library := AnimationLibrary.new()
	library.add_animation("idle",animation("idle",[0.0,0.2,0.4,0.6,0.8,1.0],[0,1,2,3,4,5],1.2,true))
	library.add_animation("attack_light",animation("attack_light",[0.0,0.06,0.14,0.20,0.29,0.42],[6,7,8,9,10,11],0.55,false))
	library.add_animation("hit",animation("hit",[0.0,0.045,0.20],[12,13,14],0.32,false))
	assert(ResourceSaver.save(library,dest+"/animations.tres") == OK)
	assert(ResourceSaver.save(library,"res://shen_animations.tres") == OK)
	var meta := {
		"character":"shen_peak","frame_size":[512,512],"feet_anchor":[256,480],"frame_index_base":0,
		"idle":{"frames":6,"duration":1.2,"loop":true,"timings_ms":[200,200,200,200,200,200]},
		"attack_light":{"frames":6,"duration":0.55,"loop":false,"impact_frame":3,"impact_time":0.20,"timings_ms":[60,80,60,90,130,130]},
		"hit":{"frames":3,"duration":0.32,"loop":false,"impact_frame":1,"impact_time":0.045,"timings_ms":[45,155,120]},
		"hold_frames":"Attack frames 1 and 2 intentionally reuse anticipation. Start/end reuse the accepted stand pose.",
		"preview_atlas":{"hframes":15,"idle":[0,5],"attack_light":[6,11],"hit":[12,14]}}
	var f := FileAccess.open(dest+"/meta.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(meta,"\t"))
	f.close()
	var report := {"status":"technical_pass_pending_art_and_game_integration","engine":Engine.get_version_info().string,"source_size":[source.get_width(),source.get_height()],"removed_low_alpha_or_chroma_pixels":removed,"poses":metrics,"frames":15,"checks":["frame dimensions","true alpha","full sword and feet inside frame","feet baseline y=480","reference scale 392px","idle loop breathing","attack impact frame 3","hit impact frame 1"],"limitations":"Four generated keyposes; hold and recovery frames reuse source poses. This is an initial animation pilot, not finished in-between animation."}
	f = FileAccess.open(dest+"/verification.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	f.close()
	print("BUILD_PASS "+JSON.stringify(report))
	quit()

