/// Purpose: Shared visual metadata (label, letter, color, icon) for manual override types.
/// Data & Logic Flow: Maps override type keys to consistent palette used by matrix tiles and lecture cards.
/// Key Components: OverrideStyle
import 'package:flutter/material.dart';

/// Visual identity of a single manual override status.
class OverrideStyle {
  /// Database key (e.g. `lupa_absen`).
  final String type;

  /// Human-readable label (e.g. `Lupa Absen`).
  final String label;

  /// Single-letter badge used in the compact semester matrix cell.
  final String letter;

  /// Solid accent color for the status.
  final Color color;

  /// Icon representing the status.
  final IconData icon;

  const OverrideStyle({
    required this.type,
    required this.label,
    required this.letter,
    required this.color,
    required this.icon,
  });

  static const OverrideStyle izin = OverrideStyle(
    type: 'izin',
    label: 'Izin',
    letter: 'I',
    color: Color(0xFF2563EB),
    icon: Icons.event_available,
  );

  static const OverrideStyle sakit = OverrideStyle(
    type: 'sakit',
    label: 'Sakit',
    letter: 'S',
    color: Color(0xFFD97706),
    icon: Icons.local_hospital_outlined,
  );

  static const OverrideStyle alpa = OverrideStyle(
    type: 'alpa',
    label: 'Alpa',
    letter: 'A',
    color: Color(0xFF991B1B),
    icon: Icons.person_off_outlined,
  );

  static const OverrideStyle lupaAbsen = OverrideStyle(
    type: 'lupa_absen',
    label: 'Lupa Absen',
    letter: 'L',
    color: Color(0xFF9333EA),
    icon: Icons.alarm_off,
  );

  static const OverrideStyle dosenTidakAbsen = OverrideStyle(
    type: 'dosen_tidak_absen',
    label: 'Dosen Tidak Absen',
    letter: 'D',
    color: Color(0xFF475569),
    icon: Icons.badge_outlined,
  );

  /// All override styles in display order.
  static const List<OverrideStyle> all = [
    izin,
    sakit,
    alpa,
    lupaAbsen,
    dosenTidakAbsen,
  ];

  /// Resolve a style from a database override key; falls back to [izin].
  static OverrideStyle of(String? type) {
    final normalized = type?.toLowerCase().replaceAll(' ', '_');
    for (final style in all) {
      if (style.type == normalized) return style;
    }
    return izin;
  }
}
