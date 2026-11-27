"""Additive, frame-by-frame sword energy, impact and mountain-ridge VFX; animated cinematic cut-in."""
from pathlib import Path
import numpy as np, math, random, json
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import map_coordinates
B=Path(__file__).resolve().parent.parent
V=B/'vfx'; V.mkdir(exist_ok=True)
C=B/'characters/shen_peak/cutin'; C.mkdir(exist_ok=True)
S=B/'characters/shen_peak/source'
P=B/'preview'
R=math.pi
def path_arc(cx,cy,rx,ry,theta0,theta1,rot=0,n=110):
    ts=np.linspace(theta0,theta1,n)
    x=rx*np.cos(ts);y=ry*np.sin(ts)
    return [(float(cx+u*math.cos(rot)-v*math.sin(rot)),float(cy+u*math.sin(rot)+v*math.cos(rot))) for u,v in zip(x,y)]
def layer(n):
    return Image.new('RGB',(n,n))
def glowy(n,lines,particles,core=(255,244,232),glow=(134,104,204)):
    bright=layer(n);base=layer(n)
    d=ImageDraw.Draw(bright);g=ImageDraw.Draw(base)
    for pts,width,strength in lines:
        # variable width brush strokes, individual strokes drawn across their full motion path
        for i in range(len(pts)-1):
            frac=(i+.5)/(len(pts)-1)
            w=max(1,round(width*(math.sin(frac*math.pi)**.6)))
            d.line((pts[i],pts[i+1]),fill=tuple(int(x*strength) for x in core),width=w)
            g.line((pts[i],pts[i+1]),fill=tuple(int(x*strength) for x in glow),width=max(2,round(w*4)))
    for x,y,dx,dy,w,s in particles:
        d.line((x-dx,y-dy,x,y),fill=tuple(int(k*s) for k in core),width=max(1,int(w)))
        g.line((x-dx,y-dy,x,y),fill=tuple(int(k*s) for k in glow),width=max(2,int(w*3)))
    blur=np.asarray(base.filter(ImageFilter.GaussianBlur(n/85)),dtype=np.float32)
    near=np.asarray(base.filter(ImageFilter.GaussianBlur(n/220)),dtype=np.float32)
    return np.clip(np.asarray(bright,dtype=np.float32)+.7*near+.85*blur,0,255)
def sword(i):
    n=512;p=i/11;theta=-1.9+2.1*p
    lines=[]
    for k in range(4):
        spread=0.46+min(p*2.8,.9)-.22*k
        pts=path_arc(250,257,203-11*k,93-7*k,theta-spread,theta+.60,rot=-.48+0.08*p)
        lines.append((pts, [13,4,2,1][k],1-.17*k))
    particles=[]
    rnd=random.Random(420)
    for j in range(75):
        a=theta-rnd.random()*1.7
        r=rnd.uniform(.74,1.14)+.18*p
        x=250+200*r*math.cos(a);y=257+94*r*math.sin(a)-28*math.cos(a)
        particles.append((x,y,10*math.sin(a),-5*math.cos(a),rnd.uniform(1,2.3),rnd.uniform(.32,.75)))
    return glowy(n,lines,particles,core=(255,255,255),glow=(187,187,187))
def spark(i):
    n=512;p=i/7;lines=[];particles=[];rnd=random.Random(250)
    for k in range(34):
        a=rnd.uniform(0,2*math.pi);base=rnd.uniform(38,164);r=base*(.2+1.15*p);s=rnd.uniform(.4,1)
        tail=max(0,r-(20+30*(1-p))*s)
        x=256+math.cos(a)*r;y=253+math.sin(a)*r
        lines.append(([(256+math.cos(a)*tail,253+math.sin(a)*tail),(x,y)],rnd.uniform(1,5),s))
        for j in range(2):
            a2=a+.05*rnd.uniform(-1,1);r2=r+rnd.uniform(8,40)
            particles.append((256+math.cos(a2)*r2,253+math.sin(a2)*r2,math.cos(a2)*8,math.sin(a2)*8,1,.5))
    if i<3:
        lines.append(([(256-80*(1-p),253),(256,253),(256+80*(1-p),253)],9*(1-p)+1,1))
        lines.append(([(256,253-52*(1-p)),(256,253+52*(1-p))],5,1))
    return glowy(n,lines,particles,core=(255,255,255),glow=(190,190,190))
