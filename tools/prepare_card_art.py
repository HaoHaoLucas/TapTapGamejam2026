"""Reproduce the card PNGs from the artist's archive. Requires Pillow and numpy.

Usage: py tools/prepare_card_art.py path/to/卡牌.zip
No image-generation service is used. Original pixels are retained in source/.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "assets" / "cards"
SCALE = 4


def trim(im: Image.Image) -> Image.Image:
    return im.crop(im.getchannel("A").getbbox())


def curve(points, steps=24):
    """Smooth hand-drawn strokes using a Catmull-Rom spline."""
    pts = [points[0], *points, points[-1]]
    result = []
    for i in range(1, len(pts) - 2):
        a, b, c, d = pts[i - 1:i + 3]
        for j in range(steps):
            t = j / steps
            result.append(tuple(0.5 * (2 * b[k] + (-a[k] + c[k]) * t +
                (2 * a[k] - 5 * b[k] + 4 * c[k] - d[k]) * t*t +
                (-a[k] + 3 * b[k] - 3 * c[k] + d[k]) * t*t*t) for k in (0, 1)))
    return [*result, points[-1]]


def stroke(draw, points, width, fill=255, smooth=True):
    pts = curve(points) if smooth else points
    pts = [(round(x*SCALE), round(y*SCALE)) for x, y in pts]
    draw.line(pts, fill=fill, width=round(width*SCALE), joint="curve")
    r = width*SCALE/2
    for x, y in (pts[0], pts[-1]):
        draw.ellipse((x-r, y-r, x+r, y+r), fill=fill)


def painted(mask, palette, seed):
    """Shaded pigment and a displaced light rim, sampled from the supplied set."""
    mask = mask.resize((mask.width//SCALE, mask.height//SCALE), Image.Resampling.LANCZOS)
    yy, xx = np.indices((mask.height, mask.width))
    rng = np.random.default_rng(seed)
    grain = rng.normal(0, .8, xx.shape) + np.sin(xx*.04 + yy*.08)*1.8
    light = np.clip(.42 + .20*np.cos(xx*.015) - .16*yy/max(mask.height, 1), 0, 1)
    rgb = np.array(palette[0]) + light[..., None]*(np.array(palette[1])-palette[0])
    rgb = np.clip(rgb + grain[..., None], 0, 255).astype("uint8")
    face = Image.fromarray(rgb).convert("RGBA"); face.putalpha(mask)
    rim_mask = mask.filter(ImageFilter.MaxFilter(7))
    rim = Image.new("RGBA", mask.size, palette[2]); rim.putalpha(rim_mask)
    rim.alpha_composite(face, (2, 3))
    return trim(rim)


def new_digit(number, palette):
    mask = Image.new("L", (300*SCALE, 450*SCALE)); d = ImageDraw.Draw(mask)
    paths = {
        6: [(222, 42), (156, 62), (95, 144), (66, 265), (82, 363), (157, 402), (227, 366), (237, 278), (179, 236), (106, 258), (72, 310)],
        7: [(57, 65), (130, 56), (240, 58), (199, 139), (157, 230), (125, 329), (111, 400)],
        8: [(151, 222), (77, 164), (82, 85), (153, 46), (223, 83), (224, 160), (151, 222), (72, 279), (73, 357), (149, 405), (228, 365), (231, 282), (151, 222)],
        9: [(223, 174), (190, 224), (111, 225), (65, 167), (76, 86), (142, 48), (209, 77), (232, 163), (211, 278), (164, 356), (103, 400)],
    }
    stroke(d, paths[number], 51)
    return painted(mask, palette, number)


def mark_icon(kind):
    mask = Image.new("L", (128*SCALE, 128*SCALE)); d = ImageDraw.Draw(mask)
    def line(points, width=8, smooth=True): stroke(d, points, width, smooth=smooth)
    def ellipse(box, width=7, fill=None):
        d.ellipse(tuple(v*SCALE for v in box), outline=255, width=width*SCALE, fill=fill)
    def polygon(points): d.polygon([(x*SCALE, y*SCALE) for x,y in points], fill=255)
    if kind == "magnet":
        line([(28,25),(28,73),(39,98),(64,106),(89,98),(100,73),(100,25)], 15)
        line([(20,45),(36,45)], 4, False); line([(92,45),(108,45)], 4, False)
    elif kind == "yinyang":
        ellipse((15,15,113,113), 7)
        line([(64,17),(91,32),(88,51),(64,64),(40,78),(39,97),(64,111)], 7)
        ellipse((56,32,72,48), fill=255); ellipse((56,80,72,96), 4)
    elif kind in ("flammable", "smolder"):
        line([(64,15),(55,42),(37,29),(24,65),(28,88),(45,108),(82,110),(105,89),(103,59),(85,36),(83,65),(64,45),(64,15)], 7)
        line([(62,65),(49,87),(56,105),(73,108),(82,92),(62,65)], 6)
        if kind == "smolder":
            line([(24,117),(50,119),(79,117),(105,119)], 7)
            line([(29,7),(23,17),(29,25)], 4); line([(98,7),(104,18),(99,28)],4)
    elif kind in ("combo", "vanguard"):
        if kind == "combo":
            line([(22,43),(66,43),(58,29),(82,47),(61,66)], 9, False)
            line([(42,85),(96,85),(88,71),(112,89),(91,108)], 9, False)
        else:
            polygon([(64,13),(106,56),(81,52),(81,99),(47,110),(47,52),(22,62)])
            line([(27,109),(18,118)],5,False); line([(101,105),(91,118)],5,False)
    elif kind == "frozen":
        for a in range(0,360,60):
            rad=math.radians(a); u=(math.cos(rad),math.sin(rad)); v=(-u[1],u[0])
            line([(64,64),(64+u[0]*47,64+u[1]*47)],6,False)
            for s in (-1,1):
                line([(64+u[0]*42+v[0]*s*10,64+u[1]*42+v[1]*s*10),(64+u[0]*30,64+u[1]*30)],5,False)
    elif kind == "price":
        ellipse((18,47,81,110),6); ellipse((29,58,70,99),4)
        line([(50,96),(50,64)],5,False)
        line([(72,55),(104,21),(105,43),(104,21),(82,23)],8,False)
    elif kind == "ghost":
        line([(28,106),(28,52),(36,27),(61,17),(86,24),(99,46),(99,107),(82,94),(65,111),(47,96),(28,106)],7)
        ellipse((43,48,53,65),fill=255); ellipse((75,48,85,65),fill=255)
    return painted(mask, ((233,220,131),(255,255,174),(209,192,102,255)), sum(map(ord,kind)))


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("archive", type=Path); args = parser.parse_args()
    ROOT.mkdir(parents=True, exist_ok=True)
    manifest = {"archive": args.archive.name, "assets": {}, "duplicates": {}}
    with zipfile.ZipFile(args.archive) as z:
        def save(name, source, crop=False):
            raw=z.read(source); im=Image.open(z.open(source)).convert("RGBA")
            original=ROOT/"source"/name; original.parent.mkdir(parents=True,exist_ok=True); original.write_bytes(raw)
            out=ROOT/name; out.parent.mkdir(parents=True,exist_ok=True)
            (trim(im) if crop else im).save(out)
            manifest["assets"][name]={"source":source,"sha256":hashlib.sha256(raw).hexdigest(),"processing":"alpha crop" if crop else "original pixels"}
            return im
        save("faces/positive.png","卡牌/正/IMG_2794.PNG")
        save("faces/negative.png","卡牌/负/IMG_2793.PNG")
        save("faces/neutral.png","卡牌/符号和0/IMG_2797.PNG")
        zero=save("faces/zero.png","卡牌/符号和0/IMG_2807.PNG")
        save("faces/back.png","卡牌/card_back.PNG")
        save("faces/room.png","卡牌/map_room_.png")
        for n,img in {1:2788,2:2787,3:2789,4:2790,5:2791}.items():
            save(f"glyphs/positive_{n}.png",f"卡牌/正/IMG_{img}.PNG",True)
        for n,img in {1:2806,2:2805,3:2804,4:2803,5:2802}.items():
            save(f"glyphs/negative_{n}.png",f"卡牌/负/IMG_{img}.PNG",True)
        for name,img in {"minus":2798,"add":2799,"mul":2800,"divide":2801}.items():
            save(f"glyphs/{name}.png",f"卡牌/符号和0/IMG_{img}.PNG",True)
        prefix="卡牌/正/强化印记 - 副本/"
        originals={"num1":"+1.png","num2":"+2.png","num3":"+3.png","echo":"fu xian.png","return":"hui shou.PNG","fragile":"yi sui.PNG","alchemy":"dian jin shou.PNG","slot_available":"card_mark_available.png","slot_occupied":"card_mark_unavailable.png"}
        for name,source in originals.items(): save(f"marks/{name}.png",prefix+source,True)
        for name in z.namelist():
            if "强化印记" in name and not name.endswith("/") and not name.startswith(prefix):
                manifest["duplicates"][name]={"canonical":next((f"marks/{k}.png" for k,v in originals.items() if v==name.rsplit("/",1)[1]),""),"sha256":hashlib.sha256(z.read(name)).hexdigest()}
        # Zero's dark teal pigment is separable from the pale face inside this ROI.
        roi=zero.crop((220,260,560,790)); arr=np.array(roi).astype(float)
        alpha=np.clip((115-arr[:,:,0])*10,0,255).astype("uint8")
        rgba=np.zeros_like(arr,dtype="uint8"); rgba[:,:,:3]=(37,61,65);rgba[:,:,3]=alpha
        glyph=trim(Image.fromarray(rgba))
        glyph.save(ROOT/"glyphs/neutral_0.png")
        manifest["assets"]["glyphs/neutral_0.png"]={"source":"faces/zero.png","processing":"central zero pigment extraction"}
        palettes={"positive":((48,35,12),(91,70,26),(184,153,66,255)),"negative":((35,35,48),(60,60,78),(140,140,167,255))}
        for tone,palette in palettes.items():
            for n in range(6,10):
                name=f"glyphs/{tone}_{n}.png";new_digit(n,palette).save(ROOT/name)
                manifest["assets"][name]={"source":f"glyphs/{tone}_1.png through {tone}_5.png","processing":"locally drawn curved strokes; matching pigment, grain and edge palette"}
            mask=glyph.getchannel("A").resize((glyph.width*SCALE,glyph.height*SCALE))
            painted(mask,palette,0).save(ROOT/f"glyphs/{tone}_0.png")
            manifest["assets"][f"glyphs/{tone}_0.png"]={"source":"glyphs/neutral_0.png","processing":"palette matched"}
        for kind in ("magnet","yinyang","flammable","smolder","combo","frozen","price","ghost","vanguard"):
            name=f"marks/{kind}.png"; mark_icon(kind).save(ROOT/name)
            manifest["assets"][name]={"source":"marks/echo.png, marks/return.png, marks/fragile.png","processing":"locally drawn motif with matching pale gold pigment and rough edge"}
    (ROOT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    (ROOT/"source"/".gdignore").write_text("", encoding="utf-8")
    print(f"Prepared {len(manifest['assets'])} card assets in {ROOT}")


if __name__=="__main__": main()
