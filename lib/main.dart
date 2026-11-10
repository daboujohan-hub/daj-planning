import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'extras.dart';

// ───────────────────────── Données ─────────────────────────

const List<String> matieres = [
  'Français', 'Maths', 'Anglais', 'Informatique', 'Technologie'
];

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

const List<String> mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];

const List<String> encouragements = [
  'Un pas à la fois, sans pression.',
  'Petit à petit, tu construis ton avenir.',
  'Chaque minute d\'étude compte.',
  'Tu n\'as pas besoin d\'être parfait, seulement de continuer.',
  'Aujourd\'hui, tu apprends quelque chose de nouveau.',
  'La régularité bat l\'intensité.',
  'Respire, concentre-toi, avance.',
  'Un développeur, c\'est quelqu\'un qui apprend tous les jours.',
  'Une pause fait aussi partie du travail.',
  'Tes efforts d\'aujourd\'hui préparent ton demain.',
  'Fier de toi : tu es là, et c\'est déjà beaucoup.',
  'Une petite victoire vaut mieux qu\'un grand plan oublié.',
  'Doucement mais sûrement.',
  'Tu avances, même quand tu ne le vois pas.',
];

String _two(int n) => n.toString().padLeft(2, '0');
String hm(int h, int m) => '${_two(h)}h${_two(m)}';
String dk(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String fmtDur(int m) => '${m ~/ 60} h ${_two(m % 60)}';
String dur(int m) => m < 60 ? '$m min' : fmtDur(m);

DateTime pd(String s) {
  final p = s.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String messageDuJour(DateTime d) {
  final doy = d.difference(DateTime(d.year, 1, 1)).inDays;
  return encouragements[doy % encouragements.length];
}

class Slot {
  final int day; // 1 = lundi ... 7 = dimanche
  final String subject;
  final int sh, sm, eh, em;
  const Slot(this.day, this.subject, this.sh, this.sm, this.eh, this.em);

  factory Slot.fromJson(Map<String, dynamic> j) => Slot(j['d'] as int,
      j['s'] as String, j['a'] as int, j['b'] as int, j['c'] as int, j['e'] as int);

  Map<String, dynamic> toJson() =>
      {'d': day, 's': subject, 'a': sh, 'b': sm, 'c': eh, 'e': em};

  int get startMin => sh * 60 + sm;
  int get endMin => eh * 60 + em;
  int get minutes => endMin - startMin;
  Color get color => couleurs[subject] ?? Colors.grey;
  String get label => '${hm(sh, sm)} → ${hm(eh, em)}';
  String get key => '$day|$subject|$sh:$sm';
}

const List<Slot> defaultSchedule = [
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
  Slot(3, 'Maths', 14, 0, 16, 0),
  Slot(3, 'Technologie', 16, 0, 17, 0),
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
  Slot(6, 'Technologie', 14, 0, 17, 0),
  Slot(6, 'Technologie', 19, 0, 21, 0),
  // Dimanche
  Slot(7, 'Français', 9, 0, 12, 0),
  Slot(7, 'Informatique', 14, 0, 17, 0),
  Slot(7, 'Anglais', 19, 0, 21, 0),
];

/// Un créneau terminé (fait ou rattrapé).
class Rec {
  final String date, key, subject;
  final int minutes;
  const Rec(this.date, this.key, this.subject, this.minutes);

  factory Rec.fromJson(Map<String, dynamic> j) => Rec(
      j['d'] as String, j['k'] as String, j['s'] as String, j['m'] as int);

  Map<String, dynamic> toJson() =>
      {'d': date, 'k': key, 's': subject, 'm': minutes};
}

class Missed {
  final DateTime date;
  final Slot slot;
  const Missed(this.date, this.slot);
}

// ───────────────────────── État + sauvegarde ─────────────────────────

class AppState extends ChangeNotifier {
  SharedPreferences? _p;
  List<Slot> slots = List<Slot>.of(defaultSchedule);
  List<Rec> recs = [];
  int reminder = 10;
  Map<String, int> goals = {};

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      final s = p.getString('slots');
      if (s != null) {
        slots = (jsonDecode(s) as List)
            .map((e) => Slot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      final r = p.getString('recs');
      if (r != null) {
        recs = (jsonDecode(r) as List)
            .map((e) => Rec.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      reminder = p.getInt('reminder') ?? 10;
      final g = p.getString('goals');
      if (g != null) {
        goals = (jsonDecode(g) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toInt()));
      }
    } catch (_) {
      // données illisibles : on repart des valeurs par défaut
    }
  }

  // ----- créneaux terminés -----

  bool isDone(String date, Slot s) =>
      recs.any((r) => r.date == date && r.key == s.key);

  Future<void> markDone(DateTime d, Slot s, {int? minutes}) async {
    final date = dk(d);
    if (isDone(date, s)) return;
    recs = [...recs, Rec(date, s.key, s.subject, minutes ?? s.minutes)];
    notifyListeners();
    await _p?.setString('recs', jsonEncode(recs.map((r) => r.toJson()).toList()));
  }

  /// Créneaux d'étude finis depuis moins de 48 h et pas faits.
  List<Missed> missed(DateTime now) {
    final out = <Missed>[];
    for (var back = 0; back <= 2; back++) {
      final d = DateTime(now.year, now.month, now.day - back);
      for (final s in slots.where((s) => s.day == d.weekday && s.subject != 'Cours')) {
        final end = DateTime(d.year, d.month, d.day, s.eh, s.em);
        if (end.isAfter(now)) continue;
        if (now.difference(end) > const Duration(hours: 48)) continue;
        if (isDone(dk(d), s)) continue;
        out.add(Missed(d, s));
      }
    }
    return out;
  }

  // ----- séries -----

  Set<String> _studyDays() =>
      recs.where((r) => r.subject != 'Cours').map((r) => r.date).toSet();

  int streak(DateTime now) {
    final days = _studyDays();
    var d = DateTime(now.year, now.month, now.day);
    if (!days.contains(dk(d))) d = DateTime(d.year, d.month, d.day - 1);
    var n = 0;
    while (days.contains(dk(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  int bestStreak() {
    final list = _studyDays().map(pd).toList()..sort();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final d in list) {
      if (prev != null && d.difference(prev).inDays == 1) {
        cur++;
      } else {
        cur = 1;
      }
      if (cur > best) best = cur;
      prev = d;
    }
    return best;
  }

  // ----- objectifs -----

  int scheduledMinutes(String subject) => slots
      .where((s) => s.subject == subject)
      .fold(0, (a, s) => a + s.minutes);

  int goalFor(String subject) {
    final g = goals[subject];
    if (g != null) return g;
    final h = (scheduledMinutes(subject) / 60).round();
    return h < 1 ? 1 : h;
  }

  Future<void> setGoal(String subject, int hours) async {
    goals = {...goals, subject: hours};
    notifyListeners();
    await _p?.setString('goals', jsonEncode(goals));
  }

  // ----- réglages -----

  Future<void> setReminder(int minutes) async {
    reminder = minutes;
    notifyListeners();
    await _p?.setInt('reminder', minutes);
    unawaited(scheduleAll(slots, reminder));
  }

  // ----- emploi du temps -----

  Future<void> _slotsChanged() async {
    notifyListeners();
    await _p?.setString('slots', jsonEncode(slots.map((s) => s.toJson()).toList()));
    unawaited(scheduleAll(slots, reminder));
  }

  Future<void> saveSlot(Slot? old, Slot nw) async {
    final list = List<Slot>.of(slots);
    final i = old == null ? -1 : list.indexWhere((s) => s.key == old.key);
    if (i >= 0) {
      list[i] = nw;
    } else {
      list.add(nw);
    }
    list.sort((a, b) => a.day != b.day ? a.day - b.day : a.startMin - b.startMin);
    slots = list;
    await _slotsChanged();
  }

  Future<void> deleteSlot(Slot old) async {
    slots = slots.where((s) => s.key != old.key).toList();
    await _slotsChanged();
  }

  Future<void> resetSlots() async {
    slots = List<Slot>.of(defaultSchedule);
    notifyListeners();
    await _p?.remove('slots');
    unawaited(scheduleAll(slots, reminder));
  }
}

final AppState state = AppState();

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

/// Un rappel chaque semaine avant chaque créneau + le bilan du dimanche soir.
Future<void> scheduleAll(List<Slot> slots, int minutesBefore) async {
  await plugin.cancelAll();
  final now = DateTime.now();
  for (var i = 0; i < slots.length; i++) {
    final s = slots[i];
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
  var b = DateTime(now.year, now.month, now.day, 21, 5);
  while (b.weekday != 7 || !b.isAfter(now)) {
    b = DateTime(b.year, b.month, b.day + 1, 21, 5);
  }
  await _zoned(997, 'Bilan de la semaine',
      'Ton bilan est prêt : viens voir tes heures d\'étude.', b,
      repeat: DateTimeComponents.dayOfWeekAndTime);
}

Future<void> testAlarm() async {
  await _zoned(999, 'Test DAJ Planning', 'Si tu vois ça, les rappels marchent ✔',
      DateTime.now().add(const Duration(seconds: 10)));
}

// ───────────────────────── Application ─────────────────────────

const Color fond = Color(0xFF0B0F14);
const Color gris = Color(0xFF9CA3AF);
const Color clair = Color(0xFFD1D5DB);
const Color vert = Color(0xFF22C55E);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  await state.load();
  await extras.load();
  unawaited(scheduleAll(state.slots, state.reminder));
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
            tooltip: 'Réglages',
            icon: const Icon(Icons.tune),
            onPressed: () => showSettings(context),
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: const [
          TodayScreen(),
          WeekScreen(),
          LibreScreen(),
          VideosScreen(),
          BilanScreen(),
        ],
      ),
      floatingActionButton: tab == 1
          ? FloatingActionButton(
              tooltip: 'Ajouter un créneau',
              onPressed: () => editSlot(context, null),
              child: const Icon(Icons.add),
            )
          : null,
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
          BottomNavigationBarItem(icon: Icon(Icons.ondemand_video), label: 'Vidéos'),
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

// ───────────────────────── Réglages ─────────────────────────

void showSettings(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: state,
      builder: (ctx, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rappel avant chaque créneau',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 5, label: Text('5 min')),
                ButtonSegment(value: 10, label: Text('10 min')),
                ButtonSegment(value: 15, label: Text('15 min')),
              ],
              selected: {state.reminder},
              onSelectionChanged: (s) => state.setReminder(s.first),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.alarm_add),
              label: const Text('Tester un rappel (10 s)'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await testAlarm();
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(const SnackBar(
                    content: Text('Rappel test dans 10 secondes. Ferme l\'appli !')));
              },
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Rétablir l\'emploi du temps d\'origine'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    title: const Text('Rétablir l\'emploi du temps ?'),
                    content: const Text(
                        'Tes modifications de créneaux seront effacées. Tes heures faites sont gardées.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Rétablir')),
                    ],
                  ),
                );
                if (ok == true) {
                  await state.resetSlots();
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

// ───────────────────────── Modifier un créneau ─────────────────────────

Future<void> editSlot(BuildContext context, Slot? old) async {
  var subject = old?.subject ?? matieres.first;
  var day = old?.day ?? 1;
  var start = TimeOfDay(hour: old?.sh ?? 8, minute: old?.sm ?? 0);
  var end = TimeOfDay(hour: old?.eh ?? 9, minute: old?.em ?? 0);
  String? err;
  const choix = [...matieres, 'Cours'];

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(old == null ? 'Nouveau créneau' : 'Modifier le créneau'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: subject,
                decoration: const InputDecoration(labelText: 'Matière'),
                items: [
                  for (final m in choix) DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) {
                  if (v != null) setS(() => subject = v);
                },
              ),
              DropdownButtonFormField<int>(
                value: day,
                decoration: const InputDecoration(labelText: 'Jour'),
                items: [
                  for (var i = 1; i <= 7; i++)
                    DropdownMenuItem(value: i, child: Text(jours[i - 1])),
                ],
                onChanged: (v) {
                  if (v != null) setS(() => day = v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Début : ${hm(start.hour, start.minute)}'),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final t = await showTimePicker(context: ctx, initialTime: start);
                  if (t != null) setS(() => start = t);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Fin : ${hm(end.hour, end.minute)}'),
                trailing: const Icon(Icons.access_time),
                onTap: () async {
                  final t = await showTimePicker(context: ctx, initialTime: end);
                  if (t != null) setS(() => end = t);
                },
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!, style: const TextStyle(color: Color(0xFFEF4444))),
                ),
            ],
          ),
        ),
        actions: [
          if (old != null)
            TextButton(
              onPressed: () async {
                await state.deleteSlot(old);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Supprimer',
                  style: TextStyle(color: Color(0xFFEF4444))),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final a = start.hour * 60 + start.minute;
              final b = end.hour * 60 + end.minute;
              if (b <= a) {
                setS(() => err = 'La fin doit être après le début.');
                return;
              }
              await state.saveSlot(
                  old, Slot(day, subject, start.hour, start.minute, end.hour, end.minute));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

// ───────────────────────── Composants ─────────────────────────

class SlotRow extends StatelessWidget {
  final Slot slot;
  final String trailing;
  final String? prefix;
  final VoidCallback? onTap;
  const SlotRow(this.slot, this.trailing, {super.key, this.prefix, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
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
                    Text(prefix == null ? slot.label : '$prefix · ${slot.label}',
                        style: const TextStyle(fontSize: 13, color: gris)),
                  ],
                ),
              ),
              Text(trailing, style: const TextStyle(fontSize: 12, color: clair)),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Aujourd'hui ─────────────────────────

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? ticker;
  int phase = 0; // 0 prêt, 1 concentration (50 min), 2 pause (10 min)
  bool tPaused = false;
  DateTime? endAt;
  int leftSec = 0;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    if (phase != 0 && !tPaused && endAt != null) {
      final left = endAt!.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        if (phase == 1) {
          _start(2);
        } else {
          _stop();
        }
        return;
      }
      leftSec = left;
    }
    setState(() {});
  }

  void _notifyEnd(int p, DateTime end) {
    unawaited(_zoned(
      998,
      p == 1 ? 'Pause de 10 minutes' : 'On reprend !',
      p == 1
          ? '50 minutes de concentration terminées, bravo.'
          : 'La pause est finie. Un nouveau tour de 50 minutes ?',
      end,
    ));
  }

  void _start(int p) {
    final secs = (p == 1 ? 50 : 10) * 60;
    final end = DateTime.now().add(Duration(seconds: secs));
    setState(() {
      phase = p;
      tPaused = false;
      endAt = end;
      leftSec = secs;
    });
    _notifyEnd(p, end);
  }

  void _stop() {
    setState(() {
      phase = 0;
      tPaused = false;
      endAt = null;
    });
    unawaited(plugin.cancel(998));
  }

  void _togglePause() {
    if (tPaused) {
      final end = DateTime.now().add(Duration(seconds: leftSec));
      setState(() {
        tPaused = false;
        endAt = end;
      });
      _notifyEnd(phase, end);
    } else {
      setState(() => tPaused = true);
      unawaited(plugin.cancel(998));
    }
  }

  Widget timerCard() {
    final running = phase != 0;
    final secs = running ? leftSec : 50 * 60;
    final col = phase == 2 ? const Color(0xFF38BDF8) : vert;
    final label = phase == 0
        ? 'MINUTEUR 50 / 10'
        : phase == 1
            ? (tPaused ? 'CONCENTRATION · EN PAUSE' : 'CONCENTRATION')
            : (tPaused ? 'PAUSE · EN SUSPENS' : 'PAUSE : REPOSE-TOI');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withValues(alpha: .6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: col)),
                const SizedBox(height: 2),
                Text('${_two(secs ~/ 60)}:${_two(secs % 60)}',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (!running)
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: vert,
                  foregroundColor: const Color(0xFF04210F),
                  minimumSize: const Size(110, 48)),
              onPressed: () => _start(1),
              child: const Text('Démarrer', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          else ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 48)),
              onPressed: _togglePause,
              child: Text(tPaused ? 'Reprendre' : 'Pause'),
            ),
            IconButton(
              tooltip: 'Arrêter',
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ],
        ],
      ),
    );
  }

  Widget feature(Slot s, DateTime now, bool running) {
    final nowMin = now.hour * 60 + now.minute;
    final study = s.subject != 'Cours';
    final progress = running
        ? ((nowMin - s.startMin) / s.minutes).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final info = running
        ? 'il reste ${dur(s.endMin - nowMin)}'
        : 'dans ${dur(s.startMin - nowMin)}';
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
            running ? 'EN COURS' : 'PROCHAIN',
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
          Text('${s.label} · $info', style: const TextStyle(color: clair)),
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
            if (study) ...[
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: s.color,
                  foregroundColor: const Color(0xFF04210F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final m = (nowMin - s.startMin).clamp(1, s.minutes).toInt();
                  state.markDone(now, s, minutes: m);
                  askNote(context, s);
                },
                child: const Text('Terminé', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> rattraper(Missed m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rattrapé ?'),
        content: Text('Marquer « ${m.slot.subject} » comme rattrapé ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false), child: const Text('Pas encore')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true), child: const Text('Oui, fait')),
        ],
      ),
    );
    if (ok == true) await state.markDone(m.date, m.slot);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final now = DateTime.now();
        final nowMin = now.hour * 60 + now.minute;
        final date = dk(now);
        final today = state.slots.where((s) => s.day == now.weekday).toList();

        Slot? current;
        Slot? next;
        for (final s in today) {
          if (state.isDone(date, s)) continue;
          if (nowMin >= s.startMin && nowMin < s.endMin) {
            current ??= s;
          } else if (s.startMin > nowMin) {
            next ??= s;
          }
        }
        final featured = current ?? next;

        final rows = <Widget>[];
        for (final s in today) {
          if (s == featured) continue;
          if (state.isDone(date, s)) {
            rows.add(SlotRow(s, 'Fait'));
          } else if (nowMin >= s.endMin) {
            if (s.subject == 'Cours') rows.add(SlotRow(s, 'Passé'));
          } else {
            final r = s.startMin - state.reminder;
            rows.add(SlotRow(s, 'Rappel ${hm(r ~/ 60, r % 60)}'));
          }
        }

        final missed = state.missed(now);
        final serie = state.streak(now);
        final today0 = DateTime(now.year, now.month, now.day);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${now.day} ${mois[now.month - 1]}',
                          style: const TextStyle(fontSize: 13, color: gris)),
                      Text(jours[now.weekday - 1],
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: vert.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: vert.withValues(alpha: .6)),
                  ),
                  child: Text(serie > 0 ? 'Série : $serie j' : 'Nouveau départ',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (featured != null)
              feature(featured, now, featured == current)
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Journée terminée, bravo !',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            timerCard(),
            const MissionCard(),
            ...rows,
            if (missed.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: Text('À rattraper (48 h)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              for (final m in missed)
                SlotRow(
                  m.slot,
                  'Appuie si fait',
                  prefix: () {
                    final back = today0
                        .difference(DateTime(m.date.year, m.date.month, m.date.day))
                        .inHours;
                    final n = (back / 24).round();
                    return n == 0 ? 'Aujourd\'hui' : (n == 1 ? 'Hier' : 'Avant-hier');
                  }(),
                  onTap: () => rattraper(m),
                ),
            ],
            const SizedBox(height: 8),
            Center(
              child: Text(messageDuJour(now),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: gris, fontSize: 14)),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Semaine ─────────────────────────

class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
          children: [
            const Text('Ma semaine',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Touche un créneau pour le modifier, + pour en ajouter.',
                  style: TextStyle(fontSize: 13, color: gris)),
            ),
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
                  for (final s in state.slots.where((s) => s.day == d))
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => editSlot(context, s),
                      child: Container(
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
                                    style: const TextStyle(fontSize: 12, color: clair)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

// ───────────────────────── Bilan ─────────────────────────

class BilanScreen extends StatelessWidget {
  const BilanScreen({super.key});

  Future<void> editGoal(BuildContext context, String m) async {
    var v = state.goalFor(m).toDouble();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Objectif : $m'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${v.round()} h par semaine',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Slider(
                value: v,
                min: 1,
                max: 20,
                divisions: 19,
                onChanged: (x) => setS(() => v = x),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                await state.setGoal(m, v.round());
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final now = DateTime.now();
        final lundi = DateTime(now.year, now.month, now.day - (now.weekday - 1));
        final days = [
          for (var i = 0; i < 7; i++) dk(DateTime(lundi.year, lundi.month, lundi.day + i))
        ];
        int minutesOf(String m) => state.recs
            .where((r) => r.subject == m && days.contains(r.date))
            .fold(0, (a, r) => a + r.minutes);
        final total = matieres.fold(0, (a, m) => a + minutesOf(m));
        final dimancheSoir = now.weekday == 7 && now.hour >= 19;
        final bravo = total == 0
            ? 'Une nouvelle semaine, un nouveau départ.'
            : 'Bravo, chaque minute compte !';

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: vert.withValues(alpha: dimancheSoir ? .22 : .12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: vert, width: dimancheSoir ? 2 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dimancheSoir ? 'BILAN DE LA SEMAINE' : 'CETTE SEMAINE',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: vert)),
                  const SizedBox(height: 6),
                  Text(fmtDur(total),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                  const Text('d\'étude', style: TextStyle(color: clair)),
                  const SizedBox(height: 10),
                  Text(bravo, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(
                      'Série : ${state.streak(now)} j · Meilleure série : ${state.bestStreak()} j',
                      style: const TextStyle(fontSize: 13, color: gris)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 18, bottom: 4),
              child: Text('Heures par matière',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            const Text('Touche une matière pour changer ton objectif.',
                style: TextStyle(fontSize: 13, color: gris)),
            const SizedBox(height: 10),
            for (final m in matieres)
              Builder(builder: (context) {
                final done = minutesOf(m);
                final goal = state.goalFor(m);
                final col = couleurs[m] ?? Colors.grey;
                final p = (done / (goal * 60)).clamp(0.0, 1.0).toDouble();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => editGoal(context, m),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: col.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: col),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(m,
                                    style: const TextStyle(
                                        fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                              Text('${fmtDur(done)} / $goal h',
                                  style: const TextStyle(fontSize: 13, color: clair)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: p,
                              minHeight: 8,
                              backgroundColor: const Color(0xFF1F2A37),
                              color: col,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

/// Programme une notification ponctuelle (utilise par les ecrans en plus).
Future<void> zonedNotify(int id, String title, String body, DateTime when) =>
    _zoned(id, title, body, when);
