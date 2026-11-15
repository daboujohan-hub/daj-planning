// Bloc « Apprendre » : dictionnaire, cartes de révision, quiz du jour,
// texte du jour à lire à voix haute, prononciation hors ligne.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';

// ───────────────────────── Prononciation ─────────────────────────

final FlutterTts _tts = FlutterTts();

Future<void> parler(BuildContext context, String texte, String lang) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await _tts.stop();
    await _tts.setLanguage(lang == 'en' ? 'en-US' : 'fr-FR');
    await _tts.setSpeechRate(0.45);
    await _tts.speak(texte);
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Lecture à voix haute impossible sur ce téléphone.')));
  }
}

// ───────────────────────── Données ─────────────────────────

class Word {
  final int id;
  final String term, meaning, example, lang; // lang : fr ou en
  final int box; // 0 à 5 (plus c'est haut, mieux c'est su)
  final String due; // prochaine révision, aaaa-mm-jj
  const Word(this.id, this.term, this.meaning, this.example, this.lang, this.box, this.due);

  Word copy({String? term, String? meaning, String? example, String? lang, int? box, String? due}) =>
      Word(id, term ?? this.term, meaning ?? this.meaning, example ?? this.example,
          lang ?? this.lang, box ?? this.box, due ?? this.due);

  factory Word.fromJson(Map<String, dynamic> j) => Word(
      j['i'] as int,
      j['t'] as String,
      j['m'] as String,
      (j['e'] as String?) ?? '',
      (j['l'] as String?) ?? 'fr',
      (j['b'] as int?) ?? 0,
      j['d'] as String);

  Map<String, dynamic> toJson() =>
      {'i': id, 't': term, 'm': meaning, 'e': example, 'l': lang, 'b': box, 'd': due};
}

/// Jours avant la prochaine révision, selon la boîte (0 à 5).
const List<int> intervalles = [0, 1, 3, 7, 14, 30];

class Apprendre extends ChangeNotifier {
  SharedPreferences? _p;
  List<Word> words = [];
  Map<String, int> scores = {}; // 'date|matière' -> score sur 5
  int textsRead = 0;
  String lastTextDate = '';

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _p = p;
      final w = p.getString('words');
      if (w != null) {
        words = (jsonDecode(w) as List)
            .map((e) => Word.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      final s = p.getString('quizScores');
      if (s != null) {
        scores = (jsonDecode(s) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toInt()));
      }
      textsRead = p.getInt('textsRead') ?? 0;
      lastTextDate = p.getString('lastTextDate') ?? '';
    } catch (_) {
      // données illisibles : on repart de zéro
    }
  }

  Future<void> _saveWords() async {
    notifyListeners();
    await _p?.setString('words', jsonEncode(words.map((w) => w.toJson()).toList()));
  }

  Future<void> addWord(String term, String meaning, String example, String lang) async {
    final now = DateTime.now();
    words = [
      ...words,
      Word(now.millisecondsSinceEpoch, term, meaning, example, lang, 0, dk(now)),
    ];
    await _saveWords();
  }

  Future<void> updateWord(Word w) async {
    words = words.map((x) => x.id == w.id ? w : x).toList();
    await _saveWords();
  }

  Future<void> deleteWord(int id) async {
    words = words.where((w) => w.id != id).toList();
    await _saveWords();
  }

  List<Word> due(DateTime now) {
    final k = dk(now);
    return words.where((w) => w.due.compareTo(k) <= 0).toList();
  }

  Future<void> answer(Word w, bool knew, DateTime now) async {
    final nb = knew ? (w.box + 1 > 5 ? 5 : w.box + 1) : 0;
    final next = DateTime(now.year, now.month, now.day + intervalles[nb]);
    await updateWord(w.copy(box: nb, due: dk(next)));
  }

  int? scoreOf(DateTime now, String subject) => scores['${dk(now)}|$subject'];

  Future<void> saveScore(DateTime now, String subject, int score) async {
    final key = '${dk(now)}|$subject';
    final old = scores[key] ?? -1;
    if (score > old) scores = {...scores, key: score};
    notifyListeners();
    await _p?.setString('quizScores', jsonEncode(scores));
  }

  Future<void> markTextRead(DateTime now) async {
    if (lastTextDate == dk(now)) return;
    textsRead++;
    lastTextDate = dk(now);
    notifyListeners();
    await _p?.setInt('textsRead', textsRead);
    await _p?.setString('lastTextDate', lastTextDate);
  }
}

