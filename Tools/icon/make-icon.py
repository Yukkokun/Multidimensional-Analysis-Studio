#!/usr/bin/env python3
"""
生成 MAT/MA Studio 的应用图标（1024 主图 + macOS iconset + icns + Xcode 资源）。

图案：一块渐变方的「多维轮廓」——五条竖轴 + 一条白色折线（文本的五个维度得分），
背后两条更淡的虚线代表 Biber 的参考文本类型。和软件里那张平行坐标图是同一个意象。

用法：python3 Tools/icon/make-icon.py
"""
import os, math
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
S = 2048                 # 超采样画布
OUT = 1024               # 最终主图
PAD = 0                  # 图标自带圆角，不留白

C_TOP = (108, 92, 231)       # #6C5CE7 靛紫
C_BOT = (47, 128, 237)       # #2F80ED 蓝
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        for_x = y / (size - 1)
        d.line([(0, y), (size, y)], fill=lerp(C_TOP, C_BOT, for_x))
    # 斜向再叠一层，避免纯竖直渐变太死板
    overlay = Image.new("L", (size, size), 0)
    od = ImageDraw.Draw(overlay)
    for i in range(size):
        od.line([(0, i), (i, 0)], fill=int(18 * (1 - i / size)))
    img = Image.composite(Image.new("RGB", (size, size), (255, 255, 255)), img, overlay)
    return img


def squircle_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def dashed_line(d, pts, fill, width, dash=34, gap=24):
    """折线虚线：按长度切段"""
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        length = math.hypot(x2 - x1, y2 - y1)
        if length == 0:
            continue
        ux, uy = (x2 - x1) / length, (y2 - y1) / length
        t = 0
        while t < length:
            e = min(t + dash, length)
            d.line([(x1 + ux * t, y1 + uy * t), (x1 + ux * e, y1 + uy * e)],
                   fill=fill, width=width)
            t = e + gap


def build():
    bg = gradient(S)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = squircle_mask(S, int(S * 0.226))
    canvas.paste(bg, (0, 0), mask)

    d = ImageDraw.Draw(canvas, "RGBA")

    # 顶部高光 + 底部压暗，做出一点点体积
    hi = Image.new("L", (S, S), 0)
    hd = ImageDraw.Draw(hi)
    hd.ellipse([-S * 0.35, -S * 0.55, S * 0.95, S * 0.35], fill=70)
    hi = hi.filter(ImageFilter.GaussianBlur(S * 0.10))
    canvas.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (0, 0), Image.composite(hi, Image.new("L", (S, S), 0), mask))

    # 5 条竖轴
    xs = [int(S * f) for f in (0.235, 0.365, 0.5, 0.635, 0.765)]
    top, bot = int(S * 0.285), int(S * 0.735)
    for x in xs:
        d.line([(x, top), (x, bot)], fill=(255, 255, 255, 40), width=int(S * 0.0042))

    # 两条参考轮廓（虚线，很淡）
    ref1 = [0.40, 0.62, 0.50, 0.66, 0.44]
    pts = [(x, int(S * v)) for x, v in zip(xs, ref1)]
    dashed_line(d, pts, (255, 255, 255, 54), int(S * 0.0085))

    # 主轮廓
    vals = [0.585, 0.375, 0.505, 0.335, 0.47]
    pts = [(x, int(S * v)) for x, v in zip(xs, vals)]

    # 阴影
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.line(pts, fill=(20, 30, 80, 120), width=int(S * 0.032), joint="curve")
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.018))
    canvas = Image.alpha_composite(canvas, shadow)

    d = ImageDraw.Draw(canvas, "RGBA")
    d.line(pts, fill=WHITE, width=int(S * 0.030), joint="curve")
    for x, y in pts:
        r = S * 0.029
        d.ellipse([x - r, y - r, x + r, y + r], fill=WHITE)

    # 内描边
    d.rounded_rectangle([S * 0.005, S * 0.005, S - S * 0.005, S - S * 0.005],
                        radius=int(S * 0.2215), outline=(255, 255, 255, 34), width=int(S * 0.0032))

    return canvas.resize((OUT, OUT), Image.LANCZOS)


def main():
    icon = build()
    outdir = os.path.join(ROOT, "Tools/icon")
    master = os.path.join(outdir, "icon_1024.png")
    icon.save(master)

    # macOS iconset
    iconset = os.path.join(outdir, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
        if size <= 512:
            icon.resize((size * 2, size * 2), Image.LANCZOS).save(
                os.path.join(iconset, f"icon_{size}x{size}@2x.png"))

    # Xcode appiconset
    xc = os.path.join(ROOT,
        "Multidimensional Analysis MacTag/Multidimensional Analysis MacTag/Assets.xcassets/AppIcon.appiconset")
    os.makedirs(xc, exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(xc, f"icon_{size}.png"))
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(xc, f"icon_{size}@2x.png"))
    icon.save(os.path.join(xc, "icon_1024.png"))

    import json
    entries = []
    for size in (16, 32, 128, 256, 512):
        entries.append({"idiom": "mac", "size": f"{size}x{size}", "scale": "1x", "filename": f"icon_{size}.png"})
        entries.append({"idiom": "mac", "size": f"{size}x{size}", "scale": "2x", "filename": f"icon_{size}@2x.png"})
    json.dump({"images": entries, "info": {"author": "xcode", "version": 1}},
              open(os.path.join(xc, "Contents.json"), "w"), indent=2)

    print("icon:", master)
    print("iconset:", iconset)
    print("xcassets:", xc)


if __name__ == "__main__":
    main()
