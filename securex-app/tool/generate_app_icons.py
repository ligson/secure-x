#!/usr/bin/env python3
"""Generate Secure X application icons for Flutter platforms."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
BRAND_DIR = ROOT / "assets" / "brand"


def rounded_rectangle_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=radius,
        fill=255,
    )
    return mask


def interpolate(start: tuple[int, int, int], end: tuple[int, int, int], t: float):
    return tuple(round(start[index] + (end[index] - start[index]) * t) for index in range(3))


def make_icon(size: int = 1024, rounded: bool = False) -> Image.Image:
    scale = 4
    canvas_size = size * scale
    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    top = (9, 47, 62)
    bottom = (19, 116, 107)
    pixels = image.load()
    for y in range(canvas_size):
        t = y / max(canvas_size - 1, 1)
        color = interpolate(top, bottom, t)
        for x in range(canvas_size):
            pixels[x, y] = (*color, 255)

    draw = ImageDraw.Draw(image, "RGBA")
    s = canvas_size

    # Soft radial atmosphere so the icon does not feel flat at desktop sizes.
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow, "RGBA")
    glow_draw.ellipse(
        (int(s * -0.10), int(s * -0.16), int(s * 0.84), int(s * 0.78)),
        fill=(90, 220, 198, 72),
    )
    glow_draw.ellipse(
        (int(s * 0.22), int(s * 0.44), int(s * 1.12), int(s * 1.20)),
        fill=(3, 20, 32, 92),
    )
    image = Image.alpha_composite(image, glow.filter(ImageFilter.GaussianBlur(int(s * 0.05))))
    draw = ImageDraw.Draw(image, "RGBA")

    # Quiet grid lines hint at encrypted storage blocks.
    for offset in (0.24, 0.42, 0.60, 0.78):
        draw.line(
            (int(s * offset), int(s * 0.10), int(s * (offset - 0.18)), int(s * 0.92)),
            fill=(201, 247, 236, 18),
            width=max(1, int(s * 0.006)),
        )
    for offset in (0.24, 0.48, 0.72):
        draw.line(
            (int(s * 0.08), int(s * offset), int(s * 0.92), int(s * (offset + 0.05))),
            fill=(201, 247, 236, 16),
            width=max(1, int(s * 0.006)),
        )

    # Shield / vault body.
    shadow = [
        (int(s * 0.50), int(s * 0.145)),
        (int(s * 0.745), int(s * 0.245)),
        (int(s * 0.695), int(s * 0.690)),
        (int(s * 0.500), int(s * 0.850)),
        (int(s * 0.305), int(s * 0.690)),
        (int(s * 0.255), int(s * 0.245)),
    ]
    draw.polygon([(x, y + int(s * 0.030)) for x, y in shadow], fill=(0, 0, 0, 76))

    shield = shadow
    draw.polygon(shield, fill=(226, 255, 247, 246))
    inset = int(s * 0.030)
    inner = [
        (int(s * 0.50), int(s * 0.215)),
        (int(s * 0.665), int(s * 0.285)),
        (int(s * 0.632), int(s * 0.642)),
        (int(s * 0.500), int(s * 0.750)),
        (int(s * 0.368), int(s * 0.642)),
        (int(s * 0.335), int(s * 0.285)),
    ]
    draw.polygon(inner, fill=(13, 71, 82, 255))
    draw.line(shield + [shield[0]], fill=(246, 255, 252, 170), width=inset)

    # The X mark is intentionally bold so it survives launcher downscaling.
    x_width = int(s * 0.082)
    draw.line(
        (int(s * 0.385), int(s * 0.365), int(s * 0.615), int(s * 0.625)),
        fill=(239, 255, 250, 255),
        width=x_width,
    )
    draw.line(
        (int(s * 0.615), int(s * 0.365), int(s * 0.385), int(s * 0.625)),
        fill=(239, 255, 250, 255),
        width=x_width,
    )
    draw.line(
        (int(s * 0.395), int(s * 0.365), int(s * 0.615), int(s * 0.610)),
        fill=(50, 220, 186, 225),
        width=int(s * 0.030),
    )

    # Vault keyhole / secret center point.
    draw.ellipse(
        (int(s * 0.455), int(s * 0.455), int(s * 0.545), int(s * 0.545)),
        fill=(8, 45, 55, 255),
    )
    draw.ellipse(
        (int(s * 0.476), int(s * 0.476), int(s * 0.524), int(s * 0.524)),
        fill=(235, 255, 250, 255),
    )
    draw.rounded_rectangle(
        (int(s * 0.488), int(s * 0.514), int(s * 0.512), int(s * 0.600)),
        radius=int(s * 0.012),
        fill=(235, 255, 250, 255),
    )

    image = image.resize((size, size), Image.Resampling.LANCZOS)
    if rounded:
        rounded_icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        rounded_icon.alpha_composite(image)
        rounded_icon.putalpha(rounded_rectangle_mask(size, int(size * 0.215)))
        return rounded_icon
    return image.convert("RGBA")


def save_png(path: Path, size: int, rounded: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    make_icon(size, rounded=rounded).save(path)


def generate_linux() -> None:
    save_png(ROOT / "linux" / "runner" / "resources" / "app_icon.png", 256, rounded=True)


def main() -> None:
    BRAND_DIR.mkdir(parents=True, exist_ok=True)
    save_png(BRAND_DIR / "securex_app_icon.png", 1024, rounded=True)
    save_png(BRAND_DIR / "securex_app_icon_square.png", 1024, rounded=False)
    # Android, iOS, macOS and Windows launcher icons are generated by
    # flutter_launcher_icons from securex_app_icon_square.png.
    generate_linux()


if __name__ == "__main__":
    main()
