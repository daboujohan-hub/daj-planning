// Congés et périodes spéciales : pendant ces dates, pas de cours à l'école.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

class Period {
  final int id;
  final String name, start, end, kind; // dates : aaaa-mm-jj
  final bool noClass;
  const Period(this.id, this.name, this.start, this.end, this.kind, this.noClass);

  factory Period.fromJson(Map<String, dynamic> j) => Period(
      j['i'] as int,
      j['n'] as String,
      j['s'] as String,
      j['e'] as String,
      j['k'] as String,
      (j['c'] as bool?) ?? true);

  Map<String, dynamic> toJson() =>
      {'i': id, 'n': name, 's': start, 'e': end, 'k': kind, 'c': noClass};
}

String fmtDay(String key) {
  final d = pd(key);
  return '${d.day} ${mois[d.month - 1]}';
}

class Conges extends ChangeNotifier {
  SharedPreferences? _p;
  List<Period> periods = [];
  Timer? _debounce;
  String _sig = '';

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      final s = p.getString('periods');
      if (s != null) {
        periods = (jsonDecode(s) as List)
            .map((e) => Period.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      // données illisibles : on repart de zéro
    }
    state.addListener(_onState);
  }

  void _onState() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      reschedule();
    });
  }

  bool _covers(Period p, String key) =>
      key.compareTo(p.start) >= 0 && key.compareTo(p.end) <= 0;

  /// Vrai si ce jour-là il n'y a pas de cours à l'école.
  bool isOff(DateTime d) {
    final k = dk(d);
    return periods.any((p) => p.noClass && _covers(p, k));
  }

  Period? current(DateTime d) {
    final k = dk(d);
    for (final p in periods) {
      if (_covers(p, k)) return p;
    }
    return null;
  }

  Period? upcoming(DateTime d, {int withinDays = 14}) {
    final k = dk(d);
    final limit = dk(DateTime(d.year, d.month, d.day + withinDays));
    final list = periods
        .where((p) => p.start.compareTo(k) > 0 && p.start.compareTo(limit) <= 0)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list.isEmpty ? null : list.first;
  }

  Future<void> add(Period p) async {
    periods = [...periods, p];
    await _save();
  }

  Future<void> remove(int id) async {
    periods = periods.where((p) => p.id != id).toList();
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await _p?.setString('periods', jsonEncode(periods.map((p) => p.toJson()).toList()));
    await reschedule(force: true);
  }

  /// Rappels des cours de l'école pour les 3 prochaines semaines,
  /// en sautant les jours de congés.
  Future<void> reschedule({bool force = false}) async {
    final now = DateTime.now();
    final cours = state.slots.where((s) => s.subject == 'Cours').toList();
    final sig =
        '${state.reminder}|${cours.map((s) => s.key).join(',')}|${periods.map((p) => '${p.start}${p.end}${p.noClass}').join(',')}|${dk(now)}';
    if (!force && sig == _sig) return;
    _sig = sig;
    try {
      final pend = await plugin.pendingNotificationRequests();
      for (final r in pend) {
        if (r.id >= 5000 && r.id < 6000) await plugin.cancel(r.id);
      }
      var n = 0;
      for (final s in cours) {
        for (var off = 0; off < 21; off++) {
          final day = DateTime(now.year, now.month, now.day + off);
          if (day.weekday != s.day || isOff(day)) continue;
          final when =
              DateTime(day.year, day.month, day.day, s.sh, s.sm - state.reminder);
          if (!when.isAfter(now)) continue;
          await zonedNotify(5000 + n, 'Cours dans ${state.reminder} min', s.label, when);
          n++;
          if (n > 900) return;
        }
      }
    } catch (_) {
      // les rappels sont un plus : on ne bloque jamais l'appli
    }
  }
}

final Conges conges = Conges();

// ───────────────────────── Bandeau « Aujourd'hui » ─────────────────────────

