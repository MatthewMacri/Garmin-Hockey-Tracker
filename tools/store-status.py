#!/usr/bin/env python3
"""Read a live Connect IQ store listing, and diff it against the manifest.

The upload notes say to check the store's Compatible Devices list against
manifest.xml before every submission, because Garmin's App Migration has
silently dropped devices from a listing before. That check is tedious by eye
at 126 products, so it is done here instead:

    tools/store-status.py [store-uuid]

With no argument it uses this app's own listing.

The store UUID is NOT the manifest application id. The manifest id 404s on the
store by design; the store assigns a listing its own UUID. Three places carry
the real one: the address bar of the listing page, the dashboard URL, and -
most usefully, because it needs no login at all - GARMIN/GarminDevice.xml on
any watch with the app installed from the store, which lists a <StoreId> per
installed app. A store-installed build also stamps it into every FIT file as
developer_data_id.application_id, so tools/fit/fitread.py recovers it offline
from a recorded game. A sideloaded build writes zeros there instead.

No browser and no API key. There is an unauthenticated JSON endpoint under
apps.garmin.com/api/... which serves the same 43-key record the listing page
embeds; this reads that, and falls back to scraping __NEXT_DATA__ out of the
server-rendered page if the endpoint ever moves. (The services.garmin.com host
hard-401s without an X-garmin-client-id; the apps.garmin.com path is a
server-side proxy that does not.)

It also diffs the live Description and What's New against the text the repo
intends to publish. That check exists because the drift it catches really
happened: every release from 2.4.0 to 2.5.5 updated What's New and left the
Description at its 2.1.0-era text, so the listing advertised none of stride
rate, heart rate recovery or skating load for five releases, and kept a claim
about chest straps that 2.4.0 had withdrawn as untested.
"""

import json
import os
import re
import sys
import urllib.request

STORE = "https://apps.garmin.com/en-US/apps/%s"
API = ("https://apps.garmin.com/api/appsLibraryExternalServices"
       "/api/asw/apps/%s")
PUBLIC = "https://apps.garmin.com/apps/%s"

# This app's own listing, so the tool runs with no arguments. Note this is the
# StoreId, not the manifest id d979409c-... which 404s on the store.
SELF = "4b5a5a43-135d-456e-91a0-c1dbca4ada2d"

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "..", "IndoorHockey", "manifest.xml")
DOCS = os.path.join(HERE, "..", "docs")