final Apprendre apprendre = Apprendre();

// ───────────────────────── Carte « Aujourd'hui » ─────────────────────────

class ApprendreCard extends StatelessWidget {
  const ApprendreCard({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: apprendre,
      builder: (context, _) {
        final now = DateTime.now();
        final n = apprendre.due(now).length;
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.menu_book, size: 18),
                label: Text('Dictionnaire (${apprendre.words.length})'),
                onPressed: () => _open(context, const DictionaryScreen()),
              ),
              ActionChip(
                avatar: const Icon(Icons.style, size: 18),
                label: Text(n > 0 ? 'Cartes ($n à revoir)' : 'Cartes'),
                onPressed: () => _open(context, const CardsScreen()),
              ),
              ActionChip(
                avatar: const Icon(Icons.quiz_outlined, size: 18),
                label: const Text('Quiz du jour'),
                onPressed: () => _open(context, const QuizScreen()),
              ),
              ActionChip(
                avatar: const Icon(Icons.record_voice_over_outlined, size: 18),
                label: const Text('Texte du jour'),
                onPressed: () => _open(context, const TextScreen()),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Dictionnaire ─────────────────────────

Future<void> showWordDialog(BuildContext context, {Word? old}) async {
  final term = TextEditingController(text: old?.term ?? '');
  final meaning = TextEditingController(text: old?.meaning ?? '');
  final example = TextEditingController(text: old?.example ?? '');
  var lang = old?.lang ?? 'fr';
  String? err;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(old == null ? 'Nouveau mot' : 'Modifier le mot'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fr', label: Text('Français')),
                  ButtonSegment(value: 'en', label: Text('Anglais')),
                ],
                selected: {lang},
                onSelectionChanged: (s) => setS(() => lang = s.first),
              ),
              TextField(
                controller: term,
                decoration: const InputDecoration(labelText: 'Mot ou expression'),
              ),
              TextField(
                controller: meaning,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Sens'),
              ),
              TextField(
                controller: example,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Exemple (facultatif)'),
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
              final t = term.text.trim();
              final m = meaning.text.trim();
              if (t.isEmpty || m.isEmpty) {
                setS(() => err = 'Écris le mot et son sens.');
                return;
              }
              if (old == null) {
                await apprendre.addWord(t, m, example.text.trim(), lang);
              } else {
                await apprendre.updateWord(
                    old.copy(term: t, meaning: m, example: example.text.trim(), lang: lang));
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});
  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon dictionnaire')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ajouter un mot',
        onPressed: () => showWordDialog(context),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: apprendre,
        builder: (context, _) {
          final list = apprendre.words
              .where((w) =>
                  q.isEmpty ||
                  w.term.toLowerCase().contains(q) ||
                  w.meaning.toLowerCase().contains(q))
              .toList()
            ..sort((a, b) => a.term.toLowerCase().compareTo(b.term.toLowerCase()));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            children: [
              TextField(
                onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Chercher un mot…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),
              if (apprendre.words.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Ton dictionnaire est vide. Appuie sur + pour ajouter un mot : tu pourras l\'écouter et le réviser avec les cartes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: gris)),
                ),
              for (final w in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF374151)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => showWordDialog(context, old: w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${w.term}  ·  ${w.lang == 'en' ? 'anglais' : 'français'}',
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.bold)),
                              Text(w.meaning, style: const TextStyle(color: clair)),
                              if (w.example.isNotEmpty)
                                Text('« ${w.example} »',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: gris,
                                        fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Écouter',
                        icon: const Icon(Icons.volume_up_outlined),
                        onPressed: () => parler(context, w.term, w.lang),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => apprendre.deleteWord(w.id),
                      ),
                    ],
                  ),
                ),
              const Text(
                  'Si tu n\'entends rien : Réglages Android, Synthèse vocale, et installe la voix française ou anglaise.',
                  style: TextStyle(fontSize: 12, color: gris)),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── Cartes de révision ─────────────────────────

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});
  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  late List<Word> queue;
  final Set<int> requeued = {};
  bool revealed = false;
  int ok = 0;
  int ko = 0;
  int total = 0;

  @override
  void initState() {
    super.initState();
    queue = apprendre.due(DateTime.now());
    total = queue.length;
  }

  Future<void> _answer(bool knew) async {
    final w = queue.first;
    await apprendre.answer(w, knew, DateTime.now());
    setState(() {
      queue = queue.sublist(1);
      revealed = false;
      if (knew) {
        ok++;
      } else {
        ko++;
        if (requeued.add(w.id)) queue = [...queue, w.copy(box: 0)];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cartes de révision')),
      body: Builder(builder: (context) {
        if (total == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Text(
                  apprendre.words.isEmpty
                      ? 'Ajoute d\'abord des mots dans ton dictionnaire.'
                      : 'Rien à revoir aujourd\'hui. Reviens demain !',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: gris, fontSize: 16)),
            ),
          );
        }
        if (queue.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, size: 56, color: vert),
                  const SizedBox(height: 12),
                  const Text('Révision terminée, bravo !',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('$ok su${ok > 1 ? 's' : ''}, $ko à revoir',
                      style: const TextStyle(color: gris)),
                ],
              ),
            ),
          );
        }
        final w = queue.first;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${total - queue.length + (queue.length > 0 ? 1 : 0)} / $total',
                style: const TextStyle(color: gris)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: vert.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: vert),
              ),
              child: Column(
                children: [
                  Text(w.term,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  IconButton(
                    tooltip: 'Écouter',
                    icon: const Icon(Icons.volume_up_outlined),
                    onPressed: () => parler(context, w.term, w.lang),
                  ),
                  const SizedBox(height: 10),
                  if (revealed) ...[
                    Text(w.meaning,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18)),
                    if (w.example.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('« ${w.example} »',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: gris, fontStyle: FontStyle.italic)),
                    ],
                  ] else
                    const Text('Essaie de te rappeler le sens…',
                        style: TextStyle(color: gris)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!revealed)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => setState(() => revealed = true),
                child: const Text('Voir la réponse'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => _answer(false),
                      child: const Text('À revoir'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: vert,
                          foregroundColor: const Color(0xFF04210F)),
                      onPressed: () => _answer(true),
                      child: const Text('Je savais'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            const Text(
                'Un mot su revient plus tard (1, 3, 7, 14, puis 30 jours). Un mot oublié revient vite.',
                style: TextStyle(fontSize: 12, color: gris)),
          ],
        );
      }),
    );
  }
}

