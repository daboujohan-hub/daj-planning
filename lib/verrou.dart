// Verrou par code PIN + rappels de silence pendant les cours de l'école.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'conges.dart';
import 'main.dart';

// ───────────────────────── Verrou (code PIN) ─────────────────────────

class Verrou extends ChangeNotifier {
  SharedPreferences? _p;
  String _salt = '';
  String _hash = '';
  int length = 4;
  int graceSec = 30; // délai avant reverrouillage quand on quitte l'appli
  int fails = 0;
  int lockUntilMs = 0;
  bool locked = false;

  bool get enabled => _hash.isNotEmpty;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      _salt = p.getString('pinSalt') ?? '';
      _hash = p.getString('pinHash') ?? '';
      length = p.getInt('pinLen') ?? 4;
      graceSec = p.getInt('pinGrace') ?? 30;
      fails = p.getInt('pinFails') ?? 0;
      lockUntilMs = p.getInt('pinUntil') ?? 0;
    } catch (_) {
      // illisible : on n'enferme pas l'utilisateur dehors
    }
    locked = enabled;
  }

  String _h(String pin) => sha256.convert(utf8.encode('$_salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final r = Random.secure();
    _salt = List.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _hash = _h(pin);
    length = pin.length;
    fails = 0;
    lockUntilMs = 0;
    locked = false;
    notifyListeners();
    await _p?.setString('pinSalt', _salt);
    await _p?.setString('pinHash', _hash);
    await _p?.setInt('pinLen', length);
    await _p?.setInt('pinFails', 0);
    await _p?.setInt('pinUntil', 0);
  }

  Future<void> disable() async {
    _hash = '';
    _salt = '';
    locked = false;
    notifyListeners();
    await _p?.remove('pinSalt');
    await _p?.remove('pinHash');
    await _p?.remove('pinLen');
  }

  Future<void> setGrace(int seconds) async {
    graceSec = seconds;
    notifyListeners();
    await _p?.setInt('pinGrace', seconds);
  }

  int waitSeconds() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now < lockUntilMs ? ((lockUntilMs - now) / 1000).ceil() : 0;
  }

  /// Vrai si le code est bon. Après 5 erreurs, il faut attendre (30 s, puis plus).
  Future<bool> verify(String pin) async {
    if (waitSeconds() > 0) return false;
    if (_h(pin) == _hash) {
      fails = 0;
      await _p?.setInt('pinFails', 0);
      return true;
    }
    fails++;
    if (fails >= 5) {
      final k = fails - 5 > 6 ? 6 : fails - 5;
      lockUntilMs = DateTime.now().millisecondsSinceEpoch + 30000 * (1 << k);
      await _p?.setInt('pinUntil', lockUntilMs);
    }
    await _p?.setInt('pinFails', fails);
    return false;
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  void lockNow() {
    if (enabled && !locked) {
      locked = true;
      notifyListeners();
    }
  }
}

final Verrou verrou = Verrou();

/// Place l'écran de verrouillage au-dessus de toute l'appli.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      pausedAt = DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final p = pausedAt;
      if (p != null &&
          verrou.enabled &&
          DateTime.now().difference(p).inSeconds >= verrou.graceSec) {
        verrou.lockNow();
      }
      pausedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: verrou,
      builder: (context, _) => Stack(
        children: [
          widget.child,
          if (verrou.locked) const Positioned.fill(child: LockScreen()),
        ],
      ),
    );
  }
}

// ───────────────────────── Clavier numérique ─────────────────────────

class PinPad extends StatelessWidget {
  final int length;
  final String code;
  final ValueChanged<String> onDigit;
  final VoidCallback onBack;
  const PinPad({
    super.key,
    required this.length,
    required this.code,
    required this.onDigit,
    required this.onBack,
  });

