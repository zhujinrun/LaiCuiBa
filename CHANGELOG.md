# Changelog

All notable changes to LaiCuiBa are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); GitHub releases read
the section whose heading matches the pushed tag.

## [Unreleased]

### Fixed
- Catvod `type_name` / `vod_actor` fields that arrive comma-joined (ASCII or
  full-width) are now split into separate entries, like the usual slash-joined
  ones. The 分类 row shows one chip per genre instead of a single
  「剧情,喜剧,爱情,同性」 chip.
- Page content now uses a consistent 17px top inset: the home rails' 「查看全部」
  grid no longer places the first row flush against the header, and settings
  sub-pages no longer sit 35px down (their first card used to float well below
  the header compared with every other page).

## [0.1.3] - 2026-11-28

### Added
- `Space` toggles play/pause in the player, matching the original.
- Home rails now show every category a site declares. A source like 大师兄
  (电影/剧集/综艺/动漫/短剧/AI漫剧/少儿) used to lose its last two sections to
  a hard cap of five.

### Fixed
- Episode chips now size to their label (92px minimum, 180px maximum) instead
  of a hard 92px, so long movie version names such as 模范家庭47号：AK47 stay on
  one line instead of wrapping into a squashed two-line block. Overlong names
  ellipsize and show the full text in a tooltip.
- Player keyboard shortcuts now actually fire. The player and shell live in the
  same `FocusScope`, and Flutter grants `autofocus` only once per scope — the
  shell mounted first and consumed it, so the player's `autofocus: true` was
  ignored and focus stayed on the shell, where no arrow key reached the player's
  bindings. The player now owns a `FocusNode` and calls `requestFocus()` in a
  post-frame callback. `CallbackShortcuts` also has to wrap the `Focus` (it binds
  to descendant focus nodes only). Arrow up/down change volume by 10% (mouse
  wheel stays at 5%), left/right seek ±10 seconds, `P` toggles the mini window.
- `Ctrl+Alt+H` (boss key) now works while the player is open. The shell's
  shortcut scope cannot see the key once the player holds focus, so the player
  rebinds the same activator to the shell's own pause-and-minimize callback.
- Volume can now be raised to the original's 150% (default stays 100%); it was
  clamped to 100% in the stepper, slider and tests.
- Detail pages no longer overflow when the window is narrow. The hero used a
  fixed 386px band with an `OverflowBox` clip, and the six action pills sat in
  a `Row`, so shrinking the window produced a `RenderFlex` overflow (the
  yellow/black stripe). The hero now sizes to its content — still 386px at wide
  widths — and the pills keep their natural width and wrap like the episode
  chips. The 选集 chips keep a 92px minimum instead of stretching to the
  available width (which made a two-version film render each chip half a screen
  wide), and grow up to 180px for long names so they stay on one line.
- 演员阵容 wraps onto multiple rows like 选集 instead of a horizontal rail that
  cut off a long cast.
- Poster-card captions no longer overflow the home rail by ~0.2px at fractional
  card widths (14 × 1.43 = 20.02 against a 20px allowance); the caption line box
  is pinned to 20px.
- Dragging the window narrower no longer flashes yellow/black overflow stripes
  under poster captions. The card art animated its height over 160ms while
  `LcbRail` resized its tight-height slot immediately, so mid-drag frames left
  the art taller than the slot; the art height now tracks the window and only
  the hover shadow/lift animates.
- Paged home rails no longer bleed past the section header's band. The card
  list previously had only a left gutter and ran to the window edge, so a rail
  with a 查看全部 button looked ragged; its scroll viewport is now inset by the
  page gutter on both sides, matching the title .. 查看全部 span. The paging
  discs stay on the rail edge.
- Sidebar navigation highlights instantly on hover again. Its background used
  a 140ms `AnimatedContainer` — unlike every other hover surface in the shell —
  so a pointer crossing the rail only caught a half-faded grey that read as a
  flicker; it is a plain `Container` now, matching the original.
