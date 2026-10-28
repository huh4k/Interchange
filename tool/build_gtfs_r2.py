#!/usr/bin/env python3
"""Split the statewide PTV GTFS feed into the per-mode files the app downloads.

Usage: tool/build_gtfs_r2.py <gtfs.zip> <out_dir>

The input is the zip of per-mode zips (1/google_transit.zip, 2/...). The output
mirrors what the app expects at kGtfsBaseUrl (lib/src/core/gtfs_config.dart):

    <out_dir>/metro.zip   <out_dir>/metro/stops.txt
    <out_dir>/tram.zip    <out_dir>/tram/stops.txt
    <out_dir>/vline.zip   <out_dir>/vline/stops.txt
    <out_dir>/metroBus.zip   <out_dir>/metroBus/stops.txt

Metro bus is by far the largest feed, so it is trimmed to the services running
in the next TRIM_DAYS days, and to the columns the app reads.

Upload the contents of <out_dir> to the bucket root, e.g.:

    npx wrangler r2 object put <bucket>/metro.zip --file <out_dir>/metro.zip \
        --content-type application/zip --remote

The kept files must match kGtfsExtractAllowList in
lib/src/data/datasources/gtfs_zip_extractor.dart.
"""
import csv
import datetime
import io
import os
import shutil
import sys
import tempfile
import zipfile

# PTV mode folder in the statewide feed -> key used by PtvMode.gtfsKey.
MODES = {"1": "vline", "2": "metro", "3": "tram", "4": "metroBus"}
TRIM_MODES = {"metroBus"}
TRIM_DAYS = 21
STOP_TIME_COLUMNS = ["trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence", "platform_code"]
KEEP = [
    "stops.txt",
    "routes.txt",
    "trips.txt",
    "stop_times.txt",
    "calendar.txt",
    "calendar_dates.txt",
]


def read_rows(inner, name):
    with inner.open(name) as raw:
        yield from csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline=""))


def write_rows(out, name, fields, rows):
    with out.open(name, "w") as raw:
        text = io.TextIOWrapper(raw, encoding="utf-8", newline="", write_through=True)
        w = csv.DictWriter(
            text, fieldnames=fields, extrasaction="ignore", lineterminator="\n"
        )
        w.writeheader()
        w.writerows(rows)
        text.detach()


def trim(inner, out, today=None):
    """Write a smaller copy of the feed: only services running in the window."""
    today = today or datetime.date.today()
    days = [today + datetime.timedelta(d) for d in range(TRIM_DAYS)]
    ymd = {d.strftime("%Y%m%d") for d in days}
    weekdays = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]

    calendar = [r for r in read_rows(inner, "calendar.txt")]
    keep_calendar = []
    services = set()
    for r in calendar:
        if r["end_date"] < min(ymd) or r["start_date"] > max(ymd):
            continue
        if any(
            r[weekdays[d.weekday()]] == "1"
            and r["start_date"] <= d.strftime("%Y%m%d") <= r["end_date"]
            for d in days
        ):
            keep_calendar.append(r)
            services.add(r["service_id"])

    keep_dates = []
    for r in read_rows(inner, "calendar_dates.txt"):
        if r["date"] in ymd:
            keep_dates.append(r)
            if r["exception_type"] == "1":
                services.add(r["service_id"])

    trips = [r for r in read_rows(inner, "trips.txt") if r["service_id"] in services]
    trip_ids = {r["trip_id"] for r in trips}
    route_ids = {r["route_id"] for r in trips}

    used_stops = set()

    def stop_times():
        for r in read_rows(inner, "stop_times.txt"):
            if r["trip_id"] in trip_ids:
                used_stops.add(r["stop_id"])
                yield r

    def fields_of(name):
        return next(csv.reader(io.TextIOWrapper(inner.open(name), encoding="utf-8-sig")))

    write_rows(out, "calendar.txt", fields_of("calendar.txt"), keep_calendar)
    write_rows(out, "calendar_dates.txt", fields_of("calendar_dates.txt"), keep_dates)
    write_rows(out, "trips.txt", fields_of("trips.txt"), trips)
    write_rows(
        out,
        "routes.txt",
        fields_of("routes.txt"),
        (r for r in read_rows(inner, "routes.txt") if r["route_id"] in route_ids),
    )
    cols = [c for c in STOP_TIME_COLUMNS if c in fields_of("stop_times.txt")]
    write_rows(out, "stop_times.txt", cols, stop_times())

    stops = list(read_rows(inner, "stops.txt"))
    parents = {r["parent_station"] for r in stops if r["stop_id"] in used_stops and r.get("parent_station")}
    write_rows(
        out,
        "stops.txt",
        fields_of("stops.txt"),
        (r for r in stops if r["stop_id"] in used_stops or r["stop_id"] in parents),
    )


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
                if key in TRIM_MODES:
                    trim(inner, out)
                else:
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