class CongesBanner extends StatelessWidget {
  const CongesBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: conges,
      builder: (context, _) {
        final now = DateTime.now();
        final cur = conges.current(now);
        if (cur != null) {
          final concours = cur.kind == 'Concours';
          final col = concours ? const Color(0xFFF97316) : const Color(0xFF38BDF8);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: col.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: col),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(concours ? 'CONCOURS' : 'CONGÉS',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: col)),
                const SizedBox(height: 2),
                Text('${cur.name} · jusqu\'au ${fmtDay(cur.end)}',
                    style: const TextStyle(fontSize: 15)),
                Text(
                    cur.noClass
                        ? 'Pas de cours : tes créneaux d\'étude continuent.'
                        : 'Les cours continuent normalement.',
                    style: const TextStyle(fontSize: 12, color: gris)),
              ],
            ),
          );
        }
        final up = conges.upcoming(now);
        if (up == null) return const SizedBox.shrink();
        final jours = pd(up.start)
            .difference(DateTime.utc(now.year, now.month, now.day))
            .inDays;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              'Dans $jours jour${jours > 1 ? 's' : ''} : ${up.name} (${fmtDay(up.start)})',
              style: const TextStyle(fontSize: 13, color: gris)),
        );
      },
    );
  }
}

// ───────────────────────── Réglages : accès ─────────────────────────

class CongesTile extends StatelessWidget {
  const CongesTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.beach_access_outlined),
      title: const Text('Congés et périodes'),
      subtitle: ListenableBuilder(
        listenable: conges,
        builder: (context, _) => Text(conges.periods.isEmpty
            ? 'Aucune période enregistrée'
            : '${conges.periods.length} période${conges.periods.length > 1 ? 's' : ''}'),
      ),
      onTap: () {
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(MaterialPageRoute<void>(builder: (_) => const CongesScreen()));
      },
    );
  }
}

// ───────────────────────── Écran des périodes ─────────────────────────

Future<void> showAddPeriod(BuildContext context) async {
  final name = TextEditingController(text: 'Vacances');
  var kind = 'Congés';
  var noClass = true;
  final now = DateTime.now();
  var start = DateTime(now.year, now.month, now.day);
  var end = DateTime(now.year, now.month, now.day + 14);
  String? err;

  String show(DateTime d) => '${d.day} ${mois[d.month - 1]} ${d.year}';

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nouvelle période'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nom (ex. Vacances de janvier)'),
              ),
              DropdownButtonFormField<String>(
                value: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'Congés', child: Text('Congés')),
                  DropdownMenuItem(value: 'Concours', child: Text('Concours ou examens')),
                ],
                onChanged: (v) {
                  if (v != null) setS(() => kind = v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Début : ${show(start)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: start,
                    firstDate: DateTime(now.year - 1, 1, 1),
                    lastDate: DateTime(now.year + 3, 12, 31),
                  );
                  if (d != null) {
                    setS(() {
                      start = d;
                      if (end.isBefore(start)) end = start;
                    });
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Fin : ${show(end)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: end,
                    firstDate: start,
                    lastDate: DateTime(now.year + 3, 12, 31),
                  );
                  if (d != null) setS(() => end = d);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pas de cours à l\'école'),
                value: noClass,
                onChanged: (v) => setS(() => noClass = v),
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
              if (name.text.trim().isEmpty) {
                setS(() => err = 'Donne un nom à cette période.');
                return;
              }
              await conges.add(Period(DateTime.now().millisecondsSinceEpoch,
                  name.text.trim(), dk(start), dk(end), kind, noClass));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

class CongesScreen extends StatelessWidget {
  const CongesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Congés et périodes')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ajouter',
        onPressed: () => showAddPeriod(context),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: conges,
        builder: (context, _) {
          final today = dk(DateTime.now());
          final list = List<Period>.of(conges.periods)
            ..sort((a, b) => a.start.compareTo(b.start));
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                    'Ajoute tes congés (par exemple « Vacances de janvier »). Pendant ces dates, l\'appli n\'affiche plus les cours de l\'école et n\'envoie plus leurs rappels.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: gris)),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            children: [
              for (final p in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: p.kind == 'Concours'
                            ? const Color(0xFFF97316)
                            : const Color(0xFF38BDF8)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('${p.kind} · du ${fmtDay(p.start)} au ${fmtDay(p.end)}',
                                style: const TextStyle(fontSize: 13, color: gris)),
                            Text(
                                today.compareTo(p.start) < 0
                                    ? 'À venir'
                                    : (today.compareTo(p.end) > 0 ? 'Terminé' : 'En cours'),
                                style: const TextStyle(fontSize: 12, color: clair)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => conges.remove(p.id),
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
