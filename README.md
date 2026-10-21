<div align="center">

<img src="assets/icon/app_icon_round.png" alt="Interchange" width="96" height="96" />

# Interchange

**Live Melbourne public transport, in one fast app.**

Metro trains, Yarra trams and V/Line, with live departures, ride tracking and connections.

[![Latest release](https://img.shields.io/github/v/release/huh4k/Interchange?style=flat-square&color=0072CE)](https://github.com/huh4k/Interchange/releases)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-78BE20?style=flat-square)](LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-3.x-8F1A95?style=flat-square)

[**Download the latest release**](https://github.com/huh4k/Interchange/releases) · [Report an issue](https://github.com/huh4k/Interchange/issues)

</div>

---

## Download

Grab the latest build for your platform from the **[Releases page](https://github.com/huh4k/Interchange/releases)**. Each release lists what changed since the last one.

To run from source instead, see [Getting Started](#getting-started).

## Features

| | |
|---|---|
| 🚆 **Three networks** | Switch between Metro trains, Yarra trams and V/Line with one tap |
| ⏱️ **Live departures** | Real-time data from the PTV Timetable API, with the GTFS timetable as a fallback |
| 📍 **Live ride tracking** | Follow your trip stop by stop, including "Between X and Y" while travelling |
| 🚶 **Leave by** | Opt-in walking time to your station, with a "Leave by" time on each departure and services you can't reach dimmed |
| 🔁 **Connection advisor** | Checks whether you'll make a transfer at key interchange stations |
| ⚠️ **Disruptions** | Alerts for the lines and stations you care about |
| ⭐ **Favourites and search** | Fast station search, recents and saved stations |

## Tech Stack

- **Flutter and Dart** for iOS, Android, macOS and Windows
- **PTV Timetable API v3** for live departures and disruptions
- **GTFS static data**, hosted on Cloudflare R2, parsed and cached on device

## Getting Started

### Prerequisites

- Flutter SDK (`>=3.12.2`) and Dart SDK (`^3.12.2`)
- An iOS simulator, Android emulator or physical device
- A PTV Developer ID and API key (request one from PTV by email)

### Setup

```bash
git clone https://github.com/huh4k/Interchange.git
cd Interchange
flutter pub get
```

To run with your own key, create a `.env` file in the project root (it's optional, since the proxy is the default):

```env
PTV_USER_ID=your_ptv_dev_id
PTV_API_KEY=your_ptv_api_key
PTV_BASE_URL=https://timetableapi.ptv.vic.gov.au
```

Then run the app:

```bash
flutter run
```

### Tests

```bash
flutter test
```

## PTV API key

No shipped build holds the PTV key. Requests go to a signing proxy, the Cloudflare Pages Function in [`functions/api/ptv`](functions/api/ptv/%5B%5Bpath%5D%5D.js), which signs them server-side and forwards them to PTV. In the Pages project settings, add `PTV_USER_ID` and `PTV_API_KEY` as encrypted variables.

| Build | Where requests go |
|---|---|
| Web (`interchange.huh4k.dev`) | Its own origin, `/api/ptv` |
| Android, iOS, desktop release builds | `https://interchange.huh4k.dev/api/ptv`, or your own via `--dart-define=PTV_PROXY_URL=...` |
| Debug runs with a `.env` key | Signed locally, straight to PTV |

The proxy only answers trusted callers: the website itself, or a client that sends the shared secret in an `X-Interchange-Key` header. Pick a secret and add it to the Pages project as an encrypted `APP_KEY` variable:

```bash
openssl rand -hex 32
```

Then pass the same value when you build an app you hand out. It's a build-time define, never part of `.env` or the repo:

```bash
flutter build apk --release --dart-define=APP_KEY=your_secret
```

Anything shipped in an app can be extracted, so this keeps casual users off the proxy rather than stopping a determined one. If it leaks, change `APP_KEY` in Pages and rebuild.

Release builds ignore the key in `.env`, but `.env` is still bundled as an asset. Empty it before a release build, or the key ships inside it:

```bash
mv .env .env.dev && touch .env && flutter build apk --release; mv .env.dev .env
```

Web deploys run from [`cloudflare.yml`](.github/workflows/cloudflare.yml) with an empty `.env`.

## GTFS data

The app doesn't download the 268 MB statewide PTV feed. Each mode (`metro`, `tram`, `vline`) uses two small files hosted on Cloudflare R2, at the base URL in [`gtfs_config.dart`](lib/src/core/gtfs_config.dart):

| File | Used for |
|---|---|
| `<mode>/stops.txt` | Station list, revalidated with ETags |
| `<mode>.zip` | Scheduled timetable fallback (routes, trips, stop times, calendars), fetched only when needed |

<details>
<summary><b>Publishing a new feed</b></summary>

<br />

1. Download the statewide `gtfs.zip` from [Victoria's open data portal](https://opendata.transport.vic.gov.au/dataset/gtfs-schedule).
2. Build the per-mode files:

   ```bash
   python3 tool/build_gtfs_r2.py path/to/gtfs.zip out_dir
   ```

3. Upload the contents of `out_dir` to the R2 bucket at the base URL's path, keeping the `metro/`, `tram/` and `vline/` folders.

</details>

## Project structure

```text
lib/
├── main.dart
└── src/
    ├── core/            config, HTTP and CSV helpers
    ├── data/            GTFS repository, index and timetable
    ├── domain/          entities and value objects
    ├── presentation/    screens, widgets and state
    ├── services/        PTV API, location, favourites
    └── theme/
tool/
└── build_gtfs_r2.py     builds the per-mode GTFS files
```

## License

Released under the [GNU General Public License v3.0](LICENSE).
