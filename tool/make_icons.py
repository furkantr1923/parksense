"""PARKSENSE logo ve platform ikonlarını üretir (Pillow).
Kullanım: python3 tool/make_icons.py"""
from PIL import Image, ImageDraw, ImageFont
import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, 'assets/fonts/DMSans-Bold.ttf')

def logo(size, rounded=True, pad=0.0):
    s = size * 4  # süper örnekleme
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    # dikey mavi gradyan
    grad = Image.new('RGBA', (s, s))
    gd = ImageDraw.Draw(grad)
    top, bot = (47, 111, 255), (22, 64, 196)
    for y in range(s):
        t = y / (s - 1)
        gd.line([(0, y), (s, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
    mask = Image.new('L', (s, s), 0)
    md = ImageDraw.Draw(mask)
    r = int(s * 0.23) if rounded else 0
    m = int(s * pad)
    md.rounded_rectangle([m, m, s - m - 1, s - m - 1], radius=r, fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # konum iğnesi (beyaz)
    cx, cy = s / 2, s * 0.44
    R = s * 0.27
    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill='white')
    import math
    ay = s * 0.86
    D = ay - cy
    phi = math.acos(R / D)  # teğet noktaları: çentiksiz iğne
    d.polygon([(cx - R * math.sin(phi), cy + R * math.cos(phi)), (cx + R * math.sin(phi), cy + R * math.cos(phi)), (cx, ay)], fill='white')
    # "P" harfi
    f = ImageFont.truetype(FONT, int(R * 1.5))
    bbox = d.textbbox((0, 0), 'P', font=f)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((cx - w / 2 - bbox[0], cy - h / 2 - bbox[1]), 'P', font=f, fill=(31, 91, 255))
    return img.resize((size, size), Image.LANCZOS)

os.makedirs(os.path.join(ROOT, 'assets/brand'), exist_ok=True)
logo(512).save(os.path.join(ROOT, 'assets/brand/logo.png'))
logo(1024).save(os.path.join(ROOT, 'assets/brand/logo_1024.png'))
for name, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    p = os.path.join(ROOT, f'android/app/src/main/res/mipmap-{name}/ic_launcher.png')
    if os.path.isdir(os.path.dirname(p)):
        logo(px).save(p)
ico = logo(256)
ico.save(os.path.join(ROOT, 'windows/runner/resources/app_icon.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('ikonlar üretildi')
