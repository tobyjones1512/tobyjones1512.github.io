#!/usr/bin/env python3
"""Builds the App Store Connect images from raw simulator captures.

Raw captures live in AppStore/raw (landscape ones already rotated upright; see the -landscape / -mac
launch arguments in MyApp.swift). Output: AppStore/iPad, AppStore/Mac, AppStore/Header-5244x2950.png
and AppStore/SearchBanner-5244x2950.png.  Run: python3 Tools/make-store-shots.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "AppStore")
RAW = os.path.join(ROOT, "raw")
ICON = "/Users/tobyjones/On-Device Documents/GitHub/tobyjones1512.github.io/maestro-pro/assets/app-icon.png"
BODONI = "/System/Library/Fonts/Supplemental/Bodoni 72.ttc"
SANS = "/System/Library/Fonts/HelveticaNeue.ttc"
AMBER, CREAM, MUTED = (232, 178, 84), (247, 238, 222), (190, 170, 142)
WALNUT_TOP, WALNUT_BOT = (58, 40, 29), (24, 16, 12)


def font(path, size, index=0):
    return ImageFont.truetype(path, size, index=index)


def background(w, h):
    """Dark walnut gradient with a soft amber glow and a vignette."""
    col = Image.linear_gradient("L").resize((w, h))
    bg = Image.composite(Image.new("RGB", (w, h), WALNUT_BOT), Image.new("RGB", (w, h), WALNUT_TOP), col)
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((w * 0.15, -h * 0.35, w * 0.85, h * 0.45), fill=(44, 28, 13))
    glow = glow.filter(ImageFilter.GaussianBlur(w // 8))
    from PIL import ImageChops
    return ImageChops.add(bg, glow)


def rounded(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, *im.size), r, fill=255)
    out = im.convert("RGBA")
    out.putalpha(m)
    return out


def device(shot, width, bezel, radius, mac=False):
    """Screenshot in a dark bezel (iPad) or a window with traffic lights (Mac), with a drop shadow."""
    h = round(width * shot.height / shot.width)
    shot = shot.resize((width, h), Image.LANCZOS)
    bar = round(width * 0.028) if mac else 0
    b = 0 if mac else bezel
    W, H = width + 2 * b, h + 2 * b + bar
    body = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((0, 0, W - 1, H - 1), radius, fill=(40, 30, 24, 255) if mac else (12, 10, 9, 255), outline=(96, 84, 72, 255), width=max(3, W // 600))
    inner = rounded(shot, radius // 2 if not mac else 10) if not mac else shot.convert("RGBA")
    if mac:
        body.paste(inner, (0, bar))
        for i, c in enumerate(((255, 95, 87), (254, 188, 46), (40, 200, 64))):
            r = bar // 5
            cx, cy = bar // 2 + i * round(r * 3.2) + r, bar // 2
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=c + (255,))
        m = Image.new("L", (W, H), 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, W - 1, H - 1), radius, fill=255)
        body.putalpha(m)
    else:
        body.paste(inner, (b, b), inner)
    pad = 120
    sh = Image.new("RGBA", (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad + 40, pad + W, pad + H + 40), radius, fill=(0, 0, 0, 190))
    sh = sh.filter(ImageFilter.GaussianBlur(50))
    sh.alpha_composite(body, (pad, pad))
    return sh, pad


def put(canvas, dev, x, y):
    im, pad = dev
    canvas.alpha_composite(im, (x - pad, y - pad))


def raw(name, crop=None):
    im = Image.open(os.path.join(RAW, name + ".png")).convert("RGB")
    return im.crop(crop) if crop else im


# Landscape captures carry the status bar down the right edge; the Mac ones sit in a 1720px band.
def land(name):
    return raw(name, (0, 0, 2672, 2064))


def mac(name):
    im = raw(name, (0, 172, 2680, 1892))
    s = 2880 / im.width
    im = im.resize((2880, round(im.height * s)), Image.LANCZOS)
    top = (im.height - 1800) // 2
    return im.crop((0, top, 2880, top + 1800))


def port(name):
    return raw(name, (0, 0, 2064, 2752))


def wrap(draw, text, fnt, maxw):
    lines, cur = [], ""
    for w in text.split():
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=fnt) <= maxw or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w
    return lines + [cur]


def slide(size, shot, title, sub, kind, is_mac=False):
    W, H = size
    c = background(W, H).convert("RGBA")
    d = ImageDraw.Draw(c)
    ft, fs = font(BODONI, round(W * 0.044), 1), font(SANS, round(W * 0.0195))
    if kind == "top":
        zone = H * 0.045 + ft.size * 1.35 + fs.size * 1.9
        avail = H - zone - H * 0.045 - (W * 0.03 if is_mac else 0)
        dw = min(round(W * 0.86), round((avail - (0 if is_mac else 2 * W * 0.011)) * shot.width / shot.height))
        dev = device(shot, dw, round(W * 0.011), round(W * 0.03), is_mac)
        tw = d.textlength(title, font=ft)
        d.text(((W - tw) / 2, H * 0.045), title, font=ft, fill=CREAM)
        sw = d.textlength(sub, font=fs)
        d.text(((W - sw) / 2, H * 0.045 + ft.size * 1.35), sub, font=fs, fill=AMBER)
        put(c, dev, (W - dev[0].width + 2 * dev[1]) // 2, H - (dev[0].height - 2 * dev[1]) - round(H * 0.04))
    else:  # portrait device on the right, words on the left
        dh = round(H * 0.9)
        dev = device(shot.resize((round(dh * shot.width / shot.height), dh)), round(dh * shot.width / shot.height), round(W * 0.011), round(W * 0.03))
        x = W - (dev[0].width - 2 * dev[1]) - round(W * 0.07)
        put(c, dev, x, (H - (dev[0].height - 2 * dev[1])) // 2)
        maxw = x - round(W * 0.12)
        y = H * 0.30
        for ln in wrap(d, title, ft, maxw):
            d.text((W * 0.07, y), ln, font=ft, fill=CREAM)
            y += ft.size * 1.15
        y += ft.size * 0.25
        for ln in wrap(d, sub, fs, maxw):
            d.text((W * 0.07, y), ln, font=fs, fill=AMBER)
            y += fs.size * 1.4
    return c.convert("RGB")


def banner(kind):
    W, H = 5244, 2950
    c = background(W, H).convert("RGBA")
    d = ImageDraw.Draw(c)
    icon = Image.open(ICON).convert("RGBA")
    isz = 520 if kind == "header" else 440
    ic = rounded(icon.resize((isz, isz), Image.LANCZOS), isz // 5)
    x0 = 330
    c.alpha_composite(ic, (x0, 760 if kind == "header" else 880))
    ft = font(BODONI, 330 if kind == "header" else 300, 1)
    y = 760 if kind == "header" else 880
    d.text((x0 + isz + 90, y - 20), "Maestro Pro", font=ft, fill=CREAM)
    tag = "Sheet music that plays along." if kind == "header" else "Read it. Hear it. Play it."
    d.text((x0 + isz + 98, y + 360), tag, font=font(SANS, 128), fill=AMBER)
    for i, line in enumerate(["Scores, lyrics and backing tracks", "Loop, slow down and change key", "For iPad and Mac"]):
        d.text((x0 + 8, 1620 + i * 130), line, font=font(SANS, 84), fill=MUTED)
    sh = {"header": [("nocturne", 1900, 330), ("home", 1700, 1500)], "search": [("practise", 2560, 620)]}[kind]
    for n, w, y2 in sh:
        dev = device(land(n), w, 38, 100)
        put(c, dev, W - (dev[0].width - 2 * dev[1]) - (250 if n != "home" else 600), y2)
    if kind == "header":  # fan the two devices: library lower-left of the playing view
        pass
    return c.convert("RGB")


def main():
    os.makedirs(os.path.join(ROOT, "iPad"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "Mac"), exist_ok=True)
    ipad = [
        ("1-play", land("nocturne"), "Every note lights as it sounds", "Follow the music on the page, in time.", "top"),
        ("2-library", land("home"), "Your whole library, one tap away", "Scores, lyrics, scales and a tuner.", "top"),
        ("3-lyrics", land("lyrics"), "Lyrics that move with the music", "Sing along with the line that is current.", "top"),
        ("4-practise", land("practise"), "Practise at your own pace", "Slow down, loop a bar, change key.", "top"),
        ("5-edit", port("edit"), "Write and edit your own scores", "Notes, rests, marks, dynamics and bars.", "side"),
        ("6-search", port("search"), "Search for scores online", "Free scores from classical to jazz.", "side"),
    ]
    for n, shot, t, s, k in ipad:
        slide((2732, 2048), shot, t, s, k).save(os.path.join(ROOT, "iPad", n + ".png"), optimize=True)
    macs = [
        ("1-play", mac("mnoc"), "Every note lights as it sounds", "Follow the music on the page, in time."),
        ("2-library", mac("mhome"), "Your whole library, one click away", "Scores, lyrics, scales and a tuner."),
        ("3-lyrics", mac("mlyr"), "Lyrics that move with the music", "Sing along with the line that is current."),
        ("4-practise", mac("mpractise"), "Practise at your own pace", "Slow down, loop a bar, change key."),
    ]
    for n, shot, t, s in macs:
        slide((2880, 1800), shot, t, s, "top", True).save(os.path.join(ROOT, "Mac", n + ".png"), optimize=True)
    banner("header").save(os.path.join(ROOT, "Header-5244x2950.png"), optimize=True)
    banner("search").save(os.path.join(ROOT, "SearchBanner-5244x2950.png"), optimize=True)


if __name__ == "__main__":
    main()
