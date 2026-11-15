// Partage de l'appli, partage / import d'un emploi du temps, premier lancement.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

const String lienAppli =
    'https://github.com/daboujohan-hub/daj-planning/releases/latest/download/DAJ-Planning.apk';
const String lienPage = 'https://github.com/daboujohan-hub/daj-planning/releases/latest';
const String prefixeCode = 'DAJ-EDT-1:';

// ───────────────────────── Code d'emploi du temps ─────────────────────────

String encoderEmploiDuTemps(List<Slot> slots) {
  final data = [
    for (final s in slots) [s.day, s.subject, s.sh, s.sm, s.eh, s.em]
  ];
  return '$prefixeCode${base64Url.encode(utf8.encode(jsonEncode(data)))}';
}

/// Retourne null si le texte ne contient pas un code valide.
List<Slot>? decoderEmploiDuTemps(String text) {
  final m = RegExp('DAJ-EDT-1:([A-Za-z0-9_=-]+)').firstMatch(text);
  if (m == null) return null;
  try {
    final raw = utf8.decode(base64Url.decode(m.group(1)!));
    final list = jsonDecode(raw) as List;
    if (list.length > 100) return null;
    final permises = <String>{...matieres, 'Cours'};
    final out = <Slot>[];
    for (final e in list) {
      final a = e as List;
      final day = a[0] as int;
      final subject = a[1] as String;
      final sh = a[2] as int;
      final sm = a[3] as int;
      final eh = a[4] as int;
      final em = a[5] as int;
      if (day < 1 || day > 7 || !permises.contains(subject)) return null;
      if (sh < 0 || sh > 23 || eh < 0 || eh > 23) return null;
      if (sm < 0 || sm > 59 || em < 0 || em > 59) return null;
      if (eh * 60 + em <= sh * 60 + sm) return null;
      out.add(Slot(day, subject, sh, sm, eh, em));
    }
    return out;
  } catch (_) {
    return null;
  }
}

Future<bool> importerDepuisPressePapiers(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final clip = await Clipboard.getData('text/plain');
  final list = decoderEmploiDuTemps(clip?.text ?? '');
  if (list == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Aucun code d\'emploi du temps DAJ dans le presse-papiers.')));
    return false;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Importer cet emploi du temps ?'),
      content: Text(
          'Ton emploi du temps actuel sera remplacé par celui-ci (${list.length} créneaux).'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Importer')),
      ],
    ),
  );
  if (ok != true) return false;
  await state.replaceSlots(list);
  messenger.showSnackBar(const SnackBar(content: Text('Emploi du temps importé.')));
  return true;
}

// ───────────────────────── Réglages : accès ─────────────────────────

class ShareTile extends StatelessWidget {
  const ShareTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.share_outlined),
      title: const Text('Partager et importer'),
      subtitle: const Text('Lien de l\'appli, emploi du temps à envoyer ou à importer'),
      onTap: () {
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(MaterialPageRoute<void>(builder: (_) => const PartageScreen()));
      },
    );
  }
}

class PartageScreen extends StatelessWidget {
  const PartageScreen({super.key});

  Future<void> _copier(BuildContext context, String texte, String message) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: texte));
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partager et importer')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        children: [
          _titre('Partager l\'appli'),
          const Text(
              'Envoie ce lien à tes amis. Ils l\'ouvrent sur leur téléphone Android, téléchargent le fichier DAJ-Planning.apk et l\'installent (Android demandera d\'autoriser l\'installation).',
              style: TextStyle(color: clair)),
          const SizedBox(height: 10),
          const SelectableText(lienAppli, style: TextStyle(fontSize: 12, color: gris)),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.link),
            label: const Text('Copier le lien de téléchargement'),
            onPressed: () => _copier(context,
                'DAJ Planning : ton emploi du temps d\'étude sur Android.\nTélécharge et installe : $lienAppli\n(page : $lienPage)',
                'Lien copié. Colle-le dans WhatsApp.'),
          ),
          _titre('Partager mon emploi du temps'),
          const Text(
              'Tu copies un code, tu l\'envoies à un ami, et il l\'importe dans son appli : il retrouve exactement tes créneaux.',
              style: TextStyle(color: clair)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.copy),
            label: const Text('Copier le code de mon emploi du temps'),
            onPressed: () => _copier(context, encoderEmploiDuTemps(state.slots),
                'Code copié. Colle-le dans WhatsApp.'),
          ),
          _titre('Importer un emploi du temps'),
          const Text('Copie d\'abord le code reçu, puis appuie ici.',
              style: TextStyle(color: clair)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.paste),
            label: const Text('Importer depuis le presse-papiers'),
            onPressed: () => importerDepuisPressePapiers(context),
          ),
          _titre('Repartir de zéro'),
          const Text(
              'Vide ton emploi du temps pour ajouter tes propres créneaux (onglet Semaine, bouton +).',
              style: TextStyle(color: clair)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Vider mon emploi du temps'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Vider l\'emploi du temps ?'),
                  content: const Text(
                      'Tous les créneaux seront supprimés. Tes heures déjà faites sont gardées.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('Annuler')),
                    FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('Vider')),
                  ],
                ),
              );
              if (ok == true) {
                await state.replaceSlots([]);
                messenger.showSnackBar(
                    const SnackBar(content: Text('Emploi du temps vidé.')));
              }
            },
          ),
          const SizedBox(height: 22),
          const Text(
              'Tes données (heures, notes, mots) restent sur ton téléphone : personne d\'autre ne les voit.',
              style: TextStyle(fontSize: 12, color: gris)),
        ],
      ),
    );
  }
}

// ───────────────────────── Premier lancement ─────────────────────────

class OnboardingCard extends StatefulWidget {
  const OnboardingCard({super.key});
  @override
  State<OnboardingCard> createState() => _OnboardingCardState();
}

class _OnboardingCardState extends State<OnboardingCard> {
  bool done = true; // caché tant qu'on n'a pas lu la préférence

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final p = await SharedPreferences.getInstance();
      final d = p.getBool('onboardingDone') ?? false;
      if (mounted) setState(() => done = d);
    } catch (_) {
      // on ne montre rien en cas de doute
    }
  }

  Future<void> _finish() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('onboardingDone', true);
    } catch (_) {
      // sans importance
    }
    if (mounted) setState(() => done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (done) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: vert.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: vert),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bienvenue sur DAJ Planning',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
              'Choisis ton point de départ. Tu pourras toujours modifier ton emploi du temps ensuite.',
              style: TextStyle(color: clair)),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              await state.replaceSlots([]);
              await _finish();
            },
            child: const Text('Partir de zéro (emploi du temps vide)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              final ok = await importerDepuisPressePapiers(context);
              if (ok) await _finish();
            },
            child: const Text('J\'ai un code d\'emploi du temps'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _finish,
            child: const Text('Garder le modèle actuel'),
          ),
        ],
      ),
    );
  }
}
