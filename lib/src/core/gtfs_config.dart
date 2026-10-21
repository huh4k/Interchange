/// Where the static GTFS data is hosted (Cloudflare R2). Per mode `<key>`
/// (see `PtvMode.gtfsKey`) it serves `<key>/stops.txt` and `<key>.zip`.
/// `tool/build_gtfs_r2.py` produces these files from the statewide PTV feed.
const kGtfsBaseUrl = 'https://gtfs.huh4k.dev/gtfs-r2';
