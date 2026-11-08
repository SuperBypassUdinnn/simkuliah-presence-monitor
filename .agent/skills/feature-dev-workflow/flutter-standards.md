# Flutter Multi-Platform Standards

## 1. Multi-Platform Support
- Codebase must compile and run seamlessly on **Android**, **Linux (GTK)**, and **Windows (Win32/WinUI)**.
- Platform-specific integrations (e.g. system notifications, secure storage) must use cross-platform plugins.

## 2. State & Widget Lifecycle
- Maintain clean separation between Models (`lib/models/`), Services (`lib/services/`), and Views (`lib/views/`).
- **BuildContext Safety**: Always guard async callbacks with `if (!context.mounted) return;` before calling `setState`, `Navigator`, or `ScaffoldMessenger`.
- **Future Memoization**: Do NOT invoke asynchronous fetch methods directly inside `FutureBuilder(future: ...)` in `build()`. Hoist futures into `StatefulWidget`'s `initState` or memoize them to prevent refetch churn on rebuilds.
- **Timer Cleanup**: Always cancel running `Timer` instances in `dispose()` (e.g. in countdown widgets) to prevent memory leaks.

## 3. UI Composition & Material 3
- Enforce `useMaterial3: true` in `ThemeData`.
- Use `ChoiceChip` / `FilterChip` for local status selection (Izin, Sakit, Alpa).
- Provide optimistic local state updates with graceful rollback and user-facing snackbar feedback on failure.

## 4. Architecture Headers
Every non-trivial Dart file must feature:
```dart
/// Purpose: <description>
/// Data & Logic Flow: <inputs -> pipeline -> outputs>
/// Key Components: <primary classes/widgets>
```
Maintain visual breathing room with proper indentation and run `dart format .` before commit.