def ultimate(i):
    n=768;p=i/29;lines=[];particles=[];rnd=random.Random(666)
    # Three intersecting sword-bright ridgelines, unfolding like a violet mountain landscape.
    for k in range(7):
        w=8 if k==0 else 3+int(2*math.sin(k))
        lift=(p-.4)*90;theta=-2.8+p*3.6+k*.24
        radius=(175+28*k)*(.7+.43*p)
        pts=path_arc(384,410-lift+22*math.sin(k),radius,70+12*k,theta-1.50,theta+1.2,rot=-.65+.19*k)
        lines.append((pts,w, max(.24,1-k*.10)))
    # mountain-crest ribbon groups, changing width, height and transparency as the impact travels.
    for k in range(4):
        pts=[]
        for j in range(105):
            q=j/104;x=74+620*q
            crest=max(0,1-abs(q-(.28+.12*k))/(.19+.025*k))
            ridge=85*crest+17*math.sin(q*24+k)+22*math.sin(q*41-k)
            y=450-k*46-ridge*(.45+.8*math.sin(math.pi*p))+(p-.5)*185
            pts.append((x,y))
        lines.append((pts,4 if k==1 else 2,.86-.13*k))
    for k in range(140):
        a=rnd.uniform(0,math.tau);v=rnd.uniform(45,335)
        r=v*(.48+p*.88);x=384+math.cos(a)*r;y=384+math.sin(a)*r*.83-(p-.4)*80
        particles.append((x,y,math.cos(a)*rnd.uniform(4,18),math.sin(a)*13,rnd.uniform(1,3),rnd.uniform(.24,.85)))
    return glowy(n,lines,particles,core=(248,231,255),glow=(164,72,255))
def write_fx(name,n,func,envelope,size,impact):
    frames=[];raw=[func(i) for i in range(n)]
    # Use absolute emitted light modulation so the crescendo peaks at the actual impact.
    energy=[float(x.sum()) for x in raw];scale=max(energy)*.73
    for i,x in enumerate(raw):
        a=np.uint8(np.clip(x*(scale*envelope[i]/max(energy[i],1)),0,255))
        im=Image.fromarray(a).resize((size,size),Image.Resampling.LANCZOS)
        frames.append(im)
    # Common VFX deliberately grayscale; the runtime's force tint supplies faction colour.
    mode='L' if name!='shen_qianren' else 'RGB'
    strip=Image.new(mode,(size*n,size))
    for i,f in enumerate(frames):strip.paste(f.convert(mode),(i*size,0))
    if mode=='RGB':
        strip=strip.quantize(colors=240,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
    strip.save(V/(name+'.png'),optimize=True)
    thumb=Image.new('RGB',(6*128,math.ceil(n/6)*128))
    for i,f in enumerate(frames):thumb.paste(f.resize((128,128)),((i%6)*128,(i//6)*128))
    thumb.save(P/(name+'_vfx_contact.jpg'),quality=90)
    return {'timings_ms':[42]*n,'impact_frame':impact}
meta={'frame_index_base':1}
meta['slash_sword']=write_fx('slash_sword',12,sword,[.18,.57,1,.91,.83,.74,.62,.48,.34,.24,.14,.045],512,3)
meta['hit_spark']=write_fx('hit_spark',8,spark,[.9,1,.77,.62,.42,.27,.12,.035],512,2)
meta['shen_qianren']=write_fx('shen_qianren',30,ultimate,[.12,.16,.20,.25,.30,.38,.46,.54,.62,.71,.81,.91,1,.94,.87,.80,.73,.66,.58,.52,.46,.40,.34,.28,.22,.17,.13,.1,.065,.023],1024,13)
(V/'meta.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
# Cinematic close-up: face region remains stable, hair and background energy move independently.
src=Image.open(S/'cutin_source.png').convert('RGB')
w,h=src.size; crop_h=round(w*720/2560); top=(h-crop_h)//2
src=src.crop((0,top,w,top+crop_h)).resize((2560,720),Image.Resampling.LANCZOS)
a=np.array(src).astype(np.float32); yy,xx=np.mgrid[0:720,0:2560].astype(np.float32)
hair=np.exp(-((xx-300)/380)**2)*(0.3+.7*(yy/720))
bg=np.clip((xx-1170)/800,0,1)
frames=[]
random.seed(12)
petals=[(random.uniform(1300,2520),random.uniform(20,700),random.uniform(2,8),random.uniform(0,math.tau)) for _ in range(40)]
for i in range(8):
    t=math.tau*i/8
    dx=hair*9*np.sin(t+yy/140)+bg*11*np.sin(t+yy/190)
    dy=hair*5*np.cos(t+xx/150)+bg*7*np.cos(t+xx/280)
    out=np.stack([map_coordinates(a[:,:,k],[yy+dy,xx+dx],order=1,mode='nearest',prefilter=False) for k in range(3)],axis=-1)
    ripple=bg*(.45+.55*np.sin(xx/95+yy/52+t))*3.5
    out+=ripple[...,None]*np.array([1,.65,1.5])
    image=Image.fromarray(np.uint8(np.clip(out,0,255)),'RGB')
    overlay=Image.new('RGB',image.size);draw=ImageDraw.Draw(overlay)
    for (x,y,r,phase) in petals:
        x+=20*math.sin(t+phase);y+=12*math.cos(t+phase)
        draw.line((int(x-r*2),int(y+r*.7),int(x+r),int(y-r*.4)),fill=(138,104,189),width=max(1,int(r/2)))
    image=Image.fromarray(np.uint8(np.clip(np.asarray(image,dtype=np.int16)+np.asarray(overlay,dtype=np.int16)+np.asarray(overlay.filter(ImageFilter.GaussianBlur(6)),dtype=np.int16),0,255)))
    # Lossless output, 2560x720 opaque RGB.
    image.save(C/f'shen_qianren_{i+1:02d}.png',compress_level=6)
    frames.append(image)
frames[2].resize((1280,360)).save(P/'cutin_preview.jpg',quality=94)