  Widget _key(String label, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: onTap == null ? Colors.transparent : const Color(0xFF374151)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < length; i++)
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < code.length ? vert : Colors.transparent,
                  border: Border.all(color: i < code.length ? vert : gris, width: 1.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) _key(d, () => onDigit(d))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _key('', null),
            _key('0', () => onDigit('0')),
            _key('⌫', onBack),
          ],
        ),
      ],
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String code = '';
  String? msg;
  bool busy = false;

  Future<void> _digit(String d) async {
    if (busy || code.length >= verrou.length) return;
    setState(() {
      code += d;
      msg = null;
    });
    if (code.length == verrou.length) {
      busy = true;
      final ok = await verrou.verify(code);
      busy = false;
      if (!mounted) return;
      if (ok) {
        verrou.unlock();
      } else {
        final w = verrou.waitSeconds();
        setState(() {
          code = '';
          msg = w > 0 ? 'Trop d\'essais. Réessaie dans $w s.' : 'Code incorrect.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fond,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40, color: vert),
                const SizedBox(height: 12),
                const Text('DAJ Planning',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Entre ton code', style: TextStyle(color: gris)),
                const SizedBox(height: 22),
                PinPad(
                  length: verrou.length,
                  code: code,
                  onDigit: _digit,
                  onBack: () {
                    if (code.isNotEmpty) {
                      setState(() => code = code.substring(0, code.length - 1));
                    }
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 20,
                  child: Text(msg ?? '',
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Réglages du verrou ─────────────────────────

class LockTile extends StatelessWidget {
  const LockTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_outline),
      title: const Text('Verrou par code'),
      subtitle: ListenableBuilder(
        listenable: verrou,
        builder: (context, _) => Text(verrou.enabled ? 'Activé' : 'Désactivé'),
      ),
      onTap: () {
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(MaterialPageRoute<void>(builder: (_) => const LockSettingsScreen()));
      },
    );
  }
}

class LockSettingsScreen extends StatelessWidget {
  const LockSettingsScreen({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verrou par code')),
      body: ListenableBuilder(
        listenable: verrou,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                  verrou.enabled
                      ? 'Un code est demandé à l\'ouverture de l\'appli.'
                      : 'Protège tes notes, tes heures et ton carnet avec un code à 4 ou 6 chiffres.',
                  style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 18),
              if (!verrou.enabled)
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.lock),
                  label: const Text('Définir un code'),
                  onPressed: () => _push(context, const PinSetupScreen()),
                )
              else ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Changer le code'),
                  onPressed: () => _push(
                      context,
                      PinCheckScreen(
                        title: 'Entre ton code actuel',
                        onOk: (ctx) => Navigator.pushReplacement(
                            ctx,
                            MaterialPageRoute<void>(
                                builder: (_) => const PinSetupScreen())),
                      )),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Désactiver le code'),
                  onPressed: () => _push(
                      context,
                      PinCheckScreen(
                        title: 'Entre ton code pour le désactiver',
                        onOk: (ctx) async {
                          await verrou.disable();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      )),
                ),
                const SizedBox(height: 24),
                const Text('Reverrouiller après avoir quitté l\'appli',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Tout de suite')),
                    ButtonSegment(value: 30, label: Text('30 s')),
                    ButtonSegment(value: 300, label: Text('5 min')),
                  ],
                  selected: {verrou.graceSec},
                  onSelectionChanged: (s) => verrou.setGrace(s.first),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                  'Important : si tu oublies ton code, il n\'y a aucun moyen de le retrouver. Il faudra désinstaller l\'appli et tu perdras tes données. Fais une sauvegarde avant (Réglages, Sauvegarde et restauration).',
                  style: TextStyle(fontSize: 13, color: Color(0xFFF97316))),
              const SizedBox(height: 10),
              const Text(
                  'Ce code protège l\'accès à l\'appli sur ton téléphone. Après 5 erreurs, il faut attendre avant de réessayer.',
                  style: TextStyle(fontSize: 13, color: gris)),
            ],
          );
        },
      ),
    );
  }
}

class PinCheckScreen extends StatefulWidget {
  final String title;
  final FutureOr<void> Function(BuildContext) onOk;
  const PinCheckScreen({super.key, required this.title, required this.onOk});

  @override
  State<PinCheckScreen> createState() => _PinCheckScreenState();
}

class _PinCheckScreenState extends State<PinCheckScreen> {
  String code = '';
  String? msg;
  bool busy = false;

