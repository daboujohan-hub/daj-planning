// Fonctionnalités 10 à 13 : graphiques, calendrier, badges, journal de forme.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extras.dart';
import 'main.dart';
import 'organiser.dart';

// ───────────────────────── Données ─────────────────────────

const List<String> humeurs = ['😔', '😕', '😐', '🙂', '😄'];
const List<String> humeursNoms = ['Difficile', 'Moyen', 'Neutre', 'Bien', 'Super'];

class Forme {
  final String date, note;
  final int mood, energy; // humeur 0 à 4, énergie 1 à 5
  const Forme(this.date, this.mood, this.energy, this.note);

  factory Forme.fromJson(Map<String, dynamic> j) => Forme(j['d'] as String,
      j['m'] as int, j['e'] as int, (j['n'] as String?) ?? '');

  Map<String, dynamic> toJson() => {'d': date, 'm': mood, 'e': energy, 'n': note};
}

class Suivi extends ChangeNotifier {
  SharedPreferences? _p;
  List<Forme> formes = [];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      final s = p.getString('formes');
      if (s != null) {
        formes = (jsonDecode(s) as List)
            .map((e) => Forme.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      // données illisibles : on repart de zéro
    }
  }

  Forme? forDate(String date) {
    for (final f in formes) {
      if (f.date == date) return f;
    }
    return null;
  }

  Future<void> saveForme(Forme f) async {
    formes = [...formes.where((x) => x.date != f.date), f]
      ..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    await _p?.setString('formes', jsonEncode(formes.map((e) => e.toJson()).toList()));
  }
}

final Suivi suivi = Suivi();

/// date -> matière -> minutes (séances terminées + concentration totale).
Map<String, Map<String, int>> studyByDay() {
  final out = <String, Map<String, int>>{};
  void add(String date, String subject, int m) {
    final day = out.putIfAbsent(date, () => <String, int>{});
    day[subject] = (day[subject] ?? 0) + m;
  }

  for (final r in state.recs) {
    if (r.subject != 'Cours') add(r.date, r.subject, r.minutes);
  }
  for (final f in orga.focusLog) {
    add(f['d'] as String, f['s'] as String, (f['m'] as num).toInt());
  }
  return out;
}

int dayTotal(Map<String, int>? m) =>
    m == null ? 0 : m.values.fold(0, (a, b) => a + b);

int totalMinutes() {
  final data = studyByDay();
  return data.values.fold(0, (a, m) => a + dayTotal(m));
}

int weekMinutes(DateTime now) {
  final data = studyByDay();
  final lundi = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  var t = 0;
  for (var i = 0; i < 7; i++) {
    t += dayTotal(data[dk(DateTime(lundi.year, lundi.month, lundi.day + i))]);
  }
  return t;
}

// ───────────────────────── Carte « Aujourd'hui » ─────────────────────────

class SuiviCard extends StatelessWidget {
  const SuiviCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([state, orga, suivi]),
      builder: (context, _) {
        final now = DateTime.now();
        final week = weekMinutes(now);
        final serie = state.streak(now);
        final formeFaite = suivi.forDate(dk(now)) != null;
        return Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF374151)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MON SUIVI',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: gris)),
                    const SizedBox(height: 2),
                    Text('${fmtDur(week)} cette semaine · série $serie j',
                        style: const TextStyle(fontSize: 14)),
                    if (!formeFaite)
                      const Text('Comment te sens-tu aujourd\'hui ?',
                          style: TextStyle(fontSize: 12, color: gris)),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => SuiviScreen(initialTab: formeFaite ? 0 : 3)),
                ),
                child: const Text('Ouvrir'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SuiviScreen extends StatelessWidget {
  final int initialTab;
  const SuiviScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mon suivi'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Graphiques'),
              Tab(text: 'Calendrier'),
              Tab(text: 'Badges'),
              Tab(text: 'Forme'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_GraphTab(), _CalendarTab(), _BadgesTab(), _FormeTab()],
        ),
      ),
    );
  }
}

// ───────────────────────── Graphiques ─────────────────────────

