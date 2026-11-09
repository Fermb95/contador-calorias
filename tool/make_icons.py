"""Genera el icono de la app y el icono de notificación."""
import math, pathlib
from PIL import Image, ImageDraw

root = pathlib.Path(__file__).resolve().parent.parent
res = root / 'android/app/src/main/res'

def icon(size):
    S = 1024
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # fondo degradado verde redondeado
    bg = Image.new('RGBA', (S, S))
    bd = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / S
        c = (int(46 + (102 - 46) * t), int(125 + (187 - 125) * t), int(50 + (106 - 50) * t), 255)
        bd.line([(0, y), (S, y)], fill=c)
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=230, fill=255)
    img.paste(bg, (0, 0), mask)
    # anillo de progreso
    cx, cy, r, w = S / 2, S / 2, 330, 92
    box = [cx - r, cy - r, cx + r, cy + r]
    d.arc(box, 0, 360, fill=(128, 190, 132, 255), width=w)
    d.arc(box, -90, 200, fill=(255, 255, 255, 255), width=w)
    # extremo redondeado
    for ang in (-90, 200):
        a = math.radians(ang)
        px, py = cx + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)
        d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=(255, 255, 255, 255))
    # hoja / gota central
    d.ellipse([cx - 95, cy - 95, cx + 95, cy + 95], fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)

for folder, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    p = res / f'mipmap-{folder}'
    p.mkdir(parents=True, exist_ok=True)
    icon(size).save(p / 'ic_launcher.png')
icon(512).save(root / 'tool/icon-512.png')

# icono de notificación: blanco sobre transparente
S = 96
n = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(n)
d.arc([10, 10, 86, 86], -90, 200, fill=(255, 255, 255, 255), width=14)
d.ellipse([36, 36, 60, 60], fill=(255, 255, 255, 255))
(res / 'drawable').mkdir(parents=True, exist_ok=True)
n.save(res / 'drawable/ic_stat_notify.png')
print('ok')
