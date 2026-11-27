from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np
from scipy import ndimage as nd
import json,sys

B=Path(__file__).resolve().parent.parent
ROOT=B.parents[2]
SRC=B/'characters/shen_peak/source'
BASE=ROOT/'assets/characters/shen_peak/frames/stand.png'
OUT=SRC/'normalized';OUT.mkdir(exist_ok=True)
def normalize(name,src,cols,rows):
    im=Image.open(src).convert('RGBA'); a=np.array(im);alpha=a[:,:,3]
    labels,n=nd.label(alpha>128); counts=np.bincount(labels.ravel());counts[0]=0
    comps=np.argsort(counts)[-(cols*rows):]
    coms=[]
    for i in comps:
        yy,xx=np.where(labels==i)
        coms.append((int(i),int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1,float(xx.mean()),float(yy.mean())))
    # group by vertical row, then horizontal. Permit art over nominal cell borders but not overlap.
    coms.sort(key=lambda c:c[-1]);coms=[x for row in range(rows) for x in sorted(coms[row*cols:(row+1)*cols],key=lambda c:c[-2])]
    print(name,[(x[1],x[2],x[3],x[4]) for x in coms])
    dis,near=nd.distance_transform_edt(labels==0,return_indices=True)
    nearest=labels[near[0],near[1]]
    # Same scale for each sheet based on nominal standing height. Leaning/crouching keeps shorter silhouette.
    heights=[x[4]-x[2] for x in coms]
    nominal=float(np.median(sorted(heights)[-3:])) if len(heights)>3 else float(np.median(heights))
    ratio=392/nominal
    report=[]
    for idx,(i,l,t,r,b,cx,cy) in enumerate(coms):
        mask=((nearest==i)&(dis<=2.8)) | (labels==i)
        q=a.copy();q[:,:,3]=np.where(mask,q[:,:,3],0);q[q[:,:,3]==0,:3]=0
        crop=Image.fromarray(q).crop((max(0,l-3),max(0,t-3),min(im.width,r+3),min(im.height,b+3)))
        # feet anchor based on lowest solid boot pixels over bottom 7% of body.
        solid=labels==i
        footband=solid[max(t,b-int((b-t)*.065)):b,:]
        xs=np.where(footband)[1]
        # shoes can have broad skirts nearby; bottom rows typically feet only.
        footx=(float(np.min(xs))+float(np.max(xs)))/2
        cut_l=max(0,l-3);cut_t=max(0,t-3)
        sc=ratio
        rw,rh=round(crop.width*sc),round(crop.height*sc)
        if rw>495:
            sc*=495/rw;rw,rh=round(crop.width*sc),round(crop.height*sc)
        piece=crop.resize((rw,rh),Image.Resampling.LANCZOS)
        x=round(256-(footx-cut_l)*sc); y=round(480-(b-cut_t)*sc)
        if x<3:x=3
        if x+rw>509:x=509-rw
        canvas=Image.new('RGBA',(512,512));canvas.alpha_composite(piece,(x,y))
        arr=np.array(canvas);yy,xx=np.where(arr[:,:,3]>128)
        correction=480-(yy.max()+1)
        if correction:
            fixed=Image.new('RGBA',(512,512));fixed.alpha_composite(canvas,(0,int(correction)));canvas=fixed
        canvas.save(OUT/f'{name}{idx+1:02d}.png')
        report.append(dict(name=f'{name}{idx+1:02d}',source_box=[l,t,r,b],ratio=sc,foot_source=footx,offset=[x,y+int(correction)]))
    return report
def make_sheet(paths,name):
    cols=3 if len(paths)!=4 else 2
    rows=(len(paths)+cols-1)//cols
    im=Image.new('RGB',(cols*512,rows*548),'#24383d');d=ImageDraw.Draw(im)
    font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',18)
    for idx,p in enumerate(paths):
        x=idx%cols*512;y=idx//cols*548
        im.paste(Image.open(p),(x,y),Image.open(p).getchannel('A'))
        for k in range(0,512,32):
            d.line((x+k,y,x+k,y+511),fill='#53666a',width=1)
            d.line((x,y+k,x+511,y+k),fill='#53666a',width=1)
            if k%64==0:
                d.text((x+k+2,y+2),str(k),fill='#d0d8d5',font=font)
                d.text((x+2,y+k+2),str(k),fill='#d0d8d5',font=font)
        d.text((x+16,y+516),p.stem,fill='#eeeeee',font=font)
    im.save(OUT/(name+'_grid.jpg'),quality=92)
if __name__=='__main__':
    base=Image.open(BASE).convert('RGBA').resize((512,512),Image.Resampling.LANCZOS)
    base.save(OUT/'base.png')
    reports=[]
    for name in ['attack','hit','ultimate','idle']:
        p=SRC/(name+'_source.png')
        if p.exists():
            nrow,ncol=(2,2) if name=='idle' else (2,3)
            reports+=normalize(name,p,ncol,nrow)
            make_sheet(sorted(OUT.glob(name+'[0-9][0-9].png')),name)
    make_sheet([OUT/'base.png'],'base')
    (OUT/'normalize.json').write_text(json.dumps(reports,indent=2))
