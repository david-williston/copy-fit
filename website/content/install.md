---
title: "Install"
description: "Copy Fit is sideload-only. Here is how to get it onto your phone."
---

Copy Fit isn't on the Play Store. You install it yourself from an APK file.

## What you need

- An Android phone running **Android 9 or later**, with a 64-bit processor —
  almost every phone from the last several years
- **Health Connect**, which is built into Android 14 and later, and a free Play
  Store app before that
- An app that writes health data into Health Connect, such as Fitbit

## Install it

1. Download the APK from the
   [latest release](https://github.com/david-williston/copy-fit/releases/latest).
2. Open it on your phone and allow installing from that source when Android
   asks. Or, with the phone connected to a computer:

   ```sh
   adb install -r copy-fit-*-arm64-v8a.apk
   ```

3. Open Copy Fit, tap **Read Health Connect**, and grant access to the data you
   want to export.

Android will warn that the app comes from an unknown developer. That is
expected: the APK is signed with a development key rather than one registered
with Google, as sideloaded builds usually are.

## Exporting more than 30 days

Health Connect only lets an app read the last 30 days unless you also grant
access to past data. Copy Fit asks for it when you pick a longer range.
Granting it can't recover history that was never written, though: if your
tracker only started syncing a month ago, a 90-day export still returns a month.

## Updating

Install a newer APK over the old one. Your settings and permissions carry over.

## Building it yourself

The source, with build instructions, is
[on GitHub](https://github.com/david-williston/copy-fit).
