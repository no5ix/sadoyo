# 0012. The compact island grows to fit a name

- Status: accepted
- Date: 2026-11-22
- Context: the closed island shows a name for several activities - a connected
  accessory, a keyboard input source, a new song, a watched area. Every one of
  them was being cut off. Three separate causes were found, all in the
  measurement that decides how wide a strip is allowed to be:
  1. A notice's wings were measured with `NSString.size` and then given back to
     SwiftUI as an exact frame, with no tolerance. AppKit's measure is under a
     point narrower than what SwiftUI draws at 11-12 pt (its tracking, shaping
     and rounding), so a name that "fit the maths" lost its last glyph. The
     notification banner already carries a 6 pt tolerance
     (`NotchNotificationBannerLayout.air`); the plain notices never got one.
  2. Each wing had a fixed width cap - 160 pt for an accessory, 240 pt for the
     rest, 340 pt for a whole capsule row - imposed before the name was read.
     Real device names reach 140-170 pt at 11 pt, so a watch, a pair of
     earbuds, a long input-source name or a long song title was truncated in
     the middle or at the tail, on displays with room to spare.
  3. In the floating capsule's row, the label ("Connected", "Copied", a
     source's short code) carried the layout priority and the name carried
     none, so the row shortened the name - the only part worth reading.
- Decision: a name's own words decide how wide its strip is.
  - Every compact text measure carries the banner's tolerance
    (`NotchNotice.textAir`, `NotchCapsuleLayout.air`).
  - A notice that names a thing (`.accessory`, `.inputSource`, `.track`,
    `.watch`) gets `NotchNotice.nameWingBudget`; a notice carrying a phrase
    (a copied preview, a status, a reading) keeps `phraseWingBudget`. The
    design maxima in `NotchCapsuleLayout.Maximum` are raised above what a name
    needs and are there to bound paragraphs, not names. What limits a name is
    the room the display and the menus leave - `NotchGeometry.noticeWings` and
    `NotchCapsuleLayout.availableWidth` - which is the honest physical limit.
  - The name takes the layout priority in a capsule row; a label gives way
    first.
  - A new song names itself in the closed island: the `.track` notice is
    presented again when playback settles, the strip names the song for
    `musicTitleDuration`, and a notched strip that names its song grows its
    leading wing (`NotchMusicStripLayout.namedWings`) with the island. Naming
    is skipped when the menus leave no room, which is the pre-existing
    graceful path.
- Consequences: the island is wider for a long name than it was; on a display
  with menus crowded, a long name is the thing that gives way, and the music
  strip falls back to cover and bars. Truncation remains for text longer than
  the bar - a clipboard preview, a 700-character device name - where the wing
  budgets and the display edge apply, with the full string kept in the
  accessibility label and in `help` text. The tolerance widens every measured
  row by 4 pt per string, which the "no band of empty black" contracts allow
  (they measure content, not padding).
- Related code: `Sources/Vorssaint/Services/Notch/NotchService.swift`
  (`NotchNotice.preferredWings`, `musicStripNamesSong`, `namedMusicWings`,
  `scheduleTrackNotice`, `nameCapsuleSong`, `capsuleStripSize`),
  `Sources/Vorssaint/Services/Notch/NotchSupport.swift`
  (`NotchCapsuleLayout.air`, `Maximum`, `NotchMusicStripLayout.maximumWing`),
  `Sources/Vorssaint/UI/Notch/NotchNoticeView.swift`,
  `Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift`,
  `Sources/Vorssaint/UI/Notch/NotchMusicStrip.swift`.
  Tests: `Tests/NotchTests.swift` (`noticeLayoutContracts`, music naming),
  `Tests/NotchCapsuleTests.swift`.
