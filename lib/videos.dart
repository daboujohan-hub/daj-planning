// Fonctionnalité 16 (version 2) : vidéos lues DANS l'appli, 20 sujets par matière.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'extras.dart';
import 'main.dart';

String searchUrl(String q) =>
    'https://m.youtube.com/results?search_query=${Uri.encodeQueryComponent(q)}';

/// Seuls YouTube et Google sont autorisés dans le lecteur.
bool hoteAutorise(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https') return false;
  bool est(String d) => u.host == d || u.host.endsWith('.$d');
  return est('youtube.com') || est('youtu.be') || est('google.com');
}

void openVideo(BuildContext context, String title, String url) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => VideoPlayerScreen(title: title, url: url)),
  );
}

/// 20 sujets par matière : chacun ouvre une recherche YouTube dans l'appli.
const Map<String, List<List<String>>> sujets = {
  'Informatique': [
    ["Découvrir l'informatique", "introduction à l'informatique cours débutant"],
    ["Comment fonctionne un ordinateur", "comment fonctionne un ordinateur expliqué"],
    ["Linux pour débutants", "linux pour débutants cours français"],
    ["Termux pour débutants", "termux tutoriel français débutant"],
    ["Les commandes du terminal", "commandes terminal linux débutant"],
    ["Apprendre Python : cours complet", "apprendre python cours complet débutant"],
    ["Python : variables, conditions, boucles", "python variables conditions boucles tutoriel"],
    ["Python : les fonctions", "python fonctions tutoriel débutant"],
    ["HTML et CSS pour débutants", "html css cours complet débutant"],
    ["JavaScript pour débutants", "javascript cours complet débutant"],
    ["Git et GitHub pour débutants", "git github tutoriel débutant français"],
    ["GitHub Actions expliqué", "github actions tutoriel français"],
    ["Flutter pour débutants", "flutter tutoriel complet débutant français"],
    ["Dart : les bases du langage", "dart langage cours débutant"],
    ["Créer une application mobile", "créer une application mobile débutant"],
    ["Les bases de données et SQL", "sql cours débutant français"],
    ["Algorithmique pour débutants", "algorithmique cours débutant"],
    ["Cybersécurité : les bases", "cybersécurité bases débutant"],
    ["Mots de passe et sécurité en ligne", "sécurité en ligne mots de passe expliqué"],
    ["L'intelligence artificielle expliquée", "intelligence artificielle expliquée simplement"],
  ],
  'Maths': [
    ["Calcul mental : les bases", "calcul mental astuces débutant"],
    ["Les quatre opérations", "addition soustraction multiplication division cours"],
    ["Les fractions", "fractions cours simple"],
    ["Les pourcentages", "pourcentages cours simple"],
    ["Les nombres décimaux", "nombres décimaux cours"],
    ["Proportionnalité et règle de trois", "proportionnalité règle de trois cours"],
    ["Unités et conversions", "conversions unités longueur masse cours"],
    ["Périmètres et aires", "périmètre aire formules cours"],
    ["Angles et triangles", "angles triangles cours collège"],
    ["Le théorème de Pythagore", "théorème de pythagore cours"],
    ["Équations du premier degré", "équations premier degré cours"],
    ["Calcul littéral", "calcul littéral cours"],
    ["Les puissances", "puissances cours maths"],
    ["Les racines carrées", "racine carrée cours"],
    ["Introduction aux fonctions", "fonctions introduction cours maths"],
    ["Statistiques simples", "statistiques moyenne médiane cours"],
    ["Les probabilités", "probabilités cours débutant"],
    ["Logique et raisonnement", "logique raisonnement mathématiques débutant"],
    ["Le binaire pour l'informatique", "système binaire expliqué"],
    ["Préparer le lycée en maths", "maths bases lycée remise à niveau"],
  ],
  'Technologie': [
    ["Qu'est-ce que la technologie ?", "qu'est-ce que la technologie expliqué"],
    ["Les composants d'un ordinateur", "composants d'un ordinateur expliqués"],
    ["Le processeur expliqué", "comment fonctionne un processeur"],
    ["La RAM et le stockage", "ram stockage ssd expliqué"],
    ["Le système binaire", "binaire 0 et 1 expliqué simplement"],
    ["Comment fonctionne un smartphone", "comment fonctionne un smartphone"],
    ["Comment fonctionne Internet", "comment fonctionne internet expliqué"],
    ["Réseaux : adresse IP et DNS", "adresse ip dns expliqué simplement"],
    ["Le Wi-Fi expliqué", "comment fonctionne le wifi"],
    ["L'électricité : les bases", "électricité bases tension courant résistance"],
    ["Composants électroniques", "composants électroniques débutant"],
    ["Arduino pour débutants", "arduino tutoriel débutant français"],
    ["Raspberry Pi pour débutants", "raspberry pi débutant français"],
    ["Capteurs et robotique", "robotique capteurs débutant"],
    ["L'impression 3D", "impression 3d débutant"],
    ["Les énergies renouvelables", "énergies renouvelables expliquées"],
    ["Les batteries expliquées", "comment fonctionne une batterie"],
    ["Le cloud expliqué", "cloud computing expliqué simplement"],
    ["La cybersécurité pour tous", "cybersécurité expliquée simplement"],
    ["Les technologies du futur", "technologies du futur expliquées"],
  ],
  'Français': [
    ["Apprendre à lire : les sons", "apprendre à lire les sons adulte"],
    ["Lire les syllabes", "lire les syllabes cours"],
    ["Lire à voix haute", "lecture à voix haute conseils"],
    ["L'alphabet et les accents", "accents français alphabet cours"],
    ["Écrire des phrases simples", "construire une phrase simple français"],
    ["Majuscules et ponctuation", "ponctuation majuscules cours"],
    ["La nature des mots", "nature des mots nom verbe adjectif cours"],
    ["Conjugaison : le présent", "conjugaison présent cours"],
    ["Conjugaison : le passé composé", "passé composé cours"],
    ["Conjugaison : le futur simple", "futur simple cours"],
    ["Conjugaison : l'imparfait", "imparfait cours"],
    ["Accords : genre et nombre", "accord genre nombre cours"],
    ["L'accord du participe passé", "accord participe passé cours simple"],
    ["Les homophones", "homophones a à et est cours"],
    ["Dictée facile", "dictée facile français"],
    ["Erreurs d'orthographe fréquentes", "erreurs d'orthographe fréquentes"],
    ["Rédiger un paragraphe", "rédiger un paragraphe cours"],
    ["Écrire un e-mail", "écrire un e-mail correctement"],
    ["Rédiger un CV et une lettre", "cv lettre de motivation conseils"],
    ["Comprendre un texte", "comprendre un texte lecture méthode"],
  ],
  'Anglais': [
    ["L'alphabet et la prononciation", "english alphabet pronunciation beginners"],
    ["Se présenter et saluer", "greetings introductions english beginners"],
    ["Nombres, jours, couleurs", "english numbers days colors beginners"],
    ["Le verbe to be", "verb to be english lesson beginners"],
    ["Le présent simple", "present simple english lesson"],
    ["Le présent continu", "present continuous english lesson"],
    ["Le prétérit (past simple)", "past simple english lesson"],
    ["Le futur : will et going to", "future will going to english lesson"],
    ["Poser des questions", "asking questions english beginners"],
    ["Les 1000 mots essentiels", "1000 most common english words"],
    ["Conversations de tous les jours", "everyday english conversations beginners"],
    ["Écouter l'anglais (débutant)", "english listening practice beginners"],
    ["Vocabulaire de l'informatique", "vocabulaire anglais informatique"],
    ["L'anglais pour programmer", "anglais pour programmeurs vocabulaire"],
    ["Lire une documentation en anglais", "lire documentation technique anglais"],
    ["Les prépositions", "english prepositions lesson"],
    ["Les verbes modaux", "modal verbs english lesson"],
    ["Les phrasal verbs", "phrasal verbs english lesson"],
    ["Prononciation américaine", "american english pronunciation lesson"],
    ["Écrire un e-mail en anglais", "write professional email english"],
  ],
};

