import sys, os
from PIL import Image, ImageDraw, ImageFilter
res = sys.argv[1]
A=(0x4F,0x6B,0xFF); B=(0x8E,0x54,0xE9)

def gradient(size):
    g=Image.new('RGBA',(size,size))
    px=g.load()
    for y in range(size):
        for x in range(size):
            t=(x+y)/(2*(size-1))
            px[x,y]=tuple(int(A[i]+(B[i]-A[i])*t) for i in range(3))+(255,)
    return g

def shield(size, scale=0.62, color=(255,255,255,255)):
    """White shield with keyhole cut-out, centred, on transparent canvas."""
    S=size*4
    img=Image.new('RGBA',(S,S),(0,0,0,0))
    d=ImageDraw.Draw(img)
    w=S*scale; h=w*1.16
    cx=S/2; top=(S-h)/2
    l=cx-w/2; r=cx+w/2
    # shield outline: flat-ish top with shoulders, curved to a point
    pts=[(cx,top),(r,top+h*0.14),(r,top+h*0.48)]
    # quadratic bezier sides meeting in a point at the bottom
    def bez(p0,c,p2,n=24):
        out=[]
        for i in range(1,n+1):
            t=i/n
            out.append(((1-t)**2*p0[0]+2*(1-t)*t*c[0]+t*t*p2[0],
                        (1-t)**2*p0[1]+2*(1-t)*t*c[1]+t*t*p2[1]))
        return out
    pts+=bez((r,top+h*0.48),(r,top+h*0.82),(cx,top+h))
    pts+=bez((cx,top+h),(l,top+h*0.82),(l,top+h*0.48))
    pts+= [(l,top+h*0.14)]
    d.polygon(pts,fill=color)
    # keyhole
    kr=w*0.13; ky=top+h*0.42
    d.ellipse([cx-kr,ky-kr,cx+kr,ky+kr],fill=(0,0,0,0))
    d.polygon([(cx-kr*0.55,ky),(cx+kr*0.55,ky),(cx+kr*0.85,ky+kr*2.6),(cx-kr*0.85,ky+kr*2.6)],fill=(0,0,0,0))
    return img.resize((size,size),Image.LANCZOS)

def legacy(size):
    S=size*4
    bg=gradient(S)
    mask=Image.new('L',(S,S),0)
    ImageDraw.Draw(mask).rounded_rectangle([0,0,S-1,S-1],radius=int(S*0.23),fill=255)
    out=Image.new('RGBA',(S,S),(0,0,0,0)); out.paste(bg,(0,0),mask)
    out=out.resize((size,size),Image.LANCZOS)
    sh=shield(size,0.5)
    out.alpha_composite(sh)
    return out

def round_icon(size):
    S=size*4
    bg=gradient(S)
    mask=Image.new('L',(S,S),0)
    ImageDraw.Draw(mask).ellipse([0,0,S-1,S-1],fill=255)
    out=Image.new('RGBA',(S,S),(0,0,0,0)); out.paste(bg,(0,0),mask)
    out=out.resize((size,size),Image.LANCZOS)
    out.alpha_composite(shield(size,0.48))
    return out

dens={'mdpi':1,'hdpi':1.5,'xhdpi':2,'xxhdpi':3,'xxxhdpi':4}
for name,f in dens.items():
    d=os.path.join(res,f'mipmap-{name}'); os.makedirs(d,exist_ok=True)
    legacy(int(48*f)).save(os.path.join(d,'ic_launcher.png'))
    round_icon(int(48*f)).save(os.path.join(d,'ic_launcher_round.png'))
    # adaptive foreground: 108dp canvas, art inside 66dp safe zone
    shield(int(108*f),0.36).save(os.path.join(d,'ic_launcher_foreground.png'))
    # splash logo (pre-Android 12): 160dp
    dd=os.path.join(res,f'drawable-{name}'); os.makedirs(dd,exist_ok=True)
    legacy(int(112*f)).save(os.path.join(dd,'splash_logo.png'))
    # Android 12 splash icon: 288dp canvas with art inside 192dp circle (white on gradient bg)
    shield(int(288*f),0.34).save(os.path.join(dd,'splash_icon.png'))
# Play Store icon
legacy(512).save(os.path.join(res,'..','..','..','..','..','assets_store_icon_512.png'))
print('ok')
