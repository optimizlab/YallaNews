import os
from PIL import Image, ImageDraw

emblem_src = r"C:\Users\vPro\.gemini\antigravity-ide\brain\e2d07e9c-da1a-47d7-bcfb-e02374e28e98\yallanews_emblem_icon_1791988884495.jpg"
full_icon_src = r"C:\Users\vPro\.gemini\antigravity-ide\brain\e2d07e9c-da1a-47d7-bcfb-e02374e28e98\yallanews_base_icon_1791988859560.jpg"
banner_src = r"C:\Users\vPro\.gemini\antigravity-ide\brain\e2d07e9c-da1a-47d7-bcfb-e02374e28e98\playstore_arabic_banner_1791988710893.jpg"

base_dir = r"d:\FLUTTER_PROJECTS\YallaNews"
res_dir = os.path.join(base_dir, "android", "app", "src", "main", "res")
playstore_dir = os.path.join(base_dir, "playstore_assets")
assets_icon_dir = os.path.join(base_dir, "assets", "icon")

os.makedirs(playstore_dir, exist_ok=True)
os.makedirs(assets_icon_dir, exist_ok=True)

img_emblem = Image.open(emblem_src).convert("RGBA")
img_full = Image.open(full_icon_src).convert("RGBA")

# 1. Play Store 512x512 (Store icon and Flutter asset)
playstore_icon = img_emblem.resize((512, 512), Image.Resampling.LANCZOS)
playstore_icon.save(os.path.join(playstore_dir, "app_icon_512x512.png"), "PNG")
playstore_icon.save(os.path.join(assets_icon_dir, "app_icon_512.png"), "PNG")

playstore_icon_branded = img_full.resize((512, 512), Image.Resampling.LANCZOS)
playstore_icon_branded.save(os.path.join(playstore_dir, "app_icon_512x512_branded.png"), "PNG")

# 2. Play Store Feature Graphic 1024x500 (Arabic Banner)
banner_img = Image.open(banner_src).convert("RGB")
feature_graphic = banner_img.resize((1024, 500), Image.Resampling.LANCZOS)
feature_graphic.save(os.path.join(playstore_dir, "feature_graphic_1024x500.png"), "PNG")
feature_graphic.save(os.path.join(assets_icon_dir, "feature_graphic_1024x500.png"), "PNG")

# Density sizes for Android launcher mipmaps
densities = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Helper for circular crop
def make_circle_icon(image_square, size):
    resized = image_square.resize((size, size), Image.Resampling.LANCZOS)
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    
    round_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    round_img.paste(resized, (0, 0), mask=mask)
    return round_img

# Standard square & round mipmap icons
for folder, size in densities.items():
    target_folder = os.path.join(res_dir, folder)
    os.makedirs(target_folder, exist_ok=True)
    
    # Standard launcher icon
    std_icon = img_emblem.resize((size, size), Image.Resampling.LANCZOS)
    std_icon.save(os.path.join(target_folder, "ic_launcher.png"), "PNG")
    
    # Round launcher icon
    round_icon = make_circle_icon(img_emblem, size)
    round_icon.save(os.path.join(target_folder, "ic_launcher_round.png"), "PNG")

# 3. Adaptive Icon Foreground (432x432 with 288x288 safe zone)
adaptive_densities = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

for folder, size in adaptive_densities.items():
    target_folder = os.path.join(res_dir, folder)
    fg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    # Scale emblem to 72% so it resides cleanly within adaptive icon safe area
    inner_size = int(size * 0.72)
    inner_icon = img_emblem.resize((inner_size, inner_size), Image.Resampling.LANCZOS)
    offset = (size - inner_size) // 2
    fg.paste(inner_icon, (offset, offset), mask=inner_icon)
    fg.save(os.path.join(target_folder, "ic_launcher_foreground.png"), "PNG")

print("SUCCESS: Generated all Android Arabic launcher icons, adaptive icons, and Play Store graphics!")