// ───────────────────────── Lecteur dans l'appli ─────────────────────────

class VideoPlayerScreen extends StatefulWidget {
  final String title, url;
  const VideoPlayerScreen({super.key, required this.title, required this.url});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final WebViewController c;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(fond)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) => (!r.isMainFrame || hoteAutorise(r.url))
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageFinished: (_) {
          if (mounted) setState(() => loading = false);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await c.canGoBack()) {
          await c.goBack();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          bottom: loading
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              : null,
        ),
        body: WebViewWidget(controller: c),
      ),
    );
  }
}

// ───────────────────────── Écran Vidéos ─────────────────────────

class _SearchBox extends StatefulWidget {
  const _SearchBox();
  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  final c = TextEditingController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void go() {
    final q = c.text.trim();
    if (q.isEmpty) return;
    openVideo(context, 'Recherche : $q', searchUrl(q));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: c,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => go(),
      decoration: InputDecoration(
        hintText: 'Chercher une vidéo…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          tooltip: 'Chercher',
          icon: const Icon(Icons.arrow_forward),
          onPressed: go,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class VideosHub extends StatelessWidget {
  const VideosHub({super.key});

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
                  child: Text('Vidéos',
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
                'Elles se lisent dans l\'appli et comptent comme du temps d\'étude, pas du temps libre.',
                style: TextStyle(fontSize: 13, color: gris)),
            const SizedBox(height: 14),
            const _SearchBox(),
            const SizedBox(height: 8),
            for (final m in sujets.keys)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Row(
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
                      const SizedBox(width: 8),
                      Text('${sujets[m]!.length} sujets',
                          style: const TextStyle(fontSize: 12, color: gris)),
                    ],
                  ),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final l in extras.links.where((l) => l.subject == m))
                      VideoTile(
                        title: l.title,
                        subtitle: 'Mon lien · appui long pour supprimer',
                        color: couleurs[m] ?? Colors.grey,
                        onTap: () => openVideo(context, l.title, l.url),
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
                    for (var i = 0; i < sujets[m]!.length; i++)
                      VideoTile(
                        title: '${i + 1}. ${sujets[m]![i][0]}',
                        subtitle: 'Vidéos YouTube sur ce sujet',
                        color: couleurs[m] ?? Colors.grey,
                        onTap: () => openVideo(
                            context, sujets[m]![i][0], searchUrl(sujets[m]![i][1])),
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
