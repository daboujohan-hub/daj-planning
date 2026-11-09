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
  'Maths': Color(0xFFA855F7), // violet
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
  Slot(1, 'Français', 8, 0, 10, 0),
  Slot(1, 'Maths', 10, 15, 11, 30),
  Slot(1, 'Cours', 13, 30, 18, 15),
  Slot(1, 'Anglais', 19, 30, 21, 0),
  // Mardi
  Slot(2, 'Français', 8, 0, 11, 30),
  Slot(2, 'Cours', 14, 15, 18, 15),
  Slot(2, 'Informatique', 19, 30, 21, 0),
  // Mercredi
  Slot(3, 'Cours', 7, 30, 9, 15),
  Slot(3, 'Français', 10, 30, 11, 30),
  Slot(3, 'Maths', 11, 30, 12, 30),
  Slot(3, 'Anglais', 14, 0, 17, 0),
  Slot(3, 'Informatique', 19, 0, 21, 0),
  // Jeudi
  Slot(4, 'Français', 8, 0, 10, 0),
  Slot(4, 'Maths', 10, 15, 11, 30),
  Slot(4, 'Cours', 13, 30, 18, 15),
  Slot(4, 'Anglais', 19, 30, 21, 0),
  // Vendredi
  Slot(5, 'Cours', 7, 15, 12, 0),
  Slot(5, 'Informatique', 14, 0, 17, 0),
  Slot(5, 'Français', 19, 0, 21, 0),
  // Samedi
  Slot(6, 'Français', 9, 0, 10, 45),
  Slot(6, 'Maths', 11, 0, 12, 0),
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

const Color fond = Color(0xFF0B0F14);
const Color gris = Color(0xFF9CA3AF);
const Color vert = Color(0xFF22C55E);
const List<String> mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];

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
        scaffoldBackgroundColor: fond,
        appBarTheme: const AppBarTheme(backgroundColor: fond, elevation: 0),
        colorScheme: ColorScheme.fromSeed(
          seedColor: vert,
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
      body: IndexedStack(
        index: tab,
        children: const [
          TodayScreen(),
          WeekScreen(),
          SoonScreen('Temps libre'),
          SoonScreen('Bilan'),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF111820),
        selectedItemColor: vert,
        unselectedItemColor: gris,
        currentIndex: tab,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.schedule), label: 'Aujourd\'hui'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Semaine'),
          BottomNavigationBarItem(icon: Icon(Icons.tv), label: 'Libre'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Bilan'),
        ],
      ),
    );
  }
}

class SoonScreen extends StatelessWidget {
  final String name;
  const SoonScreen(this.name, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('$name : bientôt disponible',
          style: const TextStyle(color: gris, fontSize: 16)),
    );
  }
}

class SlotRow extends StatelessWidget {
  final Slot slot;
  final String trailing;
  const SlotRow(this.slot, this.trailing, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: slot.color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: slot.color),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: slot.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.subject,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(slot.label, style: const TextStyle(fontSize: 13, color: gris)),
              ],
            ),
          ),
          Text(trailing,
              style: const TextStyle(fontSize: 12, color: Color(0xFFD1D5DB))),
        ],
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
  final Set<int> done = {};
  bool paused = false;

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

  String dur(int m) => m >= 60 ? '${m ~/ 60} h ${_two(m % 60)}' : '$m min';

  Widget feature(Slot s, int nowMin, bool running) {
    final total = s.endMin - s.startMin;
    final progress =
        running ? ((nowMin - s.startMin) / total).clamp(0.0, 1.0).toDouble() : 0.0;
    final info = running
        ? 'il reste ${dur(s.endMin - nowMin)}'
        : 'dans ${dur(s.startMin - nowMin)}';
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            running ? (paused ? 'EN PAUSE' : 'EN COURS') : 'PROCHAIN',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: s.color),
          ),
          const SizedBox(height: 6),
          Text(s.subject,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('${s.label} · $info',
              style: const TextStyle(color: Color(0xFFD1D5DB))),
          if (running) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFF1F2A37),
                color: s.color,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: const Color(0xFFF3F4F6),
                      side: const BorderSide(color: Color(0xFF6B7280)),
                      shape: shape,
                    ),
                    onPressed: () => setState(() => paused = !paused),
                    child: Text(paused ? 'Reprendre' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: s.color,
                      foregroundColor: const Color(0xFF04210F),
                      shape: shape,
                    ),
                    onPressed: () => setState(() {
                      done.add(schedule.indexOf(s));
                      paused = false;
                    }),
                    child: const Text('Terminé',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final today = schedule.where((s) => s.day == now.weekday).toList();

    bool isDone(Slot s) =>
        done.contains(schedule.indexOf(s)) || nowMin >= s.endMin;

    Slot? current;
    Slot? next;
    for (final s in today) {
      if (done.contains(schedule.indexOf(s))) continue;
      if (nowMin >= s.startMin && nowMin < s.endMin) {
        current ??= s;
      } else if (s.startMin > nowMin) {
        next ??= s;
      }
    }
    final featured = current ?? next;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Text('${now.day} ${mois[now.month - 1]}',
            style: const TextStyle(fontSize: 13, color: gris)),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(jours[now.weekday - 1],
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        ),
        if (featured != null)
          feature(featured, nowMin, featured == current)
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Journée terminée, bravo !',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        for (final s in today)
          if (s != featured)
            SlotRow(
              s,
              isDone(s)
                  ? 'Fait'
                  : 'Rappel ${hm((s.startMin - 10) ~/ 60, (s.startMin - 10) % 60)}',
            ),
        const SizedBox(height: 8),
        const Center(
          child: Text('Un pas à la fois, sans pression.',
              style: TextStyle(color: gris, fontSize: 14)),
        ),
      ],
    );
  }
}

class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const Text('Ma semaine',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        for (var d = 1; d <= 7; d++) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(jours[d - 1],
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in schedule.where((s) => s.day == d))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: s.color),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: s.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.subject,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          Text(s.label,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFD1D5DB))),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
