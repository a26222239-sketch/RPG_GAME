"""Prepare animation output for Godot maximum texture dimensions and compact PNG storage."""
from PIL import Image
from pathlib import Path
B=Path(__file__).resolve().parent.parent
f=B/'characters/shen_peak/frames'; c=B/'characters/shen_peak/cutin'; v=B/'vfx'
# Run after build_animation.py and build_fx.py. Re-run on an un-packed copy.
for p in sorted(f.glob('*.png')):
 if p.stem[-3:-2]=='_' and p.stem[-2:].isdigit():continue
 im=Image.open(p).convert('RGBA').quantize(256,method=Image.Quantize.FASTOCTREE,dither=Image.Dither.NONE)
 if im.width>16384:
  for i in range(im.width//im.height):
   im.crop((i*im.height,0,(i+1)*im.height,im.height)).save(p.with_name(f'{p.stem}_{i+1:02d}.png'),optimize=True)
  p.unlink()
 else:im.save(p,optimize=True)
paths=sorted(c.glob('*.png'))
if paths:
 pal=Image.open(paths[0]).convert('RGB').quantize(256,method=Image.Quantize.MEDIANCUT)
 for p in paths:Image.open(p).convert('RGB').quantize(palette=pal,dither=Image.Dither.FLOYDSTEINBERG).save(p,optimize=True)
for p in sorted(v.glob('*.png')):
 im=Image.open(p)
 if im.width>16384:
  for i in range(im.width//im.height):
   im.crop((i*im.height,0,(i+1)*im.height,im.height)).save(p.with_name(f'{p.stem}_{i+1:02d}.png'),optimize=True)
  p.unlink()
