import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ───────────────────────── Données ─────────────────────────

const Map<String, Color> couleurs = {
  'Français': Color(0xFF3B82F6), // bleu
  'Anglais': Color(0xFFEF4444), // rouge
  'Informatique': Color(0xFF22C55E), // vert
  'Technologie': Color(0xFFF97316), // orange
  'Cours': Color(0xFF9CA3AF), // gris
};

const List<String> jours = [
  'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
];

class Slot {
  final int day; // 1 = lundi ... 7 = dimanche
  final String subject;
  final int sh, sm, eh, em;
  const Slot(this.day, this.subject, this.sh, this.sm, this.eh, this.em);

  int get startMin => sh * 60 + sm;
  int get endMin => eh * 60 + em;
  Color get color => couleurs[subject] ?? Colors.grey;
  String get label => '${hm(sh, sm)} → ${hm(eh, em)}';
}

String _two(int n) => n.toString().padLeft(2, '0');
String hm(int h, int m) => '${_two(h)}h${_two(m)}';

const List<Slot> schedule = [
  // Lundi
  Slot(1, 'Français', 8, 0, 11, 30),
  Slot(1, 'Cours', 13, 30, 18, 15),
  Slot(1, 'Anglais', 19, 30, 21, 0),
  // Mardi
  Slot(2, 'Français', 8, 0, 11, 30),
  Slot(2, 'Cours', 14, 15, 18, 15),
  Slot(2, 'Informatique', 19, 30, 21, 0),
  // Mercredi
  Slot(3, 'Cours', 7, 30, 9, 15),
  Slot(3, 'Français', 10, 30, 12, 30),
  Slot(3, 'Anglais', 14, 0, 17, 0),
  Slot(3, 'Informatique', 19, 0, 21, 0),
  // Jeudi
  Slot(4, 'Français', 8, 0, 11, 30),
  Slot(4, 'Cours', 13, 30, 18, 15),
  Slot(4, 'Anglais', 19, 30, 21, 0),
  // Vendredi
  Slot(5, 'Cours', 7, 15, 12, 0),
  Slot(5, 'Informatique', 14, 0, 17, 0),
  Slot(5, 'Français', 19, 0, 21, 0),
  // Samedi
  Slot(6, 'Français', 9, 0, 12, 0),
  Slot(6, 'Anglais', 14, 0, 17, 0),
  Slot(6, 'Technologie', 19, 0, 21, 0),
  // Dimanche
  Slot(7, 'Français', 9, 0, 12, 0),
  Slot(7, 'Informatique', 14, 0, 17, 0),
  Slot(7, 'Anglais', 19, 0, 21, 0),
];

// ───────────────────────── Alarmes ─────────────────────────

final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();

const NotificationDetails _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'daj_slots',
    'Créneaux DAJ',
    channelDescription: 'Rappels de tes créneaux d\'étude',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    playSound: true,
    enableVibration: true,
  ),
);

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await plugin.initialize(init);
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.requestNotificationsPermission();
  await android?.requestExactAlarmsPermission();
}

Future<void> _zoned(int id, String title, String body, DateTime local,
    {DateTimeComponents? repeat}) async {
  // On passe par l'heure UTC : l'instant est exact, et on replanifie
  // à chaque ouverture de l'appli (donc pas de dérive).
  final when = tz.TZDateTime.from(local, tz.UTC);
  Future<void> go(AndroidScheduleMode mode) => plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        _details,
        androidScheduleMode: mode,
        matchDateTimeComponents: repeat,
      );
  try {
    await go(AndroidScheduleMode.exactAllowWhileIdle);
  } catch (_) {
    await go(AndroidScheduleMode.inexactAllowWhileIdle);
  }
}

/// Planifie un rappel chaque semaine, [minutesBefore] min avant chaque créneau.
Future<void> scheduleAll({int minutesBefore = 10}) async {
  await plugin.cancelAll();
  final now = DateTime.now();
  for (var i = 0; i < schedule.length; i++) {
    final s = schedule[i];
    var d = DateTime(now.year, now.month, now.day, s.sh, s.sm - minutesBefore);
    while (d.weekday != s.day || !d.isAfter(now)) {
      d = DateTime(d.year, d.month, d.day + 1, d.hour, d.minute);
    }
    await _zoned(
      i,
      '${s.subject} dans $minutesBefore min',
      s.label,
      d,
      repeat: DateTimeComponents.dayOfWeekAndTime,
    );
  }
}

Future<void> testAlarm() async {
  await _zoned(999, 'Test DAJ Planning', 'Si tu vois ça, les rappels marchent ✔',
      DateTime.now().add(const Duration(seconds: 10)));
}

// ───────────────────────── Interface ─────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  unawaited(scheduleAll());
  runApp(const DajApp());
}

class DajApp extends StatelessWidget {
  const DajApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAJ Planning',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B0F14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22C55E),
          brightness: Brightness.dark,
        ),
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DAJ Planning'),
        actions: [
          IconButton(
            tooltip: 'Tester un rappel (10 s)',
            icon: const Icon(Icons.alarm_add),
            onPressed: () async {
              await testAlarm();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Rappel test dans 10 secondes. Ferme l\'appli !')),
              );
            },
          ),
        ],
      ),
      body: tab == 0 ? const TodayScreen() : const WeekScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Aujourd\'hui'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Semaine'),
        ],
      ),
    );
  }
}

class SlotTile extends StatelessWidget {
  final Slot slot;
  final bool active;
  const SlotTile(this.slot, {super.key, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: slot.color.withOpacity(active ? 0.35 : 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: slot.color, width: active ? 2.5 : 1),
      ),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: slot.color, radius: 8),
        title: Text(slot.subject,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(slot.label),
        trailing: active ? const Text('EN COURS') : null,
      ),
    );
  }
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final today = schedule.where((s) => s.day == now.weekday).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(jours[now.weekday - 1],
              style: Theme.of(context).textTheme.headlineMedium),
        ),
        for (final s in today)
          SlotTile(s, active: nowMin >= s.startMin && nowMin < s.endMin),
        const SizedBox(height: 12),
        const Center(child: Text('Un pas à la fois, sans pression 🌱')),
      ],
    );
  }
}

class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (var d = 1; d <= 7; d++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(jours[d - 1],
                style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final s in schedule.where((s) => s.day == d)) SlotTile(s),
        ],
      ],
    );
  }
}
