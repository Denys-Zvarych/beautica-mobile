#!/usr/bin/env python3
"""
Generate splash_logo.png (1024×1024) and splash_logo_android12.png (1152×1152)
for the Beautica VelvetTouch design system.

Design spec: compact 78×78dp neumorphic "B" pillow centered on transparent
background. flutter_native_splash sets the #E6DDD0 bg separately.

Run from the beautica-mobile/ directory:
    python3 scripts/generate_splash_logo.py
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

FONT_PATH = "assets/fonts/Comfortaa-Bold.ttf"
OUT_STD   = "assets/branding/splash_logo.png"
OUT_A12   = "assets/branding/splash_logo_android12.png"


def draw_blurred_shadow(canvas: Image.Image, rect, radius, fill_rgb, alpha, blur):
    """Composit a gaussian-blurred rounded-rect onto canvas (RGBA)."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw  = ImageDraw.Draw(layer)
    draw.rounded_rectangle(rect, radius=radius, fill=(*fill_rgb, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(radius=blur))
    canvas.alpha_composite(layer)


def generate_std(font_path: str, out_path: str) -> None:
    """
    1024×1024 px source image.
    1dp = 4px  (source 1024 → mdpi 256 at ×0.25 = ×1/4).

    Tile: 78dp × 4 = 312px.  Centered in 1024 → top-left (356, 356).
    """
    SIZE = 1024
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # ── Tile geometry ────────────────────────────────────────────────────────
    tx, ty = 356, 356
    tw, th = 312, 312
    r = 96          # 24dp × 4

    # ── Shadows ───────────────────────────────────────────────────────────────
    # Dark shadow: +20px offset, blur 20, color #C0AF98 α200
    draw_blurred_shadow(
        canvas,
        [tx + 20, ty + 20, tx + tw + 20, ty + th + 20],
        radius=r,
        fill_rgb=(0xC0, 0xAF, 0x98),
        alpha=200,
        blur=20,
    )
    # Light shadow: -20px offset, blur 20, color #FFFBF4 α210
    draw_blurred_shadow(
        canvas,
        [tx - 20, ty - 20, tx + tw - 20, ty + th - 20],
        radius=r,
        fill_rgb=(0xFF, 0xFB, 0xF4),
        alpha=210,
        blur=20,
    )

    # ── Tile fill ─────────────────────────────────────────────────────────────
    tile_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tile_draw  = ImageDraw.Draw(tile_layer)
    tile_draw.rounded_rectangle(
        [tx, ty, tx + tw, ty + th],
        radius=r,
        fill=(0xE6, 0xDD, 0xD0, 255),
    )
    canvas.alpha_composite(tile_layer)

    # ── "B" glyph ─────────────────────────────────────────────────────────────
    font      = ImageFont.truetype(font_path, 144)   # 36dp × 4 = 144px
    text_draw = ImageDraw.Draw(canvas)
    bbox      = font.getbbox("B")
    text_w    = bbox[2] - bbox[0]
    text_h    = bbox[3] - bbox[1]
    text_x    = tx + (tw - text_w) // 2 - bbox[0]
    text_y    = ty + (th - text_h) // 2 - bbox[1]
    text_draw.text((text_x, text_y), "B", font=font, fill=(0xC4, 0xA9, 0x88, 255))

    canvas.save(out_path)
    print(f"[OK] {out_path}  ({SIZE}×{SIZE})")


def generate_android12(font_path: str, out_path: str) -> None:
    """
    1152×1152 px Android 12 splash icon.

    Android 12 SplashScreen API shrinks the adaptive icon to 1/3 of the screen,
    with a 1/3 safe-zone margin. To keep the neumorphic tile visually compact:

      Safe zone:  768×768  centred in 1152  → margin 192px each side.
      Tile:       384×384  centred in 1152  → top-left at (576-192, 576-192) = (384, 384).
      Scale:      1dp ≈ 5px  (384 / 78 ≈ 4.9 → rounded to 5).
      Radius:     24dp × 5 = 120px
      Font:       36dp × 5 = 180px
      Shadow offsets: ±25px, blur 60px.
    """
    SIZE = 1152
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # ── Tile geometry ────────────────────────────────────────────────────────
    tw, th = 384, 384
    cx, cy = SIZE // 2, SIZE // 2
    tx, ty = cx - tw // 2, cy - th // 2   # (384, 384)
    r      = 120    # 24dp × 5

    # ── Shadows ───────────────────────────────────────────────────────────────
    draw_blurred_shadow(
        canvas,
        [tx + 25, ty + 25, tx + tw + 25, ty + th + 25],
        radius=r,
        fill_rgb=(0xC0, 0xAF, 0x98),
        alpha=200,
        blur=16,
    )
    draw_blurred_shadow(
        canvas,
        [tx - 25, ty - 25, tx + tw - 25, ty + th - 25],
        radius=r,
        fill_rgb=(0xFF, 0xFB, 0xF4),
        alpha=210,
        blur=16,
    )

    # ── Tile fill ─────────────────────────────────────────────────────────────
    tile_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tile_draw  = ImageDraw.Draw(tile_layer)
    tile_draw.rounded_rectangle(
        [tx, ty, tx + tw, ty + th],
        radius=r,
        fill=(0xE6, 0xDD, 0xD0, 255),
    )
    canvas.alpha_composite(tile_layer)

    # ── "B" glyph ─────────────────────────────────────────────────────────────
    font      = ImageFont.truetype(font_path, 180)   # 36dp × 5 = 180px
    text_draw = ImageDraw.Draw(canvas)
    bbox      = font.getbbox("B")
    text_w    = bbox[2] - bbox[0]
    text_h    = bbox[3] - bbox[1]
    text_x    = tx + (tw - text_w) // 2 - bbox[0]
    text_y    = ty + (th - text_h) // 2 - bbox[1]
    text_draw.text((text_x, text_y), "B", font=font, fill=(0xC4, 0xA9, 0x88, 255))

    canvas.save(out_path)
    print(f"[OK] {out_path}  ({SIZE}×{SIZE})")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    print(f"Working dir: {os.getcwd()}")
    assert os.path.exists(FONT_PATH), f"Font not found: {FONT_PATH}"
    generate_std(FONT_PATH, OUT_STD)
    generate_android12(FONT_PATH, OUT_A12)
    print("Done.")
