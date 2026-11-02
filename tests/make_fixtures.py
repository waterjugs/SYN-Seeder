"""Builds the screenshot cases the AutoHotkey tests (tests/run.ahk) check the button finder on.

    pip install opencv-python-headless numpy
    python tests/make_fixtures.py build/fixtures

Each case is a screenshot from tests/screens, resized or padded to a screen
size the way a player would see it (or might, on a screen narrower than
16:9), then shrunk to the app's working copy (by
the whole factor round(height / 720), averaging f x f blocks), and saved as
an 8-bit gray PNG.
cases.json says what the app should see on each one.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

SCREENS = Path(__file__).resolve().parent / "screens"

# Screenshot -> the screen the app should report (None: in game, loading or a splash).
EXPECTED = {
    "warn": None,  # splash, handled by pressing space
    "menu": "menu_enlist",
    "browser": "browser_search",
    "search": "server_row",
    "hover": "server_row",
    "search_empty": "browser_refresh",  # edited copy of "search" with the row removed
    "select_force": "select_force",  # assembled from native-res zooms of the live screen
    "units": "switch_team",
    "create_unit": "create_unit",  # popup after +; assembled from native-res zooms
    # 2026-10-29 live rejoin (the game skips Select Force): brighter scenery
    # shows through the see-through CREATE UNIT button.
    "rejoin_units": "switch_team",
    "rejoin_create_unit": "create_unit",
    "roles_msg": "admin_yes",
    "roles": "roles_confirm",
    "roles_live": "roles_confirm",  # 2026-10-26 live run, half-res capture: other background behind "CONFIRM ROLE"
    "select_role": "roles_confirm",  # 2026-10-26 live run: SELECT A ROLE after joining someone else's squad
    "deploy": "deploy_button",
    "deploy_counting": None,  # after F: CANCEL DEPLOY counting down; another F would cancel it
    "ingame": None,
    "gamemenu": "game_menu_leave",
}
RESOLUTIONS = {"1080p": (1920, 1080), "720p": (1280, 720), "1440p": (2560, 1440)}
# Captured natively at 1920x1080 on 2026-10-27 (live run on game build v1.7).
EXPECTED_1080P = {
    "menu": "menu_enlist",
    "search": "server_row",
    "select_force": "select_force",
    "units": "switch_team",
    "create_unit": "create_unit",
    "deploy_counting": None,
    "ingame": None,
}
# Wide screens: the game keeps its menus in a 16:9 area in the middle, at the
# size it uses for a 16:9 screen of the same height (seen live at 2560x1080 on
# 2026-11-01), so these pad the 16:9 screenshots out at both sides.
WIDE = {"2560x1080": (2560, 1080), "3440x1440": (3440, 1440), "5120x2160": (5120, 2160)}
# Captured natively in live runs on 2026-11-01 (game build v1.7), with the
# account name and admin messages blacked out.
EXPECTED_NATIVE = {
    "2560x1080/select_force": "select_force",
    "2560x1080/units": "switch_team",
    "2560x1080/create_unit": "create_unit",
    "3440x1440/search": "server_row",
    "3840x2160/select_force": "select_force",
    "3840x2160/units": "switch_team",
    "3840x2160/create_unit": "create_unit",
    "3840x2160/roles": "roles_confirm",
    "3840x2160/deploy_counting": None,
    "5120x2160/search": "server_row",
}

# The native captures again at sizes no button image was cut at, where the app
# tries the image cut nearest the screen's height first. Trimmed by a row at
# the bottom, the game's own pixels go through that path (the menus move by
# under a pixel); resized, the text is the source's, shrunk or grown, which
# flatters the image cut at the source's height.
TRIMMED = [f"1080p/{shot}" for shot in EXPECTED_1080P] + list(EXPECTED_NATIVE)
RESIZED_NATIVE = {
    "1080p/search": [(1600, 900), (1366, 768)],
    "1080p/create_unit": [(1600, 900), (1366, 768)],
    "1080p/units": [(1600, 900)],
    "1080p/select_force": [(1366, 768)],
    "2560x1080/create_unit": [(2276, 960)],
    "3440x1440/search": [(2867, 1200)],
    "3840x2160/create_unit": [(3200, 1800)],
    "3840x2160/units": [(3200, 1800)],
    "5120x2160/search": [(4267, 1800)],
}
# The native 1080p CREATE UNIT capture stretched a few percent wider, as text
# comes out when the game draws it at a height no button image was cut at:
# only the last-resort sizes (Vision.LAST_RESORT) find it. [path, stretch, height]
STRETCHED = [("1080p/create_unit", 1.03, 1080), ("1080p/create_unit", 1.04, 1440)]

# Parts of the screens, as fractions of the 16:9 menu area (as in src/Flow.ahk).
INFANTRY_CREATE = [0.29, 0.10, 0.53, 0.22]
FACTION_BADGE = [0.0, 0.75, 0.12, 0.95]
# Screens narrower than 16:9 (16:10, 4:3), which no one has seeded on yet, with
# the game's 16:9 menus fitted to them each way narrow() makes. Cases where
# that way would put the button off the screen are left out.
NARROW_SHOTS = ["menu", "search", "select_force", "units", "create_unit", "roles_msg", "deploy", "gamemenu"]
NARROW = [("letter", (1920, 1200)), ("dpiw", (1600, 1200)), ("edge", (1920, 1200)), ("center", (1920, 1200))]
OFF_SCREEN = {("edge", "select_force"), ("center", "menu"), ("center", "gamemenu")}
# The server browser with the server's row (its name, players and ping from
# search.jpg) pasted into row k of an unfiltered list of nine (browser.jpg).
# Every row keeps the list's own JOIN, as in the game, so only the JOIN on the
# server's row is the one to click: on narrow screens and a 16:9 control. On
# 4:3 a JOIN's spot reaches the rows around it, so there the JOIN found
# nearest the server's name can be another server's.
ROW_TOP, ROW_STEP, ROW_HEIGHT, ROW_LEFT = 198, 79, 77, 55  # at 1920x1080
JOIN_CELL = (1232, 1360)  # the JOIN button's cell across, at 1920x1080
FIRST_JOIN_Y = 234  # the first row's JOIN, at 1920x1080
# [kind, size, row, options]. "blank" paints out the JOIN on the server's row,
# so nothing must be clicked; "at" puts the game's top left corner at that
# screen position (another monitor, or a window).
LIST_ROWS = (
    [("16x9", (1920, 1080), 4, {}), ("16x9", (1920, 1080), 4, {"blank": True}),
     ("16x9", (1920, 1080), 4, {"at": (-1920, 240)})]
    + [(kind, size, k, {}) for kind, size in NARROW if kind != "edge" for k in (0, 8)]
    + [(kind, (1600, 1200), k, {}) for kind in ("letter", "dpiw") for k in (1, 7)]
    + [("letter", (1600, 1200), 1, {"blank": True}), ("letter", (1600, 1200), 7, {"at": (2560, -300)})])
US_CARD = [0.05, 0.30, 0.50, 0.55]
NVA_CARD = [0.50, 0.30, 0.95, 0.55]
CREATE_UNIT_BUTTON = [0.55, 0.60, 0.95, 0.90]


def load(name: str, size: tuple[int, int]) -> np.ndarray:
    return fit(cv2.imread(str(SCREENS / f"{name}.jpg"), cv2.IMREAD_GRAYSCALE), size)


def fit(gray: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    if (gray.shape[1], gray.shape[0]) == size:
        return gray.copy()
    return cv2.resize(gray, size, interpolation=cv2.INTER_AREA if size[0] < gray.shape[1] else cv2.INTER_CUBIC)


def server_list(k: int, blank: bool = False) -> np.ndarray:
    """The 1920x1080 server browser listing nine servers, the server's own in
    row ``k`` (up to its JOIN cell); with ``blank``, that row's JOIN painted
    out with the cell's own gray."""
    page = load_file("browser")
    rows = load_file("search")
    top, right = ROW_TOP + ROW_STEP * k, JOIN_CELL[0] - 6
    page[top: top + ROW_HEIGHT, ROW_LEFT:right] = rows[ROW_TOP: ROW_TOP + ROW_HEIGHT, ROW_LEFT:right]
    if blank:
        y = FIRST_JOIN_Y + ROW_STEP * k
        page[y - 34: y + 35, JOIN_CELL[0]:JOIN_CELL[1]] = int(np.median(page[y - 20: y + 20, 1242:1262]))
    return page


