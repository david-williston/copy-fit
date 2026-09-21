# Copy Fit

A personal Android app that pulls your health data out of **Health Connect** and
puts it on the clipboard as JSON, so you can paste it into ChatGPT for coaching.

Android only. Sideload only. Not built for the Play Store.

## What it does

1. Asks Health Connect for read access to the metrics you pick.
2. Reads back the range you choose (7 days to 1 year).
3. Formats the result as JSON and copies it to the clipboard.

Nothing leaves the phone. There is no network code and no analytics — the only
way data moves is the clipboard or the share sheet, both of which you trigger.

## Formats

**Daily summary** (the default) — one object per calendar day, with each metric
rolled up. This is the one to paste into a chat: a month of data is typically a
few thousand tokens.

```json
{
  "export": {
    "source": "Android Health Connect",
    "generated_at": "2026-09-20T11:24:03-06:00",
    "range": { "start": "2026-08-22", "end": "2026-09-20" },
    "format": "daily_summary",
    "notes": ["..."]
  },
  "units": { "steps": "count", "distance": "m", "heart_rate": "bpm", "weight": "kg" },
  "days": [
    {
      "date": "2026-09-19",
      "steps": 8421,
      "distance": 6210,
      "active_energy": 512,
      "heart_rate": { "min": 48, "avg": 68.2, "max": 142, "n": 1440 },
      "resting_heart_rate": 52,
      "sleep": {
        "asleep_min": 465,
        "in_bed_min": 480,
        "efficiency_pct": 96.9,
        "session_count": 2,
        "main_sleep": {
          "start": "2026-09-18T23:00:00-06:00",
          "end": "2026-09-19T06:00:00-06:00",
          "in_bed_min": 420, "asleep_min": 420, "efficiency_pct": 100,
          "deep_min": 72, "rem_min": 98, "light_min": 250, "awake_min": 15
        },
        "naps": [
          { "start": "2026-09-19T14:00:00-06:00", "end": "2026-09-19T14:45:00-06:00",
            "in_bed_min": 45, "asleep_min": 45, "light_min": 45 }
        ]
      },
      "weight": 81.2,
      "workouts": [
        { "activity": "RUNNING", "energy_kcal": 410, "distance_m": 6800,
          "start": "2026-09-19T06:30:00-06:00", "duration_min": 42 }
      ]
    }
  ]
}
```

**Raw points** — every individual reading. Complete, but heart rate alone can be
hundreds of readings a day, so this runs to megabytes over long ranges. Use it
when you want a specific day analysed in detail.

The result card shows the byte size and a rough token count before you copy, so
you can tell whether it will fit in a chat.

### Conventions worth knowing

- Days are **local calendar days**, and a day with no data is left out entirely.
- **Sleep is filed under the date the session ended** (the wake-up date). Stages
  are attached to the session that contains them *first*, then the whole session
  is dated — so a night crossing midnight stays intact rather than scattering its
  pre-midnight stages onto the previous day.
- `main_sleep` is the longest session of the day. `naps` holds every other
  session, each keeping its own `start` and `end`.
- Day-level `asleep_min` / `in_bed_min` are **totals across all sessions**, so a
  night plus an afternoon nap add up. Per-session figures live inside each
  session object.
- Within a session, `asleep_min` is deep + REM + light and excludes awake;
  `in_bed_min` is the full session length; `efficiency_pct` is their ratio.
- `stages_available: false` means the source logged a session with no stage
  breakdown, so `asleep_min` falls back to the session length.
- `unassigned_stages` is stage time belonging to no session. It is excluded from
  `asleep_min` and is normally a source quirk — surfaced rather than dropped so
  the numbers stay honest.
- Every metric other than sleep is filed under the date its reading started.
- Units are listed per metric in the top-level `units` object rather than baked
  into key names, so they reflect what Health Connect actually returned.

## Running it

Needs Flutter and an Android SDK. `flutter doctor` should be clean.

```sh
flutter pub get
flutter test
```

Day to day, run it from VS Code: the `copy-fit` config in `.vscode/launch.json`
launches in debug mode on the attached phone (F5). Debug builds print the
per-type read report to the Debug Console, which is easier to read and copy than
the on-screen Diagnostics card.

Hot reload does not re-read saved preferences, so after changing the default
metric set use hot **restart**.

From the terminal the equivalent is:

```sh
flutter run            # debug, with hot reload
flutter run --release  # release timings on the device
```

### Building a standalone APK

Only needed if you want the app on the phone without a cable:

```sh
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The release build is signed with the local **debug** keystore, which is fine for
sideloading. The catch: if that keystore is ever regenerated, a new APK will not
install over the old one and you will have to uninstall first. If that becomes
annoying, create a real keystore and wire it into
`android/app/build.gradle.kts`.

## Where settings live

Range, format, the recording-app toggle and the metric selection are stored with
`shared_preferences`, which on Android is a private XML file in the app's own
data directory:

```
/data/data/com.davidwilliston.copy_fit/shared_prefs/FlutterSharedPreferences.xml
```

Every change is written immediately, so a choice survives closing the app
without running an export. The values survive app updates and reinstalls; they
are wiped by an uninstall or by "Clear storage" in app info. Clearing storage
also revokes the Health Connect permissions, so the app comes back at its
defaults and asks for access again.

The `metrics` key is versioned (`metrics.v2`). Bump it when the default
selection changes, otherwise a saved set from an older build masks the new
default.

## First run

Health Connect must be installed — it ships with Android 14+ and is a Play Store
app before that. The banner at the top of the screen says whether it is present
and offers to install it if not.

On the first read, Android shows the Health Connect permission screen. Grant the
metrics you care about. **Ranges longer than 30 days also need the "historical
data" permission**, which Health Connect asks for separately; without it your
export silently stops at 30 days. The app warns you about this when you pick a
long range.

If a metric comes back empty, the **Diagnostics** card under the result explains
why: it lists every Health Connect type separately with how many points it
returned, whether the permission was granted, the dates actually covered, and the
error if the read threw. In debug builds the same report prints to the console.

The most common cause of a short export is the **30-day cap**: without the
historical-data permission, Health Connect silently truncates every read to the
last 30 days. The Diagnostics card says outright whether that permission was
granted and flags a result that looks truncated.

## Layout

| Path | What it is |
| --- | --- |
| `lib/metrics.dart` | The catalog of exportable metrics and how each aggregates |
| `lib/exporter.dart` | Turns Health Connect points into the JSON document |
| `lib/health_service.dart` | Permission handling and reads, wrapping the `health` plugin |
| `lib/home_page.dart` | The single-screen UI |
| `test/exporter_test.dart` | Aggregation rules — the part worth testing |

To add a metric, add an entry to `kMetrics` and the matching
`android.permission.health.READ_*` line to `android/app/src/main/AndroidManifest.xml`.
