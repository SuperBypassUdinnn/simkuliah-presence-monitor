/// Purpose: Flutter client application entrypoint with responsive sidebar navigation, auto-refresh on focus, and desktop background operation.
/// Data & Logic Flow: Initializes widget tree, theme configurations, and root layout with tab focus auto-refresh; desktop additionally runs a realtime in-app alert service, hides to the system tray on window close, and keeps polling while hidden.
/// Key Components: SimkuliahApp, MainHomeScreen
import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_notification.dart';
import 'core/firebase_config.dart';
import 'core/refresh_bus.dart';
import 'core/supabase_config.dart';
import 'services/push_notification_service.dart';
import 'services/realtime_alert_service.dart';
import 'views/active_presence_view.dart';
import 'views/semester_matrix_view.dart';
import 'views/today_feed_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SupabaseConfig.initialize();
  } catch (e) {
    debugPrint('Supabase initialization note: $e');
  }
  try {
    await FirebaseConfig.initialize();
    await PushNotificationService.instance.initialize();
  } catch (e) {
    debugPrint('Push notification note: $e');
  }
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
    // Desktop window management: initialize before runApp so hide-on-close
    // and tray behavior can attach to the native window.
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'Simkuliah Monitor'),
      () async {
        await windowManager.show();
      },
    );
  }
  runApp(const SimkuliahApp());
}

class SimkuliahApp extends StatelessWidget {
  const SimkuliahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simkuliah Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen>
    with WidgetsBindingObserver, WindowListener, TrayListener {
  int _currentIndex = 0;
  RealtimeAlertService? _alertService;

  /// Stable, human-readable StatusNotifierItem id. Plasma keys the per-app
  /// tray settings (System Tray > Entries) by this id, so it must be stable
  /// across restarts, and Plasma displays the item under this name. A
  /// space-containing id is valid: e.g. Kate registers as "Kate Sessions".
  static const String _trayItemId = 'Simkuliah Monitor';

  /// Direct handle to the tray_manager plugin channel; see
  /// _setupDesktopBackground for why setIcon bypasses the package wrapper.
  static const MethodChannel _trayChannel = MethodChannel('tray_manager');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Desktop in-app realtime alerts. Android relies on the FCM push stack
    // instead, which also works while the app is backgrounded.
    if (!kIsWeb && !Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final service = RealtimeAlertService();
        service.start(onAlert: _showRealtimeAlert);
        setState(() {
          _alertService = service;
        });
      });
    }
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
      unawaited(_setupDesktopBackground());
    }
  }

  /// Enable background operation: the window close button hides the app to
  /// the system tray instead of quitting, so the realtime alert service
  /// keeps polling while hidden. Real exit happens via the tray menu.
  Future<void> _setupDesktopBackground() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    final iconPath = _trayIconPath();
    if (iconPath != null) {
      // Invoke the plugin channel directly instead of trayManager.setIcon:
      // the wrapper hardcodes 'id': shortid.generate(), so the
      // StatusNotifierItem id would be random per process and Plasma would
      // forget the user's tray visibility choice on every restart.
      await _trayChannel.invokeMethod<dynamic>('setIcon', <String, dynamic>{
        'id': _trayItemId,
        'iconPath': iconPath,
        'isTemplate': false,
        'iconPosition': 'left',
        'iconSize': 18,
      });
    }
    // The Linux (appindicator) plugin implements setIcon/setTitle/
    // setContextMenu only: no tooltip support, and right-click pops the
    // menu up natively.
    if (Platform.isWindows) {
      await trayManager.setToolTip('Simkuliah Monitor');
    }
    if (Platform.isLinux) {
      // The vendored plugin maps setTitle to app_indicator_set_title, i.e.
      // the SNI Title property Plasma displays as the tray entry name.
      await trayManager.setTitle(_trayItemId);
    }
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Buka Simkuliah Monitor'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Keluar'),
        ],
      ),
    );
  }

  /// AppIndicator on Linux needs an absolute icon file path; resolve the
  /// bundled asset next to the executable (bundle/data/flutter_assets
  /// layout shared by Linux and Windows builds).
  String? _trayIconPath() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final iconPath = '$exeDir/data/flutter_assets/assets/icons/tray_icon.png';
      if (File(iconPath).existsSync()) {
        return iconPath;
      }
    } catch (_) {
      // Fall through to the null case (tray without a custom icon).
    }
    return null;
  }

  @override
  void onWindowClose() async {
    // Keep running in the tray; the realtime alert service stays active.
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Linux pops the context menu natively via appindicator; only Windows
    // needs the explicit pop-up call.
    if (Platform.isWindows) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        windowManager.show();
        windowManager.focus();
      case 'exit':
        windowManager.destroy();
    }
  }

  /// Render one realtime alert in the overlay. Urgent alerts (lecturer opened
  /// presence, window closing) are sticky: no auto-dismiss, close button only.
  int _showRealtimeAlert(PresenceAlert alert) {
    final scheme = Theme.of(context).colorScheme;
    return AppNotification.show(
      context,
      title: alert.title,
      message: alert.message,
      color: alert.urgent ? scheme.error : scheme.primary,
      icon: alert.urgent
          ? Icons.notification_important_rounded
          : Icons.info_outline,
      duration: alert.urgent ? Duration.zero : const Duration(seconds: 4),
    );
  }

  @override
  void dispose() {
    unawaited(_alertService?.stop());
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Silent background refresh: views keep their cached content and swap
      // it in place, so regaining focus never flashes a loading spinner.
      RefreshBus.instance.requestRefresh();
    }
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
    // Tabs stay mounted in the IndexedStack; a silent refetch keeps their
    // data fresh without remounting.
    RefreshBus.instance.requestRefresh();
  }

  List<Widget> get _views => const [
    ActivePresenceView(),
    TodayFeedView(),
    SemesterMatrixView(),
  ];

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _onTabSelected(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  size: 20,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.asset(
                    'assets/icons/tray_icon.png',
                    width: 24,
                    height: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SIMKULIAH',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      'Presence Monitor',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Text(
              'MENU UTAMA',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
            ),
          ),

          // Menu Items
          _buildNavItem(
            index: 0,
            icon: Icons.timer_outlined,
            selectedIcon: Icons.timer,
            label: 'Presensi Aktif',
          ),
          _buildNavItem(
            index: 1,
            icon: Icons.calendar_today_outlined,
            selectedIcon: Icons.calendar_today,
            label: 'Jadwal Hari Ini',
          ),
          _buildNavItem(
            index: 2,
            icon: Icons.table_chart_outlined,
            selectedIcon: Icons.table_chart,
            label: 'Matriks Semester',
          ),

          const Spacer(),

          // Bottom User Card
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.4,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.2,
                  ),
                  child: Icon(
                    Icons.person,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Fadhlurrahman Alaudin',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '2408107010053',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            _buildSidebar(context),
            Expanded(
              child: IndexedStack(index: _currentIndex, children: _views),
            ),
          ],
        ),
      );
    }

    // Fallback bottom navigation on narrow mobile screen
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _views),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Presensi Aktif',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Jadwal Hari Ini',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_chart_outlined),
            selectedIcon: Icon(Icons.table_chart),
            label: 'Matriks Semester',
          ),
        ],
      ),
    );
  }
}
