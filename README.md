# LaiCuiBa

A self-maintained Flutter desktop media client, reimplemented from scratch to
stay close to BieCuiLe 1.0.6 (Windows) in look and feel while fixing the
playback defects that the original cannot escape.

> LaiCuiBa is an independent project. It shares no code with the original —
> that build is a Flutter AOT snapshot and cannot be decompiled. It reuses the
> upstream `libmpv` binary and the OFL-licensed title typeface; Node / Python
> runtimes are assembled from matching local installations.

## Requirements

| Component | Version | Why pinned |
| --- | --- | --- |
| Flutter | **3.44.9** | Same framework revision (`6b182d2`) as the original build |
| Dart | **3.12.2** | Shipped with Flutter 3.44.9 |
| Visual Studio 2022 + "Desktop development with C++" | 17.x | Windows runner |

The pin lives in three places and they must agree:

- `.fvmrc` — machine-readable, picked up by FVM
- `.flutter-version` — plain text, picked up by other version managers
- `pubspec.yaml` — `environment.sdk` / `environment.flutter`

Check the active toolchain before you build:

```bash
dart run tool/verify_toolchain.dart
```

It exits non-zero and tells you what to install if anything drifts. Flutter
differences are not cosmetic here: Material 3 metrics and text layout shift
between minors, which invalidates the screenshot comparisons in `.probe/`.

## Run

```bash
flutter pub get
bash tool/sync_runtime.sh      # assemble Node 18 / Python 3.11 runtime
flutter run -d windows          # hot reload
flutter build windows --debug   # build/windows/x64/runner/Debug/LaiCuiBa.exe
flutter test                    # smoke tests
```

## Layout

```
lib/
  core/       theme tokens (colors, metrics, typography)
  models/     domain models
  services/   data sources; demo fixtures for now
  ui/
    shell.dart          sidebar + top bar + page switching
    pages/              home, resources, favorites, history, settings
    widgets/            hero banner, media card, poster art, title bar
tool/         developer scripts (toolchain check)
windows/      Win32 runner, frameless window
android/      Android runner (phone / TV)
assets/fonts/ LcbSerif (SIL OFL 1.1)
```

`.probe/` (one level up) holds the reverse-engineering evidence: the original
screenshots used as pixel baselines, the extracted source-file inventory, and
the window automation scripts.

See `ARCHITECTURE.md` for the module map, the reconstruction limits, and the
five-phase roadmap.
