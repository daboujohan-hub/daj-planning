// Fonctionnalités 6 à 9 : examens et devoirs, tâches par projet,
// concentration totale, rappels bien-être.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

// ───────────────────────── Modèles ─────────────────────────

class Exam {
  final int id;
  final String title, subject, kind, date; // date : aaaa-mm-jj
  final bool done;
  const Exam(this.id, this.title, this.subject, this.kind, this.date, this.done);

  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
      j['i'] as int,
      j['t'] as String,
      j['s'] as String,
      j['k'] as String,
      j['d'] as String,
      (j['x'] as bool?) ?? false);

  Map<String, dynamic> toJson() =>
      {'i': id, 't': title, 's': subject, 'k': kind, 'd': date, 'x': done};

  Exam withDone(bool v) => Exam(id, title, subject, kind, date, v);

  DateTime get day {
    final p = date.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  int daysLeft(DateTime now) {
    final d = day;
    return DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
  }
}

String countdown(int d) {
  if (d < 0) return 'En retard de ${-d} j';
  if (d == 0) return 'Aujourd\'hui';
  if (d == 1) return 'Demain';
  return 'J-$d';
}

class Task {
  String title;
  bool done;
  Task(this.title, this.done);

  factory Task.fromJson(Map<String, dynamic> j) =>
      Task(j['t'] as String, (j['d'] as bool?) ?? false);

  Map<String, dynamic> toJson() => {'t': title, 'd': done};
}

class Project {
  String name;
  List<Task> tasks;
  Project(this.name, this.tasks);

  factory Project.fromJson(Map<String, dynamic> j) => Project(
      j['n'] as String,
      (j['t'] as List)
          .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList());

  Map<String, dynamic> toJson() =>
      {'n': name, 't': tasks.map((t) => t.toJson()).toList()};
}

// ───────────────────────── État + sauvegarde ─────────────────────────

