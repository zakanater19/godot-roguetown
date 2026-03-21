# ================================================
# SINGLE-ITEM CLOTHING GENERATOR — FINAL FIX
# ================================================

import json
import re
import shutil
from pathlib import Path

# ================================================
# ================== CONFIG =====================
# ================================================

SOURCE_FOLDER = r"C:\Users\AHA\Desktop\scrapeme"
PNG_FILENAME = "plate.png"

# Available slots: head, armor, clothing, trousers, feet
SLOT = "armor" 

DESCRIPTION = "full plate armor"
ITEM_TYPE_OVERRIDE = None
REGION_X = 0

# ================================================
# ============== NO EDIT BELOW HERE =============
# ================================================

PROJECT_ROOT = Path(__file__).parent
CLOTHING_DIR = PROJECT_ROOT / "clothing"
OFFSETS_PATH = CLOTHING_DIR / "clothing_offsets.json"
PLAYER_GD_PATH = PROJECT_ROOT / "player.gd"
HUD_GD_PATH = PROJECT_ROOT / "HUD.gd"
HAND_EDITOR_PATH = PROJECT_ROOT / "addons" / "pixel_hand_editor" / "hand_editor_panel.gd"
TEMPLATE_GD = CLOTHING_DIR / "leatherboots.gd"


def to_pascal_case(filename_stem: str) -> str:
    clean = re.sub(r"^(shirts?|shirt)_?", "", filename_stem, flags=re.IGNORECASE)
    clean = re.sub(r"[^a-zA-Z0-9]", "_", clean)
    parts = [word for word in clean.split("_") if word]
    return "".join(word.capitalize() for word in parts)


def add_to_dict_in_file(filepath, dict_name, key, value, is_quote_val=True):
    if not filepath.exists():
        print(f"❌ File not found: {filepath}")
        return
    content = filepath.read_text(encoding="utf-8")
    # Improved regex to be less strict about whitespace and type hints
    pattern = r'(const\s+' + dict_name + r'\s*(?::\s*[a-zA-Z]+)?\s*=\s*\{)'
    match = re.search(pattern, content, re.IGNORECASE)
    
    if match:
        # Find the closing brace of the dictionary
        start_index = match.end()
        # Find the closing brace at the end of the dictionary block
        end_brace_index = content.find("}", start_index)
        
        if end_brace_index != -1:
            dict_content = content[start_index:end_brace_index]
            
            if f'"{key}"' not in dict_content:
                val_str = f'"{value}"' if is_quote_val else value
                new_entry = f'\n\t"{key}": {val_str},'
                updated_content = content[:end_brace_index] + new_entry + "\n" + content[end_brace_index:]
                filepath.write_text(updated_content, encoding="utf-8")
                print(f"✅ Registered {key} in {dict_name} ({filepath.name})")
            else:
                print(f"ℹ️ {key} already exists in {dict_name} ({filepath.name})")
    else:
        print(f"❌ Could not find dictionary definition for {dict_name} in {filepath.name}")


# ====================== RUN ======================

print("🚀 FINAL clothing generator (Robust version)\n")

source_png = Path(SOURCE_FOLDER) / PNG_FILENAME
if not source_png.exists():
    print(f"❌ PNG not found: {source_png}")
    exit()

stem = source_png.stem
item_type = ITEM_TYPE_OVERRIDE if ITEM_TYPE_OVERRIDE else to_pascal_case(stem)
node_name = item_type
gd_name = f"{stem}.gd"
tscn_name = f"{stem}.tscn"
target_png = CLOTHING_DIR / f"{stem}.png"

# Clean old files
for f in [gd_name, tscn_name, f"{stem}.png"]:
    p = CLOTHING_DIR / f
    if p.exists():
        p.unlink()

shutil.copy2(source_png, target_png)
print(f"✅ Copied {PNG_FILENAME}")

# .gd script
gd_text = TEMPLATE_GD.read_text(encoding="utf-8")
gd_text = re.sub(r'var slot: String = ".*?"', f'var slot: String = "{SLOT}"', gd_text)
gd_text = re.sub(r'var item_type: String = ".*?"', f'var item_type: String = "{item_type}"', gd_text)
gd_text = re.sub(r'func get_description\(\) -> String:\s*return ".*?"', 
                 f'func get_description() -> String:\n\treturn "{DESCRIPTION}"', 
                 gd_text, flags=re.DOTALL)
(CLOTHING_DIR / gd_name).write_text(gd_text, encoding="utf-8")
print(f"✅ Script: {gd_name}")

