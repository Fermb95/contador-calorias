import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'db.dart';
import 'notifications.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/today_screen.dart';
import 'state.dart';
import 'util.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.init();
  await app.init();
  try {
    await Notif.init();
  } catch (e) {
    debugPrint('Notificaciones no disponibles: $e');
  }
  runApp(const BalanceApp());
}

ThemeData _theme(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32), brightness: b);
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

class BalanceApp extends StatelessWidget {
  const BalanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Balance',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Root(),
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => app.profile == null ? const ProfileScreen(firstTime: true) : const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  DateTime _lastDay = today();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _onOpen() async {
    final p = app.profile;
    if (p == null) return;
    try {
      await Notif.scheduleReminders(p);
    } catch (_) {}
    await app.refreshSummary();
    if (p.hcEnabled) await app.syncHealth();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Si cambió el día mientras la app estaba en segundo plano, pasamos a hoy.
      final now = today();
      if (!sameDay(_lastDay, now)) {
        if (sameDay(app.date, _lastDay)) app.setDate(now);
        _lastDay = now;
        if (app.profile != null) Notif.scheduleReminders(app.profile!);
      }
      app.refreshSummary();
      if (app.profile?.hcEnabled ?? false) app.syncHealth();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        body: IndexedStack(
          index: app.tab,
          children: const [TodayScreen(), HistoryScreen(), ProgressScreen(), SettingsScreen()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: app.tab,
          onDestinationSelected: app.setTab,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Diario'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Histórico'),
            NavigationDestination(icon: Icon(Icons.monitor_weight_outlined), selectedIcon: Icon(Icons.monitor_weight), label: 'Peso'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
          ],
        ),
      ),
    );
  }
}
