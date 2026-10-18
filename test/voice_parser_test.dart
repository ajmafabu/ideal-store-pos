import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:ideal_store_pos/utils/voice_parser.dart';

/// Product names as the shop writes them (English + Tamil name).
final _names = <(String, String?, String)>[
  ('Marie gold 10 rs', 'மேரி கோல்ட் 10 Rs', 'pcs'),
  ('Marie gold 20 rs', 'மேரி கோல்ட் 20 Rs', 'pcs'),
  ('Marie gold 30 rs', 'மேரி கோல்ட் 30 Rs', 'pcs'),
  ('Marie Light 10 rs', 'மேரி லைட் 10 Rs', 'pcs'),
  ('margo 10 rs', 'மார்கோ 10 Rs', 'pcs'),
  ('SUGAR BANNARI 1 kg', 'சுகர் பண்ணாரி 1 கேஜி', 'pcs'),
  ('SUGAR PONNI 100 gram', 'சுகர் பொன்னி 100 கிராம்', 'pcs'),
  ('SUGAR RAJSREE 500gram', 'சுகர் ராஜஸ்ரீ 500கிராம்', 'pcs'),
  ('hamam 10 rs soap', 'ஹமாம் 10 Rs சோப்', 'pcs'),
  ('hamam 38 rs', 'ஹமாம் 38 Rs', 'pcs'),
  ('lux 10 rs', 'லக்ஸ் 10 Rs', 'pcs'),
  ('lux rose 40rs', 'லக்ஸ் ரோஸ் 40Rs', 'pcs'),
  ('RIN SOAP 20 RS', 'ரின் சோப் 20 Rs', 'pcs'),
  ('Rin 10 rs soap', 'ரின் 10 Rs சோப்', 'pcs'),
  ('thuvaramparuppu 250 gm', 'துவரம்பருப்பு 250 gm', 'pcs'),
  ('thuvaramparuppu 500 gm', 'துவரம்பருப்பு 500 gm', 'pcs'),
  ('mani karam 1 kg', 'மணி காரம் 1 கேஜி', 'kg'),
  ('KADALAI MITTAI 5RS JAR', 'கடலை மிட்டாய் 5Rs ஜார்', 'pcs'),
  ('five star 10 rs', 'ஃபைவ் ஸ்டார் 10 Rs', 'box'),
  ('choco star', 'சோக்கோ ஸ்டார்', 'pcs'),
  ('Maha palmoil 1 lit', 'மஹா பாமாயில் 1 லிட்டர்', 'pcs'),
  ('Maha palmoil 1/2 lit', 'மஹா பாமாயில் 1/2 லிட்டர்', 'pcs'),
  ('Navarathna oil 10 rs', 'நவரத்னா ஆயில் 10 Rs', 'pcs'),
  ('Navarathna oil 1 rs', 'நவரத்னா ஆயில் 1 Rs', 'pcs'),
  ('3 roses 5 rs', '3 ரோசஸ் 5 rs', 'pcs'),
  ('3 roses 20 rs', '3 ரோசஸ் 20 Rs', 'pcs'),
  ('Bru 10 rs', 'புரூ 10 Rs', 'pcs'),
  ('Bru 2 rs', 'புரூ 2 Rs', 'pcs'),
  ('Esoap bar 10 rs', null, 'pcs'),
  ('good night koshu bathi', 'குட் நைட் கொசு பத்தி', 'pcs'),
  ('good night', 'குட் நைட்', 'pcs'),
  ('SAKTHI CHILLI', 'சக்தி சில்லி', 'pcs'),
  ('sakthi sambar 10rs', 'சக்தி சாம்பார் 10Rs', 'pack'),
  ('Colgate 2', 'கோல்கேட் 2', 'pcs'),
  ('colgate 20rs', 'கோல்கேட் 20Rs', 'pcs'),
  ('chik chik', null, 'pcs'),
  ('choki choki 2 rs', null, 'pcs'),
  ('melody choclate', 'மெலடி சாக்லேட்', 'pcs'),
  ('dettol 10 rs', 'டெட்டால் 10 Rs', 'pcs'),
  ('LAKSHMI SEEVAL 10', 'லக்ஷ்மி சீவல் 10', 'pcs'),
  ('LAKSHMI SEEVAL 5', 'லட்சுமி சீவல் 5', 'pcs'),
  ('MLS SEEVAL 10 N', 'எம்எல்எஸ் சீவல் 10 என்', 'pcs'),
  ('SULTHAN POGAYILAI', 'சுல்தான் புகையிலை', 'pcs'),
  ('kings cigrate', 'கிங்ஸ் சிகரெட்', 'pcs'),
  ('sciccor filter', 'சிசர் ஃபில்டர்', 'pcs'),
  ('flake cigrate', 'பிளேக் சிகரட்', 'pcs'),
  ('RASAM PODI 10', 'ரசம் பொடி 10', 'pcs'),
];

