import 'dart:isolate';
import 'dart:math';

import '../models/product.dart';

/// Turns what was said ("ரெண்டு மேரி கோல்ட் பத்து ரூபாய், அரை கிலோ சர்க்கரை")
/// into bill lines with ranked product choices. Pure Dart, no plugins, so it
/// is fully tested (test/voice_parser_test.dart).
///
/// Rebuilt 16 Oct 2026. The old parser replaced text fragments anywhere in
/// the sentence (அரிசி → அரிசிி, சாக்லேட் → லேட்), dropped every number
/// (so ₹10 and ₹20 Marie Gold looked the same), took 250 grams as 250
/// packs, and added its first guess straight to the bill. Now:
///  * the sentence is split into whole words; nothing is replaced inside
///    a word;
///  * names are compared by sound (Tamil and English spellings of the same
///    name give the same key: ஹமாம் = hamam, கோல்கேட் = colgate);
///  * a number is the quantity, the price ("பத்து ரூபாய்") or the pack
///    size ("அரை கிலோ"), and the price/size picks the right product;
///  * every line comes with choices; the screen asks before adding.
class VoiceParser {
  VoiceParser(
    List<Product> products, {
    Map<String, String> learned = const {},
    Map<String, String> words = const {},
  })  : _learned = learned,
        _words = _wordRules(words),
        _products = [for (final p in products) _ProductKey.of(p)];

  final List<_ProductKey> _products;

  /// Taught words: what the phone hears → what was meant ("குரு" → "bru").
  final List<(RegExp, String)> _words;