def listing(uuid):
    """The listing's own JSON record."""
    req = urllib.request.Request(API % uuid, headers={"User-Agent": "curl/8"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            detail = json.loads(r.read().decode("utf-8", "replace"))
        if detail.get("id"):
            return detail
    except Exception:
        pass  # fall through to the page scrape

    req = urllib.request.Request(STORE % uuid, headers={"User-Agent": "curl/8"})
    with urllib.request.urlopen(req, timeout=30) as r:
        html = r.read().decode("utf-8", "replace")
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        raise SystemExit("neither the API nor the page gave a listing - the "
                         "store changed, or that UUID is not a listing")
    detail = json.loads(m.group(1))["props"]["pageProps"].get("initialAppDetail")
    if not detail:
        raise SystemExit("page carries no app detail - check the UUID")
    return detail


def normalise(s):
    """Compare what the text says, not how it is wrapped.

    The upload form reflows a pasted paragraph, so the repo's hard-wrapped
    source and the stored text differ by newlines alone. Paragraph breaks are
    kept, because those survive the paste and are a real difference. Dashes
    are folded because the form has been seen to prettify a hyphen into an
    em dash.
    """
    s = (s or "").replace("\r\n", "\n").replace("\u2014", "-").replace("\u2013", "-")
    paras = re.split(r"\n\s*\n", s.strip())
    return "\n\n".join(" ".join(p.split()) for p in paras)


def intended():
    """The Description and What's New the repo means to publish.

    Taken from the highest-numbered docs/store-*.md, which is the file the
    release procedure retargets on every version.
    """
    best, bestkey = None, ()
    for name in os.listdir(DOCS):
        m = re.match(r"store-(\d+(?:\.\d+)*)\.md$", name)
        if m:
            key = tuple(int(x) for x in m.group(1).split("."))
            if key > bestkey:
                best, bestkey = os.path.join(DOCS, name), key
    if not best:
        return None, {}
    with open(best, encoding="utf-8") as f:
        text = f.read()
    out = {}
    for heading in ("Description", "What's New"):
        m = re.search(r"^## %s\s*$(.*?)(?=^## |\Z)" % re.escape(heading),
                      text, re.S | re.M)
        if not m:
            continue
        fenced = re.findall(r"^```[^\n]*\n(.*?)^```", m.group(1), re.S | re.M)
        if fenced:
            # The paste block is the long one; shorter fences in the same
            # section are examples and field snippets.
            out[heading] = max(fenced, key=len).rstrip("\n")
    return os.path.basename(best), out


def manifest_parts():
    """Every part number the package declares, via the SDK's device files."""
    with open(MANIFEST, encoding="utf-8") as f:
        ids = sorted(set(re.findall(r'<iq:product id="([^"]+)"', f.read())))
    parts, missing = set(), []
    devices = os.path.expanduser("~/.Garmin/ConnectIQ/Devices")
    for d in ids:
        path = os.path.join(devices, d, "compiler.json")
        if not os.path.exists(path):
            missing.append(d)
            continue
        with open(path, encoding="utf-8") as f:
            for p in json.load(f).get("partNumbers", []):
                if p.get("number"):
                    parts.add(p["number"])
    return ids, parts, missing


def check_text(d):
    """Diff the live listing text against what the repo intends to publish."""
    src, want = intended()
    if not want:
        return False
    loc = (d.get("appLocalizations") or [{}])[0]
    got = {"Description": loc.get("description"),
           "What's New": loc.get("whatsNew")}
    stale = []
    print("\ntext vs %s:" % src)
    for heading in ("Description", "What's New"):
        if heading not in want:
            continue
        if normalise(want[heading]) == normalise(got.get(heading)):
            print("   %-12s matches the repo" % heading)
        else:
            stale.append(heading)
            print("   %-12s DIFFERS  (live %d chars, repo %d)"
                  % (heading, len(got.get(heading) or ""), len(want[heading])))
    if stale:
        print("The listing is not showing what this repo says it should. Paste"
              "\n%s from %s on the next upload - BOTH boxes, every time."
              % (" and ".join(stale), src))
    return bool(stale)


def main():
    if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] in
                             ("-h", "--help")):
        print(__doc__)
        return 2
    uuid = sys.argv[1] if len(sys.argv) == 2 else SELF
    d = listing(uuid)

    import datetime

    def date(ms):
        if not ms:
            return "?"
        return datetime.datetime.fromtimestamp(
            ms / 1000, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    name = (d.get("appLocalizations") or [{}])[0].get("name", "?")
    print("listing   : %s   by %s" % (name, (d.get("developer") or {}).get(
        "developerDisplayName", "?")))
    print("status    : %s" % d.get("status", "?"))

    # The two version numbers are different things and both matter. The
    # external one is the free text typed into the upload form. The internal
    # one is the ordinal the store assigns, and it is what a store-installed
    # build stamps into the FIT file as application_version - which is why a
    # sideloaded build, having no ordinal, writes zero.
    print("version   : %s   (internal %s)"
          % (d.get("latestExternalVersion", "?"), d.get("latestInternalVersion", "?")))
    print("published : %s" % date(d.get("releaseDate")))

    pending = d.get("hasVersionPendingScan")
    if pending:
        print("REVIEW    : a submitted version is still being scanned. The "
              "public listing\n            keeps showing the version above "
              "until it passes.")
    else:
        print("review    : nothing pending - the version above is the live one")

    if d.get("latestVersionAutoMigrated"):
        print("MIGRATED  : Garmin auto-migrated this version's device list "
              "rather than\n            taking it from the manifest. Check "
              "the dropped list below.")

    for label, key in (("downloads", "downloadCount"), ("rating", "averageRating"),
                       ("reviews", "reviewCount")):
        if key in d:
            print("%-10s: %s" % (label, d[key]))
    live = set(d.get("compatibleDevicePartNumbers") or [])
    print("devices   : %d part numbers live" % len(live))

    ids, parts, missing = manifest_parts()
    print("manifest  : %d products -> %d part numbers" % (len(ids), len(parts)))
    if missing:
        print("            (%d products have no SDK device file installed, so "
              "their part\n             numbers could not be read: %s%s)"
              % (len(missing), ", ".join(missing[:4]),
                 " ..." if len(missing) > 4 else ""))

    # Only meaningful against your own listing: run it on someone else's and
    # the "dropped" list is just the difference between two different apps.
    dropped = parts - live
    extra = live - parts
    if dropped:
        print("\nDROPPED - in the package, missing from the listing (%d):"
              % len(dropped))
        for p in sorted(dropped):
            print("   %s" % p)
        print("These are devices your users cannot install on. Fix the "
              "Compatible\nDevices list on the upload form before submitting.")
    if extra:
        print("\nonly on the listing, not in this package (%d): %s%s"
              % (len(extra), ", ".join(sorted(extra)[:6]),
                 " ..." if len(extra) > 6 else ""))
    if not dropped and not extra and parts:
        print("\nlisting and package agree on every part number.")

    stale = check_text(d)
    print("\nlink      : %s" % (PUBLIC % uuid))
    return 1 if (dropped or stale) else 0


if __name__ == "__main__":
    sys.exit(main())
