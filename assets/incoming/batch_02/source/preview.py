"""Render an illustrative normal/quarter speed playback of the delivered frames.
Uses the game's existing battle background; not a captured Godot build."""
from PIL import Image,ImageDraw,ImageFont,ImageFilter,ImageOps
from pathlib import Path
import json, numpy as np, subprocess, math, sys
B=Path(__file__).resolve().parent.parent
GAME=Path(sys.argv[1]) if len(sys.argv)>1 else Path('game-render')
F=B/'characters/shen_peak/frames'; V=B/'vfx'; P=B/'preview'
W,H=960,540;RATE=24
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font=ImageFont.truetype(FONT,17);bold=ImageFont.truetype(FONT,27);small=ImageFont.truetype(FONT,13)
def load(folder,name,side=None):
 p=folder/(name+'.png')
 if p.exists():
  im=Image.open(p).convert('RGBA');s=im.height if side is None else side
  return [im.crop((i*s,0,(i+1)*s,s)) for i in range(im.width//s)]
 return [Image.open(p).convert('RGBA') for p in sorted(folder.glob(name+'_[0-9][0-9].png'))]
meta=json.loads((F/'meta.json').read_text());fxmeta=json.loads((V/'meta.json').read_text())
names=['idle','attack_light','hit','hit_heavy','shen_qianren']
art={name:load(F,name) for name in names};fx={k:load(V,k) for k in ('slash_sword','hit_spark','shen_qianren')}
cutin=load(B/'characters/shen_peak/cutin','shen_qianren')
background=ImageOps.fit(Image.open(GAME/'assets/backgrounds/battle/tianmo_hall.jpg').convert('RGB'),(W,H))
background=Image.blend(background,Image.new('RGB',(W,H),(13,11,22)),.17)
enemy_path=GAME/'assets/characters/tianmo/frames/stand.png'
enemy=Image.open(enemy_path).convert('RGBA').resize((430,430),Image.Resampling.LANCZOS)
# Existing stand images face either direction by art conventions. Mirror test enemy for facing player.
enemy=ImageOps.mirror(enemy)
enemy_xy=(500,60); hero_xy=(15,60); hero_size=430
def index_at(name,t,met):
 times=np.cumsum(met[name]['timings_ms'])/1000
 return min(len(times)-1,int(np.searchsorted(times,t,side='right')))
def effect(canvas,name,t,x,y,sz):
 if t<0 or t>=sum(fxmeta[name]['timings_ms'])/1000:return canvas
 im=fx[name][index_at(name,t,fxmeta)].resize((sz,sz),Image.Resampling.BILINEAR)
 im=im.convert('RGB')
 a=np.asarray(canvas.convert('RGB'),dtype=np.int16).copy()
 l=max(0,x);u=max(0,y);r=min(W,x+sz);b=min(H,y+sz)
 if l<r and u<b:a[u:b,l:r]=np.clip(a[u:b,l:r]+np.asarray(im,dtype=np.int16)[u-y:b-y,l-x:r-x],0,255)
 return Image.fromarray(a.astype('uint8')).convert('RGBA')
def draw_frame(name,t,speed):
 if name=='shen_qianren' and t<.667:
  im=cutin[min(7,int(t*12))].convert('RGB')
  c=Image.new('RGBA',(W,H),(16,11,26,255))
  c.alpha_composite(im.resize((W,270),Image.Resampling.LANCZOS).convert('RGBA'),(0,135))
  d=ImageDraw.Draw(c);d.text((40,420),'SHEN QINGHE / THOUSAND RIDGES',font=bold,fill='#e9d2ff')
 else:
  if name=='shen_qianren':t-=.667
  c=background.convert('RGBA');d=ImageDraw.Draw(c)
  for x in (hero_xy[0]+215,enemy_xy[0]+215):
   d.ellipse((x-52,456,x+52,474),fill=(20,13,26,100))
  c.alpha_composite(enemy,enemy_xy)
  frame=art[name][index_at(name,t,meta)].resize((hero_size,hero_size),Image.Resampling.LANCZOS)
  c.alpha_composite(frame,hero_xy)
  if name=='attack_light':
   impact=sum(meta[name]['timings_ms'][:meta[name]['impact_frame']-1])/1000
   c=effect(c,'slash_sword',t-impact+.084,545,170,330)
  if name in ('hit','hit_heavy'):c=effect(c,'hit_spark',t+.04,96,182,260)
  if name=='shen_qianren':
   impact=sum(meta[name]['timings_ms'][:meta[name]['impact_frame']-1])/1000
   c=effect(c,'shen_qianren',t-impact+.504,410,40,485)
 d=ImageDraw.Draw(c)
 d.rectangle((0,0,W,54),fill=(14,12,21,255));d.text((23,11),'SHEN QINGHE  /  ANIMATION PILOT',font=bold,fill='#e4d8c6')
 d.rectangle((0,H-50,W,H),fill=(14,12,21,255));d.text((23,H-39),name.replace('_',' ').upper(),font=font,fill='#e4d8c6')
 d.text((W-280,H-35),f'{speed:g}x  |  ART COMPOSITE PREVIEW',font=small,fill='#b7a9c7')
 return c.convert('RGB')
for speed,tag in [(1,'normal'),(.25,'quarter')]:
 outfile=P/f'shen_preview_{tag}.mp4'
 proc=subprocess.Popen(['ffmpeg','-y','-loglevel','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(RATE),'-i','-','-c:v','libx264','-threads','2','-preset','fast','-crf','25','-pix_fmt','yuv420p','-movflags','+faststart',str(outfile)],stdin=subprocess.PIPE)
 for name in names:
  duration=sum(meta[name]['timings_ms'])/1000+(.667 if name=='shen_qianren' else 0)
  count=math.ceil(duration*RATE/speed)
  for j in range(count):
   im=draw_frame(name,j/RATE*speed,speed)
   if speed==1 and name=='shen_qianren' and j==int(0.9*RATE):im.save(P/'battle_preview.jpg',quality=92)
   proc.stdin.write(im.tobytes())
 proc.stdin.close()
 if proc.wait():raise RuntimeError('ffmpeg failed')
