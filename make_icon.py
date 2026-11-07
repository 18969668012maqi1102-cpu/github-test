# -*- coding: utf-8 -*-
"""生成 iOS App 图标：蓝色渐变底 + 白色剪贴板 + 勾选清单"""
import os, math
from PIL import Image, ImageDraw

S = 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)

# ---------- 背景：斜向渐变 + 右上光晕 ----------
bg = Image.new("RGB", (S, S), (29, 58, 138))
px = bg.load()
c1 = (30, 64, 175)     # 深蓝（左上）
c2 = (59, 130, 246)    # 亮蓝（右下）
for y in range(S):
    for x in range(S):
        t = (x / S) * 0.55 + (y / S) * 0.45
        px[x, y] = (
            int(c1[0] + (c2[0] - c1[0]) * t),
            int(c1[1] + (c2[1] - c1[1]) * t),
            int(c1[2] + (c2[2] - c1[2]) * t),
        )

# 右上柔光
glow = Image.new("L", (S, S), 0)
gd = ImageDraw.Draw(glow)
gd.ellipse([S * 0.42, -S * 0.28, S * 1.30, S * 0.72], fill=70)
bg = Image.composite(Image.new("RGB", (S, S), (96, 165, 250)), bg, glow.filter(__import__("PIL.ImageFilter", fromlist=["ImageFilter"]).GaussianBlur(120)))

img = bg.convert("RGBA")
d = ImageDraw.Draw(img)

WHITE = (255, 255, 255, 255)
SOFT = (255, 255, 255, 150)

# ---------- 剪贴板主体 ----------
# 比例要点：内容占图标 ~80%，上下留白均衡，避开 iOS squircle 圆角裁切安全区
bx0, by0, bx1, by1 = 186, 158, 838, 896
r = 62
d.rounded_rectangle([bx0, by0, bx1, by1], radius=r, fill=(255, 255, 255, 238))

# 剪贴板顶部夹子
cx0, cy0, cx1, cy1 = 400, 96, 624, 238
d.rounded_rectangle([cx0, cy0, cx1, cy1], radius=46, fill=(255, 255, 255, 255))
d.rounded_rectangle([cx0 + 62, cy0 + 48, cx1 - 62, cy1 + 26], radius=28,
                    fill=(37, 99, 235, 255))

# ---------- 三行清单 ----------
def check(draw, cx, cy, size, color):
    """画一个勾（圆头）"""
    w = size * 0.23
    pts = [(cx - size * 0.44, cy + size * 0.02),
           (cx - size * 0.08, cy + size * 0.36),
           (cx + size * 0.48, cy - size * 0.38)]
    draw.line(pts, fill=color, width=int(w), joint="curve")
    for (px_, py_) in pts:
        draw.ellipse([px_ - w / 2, py_ - w / 2, px_ + w / 2, py_ + w / 2], fill=color)

rows = [
    (388, 388, 330, True),
    (568, 568, 278, False),
    (748, 748, 306, False),
]
line_h = 40
for cy, ly, lw, has_check in rows:
    if has_check:
        check(d, 312, cy, 104, (37, 99, 235, 255))
        d.rounded_rectangle([404, ly - line_h / 2, 404 + lw, ly + line_h / 2],
                            radius=line_h / 2, fill=(30, 64, 175, 215))
    else:
        # 空心勾选框
        d.ellipse([312 - 38, cy - 38, 312 + 38, cy + 38],
                  outline=(148, 163, 184, 255), width=14)
        d.rounded_rectangle([404, ly - line_h / 2, 404 + lw, ly + line_h / 2],
                            radius=line_h / 2, fill=(148, 163, 184, 195))

img.save(os.path.join(OUT, "icon-1024.png"))
print("已生成 1024x1024")

# ---------- 导出各尺寸 ----------
sizes = [
    ("icon-20@2x.png", 40), ("icon-20@3x.png", 60),
    ("icon-29@2x.png", 58), ("icon-29@3x.png", 87),
    ("icon-40@2x.png", 80), ("icon-40@3x.png", 120),
    ("icon-60@2x.png", 120), ("icon-60@3x.png", 180),
    ("icon-76@1x.png", 76), ("icon-76@2x.png", 152),
    ("icon-83.5@2x.png", 167),
]
for name, size in sizes:
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name))
    print("已生成", name, size)

print("完成：", OUT)