def load_file(path: str) -> np.ndarray:
    return cv2.imread(str(SCREENS / f"{path}.jpg"), cv2.IMREAD_GRAYSCALE)


def widen(gray: np.ndarray, width: int) -> np.ndarray:
    side = width - gray.shape[1]
    return cv2.copyMakeBorder(gray, 0, 0, side // 2, side - side // 2, cv2.BORDER_CONSTANT, value=25)


def load_wide(name: str, res: str) -> np.ndarray:
    w, h = WIDE[res]
    if h == 1080 and (SCREENS / "1080p" / f"{name}.jpg").exists():
        gray = load_file(f"1080p/{name}")  # text drawn natively at this height
    else:
        gray = load(name, (h * 16 // 9, h))
    return widen(gray, w)


def narrow(source: np.ndarray, kind: str, size: tuple[int, int]) -> np.ndarray:
    """The 16:9 screenshot ``source`` on a ``size`` screen narrower than
    16:9, the game's menus fitted to it ``kind`` of way: "letter", scaled to
    the width and centred with black above and below; "dpiw", scaled to the
    width with the top half kept at the top and the bottom half at the
    bottom; "edge", scaled to the height with the left half kept at the left
    edge and the right half at the right; "center", scaled to the height and
    cut off at both sides."""
    w, h = size
    if kind in ("letter", "dpiw"):
        menus = round(w * 9 / 16)
        gray = fit(source, (w, menus))
        gap = h - menus
        if kind == "letter":
            return cv2.copyMakeBorder(gray, gap // 2, gap - gap // 2, 0, 0, cv2.BORDER_CONSTANT, value=0)
        half = menus // 2
        return np.vstack([gray[:half], gray[half - gap // 2: half - gap // 2 + gap], gray[half:]]).copy()
    wide = round(h * 16 / 9)
    gray = fit(source, (wide, h))
    if kind == "edge":
        return np.hstack([gray[:, : w // 2], gray[:, wide - (w - w // 2):]]).copy()
    left = (wide - w) // 2
    return gray[:, left: left + w].copy()


def list_join_y(kind: str, size: tuple[int, int], k: int) -> tuple[float, float]:
    """Where row ``k``'s JOIN is drawn down a ``size`` screen fitted ``kind``
    of way (see narrow), and the rows' pitch there, in pixels."""
    w, h = size
    if kind in ("letter", "dpiw"):
        menus = round(w * 9 / 16)
        gap = h - menus
        y = (FIRST_JOIN_Y + ROW_STEP * k) * menus / 1080
        if kind == "letter":
            y += gap // 2
        elif y >= menus // 2:
            y += gap
        return y, ROW_STEP * menus / 1080
    return (FIRST_JOIN_Y + ROW_STEP * k) * h / 1080, ROW_STEP * h / 1080


def factor(height: int) -> int:
    """How much the app shrinks a capture this tall (Vision.Factor): Python's
    round() rounds halves to even, as the app's RoundHalfEven does."""
    return max(1, round(height / 720))


def shrink(gray: np.ndarray, f: int) -> np.ndarray:
    """The app's working copy (Vision.WorkSize, GameScreen.Shrink): each f x f
    block averaged, rounding half up."""
    if f == 1:
        return gray
    h, w = gray.shape
    blocks = gray[: h // f * f, : w // f * f].astype(np.int64).reshape(h // f, f, w // f, f).sum(axis=(1, 3))
    return ((blocks + f * f // 2) // (f * f)).astype(np.uint8)


def menu_x(x: float, size: tuple[int, int]) -> float:
    """Where an x fraction of the 16:9 menu area lands on a ``size`` screen, in pixels."""
    w, h = size
    menus = min(w, h * 16 / 9)
    return (w - menus) / 2 + x * menus


def near(centre: float, reach: float) -> list[float]:
    return [centre - reach, centre + reach]


def checks_for(shot: str, size: tuple[int, int], kind: str) -> list[dict]:
    """The finer checks tests/test_matching.py made on this screenshot, if any."""
    w, h = size
    out: list[dict] = []
    if shot == "units" and kind in ("resized", "wide", "native1080"):
        out.append({"find": "faction_nva", "region": FACTION_BADGE})
    if (shot == "units" and kind != "native") or (shot == "rejoin_units" and kind == "wide"):
        out.append({"find": "infantry_create", "region": INFANTRY_CREATE,
                    "x": [menu_x(0.29, size), menu_x(0.53, size)]})
    if shot == "select_force":
        out.append({"find": "force_us", "region": US_CARD, "x": [0, w / 2]})
        out.append({"find": "force_nva", "region": NVA_CARD, "x": [w / 2, w]})
    if shot in ("create_unit", "rejoin_create_unit"):
        reach = 0.02 * (w if kind == "native" else min(w, h * 16 / 9))
        out.append({"find": "create_unit_button", "region": CREATE_UNIT_BUTTON,
                    "x": near(menu_x(0.765, size), reach), "y": near(0.741 * h, 0.02 * h)})
    if kind == "resized_native":
        if shot == "create_unit" and size in ((1600, 900), (1366, 768)):
            out.append({"only_cut": 1440, "name": "create_unit"})  # needs the last-resort sizes
        if shot == "search":
            out.append({"join_on_row": True, "x": near(menu_x(1726 / 2560, size), 0.01 * w), "row_dy": 0.01 * h})
        if shot == "units":
            out.append({"find": "switch_team"})
        return out
    if shot == "search":
        if kind == "resized":
            out.append({"join_on_row": True, "x": near(1726 * w / 2560, 10 * w / 1920),
                        "y": near(311 * h / 1440, 10 * h / 1080)})
        elif kind == "wide":
            out.append({"join_on_row": True, "x": near(menu_x(1726 / 2560, size), 15 * h / 1080)})
        elif kind == "native1080":
            out.append({"join_on_row": True, "row_x": near(365, 15), "row_y": near(227, 15),
                        "x": near(1294, 15), "y": near(233, 15)})
            out.append({"only_cut": 1080, "name": "server_row"})
        elif kind == "native":
            out.append({"join_on_row": True, "x": near(menu_x(1726 / 2560, size), 0.01 * w),
                        "row_dy": 0.01 * h})
            if w == 5120 and h in (2159, 2160):  # also trimmed
                out.append({"only_cut": 2160, "name": "server_row"})
    if shot == "create_unit" and kind == "native1080":
        out.append({"only_cut": 1080, "name": "create_unit"})
    if shot == "units" and kind == "native":
        out.append({"find": "infantry_create", "region": INFANTRY_CREATE, "x": near(menu_x(0.411, size), 0.02 * w)})
        out.append({"find": "switch_team"})
        out.append({"find": "faction_nva", "region": FACTION_BADGE, "missing": True})  # these runs picked US
        if w == 3840 and h in (2159, 2160):  # also trimmed
            out.append({"only_cut": 2160, "name": "switch_team"})
    if shot == "browser" and size == (1920, 1080) and kind == "resized":
        out.append({"count": "browser_join", "min": 8})
    if shot == "menu" and size == (2560, 1440) and kind == "resized":
        out.append({"find": "menu_enlist", "x": near(180, 12), "y": near(905, 12)})
    return out


def cases() -> list[tuple]:
    """[label, screenshot, screen the app should see, checks] for each case,
    and for some a dict of more case fields ("left", "top": where the
    screenshot is on screen)."""
    out = []
    for shot, screen in EXPECTED.items():
        for res, size in RESOLUTIONS.items():
            out.append((f"{shot}@{res}", load(shot, size), screen, checks_for(shot, size, "resized")))
        for res, size in WIDE.items():
            out.append((f"{shot}@{res}", load_wide(shot, res), screen, checks_for(shot, size, "wide")))
    for shot, screen in EXPECTED_1080P.items():
        out.append((f"1080p/{shot}", load_file(f"1080p/{shot}"), screen, checks_for(shot, (1920, 1080), "native1080")))
    for path, screen in EXPECTED_NATIVE.items():
        gray = load_file(path)
        size = (gray.shape[1], gray.shape[0])
        out.append((path, gray, screen, checks_for(path.split("/")[1], size, "native")))
    for path in TRIMMED:
        gray = load_file(path)[:-1]
        size = (gray.shape[1], gray.shape[0])
        out.append((f"{path}@{size[0]}x{size[1]}", gray, native_screen(path),
                    checks_for(path.split("/")[1], size, "native1080" if path.startswith("1080p/") else "native")))
    for path, sizes in RESIZED_NATIVE.items():
        source = load_file(path)
        for size in sizes:
            gray = cv2.resize(source, size, interpolation=cv2.INTER_AREA if size[0] < source.shape[1] else cv2.INTER_CUBIC)
            out.append((f"{path}@{size[0]}x{size[1]}", gray, native_screen(path),
                        checks_for(path.split("/")[1], size, "resized_native")))
    for path, stretch, height in STRETCHED:
        source = load_file(path)
        size = (round(height * 16 / 9 * stretch), height)
        out.append((f"stretched/{path.split('/')[1]}@{size[0]}x{size[1]}", fit(source, size), native_screen(path), []))
    for kind, size in NARROW:
        for shot in NARROW_SHOTS:
            if (kind, shot) not in OFF_SCREEN:
                out.append((f"{kind}/{shot}@{size[0]}x{size[1]}", narrow(load_file(shot), kind, size),
                            EXPECTED[shot], []))
    for kind, size, k, options in LIST_ROWS:
        page = server_list(k, options.get("blank", False))
        gray = page if size == (1920, 1080) else narrow(page, kind, size)
        y, pitch = list_join_y(kind, size, k)
        w, h = size
        if options.get("blank"):
            checks = [{"join_on_row": True, "none": True}]
        else:
            checks = [{"join_on_row": True, "y": near(y, pitch / 2)}]
            # Where each JOIN's spot reaches over its neighbours (dpiw, 4:3),
            # FindAll sees only some of them.
            if kind != "dpiw" and w * 10 >= h * 16:
                checks.append({"count": "browser_join", "min": 8})
        label = f"{kind}/browser_row{k}" + ("_blank" if options.get("blank") else "")
        at = {}
        if "at" in options:
            at = {"left": options["at"][0], "top": options["at"][1]}
            label += f"_at{at['left']},{at['top']}"
        out.append((f"{label}@{w}x{h}", gray, "server_row", checks, at))
    return out


def native_screen(path: str) -> str | None:
    """What the app should see on a native capture."""
    return EXPECTED_1080P[path[len("1080p/"):]] if path.startswith("1080p/") else EXPECTED_NATIVE[path]


def main(folder: str) -> None:
    root = Path(folder)
    (root / "frames").mkdir(parents=True, exist_ok=True)
    listing = []
    for n, (label, gray, screen, checks, *more) in enumerate(cases(), 1):
        h, w = gray.shape
        f = factor(h)
        file = f"frames/{n:03d}.png"
        cv2.imwrite(str(root / file), shrink(gray, f), [cv2.IMWRITE_PNG_COMPRESSION, 1])
        listing.append({"label": label, "file": file, "width": w, "height": h, "factor": f,
                        "screen": screen, "checks": checks, **(more[0] if more else {})})
    (root / "cases.json").write_text(json.dumps(listing, indent=1), encoding="utf-8")
    print(f"{len(listing)} cases in {root}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/fixtures")
