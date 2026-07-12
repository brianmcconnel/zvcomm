import 'emoji_data.dart';

/// Keyword + fuzzy index so users can search "heart", "fir", "smil", etc.
///
/// Results are ranked best-first (exact → prefix → contains → fuzzy).
abstract final class EmojiSearch {
  /// Returns emojis matching [query], best matches first.
  ///
  /// Space/underscore-separated terms are AND'd (all must match).
  static List<String> search(String query, {int limit = 80}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // Exact emoji paste → single result.
    if (_allSet.contains(trimmed)) return [trimmed];

    final raw = trimmed.toLowerCase();
    final terms =
        raw.split(RegExp(r'[\s,_-]+')).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return const [];

    final scored = <({String emoji, int score})>[];
    final catalog = EmojiCatalog.all;
    for (var i = 0; i < catalog.length; i++) {
      final e = catalog[i];
      final keys = _keywordsFor(e);
      var total = 0;
      var ok = true;
      for (final t in terms) {
        final s = _bestTermScore(keys, t);
        if (s <= 0) {
          ok = false;
          break;
        }
        total += s;
      }
      if (!ok) continue;

      // Prefer specific aliases over bare category tags.
      if (_aliases.containsKey(e)) total += 25;
      // Slight boost for quick-reaction strip.
      if (EmojiCatalog.quickReactions.contains(e)) total += 15;
      // Stable tie-break: earlier catalog order slightly preferred.
      total += (catalog.length - i) ~/ 200;

      scored.add((emoji: e, score: total));
    }

    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.emoji.compareTo(b.emoji);
    });

    if (scored.length <= limit) {
      return [for (final s in scored) s.emoji];
    }
    return [for (final s in scored.take(limit)) s.emoji];
  }

  /// Best score of [term] against any keyword / keyword word.
  static int _bestTermScore(List<String> keys, String term) {
    var best = 0;
    for (final k in keys) {
      best = _max(best, _scoreAgainst(k, term));
      // Multi-word keywords: "thumbs up" → also score "thumbs", "up".
      if (k.contains(' ') || k.contains('-')) {
        for (final part in k.split(RegExp(r'[\s-]+'))) {
          if (part.isEmpty) continue;
          best = _max(best, _scoreAgainst(part, term));
        }
      }
    }
    return best;
  }

  /// Score how well [keyword] matches [term] (higher = better).
  static int _scoreAgainst(String keyword, String term) {
    if (keyword.isEmpty || term.isEmpty) return 0;
    if (keyword == term) return 1000;

    // Prefix: "hea" → "heart"
    if (keyword.startsWith(term)) {
      // Tighter prefix (covers more of keyword) ranks higher.
      final coverage = (term.length * 100) ~/ keyword.length;
      return 700 + coverage;
    }

    // Word-boundary-ish: keyword contains term as whole token start
    // e.g. term "eye" in "heart eyes"
    final idx = keyword.indexOf(term);
    if (idx >= 0) {
      final atStart =
          idx == 0 || keyword[idx - 1] == ' ' || keyword[idx - 1] == '-';
      return atStart ? 500 : 350;
    }

    // Fuzzy subsequence: "hrt" → "heart", "thms" → "thumbs"
    if (term.length >= 2 && _isSubsequence(term, keyword)) {
      final density = (term.length * 100) ~/ keyword.length;
      return 200 + density;
    }

    // Typo tolerance (edit distance) for longer queries.
    if (term.length >= 3 && keyword.length >= 3) {
      final maxLen =
          keyword.length > term.length ? keyword.length : term.length;
      // Only compare when lengths are close.
      if ((keyword.length - term.length).abs() <= 2) {
        final d = _editDistance(term, keyword, maxDist: 2);
        if (d == 1) return 180;
        if (d == 2 && term.length >= 5) return 100;
      }
      // Prefix of keyword with 1 typo: "hearr" ≈ "heart"
      if (keyword.length >= term.length) {
        final head = keyword.substring(0, term.length.clamp(0, keyword.length));
        final d = _editDistance(term, head, maxDist: 1);
        if (d == 1) return 220;
      }
      // Avoid unused warning
      if (maxLen < 0) return 0;
    }

    return 0;
  }

  static bool _isSubsequence(String needle, String haystack) {
    var i = 0;
    for (var j = 0; j < haystack.length && i < needle.length; j++) {
      if (haystack.codeUnitAt(j) == needle.codeUnitAt(i)) i++;
    }
    return i == needle.length;
  }

  /// Bounded Levenshtein; returns > [maxDist] if exceeded.
  static int _editDistance(String a, String b, {int maxDist = 2}) {
    if (a == b) return 0;
    final m = a.length;
    final n = b.length;
    if ((m - n).abs() > maxDist) return maxDist + 1;

    // Two-row DP
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      var rowMin = curr[0];
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = _min3(
          prev[j] + 1,
          curr[j - 1] + 1,
          prev[j - 1] + cost,
        );
        if (curr[j] < rowMin) rowMin = curr[j];
      }
      if (rowMin > maxDist) return maxDist + 1;
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }

  static int _min3(int a, int b, int c) {
    final x = a < b ? a : b;
    return x < c ? x : c;
  }

  static int _max(int a, int b) => a > b ? a : b;

  static final Set<String> _allSet = EmojiCatalog.all.toSet();

  static final Map<String, List<String>> _cache = {};

  static List<String> _keywordsFor(String emoji) {
    final cached = _cache[emoji];
    if (cached != null) return cached;

    final keys = <String>{};

    // Category membership (lower weight via scoring, still searchable).
    for (final c in EmojiCatalog.categories) {
      if (c.emojis.contains(emoji)) {
        keys.add(c.name.toLowerCase());
        keys.addAll(_categoryTags[c.name] ?? const []);
      }
    }

    // Specific aliases (primary search surface).
    final specific = _aliases[emoji];
    if (specific != null) {
      for (final s in specific) {
        keys.add(s.toLowerCase());
      }
    }

    // Quick reactions tag.
    if (EmojiCatalog.quickReactions.contains(emoji)) {
      keys.addAll(const ['reaction', 'quick', 'react']);
    }

    final list = keys.toList(growable: false);
    _cache[emoji] = list;
    return list;
  }

  static const _categoryTags = <String, List<String>>{
    'Smileys': [
      'face',
      'emotion',
      'smiley',
      'mood',
      'expression',
    ],
    'Gestures': [
      'hand',
      'gesture',
      'body',
      'finger',
      'sign',
    ],
    'People': [
      'person',
      'people',
      'human',
      'man',
      'woman',
      'family',
    ],
    'Animals': [
      'animal',
      'nature',
      'pet',
      'plant',
      'weather',
      'flower',
      'tree',
    ],
    'Food': [
      'food',
      'drink',
      'eat',
      'meal',
      'fruit',
      'vegetable',
    ],
    'Travel': [
      'travel',
      'place',
      'car',
      'plane',
      'building',
      'map',
      'vehicle',
    ],
    'Activities': [
      'sport',
      'game',
      'music',
      'hobby',
      'play',
      'ball',
    ],
    'Objects': [
      'object',
      'tool',
      'thing',
      'device',
      'phone',
      'book',
    ],
    'Symbols': [
      'symbol',
      'sign',
      'arrow',
      'heart',
      'number',
      'shape',
    ],
    'Flags': [
      'flag',
      'country',
      'nation',
    ],
  };

  /// Per-emoji search aliases (common CLDR-style short names).
  static const _aliases = <String, List<String>>{
    // Smileys
    '😀': ['grinning', 'smile', 'happy', 'joy'],
    '😃': ['smile', 'happy', 'grinning'],
    '😄': ['smile', 'happy', 'laugh'],
    '😁': ['grin', 'smile', 'happy'],
    '😆': ['laugh', 'happy', 'lol'],
    '😅': ['sweat', 'smile', 'relief', 'nervous'],
    '🤣': ['rofl', 'laugh', 'lol', 'funny'],
    '😂': ['joy', 'tears', 'laugh', 'lol', 'crying'],
    '🙂': ['smile', 'slight'],
    '🙃': ['upside', 'sarcasm'],
    '😉': ['wink', 'flirt'],
    '😊': ['blush', 'smile', 'happy'],
    '😇': ['angel', 'innocent', 'halo'],
    '🥰': ['love', 'hearts', 'adore', 'crush'],
    '😍': ['heart eyes', 'love', 'crush'],
    '🤩': ['starstruck', 'excited', 'stars'],
    '😘': ['kiss', 'blow', 'love'],
    '😗': ['kiss'],
    '☺️': ['smile', 'relaxed'],
    '😚': ['kiss', 'closed eyes'],
    '😙': ['kiss', 'smile'],
    '🥲': ['tear', 'grateful', 'smile'],
    '😋': ['yum', 'delicious', 'tongue'],
    '😛': ['tongue', 'playful'],
    '😜': ['wink', 'tongue', 'joke'],
    '🤪': ['zany', 'goofy', 'crazy'],
    '😝': ['tongue', 'squint'],
    '🤑': ['money', 'rich', 'dollar'],
    '🤗': ['hug', 'hugging'],
    '🤭': ['oops', 'giggle', 'secret'],
    '🤫': ['shh', 'quiet', 'secret'],
    '🤔': ['think', 'thinking', 'hmm'],
    '🤐': ['zipper', 'secret', 'quiet'],
    '🤨': ['raised eyebrow', 'skeptical', 'doubt'],
    '😐': ['neutral', 'meh'],
    '😑': ['expressionless', 'blank'],
    '😶': ['silent', 'no mouth'],
    '😏': ['smirk', 'smug'],
    '😒': ['unamused', 'meh', 'sideeye'],
    '🙄': ['eyeroll', 'annoyed'],
    '😬': ['grimace', 'awkward'],
    '😮‍💨': ['exhale', 'relief', 'sigh'],
    '🤥': ['lie', 'pinocchio'],
    '😌': ['relieved', 'calm', 'peace'],
    '😔': ['sad', 'pensive', 'down'],
    '😪': ['sleepy', 'tired'],
    '🤤': ['drool', 'hungry'],
    '😴': ['sleep', 'zzz', 'tired'],
    '😷': ['mask', 'sick', 'covid'],
    '🤒': ['sick', 'fever', 'ill'],
    '🤕': ['hurt', 'bandage', 'injured'],
    '🤢': ['nauseated', 'sick', 'green'],
    '🤮': ['vomit', 'puke', 'sick'],
    '🤧': ['sneeze', 'achoo', 'sick'],
    '🥵': ['hot', 'heat', 'sweating'],
    '🥶': ['cold', 'freezing', 'ice'],
    '🥴': ['woozy', 'drunk', 'dizzy'],
    '😵': ['dizzy', 'knocked out', 'dead'],
    '🤯': ['mind blown', 'exploding', 'shocked'],
    '🤠': ['cowboy', 'hat'],
    '🥳': ['party', 'celebrate', 'birthday'],
    '🥸': ['disguise', 'glasses', 'incognito'],
    '😎': ['cool', 'sunglasses', 'awesome'],
    '🤓': ['nerd', 'glasses', 'geek'],
    '🧐': ['monocle', 'fancy', 'inspect'],
    '😕': ['confused', 'puzzled'],
    '😟': ['worried', 'concerned'],
    '🙁': ['frown', 'sad'],
    '☹️': ['frown', 'sad'],
    '😮': ['surprised', 'wow', 'open mouth'],
    '😯': ['hushed', 'surprised'],
    '😲': ['astonished', 'shocked'],
    '😳': ['flushed', 'embarrassed'],
    '🥺': ['pleading', 'puppy', 'cute', 'please'],
    '😦': ['frowning', 'open mouth'],
    '😧': ['anguished', 'pain'],
    '😨': ['fearful', 'scared'],
    '😰': ['anxious', 'sweat', 'worried'],
    '😥': ['disappointed', 'relieved', 'sad'],
    '😢': ['cry', 'sad', 'tear'],
    '😭': ['sob', 'cry', 'bawling'],
    '😱': ['scream', 'fear', 'shock'],
    '😖': ['confounded', 'frustrated'],
    '😣': ['persevering', 'struggle'],
    '😞': ['disappointed', 'sad'],
    '😓': ['downcast', 'sweat'],
    '😩': ['weary', 'tired'],
    '😫': ['tired', 'exhausted'],
    '🥱': ['yawn', 'bored', 'sleepy'],
    '😤': ['triumph', 'steam', 'huff', 'angry'],
    '😡': ['rage', 'angry', 'mad', 'pouting'],
    '😠': ['angry', 'mad'],
    '🤬': ['cursing', 'swearing', 'symbols'],
    '😈': ['smiling devil', 'evil', 'horns'],
    '👿': ['angry devil', 'imp', 'evil'],
    '💀': ['skull', 'dead', 'death'],
    '☠️': ['skull crossbones', 'poison', 'danger', 'pirate'],
    '💩': ['poop', 'poo', 'crap'],
    '🤡': ['clown'],
    '👹': ['ogre', 'monster'],
    '👺': ['goblin', 'monster'],
    '👻': ['ghost', 'boo', 'halloween'],
    '👽': ['alien', 'ufo', 'space'],
    '👾': ['alien monster', 'game', 'space'],
    '🤖': ['robot', 'bot'],
    '😺': ['cat', 'smile'],
    '😸': ['cat', 'grin'],
    '😹': ['cat', 'joy', 'tears'],
    '😻': ['cat', 'heart eyes', 'love'],
    '😼': ['cat', 'smirk'],
    '😽': ['cat', 'kiss'],
    '🙀': ['cat', 'scream', 'shock'],
    '😿': ['cat', 'cry', 'sad'],
    '😾': ['cat', 'pouting', 'angry'],

    // Gestures
    '👋': ['wave', 'hello', 'hi', 'bye', 'hand'],
    '🤚': ['raised back hand', 'stop'],
    '🖐️': ['hand', 'five', 'fingers'],
    '✋': ['raised hand', 'stop', 'high five'],
    '🖖': ['vulcan', 'spock', 'live long'],
    '👌': ['ok', 'okay', 'perfect'],
    '🤌': ['pinched', 'italian', 'what'],
    '🤏': ['pinch', 'small', 'bit'],
    '✌️': ['victory', 'peace', 'two'],
    '🤞': ['crossed fingers', 'luck', 'hope'],
    '🤟': ['love you', 'ily'],
    '🤘': ['rock', 'horns', 'metal'],
    '🤙': ['call me', 'shaka', 'hang loose'],
    '👈': ['point left'],
    '👉': ['point right'],
    '👆': ['point up'],
    '🖕': ['middle finger', 'flip'],
    '👇': ['point down'],
    '☝️': ['index', 'point up'],
    '👍': ['thumbs up', 'like', 'yes', 'approve', 'good', '+1'],
    '👎': ['thumbs down', 'dislike', 'no', 'bad', '-1'],
    '✊': ['fist', 'power'],
    '👊': ['punch', 'fist bump'],
    '🤛': ['left fist'],
    '🤜': ['right fist'],
    '👏': ['clap', 'applause', 'bravo'],
    '🙌': ['raised hands', 'hooray', 'celebration'],
    '👐': ['open hands'],
    '🤲': ['palms up', 'pray', 'please'],
    '🤝': ['handshake', 'deal', 'agree'],
    '🙏': ['pray', 'please', 'thanks', 'namaste', 'high five'],
    '✍️': ['writing', 'hand'],
    '💅': ['nail polish', 'nails', 'care'],
    '🤳': ['selfie', 'phone', 'camera'],
    '💪': ['muscle', 'flex', 'strong', 'arm'],
    '🦾': ['mechanical arm', 'prosthetic'],
    '🦿': ['mechanical leg'],
    '🦵': ['leg', 'kick'],
    '🦶': ['foot'],
    '👂': ['ear', 'hear', 'listen'],
    '🦻': ['ear aid', 'hearing'],
    '👃': ['nose', 'smell'],
    '🧠': ['brain', 'smart', 'think'],
    '🫀': ['heart organ', 'anatomy'],
    '🫁': ['lungs', 'breathe'],
    '🦷': ['tooth', 'dental'],
    '🦴': ['bone'],
    '👀': ['eyes', 'look', 'see', 'watching'],
    '👁️': ['eye', 'look'],
    '👅': ['tongue', 'lick'],
    '👄': ['mouth', 'lips'],
    '💋': ['kiss mark', 'lipstick', 'lips'],
    '🩸': ['blood', 'drop', 'period'],

    // Common hearts / symbols
    '❤️': ['heart', 'love', 'red'],
    '🧡': ['orange heart', 'love'],
    '💛': ['yellow heart', 'love'],
    '💚': ['green heart', 'love'],
    '💙': ['blue heart', 'love'],
    '💜': ['purple heart', 'love'],
    '🖤': ['black heart', 'love'],
    '🤍': ['white heart', 'love'],
    '🤎': ['brown heart', 'love'],
    '💔': ['broken heart', 'heartbreak', 'sad'],
    '❣️': ['heart exclamation', 'love'],
    '💕': ['two hearts', 'love'],
    '💞': ['revolving hearts', 'love'],
    '💓': ['beating heart', 'love'],
    '💗': ['growing heart', 'love'],
    '💖': ['sparkling heart', 'love'],
    '💘': ['cupid', 'arrow heart', 'love'],
    '💝': ['gift heart', 'love', 'present'],
    '💯': ['hundred', '100', 'perfect', 'score'],
    '🔥': ['fire', 'lit', 'hot', 'flame'],
    '✨': ['sparkles', 'shine', 'magic', 'stars'],
    '⭐': ['star'],
    '🌟': ['glowing star', 'shine'],
    '💥': ['collision', 'boom', 'explode'],
    '💫': ['dizzy star', 'sparkle'],
    '🎉': ['party', 'tada', 'celebrate', 'confetti'],
    '🎊': ['confetti', 'party', 'celebrate'],
    '🎈': ['balloon', 'party', 'birthday'],
    '🎁': ['gift', 'present', 'birthday'],
    '🏆': ['trophy', 'win', 'champion'],
    '🥇': ['gold', 'medal', 'first', '1st'],
    '🥈': ['silver', 'medal', 'second'],
    '🥉': ['bronze', 'medal', 'third'],
    '✅': ['check', 'done', 'yes', 'ok'],
    '❌': ['x', 'cross', 'no', 'wrong'],
    '⚠️': ['warning', 'caution', 'alert'],
    '❓': ['question', 'help', '?'],
    '❗': ['exclamation', 'important', '!'],
    '💤': ['zzz', 'sleep', 'tired'],
    '🎵': ['music', 'note', 'song'],
    '🎶': ['music', 'notes', 'song'],

    // Food highlights
    '🍕': ['pizza', 'food', 'cheese'],
    '🍔': ['burger', 'hamburger', 'food'],
    '🍟': ['fries', 'food'],
    '🌮': ['taco', 'food', 'mexican'],
    '🍣': ['sushi', 'food', 'japanese', 'fish'],
    '🍜': ['ramen', 'noodles', 'soup', 'food'],
    '🍦': ['icecream', 'dessert', 'sweet'],
    '🍩': ['donut', 'doughnut', 'dessert'],
    '🍪': ['cookie', 'dessert'],
    '🎂': ['cake', 'birthday', 'dessert'],
    '☕': ['coffee', 'tea', 'cafe', 'drink'],
    '🍺': ['beer', 'drink', 'alcohol'],
    '🍻': ['beers', 'cheers', 'drink'],
    '🍷': ['wine', 'drink', 'alcohol'],
    '🍹': ['cocktail', 'drink', 'tropical'],
    '🧃': ['juice', 'box', 'drink'],
    '🍎': ['apple', 'fruit', 'red'],
    '🍌': ['banana', 'fruit'],
    '🍓': ['strawberry', 'fruit', 'berry'],
    '🥑': ['avocado', 'food'],

    // Animals
    '🐶': ['dog', 'puppy', 'pet'],
    '🐱': ['cat', 'kitten', 'pet'],
    '🐭': ['mouse', 'pet'],
    '🐹': ['hamster', 'pet'],
    '🐰': ['rabbit', 'bunny', 'pet'],
    '🦊': ['fox'],
    '🐻': ['bear'],
    '🐼': ['panda'],
    '🐨': ['koala'],
    '🐯': ['tiger'],
    '🦁': ['lion'],
    '🐮': ['cow'],
    '🐷': ['pig'],
    '🐸': ['frog'],
    '🐵': ['monkey'],
    '🙈': ['see no evil', 'monkey', 'oops'],
    '🙉': ['hear no evil', 'monkey'],
    '🙊': ['speak no evil', 'monkey', 'secret'],
    '🐔': ['chicken', 'bird'],
    '🐧': ['penguin', 'bird'],
    '🐦': ['bird'],
    '🦅': ['eagle', 'bird'],
    '🦆': ['duck', 'bird'],
    '🦉': ['owl', 'bird', 'wise'],
    '🦇': ['bat', 'halloween'],
    '🐺': ['wolf'],
    '🦄': ['unicorn', 'magic'],
    '🐝': ['bee', 'honey'],
    '🐛': ['bug', 'insect'],
    '🦋': ['butterfly'],
    '🐢': ['turtle'],
    '🐍': ['snake'],
    '🐙': ['octopus'],
    '🐠': ['fish', 'tropical'],
    '🐟': ['fish'],
    '🐬': ['dolphin'],
    '🐳': ['whale'],
    '🦈': ['shark'],
    '🐘': ['elephant'],
    '🦒': ['giraffe'],
    '🐕': ['dog'],
    '🐈': ['cat'],
    '🌹': ['rose', 'flower', 'love'],
    '🌸': ['cherry blossom', 'flower', 'spring'],
    '🌻': ['sunflower', 'flower'],
    '🌺': ['hibiscus', 'flower'],
    '🍀': ['clover', 'luck', 'four leaf'],
    '🌳': ['tree', 'deciduous'],
    '🌲': ['evergreen', 'tree', 'pine'],
    '🌴': ['palm', 'tree', 'tropical'],
    '🌵': ['cactus', 'desert'],
    '🌙': ['moon', 'night', 'crescent'],
    '☀️': ['sun', 'sunny', 'weather'],
    '🌈': ['rainbow', 'pride', 'weather'],
    '☁️': ['cloud', 'weather'],
    '🌧️': ['rain', 'weather'],
    '⛈️': ['storm', 'thunder', 'weather'],
    '❄️': ['snow', 'cold', 'winter'],
    '☃️': ['snowman', 'winter'],
    '⚡': ['lightning', 'zap', 'electric'],
    '🌊': ['wave', 'ocean', 'water', 'sea'],

    // Travel
    '🚗': ['car', 'auto', 'drive'],
    '🚕': ['taxi', 'cab'],
    '🚌': ['bus'],
    '🚑': ['ambulance', 'emergency'],
    '🚒': ['fire truck', 'emergency'],
    '🚓': ['police', 'car'],
    '✈️': ['plane', 'airplane', 'flight', 'travel'],
    '🚀': ['rocket', 'space', 'launch'],
    '🚁': ['helicopter'],
    '🚂': ['train', 'locomotive'],
    '🚲': ['bike', 'bicycle'],
    '🛵': ['scooter'],
    '🚢': ['ship', 'boat'],
    '🏠': ['home', 'house'],
    '🏡': ['house', 'garden', 'home'],
    '🏢': ['office', 'building'],
    '🏫': ['school', 'building'],
    '🏥': ['hospital', 'medical'],
    '⛪': ['church', 'religion'],
    '🗽': ['statue of liberty', 'nyc', 'new york'],
    '🗼': ['tokyo tower', 'tower'],
    '🏰': ['castle'],
    '⛺': ['tent', 'camping'],
    '🏖️': ['beach', 'vacation'],
    '⛰️': ['mountain'],
    '🌋': ['volcano'],

    // Activities / objects
    '⚽': ['soccer', 'football', 'ball', 'sport'],
    '🏀': ['basketball', 'ball', 'sport'],
    '🏈': ['football', 'american', 'sport'],
    '⚾': ['baseball', 'sport'],
    '🎾': ['tennis', 'sport'],
    '🏐': ['volleyball', 'sport'],
    '🎱': ['billiards', 'pool', '8ball'],
    '🎮': ['game', 'controller', 'video game', 'play'],
    '🎲': ['dice', 'game', 'random'],
    '🎯': ['dart', 'target', 'bullseye'],
    '🎧': ['headphones', 'music', 'listen'],
    '🎤': ['microphone', 'sing', 'karaoke'],
    '🎸': ['guitar', 'music', 'rock'],
    '🎹': ['piano', 'keyboard', 'music'],
    '🥁': ['drum', 'music'],
    '🎬': ['movie', 'film', 'clapper'],
    '📱': ['phone', 'mobile', 'iphone', 'cell'],
    '💻': ['laptop', 'computer', 'macbook'],
    '🖥️': ['desktop', 'computer', 'monitor'],
    '⌨️': ['keyboard'],
    '🖨️': ['printer'],
    '📷': ['camera', 'photo'],
    '📸': ['camera flash', 'photo', 'selfie'],
    '📺': ['tv', 'television'],
    '💡': ['bulb', 'idea', 'light'],
    '🔦': ['flashlight', 'torch'],
    '💰': ['money', 'bag', 'rich', 'cash'],
    '💵': ['dollar', 'money', 'cash', 'bill'],
    '💳': ['credit card', 'payment', 'card'],
    '💎': ['gem', 'diamond', 'jewel'],
    '🔑': ['key', 'password', 'unlock'],
    '🔒': ['lock', 'secure', 'private'],
    '🔓': ['unlock', 'open'],
    '📧': ['email', 'mail'],
    '📦': ['package', 'box', 'parcel', 'delivery'],
    '📚': ['books', 'library', 'read'],
    '📖': ['book', 'open', 'read'],
    '✏️': ['pencil', 'write'],
    '📝': ['memo', 'note', 'write'],
    '📅': ['calendar', 'date'],
    '⏰': ['alarm', 'clock', 'time'],
    '⌚': ['watch', 'time'],
    '🔍': ['search', 'magnifying', 'find', 'zoom'],
    '💊': ['pill', 'medicine', 'drug'],
    '💉': ['syringe', 'shot', 'vaccine'],
    '🧹': ['broom', 'clean'],
    '🧻': ['toilet paper', 'tissue'],
    '🧼': ['soap', 'clean', 'wash'],
    '🛒': ['cart', 'shopping'],
    '📎': ['paperclip', 'clip'],
    '📌': ['pin', 'pushpin'],
    '🔔': ['bell', 'notification', 'alert'],
    '🔕': ['mute bell', 'silent'],

    // Flags common
    '🏳️': ['white flag', 'flag'],
    '🏴': ['black flag', 'flag'],
    '🏁': ['checkered flag', 'racing', 'finish'],
    '🚩': ['red flag', 'triangular'],
    '🏳️‍🌈': ['pride', 'rainbow flag', 'lgbt', 'lgbtq'],
    '🏳️‍⚧️': ['trans', 'transgender', 'flag'],
    '🏴‍☠️': ['pirate', 'jolly roger'],
    '🇺🇸': ['usa', 'america', 'united states', 'flag'],
    '🇬🇧': ['uk', 'britain', 'england', 'flag'],
    '🇨🇦': ['canada', 'flag'],
    '🇲🇽': ['mexico', 'flag'],
    '🇧🇷': ['brazil', 'flag'],
    '🇫🇷': ['france', 'flag'],
    '🇩🇪': ['germany', 'flag'],
    '🇮🇹': ['italy', 'flag'],
    '🇪🇸': ['spain', 'flag'],
    '🇯🇵': ['japan', 'flag'],
    '🇨🇳': ['china', 'flag'],
    '🇰🇷': ['korea', 'south korea', 'flag'],
    '🇮🇳': ['india', 'flag'],
    '🇦🇺': ['australia', 'flag'],
    '🇷🇺': ['russia', 'flag'],
    '🇺🇦': ['ukraine', 'flag'],
  };
}
