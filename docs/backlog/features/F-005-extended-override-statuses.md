# Feature Log: F-005 Extended Override Statuses & Matrix Indicators

- **Parent Plan**: [`.planning/02-presence-sync-and-override-ux.md`](../../../.planning/02-presence-sync-and-override-ux.md)
- **Target Issue**: #5
- **Status**: In Progress
- **Author**: AI Agent / Developer

## 1. Problem Statement & Scope
Every manual override shared one generic color in the semester matrix, and only
`izin`, `sakit`, and `alpa` were supported. Add `lupa_absen` and
`dosen_tidak_absen`, then give each status a distinct letter, icon, and color.

## 2. Implementation Checklist
- [x] Extend backend `OverrideType` and webhook validation.
- [x] Add migration `20261109020000_widen_override_type.sql`.
- [x] Add shared `OverrideStyle` palette in the Flutter client.
- [x] Render distinct compact matrix cells and override chips.
- [x] Apply the palette to banners, dialogs, and snackbars.

## 3. Objective Verification Matrix
| Command | Result | Notes |
| :--- | :--- | :--- |
| `flutter analyze --no-pub` | PASS | No warnings |
| `flutter test` | PASS | Model formatting covered |
| `ruff check backend` | PASS | Enum and validation clean |
| `pytest -q` | PASS | Override enum assertions updated |