- 「浏览内容」 filter chips wrap onto multiple rows instead of a single
  non-scrollable line that hid and disabled every option past the panel's edge
  (a source like 大师兄 ships 17 years). The panel itself scrolls vertically
  now so a tall, wrapped filter list never overflows a short window.
- Detail-page dialogs (换平台 / 下载 / 收藏 / 追更 / 评论) follow the app's light
  theme again. They hard-coded a near-black background while their body text
  used the light theme's dark grey, leaving the panels unreadable; the dialogs
  now inherit the theme surface and the 评论 panel's white-on-black tokens were
  replaced with the matching light ones. Its title uses the same theme
  `titleLarge` style as the other dialogs instead of a smaller hard-coded size.
- Resource cards no longer carry Flutter's desktop drag handle (two bars on
  the trailing edge). The cards were already long-press draggable; the default
  handle is now disabled and the whole card is wrapped in a delayed drag
  listener on every platform, matching the original's clean card layout.
- The resource card's `⋯` menu now matches the original's grouped layout: the
  actions sit in a #F6F6F8 rounded card with inset 1px dividers on 50px rows,
  the title is 16/600, and the close control is a 28px grey disc instead of a
  bare xmark; 删除 stays red. Values were sampled from the original screenshot.
  The two extra actions (更换图标 / 放进分组) remain — they are real features in
  this build, not styling. Actionable rows now show the click cursor and an
  instant grey hover background; the disabled 设为当前资源 row stays flat.
- The 资源 page's first header tool icon now uses the original's slider glyph
  (three lines with knobs) instead of a plain hamburger.
- Source check notifications no longer stay on screen for minutes. The 重新检测
  and 测速进度 bars used a 2/10-minute `SnackBar.duration` as a stand-in for a
  manual close; an exception or an early `!context.mounted` return skipped the
  `hideCurrentSnackBar()`, and a notification raised mid-check pushed the bar
  down the queue where hiding the head left it to surface for its full length.
  A shared `runProgressSnackBar()` now catches errors, clears the whole queue
  before showing the result, and gives the progress bar a finite fallback
  duration so a hung probe cannot pin a message to the screen.
- The 资源 header's tool icons now match the 收藏 page's: transparent 28px
  tiles with a quiet glyph that darkens on hover, instead of permanently
  filled #F6F6F8 squares. Active modes (分组 / 搜索 / 多选) tint the glyph
  instead of the tile.

## [0.1.2] - 2026-11-27

### Added
- Player keyboard shortcuts: arrow up/down change volume, left/right seek
  ±10 seconds, and `P` toggles the mini window. The original's boss key
  (`Ctrl+Alt+H`) pauses and minimizes the window, with an in-app fallback
  instead of a system-wide hotkey.

### Fixed
- Detail pages render the source's `vod_pic` as a network image, so a cover
  visible on a continue-watching card also appears after opening it.
- The player no longer shows two buffering spinners at once; only the small
  one in the control bar remains.
- HLS ad removal now also covers the unmarked pods on 尚公主 高清线路1. That CDN
  splices ads with no marker and hash-named segments in the same directory, so
  the 0.1.1 marker/prefix rule missed it entirely. The cleaner now also detects
  the tight runs of discontinuities (2-3 segments apart, versus the show's
  normal 5+) that frame those pods, and removes the whole pod so the timeline
  stays continuous instead of jumping back to 00:00 at 04:58.
- HLS ad removal also covers the FF line's third splice shape: a single short
  ad pod (4-5 segments) isolated between much longer show stretches, again with
  no marker and hash-named segments. The cleaner now drops a short 2-8 segment
  discontinuity gap only when both neighbours are long (≥20 segments), so the
  regular 6-segment gaps on the RY line and the LZ line's 7/7/420 pattern are
  left untouched. Verified 699 → 690 segments with both 澳门新葡京 pods gone.

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