// ───────────────────────── Quiz du jour ─────────────────────────

class Q {
  final String subject, question;
  final List<String> options;
  final int answer;
  const Q(this.subject, this.question, this.options, this.answer);
}

const List<Q> banque = [
  // Français
  Q('Français', "Quel est le pluriel de « cheval » ?", ["chevals", "chevaux", "chevaus", "chevalx"], 1),
  Q('Français', "Complète : Marie ___ fini son travail.", ["a", "à", "as", "ah"], 0),
  Q('Français', "Quel mot est un verbe ?", ["maison", "courir", "rapide", "table"], 1),
  Q('Français', "Complète : Nous ___ à l'école.", ["allons", "allez", "vont", "va"], 0),
  Q('Français', "Quel est l'infinitif de « ils sont » ?", ["avoir", "être", "faire", "aller"], 1),
  Q('Français', "Quel est le féminin de « acteur » ?", ["acteure", "actrice", "acteuse", "actrisse"], 1),
  Q('Français', "Complète : Elle ___ sa leçon.", ["apprend", "apprends", "apprent", "aprend"], 0),
  Q('Français', "Complète : ___ enfants jouent dehors.", ["Ces", "Ses", "C'est", "Sais"], 0),
  Q('Français', "Quel signe termine une question ?", [".", "!", "?", ","], 2),
  Q('Français', "Quel mot est bien écrit ?", ["dévelopement", "développement", "développemant", "dévéloppement"], 1),
  // Maths
  Q('Maths', "Combien font 7 × 8 ?", ["54", "56", "58", "64"], 1),
  Q('Maths', "3/4 s'écrit aussi :", ["0,34", "0,75", "0,25", "1,34"], 1),
  Q('Maths', "Combien font 25 % de 80 ?", ["10", "20", "25", "40"], 1),
  Q('Maths', "Quel est le périmètre d'un carré de côté 6 cm ?", ["12 cm", "24 cm", "36 cm", "18 cm"], 1),
  Q('Maths', "Quelle est l'aire d'un rectangle de 5 cm sur 3 cm ?", ["8 cm²", "15 cm²", "16 cm²", "30 cm²"], 1),
  Q('Maths', "Résous : x + 7 = 12. Que vaut x ?", ["4", "5", "19", "7"], 1),
  Q('Maths', "Combien font 2³ ?", ["6", "8", "9", "5"], 1),
  Q('Maths', "Quelle est la racine carrée de 81 ?", ["8", "9", "18", "7"], 1),
  Q('Maths', "Quelle est la somme des angles d'un triangle ?", ["90°", "180°", "270°", "360°"], 1),
  Q('Maths', "Combien font 1/2 + 1/4 ?", ["2/6", "3/4", "1/6", "2/4"], 1),
  // Anglais
  Q('Anglais', "Que signifie « hello » ?", ["Au revoir", "Bonjour", "Merci", "S'il te plaît"], 1),
  Q('Anglais', "Complète : I ___ a student.", ["am", "is", "are", "be"], 0),
  Q('Anglais', "Que signifie « cat » ?", ["chien", "chat", "oiseau", "cheval"], 1),
  Q('Anglais', "Quel est le passé de « go » ?", ["goed", "went", "gone", "going"], 1),
  Q('Anglais', "Complète : She ___ to school every day.", ["go", "goes", "going", "gone"], 1),
  Q('Anglais', "Que signifie « thank you » ?", ["Bonjour", "Merci", "Pardon", "Salut"], 1),
  Q('Anglais', "Comment dit-on « ordinateur » en anglais ?", ["computer", "keyboard", "screen", "mouse"], 0),
  Q('Anglais', "Complète : They ___ playing.", ["is", "am", "are", "be"], 2),
  Q('Anglais', "Quel est le contraire de « big » ?", ["tall", "small", "long", "wide"], 1),
  Q('Anglais', "« Where » sert à demander :", ["le temps", "un lieu", "une personne", "la raison"], 1),
  // Informatique
  Q('Informatique', "Que signifie « CPU » ?", ["Mémoire", "Processeur", "Écran", "Clavier"], 1),
  Q('Informatique', "À quoi sert Git ?", ["Dessiner des images", "Gérer les versions du code", "Écouter de la musique", "Envoyer des SMS"], 1),
  Q('Informatique', "Quelle extension a un fichier Python ?", [".pt", ".py", ".python", ".pyt"], 1),
  Q('Informatique', "À quoi sert le HTML ?", ["Faire des calculs", "Structurer une page web", "Dessiner des circuits", "Sauvegarder des photos"], 1),
  Q('Informatique', "À quoi sert une boucle ?", ["Répéter des instructions", "Éteindre l'ordinateur", "Changer de langue", "Effacer un fichier"], 0),
  Q('Informatique', "Que vaut 101 en binaire ?", ["3", "4", "5", "6"], 2),
  Q('Informatique', "À quoi sert une variable ?", ["Stocker une valeur", "Afficher un son", "Brancher un câble", "Refroidir le processeur"], 0),
  Q('Informatique', "Quel langage décrit le style d'une page web ?", ["CSS", "SQL", "Java", "Bash"], 0),
  Q('Informatique', "Que fait la commande « ls » dans Termux ?", ["Liste les fichiers", "Supprime tout", "Éteint le téléphone", "Ouvre Internet"], 0),
  Q('Informatique', "Quel mot de passe est le plus solide ?", ["1234", "ton prénom", "une phrase longue avec chiffres et symboles", "ta date de naissance"], 2),
  // Technologie
  Q('Technologie', "À quoi sert la RAM ?", ["Mémoire de travail temporaire", "Stocker les photos pour toujours", "Refroidir le PC", "Afficher l'image"], 0),
  Q('Technologie', "Le Wi-Fi permet de :", ["Se connecter sans fil", "Charger la batterie", "Imprimer en 3D", "Nettoyer l'écran"], 0),
  Q('Technologie', "Quelle est l'unité de la tension électrique ?", ["Watt", "Volt", "Mètre", "Litre"], 1),
  Q('Technologie', "Quel composant stocke les données durablement ?", ["La RAM", "Le SSD", "Le ventilateur", "Le clavier"], 1),
  Q('Technologie', "Que signifie « IP » dans « adresse IP » ?", ["Internet Protocol", "Image Pixel", "Input Power", "Instant Phone"], 0),
  Q('Technologie', "Combien de bits y a-t-il dans un octet ?", ["4", "8", "16", "10"], 1),
  Q('Technologie', "À quoi sert un capteur ?", ["Mesurer une information (température, lumière…)", "Écrire du code", "Envoyer un e-mail", "Faire du bruit"], 0),
  Q('Technologie', "Laquelle est une énergie renouvelable ?", ["Le charbon", "Le solaire", "Le pétrole", "Le gaz"], 1),
  Q('Technologie', "Le « cloud », c'est :", ["Des serveurs accessibles par Internet", "Un nuage météo", "Un type de clavier", "Un câble"], 0),
  Q('Technologie', "À quoi sert un pare-feu ?", ["Filtrer les connexions pour protéger", "Refroidir l'ordinateur", "Augmenter le volume", "Prendre des photos"], 0),
];

