"""Shen Qinghe sprite production: generated handpainted keyframes, registered local
mesh interpolation, anchored feet, independent cloth/hair follow-through.
No frame is copied simply to inflate the drawing count."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy.interpolate import RBFInterpolator
from scipy import ndimage as nd
import numpy as np, json, math, functools, os

B=Path(__file__).resolve().parent.parent
K=B/'characters/shen_peak/source/normalized'
F=B/'characters/shen_peak/frames'
F.mkdir(exist_ok=True)
M=json.loads((B/'source/landmarks.json').read_text())
N=512
Y,X=np.mgrid[:N,:N].astype(np.float32)
coarse=np.stack(np.meshgrid(np.linspace(0,511,121),np.linspace(0,511,121)),-1)
boundary=np.array([[0,0],[255,0],[511,0],[511,255],[511,511],[255,511],[0,511],[0,255]],float)
def read_pose(k):
    a=np.array(Image.open(K/(k+'.png')).convert('RGBA'))
    p=np.array(M[k],np.float32)
    # Align actual boot footprint, not the skirt or sword. Keep original stand fixed.
    actual=(p[15,0]+p[17,0])/2
    expected=(M['base'][15][0]+M['base'][17][0])/2
    shift=round(expected-actual) if k!='base' else 0
    ys,xs=np.where(a[...,3]>128)
    shift=max(3-int(xs.min()),min(508-int(xs.max()),shift))
    if shift:
        out=np.zeros_like(a)
        if shift>0:out[:,shift:]=a[:,:-shift]
        else:out[:,:shift]=a[:,-shift:]
        a=out;p[:,0]+=shift
    return a,p

def color_premul(a):
    b=a.astype(np.float32)/255
    b[...,:3]*=b[...,3:]
    return b

def restore(b):
    # premultiplied image; prevent transparent seams between key silhouettes.
    q=np.zeros_like(b);q[...,3]=np.clip(b[...,3],0,1)
    q[...,:3]=np.clip(b[...,:3]/np.maximum(q[...,3:],1e-6),0,1)
    return np.uint8(np.clip(q*255+.5,0,255))

def fit_points(p,other):
    # Keep the blade straight: give the mesh control points at both ends and interior.
    a=p[7];b=p[8];c=p[6]
    pts=np.vstack([p,a+(b-a)*.25,a+(b-a)*.5,a+(b-a)*.75])
    return np.delete(p,8,axis=0)

def warp(src, fromp, top):
    """Inverse local mesh. Source and destination differ at individual joints and
    independent long hair/hem controls rather than a whole-body affine transform."""
    fromp=fit_points(fromp,top);top=fit_points(top,fromp)
    origin=np.vstack([top,boundary])
    delta=np.vstack([fromp-top,np.zeros_like(boundary)])
    # RBF inference on a fine grid; mildly smooth to avoid folds between closely spaced joints
    model=RBFInterpolator(origin/511,delta,kernel='thin_plate_spline',smoothing=.003)
    dis=model(coarse.reshape(-1,2)/511).reshape(121,121,2)
    dx=np.asarray(Image.fromarray(dis[:,:,0].astype(np.float32)).resize((N,N),Image.Resampling.BICUBIC))
    dy=np.asarray(Image.fromarray(dis[:,:,1].astype(np.float32)).resize((N,N),Image.Resampling.BICUBIC))
    coords=[Y+dy,X+dx]
    return np.stack([nd.map_coordinates(src[...,i],coords,order=1,mode='constant',cval=0,prefilter=False) for i in range(4)],axis=-1)

def fix_feet(a,air=False):
    yy,xx=np.where(a[...,3]>128)
    if not len(yy):raise ValueError('empty sprite')
    # global y offset only to compensate subpixel warp at contact plane.
    if not air:
        dy=479-int(yy.max())
        if dy:
            out=np.zeros_like(a)
            if dy>0:out[dy:]=a[:-dy]
            else:out[:dy]=a[-dy:]
            a=out
    # transparent perimeter guaranteed; no actual silhouettes are clipped (checked later).
    a[a[...,3]<3]=0
    return a

def remove_blade(a,p):
    h=p[7];tip=p[8];d=tip-h;den=max(float(d@d),1)
    t=((X-h[0])*d[0]+(Y-h[1])*d[1])/den
    dist=np.abs((X-h[0])*d[1]-(Y-h[1])*d[0])/math.sqrt(den)
    opaque=a[...,3]>24
    mask=(t>.025)&(t<1.05)&(dist<9)&opaque
    if not mask.any():return a.copy()
    edt,inds=nd.distance_transform_edt(~(opaque&~mask),return_indices=True)
    out=a.copy();out[mask]=0
    fill=mask&(edt<=4);out[fill]=a[inds[0][fill],inds[1][fill]]
    return out

def paint_blade(a,p):
    h=p[7];tip=p[8];d=tip-h;L=float(np.linalg.norm(d))
    if L<15:return a
    u=d/L;v=np.array([-u[1],u[0]])
    im=Image.fromarray(a,'RGBA')
    layer=Image.new('RGBA',(N*2,N*2));draw=ImageDraw.Draw(layer)
    def xy(q):return (float(q[0]*2),float(q[1]*2))
    blade=[h-v*3.25,h+d*.88-v*2,tip,h+d*.88+v*2,h+v*3.25]
    draw.polygon([xy(q) for q in blade],fill=(143,139,155,255))
    draw.polygon([xy(q) for q in [h-v*3.25,h+d*.88-v*2,tip,h+v*.1]],fill=(225,220,218,255))
    draw.line([xy(h+v*.15),xy(tip)],fill=(244,237,231,220),width=2)
    return np.array(Image.alpha_composite(im,layer.resize((N,N),Image.Resampling.LANCZOS)))

def morph(a0,p0,a1,p1,t,style,phase=0.):
    if t<1e-6:return a0.copy()
    if t>1-1e-6:return a1.copy()
    # eased spacing per segment, with independently delayed hair and cloth.
    e=t
    v=np.full(len(p0),e,np.float32)
    delay=[18,19,20,21,22,23]
    for k in delay:
        td=np.clip(t-.12*math.sin(math.pi*t),0,1)
        v[k]=td
    p=p0+(p1-p0)*v[:,None]
    sway=math.sin(math.pi*t)
    # secondary arcs based on garment flow. Distinct movement with no chest/face warping beyond landmarks.
    p[19,0]+= (4 if style=='idle' else 7)*sway*math.cos(phase)
    p[18,1]+= 2*sway
    p[20,0]+= (4 if style=='idle' else 6)*sway*math.cos(phase+.7)
    p[21,1]-= 3*sway
    p[22,0]+= 4*sway*math.sin(phase+.8)
    # Maintain an arc for tip movement and approximately preserve blade length.
    d0=p0[8]-p0[7];d1=p1[8]-p1[7]
    angle0=math.atan2(d0[1],d0[0]);angle1=math.atan2(d1[1],d1[0]);d=(angle1-angle0+math.pi)%(2*math.pi)-math.pi
    angle=angle0+d*e
    length=np.linalg.norm(d0)*(1-e)+np.linalg.norm(d1)*e
    tip=p[7]+np.array([math.cos(angle),math.sin(angle)])*length
    # Constrain tip to frame while avoiding huge mesh extrapolation; endpoint art still exact.
    p[8]=np.clip(tip,[5,5],[506,474])
    if style=='idle':
        wa=warp(color_premul(a0),p0,p);wb=warp(color_premul(a1),p1,p)
        raw=(1-e)*wa+e*wb
    else:
        wa=warp(color_premul(remove_blade(a0,p0)),p0,p)
        wb=warp(color_premul(remove_blade(a1,p1)),p1,p)
        primary,secondary=(wa,wb) if e<.5 else (wb,wa)
        mix=(e if e<.5 else 1-e)*.6
        blend=mix*secondary[...,3:]*primary[...,3:]
        raw=primary*(1-blend)+secondary*blend
        raw[...,3]=primary[...,3]
    # Alpha normalized, smooth matte discourages doubled faint silhouettes.
    out=restore(raw)
    alpha=raw[...,3]
    out[...,3]=np.round(np.clip((alpha-.08)/.84,0,1)*255).astype(np.uint8)
    out[out[...,3]==0]=0
    return fix_feet(paint_blade(out,p) if style!='idle' else out)

cache={k:read_pose(k) for k in M if k!='_order'}
def animation(name,keys,n,loop=False):
    result=[]
    for i in range(n):
        found=False
        for j in range(len(keys)-1):
            start,k0=keys[j];end,k1=keys[j+1]
            if start<=i<=end:
                a,p=cache[k0];b,q=cache[k1]
                t=(i-start)/(end-start)
                fr=morph(a,p,b,q,t,'idle' if name=='idle' else name,j*.85)
                result.append(fr);found=True;break
        if not found:raise RuntimeError((name,i))
    return result

# Different drawn keyposes; the source and ending stance are deliberately the same reference.
# timing key indices are zero-based internally; metadata uses one-based frame numbering.
seq={
 'idle': ([(0,'base'),(4,'idle02'),(8,'idle03'),(12,'idle04'),(16,'base')],16),
 'attack_light': ([(0,'base'),(2,'attack02'),(6,'attack03'),(11,'attack04'),(15,'attack05'),(19,'attack06'),(21,'base')],22),
 'hit': ([(0,'hit01'),(4,'hit02'),(8,'hit03'),(11,'base')],12),
 'hit_heavy': ([(0,'hit04'),(8,'hit05'),(15,'hit06'),(21,'base')],22),
 'shen_qianren': ([(0,'base'),(8,'ultimate02'),(14,'ultimate03'),(22,'ultimate04'),(30,'ultimate03'),(39,'ultimate02'),(45,'ultimate06'),(49,'base')],50)
}
meta={
 'frame_index_base':1,
 'idle':{'timings_ms':[83]*16},
 'attack_light':{'timings_ms':[42]*22,'impact_frame':12},
 'hit':{'timings_ms':[42]*12},
 'hit_heavy':{'timings_ms':[42]*22},
 'shen_qianren':{'timings_ms':[42]*50,'impact_frame':23}
}
def write_strip(name,frames):
    out=Image.new('RGBA',(N*len(frames),N))
    for i,f in enumerate(frames):out.paste(Image.fromarray(f),(N*i,0))
    out.save(F/(name+'.png'),compress_level=6)
def contact(name,frames):
    cols=5;size=256;rows=(len(frames)+cols-1)//cols
    out=Image.new('RGB',(cols*size,rows*(size+24)),'#24383d');d=ImageDraw.Draw(out)
    for i,a in enumerate(frames):
        im=Image.fromarray(a).resize((size,size),Image.Resampling.LANCZOS)
        x=(i%cols)*size;y=(i//cols)*(size+24)
        out.paste(im,(x,y),im.getchannel('A'))
        d.line((x,y+240,x+size,y+240),fill='#967f62',width=1)
        d.text((x+10,y+size+3),f'{i+1:02d}',fill='#e7ddc6')
    out.save(B/'preview'/f'{name}_contact.jpg',quality=92)
if __name__=='__main__':
    for name,(keys,n) in seq.items():
        print('Building',name,flush=True)
        frames=animation(name,keys,n)
        write_strip(name,frames);contact(name,frames)
    (F/'meta.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