  static List<(RegExp, String)> _wordRules(Map<String, String> words) {
    final entries = words.entries.where((e) => e.key.trim().isNotEmpty).toList()
      // longer first, so "குரு சோப்" wins over "குரு"
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    return [
      for (final e in entries)
        (
          RegExp(
            '(?<=^|[\\s,.])${e.key.trim().split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+')}(?=\$|[\\s,.])',
            caseSensitive: false,
          ),
          e.value.trim(),
        ),
    ];
  }

  /// Puts the taught words in: whole words only ("குருவி" stays).
  String applyWords(String text) {
    var t = text;
    for (final (re, means) in _words) {
      t = t.replaceAll(re, means);
    }
    return t;
  }

  /// Spoken words (see [VoiceLine.phrase]) → product id the shop picked
  /// last time for them.
  final Map<String, String> _learned;

  /// A line is "sure" when its best match scores at least this much and is
  /// clearly ahead of the next one. Otherwise the screen asks.
  static const sureScore = 0.80;
  static const sureGap = 0.08;

  List<VoiceLine> parse(String text) {
    final lines = <VoiceLine>[];
    for (final piece in splitItems(applyWords(text))) {
      lines.addAll(_segment(piece).$1);
    }
    return lines;
  }

  /// The phone gives up to 10 guesses for each stretch of speech ("குரு 10
  /// ரூபாய்", "ப்ரூ 10 ரூபாய்", …). The first guess is not always the one
  /// that names a real product, so every guess is read and the one that
  /// matches the shop's products best is kept.
  /// [pieces]: per stretch of speech, the phone's guesses (best first).
  VoiceOrder parseBest(List<List<String>> pieces) {
    final heard = <String>[];
    final lines = <VoiceLine>[];
    for (final guesses in pieces) {
      List<VoiceLine>? bestLines;
      String? bestText;
      var bestValue = double.negativeInfinity;
      for (var g = 0; g < guesses.length && g < 10; g++) {
        final text = applyWords(guesses[g]).trim();
        if (text.isEmpty) continue;
        final found = <VoiceLine>[];
        var value = 0.0;
        for (final piece in splitItems(text)) {
          final (l, v) = _segment(piece);
          found.addAll(l);
          value += v;
        }
        // the phone's first guess wins a tie
        if (value > bestValue + 1e-6) {
          bestValue = value;
          bestLines = found;
          bestText = text;
        }
      }
      if (bestText != null) {
        heard.add(bestText);
        lines.addAll(bestLines!);
      }
    }
    return VoiceOrder(heard.join(', '), lines);
  }

  /// Words the shop changed in the heard text, to remember: "குரு 10
  /// ரூபாய்" corrected to "bru 10 ரூபாய்" → {"குரு": "bru"}. Only small
  /// changes (up to 3 words each side) are kept.
  static Map<String, String> correctionsBetween(String before, String after) {
    List<String> words(String t) =>
        // a comma stays a word of its own, so it keeps two fixes apart
        t.toLowerCase().replaceAll(',', ' , ').replaceAll('.', ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final a = words(before);
    final b = words(after);
    // longest common run of words, then the gaps between are the changes
    final lcs = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1]);
      }
    }
    final out = <String, String>{};
    var i = 0, j = 0;
    final gapA = <String>[], gapB = <String>[];
    void closeGap() {
      if (gapA.isNotEmpty && gapB.isNotEmpty && gapA.length <= 3 && gapB.length <= 3) {
        final heard = gapA.join(' ');
        final meant = gapB.join(' ');
        // numbers are not words to remember
        if (parseNumberWord(heard) == null && heard != meant && !heard.contains(',') && !meant.contains(',')) {
          out[heard] = meant;
        }
      }
      gapA.clear();
      gapB.clear();
    }

    while (i < a.length || j < b.length) {
      if (i < a.length && j < b.length && a[i] == b[j]) {
        closeGap();
        i++;
        j++;
      } else if (j < b.length && (i >= a.length || lcs[i][j + 1] >= lcs[i + 1][j])) {
        gapB.add(b[j++]);
      } else {
        gapA.add(a[i++]);
      }
    }
    closeGap();
    return out;
  }

  /// One piece of speech can hold several items with no pause or joining
  /// word between them: "சுகர் ஒரு கிலோ லட்சுமி சீவல் 10 எம் எல் எஸ் சீவல் 10"
  /// is three items (owner's phone, 16 Oct 2026). Every way of cutting the
  /// words into items is tried (items of up to 8 words). The best cut:
  ///  1. puts the most words into items that match a product well;
  ///  2. then has the fewest items ("ஹமாம் சோப்பு" is one item);
  ///  3. then has the better matches.
  /// An item never holds the same name word twice ("சீவல் … சீவல்").
  (List<VoiceLine>, double) _segment(String piece) {
    final words = _splitWords(piece);
    if (words.isEmpty) return (const <VoiceLine>[], 0.0);
    const maxLen = 8;
    final n = words.length;
    final best = List<double>.filled(n + 1, double.negativeInfinity);
    final from = List<int>.filled(n + 1, -1);
    final lineAt = <(int, int), VoiceLine?>{};
    best[0] = 0;
    for (var j = 1; j <= n; j++) {
      for (var i = max(0, j - maxLen); i < j; i++) {
        if (best[i] == double.negativeInfinity) continue;
        final line = parseItem(words.sublist(i, j).join(' '));
        lineAt[(i, j)] = line;
        final v = best[i] + _value(line, words, i, j);
        // ties: a number between two names goes with the name before it
        // ("கிங்ஸ் 10 கிங்ஸ் லைட் 10"), so the later cut wins
        if (v >= best[j] - 1e-9) {
          best[j] = v;
          from[j] = i;
        }
      }
    }
    final out = <VoiceLine>[];
    var j = n;
    while (j > 0) {
      final i = from[j];
      final line = lineAt[(i, j)];
      if (line != null) out.insert(0, line);
      j = i;
    }
    return (out, best[n]);
  }

  /// The worth of one item in a cut, as one number that orders the cut by
  /// the rules above: well-matched words × 100, minus 1 per item, plus a
  /// little for the match quality.
  double _value(VoiceLine? line, List<String> words, int i, int j) {
    var v = -1.0; // every item
    // ties: a number between two names goes with the name before it
    // ("கிங்ஸ் 10 கிங்ஸ் லைட் 10"), so a cut that ends on a number wins
    if (parseNumberWord(words[j - 1]) != null) v += 0.0001;
    // "ரூபாய்", "கிலோ", "packet" belong to the number before them
    if (i > 0) {
      final w = words[i];
      if (_isPriceWord(w) || _isCountUnit(w) || _sizeUnit(w) != null || _isDozen(w)) return -1e6;
    }
    // "அரை", "கால்" come before what they measure ("அரை ஹமாம்"), so an item
    // that ends on one has taken the next item's quantity
    final last = words[j - 1];
    if (j < words.length && const {'அரை', 'கால்', 'முக்கால்', 'half', 'quarter'}.contains(last)) v -= 0.5;
    if (line == null) return v; // only numbers or fillers
    if (line.quantities > 1) v -= 50; // two quantities in one item
    final names = line.phrase.split(' ');
    final keys = names.map(soundKey).toList();
    if (keys.toSet().length < keys.length) return v - 1; // a word said twice
    // the best of the first few choices: words that belong to the product
    // count for the item, stray words against it
    // "பொடி", "சோப்பு", "சிகரெட்" only describe the item: alone they are not
    // an item, and a product name without them is still a full match
    final describing = keys.where(_describingKeys.contains).length;
    if (describing == names.length) return v;
    var bestWorth = 0.0;
    var quality = 0.0;
    for (final c in line.choices.take(3)) {
      if (c.score < _goodScore) continue;
      final stray = max(0, names.length - describing - c.matched);
      final worth = 100.0 * c.matched - 60.0 * stray;
      if (worth > bestWorth) {
        bestWorth = worth;
        quality = min(c.score, 1.2);
      }
    }
    if (bestWorth == 0 && line.best != null) quality = min(line.best!.score, 1.2);
    return v + bestWorth + 0.01 * quality;
  }

  static final Set<String> _describingKeys = {
    for (final w in const [
      'பொடி', 'தூள்', 'சோப்பு', 'சோப்', 'பவுடர்', 'ஆயில்', 'எண்ணெய்', 'சிகரெட்', 'சிகரட்',
      'பிஸ்கட்', 'ஷாம்பு', 'மாவு', 'பேஸ்ட்', 'ஜூஸ்', 'பாக்கெட்',
      'podi', 'thool', 'soap', 'powder', 'oil', 'cigarette', 'cigrate', 'biscuit',
      'shampoo', 'maavu', 'paste', 'juice',
    ])
      soundKey(w),
  };

  /// A match good enough to count its words as found.
  static const _goodScore = 0.80;

  // ── splitting ──────────────────────────────────────────────────────────

  static final _separatorWords = {
    'மற்றும்', 'அப்புறம்', 'அப்றம்', 'அப்பறம்', 'பிறகு', 'அடுத்து', 'அடுத்தது',
    'and', 'then', 'next', 'also', 'plus',
  };

  /// One item per piece: split on commas, full stops and joining words
  /// ("மற்றும்", "அப்புறம்", "and"). Whole words only.
  static List<String> splitItems(String text) {
    final out = <String>[];
    for (final part in text.split(RegExp(r'[,،;\n]|\.(?!\d)'))) {
      var current = <String>[];
      for (final w in part.trim().split(RegExp(r'\s+'))) {
        if (w.isEmpty) continue;
        if (_separatorWords.contains(w.toLowerCase())) {
          if (current.isNotEmpty) out.add(current.join(' '));
          current = [];
        } else {
          current.add(w);
        }
      }
      if (current.isNotEmpty) out.add(current.join(' '));
    }
    return out;
  }

  // ── one item ───────────────────────────────────────────────────────────

  VoiceLine? parseItem(String spoken) {
    final tokens = _tokenize(spoken);
    final words = <String>[];
    final free = <_FreeNumber>[]; // numbers with no unit or "rupees"
    double? countQty; // "2 packet", "ரெண்டு", a number before the name
    double? price; // "10 ரூபாய்"
    double? size; // grams or ml: "அரை கிலோ" = 500
    String? sizeKind; // 'g' or 'ml'
    var dozen = false;

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.number == null) {
        if (_isPriceWord(t.text) || _isCountUnit(t.text) || _sizeUnit(t.text) != null) {
          continue; // a unit with no number before it ("packet sugar")
        }
        if (_isDozen(t.text)) {
          dozen = true;
          continue;
        }
        if (_fillers.contains(t.text)) continue;
        words.add(t.text);
        continue;
      }
      final n = t.number!;
      final next = i + 1 < tokens.length ? tokens[i + 1].text : '';
      if (_isPriceWord(next)) {
        price = n;
        i++;
      } else if (_sizeUnit(next) != null) {
        final (factor, kind) = _sizeUnit(next)!;
        size = n * factor;
        sizeKind = kind;
        i++;
      } else if (_isCountUnit(next)) {
        countQty = n;
        i++;
      } else if (_isDozen(next)) {
        countQty = n * 12;
        i++;
      } else {
        // a number said as a word may be part of a name ("five star")
        final spelled = double.tryParse(t.text) == null ? t.text : null;
        free.add(_FreeNumber(n, beforeName: words.isEmpty, word: spelled));
      }
    }
    if (dozen && countQty == null && free.isEmpty) countQty = 12;

    if (words.isEmpty) return null;
    final phrase = words.join(' ');

    final query = _Query(
      words: [for (final w in words) _WordKeys.of(w)],
      price: price,
      size: size,
      sizeKind: sizeKind,
      free: free,
    );

    final scored = <VoiceChoice>[];
    for (final pk in _products) {
      final c = _score(pk, query, countQty);
      if (c != null) scored.add(c);
    }
    scored.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      return a.product.name.length.compareTo(b.product.name.length);
    });

    // the product the shop chose last time for these words goes first
    final learnedId = _learned[phrase];
    if (learnedId != null) {
      final i = scored.indexWhere((c) => c.product.id == learnedId);
      if (i > 0) {
        final c = scored.removeAt(i);
        scored.insert(0, c.withScore(max(c.score, scored.first.score) + 0.2));
      } else if (i == 0) {
        scored[0] = scored[0].withScore(scored[0].score + 0.2);
      } else {
        final pk = _products.where((p) => p.product.id == learnedId).firstOrNull;
        if (pk != null) {
          final c = _score(pk, query, countQty, force: true)!;
          scored.insert(0, c.withScore(1.2));
        }
      }
    }

    final choices = scored.where((c) => c.score >= 0.45).take(6).toList();
    // how many separate quantities were said: "25 … 3 பாக்கெட்" is two, so
    // the 3 packets belong to the next item (owner's round 5, 17 Oct 2026)
    // ("ரெண்டு 3 roses": numbers before the name together are one quantity,
    // the 3 may be part of the name)
    final quantities = (countQty != null ? 1 : 0) + (free.any((f) => f.beforeName) ? 1 : 0);
    return VoiceLine(spoken: spoken.trim(), phrase: phrase, choices: choices, quantities: quantities);
  }

  // ── scoring ────────────────────────────────────────────────────────────

  final Map<String, double> _simCache = {};

  double _sim(_WordKeys w, String productKey) =>
      _simCache.putIfAbsent('${w.keys.join('/')}|$productKey', () => w.similarity(productKey));

  VoiceChoice? _score(_ProductKey pk, _Query q, double? countQty, {bool force = false}) {
    final free = [...q.free];
    // "3 roses": the number said just before the name is part of it
    final lastBefore = q.free.where((f) => f.beforeName).lastOrNull;
    var leadHit = false;
    if (pk.lead != null && lastBefore != null && (lastBefore.value - pk.lead!).abs() < 0.001) {
      free.remove(lastBefore);
      leadHit = true;
    }
    // "5 star": the phone writes "five" as 5, and "five" is in the name
    final wordAt = lastBefore == null || leadHit ? null : pk.numberWords[lastBefore.value];
    if (wordAt != null) {
      free.remove(lastBefore);
      leadHit = true;
    }
    // "five star": the number word is part of this product's name
    final nameWords = [...q.words];
    for (final f in q.free) {
      if (f.word != null && pk.words.contains(soundKey(f.word!))) {
        nameWords.insert(0, _WordKeys.of(f.word!));
        free.remove(f);
      }
    }

    // how well the spoken words match the product's words, by sound
    var total = 0.0;
    final used = <int>{};
    var matched = 0; // said words that clearly belong to this product
    final matchedAt = <int>{};
    for (final w in nameWords) {
      var best = 0.0;
      var bestAt = -1;
      for (var j = 0; j < pk.words.length; j++) {
        var s = _sim(w, pk.words[j]);
        // Tamil said: the shop's Tamil name is a safer match than an
        // English spelling ("sciccor" sounds like sugar, சிசர் does not)
        if (w.tamil && pk.taIdx.isNotEmpty && !pk.taIdx.contains(j)) s *= 0.97;
        if (s > best) {
          best = s;
          bestAt = j;
        }
      }
      total += best;
      if (best >= 0.7) used.add(bestAt);
      // each product word belongs to one said word only; describing words
      // (பொடி, சிகரெட்) do not tell products apart
      if (best >= 0.75 && !_describingKeys.contains(w.keys.first) && matchedAt.add(bestAt)) matched++;
    }
    var nameScore = total / nameWords.length;
    // "துவரம் பருப்பு" said apart, "thuvaramparuppu" written together (or
    // the other way round)
    final joined = q.words.length != pk.enIdx.length &&
            q.joinedKey.length >= 6 &&
            pk.joinedKey.length >= 6
        ? _similarity(q.joinedKey, pk.joinedKey)
        : 0.0;
    if (joined > nameScore && joined >= 0.8) {
      nameScore = joined;
      used.addAll(List.generate(pk.words.length, (i) => i));
      matched = nameWords.length;
    }
    if (!force && nameScore < 0.55) return null;

    // product words that were not said count a little against it, so "lux"
    // prefers "lux 10 rs" over "lux rose 40rs" (English and Tamil names
    // are counted apart: the better of the two)
    double cover(List<int> idx) =>
        idx.isEmpty ? 0 : idx.where(used.contains).length / idx.length;
    final coverage = pk.words.isEmpty ? 1.0 : max(cover(pk.enIdx), cover(pk.taIdx));
    var score = 0.8 * nameScore + 0.2 * coverage;
    if (leadHit) {
      score += 0.12;
      if (wordAt != null && wordAt >= 0) {
        used.add(wordAt);
        score += 0.2 * (1 / max(1, pk.words.length)); // "five" was said too
      }
    }

    var qty = countQty ?? 1.0;

    // price said ("பத்து ரூபாய்"): pick the product with that price in its name
    if (q.price != null) {
      if (pk.hasNumber(q.price!)) {
        score += 0.15;
      } else if (pk.prices.isNotEmpty || pk.bare.isNotEmpty) {
        score -= 0.15;
      }
    }

    // size said ("அரை கிலோ", "200 கிராம்")
    String? note;
    if (q.size != null) {
      final s = q.size!;
      if (pk.isLoose) {
        // sold by weight: the size is the quantity (in kg / litre)
        qty = s / 1000 * (countQty ?? 1);
        score += 0.05;
      } else if (pk.size != null && pk.sizeKind == q.sizeKind && (pk.size! - s).abs() < 0.01) {
        score += 0.15; // "அரை கிலோ சர்க்கரை" → the 500 g pack
      } else if (pk.size != null && pk.sizeKind == q.sizeKind && pk.size! < s) {
        final packs = s / pk.size!;
        if ((packs - packs.round()).abs() < 0.01 && packs <= 50) {
          qty = packs.roundToDouble() * (countQty ?? 1); // 2 kg = 2 × 1 kg pack
          score += 0.06 / packs; // fewer, bigger packs first
          note = '${_fmt(s)} ${q.sizeKind} = ${_fmt(packs)} × ${_fmt(pk.size!)} ${q.sizeKind}';
        } else {
          score -= 0.08;
        }
      } else {
        // another size of the same thing (or a name with no size) is still
        // a fair choice, below the right size
        score -= 0.08;
      }
    }

    // numbers said with no unit: one that is in the product's name is its
    // price or size ("marie gold பத்து"); the rest is the quantity
    final inName = free.where((f) => pk.hasNumber(f.value)).toList();
    if (inName.isNotEmpty) {
      // a number before the name is the quantity ("ரெண்டு லக்ஸ்"); only one
      // said after it is the price or size
      final after = inName.where((f) => !f.beforeName);
      if (after.isNotEmpty) {
        free.remove(after.first);
        score += 0.12;
      }
    }
    if (free.isNotEmpty && countQty == null && q.size == null) {
      qty = free.first.value;
    } else if (free.isNotEmpty && countQty == null && q.size != null && !pk.isLoose && note == null) {
      qty = free.first.value; // "ரெண்டு அரை கிலோ சர்க்கரை" = 2 × 500 g
    }

    if (qty <= 0) qty = 1;
    // pieces and packs are whole numbers; "அரை" of a piece needs a look
    var needsCheck = false;
    if (!pk.isLoose && qty != qty.roundToDouble()) {
      note = '${_fmt(qty)} ${pk.product.unit}? (whole ${pk.product.unit} only)';
      qty = max(1, qty.roundToDouble());
      needsCheck = true;
    }

    return VoiceChoice(
      product: pk.product,
      qty: qty,
      score: score,
      note: note,
      needsCheck: needsCheck,
      matched: matched,
    );
  }

  // ── tokens and numbers ─────────────────────────────────────────────────

  /// The words of [spoken], with numbers and units apart ("10rs" → 10 rs)
  /// and spelled letters joined: "எம் எல் எஸ்" / "m l s" → "mls".
  static List<String> _splitWords(String spoken) {
    // "2kg", "500g", "10rs" → "2 kg"; keep "1.5"
    final spaced = spoken
        .toLowerCase()
        .replaceAllMapped(RegExp(r'(\d)([^\d\s.,/])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'([^\d\s.,/₹])(\d)'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'₹\s*(\d+(?:\.\d+)?)'), (m) => ' ${m[1]} ரூபாய் ')
        .replaceAll('₹', ' ')
        .replaceAll(RegExp(r'[!?"“”()]'), ' ');
    final raw = spaced.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <String>[];
    for (var i = 0; i < raw.length; i++) {
      final letters = <String>[];
      var k = i;
      while (k < raw.length && _letterOf(raw[k]) != null) {
        letters.add(_letterOf(raw[k])!);
        k++;
      }
      if (letters.length >= 2) {
        out.add(letters.join());
        i = k - 1;
      } else {
        out.add(raw[i]);
      }
    }
    return out;
  }

  // letters as said in Tamil (and as English letters)
  static const _letters = {
    'ஏ': 'a', 'ஏய்': 'a', 'பி': 'b', 'பீ': 'b', 'சி': 'c', 'சீ': 'c', 'டி': 'd',
    'ஈ': 'e', 'எஃப்': 'f', 'எப்': 'f', 'ஜி': 'g', 'ஜீ': 'g', 'எச்': 'h', 'ஹெச்': 'h',
    'ஐ': 'i', 'ஜே': 'j', 'கே': 'k', 'எல்': 'l', 'எம்': 'm', 'என்': 'n', 'ஓ': 'o',
    'க்யூ': 'q', 'ஆர்': 'r', 'எஸ்': 's', 'டீ': 't', 'யூ': 'u', 'வி': 'v', 'வீ': 'v',
    'டபிள்யூ': 'w', 'எக்ஸ்': 'x', 'ஒய்': 'y', 'வொய்': 'y', 'இசட்': 'z', 'செட்': 'z',
  };

  static String? _letterOf(String w) {
    if (w.length == 1 && RegExp(r'[a-z]').hasMatch(w)) return w;
    return _letters[w];
  }

  List<_Token> _tokenize(String spoken) {
    final raw = _splitWords(spoken);
    final out = <_Token>[];
    for (var i = 0; i < raw.length; i++) {
      final w = raw[i];
      final n = parseNumberWord(w);
      if (n == null) {
        out.add(_Token(w));
        continue;
      }
      var value = n;
      // "இருபது அஞ்சு" / "twenty five" said as two words; "ஒன்று அரை" = 1.5
      while (i + 1 < raw.length) {
        final m = parseNumberWord(raw[i + 1]);
        if (m == null) break;
        final joins = (value >= 20 && value % 10 == 0 && value < 100 && m >= 1 && m <= 9 && m == m.roundToDouble()) ||
            (value >= 100 && value % 100 == 0 && m >= 1 && m < 100) ||
            (value == value.roundToDouble() && value >= 1 && m == 0.5 && _isHalfWord(raw[i + 1]));
        if (!joins) break;
        value += m;
        i++;
      }
      out.add(_Token(w, value));
    }
    return out;
  }

  static bool _isHalfWord(String w) => w == 'அரை' || w == 'half' || w == 'arai';

  static final Map<String, double> _numberWords = {
    // English
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7,
    'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13,
    'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90, 'hundred': 100,
    'half': 0.5, 'quarter': 0.25,
    // Tamil, written and spoken forms
    'ஒன்று': 1, 'ஒண்ணு': 1, 'ஒன்னு': 1, 'ஒரு': 1, 'ஓர்': 1,
    'இரண்டு': 2, 'ரெண்டு': 2, 'ரண்டு': 2, 'இரெண்டு': 2,
    'மூன்று': 3, 'மூணு': 3, 'மூனு': 3,
    // the phone often writes நாலு as நாளு ("day"): heard in the shop, 17 Oct 2026
    'நான்கு': 4, 'நாலு': 4, 'நாழு': 4, 'நாளு': 4,
    'ஐந்து': 5, 'அஞ்சு': 5, 'அஞ்சி': 5, 'அய்ந்து': 5,
    'ஆறு': 6, 'ஏழு': 7, 'எட்டு': 8,
    'ஒன்பது': 9, 'ஒம்பது': 9, 'ஒம்போது': 9,
    'பத்து': 10, 'பதினொன்று': 11, 'பதினொண்ணு': 11, 'பதினொன்னு': 11,
    'பன்னிரண்டு': 12, 'பன்னெண்டு': 12, 'பன்னண்டு': 12,
    'பதிமூன்று': 13, 'பதிமூணு': 13, 'பதினான்கு': 14, 'பதினாலு': 14,
    'பதினைந்து': 15, 'பதினஞ்சு': 15, 'பதினாறு': 16, 'பதினேழு': 17,
    'பதினெட்டு': 18, 'பத்தொன்பது': 19, 'பத்தொம்பது': 19,
    'இருபது': 20, 'இருவது': 20, 'முப்பது': 30, 'நாற்பது': 40, 'நாப்பது': 40,
    'ஐம்பது': 50, 'அம்பது': 50, 'அறுபது': 60, 'எழுபது': 70, 'எண்பது': 80,
    'தொண்ணூறு': 90, 'தொன்னூறு': 90,
    'நூறு': 100, 'இருநூறு': 200, 'முந்நூறு': 300, 'முன்னூறு': 300, 'நானூறு': 400,
    'ஐநூறு': 500, 'அஞ்னூறு': 500, 'அறுநூறு': 600, 'எழுநூறு': 700, 'எண்ணூறு': 800,
    'ஆயிரம்': 1000,
    'அரை': 0.5, 'கால்': 0.25, 'முக்கால்': 0.75, 'arai': 0.5,
  };

  // "இருபத்து", "முப்பத்து" … the joining form used in 21–99 and 101–999
  static const Map<String, double> _tensStems = {
    'இருபத்து': 20, 'இருவத்து': 20, 'முப்பத்து': 30, 'நாற்பத்து': 40, 'நாப்பத்து': 40,
    'ஐம்பத்து': 50, 'அம்பத்து': 50, 'அறுபத்து': 60, 'எழுபத்து': 70, 'எண்பத்து': 80,
    'தொண்ணூற்று': 90, 'தொண்ணூத்து': 90,
    'நூற்று': 100, 'நூத்து': 100, 'இருநூற்று': 200, 'இருநூத்து': 200,
    'முந்நூற்று': 300, 'முன்னூத்து': 300, 'நானூற்று': 400, 'நானூத்து': 400,
    'ஐநூற்று': 500, 'ஐநூத்து': 500,
  };

  static const Map<String, String> _vowelOfSign = {
    'ா': 'ஆ', 'ி': 'இ', 'ீ': 'ஈ', 'ு': 'உ', 'ூ': 'ஊ',
    'ெ': 'எ', 'ே': 'ஏ', 'ை': 'ஐ', 'ொ': 'ஒ', 'ோ': 'ஓ',
  };

  /// A number written as digits or said as one word: "12", "1.5", "ரெண்டு",
  /// "இருபத்தஞ்சு" (25), "நூத்தம்பது" (150), "ஒன்றரை" (1½), "twenty".
  static double? parseNumberWord(String word) {
    final w = word.trim();
    if (w.isEmpty) return null;
    final d = double.tryParse(w);
    if (d != null) return d;
    if (w == '1/2' || w == '½') return 0.5;
    final known = _numberWords[w];
    if (known != null) return known;

    // "ஒன்றரை", "ரெண்டரை", "மூணரை": n and a half
    if (w.endsWith('ரை') && w.length > 3) {
      final base = parseNumberWord('${w.substring(0, w.length - 2)}ு');
      if (base != null && base >= 1 && base <= 20) return base + 0.5;
    }

    // stems joined to the rest: இருபத்து + அஞ்சு → இருபத்தஞ்சு
    for (final e in _tensStems.entries) {
      final stem = e.key; // ends with "ு"
      final open = stem.substring(0, stem.length - 1); // "இருபத்த"
      String? rest;
      if (w.startsWith(stem) && w.length > stem.length) {
        rest = w.substring(stem.length); // இருபத்துமூணு
      } else if (w.startsWith(open) && w.length > open.length) {
        final sign = w[open.length];
        final vowel = _vowelOfSign[sign];
        if (vowel != null) {
          rest = vowel + w.substring(open.length + 1); // இருபத்தொன்று
          // "இருபத்திமூணு": the இ only links the two parts
          if (sign == 'ி' && parseNumberWord(rest) == null) {
            rest = w.substring(open.length + 1);
          }
        } else {
          rest = 'அ${w.substring(open.length)}'; // இருபத்தஞ்சு
        }
      }
      if (rest == null) continue;
      final r = parseNumberWord(rest);
      if (r != null && r >= 1 && r < e.value && r == r.roundToDouble()) return e.value + r;
    }
    return null;
  }

  // ── units ──────────────────────────────────────────────────────────────

  static const _priceWords = {
    'ரூபாய்', 'ரூபா', 'ரூ', 'ருபாய்', 'ரூபாய்க்கு', 'ரூபாக்கு', 'ரூவா', 'ரூவாக்கு',
    'rs', 'rs.', 'rupees', 'rupee', 'rupay', 'mrp', 'ஆர்எஸ்',
  };
  static bool _isPriceWord(String w) => _priceWords.contains(w);

  static const _countUnits = {
    'பாக்கெட்', 'பேக்கெட்', 'பாக்கட்', 'பேக்', 'பீஸ்', 'எண்ணம்', 'பாக்ஸ்', 'டப்பா',
    'பாட்டில்', 'கவர்', 'பை', 'சரம்', 'கட்டு', 'நம்பர்', 'மூட்டை', 'மூடை', 'சாக்கு',
    'டின்', 'ஜார்',
    'packet', 'packets', 'pack', 'packs', 'pcs', 'pc', 'piece', 'pieces', 'nos',
    'no', 'number', 'box', 'boxes', 'bottle', 'bottles', 'cover', 'covers',
    'bag', 'bags', 'saram', 'tin', 'tins',
  };
  static bool _isCountUnit(String w) => _countUnits.contains(w);
  static bool _isDozen(String w) => w == 'டஜன்' || w == 'டசன்' || w == 'dozen';

  /// Size units → (factor to grams or ml, kind).
  static (double, String)? _sizeUnit(String w) {
    switch (w) {
      case 'கிலோ' || 'கிலோகிராம்' || 'கேஜி' || 'kg' || 'kgs' || 'kilo' || 'kilos' || 'kilogram':
        return (1000, 'g');
      case 'கிராம்' || 'கிராம்ஸ்' || 'ஜி' || 'g' || 'gm' || 'gms' || 'gram' || 'grams' || 'gr':
        return (1, 'g');
      case 'லிட்டர்' || 'லிட்டர்ஸ்' || 'லிட்' || 'l' || 'lit' || 'ltr' || 'ltrs' || 'litre' || 'liter' || 'litres' || 'liters':
        return (1000, 'ml');
      case 'மில்லி' || 'மி.லி' || 'ml' || 'மிலி':
        return (1, 'ml');
    }
    return null;
  }

  /// Polite words and verbs that are not part of a product name.
  static const _fillers = {
    'வேணும்', 'வேண்டும்', 'வேணு', 'குடுங்க', 'கொடுங்க', 'குடு', 'கொடு', 'தாங்க',
    'போடுங்க', 'போடு', 'அண்ணா', 'அக்கா', 'சார்', 'மேடம்', 'கொஞ்சம்', 'இன்னும்',
    'please', 'give', 'me', 'want', 'need', 'add', 'the', 'of', 'a', 'an',
    'some', 'i', 'sir',
  };

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

/// One spoken item and the products it could be (best first).
class VoiceLine {
  VoiceLine({required this.spoken, required this.phrase, required this.choices, this.quantities = 0});

  /// Separate quantities said in it (more than one means a bad cut).
  final int quantities;

  /// What was heard for this item.
  final String spoken;

  /// The name words only (no numbers or units): the key for learning.
  final String phrase;

  /// Products it could be, best first; empty when nothing matched.
  final List<VoiceChoice> choices;

  VoiceChoice? get best => choices.isEmpty ? null : choices.first;

  /// Safe to pre-select without a second look.
  bool get isSure {
    final b = best;
    if (b == null || b.needsCheck || b.score < VoiceParser.sureScore) return false;
    if (choices.length < 2) return true;
    return b.score - choices[1].score >= VoiceParser.sureGap;
  }
}

class VoiceChoice {
  VoiceChoice({
    required this.product,
    required this.qty,
    required this.score,
    this.note,
    this.needsCheck = false,
    this.matched = 0,
  });

  final Product product;
  final double qty;
  final double score;

  /// How many of the said name words clearly belong to this product.
  final int matched;

  /// Shown under the line, e.g. "2 kg = 2 × 1 kg pack".
  final String? note;

  /// The quantity was changed to fit the product (half a piece).
  final bool needsCheck;

  VoiceChoice withScore(double s) =>
      VoiceChoice(product: product, qty: qty, score: s, note: note, needsCheck: needsCheck, matched: matched);
}

// ── internals ────────────────────────────────────────────────────────────

class _Token {
  _Token(this.text, [this.number]);
  final String text;
  final double? number;
}

class _FreeNumber {
  _FreeNumber(this.value, {required this.beforeName, this.word});
  final double value;
  final bool beforeName;

  /// The word as said ("five"), when it was not digits.
  final String? word;
}

class _Query {
  _Query({required this.words, this.price, this.size, this.sizeKind, required this.free})
      : joinedKey = words.map((w) => w.keys.first).join();
  final List<_WordKeys> words;
  final double? price;
  final double? size;
  final String? sizeKind;
  final List<_FreeNumber> free;
  final String joinedKey;
}

/// The sound keys of one spoken word: itself plus common Tamil → English
/// names (சர்க்கரை → sugar, because the products say "SUGAR BANNARI").
class _WordKeys {
  _WordKeys(this.keys, {this.tamil = false});
  final List<String> keys;
  final bool tamil;

  static _WordKeys of(String word) {
    final keys = <String>{soundKey(word)};
    for (final s in _synonyms[word] ?? const <String>[]) {
      keys.add(soundKey(s));
    }
    keys.remove('');
    return _WordKeys(keys.toList(), tamil: RegExp(r'[஀-௿]').hasMatch(word));
  }

  double similarity(String productKey) {
    var best = 0.0;
    for (final k in keys) {
      final s = _similarity(k, productKey);
      if (s > best) best = s;
    }
    return best;
  }

  // Everyday Tamil words → the words used in the product names.
  static const Map<String, List<String>> _synonyms = {
    'சர்க்கரை': ['sugar'], 'சக்கரை': ['sugar'], 'சீனி': ['sugar'],
    'அரிசி': ['rice', 'arisi'], 'எண்ணெய்': ['oil', 'ennai'], 'எண்ணெ': ['oil'],
    'எண்ணை': ['oil'], 'உப்பு': ['salt', 'uppu'], 'சோப்பு': ['soap'], 'சோப்': ['soap'],
    'டீ': ['tea'], 'தேநீர்': ['tea'], 'டீத்தூள்': ['tea', 'thool'],
    'காபி': ['coffee'], 'காப்பி': ['coffee'], 'பால்': ['milk', 'paal'],
    'தூள்': ['thool', 'powder'], 'பொடி': ['podi', 'powder'], 'மாவு': ['maavu', 'mavu', 'atta'],
    'முட்டை': ['egg', 'muttai'], 'நெய்': ['ghee', 'nei'], 'வேப்பம்': ['neem'],
    'வேம்பு': ['neem'], 'ரோஜா': ['rose'], 'பற்பசை': ['paste'], 'தண்ணீர்': ['water'],
    'தண்ணி': ['water'], 'கொசு': ['kosu', 'mosquito'], 'ஊதுபத்தி': ['agarbatti', 'bathi'],
    'கற்பூரம்': ['camphor', 'karpooram'], 'சூடம்': ['camphor', 'sudam'],
    'தீப்பெட்டி': ['matches', 'theepetti'], 'மெழுகுவர்த்தி': ['candle'],
    'மிளகாய்': ['chilli', 'milagai'], 'மஞ்சள்': ['turmeric', 'manjal'],
    'பிஸ்கட்': ['biscuit'], 'பிஸ்கெட்': ['biscuit'], 'சாக்லேட்': ['chocolate'],
    'ஷாம்பு': ['shampoo'], 'பேஸ்ட்': ['paste'], 'பிரஷ்': ['brush'],
    'துணி': ['cloth'], 'வாழைப்பழம்': ['banana'], 'ரவை': ['rava', 'ravai'],
    'சேமியா': ['semiya', 'vermicelli'], 'புளி': ['puli', 'tamarind'],
    'கடுகு': ['kadugu', 'mustard'], 'சீரகம்': ['seeragam', 'jeera'],
    'பெருங்காயம்': ['perungayam', 'asafoetida'], 'வத்தல்': ['vathal'],
    'sugar': ['சர்க்கரை'], 'oil': ['எண்ணெய்'], 'salt': ['உப்பு'], 'rice': ['அரிசி'],
  };
}

class _ProductKey {
  _ProductKey({
    required this.product,
    required this.words,
    required this.enIdx,
    required this.taIdx,
    required this.joinedKey,
    required this.prices,
    required this.bare,
    required this.lead,
    required this.numberWords,
    required this.size,
    required this.sizeKind,
    required this.isLoose,
  });

  final Product product;
  final List<String> words; // sound keys of the name words (English + Tamil)
  final List<int> enIdx; // which of [words] are in the English name
  final List<int> taIdx; // and which in the Tamil name
  final String joinedKey; // English name words joined
  final Set<double> prices; // "10 rs", "mrp 25"
  final Set<double> bare; // "Colgate 2", "kulfi 80"
  final double? lead; // "3 roses 5 rs": the 3 is part of the name

  /// Number words in the name and where: "five star" → {5: index of five}.
  final Map<double, int> numberWords;
  final double? size; // grams or ml: "500g", "1 kg", "1/2 lit"
  final String? sizeKind;
  final bool isLoose; // sold by weight or volume

  Set<double> get numbers => {...prices, ...bare, if (size != null) ..._sizeSpoken};

  // the size as people say it: 500 for "500 g", 1 for "1 kg"
  Set<double> get _sizeSpoken => {size!, if (size! >= 1000) size! / 1000};

  bool hasNumber(double n) => numbers.any((x) => (x - n).abs() < 0.001);

  static _ProductKey of(Product p) {
    final words = <String>[];
    int indexOf(String key) {
      final i = words.indexOf(key);
      if (i >= 0) return i;
      words.add(key);
      return words.length - 1;
    }

    final english = _nameWords(p.name);
    final enIdx = {for (final w in english.words) soundKey(w)}..remove('');
    final tamil = p.tamilName?.trim() ?? '';
    final ta = _nameWords(tamil);
    final taIdx = {for (final w in ta.words) soundKey(w)}..remove('');
    final unit = p.unit.toLowerCase().trim();
    return _ProductKey(
      product: p,
      words: words,
      enIdx: [for (final k in enIdx) indexOf(k)],
      taIdx: [for (final k in taIdx) indexOf(k)],
      joinedKey: english.words.map(soundKey).join(),
      prices: {...english.prices, ...ta.prices},
      bare: {...english.bare, ...ta.bare},
      lead: english.lead,
      numberWords: {
        for (final w in [...english.words, ...ta.words])
          if (VoiceParser.parseNumberWord(w) case final n? when n >= 1) n: words.indexOf(soundKey(w)),
      },
      size: english.size ?? ta.size,
      sizeKind: english.size != null ? english.sizeKind : ta.sizeKind,
      isLoose: const {'kg', 'g', 'gm', 'gram', 'ltr', 'litre', 'l', 'ml'}.contains(unit),
    );
  }
}

class _NameParts {
  final words = <String>[];
  final prices = <double>{};
  final bare = <double>{};
  double? lead;
  double? size;
  String? sizeKind;
}

/// Splits a product name into name words and its numbers: "Marie gold
/// 10 rs" → [marie, gold] + price 10; "aashirvad 500g" → size 500 g;
/// "Marie gold 5 rs(12)" → price 5 (the (12) is the pack count).
_NameParts _nameWords(String name) {
  final parts = _NameParts();
  final text = name
      .toLowerCase()
      .replaceAll(RegExp(r'\(\s*\d+\s*\)'), ' ') // "(12)" pack count
      .replaceAll(RegExp(r'\d+\s*pc\b'), ' ')
      .replaceAllMapped(RegExp(r'(\d)([^\d\s./])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([^\d\s./])(\d)'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[()\-_,+&]'), ' ');
  final tokens = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  var pricePending = false; // "mrp 25"
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    double? n = double.tryParse(t);
    if (t == '1/2') n = 0.5;
    if (n == null) {
      if (t == 'mrp' || t == 'rs' || t == 'ரூ') {
        pricePending = t == 'mrp';
        continue;
      }
      if (VoiceParser._sizeUnit(t) != null || VoiceParser._isCountUnit(t) || VoiceParser._isPriceWord(t)) continue;
      if (t == 'r' || t == 'ஆர்' || t == '.') continue; // "Kadalai 5 R"
      if (t.length < 2 && !RegExp(r'[^\x00-\x7F]').hasMatch(t)) continue;
      parts.words.add(t);
      continue;
    }
    final next = i + 1 < tokens.length ? tokens[i + 1] : '';
    if (i == 0 && double.tryParse(next) == null && VoiceParser._sizeUnit(next) == null &&
        !VoiceParser._isPriceWord(next) && next != 'rs' && next != 'r') {
      parts.lead = n; // "3 roses"
      continue;
    }
    if (pricePending) {
      parts.prices.add(n);
      pricePending = false;
    } else if (next == 'rs' || next == 'r' || next == 'ஆர்' || VoiceParser._isPriceWord(next)) {
      parts.prices.add(n);
      i++;
    } else if (VoiceParser._sizeUnit(next) != null) {
      final (factor, kind) = VoiceParser._sizeUnit(next)!;
      parts.size ??= n * factor;
      parts.sizeKind ??= kind;
      i++;
    } else {
      parts.bare.add(n);
    }
  }
  return parts;
}

// ── sound keys ───────────────────────────────────────────────────────────

const _consonants = {
  'க': 'k', 'ங': 'ng', 'ச': 's', 'ஞ': 'nj', 'ட': 't', 'ண': 'n', 'த': 't',
  'ந': 'n', 'ப': 'p', 'ம': 'm', 'ய': 'y', 'ர': 'r', 'ல': 'l', 'வ': 'v',
  'ழ': 'l', 'ள': 'l', 'ற': 'r', 'ன': 'n', 'ஜ': 'j', 'ஷ': 'sh', 'ஸ': 's',
  'ஹ': 'h',
};
const _vowels = {
  'அ': 'a', 'ஆ': 'aa', 'இ': 'i', 'ஈ': 'ii', 'உ': 'u', 'ஊ': 'uu', 'எ': 'e',
  'ஏ': 'ee', 'ஐ': 'ai', 'ஒ': 'o', 'ஓ': 'oo', 'ஔ': 'au',
};
const _signs = {
  'ா': 'aa', 'ி': 'i', 'ீ': 'ii', 'ு': 'u', 'ூ': 'uu', 'ெ': 'e', 'ே': 'ee',
  'ை': 'ai', 'ொ': 'o', 'ோ': 'oo', 'ௌ': 'au',
};

/// Tamil letters → Latin letters (ஹமாம் → hamaam). Other text is kept.
String transliterate(String text) {
  final b = StringBuffer();
  // ட்ச is how Tamil writes "ksh": லட்சுமி = Lakshmi
  final chars = text.replaceAll('ட்ச', 'க்ஷ').split('');
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    final cons = _consonants[c];
    if (cons != null) {
      b.write(cons);
      final next = i + 1 < chars.length ? chars[i + 1] : '';
      if (next == '்') {
        i++;
      } else if (_signs.containsKey(next)) {
        b.write(_signs[next]);
        i++;
      } else {
        b.write('a');
      }
      continue;
    }
    final v = _vowels[c];
    if (v != null) {
      b.write(v);
      continue;
    }
    if (c == 'ஃ') {
      continue; // ஃப = f, the same sound as ப in a sound key
    }
    b.write(c);
  }
  return b.toString();
}

/// A spelling-free key for how a word sounds, the same for its Tamil and
/// English spellings: hamam / ஹமாம் → "amam", colgate / கோல்கேட் → "kalkat".
String soundKey(String word) {
  final isTamil = RegExp(r'[஀-௿]').hasMatch(word);
  var s = transliterate(word.toLowerCase()).replaceAll(RegExp(r'[^a-z]'), '');
  if (s.isEmpty) return '';
  if (isTamil) {
    // Tamil puts a short vowel inside English sounds: புரூ (bru),
    // பிரஷ் (brush), கிரீம் (cream), ஸ்டார் is fine
    s = s.replaceFirstMapped(RegExp(r'^([kgptbdsf])[ui]([rl])'), (m) => '${m[1]}${m[2]}');
  }
  const pairs = [
    ('ph', 'p'), ('th', 't'), ('dh', 't'), ('sh', 's'), ('ch', 's'), ('zh', 'l'),
    ('kh', 'k'), ('gh', 'k'), ('bh', 'p'), ('ck', 'k'), ('x', 'ks'), ('q', 'k'),
    ('w', 'v'), ('z', 's'), ('j', 's'), ('f', 'p'), ('g', 'k'), ('d', 't'), ('b', 'p'),
  ];
  for (final (a, b) in pairs) {
    s = s.replaceAll(a, b);
  }
  s = s.replaceAllMapped(RegExp(r'c([eiy])'), (m) => 's${m[1]}').replaceAll('c', 'k');
  s = s.replaceAll('h', '');
  s = s.replaceAll(RegExp(r'[aeiouy]+'), 'a');
  s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  if (s.length > 2 && s.endsWith('a')) s = s.substring(0, s.length - 1);
  return s;
}

double _similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  var lev = 1 - _levenshtein(a, b) / longer.length;
  // consonants only: "lites" / லைட்ஸ், "lakshmi" / லட்சுமி differ only in
  // vowels that English writes and Tamil adds
  final ca = _consonantsOf(a);
  final cb = _consonantsOf(b);
  if (ca.length >= 3 && cb.length >= 3) {
    final c = 0.95 * (1 - _levenshtein(ca, cb) / max(ca.length, cb.length));
    if (c > lev) lev = c;
  }
  // "navarat" said, "navaratna" written: the start of a longer word. Short
  // keys are not trusted this way ("sak" is not "sakar").
  if (shorter.length >= 4 && longer.startsWith(shorter)) {
    return max(lev, 0.6 + 0.3 * shorter.length / longer.length);
  }
  return lev;
}

String _consonantsOf(String key) => key[0] + key.substring(1).replaceAll('a', '');

int _levenshtein(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Collects what the phone hears into one order.
///
/// Many Android phones start a fresh piece of text after each short pause,
/// and their final result holds only the last piece, so a 5-item order came
/// back as the 5th item only (owner, 16 Oct 2026). Pieces are kept here:
/// when the words being heard start over, the earlier piece is saved, and
/// every final result is saved, across listening restarts.
class VoiceTranscript {
  final List<String> _pieces = [];
  // the phone's other guesses for each saved piece (first = the piece)
  final List<List<String>> _guesses = [];
  String _current = '';

  /// Per piece, the phone's guesses, best first (for [VoiceParser.parseBest]).
  List<List<String>> get guesses => [
        ..._guesses,
        if (_current.trim().isNotEmpty) [_current.trim()],
      ];

  /// Everything heard so far, one piece per item group, comma separated
  /// (the parser splits items on commas).
  String get text => [..._pieces, if (_current.trim().isNotEmpty) _current.trim()].join(', ');

  bool get isEmpty => text.isEmpty;

  /// A words-so-far update while the person is speaking.
  void partial(String words) {
    final w = words.trim();
    if (w.isEmpty) return;
    if (_startsOver(_current, w)) _save(_current);
    _current = w;
  }

  /// The phone's final words for this stretch of listening.
  void finalResult(String words, {List<String> alternates = const []}) {
    final saved = _pieces.join(' ');
    // a phone that does return everything: drop what is already saved
    String strip(String t) {
      var w = t.trim();
      if (saved.isNotEmpty && _norm(w).startsWith(_norm(saved))) {
        w = w.substring(min(w.length, _prefixLength(w, saved))).trim();
      }
      return w;
    }

    final w = strip(words);
    if (w.isEmpty) {
      flush();
      return;
    }
    if (_startsOver(_current, w)) _save(_current);
    _current = '';
    final others = [
      for (final a in alternates)
        if (strip(a).isNotEmpty && strip(a) != w) strip(a),
    ];
    _save(w, others: others);
  }

  /// Keeps the words being heard (listening was stopped mid-way).
  void flush() {
    _save(_current);
    _current = '';
  }

  void _save(String piece, {List<String> others = const []}) {
    final p = piece.trim();
    if (p.isEmpty) return;
    if (_pieces.isNotEmpty && _norm(_pieces.last) == _norm(p)) {
      if (others.isNotEmpty) _guesses.last = [p, ...others];
      return;
    }
    _pieces.add(p);
    _guesses.add([p, ...others]);
  }

  /// The new words are a new piece, not the old piece growing or being
  /// corrected: they start differently and are clearly shorter.
  static bool _startsOver(String before, String now) {
    final b = before.trim();
    if (b.isEmpty) return false;
    final bw = b.split(RegExp(r'\s+'));
    final nw = now.trim().split(RegExp(r'\s+'));
    if (_norm(now).startsWith(_norm(b))) return false; // growing
    if (nw.first == bw.first) return false; // corrected, same start
    return nw.length < bw.length || now.length < b.length * 0.7;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s,]+'), ' ').trim();

  /// How many characters of [w] cover [saved] (ignoring spaces/commas).
  static int _prefixLength(String w, String saved) {
    final target = _norm(saved).replaceAll(' ', '').length;
    var seen = 0;
    for (var i = 0; i < w.length; i++) {
      if (!RegExp(r'[\s,]').hasMatch(w[i])) seen++;
      if (seen >= target) return i + 1;
    }
    return w.length;
  }
}

/// Reads an order on a background thread: `Isolate.run(() =>
/// parseVoiceOrder(products, learned, text))` must not be written inside
/// a screen's method, where the closure can carry the screen with it and
/// cannot be sent (the sheet never opened, 16 Oct 2026). This top-level
/// function carries only its arguments.
Future<VoiceOrder> parseVoiceOrderInBackground(
  List<Product> products,
  Map<String, String> learned,
  Map<String, String> words,
  List<List<String>> guesses,
) {
  return Isolate.run(
    () => VoiceParser(products, learned: learned, words: words).parseBest(guesses),
  );
}

/// What was heard (the guesses that matched best) and the bill lines.
class VoiceOrder {
  VoiceOrder(this.heard, this.lines);
  final String heard;
  final List<VoiceLine> lines;
}
