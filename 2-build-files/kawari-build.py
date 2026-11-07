"""Build configuration for the unencrypted PAL Kawari port."""
from pathlib import Path
import sys

if sys.argv[1] == "options":
    maximum = "TRUE" if "max" in sys.argv[2:] else "FALSE"
    Path("1-source-files/main-sources/elite-build-options.asm").write_text(
        "_VERSION=8\n_VARIANT=2\n_REMOVE_CHECKSUMS=TRUE\n"
        "_MATCH_ORIGINAL_BINARIES=FALSE\n_MAX_COMMANDER=" + maximum + "\n"
    )
