# Changelog

Personal, sideload-only. Versions are milestones for my own reference rather
than published releases.

## 1.2.1 — 2026-09-21

### Fixed

- **Health Connect's "Read privacy policy" link now opens the privacy policy.**
  It used to open the app itself, since there was no policy to link to. It now
  opens the privacy page on the website in your browser. The browser does the
  fetching, so the app still requests no internet permission.

### Outside the app

Not part of the APK, but new in the repository since 1.2.0:

- **A website**, at https://david-williston.github.io/copy-fit/, explaining how
  the app works, how to install it, and its privacy policy. It shows the latest
  release and the commit it was built from, and republishes itself whenever a
  release is published.
- **`tool/make_icon.py`**, which generates the launcher icon, the README logo
  and the website's images, and refuses any design a launcher would crop.

## 1.2.0 — 2026-09-20

### Added

- **24-hour and 3-day ranges**, for exporting to a coach every morning. The
  last 24 hours is now the default: exported in the morning it returns last
  night's sleep and nothing older, so each day's paste adds only what is new.
- **A launcher icon and logo**, replacing the default Flutter icon: two
  overlapping sheets, the copy symbol, with a pulse line on the front one.

### Changed

- The 24-hour range is **rolling**, counting back from the moment of export,
  while every other range still covers whole calendar days. Because a rolling
  window starts mid-day, its export reports the exact `from` and `to` instead
  of dates, and notes that the edge days' totals may be partial. Sleep is
  unaffected: a session comes back whole or not at all.
- A range saved by an earlier version is carried over. The new default only
  applies to fresh installs, so an existing install keeps its last choice
  until a different range is picked.

### Fixed

- Calendar ranges could start an hour off midnight when they crossed a
  daylight-saving change, because the window was built by subtracting
  `Duration(days:)`. They are now built from dates. This never affected
  timezones that keep one offset all year.

## 1.1.1 — 2026-09-20

### Fixed

- Sleep stages are matched to their session by **uuid** instead of by interval
  containment. Health Connect gives every stage its parent session's uuid, so
  the parentage was available all along and did not need to be inferred.
  Interval matching took the first session whose window contained the stage,
  so if two sources logged the same night and one session nested inside the
  other, the inner session's stages were handed to the outer one. Containment
  survives only as a fallback, for a stage whose session began before the
  queried window.

Exports are unchanged with a single data source and non-overlapping nights.

## 1.1.0 — 2026-09-20

### Added

- The app bar shows the running version, read from the platform at runtime so
  it cannot drift from `pubspec.yaml`. Before this, every build since the
  initial scaffold installed as `1.0.0+1` and there was no way to tell from
  the phone which one was running.

## 1.0.0 — 2026-09-20

First working version.

### Added

- Reads Android Health Connect and copies the result to the clipboard as JSON.
  Read-only and offline: no network code, and data leaves the phone only
  through the clipboard or the share sheet.
- 27 metrics across activity, heart, sleep, body, vitals and intake, each
  declaring how it aggregates — summed, min/avg/max, averaged, or last reading
  of the day.
- Two output shapes: a daily summary compact enough to paste into a chat, and
  raw points for examining a short range in detail. The result card reports
  byte size and an approximate token count before anything is copied.
- Sleep resolved by session: `main_sleep`, `naps` and day totals, with each
  session keeping its own start, end and stage breakdown.
- A Diagnostics card listing every Health Connect type separately with its
  count, permission state, dates covered, source and error. An empty result is
  otherwise identical whether it was denied, unsupported, capped or genuinely
  absent.
- Settings persisted to `shared_preferences` as they change.

### Known limits

- Health Connect caps reads at 30 days without the historical-data permission,
  which the app checks on launch and requests when a longer range is chosen.
  Granting it does not create history that was never written: if the source
  app only ever populated the last 30 days, a 90-day export still returns 30.
- The metric catalog and the Android manifest must be kept in sync by hand. A
  metric without its `READ_*` permission fails silently at runtime, though the
  Diagnostics card shows it as denied.
