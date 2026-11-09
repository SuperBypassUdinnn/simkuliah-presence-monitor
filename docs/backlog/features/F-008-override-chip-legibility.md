# Feature Log: F-008 Override Chip Legibility

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: #9
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
The `Jadwal Hari Ini` override chips carried leading icons, the selected state
was not prominent enough, and the slate `Dosen Tidak Absen` color read like a
disabled button. Make the chips text-only and give every state clear contrast.

## 2. Implementation Checklist
- [x] Remove leading icons from lecture-card override chips.
- [x] Add a white selected border, bold label, and elevation.
- [x] Lighten unselected accents on dark surfaces.
- [x] Change `Dosen Tidak Absen` to teal `#0D9488`.
- [x] Raise `Keterangan:` banner contrast on dark surfaces.

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No warnings |
| `dart format --output=none --set-exit-if-changed .` | PASS | Formatted |
| `flutter test` | PASS | Widget suite green |
| `python3 scripts/verify_pipeline.py` | PASS | Full local gate |
