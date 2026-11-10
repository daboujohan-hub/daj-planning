// Fonctionnalités 10, 11, 12 et 16 : carnet de notes, mini-missions,
// temps libre (limite YouTube) et vidéos éducatives.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart';

String two(int n) => n.toString().padLeft(2, '0');

class Note {
  final String date, subject, text;
  const Note(this.date, this.subject, this.text);

  factory Note.fromJson(Map<String, dynamic> j) =>
      Note(j['d'] as String, j['s'] as String, j['t'] as String);

  Map<String, dynamic> toJson() => {'d': date, 's': subject, 't': text};
}

class VideoLink {
  final String subject, title, url;
  const VideoLink(this.subject, this.title, this.url);

  factory VideoLink.fromJson(Map<String, dynamic> j) =>
      VideoLink(j['s'] as String, j['t'] as String, j['u'] as String);

  Map<String, dynamic> toJson() => {'s': subject, 't': title, 'u': url};
}

/// Recherches YouTube prêtes à l'emploi, par matière.
const Map<String, List<List<String>>> suggestions = {
  'Informatique': [
    ['Programmation pour débutants', 'programmation pour débutants cours complet'],
    ['Python en français', 'python cours débutant français'],
    ['Flutter en français', 'flutter tutoriel français'],
  ],
  'Maths': [
    ['Maths : les bases', 'cours de maths les bases'],
    ['Fractions expliquées simplement', 'fractions cours simple'],
    ['Maths niveau lycée', 'cours de maths lycée'],
  ],
  'Technologie': [
    ['Comment fonctionne un ordinateur', 'comment fonctionne un ordinateur'],
    ['Électronique pour débutants', 'électronique pour débutants cours'],
    ['Internet expliqué simplement', 'comment fonctionne internet expliqué'],
  ],
  'Français': [
    ['Apprendre à bien lire', 'apprendre à lire cours français adulte'],
    ['Orthographe et dictées', 'orthographe dictée cours'],
    ['Conjugaison facile', 'conjugaison français cours'],
  ],
  'Anglais': [
    ['English for beginners', 'english for beginners lesson'],
    ['Anglais pour informaticiens', 'anglais pour informaticiens vocabulaire'],
    ['Prononciation anglaise', 'prononciation anglais cours'],
  ],
};

class Extras extends ChangeNotifier {
  SharedPreferences? _p;
  List<Note> notes = [];
  Map<String, String> missions = {}; // matière -> mini-mission
  Map<String, int> freeMin = {}; // date -> minutes de temps libre utilisées
  int limitMin = 60;
  DateTime? freeStart;
  List<VideoLink> links = [];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      final n = p.getString('notes');
      if (n != null) {
        notes = (jsonDecode(n) as List)
            .map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      final m = p.getString('missions');
      if (m != null) missions = Map<String, String>.from(jsonDecode(m) as Map);
      final f = p.getString('freeMin');
      if (f != null) {
        freeMin = (jsonDecode(f) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toInt()));
      }
      limitMin = p.getInt('limitMin') ?? 60;
      final fs = p.getString('freeStart');
      if (fs != null) freeStart = DateTime.tryParse(fs);
      final l = p.getString('links');
      if (l != null) {
        links = (jsonDecode(l) as List)
            .map((e) => VideoLink.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      // données illisibles : on repart de zéro
    }
  }

  // ----- carnet et missions -----

  Future<void> addNote(Note n) async {
    notes = [...notes, n];
    notifyListeners();
    await _p?.setString('notes', jsonEncode(notes.map((e) => e.toJson()).toList()));
  }

  Future<void> deleteNote(Note n) async {
    notes = notes.where((e) => !identical(e, n)).toList();
    notifyListeners();
    await _p?.setString('notes', jsonEncode(notes.map((e) => e.toJson()).toList()));
  }

  Future<void> setMission(String subject, String text) async {
    missions = {...missions, subject: text};
    notifyListeners();
    await _p?.setString('missions', jsonEncode(missions));
  }

  Future<void> clearMission(String subject) async {
    missions = Map<String, String>.of(missions)..remove(subject);
    notifyListeners();
    await _p?.setString('missions', jsonEncode(missions));
  }

  // ----- temps libre -----

  bool get running => freeStart != null;

  int usedToday(DateTime now) {
    final saved = freeMin[dk(now)] ?? 0;
    final run = freeStart == null ? 0 : now.difference(freeStart!).inMinutes;
    return saved + run.clamp(0, 240).toInt();
  }