class Orga extends ChangeNotifier {
  SharedPreferences? _p;
  List<Exam> exams = [];
  List<Project> projects = [Project('Aboudev Labs', [])];
  bool water = false;
  bool eyes = true;
  List<Map<String, dynamic>> focusLog = []; // {'d': date, 'm': minutes, 's': matière}

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      final e = p.getString('exams');
      if (e != null) {
        exams = (jsonDecode(e) as List)
            .map((x) => Exam.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
      }
      final pr = p.getString('projects');
      if (pr != null) {
        projects = (jsonDecode(pr) as List)
            .map((x) => Project.fromJson(Map<String, dynamic>.from(x as Map)))
            .toList();
      }
      water = p.getBool('water') ?? false;
      eyes = p.getBool('eyes') ?? true;
      final f = p.getString('focusLog');
      if (f != null) {
        focusLog = (jsonDecode(f) as List)
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
      }
    } catch (_) {
      // données illisibles : valeurs par défaut
    }
  }

  Future<void> _saveExams() async {
    notifyListeners();
    await _p?.setString('exams', jsonEncode(exams.map((e) => e.toJson()).toList()));
    unawaited(reschedule());
  }

  Future<void> _saveProjects() async {
    notifyListeners();
    await _p?.setString('projects', jsonEncode(projects.map((e) => e.toJson()).toList()));
  }

  // ----- examens -----

  Future<void> addExam(Exam e) async {
    exams = [...exams, e];
    await _saveExams();
  }

  Future<void> toggleExam(int id) async {
    exams = exams.map((e) => e.id == id ? e.withDone(!e.done) : e).toList();
    await _saveExams();
  }

  Future<void> deleteExam(int id) async {
    exams = exams.where((e) => e.id != id).toList();
    await _saveExams();
  }

  Exam? nextExam(DateTime now) {
    final list = exams.where((e) => !e.done && e.daysLeft(now) >= 0).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return list.isEmpty ? null : list.first;
  }

  // ----- projets -----

  Future<void> addProject(String name) async {
    projects = [...projects, Project(name, [])];
    await _saveProjects();
  }

  Future<void> deleteProject(int i) async {
    projects = List<Project>.of(projects)..removeAt(i);
    await _saveProjects();
  }

  Future<void> addTask(int pi, String title) async {
    projects[pi].tasks.add(Task(title, false));
    await _saveProjects();
  }

  Future<void> toggleTask(int pi, int ti) async {
    projects[pi].tasks[ti].done = !projects[pi].tasks[ti].done;
    await _saveProjects();
  }

  Future<void> deleteTask(int pi, int ti) async {
    projects[pi].tasks.removeAt(ti);
    await _saveProjects();
  }

  // ----- bien-être -----

  Future<void> setWater(bool v) async {
    water = v;
    notifyListeners();
    await _p?.setBool('water', v);
    unawaited(reschedule());
  }

  Future<void> setEyes(bool v) async {
    eyes = v;
    notifyListeners();
    await _p?.setBool('eyes', v);
  }

  /// Pendant une séance de concentration de 50 min : repos des yeux à 20 et 40 min.
  Future<void> eyeBreaks(DateTime start) async {
    if (!eyes) return;
    const msg = 'Regarde au loin pendant 20 secondes.';
    await zonedNotify(4001, 'Repos des yeux', msg, start.add(const Duration(minutes: 20)));
    await zonedNotify(4002, 'Repos des yeux', msg, start.add(const Duration(minutes: 40)));
  }

  Future<void> cancelEyeBreaks() async {
    await plugin.cancel(4001);
    await plugin.cancel(4002);
  }

  // ----- concentration -----

  Future<void> logFocus(int minutes, String subject) async {
    if (minutes < 1) return;
    focusLog = [
      ...focusLog,
      {'d': dk(DateTime.now()), 'm': minutes, 's': subject}
    ];
    await _p?.setString('focusLog', jsonEncode(focusLog));
  }

  // ----- notifications -----

  /// Rappels d'examens (veille 18h, jour même 7h30) et d'eau (10h à 18h).
  Future<void> reschedule() async {
    try {
      final pend = await plugin.pendingNotificationRequests();
      for (final r in pend) {
        if (r.id >= 3000 && r.id < 4000) await plugin.cancel(r.id);
        if (r.id >= 4100 && r.id < 4200) await plugin.cancel(r.id);
      }
      final now = DateTime.now();
      var n = 0;
      for (final e in exams) {
        if (e.done) continue;
        final d = e.day;
        final veille = DateTime(d.year, d.month, d.day - 1, 18, 0);
        final matin = DateTime(d.year, d.month, d.day, 7, 30);
        if (veille.isAfter(now)) {
          await zonedNotify(3000 + n * 2, '${e.kind} demain', '${e.title} (${e.subject})', veille);
        }
        if (matin.isAfter(now)) {
          await zonedNotify(3001 + n * 2, '${e.kind} aujourd\'hui', '${e.title} (${e.subject})', matin);
        }
        n++;
        if (n > 400) break;
      }
      if (water) {
        const heures = [10, 12, 14, 16, 18];
        for (var i = 0; i < heures.length; i++) {
          var d = DateTime(now.year, now.month, now.day, heures[i]);
          if (!d.isAfter(now)) d = DateTime(d.year, d.month, d.day + 1, heures[i]);
          await zonedDaily(4100 + i, 'Pense à boire de l\'eau',
              'Un verre d\'eau, et on continue.', d);
        }
      }
    } catch (_) {
      // les rappels sont un plus : on ne bloque jamais l'appli
    }
  }
}

final Orga orga = Orga();

// ───────────────────────── Outils ─────────────────────────

Future<String?> askText(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Ajouter')),
      ],
    ),
  );
}

// ───────────────────────── Carte « Aujourd'hui » ─────────────────────────