class _GraphTab extends StatefulWidget {
  const _GraphTab();
  @override
  State<_GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<_GraphTab> {
  int range = 7;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([state, orga]),
      builder: (context, _) {
        final data = studyByDay();
        final now = DateTime.now();
        final days = [
          for (var i = range - 1; i >= 0; i--)
            DateTime(now.year, now.month, now.day - i)
        ];
        final totals = [for (final d in days) dayTotal(data[dk(d)])];
        var maxV = 60;
        for (final t in totals) {
          if (t > maxV) maxV = t;
        }
        final total = totals.fold(0, (a, b) => a + b);
        final studied = totals.where((t) => t > 0).length;

        Widget bar(int i) {
          const h = 140.0;
          final m = data[dk(days[i])];
          final segs = <Widget>[];
          if (m != null) {
            for (final s in matieres) {
              final v = m[s] ?? 0;
              if (v > 0) {
                segs.add(Container(
                  height: (v / maxV * h).clamp(2.0, h).toDouble(),
                  color: couleurs[s] ?? gris,
                ));
              }
            }
          }
          final label = range == 7
              ? jours[days[i].weekday - 1].substring(0, 1)
              : ((i % 5 == 0 || i == days.length - 1) ? '${days[i].day}' : '');
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: range == 7 ? 4.0 : 1.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (range == 7 && totals[i] > 0)
                  Text('${(totals[i] / 60).toStringAsFixed(1).replaceAll('.', ',')} h',
                      style: const TextStyle(fontSize: 10, color: clair)),
                const SizedBox(height: 2),
                ...segs,
                const SizedBox(height: 4),
                SizedBox(
                  height: 14,
                  child: Text(label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(fontSize: 10, color: gris)),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 jours')),
                ButtonSegment(value: 30, label: Text('30 jours')),
              ],
              selected: {range},
              onSelectionChanged: (s) => setState(() => range = s.first),
            ),
            const SizedBox(height: 18),
            Text(fmtDur(total),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
            Text(
                'sur $range jours · $studied jour${studied > 1 ? 's' : ''} étudié${studied > 1 ? 's' : ''} · moyenne ${fmtDur(total ~/ range)} par jour',
                style: const TextStyle(fontSize: 13, color: gris)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < days.length; i++) Expanded(child: bar(i)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final m in matieres)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: couleurs[m] ?? gris, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(m, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Séances terminées + séances de concentration totale.',
                style: TextStyle(fontSize: 12, color: gris)),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Calendrier ─────────────────────────

class _CalendarTab extends StatefulWidget {
  const _CalendarTab();
  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  late DateTime month;
  String? selected;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    month = DateTime(n.year, n.month, 1);
    selected = dk(n);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([state, orga]),
      builder: (context, _) {
        final data = studyByDay();
        final now = DateTime.now();
        final todayKey = dk(now);
        final lead = month.weekday - 1;
        final count = DateTime(month.year, month.month + 1, 0).day;
        final weeks = ((lead + count) / 7).ceil();
        final daysStudied = [
          for (var d = 1; d <= count; d++)
            if (dayTotal(data[dk(DateTime(month.year, month.month, d))]) > 0) d
        ].length;

        Widget cell(int index) {
          final d = index - lead + 1;
          if (d < 1 || d > count) return const Expanded(child: SizedBox(height: 46));
          final date = DateTime(month.year, month.month, d);
          final key = dk(date);
          final mins = dayTotal(data[key]);
          final isToday = key == todayKey;
          final isSel = key == selected;
          final alpha = mins == 0 ? 0.0 : (mins >= 120 ? .9 : (mins >= 60 ? .6 : .35));
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => selected = key),
              child: Container(
                height: 42,
                margin: const EdgeInsets.all(2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: vert.withValues(alpha: alpha),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSel
                        ? Colors.white
                        : (isToday ? vert : Colors.transparent),
                    width: isSel ? 2 : 1.5,
                  ),
                ),
                child: Text('$d',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          );
        }

        final sel = selected == null ? null : data[selected];
        final selMin = dayTotal(sel);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Mois précédent',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () =>
                      setState(() => month = DateTime(month.year, month.month - 1, 1)),
                ),
                Expanded(
                  child: Text('${mois[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Mois suivant',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () =>
                      setState(() => month = DateTime(month.year, month.month + 1, 1)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final j in jours)
                  Expanded(
                    child: Center(
                      child: Text(j.substring(0, 1),
                          style: const TextStyle(fontSize: 12, color: gris)),
                    ),
                  ),
              ],
            ),
            for (var w = 0; w < weeks; w++)
              Row(children: [for (var c = 0; c < 7; c++) cell(w * 7 + c)]),
            const SizedBox(height: 14),
            Text('$daysStudied jour${daysStudied > 1 ? 's' : ''} étudié${daysStudied > 1 ? 's' : ''} ce mois-ci',
                style: const TextStyle(fontSize: 14, color: clair)),
            const SizedBox(height: 16),
            if (selected != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${pd(selected!).day} ${mois[pd(selected!).month - 1]} : ${selMin == 0 ? 'jour de repos' : fmtDur(selMin)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (sel != null)
                      for (final m in matieres)
                        if ((sel[m] ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                      color: couleurs[m] ?? gris, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Text('$m : ${fmtDur(sel[m] ?? 0)}'),
                              ],
                            ),
                          ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Badges et paliers ─────────────────────────

class Trophee {
  final String title, desc;
  final IconData icon;
  final int value, goal;
  final bool minutes; // la progression est en minutes (affichée en heures)
  const Trophee(this.title, this.desc, this.icon, this.value, this.goal,
      {this.minutes = false});

  bool get unlocked => value >= goal;

  String get progress => minutes
      ? '${fmtDur(value > goal ? goal : value)} / ${goal ~/ 60} h'
      : '${value > goal ? goal : value} / $goal';
}

const List<String> niveaux = [
  'Débutant', 'Curieux', 'Régulier', 'Appliqué', 'Solide', 'Expert', 'Maître'
];
const List<int> seuilsH = [0, 5, 15, 30, 60, 100, 200];

List<Trophee> computeTrophees() {
  final study = state.recs.where((r) => r.subject != 'Cours').toList();
  final total = totalMinutes();
  final best = state.bestStreak();
  final focusN = orga.focusLog.length;

  final weeks = <String, Set<String>>{};
  void addWeek(String date, String subject) {
    final d = pd(date);
    final lundi = d.subtract(Duration(days: d.weekday - 1));
    weeks.putIfAbsent(dk(lundi), () => <String>{}).add(subject);
  }

  for (final r in study) {
    addWeek(r.date, r.subject);
  }
  for (final f in orga.focusLog) {
    addWeek(f['d'] as String, f['s'] as String);
  }
  var maxSubjects = 0;
  for (final s in weeks.values) {
    if (s.length > maxSubjects) maxSubjects = s.length;
  }

  return [
    Trophee('Premier pas', 'Terminer une première séance', Icons.flag, study.length, 1),
    Trophee('Dix séances', 'Terminer 10 séances', Icons.looks_one, study.length, 10),
    Trophee('Cinquante séances', 'Terminer 50 séances', Icons.workspace_premium, study.length, 50),
    Trophee('Trois jours de suite', 'Étudier 3 jours d\'affilée', Icons.local_fire_department, best, 3),
    Trophee('Une semaine', 'Étudier 7 jours d\'affilée', Icons.event_available, best, 7),
    Trophee('Deux semaines', 'Étudier 14 jours d\'affilée', Icons.emoji_events, best, 14),
    Trophee('10 heures', 'Cumuler 10 h d\'étude', Icons.timer, total, 600, minutes: true),
    Trophee('50 heures', 'Cumuler 50 h d\'étude', Icons.hourglass_bottom, total, 3000, minutes: true),
    Trophee('100 heures', 'Cumuler 100 h d\'étude', Icons.military_tech, total, 6000, minutes: true),
    Trophee('Touche-à-tout', 'Étudier les 5 matières dans la même semaine', Icons.palette, maxSubjects, 5),
    Trophee('Concentré', 'Une séance de concentration totale', Icons.center_focus_strong, focusN, 1),
    Trophee('Très concentré', '10 séances de concentration totale', Icons.self_improvement, focusN, 10),
    Trophee('Plume', 'Écrire 5 notes dans ton carnet', Icons.edit_note, extras.notes.length, 5),
    Trophee('Prêt pour l\'examen', 'Terminer un examen ou un devoir', Icons.school,
        orga.exams.where((e) => e.done).length, 1),
  ];
}

class _BadgesTab extends StatelessWidget {
  const _BadgesTab();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([state, orga, extras]),
      builder: (context, _) {
        final hours = totalMinutes() / 60;
        var lvl = 0;
        for (var i = 0; i < seuilsH.length; i++) {
          if (hours >= seuilsH[i]) lvl = i;
        }
        final next = lvl + 1 < seuilsH.length ? seuilsH[lvl + 1] : null;
        final p = next == null
            ? 1.0
            : ((hours - seuilsH[lvl]) / (next - seuilsH[lvl])).clamp(0.0, 1.0).toDouble();
        final list = computeTrophees();
        list.sort((a, b) => (b.unlocked ? 1 : 0) - (a.unlocked ? 1 : 0));
        final got = list.where((t) => t.unlocked).length;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: vert.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: vert),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NIVEAU ${lvl + 1}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: vert)),
                  Text(niveaux[lvl],
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF1F2A37),
                      color: vert,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      next == null
                          ? 'Niveau maximum atteint, bravo !'
                          : '${hours.toStringAsFixed(1).replaceAll('.', ',')} h sur ${next} h pour le niveau suivant',
                      style: const TextStyle(fontSize: 13, color: clair)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('Badges : $got / ${list.length}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Aucune pression : ils arrivent à ton rythme.',
                style: TextStyle(fontSize: 13, color: gris)),
            const SizedBox(height: 10),
            for (final t in list)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.unlocked ? vert.withValues(alpha: .10) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: t.unlocked ? vert : const Color(0xFF374151)),
                ),
                child: Row(
                  children: [
                    Icon(t.icon, size: 28, color: t.unlocked ? vert : const Color(0xFF4B5563)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: t.unlocked ? null : gris)),
                          Text(t.desc, style: const TextStyle(fontSize: 12, color: gris)),
                        ],
                      ),
                    ),
                    Text(t.unlocked ? 'Obtenu' : t.progress,
                        style: TextStyle(
                            fontSize: 12,
                            color: t.unlocked ? vert : gris,
                            fontWeight: t.unlocked ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Journal de forme ─────────────────────────

class _FormeTab extends StatefulWidget {
  const _FormeTab();
  @override
  State<_FormeTab> createState() => _FormeTabState();
}

class _FormeTabState extends State<_FormeTab> {
  int mood = 3;
  int energy = 3;
  final note = TextEditingController();
  bool saved = false;

  @override
  void initState() {
    super.initState();
    final f = suivi.forDate(dk(DateTime.now()));
    if (f != null) {
      mood = f.mood;
      energy = f.energy;
      note.text = f.note;
      saved = true;
    }
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await suivi.saveForme(Forme(dk(DateTime.now()), mood, energy, note.text.trim()));
    if (mounted) setState(() => saved = true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: suivi,
      builder: (context, _) {
        final recent = suivi.formes.reversed.take(14).toList();
        final avg = recent.isEmpty
            ? 0.0
            : recent.fold(0, (a, f) => a + f.energy) / recent.length;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Comment te sens-tu aujourd\'hui ?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            const Text('Humeur', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < humeurs.length; i++)
                  ChoiceChip(
                    label: Text('${humeurs[i]} ${humeursNoms[i]}'),
                    selected: mood == i,
                    onSelected: (_) => setState(() {
                      mood = i;
                      saved = false;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Énergie', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (var i = 1; i <= 5; i++) ButtonSegment(value: i, label: Text('$i')),
              ],
              selected: {energy},
              onSelectionChanged: (s) => setState(() {
                energy = s.first;
                saved = false;
              }),
            ),
            const SizedBox(height: 4),
            const Text('1 = très fatigué, 5 = plein d\'énergie',
                style: TextStyle(fontSize: 12, color: gris)),
            const SizedBox(height: 16),
            TextField(
              controller: note,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => saved = false),
              decoration: const InputDecoration(
                  labelText: 'Un mot sur ta journée (facultatif)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: Icon(saved ? Icons.check : Icons.save_outlined),
              label: Text(saved ? 'Enregistré' : 'Enregistrer'),
              onPressed: saved ? null : _save,
            ),
            const SizedBox(height: 26),
            Text(
                recent.isEmpty
                    ? 'Historique'
                    : 'Derniers jours · énergie moyenne ${avg.toStringAsFixed(1).replaceAll('.', ',')} / 5',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              const Text('Ton journal apparaîtra ici.', style: TextStyle(color: gris)),
            for (final f in recent)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Row(
                  children: [
                    Text(humeurs[f.mood.clamp(0, 4).toInt()], style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${pd(f.date).day} ${mois[pd(f.date).month - 1]}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (f.note.isNotEmpty)
                            Text(f.note,
                                style: const TextStyle(fontSize: 13, color: clair)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Container(
                            width: 8,
                            height: 14,
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(
                              color: i <= f.energy ? vert : const Color(0xFF1F2A37),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
