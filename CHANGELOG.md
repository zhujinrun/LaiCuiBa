# Changelog

All notable changes to LaiCuiBa are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); GitHub releases read
the section whose heading matches the pushed tag.

## [Unreleased]

## [0.1.1] - 2026-11-27

### Fixed
- HLS mid-roll ad pods are removed before mpv sees the playlist, so an injected
  ad no longer changes the timeline and sends the progress bar back to 00:00.
  Playlists are fetched through a loopback cleaner that drops the ad marker,
  its TS segments and both discontinuities; the remaining segments keep their
  original URLs and headers.
- The player header's episode-count label is rendered as `共N集` instead of the
  source's `第N集` / `全N集`, matching the original app.

## [0.1.0] - 2026-11-27

### Fixed
- Playback now remembers the working line by name instead of falling back to
  the default line after reopening a title; history rows without a line flag
  are handled with a settings-based fallback.
- Opening a title from history keeps the usable poster when the fresh detail
  response has no image.

### Added
- Favorites page: 追剧 empty state with Trakt login information, inline search,
  new/manage folder dialogs, poster `...` menu with 取消收藏, and the
  original header glyphs.
- History page: right-click batch selection (已选 / 全选 / 删除 / 完成), a
  two-column 347px card grid with progress bars, and detail-page resume from
  the row's action button.
- Settings page: root rows and all first-level sub-pages aligned with the
  original, including per-page header icons, lower-half rows in 播放 and
  媒体徽章, and persisted toggles for every exposed switch.
- GitHub Actions release flow: a `vX.Y.Z` tag builds Windows and Android
  artifacts, reads this changelog, and publishes a GitHub Release.

### Changed
- Settings sub-pages no longer show the global search box; the header follows
  the original's per-page tool icons.
- Removed settings rows that did not exist in the original; their behaviour is
  still covered by direct store tests.
