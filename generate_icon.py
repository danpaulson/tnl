#!/usr/bin/env python3
"""Generate a tunnel-themed app icon and menu bar icon for TNL."""

from PIL import Image, ImageDraw
import os
import subprocess
import shutil

SIZE = 1024

def generate_app_icon():
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = SIZE // 2, SIZE // 2

    mask = Image.new('L', (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask)
    r = int(SIZE * 0.22)
    mask_draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=r, fill=255)

    bg_color = (18, 22, 36)
    draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=r, fill=bg_color)

    rings = [
        {"radius": 340, "color": (40, 70, 160), "thickness": 18, "glow": 50},
        {"radius": 210, "color": (0, 170, 200), "thickness": 14, "glow": 60},
        {"radius": 100, "color": (100, 230, 255), "thickness": 10, "glow": 70},
    ]

    for ring in rings:
        rad = ring["radius"]
        color = ring["color"]
        thick = ring["thickness"]

        for g in range(8, 0, -1):
            glow_alpha = int(ring["glow"] * (1 - g / 8) ** 0.5)
            glow_color = (*color, glow_alpha)
            bbox = [cx - rad - g * 2, cy - rad - g * 2, cx + rad + g * 2, cy + rad + g * 2]
            draw.ellipse(bbox, outline=glow_color, width=thick)

        bbox = [cx - rad, cy - rad, cx + rad, cy + rad]
        draw.ellipse(bbox, outline=(*color, 240), width=thick)

    for glow_r in range(50, 0, -1):
        alpha = int(200 * (1 - glow_r / 50) ** 1.8)
        draw.ellipse(
            [cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r],
            fill=(180, 245, 255, alpha)
        )

    result = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    result.paste(img, mask=mask)
    return result

def generate_menubar_icon(size=18):
    """Generate a crisp template image for the macOS menu bar — 3 clean circles."""
    s = size * 2  # @2x for retina
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = s // 2, s // 2

    # 3 clean concentric circles, thin crisp lines
    color = (0, 0, 0, 255)
    draw.ellipse([cx - 15, cy - 15, cx + 15, cy + 15], outline=color, width=1)
    draw.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], outline=color, width=1)
    draw.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], outline=color, width=1)

    return img, size

def create_icns(img, output_dir):
    iconset = os.path.join(output_dir, "icon.iconset")
    os.makedirs(iconset, exist_ok=True)

    sizes = [16, 32, 64, 128, 256, 512]
    for s in sizes:
        img.resize((s, s), Image.LANCZOS).save(os.path.join(iconset, f"icon_{s}x{s}.png"))
        s2 = s * 2
        if s2 <= 1024:
            img.resize((s2, s2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{s}x{s}@2x.png"))
    img.save(os.path.join(iconset, "icon_512x512@2x.png"))

    icns_path = os.path.join(output_dir, "icon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns_path], check=True)
    shutil.rmtree(iconset)
    return icns_path

if __name__ == "__main__":
    base = "/Users/dan/dev/tnl"

    app_icon = generate_app_icon()
    app_icon.save(os.path.join(base, "icon_preview.png"))
    create_icns(app_icon, base)

    menubar, menubar_size = generate_menubar_icon()
    menubar.save(os.path.join(base, "menubar_icon.png"))

    print(f"Done: icon_preview.png, icon.icns, menubar_icon.png ({menubar_size}pt)")
