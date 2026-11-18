# -*- coding: utf-8 -*-
"""mdcX Boost 配置器图标：深色底 + 金色闪电（纯 PIL）"""
import os, sys
from PIL import Image, ImageDraw

GOLD = (250, 200, 51, 255)
BG_TOP = (28, 26, 46, 255)
BG_BOT = (12, 10, 22, 255)

def make(size):
    img = Image.new("RGBA", (size, size), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # 渐变背景
    for y in range(size):
        t = y / size
        c = tuple(int(BG_TOP[i]*(1-t)+BG_BOT[i]*t) for i in range(4))
        d.line([(0,y),(size,y)], fill=c)
    # 闪电多边形（居中）
    cx, cy = size/2, size/2
    s = size/100.0
    pts = [
        (cx+10*s, cy-34*s), (cx-20*s, cy+4*s), (cx-2*s, cy+4*s),
        (cx-12*s, cy+34*s), (cx+22*s, cy-8*s), (cx+2*s, cy-8*s),
    ]
    d.polygon(pts, fill=GOLD)
    return img

def main(outdir):
    sizes = {
        "AppIcon60x60@2x.png": 120,
        "AppIcon60x60@3x.png": 180,
        "AppIcon76x76@2x~ipad.png": 152,
        "AppIcon83.5x83.5@2x~ipad.png": 167,
        "AppIcon.png": 1024,
    }
    for name, sz in sizes.items():
        make(sz).save(os.path.join(outdir, name))
    print("icons:", ", ".join(sizes.keys()))
    return list(sizes.keys())

if __name__ == "__main__":
    main(sys.argv[1])
