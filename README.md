# RPS — Regatta Positioning System

A native iOS app for sailboat racing: build a course, run the start sequence, and see live
bearing/distance to the next mark, wind, and current — all on the water, without cell signal once
the marks are loaded.

RPS is the client half of a two-repo system. The other half, [`rps_admin`](https://github.com/jdank417/RPS_Admin),
is the FastAPI backend and Angular admin console that clubs use to maintain their marks and that
this app talks to.

## Features

- **Course Builder** — lay out a course from a club's charted marks, or drop a portable one from
  the boat's current GPS position.
- **Race Mode** — start sequence, live position, and bearing/distance to the next mark, computed
  on-device from GPS.
- **Weather** — WeatherKit as the primary wind/conditions source, with an Open-Meteo fallback, plus
  NOAA tidal current data.
- **Live Activities & widgets** — the start countdown and current leg on the Lock Screen and Home
  Screen, via ActivityKit and WidgetKit (see [`RPSLiveActivity`](RPSLiveActivity)).
- **Accounts** — sign in, manage a home club, request a club be onboarded, and delete your account,
  all backed by `rps_admin`.

## Architecture

- **SwiftUI**, using the `@Observable` macro rather than `ObservableObject`. A handful of
  long-lived stores are created once in [`RPSApp.swift`](RPS/RPSApp.swift) and handed down through
  the environment, so Course Builder, Race Mode, and the widgets all read and write the same
  course/GPS/wind state instead of each holding their own copy:

  | Store | Owns |
  |---|---|
  | `AppState` | Sign-in state, deep-link routing |
  | `AppSettings` | Persisted user settings, API base URL |
  | `CourseStateStore` | The course currently being built or raced |
  | `LivePositionStore` | Live GPS position |
  | `WindService` | Current wind reading (WeatherKit / Open-Meteo) |
  | `TidalCurrentService` | NOAA tidal current data |
  | `StartSequenceViewModel` | Start-sequence timing |
  | `RaceViewModel` | Bearing/distance to the next mark |
  | `RaceLiveActivityManager` | The Live Activity shown during a race |

- **Feature modules** under [`RPS/Features`](RPS/Features): `Auth`, `CourseBuilder`, `Info`, `Map`,
  `Onboarding`, `Profile`, `Race`, `Root`, `Weather`.

- **Networking** ([`RPS/Networking`](RPS/Networking)) — an async/await `APIClient` that talks to
  `rps_admin`'s REST API, with bearer-token auth, automatic 401 → refresh → retry, and generous
  timeouts (90–120s) to tolerate the backend's free-tier cold starts. Access and refresh tokens are
  stored in the Keychain via `KeychainStore`, never `UserDefaults`. There is no local database
  beyond on-device caching — every authorization and validation rule lives server-side, so the app
  and the admin console can never disagree about what a club's marks or membership actually are.

- **Deep linking** — the `rps://` custom URL scheme (`rps://countdown`, `rps://leg`), used by the
  Live Activity and widget tap targets, routed through `AppState.handle(url:)`.

## `RPSLiveActivity`

A separate widget extension target providing:

- `RPSRaceWidget` — the start countdown and current-leg Live Activity / Dynamic Island.
- `RPSWindWidget` — a Home Screen wind widget.

The main app and the extension share data through the `group.JasonDank.RPS` App Group.

## Requirements

- Xcode with an iOS 26.2+ deployment target, Swift 5.
- An Apple Developer account with WeatherKit and Live Activities entitlements (`RPS.entitlements`,
  `RPSLiveActivityExtension.entitlements`) to build and run on a device.
- No SwiftPM/CocoaPods dependencies — everything is first-party frameworks.

## Backend

The app talks to [`rps_admin`](https://github.com/jdank417/RPS_Admin) (`AppSettings.apiBaseURLString`,
default `https://rps-admin-backend.onrender.com`) for auth, club/mark data, and account management.
See that repo for the API and the admin console clubs use to manage their own marks and admins.