class OrgaCard extends StatelessWidget {
  const OrgaCard({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: orga,
      builder: (context, _) {
        final now = DateTime.now();
        final next = orga.nextExam(now);
        final col = next == null ? gris : (couleurs[next.subject] ?? gris);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (next != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: col.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: col),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(next.kind.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                  color: col)),
                          const SizedBox(height: 2),
                          Text('${next.title} · ${next.subject}',
                              style: const TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                    Text(countdown(next.daysLeft(now)),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.event_note, size: 18),
                  label: const Text('Examens'),
                  onPressed: () => _open(context, const ExamsScreen()),
                ),
                ActionChip(
                  avatar: const Icon(Icons.checklist, size: 18),
                  label: const Text('Projets'),
                  onPressed: () => _open(context, const ProjectsScreen()),
                ),
                ActionChip(
                  avatar: const Icon(Icons.center_focus_strong, size: 18),
                  label: const Text('Concentration'),
                  onPressed: () => _open(context, const FocusScreen()),
                ),
                ActionChip(
                  avatar: const Icon(Icons.water_drop_outlined, size: 18),
                  label: const Text('Bien-être'),
                  onPressed: () => _open(context, const WellbeingScreen()),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Examens et devoirs ─────────────────────────

Future<void> showAddExam(BuildContext context) async {
  final title = TextEditingController();
  var subject = matieres.first;
  var kind = 'Examen';
  DateTime date = DateTime.now().add(const Duration(days: 7));
  String? err;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Examen ou devoir'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Titre (ex. Contrôle de fractions)'),
              ),
              DropdownButtonFormField<String>(
                value: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'Examen', child: Text('Examen')),
                  DropdownMenuItem(value: 'Devoir', child: Text('Devoir')),
                ],
                onChanged: (v) {
                  if (v != null) setS(() => kind = v);
                },
              ),
              DropdownButtonFormField<String>(
                value: subject,
                decoration: const InputDecoration(labelText: 'Matière'),
                items: [
                  for (final m in matieres) DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) {
                  if (v != null) setS(() => subject = v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date : ${date.day} ${mois[date.month - 1]} ${date.year}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: DateTime(now.year + 2, 12, 31),
                  );
                  if (d != null) setS(() => date = d);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) {
                setS(() => err = 'Donne un titre.');
                return;
              }
              await orga.addExam(Exam(DateTime.now().millisecondsSinceEpoch,
                  title.text.trim(), subject, kind, dk(date), false));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Examens et devoirs')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ajouter',
        onPressed: () => showAddExam(context),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: orga,
        builder: (context, _) {
          final now = DateTime.now();
          final list = List<Exam>.of(orga.exams)
            ..sort((a, b) {
              if (a.done != b.done) return a.done ? 1 : -1;
              return a.day.compareTo(b.day);
            });
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                    'Aucun examen ni devoir. Appuie sur + pour en ajouter : tu auras un rappel la veille à 18h et le jour même à 7h30.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: gris)),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            children: [
              for (final e in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: (couleurs[e.subject] ?? gris).withValues(alpha: e.done ? .06 : .14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: couleurs[e.subject] ?? gris),
                  ),
                  child: Row(
                    children: [
                      Checkbox(value: e.done, onChanged: (_) => orga.toggleExam(e.id)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    decoration:
                                        e.done ? TextDecoration.lineThrough : null)),
                            Text('${e.kind} · ${e.subject} · ${e.day.day} ${mois[e.day.month - 1]}',
                                style: const TextStyle(fontSize: 13, color: gris)),
                          ],
                        ),
                      ),
                      if (!e.done)
                        Text(countdown(e.daysLeft(now)),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => orga.deleteExam(e.id),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── Projets ─────────────────────────

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tâches par projet')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouveau projet',
        onPressed: () async {
          final name = await askText(context, 'Nouveau projet', 'Nom du projet');
          if (name != null && name.isNotEmpty) await orga.addProject(name);
        },
        child: const Icon(Icons.create_new_folder_outlined),
      ),
      body: ListenableBuilder(
        listenable: orga,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            children: [
              for (var pi = 0; pi < orga.projects.length; pi++)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                        '${orga.projects[pi].name}  (${orga.projects[pi].tasks.where((t) => t.done).length}/${orga.projects[pi].tasks.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    children: [
                      for (var ti = 0; ti < orga.projects[pi].tasks.length; ti++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Checkbox(
                            value: orga.projects[pi].tasks[ti].done,
                            onChanged: (_) => orga.toggleTask(pi, ti),
                          ),
                          title: Text(
                            orga.projects[pi].tasks[ti].title,
                            style: TextStyle(
                                decoration: orga.projects[pi].tasks[ti].done
                                    ? TextDecoration.lineThrough
                                    : null),
                          ),
                          trailing: IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => orga.deleteTask(pi, ti),
                          ),
                        ),
                      Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter une tâche'),
                            onPressed: () async {
                              final t = await askText(context, 'Nouvelle tâche', 'Tâche');
                              if (t != null && t.isNotEmpty) await orga.addTask(pi, t);
                            },
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Supprimer le projet',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (d) => AlertDialog(
                                  title: const Text('Supprimer ce projet ?'),
                                  content: Text(orga.projects[pi].name),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(d, false),
                                        child: const Text('Annuler')),
                                    FilledButton(
                                        onPressed: () => Navigator.pop(d, true),
                                        child: const Text('Supprimer')),
                                  ],
                                ),
                              );
                              if (ok == true) await orga.deleteProject(pi);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── Concentration totale ─────────────────────────

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  Timer? ticker;
  int minutes = 50;
  String subject = matieres.first;
  bool running = false;
  bool finished = false;
  DateTime? start;
  DateTime? endAt;
  int leftSec = 0;

  @override
  void dispose() {
    ticker?.cancel();
    if (running) _logElapsed();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (running) plugin.cancel(4003);
    super.dispose();
  }

  void _logElapsed() {
    final s = start;
    if (s == null) return;
    final spent = DateTime.now().difference(s).inMinutes;
    orga.logFocus(spent > minutes ? minutes : spent, subject);
  }

  void _begin() {
    final now = DateTime.now();
    final end = now.add(Duration(minutes: minutes));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    zonedNotify(4003, 'Concentration terminée', 'Bravo ! Tu peux souffler.', end);
    setState(() {
      running = true;
      finished = false;
      start = now;
      endAt = end;
      leftSec = minutes * 60;
    });
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || endAt == null) return;
    final left = endAt!.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      ticker?.cancel();
      _logElapsed();
      HapticFeedback.heavyImpact();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      setState(() {
        running = false;
        finished = true;
      });
      return;
    }
    setState(() => leftSec = left);
  }

  void _stop() {
    ticker?.cancel();
    _logElapsed();
    plugin.cancel(4003);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    if (running) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(subject,
                    style: TextStyle(
                        fontSize: 18,
                        letterSpacing: 2,
                        color: couleurs[subject] ?? gris)),
                const SizedBox(height: 16),
                Text('${two2(leftSec ~/ 60)}:${two2(leftSec % 60)}',
                    style: const TextStyle(fontSize: 84, fontWeight: FontWeight.w300)),
                const SizedBox(height: 40),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
                  onPressed: _stop,
                  child: const Text('Terminer'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Concentration totale')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (finished)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('Séance terminée, bravo !',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          const Text('Un écran noir, un seul chiffre, rien d\'autre.',
              style: TextStyle(color: gris)),
          const SizedBox(height: 20),
          const Text('Matière', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in matieres)
                ChoiceChip(
                  label: Text(m),
                  selected: subject == m,
                  onSelected: (_) => setState(() => subject = m),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Durée', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 25, label: Text('25 min')),
              ButtonSegment(value: 50, label: Text('50 min')),
              ButtonSegment(value: 90, label: Text('90 min')),
            ],
            selected: {minutes},
            onSelectionChanged: (s) => setState(() => minutes = s.first),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: vert,
                foregroundColor: const Color(0xFF04210F)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Commencer', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _begin,
          ),
          const SizedBox(height: 10),
          const Text(
              'Les barres du téléphone se cachent. Une notification te prévient à la fin, même si l\'écran s\'éteint.',
              style: TextStyle(fontSize: 13, color: gris)),
        ],
      ),
    );
  }
}

String two2(int n) => n.toString().padLeft(2, '0');

// ───────────────────────── Bien-être ─────────────────────────

class WellbeingScreen extends StatelessWidget {
  const WellbeingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bien-être')),
      body: ListenableBuilder(
        listenable: orga,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rappels pour boire de l\'eau'),
                subtitle: const Text('À 10h, 12h, 14h, 16h et 18h, chaque jour.'),
                value: orga.water,
                onChanged: (v) => orga.setWater(v),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repos des yeux (règle 20-20-20)'),
                subtitle: const Text(
                    'Pendant le minuteur de 50 minutes : à 20 et 40 minutes, regarde au loin pendant 20 secondes.'),
                value: orga.eyes,
                onChanged: (v) => orga.setEyes(v),
              ),
            ],
          );
        },
      ),
    );
  }
}