# .tscn
tscn_content = f'''[gd_scene format=4]
[ext_resource type="Script" path="res://clothing/{stem}.gd" id="1_{stem}"]
[ext_resource type="Texture2D" path="res://clothing/{stem}.png" id="2_{stem}"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_1"]
size = Vector2(28, 14)

[node name="{node_name}" type="Area2D"]
z_index = 5
script = ExtResource("1_{stem}")

[node name="Sprite2D" type="Sprite2D" parent="."]
scale = Vector2(1.0, 1.0)
texture = ExtResource("2_{stem}")
region_enabled = true
region_rect = Rect2({REGION_X}, 0, 32, 32)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_1")
'''

(CLOTHING_DIR / tscn_name).write_text(tscn_content, encoding="utf-8")
print(f"✅ Scene: {tscn_name}")

# offsets JSON
offsets = json.loads(OFFSETS_PATH.read_text(encoding="utf-8")) if OFFSETS_PATH.exists() else {}
if item_type not in offsets:
    offsets[item_type] = {
        "east": {"offset": [0.0, 0.0], "scale": 0.50},
        "north": {"offset": [0.0, 0.0], "scale": 0.50},
        "south": {"offset": [0.0, 0.0], "scale": 0.50},
        "west": {"offset": [0.0, 0.0], "scale": 0.50}
    }
    OFFSETS_PATH.write_text(json.dumps(offsets, indent=2), encoding="utf-8")
    print(f"✅ Offsets added to JSON")

# ================================================
# MANUAL INSTRUCTIONS
# ================================================

print("\n" + "="*60)
print("IMPORTANT:")
print("="*60)
print("1. If Godot is open, the files should import automatically.")
print("2. Delete your .godot folder and restart Godot if the items show up as broken dependencies.")
print("="*60)

# Patch other files
tscn_path = f"res://clothing/{stem}.tscn"
png_path = f"res://clothing/{stem}.png"

add_to_dict_in_file(HUD_GD_PATH, "CLOTHING_SCENES", item_type, tscn_path)
add_to_dict_in_file(HUD_GD_PATH, "CLOTHING_TEXTURES", item_type, png_path)
add_to_dict_in_file(HAND_EDITOR_PATH, "CLOTHING_ITEMS", item_type, png_path)

# Try to patch player.gd with improved patterns
if PLAYER_GD_PATH.exists():
    content = PLAYER_GD_PATH.read_text(encoding="utf-8")
    
    # Add to CLOTHING_SCENE_PATHS
    pattern1 = r'(const\s+CLOTHING_SCENE_PATHS\s*(?:\s*:\s*Dictionary)?\s*=\s*\{)'
    match1 = re.search(pattern1, content, re.DOTALL)
    if match1:
        # Find closing brace
        start_index = match1.end()
        end_brace_index = content.find("}", start_index)
        if end_brace_index != -1 and f'"{item_type}"' not in content[start_index:end_brace_index]:
            new_entry = f'\n\t"{item_type}": "{tscn_path}",'
            updated = content[:end_brace_index] + new_entry + "\n" + content[end_brace_index:]
            content = updated
            print(f"✅ Registered {item_type} in player.gd (CLOTHING_SCENE_PATHS)")
        
    # Add to CLOTHING_TEXTURES
    pattern2 = r'(const\s+CLOTHING_TEXTURES\s*(?:\s*:\s*Dictionary)?\s*=\s*\{)'
    match2 = re.search(pattern2, content, re.DOTALL)
    if match2:
        start_index = match2.end()
        end_brace_index = content.find("}", start_index)
        if end_brace_index != -1 and f'"{item_type}"' not in content[start_index:end_brace_index]:
            new_entry = f'\n\t"{item_type}": "{png_path}",'
            updated = content[:end_brace_index] + new_entry + "\n" + content[end_brace_index:]
            content = updated
            print(f"✅ Registered {item_type} in player.gd (CLOTHING_TEXTURES)")
    
    # Patch _setup_clothing_sprites
    setup_pattern = r'(func _setup_clothing_sprites\(\) -> void:\s*for spec in \[\[.*?\]\]):'
    setup_match = re.search(setup_pattern, content, re.DOTALL)
    if setup_match:
        old_text = setup_match.group(0)
        if '["ClothingSprite"]' not in old_text:
            array_match = re.search(r'for spec in \[(.*?)\]:', old_text, re.DOTALL)
            if array_match:
                array_content = array_match.group(1).strip()
                if not array_content.endswith(','):
                    array_content += ','
                new_array = array_content + ' ["ClothingSprite"]'
                new_text = old_text.replace(array_match.group(1), new_array)
                content = content.replace(old_text, new_text)
                print("✅ Added ClothingSprite to sprite creation")
    
    PLAYER_GD_PATH.write_text(content, encoding="utf-8")

print("\n🎉 Script completed! Item fully injected into game architecture.")