  Future<void> _digit(String d) async {
    if (busy || code.length >= verrou.length) return;
    setState(() {
      code += d;
      msg = null;
    });
    if (code.length == verrou.length) {
      busy = true;
      final ok = await verrou.verify(code);
      busy = false;
      if (!mounted) return;
      if (ok) {
        await widget.onOk(context);
      } else {
        final w = verrou.waitSeconds();
        setState(() {
          code = '';
          msg = w > 0 ? 'Trop d\'essais. Réessaie dans $w s.' : 'Code incorrect.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PinPad(
                length: verrou.length,
                code: code,
                onDigit: _digit,
                onBack: () {
                  if (code.isNotEmpty) {
                    setState(() => code = code.substring(0, code.length - 1));
                  }
                },
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 20,
                child: Text(msg ?? '',
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});
  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  int len = 4;
  String first = '';
  String code = '';
  bool confirm = false;
  String? msg;

  Future<void> _digit(String d) async {
    if (code.length >= len) return;
    setState(() {
      code += d;
      msg = null;
    });
    if (code.length < len) return;
    if (!confirm) {
      setState(() {
        first = code;
        code = '';
        confirm = true;
      });
    } else if (code == first) {
      await verrou.setPin(first);
      if (mounted) Navigator.pop(context);
    } else {
      setState(() {
        code = '';
        first = '';
        confirm = false;
        msg = 'Les deux codes ne sont pas identiques. Recommence.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau code')),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(confirm ? 'Entre-le une deuxième fois' : 'Choisis ton code',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (!confirm && code.isEmpty)
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 4, label: Text('4 chiffres')),
                    ButtonSegment(value: 6, label: Text('6 chiffres')),
                  ],
                  selected: {len},
                  onSelectionChanged: (s) => setState(() => len = s.first),
                )
              else
                const SizedBox(height: 40),
              const SizedBox(height: 24),
              PinPad(
                length: len,
                code: code,
                onDigit: _digit,
                onBack: () {
                  if (code.isNotEmpty) {
                    setState(() => code = code.substring(0, code.length - 1));
                  }
                },
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(msg ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Rappels de silence (cours) ─────────────────────────

class Silence extends ChangeNotifier {
  SharedPreferences? _p;
  bool enabled = false;
  Timer? _debounce;
  String _sig = '';

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      enabled = p.getBool('silence') ?? false;
    } catch (_) {
      enabled = false;
    }
    state.addListener(_onChange);
    conges.addListener(_onChange);
  }

  void _onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      reschedule();
    });
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    notifyListeners();
    await _p?.setBool('silence', v);
    await reschedule(force: true);
  }

  /// Pour chaque cours des 3 prochaines semaines (hors congés) :
  /// 5 min avant « mets ton téléphone en silencieux », à la fin « remets le son ».
  Future<void> reschedule({bool force = false}) async {
    final now = DateTime.now();
    final cours = state.slots.where((s) => s.subject == 'Cours').toList();
    final sig =
        '$enabled|${cours.map((s) => s.key).join(',')}|${conges.periods.map((p) => '${p.start}${p.end}${p.noClass}').join(',')}|${dk(now)}';
    if (!force && sig == _sig) return;
    _sig = sig;
    try {
      final pend = await plugin.pendingNotificationRequests();
      for (final r in pend) {
        if (r.id >= 6000 && r.id < 7000) await plugin.cancel(r.id);
      }
      if (!enabled) return;
      var n = 0;
      for (final s in cours) {
        for (var off = 0; off < 21; off++) {
          final day = DateTime(now.year, now.month, now.day + off);
          if (day.weekday != s.day || conges.isOff(day)) continue;
          final debut = DateTime(day.year, day.month, day.day, s.sh, s.sm - 5);
          final fin = DateTime(day.year, day.month, day.day, s.eh, s.em);
          if (debut.isAfter(now)) {
            await zonedNotify(6000 + n, 'Cours dans 5 min',
                'Passe ton téléphone en silencieux.', debut);
            n++;
          }
          if (fin.isAfter(now)) {
            await zonedNotify(6000 + n, 'Cours terminé',
                'Tu peux remettre le son.', fin);
            n++;
          }
          if (n > 900) return;
        }
      }
    } catch (_) {
      // les rappels sont un plus : on ne bloque jamais l'appli
    }
  }
}

final Silence silence = Silence();

class SilenceTile extends StatelessWidget {
  const SilenceTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: silence,
      builder: (context, _) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.volume_off_outlined),
        title: const Text('Rappels de silence en cours'),
        subtitle: const Text(
            '5 min avant chaque cours : « mets ton téléphone en silencieux », et à la fin : « remets le son ».'),
        value: silence.enabled,
        onChanged: (v) => silence.setEnabled(v),
      ),
    );
  }
}