List<Q> questionsDuJour(DateTime now, String subject) {
  final list = banque.where((q) => q.subject == subject).toList();
  final seed = int.parse(dk(now).replaceAll('-', '')) +
      subject.codeUnits.fold(0, (a, b) => a + b);
  final idx = List<int>.generate(list.length, (i) => i)..shuffle(Random(seed));
  return [for (final i in idx.take(5)) list[i]];
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  String subject = matieres[(DateTime.now().weekday - 1) % matieres.length];
  List<Q>? qs;
  int i = 0;
  int score = 0;
  int? picked;
  final List<Q> wrong = [];
  final Set<String> added = {};

  void _start() {
    setState(() {
      qs = questionsDuJour(DateTime.now(), subject);
      i = 0;
      score = 0;
      picked = null;
      wrong.clear();
      added.clear();
    });
  }

  Future<void> _pick(int k) async {
    if (picked != null) return;
    final q = qs![i];
    setState(() {
      picked = k;
      if (k == q.answer) {
        score++;
      } else {
        wrong.add(q);
      }
    });
  }

  Future<void> _next() async {
    if (i + 1 < qs!.length) {
      setState(() {
        i++;
        picked = null;
      });
    } else {
      await apprendre.saveScore(DateTime.now(), subject, score);
      setState(() {
        i++;
        picked = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz du jour')),
      body: ListenableBuilder(
        listenable: apprendre,
        builder: (context, _) {
          final now = DateTime.now();
          if (qs == null) {
            final best = apprendre.scoreOf(now, subject);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('5 questions courtes. Choisis une matière :',
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 14),
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
                const SizedBox(height: 18),
                if (best != null)
                  Text('Ton meilleur score aujourd\'hui : $best / 5',
                      style: const TextStyle(color: vert)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Commencer'),
                  onPressed: _start,
                ),
                const SizedBox(height: 10),
                const Text('Les questions changent chaque jour.',
                    style: TextStyle(fontSize: 12, color: gris)),
              ],
            );
          }
          if (i >= qs!.length) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('$score / ${qs!.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                Text(
                    score == qs!.length
                        ? 'Parfait, bravo !'
                        : (score >= 3 ? 'Bien joué !' : 'Continue, tu progresses.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: clair)),
                const SizedBox(height: 20),
                if (wrong.isNotEmpty)
                  const Text('À retenir :',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                for (final q in wrong)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF374151)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q.question),
                        const SizedBox(height: 4),
                        Text('Réponse : ${q.options[q.answer]}',
                            style: const TextStyle(
                                color: vert, fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          icon: Icon(added.contains(q.question)
                              ? Icons.check
                              : Icons.add_card),
                          label: Text(added.contains(q.question)
                              ? 'Ajouté aux cartes'
                              : 'Ajouter à mes cartes'),
                          onPressed: added.contains(q.question)
                              ? null
                              : () async {
                                  await apprendre.addWord(q.question,
                                      q.options[q.answer], '', 'fr');
                                  setState(() => added.add(q.question));
                                },
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => setState(() => qs = null),
                  child: const Text('Terminer'),
                ),
              ],
            );
          }
          final q = qs![i];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Question ${i + 1} / ${qs!.length}  ·  $subject',
                  style: const TextStyle(color: gris)),
              const SizedBox(height: 12),
              Text(q.question,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              for (var k = 0; k < q.options.length; k++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      alignment: Alignment.centerLeft,
                      side: BorderSide(
                        color: picked == null
                            ? const Color(0xFF4B5563)
                            : (k == q.answer
                                ? vert
                                : (k == picked
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF374151))),
                        width: picked != null && (k == q.answer || k == picked) ? 2 : 1,
                      ),
                    ),
                    onPressed: () => _pick(k),
                    child: Text(q.options[k], style: const TextStyle(fontSize: 16)),
                  ),
                ),
              if (picked != null) ...[
                const SizedBox(height: 6),
                Text(
                    picked == q.answer
                        ? 'Bonne réponse !'
                        : 'Pas tout à fait. La bonne réponse : ${q.options[q.answer]}',
                    style: TextStyle(
                        color: picked == q.answer ? vert : const Color(0xFFF97316))),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: _next,
                  child: Text(i + 1 < qs!.length ? 'Suivant' : 'Voir mon score'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── Texte du jour ─────────────────────────

const List<String> textes = [
  "Je m'appelle Abou. J'étudie chaque jour.",
  "Ce matin, je lis. Ce soir, j'écris. Je suis content de progresser.",
  "J'ai un téléphone et un projet. Chaque jour, je travaille un peu, et mon projet grandit.",
  "Apprendre, c'est comme construire une maison. On pose une pierre à la fois. Aujourd'hui, j'en pose une de plus.",
  "Un développeur écrit des instructions pour l'ordinateur. Il teste, il corrige, et il recommence. Chaque erreur lui apprend quelque chose.",
  "Quand je ne comprends pas, je ne m'énerve pas. Je relis lentement, je cherche un exemple, et je pose une question. Peu à peu, les idées deviennent claires.",
  "Il vaut mieux étudier une heure chaque jour que dix heures une seule fois. La régularité fait la différence : le cerveau retient mieux quand il revoit les choses souvent.",
  "Le français, l'anglais, les maths et l'informatique sont comme quatre outils dans une même boîte. Plus j'en maîtrise, plus je peux construire de belles choses, et plus mes projets deviennent solides.",
  "Aujourd'hui, j'ai pris le temps de me concentrer pendant cinquante minutes. Puis j'ai fait une pause pour boire de l'eau et regarder au loin. Mon esprit est plus calme, et je me sens prêt à continuer.",
  "Les erreurs ne sont pas des échecs. Quand mon programme ne fonctionne pas, je lis le message avec attention. Il m'indique souvent où chercher. En corrigeant, j'apprends plus qu'en réussissant du premier coup.",
  "Mon objectif n'est pas d'être parfait, mais d'avancer chaque jour avec constance. Je note ce que j'ai appris, je révise les mots difficiles, et je prépare la prochaine séance. Doucement, mais sûrement, je deviens la personne que je veux être.",
  "Demain, je me réveillerai, je regarderai mon emploi du temps, et je commencerai par la première matière. Je ne ferai pas tout d'un coup : je ferai ce qui est prévu, avec soin. Le soir, je verrai le chemin parcouru, et je serai fier de moi, parce que j'aurai tenu ma promesse envers moi-même.",
];

class TextScreen extends StatelessWidget {
  const TextScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Texte du jour')),
      body: ListenableBuilder(
        listenable: apprendre,
        builder: (context, _) {
          final now = DateTime.now();
          final done = apprendre.lastTextDate == dk(now);
          // Un texte par jour lu ; le texte du jour est celui qu'on vient de lire s'il est déjà fait.
          var idx = apprendre.textsRead - (done ? 1 : 0);
          if (idx < 0) idx = 0;
          if (idx >= textes.length) idx = textes.length - 1;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Texte ${idx + 1} sur ${textes.length}',
                  style: const TextStyle(color: gris)),
              const SizedBox(height: 4),
              const Text('Lis à voix haute, lentement. Chaque jour, le texte s\'allonge un peu.',
                  style: TextStyle(fontSize: 13, color: gris)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Text(textes[idx],
                    style: const TextStyle(fontSize: 20, height: 1.5)),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Écouter le texte'),
                onPressed: () => parler(context, textes[idx], 'fr'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: Icon(done ? Icons.check : Icons.record_voice_over_outlined),
                label: Text(done ? 'Lu aujourd\'hui, bravo !' : 'J\'ai lu à voix haute'),
                onPressed: done ? null : () => apprendre.markTextRead(now),
              ),
              const SizedBox(height: 14),
              Text(
                  apprendre.textsRead >= textes.length
                      ? 'Tu as lu tous les textes. Le dernier reste ici pour t\'entraîner.'
                      : 'Textes lus : ${apprendre.textsRead}',
                  style: const TextStyle(fontSize: 13, color: gris)),
            ],
          );
        },
      ),
    );
  }
}
