"""Build configuration for the unencrypted PAL Kawari port."""
from pathlib import Path
import sys

if sys.argv[1] == "options":
    # options [max] [pace=<game ticks per second>] [fps=<25|50>]
    words = sys.argv[2:]
    maximum = "TRUE" if "max" in words else "FALSE"
    settings = dict(w.split("=", 1) for w in words if "=" in w and w.split("=", 1)[1])
    pace = float(settings.get("pace", "8"))
    fps = int(settings.get("fps", "25"))
    if not 0.5 <= pace <= 50:
        sys.exit("pace must be between 0.5 and 50 game ticks per second")
    if fps not in (25, 50):
        sys.exit("fps must be 25 or 50 (whole PAL fields per frame)")
    Path("1-source-files/main-sources/elite-build-options.asm").write_text(
        "_VERSION=8\n_VARIANT=2\n_REMOVE_CHECKSUMS=TRUE\n"
        "_MATCH_ORIGINAL_BINARIES=FALSE\n_MAX_COMMANDER=" + maximum + "\n"
        f"_KW_PACE={pace}\n_KW_FIELDS={50 // fps}\n"
    )
