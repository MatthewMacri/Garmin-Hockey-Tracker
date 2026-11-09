#!/usr/bin/env python3
"""Read a live Connect IQ store listing, and diff it against the manifest.

The upload notes say to check the store's Compatible Devices list against
manifest.xml before every submission, because Garmin's App Migration has
silently dropped devices from a listing before. That check is tedious by eye
at 126 products, so it is done here instead:

    tools/store-status.py <store-uuid>

The store UUID is NOT the manifest application id. The manifest id 404s on the
store by design; the store assigns a listing its own UUID, which is the one in
the address bar of the live listing page.

No browser and no API key. The listing is a server-rendered Next.js page, so
everything worth reading - version, downloads, rating, review count and the
full compatible-device list - is in the HTML it serves to curl.
"""

import json
import os
import re
import sys
import urllib.request

STORE = "https://apps.garmin.com/en-US/apps/%s"
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "IndoorHockey", "manifest.xml")


def listing(uuid):
    """The listing's own JSON, lifted out of the page it is embedded in."""
    req = urllib.request.Request(STORE % uuid, headers={"User-Agent": "curl/8"})
    with urllib.request.urlopen(req, timeout=30) as r:
        html = r.read().decode("utf-8", "replace")
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        raise SystemExit("no __NEXT_DATA__ in the page - the store's markup "
                         "changed, or that UUID is not a listing")
    detail = json.loads(m.group(1))["props"]["pageProps"].get("initialAppDetail")
    if not detail:
        raise SystemExit("page carries no app detail - check the UUID")
    return detail


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


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    d = listing(sys.argv[1])

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
    return 1 if dropped else 0


if __name__ == "__main__":
    sys.exit(main())
