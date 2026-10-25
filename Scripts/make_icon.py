"""Generate the project's own opaque 1024px AppIcon without external assets."""
from pathlib import Path
import json
import math
import struct
import zlib

root = Path(__file__).resolve().parents[1]/'Kanke/Assets.xcassets'
icon = root/'AppIcon.appiconset'
icon.mkdir(parents=True, exist_ok=True)
size = 1024
rows = bytearray()
for y in range(size):
    rows.append(0)
    for x in range(size):
        glow = max(0, 1-math.hypot(x-400, y-330)/850)
        r, g, b = int(18+36*glow), int(23+40*glow), int(43+90*glow)
        distance = math.hypot(x-512, y-512)
        if 300 < distance < 321:
            r, g, b = 160, 174, 255
        # A simple rounded-screen/play mark, drawn from native geometry.
        if 410 <= x <= 680 and abs(y-512) < (680-x)*0.67:
            r, g, b = 239, 242, 255
        rows.extend((r, g, b))
def chunk(kind, data):
    return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data)&0xffffffff)
png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))+chunk(b'IDAT', zlib.compress(rows, 9))+chunk(b'IEND', b'')
(icon/'AppIcon.png').write_bytes(png)
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}], 'info':{'author':'xcode','version':1}}, indent=2), encoding='utf-8')
(root/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}', encoding='utf-8')
accent = root/'AccentColor.colorset'
accent.mkdir(exist_ok=True)
(accent/'Contents.json').write_text(json.dumps({'colors':[{'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.600','green':'0.660','blue':'1.000','alpha':'1.000'}}}], 'info':{'author':'xcode','version':1}}, indent=2), encoding='utf-8')
print('Created opaque AppIcon:', len(png), 'bytes')