late List<Product> _products;
late VoiceParser _parser;

Product _p(String name) => _products.firstWhere((p) => p.name == name);

/// The best line for one spoken item.
VoiceChoice _best(String spoken) {
  final lines = _parser.parse(spoken);
  expect(lines, hasLength(1), reason: spoken);
  final best = lines.single.best;
  expect(best, isNotNull, reason: spoken);
  return best!;
}

void _expectBest(String spoken, String product, double qty) {
  final b = _best(spoken);
  expect(b.product.name, product, reason: spoken);
  expect(b.qty, qty, reason: spoken);
}

void main() {
  setUpAll(() {
    var i = 0;
    _products = [
      for (final (name, tamil, unit) in _names)
        Product(id: 'p${i++}', name: name, tamilName: tamil, unit: unit, sellingPrice: 10),
    ];
    _parser = VoiceParser(_products);
  });

  group('Tamil numbers', () {
    test('words, spoken forms and joined forms', () {
      final cases = {
        'ரெண்டு': 2.0, 'மூணு': 3.0, 'அஞ்சு': 5.0, 'பத்து': 10.0, 'பன்னெண்டு': 12.0,
        'இருபது': 20.0, 'இருபத்தஞ்சு': 25.0, 'இருபத்தொன்று': 21.0, 'முப்பத்திரண்டு': 32.0,
        'நாப்பத்தெட்டு': 48.0, 'நூறு': 100.0, 'நூத்தம்பது': 150.0, 'அரை': 0.5,
        'நாளு': 4.0, 'கால்': 0.25, 'முக்கால்': 0.75, 'ஒன்றரை': 1.5, 'ரெண்டரை': 2.5, '12': 12.0,
        '1.5': 1.5, 'twenty': 20.0,
      };
      cases.forEach((word, n) => expect(VoiceParser.parseNumberWord(word), n, reason: word));
    });

    test('ordinary words are not numbers', () {
      for (final w in ['அரிசி', 'சர்க்கரை', 'ஆறுமுகம்', 'காலை', 'lux']) {
        expect(VoiceParser.parseNumberWord(w), isNull, reason: w);
      }
    });
  });

  group('the old bugs', () {
    test('a correct Tamil word is not changed inside (அரிசி, சாக்லேட்)', () {
      // the old code turned சாக்லேட் into "லேட்" and அரிசி into "அரிசிி"
      final line = _parser.parse('சாக்லேட் ரெண்டு').single;
      expect(line.phrase, 'சாக்லேட்');
      expect(line.best!.product.name, 'melody choclate');
      expect(line.best!.qty, 2);
    });

    test('the price picks the product (₹10 vs ₹20 Marie Gold)', () {
      _expectBest('ரெண்டு மேரி கோல்ட் பத்து ரூபாய்', 'Marie gold 10 rs', 2);
      _expectBest('மேரி கோல்ட் 20 ரூபாய் 3 பாக்கெட்', 'Marie gold 20 rs', 3);
      _expectBest('marie gold ₹30', 'Marie gold 30 rs', 1);
    });

    test('grams are a pack size, not the quantity', () {
      _expectBest('அரை கிலோ சர்க்கரை', 'SUGAR RAJSREE 500gram', 1);
      _expectBest('2 kg sugar', 'SUGAR BANNARI 1 kg', 2); // two 1 kg packs
      _expectBest('துவரம் பருப்பு 500 கிராம்', 'thuvaramparuppu 500 gm', 1);
      _expectBest('பாமாயில் அரை லிட்டர்', 'Maha palmoil 1/2 lit', 1);
    });

    test('English units are understood', () {
      _expectBest('maha palmoil 1 litre', 'Maha palmoil 1 lit', 1);
      _expectBest('3 packets rin soap 20 rs', 'RIN SOAP 20 RS', 3);
    });

    test('loose goods take the weight as the quantity', () {
      _expectBest('ஒன்றரை கிலோ மணி காரம்', 'mani karam 1 kg', 1.5);
    });

    test('half a piece is flagged, never billed as 0.5', () {
      final b = _best('அரை ஹமாம்');
      expect(b.qty, 1);
      expect(b.needsCheck, isTrue);
      expect(_parser.parse('அரை ஹமாம்').single.isSure, isFalse);
    });

    test('numbers above 20 are understood', () {
      _expectBest('இருபத்தஞ்சு கடலை மிட்டாய் 5 ரூபாய்', 'KADALAI MITTAI 5RS JAR', 25);
    });
  });

  group('matching by sound', () {
    test('Tamil spelling finds the English name', () {
      _expectBest('ஹமாம் சோப்பு மூணு', 'hamam 10 rs soap', 3);
      _expectBest('நவரத்னா ஆயில் பத்து ரூபாய்', 'Navarathna oil 10 rs', 1);
      _expectBest('good night கொசு பத்தி', 'good night koshu bathi', 1);
      _expectBest('மூணு பாக்கெட் சக்தி சில்லி', 'SAKTHI CHILLI', 3);
    });

    test('Tamil vowel inside an English name (புரூ = Bru)', () {
      _expectBest('புரூ 10 ரூபாய் நாலு', 'Bru 10 rs', 4);
    });

    test('everyday Tamil words find English names (சர்க்கரை = sugar)', () {
      expect(_best('சர்க்கரை').product.name, startsWith('SUGAR'));
    });

    test('the shorter name wins when nothing else is said', () {
      _expectBest('லக்ஸ்', 'lux 10 rs', 1);
    });

    test('short look-alikes do not win (சர்க்கரை is not chik chik)', () {
      final names = _parser.parse('250 கிராம் சர்க்கரை').single.choices.take(3).map((c) => c.product.name);
      expect(names.first, startsWith('SUGAR'));
    });

    test('two short words do not join into another name (டீ தூள் ≠ dettol)', () {
      final best = _parser.parse('டீ தூள்').single.best;
      expect(best?.product.name, isNot('dettol 10 rs'));
    });
  });

  group('numbers that belong to the name', () {
    test('"five star" is a name, not 5 × star', () {
      _expectBest('five star 10 rs', 'five star 10 rs', 1);
    });

    test('"3 roses" keeps its 3; a number before it is the quantity', () {
      _expectBest('3 ரோசஸ் 5 ரூபாய்', '3 roses 5 rs', 1);
      _expectBest('ரெண்டு 3 roses 20 rs', '3 roses 20 rs', 2);
    });
  });

  group('several items in one sentence', () {
    test('split on மற்றும் / அப்புறம் / commas / and', () {
      final lines = _parser.parse('லக்ஸ் 10 ரூபாய் அஞ்சு மற்றும் ரின் சோப் 20 ரூபாய், 2 kg sugar and five star 10 rs');
      expect(lines.map((l) => l.best!.product.name).toList(), [
        'lux 10 rs',
        'RIN SOAP 20 RS',
        'SUGAR BANNARI 1 kg',
        'five star 10 rs',
      ]);
      expect(lines.map((l) => l.best!.qty).toList(), [5, 1, 2, 1]);
    });

    test('splitting keeps decimals and whole words', () {
      expect(VoiceParser.splitItems('1.5 kg mani karam, lux'), ['1.5 kg mani karam', 'lux']);
      // "and" inside a word does not split it
      expect(VoiceParser.splitItems('candle andhra'), ['candle andhra']);
    });
  });

  group('confirm before adding', () {
    test('a clear match is sure; a close race is not', () {
      expect(_parser.parse('ரின் சோப் 20 ரூபாய்').single.isSure, isTrue);
      // ₹10 Marie Gold and ₹10 Marie Light: say "மேரி" only → ask
      expect(_parser.parse('மேரி 10 ரூபாய்').single.isSure, isFalse);
    });

    test('nothing matched gives no choices, not a wrong product', () {
      final line = _parser.parse('ஹெலிகாப்டர்').single;
      expect(line.choices.where((c) => c.score >= VoiceParser.sureScore), isEmpty);
    });

    test('a learned pick goes first next time', () {
      final learned = VoiceParser(_products, learned: {'மேரி': _p('Marie Light 10 rs').id});
      final line = learned.parse('மேரி 10 ரூபாய்').single;
      expect(line.best!.product.name, 'Marie Light 10 rs');
      expect(line.isSure, isTrue);
    });

    test('only numbers or only fillers give no line', () {
      expect(_parser.parse('ரெண்டு'), isEmpty);
      expect(_parser.parse('குடுங்க'), isEmpty);
    });
  });

  group('collecting a 5-item order (phone starts over after pauses)', () {
    test('pieces are kept when the words start over', () {
      final t = VoiceTranscript()
        ..partial('லக்ஸ்')
        ..partial('லக்ஸ் 10 ரூபாய்')
        ..partial('லக்ஸ் 10 ரூபாய் அஞ்சு')
        // pause: the phone starts a new piece
        ..partial('ஹமாம்')
        ..partial('ஹமாம் சோப்பு மூணு')
        ..partial('அரை')
        ..partial('அரை கிலோ சர்க்கரை')
        // its final result holds only the last piece
        ..finalResult('அரை கிலோ சர்க்கரை');
      expect(t.text, 'லக்ஸ் 10 ரூபாய் அஞ்சு, ஹமாம் சோப்பு மூணு, அரை கிலோ சர்க்கரை');
    });

    test('pieces from several listening restarts are joined', () {
      final t = VoiceTranscript()
        ..partial('five star')
        ..finalResult('five star 10 rs')
        ..partial('2 kg')
        ..finalResult('2 kg sugar')
        ..partial('rin soap')
        ..flush(); // the mic was tapped mid-way
      expect(t.text, 'five star 10 rs, 2 kg sugar, rin soap');
      final lines = _parser.parse(t.text);
      expect(lines.map((l) => l.best!.product.name).toList(),
          ['five star 10 rs', 'SUGAR BANNARI 1 kg', 'RIN SOAP 20 RS']);
    });

    test('a phone that returns everything is not doubled', () {
      final t = VoiceTranscript()
        ..finalResult('five star 10 rs')
        ..finalResult('five star 10 rs 2 kg sugar');
      expect(t.text, 'five star 10 rs, 2 kg sugar');
    });

    test('a corrected word is not a new item', () {
      final t = VoiceTranscript()
        ..partial('மேரி கோல்டு')
        ..partial('மேரி கோல்ட் 10 ரூபாய்')
        ..finalResult('மேரி கோல்ட் 10 ரூபாய்');
      expect(t.text, 'மேரி கோல்ட் 10 ரூபாய்');
    });
  });

  group('items said with no pause between them (owner, 16 Oct 2026)', () {
    List<String> names(String said) => _parser.parse(said).map((l) => l.best!.product.name).toList();

    test('sugar, two seevals and pogayilai', () {
      expect(names('சுகர் ஒரு கிலோ லட்சுமி சீவல் 10 எம் எல் எஸ் சீவல் 10, சுல்தான் போகலை பத்து'), [
        'SUGAR BANNARI 1 kg',
        'LAKSHMI SEEVAL 10',
        'MLS SEEVAL 10 N',
        'SULTHAN POGAYILAI',
      ]);
    });

    test('cigarettes', () {
      expect(names('கிங்ஸ் 10 சிசர் பில்டர் பத்து ஃபிளக்ஸ் சிகரெட் 10'), [
        'kings cigrate',
        'sciccor filter',
        'flake cigrate',
      ]);
    });

    test('a long order in one breath', () {
      final lines = _parser.parse(
          'ரெண்டு மேரி கோல்ட் பத்து ரூபாய் அரை கிலோ சர்க்கரை ஹமாம் சோப்பு மூணு லக்ஸ் 10 ரூபாய் அஞ்சு five star 10 rs');
      expect(lines.map((l) => l.best!.product.name).toList(), [
        'Marie gold 10 rs',
        'SUGAR RAJSREE 500gram',
        'hamam 10 rs soap',
        'lux 10 rs',
        'five star 10 rs',
      ]);
      expect(lines.map((l) => l.best!.qty).toList(), [2, 1, 3, 5, 1]);
    });

    test('a describing word does not start a new item', () {
      expect(names('சக்தி சாம்பார் பொடி பத்து ரூபாய்'), ['sakthi sambar 10rs']);
    });

    test('spelled letters are joined (எம் எல் எஸ் = MLS)', () {
      expect(names('எம் எல் எஸ் சீவல் 10'), ['MLS SEEVAL 10 N']);
    });
  });

  test('the order is read on a background thread (the sheet opens)', () async {
    final order = await parseVoiceOrderInBackground(_products, const {}, const {}, [
      ['லட்சுமி சீவல் 10 எம் எல் எஸ் சீவல் 10'],
    ]);
    expect(order.lines.map((l) => l.best!.product.name).toList(), ['LAKSHMI SEEVAL 10', 'MLS SEEVAL 10 N']);
  });

  group("the phone's other guesses (idea 1)", () {
    test('the guess that names a product wins ("குரு" heard, "ப்ரூ" also guessed)', () {
      final order = _parser.parseBest([
        ['குரு 10 ரூபாய் நாலு', 'ப்ரூ 10 ரூபாய் நாலு', 'குருவி 10 ரூபாய் நாலு'],
      ]);
      expect(order.heard, 'ப்ரூ 10 ரூபாய் நாலு');
      expect(order.lines.single.best!.product.name, 'Bru 10 rs');
      expect(order.lines.single.best!.qty, 4);
    });

    test('each stretch of speech picks its own best guess', () {
      final order = _parser.parseBest([
        ['லக்ஸ் 10 ரூபாய்', 'லக்ஸ் 10 ரூபா'],
        ['குரு 2 ரூபாய்', 'bru 2 rupees'],
      ]);
      expect(order.lines.map((l) => l.best!.product.name).toList(), ['lux 10 rs', 'Bru 2 rs']);
    });

    test('with equal guesses the phone’s first one is kept', () {
      final order = _parser.parseBest([
        ['ஹமாம் சோப்பு மூணு', 'ஹமாம் சோப்பு மூனு'],
      ]);
      expect(order.heard, 'ஹமாம் சோப்பு மூணு');
    });
  });

  group('taught words (idea 2)', () {
    test('a taught word is put in before matching, whole words only', () {
      final taught = VoiceParser(_products, words: {'குரு': 'bru'});
      expect(taught.applyWords('குரு 10 ரூபாய், குருவி'), 'bru 10 ரூபாய், குருவி');
      final line = taught.parse('குரு 10 ரூபாய் நாலு').single;
      expect(line.best!.product.name, 'Bru 10 rs');
      expect(line.best!.qty, 4);
    });

    test('longer taught phrases go first', () {
      final taught = VoiceParser(_products, words: {'குரு': 'bru', 'குரு சோப்': 'rin soap'});
      expect(taught.applyWords('குரு சோப் 20 ரூபாய்'), 'rin soap 20 ரூபாய்');
    });

    test('a correction in the sheet becomes a taught word', () {
      expect(VoiceParser.correctionsBetween('குரு 10 ரூபாய் நாலு', 'bru 10 ரூபாய் நாலு'), {'குரு': 'bru'});
      expect(
        VoiceParser.correctionsBetween('ரெண்டு குரு, மேரி கோல்ட்', 'ரெண்டு bru, marie gold'),
        {'குரு': 'bru', 'மேரி கோல்ட்': 'marie gold'},
      );
      // numbers changed are not words to remember; nothing changed → nothing
      expect(VoiceParser.correctionsBetween('லக்ஸ் 10', 'லக்ஸ் 20'), isEmpty);
      expect(VoiceParser.correctionsBetween('லக்ஸ் 10', 'லக்ஸ் 10'), isEmpty);
    });
  });

  test('the transcript keeps the phone’s guesses for each piece', () {
    final t = VoiceTranscript()
      ..finalResult('குரு 10 ரூபாய்', alternates: ['ப்ரூ 10 ரூபாய்'])
      ..partial('லக்ஸ்');
    expect(t.guesses, [
      ['குரு 10 ரூபாய்', 'ப்ரூ 10 ரூபாய்'],
      ['லக்ஸ்'],
    ]);
  });

  test('round 2 with the owner: குரு taught as bru, நாளு heard for நாலு', () {
    final taught = VoiceParser(_products, words: {'குரு': 'bru'});
    final lines = taught.parse('குரு பத்து ரூபாய் நாளு அரை கிலோ சர்க்கரை ஹமாம் சோப்பு மூணு');
    expect(lines.map((l) => l.best!.product.name).toList(), ['Bru 10 rs', 'SUGAR RAJSREE 500gram', 'hamam 10 rs soap']);
    expect(lines.map((l) => l.best!.qty).toList(), [4, 1, 3]);
  });

  test('round 5 with the owner: quantities said before the name', () {
    final lines = _parser.parse('25 கடலை மிட்டாய் அஞ்சு ரூபாய் 3 பாக்கெட் சக்தி சில்லி அரை ஹமாம்');
    expect(lines.map((l) => l.best!.product.name).toList(), [
      'KADALAI MITTAI 5RS JAR',
      'SAKTHI CHILLI',
      startsWith('hamam'),
    ]);
    expect(lines[0].best!.qty, 25);
    expect(lines[1].best!.qty, 3);
    expect(lines[2].best!.needsCheck, isTrue); // half a soap: check
  });

  test('round 7 with the owner: the phone writes "five star" as "5 star"', () {
    final lines = _parser.parse('5 star 10 rupees 2 kg sugar Colgate salt 20 rupees');
    expect(lines.first.best!.product.name, 'five star 10 rs');
    expect(lines.first.best!.qty, 1);
    expect(lines[1].best!.qty, 2);
    // and "2 5 star" is two of them
    expect(_parser.parse('2 5 star 10 rs').single.best!.qty, 2);
  });

  test('sound keys: Tamil and English spellings agree', () {
    expect(soundKey('ஹமாம்'), soundKey('hamam'));
    expect(soundKey('கோல்கேட்'), soundKey('colgate'));
    expect(soundKey('மேரி'), soundKey('marie'));
    expect(soundKey('பொன்னி'), soundKey('ponni'));
    expect(soundKey('புரூ'), soundKey('bru'));
    expect(soundKey('நவரத்னா'), soundKey('navarathna'));
  });
}
