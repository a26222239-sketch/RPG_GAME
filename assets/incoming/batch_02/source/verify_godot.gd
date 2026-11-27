extends SceneTree
func _initialize():
    var root = "res://assets/incoming/batch_02"
    var categories = [{"dir":root+"/characters/shen_peak/frames", "sets":{"idle":16,"attack_light":22,"hit":12,"hit_heavy":22,"shen_qianren":50}, "side":512},{"dir":root+"/vfx","sets":{"slash_sword":12,"hit_spark":8,"shen_qianren":30},"side":0},{"dir":root+"/characters/shen_peak/cutin","sets":{"shen_qianren":8},"side":-1}]
    var count = 0
    for cat in categories:
        for name in cat.sets:
            var n = cat.sets[name]
            var path = cat.dir+"/"+name+".png"
            var side = cat.side
            if side == 0:
                side = 1024 if name=="shen_qianren" else 512
            if FileAccess.file_exists(path):
                var im = Image.load_from_file(path)
                if im == null or im.get_height()!=side or im.get_width()!=side*n or im.get_width()>16384:
                    printerr("invalid strip: ",path);quit(1);return
                count += n
            else:
                for i in range(1,n+1):
                    var f = cat.dir+"/"+name+"_%02d.png"%i
                    var im = Image.load_from_file(f)
                    var w = 2560 if side==-1 else side
                    var h = 720 if side==-1 else side
                    if im == null or im.get_width()!=w or im.get_height()!=h:
                        printerr("invalid frame: ",f);quit(1);return
                    count += 1
    print("Godot Image.load_from_file: ",count," frames across 9 groups; all dimensions valid, strip width <= 16384.")
    quit()
