#!/usr/bin/env bash
# Rewrite the <iq:products> list in manifest.xml to exactly the devices that
# are installed locally AND new enough for this app's minApiLevel.
#
# "Universal" is only true if it compiles, so the device list is derived from
# the SDK's own device data rather than guessed.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

DEVDIR="$HOME/.Garmin/ConnectIQ/Devices"
[ -d "$DEVDIR" ] || { echo "No devices installed yet: $DEVDIR" >&2; exit 1; }

python3 -I - "$DEVDIR" <<'PY'
import json, os, re, sys

devdir = sys.argv[1]
manifest = "manifest.xml"
text = open(manifest, encoding="utf-8").read()

want = re.search(r'minApiLevel="([\d.]+)"', text)
min_api = tuple(int(p) for p in want.group(1).split(".")) if want else (0, 0, 0)

def api_of(device):
    path = os.path.join(devdir, device, "compiler.json")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    # The highest Connect IQ version this device can run.
    best = None
    for part in data.get("partNumbers", []):
        for level in part.get("connectIQVersion", "0.0.0").split(","):
            try:
                parsed = tuple(int(x) for x in level.strip().split("."))
            except ValueError:
                continue
            if best is None or parsed > best:
                best = parsed
    return best

keep, drop = [], []
for device in sorted(os.listdir(devdir)):
    if not os.path.isdir(os.path.join(devdir, device)):
        continue
    api = api_of(device)
    if api is None:
        drop.append((device, "no compiler.json"))
    elif api < min_api:
        drop.append((device, ".".join(map(str, api))))
    else:
        keep.append(device)

block = "\n".join('            <iq:product id="%s"/>' % d for d in keep)
text = re.sub(r"(<iq:products>)(.*?)(\s*</iq:products>)",
              lambda m: m.group(1) + "\n" + block + m.group(3),
              text, flags=re.S)
open(manifest, "w", encoding="utf-8").write(text)

print("kept %d device(s)" % len(keep))
for device, why in drop:
    print("  dropped %-28s (%s)" % (device, why))
PY
