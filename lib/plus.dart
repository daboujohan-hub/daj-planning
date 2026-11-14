// Fonctionnalités 14 et 15 : sauvegarde / restauration et taille du texte.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

final ValueNotifier<double> textScale = ValueNotifier<double>(1.0);

Future<void> loadPlus() async {
  try {
    final p = await SharedPreferences.getInstance();
    textScale.value = (p.getDouble('textScale') ?? 1.0).clamp(0.8, 1.6).toDouble();
  } catch (_) {
    textScale.value = 1.0;
  }
}

Future<void> saveTextScale(double v) async {
  textScale.value = v;
  final p = await SharedPreferences.getInstance();
  await p.setDouble('textScale', v);
}

// ───────────────────────── Sauvegarde ─────────────────────────

Future<String> buildBackup() async {
  final p = await SharedPreferences.getInstance();
  final data = <String, dynamic>{};
  for (final k in p.getKeys()) {
    data[k] = p.get(k);
  }
  return jsonEncode({'app': 'DAJ Planning', 'v': 1, 'data': data});
}

Future<bool> restoreBackup(String text) async {
  try {
    final m = jsonDecode(text) as Map<String, dynamic>;
    if (m['app'] != 'DAJ Planning') return false;
    final data = Map<String, dynamic>.from(m['data'] as Map);
    final p = await SharedPreferences.getInstance();
    await p.clear();
    for (final e in data.entries) {
      final v = e.value;
      if (v is String) {
        await p.setString(e.key, v);
      } else if (v is int) {
        await p.setInt(e.key, v);
      } else if (v is double) {
        await p.setDouble(e.key, v);
      } else if (v is bool) {
        await p.setBool(e.key, v);
      } else if (v is List) {
        await p.setStringList(e.key, v.map((x) => x.toString()).toList());
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await buildBackup();
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(
        content: Text('Sauvegarde copiée (${text.length} caractères). Colle-la dans une note privée.')));
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final clip = await Clipboard.getData('text/plain');
    final text = clip?.text ?? '';
    if (text.trim().isEmpty || !text.contains('DAJ Planning')) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Aucune sauvegarde DAJ Planning dans le presse-papiers.')));
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restaurer la sauvegarde ?'),
        content: const Text(
            'Toutes les données actuelles seront remplacées par celles de la sauvegarde.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true), child: const Text('Restaurer')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await restoreBackup(text);
    if (!context.mounted) return;
    if (!done) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Sauvegarde illisible : rien n\'a été changé.')));
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: const Text('Données restaurées'),
        content: const Text('L\'appli va se fermer. Rouvre-la pour retrouver tes données.'),
        actions: [
          FilledButton(
              onPressed: () => SystemNavigator.pop(), child: const Text('Fermer l\'appli')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
              'Ta sauvegarde contient ton emploi du temps, tes heures, tes notes, tes missions, tes objectifs et tes réglages.',
              style: TextStyle(fontSize: 15)),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.copy),
            label: const Text('Copier ma sauvegarde'),
            onPressed: () => _copy(context),
          ),
          const SizedBox(height: 6),
          const Text(
              'Colle-la ensuite dans une note privée (Keep, par exemple). Efface-la du presse-papiers après usage : elle contient tes notes.',
              style: TextStyle(fontSize: 13, color: gris)),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.restore_page_outlined),
            label: const Text('Restaurer depuis le presse-papiers'),
            onPressed: () => _restore(context),
          ),
          const SizedBox(height: 6),
          const Text(
              'Copie d\'abord le texte de ta sauvegarde depuis ta note, puis appuie ici.',
              style: TextStyle(fontSize: 13, color: gris)),
        ],
      ),
    );
  }
}

// ───────────────────────── Taille du texte ─────────────────────────

void showTextSize(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Taille du texte'),
      content: ValueListenableBuilder<double>(
        valueListenable: textScale,
        builder: (context, s, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${(s * 100).round()} %',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Slider(
              value: s,
              min: 0.8,
              max: 1.4,
              divisions: 6,
              onChanged: (v) => saveTextScale(v),
            ),
            const Text('Exemple : un pas à la fois, sans pression.'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => saveTextScale(1.0), child: const Text('Normal')),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// Lignes ajoutées dans les Réglages.
class PlusTiles extends StatelessWidget {
  const PlusTiles({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.text_fields),
          title: const Text('Taille du texte'),
          subtitle: ValueListenableBuilder<double>(
            valueListenable: textScale,
            builder: (context, s, _) => Text('${(s * 100).round()} %'),
          ),
          onTap: () => showTextSize(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Sauvegarde et restauration'),
          onTap: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute<void>(builder: (_) => const BackupScreen()));
          },
        ),
      ],
    );
  }
}
