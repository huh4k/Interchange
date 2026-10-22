/// Where the static GTFS data is hosted (Cloudflare R2). Per mode `<key>`
/// (see `PtvMode.gtfsKey`) it serves `<key>/stops.txt` and `<key>.zip`.
/// `tool/build_gtfs_r2.py` produces these files from the statewide PTV feed.
/// Override with `--dart-define=GTFS_BASE_URL=...`, e.g. a local CORS proxy
/// when running the web build on localhost.
const kGtfsBaseUrl = String.fromEnvironment(
  'GTFS_BASE_URL',
  defaultValue: 'https://gtfs.huh4k.dev/gtfs-r2',
);
