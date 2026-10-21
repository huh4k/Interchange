#!/usr/bin/env python3
"""Split the statewide PTV GTFS feed into the per-mode files the app downloads.

Usage: tool/build_gtfs_r2.py <gtfs.zip> <out_dir>

The input is the zip of per-mode zips (1/google_transit.zip, 2/...). The output
mirrors what the app expects at kGtfsBaseUrl (lib/src/core/gtfs_config.dart):

    <out_dir>/metro.zip   <out_dir>/metro/stops.txt
    <out_dir>/tram.zip    <out_dir>/tram/stops.txt
    <out_dir>/vline.zip   <out_dir>/vline/stops.txt

Upload the contents of <out_dir> to the bucket root, e.g.:

    npx wrangler r2 object put <bucket>/metro.zip --file <out_dir>/metro.zip \
        --content-type application/zip --remote

The kept files must match kGtfsExtractAllowList in
lib/src/data/datasources/gtfs_zip_extractor.dart.
"""
import os
import shutil
import sys
import tempfile
import zipfile

# PTV mode folder in the statewide feed -> key used by PtvMode.gtfsKey.
MODES = {"1": "vline", "2": "metro", "3": "tram"}
KEEP = [
    "stops.txt",
    "routes.txt",
    "trips.txt",
    "stop_times.txt",
    "calendar.txt",
    "calendar_dates.txt",
]


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    master_path, out_dir = sys.argv[1:]
    os.makedirs(out_dir, exist_ok=True)

    with zipfile.ZipFile(master_path) as master, tempfile.TemporaryDirectory() as tmp:
        for folder, key in MODES.items():
            inner_path = os.path.join(tmp, f"{key}_in.zip")
            with master.open(f"{folder}/google_transit.zip") as src, open(inner_path, "wb") as dst:
                shutil.copyfileobj(src, dst)

            zip_path = os.path.join(out_dir, f"{key}.zip")
            with zipfile.ZipFile(inner_path) as inner, zipfile.ZipFile(
                zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9
            ) as out:
                for name in KEEP:
                    with inner.open(name) as src, out.open(name, "w") as dst:
                        shutil.copyfileobj(src, dst)

            stops_dir = os.path.join(out_dir, key)
            os.makedirs(stops_dir, exist_ok=True)
            with zipfile.ZipFile(zip_path) as z, z.open("stops.txt") as src, open(
                os.path.join(stops_dir, "stops.txt"), "wb"
            ) as dst:
                shutil.copyfileobj(src, dst)

            print(f"{key}: {os.path.getsize(zip_path) / 1e6:.1f} MB zip")


if __name__ == "__main__":
    main()
