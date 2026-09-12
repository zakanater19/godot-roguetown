"""Import the character sprites used by the Godot prototype from a Roguetown DMI tree.

Run from the Godot project directory:
    python scripts/tools/import_roguetown_character_assets.py "../RogueTown-main-codebase for ref"

Pillow is only needed while importing. The generated PNG files have no runtime
dependency on this script or on the reference checkout.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = PROJECT_ROOT / "assets" / "characters"

HAIR_STATES = [
    "hair_skinhead",
    "hair_gelled",
    "hair_pirate",
    "hair_ponytail",
    "hair_business2",
    "hair_business",
    "hair_shavedmohawk",
    "hair_bedhead",
    "hair_bowlcut2",
    "hair_undercut",
    "hair_father",
    "hair_thinning",
    "hair_thinningrear",
    "hair_baldfade",
    "hair_forelock",
    "hair_rogue",
    "hair_tied",
    "hair_romantic",
    "hair_runt",
    "hair_son",
    "hair_bog",
    "fhair_shorthairg",
    "fhair_vlongfringe",
    "fhair_beehive",
    "fhair_barmaid",
    "fhair_longstraightponytail",
    "fhair_messy",
    "fhair_twintail",
    "fhair_doublebun",
    "fhair_bob",
    "fhair_amazon",
    "fhair_tressshoulder",
    "fhair_himecut2",
    "fhair_homely",
    "fhair_bob2",
    "fhair_pixie",
]

FACIAL_HAIR_STATES = [
    "facial_stubble",
    "facial_fullbeard",
    "facial_burns",
    "facial_pipe",
    "facial_knightly",
    "facial_5oclockmoustache",
    "facial_vandyke",
    "facial_muttonmus",
    "facial_moonshiner",
    "facial_longbeard",
    "facial_wise",
    "facial_dwarf",
    "facial_brokenman",
    "facial_chin",
    "facial_manly",
    "facial_viking",
]


@dataclass(frozen=True)
class DmiState:
    start: int
    directions: int
    frames: int


class Dmi:
    def __init__(self, path: Path) -> None:
        source = Image.open(path)
        self.image = source.convert("RGBA")
        description = source.info.get("Description", "")
        width_match = re.search(r"width = (\d+)", description)
        height_match = re.search(r"height = (\d+)", description)
        if width_match is None or height_match is None:
            raise ValueError(f"{path} has no DMI dimensions")
        self.width = int(width_match.group(1))
        self.height = int(height_match.group(1))
        self.columns = self.image.width // self.width
        self.states: dict[str, DmiState] = {}
        cursor = 0
        state_pattern = re.compile(
            r'state = "([^"]*)"\s+dirs = (\d+)\s+frames = (\d+)'
        )
        for name, direction_count, frame_count in state_pattern.findall(description):
            directions = int(direction_count)
            frames = int(frame_count)
            self.states[name] = DmiState(cursor, directions, frames)
            cursor += directions * frames

    def direction_strip(self, state_name: str) -> Image.Image:
        state = self.states.get(state_name)
        if state is None:
            raise KeyError(f"Missing DMI state: {state_name}")
        if state.directions != 4:
            raise ValueError(f"{state_name} has {state.directions} directions, expected 4")
        result = Image.new("RGBA", (self.width * 4, self.height))
        for direction in range(4):
            # The first animation frame for each BYOND direction is sufficient
            # for the currently non-animated Godot player renderer.
            tile_index = state.start + direction * state.frames
            x = tile_index % self.columns * self.width
            y = tile_index // self.columns * self.height
            result.paste(
                self.image.crop((x, y, x + self.width, y + self.height)),
                (direction * self.width, 0),
            )
        return result


def tint(source: Image.Image, html_color: str) -> Image.Image:
    rgb = tuple(int(html_color[index : index + 2], 16) for index in (1, 3, 5))
    color_layer = Image.new("RGBA", source.size, (*rgb, 255))
    tinted = ImageChops.multiply(source, color_layer)
    tinted.putalpha(source.getchannel("A"))
    return tinted


def composite_states(dmi: Dmi, state_names: tuple[str, ...]) -> Image.Image:
    if not state_names:
        raise ValueError("At least one DMI state is required")
    result = dmi.direction_strip(state_names[0])
    for overlay_state in state_names[1:]:
        if overlay_state in dmi.states:
            result = Image.alpha_composite(result, dmi.direction_strip(overlay_state))
    return result


def save_sheet(dmi: Dmi, states: list[str], destination: Path) -> None:
    sheet = Image.new("RGBA", (128, len(states) * 32))
    for row, state_name in enumerate(states):
        sheet.paste(dmi.direction_strip(state_name), (0, row * 32))
    sheet.save(destination)


def import_assets(reference_root: Path) -> None:
    icons = reference_root / "icons" / "roguetown"
    if not icons.is_dir():
        raise FileNotFoundError(f"No Roguetown icon tree found below {reference_root}")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

    female_body = Dmi(icons / "mob" / "bodies" / "f" / "fs.dmi")
    # The source body is greyscale because BYOND applies a skin tone at
    # runtime. Match the prototype's existing male base until skin-tone
    # customization is added as its own option.
    tint(female_body.direction_strip("fs"), "#ffddd1").save(
        OUTPUT_ROOT / "body_female.png"
    )

    save_sheet(Dmi(icons / "mob" / "hair.dmi"), HAIR_STATES, OUTPUT_ROOT / "hair_styles.png")
    save_sheet(
        Dmi(icons / "mob" / "facial.dmi"),
        FACIAL_HAIR_STATES,
        OUTPUT_ROOT / "facial_hair_styles.png",
    )

    clothing_root = icons / "clothing" / "onmob"
    mappings = {
        "undershirt_female.png": ("shirts.dmi", ("undershirt_f", "undershirt_f_boob"), ""),
        "blackshirt_female.png": ("shirts.dmi", ("undershirt_f", "undershirt_f_boob"), "#414143"),
        "apothshirt_female.png": ("shirts.dmi", ("undershirt_f", "undershirt_f_boob"), "#71824a"),
        "leathertrousers_female.png": ("pants.dmi", ("leathertrou_f",), ""),
        "leatherboots_female.png": ("feet.dmi", ("leatherboots_f",), ""),
        "chaingloves_female.png": ("gloves.dmi", ("cgloves_f",), ""),
        "ironchestplate_female.png": ("armor.dmi", ("ibreastplate_f", "ibreastplate_f_boob"), ""),
        "merchantrobe_female.png": ("armor.dmi", ("merrobe_f", "merrobe_f_boob"), ""),
        "plate_female.png": ("armor.dmi", ("coat_of_plates_f",), ""),
        # Roguetown splits cloaks into body, right and left pieces so each
        # direction can layer around the wearer. Godot renders the slot as one
        # sprite, therefore those pieces are flattened during import.
        "king_cloak_female.png": (
            "cloaks.dmi",
            ("lord_cloak_f", "r_lord_cloak_f", "l_lord_cloak_f"),
            "",
        ),
        "ironhelmet_female.png": ("head.dmi", ("helmet_f",), ""),
    }
    dmi_cache: dict[str, Dmi] = {}
    for destination_name, (dmi_name, state_names, color) in mappings.items():
        if dmi_name not in dmi_cache:
            dmi_cache[dmi_name] = Dmi(clothing_root / dmi_name)
        output = composite_states(dmi_cache[dmi_name], state_names)
        if color:
            output = tint(output, color)
        output.save(OUTPUT_ROOT / destination_name)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Pass the path to the Roguetown reference checkout")
    import_assets(Path(sys.argv[1]).resolve())
