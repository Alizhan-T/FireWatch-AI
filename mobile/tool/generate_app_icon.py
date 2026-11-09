#!/usr/bin/env python3
"""Generate the FireWatch AI iOS app icon using Pillow.

Run from the repository root:
  python3 mobile/tool/generate_app_icon.py

The script writes the 1024x1024 App Store icon into the Xcode asset catalog.
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import json
import math

ROOT = Path(__file__).resolve().parents[2]
ICON_DIR = ROOT / "mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
ICON_DIR.mkdir(parents=True, exist_ok=True)
SIZE = 1024
SCALE = 4

# Draw at 4x resolution for clean antialiasing.
n = SIZE * SCALE
img = Image.new("RGB", (n, n), (8, 15, 29))
px = img.load()
for y in range(n):
    t = y / max(1, n - 1)
    for x in range(n):
        glow = max(0.0, 1.0 - math.sqrt(((x/n)-0.50)**2 + ((y/n)-0.43)**2) / 0.78)
        px[x, y] = (
            int(7 + 8*t + 5*glow),
            int(15 + 8*t + 4*glow),
            int(29 + 13*t + 7*glow),
        )

draw = ImageDraw.Draw(img, "RGBA")

def pts(values):
    return [(int(x*SCALE), int(y*SCALE)) for x, y in values]

# Soft ambient flame glow.
glow_layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow_layer)
gd.ellipse((300*SCALE, 170*SCALE, 740*SCALE, 760*SCALE), fill=(255, 88, 25, 90))
glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(85*SCALE))
img = Image.alpha_composite(img.convert("RGBA"), glow_layer)
draw = ImageDraw.Draw(img, "RGBA")

# Protective shield silhouette.
shield = [(512,145),(760,238),(744,500),(680,660),(512,810),(344,660),(280,500),(264,238)]
draw.polygon(pts(shield), fill=(26,43,65,255), outline=(115,145,180,210), width=7*SCALE)
inner = [(512,190),(714,270),(700,492),(642,628),(512,748),(382,628),(324,492),(310,270)]
draw.polygon(pts(inner), fill=(13,26,44,255), outline=(57,83,115,255), width=4*SCALE)

# Forest silhouettes at the bottom of the shield.
forest = Image.new("RGBA", (n,n), (0,0,0,0))
fd = ImageDraw.Draw(forest)
tree_color=(37,76,91,255)
def tree(cx, base, h, w):
    fd.polygon(pts([(cx,base-h),(cx-w,base-h*0.48),(cx-w*0.42,base-h*0.48),
                    (cx-w*0.86,base-h*0.12),(cx+w*0.86,base-h*0.12),
                    (cx+w*0.42,base-h*0.48),(cx+w,base-h*0.48)]), fill=tree_color)
    fd.rectangle((int((cx-5)*SCALE),int((base-h*0.12)*SCALE),
                  int((cx+5)*SCALE),int(base*SCALE)),fill=(48,66,78,255))
for args in [(390,650,170,58),(470,680,210,70),(590,680,205,68),(670,650,165,55)]:
    tree(*args)
img = Image.alpha_composite(img, forest)
draw = ImageDraw.Draw(img, "RGBA")

# Main flame: warm outer flame and bright inner core.
outer = [(512,260),(570,335),(596,402),(660,470),(675,548),(648,614),
         (598,660),(512,682),(426,660),(366,614),(340,548),(352,488),
         (392,432),(405,510),(438,468),(448,405),(480,350)]
draw.polygon(pts(outer), fill=(255,91,34,255))
inner_flame = [(512,390),(548,445),(575,490),(579,540),(554,586),
               (512,610),(470,586),(445,550),(455,505),(487,465)]
draw.polygon(pts(inner_flame), fill=(255,174,55,255))
core = [(512,492),(535,530),(535,558),(512,580),(489,558),(489,535)]
draw.polygon(pts(core), fill=(255,231,170,255))

# Subtle highlight line on shield.
draw.line(pts([(330,275),(512,205),(694,275)]), fill=(174,197,222,90), width=3*SCALE)

# Downsample with high-quality antialiasing and flatten to RGB.
img = img.convert("RGB").resize((SIZE,SIZE), Image.Resampling.LANCZOS)
img.save(ICON_DIR / "FireWatchAppIcon.png", format="PNG", optimize=True)

contents = {
    "images": [{
        "filename": "FireWatchAppIcon.png",
        "idiom": "universal",
        "platform": "ios",
        "size": "1024x1024"
    }],
    "info": {"author": "xcode", "version": 1}
}
(ICON_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
print(f"Generated: {ICON_DIR / 'FireWatchAppIcon.png'}")