  Future<void> startFree() async {
    if (running) return;
    final now = DateTime.now();
    final remaining = limitMin - usedToday(now);
    freeStart = now;
    notifyListeners();
    await _p?.setString('freeStart', now.toIso8601String());
    if (remaining > 0) {
      unawaited(zonedNotify(
        996,
        'Limite YouTube atteinte',
        'Tu as utilisé ton temps libre du jour. Place à autre chose, sans culpabiliser.',
        now.add(Duration(minutes: remaining)),
      ));
    }
  }

  Future<void> stopFree() async {
    final st = freeStart;
    if (st == null) return;
    final spent = DateTime.now().difference(st).inMinutes.clamp(0, 240).toInt();
    final key = dk(st);
    freeMin = {...freeMin, key: (freeMin[key] ?? 0) + spent};
    freeStart = null;
    notifyListeners();
    await _p?.setString('freeMin', jsonEncode(freeMin));
    await _p?.remove('freeStart');
    unawaited(plugin.cancel(996));
  }

  Future<void> setLimit(int minutes) async {
    limitMin = minutes;
    notifyListeners();
    await _p?.setInt('limitMin', minutes);
  }

  // ----- liens vidéos -----

  Future<void> addLink(VideoLink l) async {
    links = [...links, l];
    notifyListeners();
    await _p?.setString('links', jsonEncode(links.map((e) => e.toJson()).toList()));
  }

  Future<void> removeLink(VideoLink l) async {
    links = links.where((e) => !identical(e, l)).toList();
    notifyListeners();
    await _p?.setString('links', jsonEncode(links.map((e) => e.toJson()).toList()));
  }
}

final Extras extras = Extras();

// ───────────────────────── Outils ─────────────────────────

Future<void> openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir le lien.')));
  }
}

// ───────────────────────── Note + mini-mission ─────────────────────────

