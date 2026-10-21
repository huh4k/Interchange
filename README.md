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

Create a `.env` file in the project root:

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

## Web deployment

The web build is public, so it never holds the PTV key. It calls `/api/ptv/...` on its own origin, and the Cloudflare Pages Function in [`functions/api/ptv`](functions/api/ptv/%5B%5Bpath%5D%5D.js) signs the request and forwards it to PTV. In the Pages project settings, add `PTV_USER_ID` and `PTV_API_KEY` as encrypted variables. Deploys run from [`cloudflare.yml`](.github/workflows/cloudflare.yml).

Mobile and desktop builds read the key from your local `.env` instead (see [Setup](#setup)).

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