Future<void> askNote(BuildContext context, Slot s) async {
  final note = TextEditingController();
  final mission = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Séance terminée : ${s.subject}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Ce que j\'ai appris (facultatif)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: mission,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Mini-mission pour la prochaine séance (facultatif)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Passer')),
        FilledButton(
          onPressed: () async {
            final n = note.text.trim();
            final m = mission.text.trim();
            if (n.isNotEmpty) await extras.addNote(Note(dk(DateTime.now()), s.subject, n));
            if (m.isNotEmpty) await extras.setMission(s.subject, m);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}

/// Carte affichée sur « Aujourd'hui » : mini-mission + accès au carnet.
class MissionCard extends StatelessWidget {
  const MissionCard({super.key});

  Slot? _upcoming(DateTime now) {
    final nowMin = now.hour * 60 + now.minute;
    final date = dk(now);
    final list = state.slots
        .where((s) =>
            s.day == now.weekday &&
            s.subject != 'Cours' &&
            s.endMin > nowMin &&
            !state.isDone(date, s))
        .toList();
    return list.isEmpty ? null : list.first;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([state, extras]),
      builder: (context, _) {
        final up = _upcoming(DateTime.now());
        final mission = up == null ? null : extras.missions[up.subject];
        final col = up?.color ?? gris;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (up != null && mission != null && mission.isNotEmpty)
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
                          Text('MISSION · ${up.subject}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                  color: col)),
                          const SizedBox(height: 4),
                          Text(mission, style: const TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => extras.clearMission(up.subject),
                      child: const Text('Fait'),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Mon carnet'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const CarnetScreen()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CarnetScreen extends StatelessWidget {
  const CarnetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon carnet')),
      body: ListenableBuilder(
        listenable: extras,
        builder: (context, _) {
          final notes = extras.notes.reversed.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              const Text('Missions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (extras.missions.isEmpty)
                const Text('Aucune mission pour le moment.',
                    style: TextStyle(color: gris))
              else
                for (final e in extras.missions.entries)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                          radius: 8, backgroundColor: couleurs[e.key] ?? Colors.grey),
                      title: Text(e.key),
                      subtitle: Text(e.value),
                      trailing: IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => extras.clearMission(e.key),
                      ),
                    ),
                  ),
              const SizedBox(height: 20),
              const Text('Ce que j\'ai appris',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (notes.isEmpty)
                const Text('Tes notes de fin de séance apparaîtront ici.',
                    style: TextStyle(color: gris))
              else
                for (final n in notes)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                          radius: 8, backgroundColor: couleurs[n.subject] ?? Colors.grey),
                      title: Text('${n.subject} · ${n.date}',
                          style: const TextStyle(fontSize: 13, color: gris)),
                      subtitle: Text(n.text, style: const TextStyle(fontSize: 15)),
                      trailing: IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => extras.deleteNote(n),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── Temps libre ─────────────────────────

class LibreScreen extends StatefulWidget {
  const LibreScreen({super.key});
  @override
  State<LibreScreen> createState() => _LibreScreenState();
}

class _LibreScreenState extends State<LibreScreen> {
  Timer? t;

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && extras.running) setState(() {});
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: extras,
      builder: (context, _) {
        final now = DateTime.now();
        final used = extras.usedToday(now);
        final limit = extras.limitMin;
        final ratio = (used / limit).clamp(0.0, 1.0).toDouble();
        final col = used >= limit
            ? const Color(0xFFEF4444)
            : (ratio >= .8 ? const Color(0xFFF97316) : vert);
        final msg = used >= limit
            ? 'Limite atteinte : c\'est le moment de faire autre chose, sans culpabiliser.'
            : 'Il te reste ${dur(limit - used)} aujourd\'hui.';
        final secs = extras.running ? now.difference(extras.freeStart!).inSeconds : 0;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            const Text('Temps libre',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('YouTube et loisirs, avec une limite douce par jour.',
                style: TextStyle(fontSize: 13, color: gris)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: col.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: col, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AUJOURD\'HUI',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: col)),
                  const SizedBox(height: 6),
                  Text('${dur(used)} / ${dur(limit)}',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF1F2A37),
                      color: col,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(msg, style: const TextStyle(color: clair)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!extras.running)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: vert,
                  foregroundColor: const Color(0xFF04210F),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Démarrer YouTube',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  await extras.startFree();
                  if (context.mounted) await openLink(context, 'https://www.youtube.com');
                },
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF6B7280)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('En cours : ${two(secs ~/ 60)}:${two(secs % 60)}',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    FilledButton.tonal(
                      onPressed: () => extras.stopFree(),
                      child: const Text('J\'ai fini'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text('Le chrono est manuel : appuie sur « J\'ai fini » quand tu quittes YouTube.',
                style: TextStyle(fontSize: 12, color: gris)),
            const SizedBox(height: 20),
            Text('Limite par jour : ${dur(limit)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Slider(
              value: limit.toDouble().clamp(15.0, 180.0).toDouble(),
              min: 15,
              max: 180,
              divisions: 11,
              label: '$limit min',
              onChanged: (v) => extras.setLimit(v.round()),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Vidéos éducatives ─────────────────────────

class VideoTile extends StatelessWidget {
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const VideoTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: gris)),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 18, color: clair),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showAddLink(BuildContext context) async {
  var subject = 'Informatique';
  final title = TextEditingController();
  final url = TextEditingController();
  String? err;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Ajouter une vidéo ou une chaîne'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: subject,
                decoration: const InputDecoration(labelText: 'Matière'),
                items: [
                  for (final m in suggestions.keys)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) {
                  if (v != null) setS(() => subject = v);
                },
              ),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Titre'),
              ),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration:
                    const InputDecoration(labelText: 'Lien YouTube (https://…)'),
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
              final raw = url.text.trim();
              final u = Uri.tryParse(raw);
              const hotes = {'www.youtube.com', 'youtube.com', 'm.youtube.com', 'youtu.be'};
              final ok = u != null && u.scheme == 'https' && hotes.contains(u.host);
              if (title.text.trim().isEmpty || !ok) {
                setS(() => err = 'Donne un titre et un lien YouTube qui commence par https://');
                return;
              }
              await extras.addLink(VideoLink(subject, title.text.trim(), raw));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    ),
  );
}

class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: extras,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Vidéos éducatives',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showAddLink(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Lien'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
                'Elles s\'ouvrent dans l\'appli YouTube et comptent comme du temps d\'étude, pas du temps libre.',
                style: TextStyle(fontSize: 13, color: gris)),
            for (final m in suggestions.keys) ...[
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: couleurs[m] ?? Colors.grey, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Text(m,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              for (final s in suggestions[m]!)
                VideoTile(
                  title: s[0],
                  subtitle: 'Recherche YouTube',
                  color: couleurs[m] ?? Colors.grey,
                  onTap: () => openLink(context,
                      'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(s[1])}'),
                ),
              for (final l in extras.links.where((l) => l.subject == m))
                VideoTile(
                  title: l.title,
                  subtitle: 'Mon lien · appui long pour supprimer',
                  color: couleurs[m] ?? Colors.grey,
                  onTap: () => openLink(context, l.url),
                  onLongPress: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Supprimer ce lien ?'),
                        content: Text(l.title),
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
                    if (ok == true) await extras.removeLink(l);
                  },
                ),
            ],
          ],
        );
      },
    );
  }
}
