import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/product.dart';
import 'logger.dart';

class VoiceBillingResult {
  final Product product;
  final double qty;
  final String spokenText;
  final List<Product> alternatives;

  VoiceBillingResult({
    required this.product,
    required this.qty,
    required this.spokenText,
    this.alternatives = const [],
  });
}

class _ScoredProduct {
  final Product product;
  final double score;
  _ScoredProduct(this.product, this.score);
}

class VoiceBilling {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  // ── Comprehensive Tamil speech corrections (200+ entries) ──
  // Format: 'spoken_variant' → 'correct_tamil'
  static final Map<String, String> _tamilCorrections = {
    // Groceries - Rice & Grains
    'அரிசி': 'அரிசி', 'அரிஷி': 'அரிசி', 'அரிச': 'அரிசி',
    'சம்பா': 'சம்பா', 'சம்ப': 'சம்பா', 'சம்பா அரிசி': 'சம்பா அரிசி',
    'பாஸ்மதி': 'பாஸ்மதி', 'பாஸ்மத': 'பாஸ்மதி', 'பாஸ்மதீ': 'பாஸ்மதி',
    'ராவிசி': 'ராவிசி', 'ராவிஸ்': 'ராவிசி',
    'புல்லு': 'புல்லு', 'புல்': 'புல்லு',
    'கோதுமை': 'கோதுமை', 'கோதும': 'கோதுமை', 'கோதுமை மாவு': 'கோதுமை மாவு',
    'மாவு': 'மாவு', 'மாவ': 'மாவு',
    'அவல்': 'அவல்', 'அவல': 'அவல்',
    'பொரி': 'பொரி', 'பொர': 'பொரி',
    'உளுந்து': 'உளுந்து', 'உளுந்த': 'உளுந்து', 'உதுளு': 'உளுந்து',
    'பருப்பு': 'பருப்பு', 'பரப்பு': 'பருப்பு', 'பருப': 'பருப்பு',
    'துவரம்': 'துவரம்', 'துவர': 'துவரம்',
    'பாசிப்': 'பாசிப்', 'பாசி': 'பாசிப்',
    'மூங்கில்': 'மூங்கில்', 'மூங்கில': 'மூங்கில்',
    'மொச்சை': 'மொச்சை', 'மொச்ச': 'மொச்சை',
    'கொண்டை': 'கொண்டை', 'கொண்ட': 'கொண்டை',
    'சோயா': 'சோயா', 'சோய': 'சோயா',

    // Spices & Seasonings
    'மிளகாய்': 'மிளகாய்', 'மிளகாய': 'மிளகாய்', 'மிளகா': 'மிளகாய்',
    'மிளகு': 'மிளகு', 'மிளக': 'மிளகு',
    'சீரகம்': 'சீரகம்', 'சீரக': 'சீரகம்', 'சீரகம': 'சீரகம்',
    'சின்ன வெங்காயம்': 'சின்ன வெங்காயம்',
    'மல்லி': 'மல்லி', 'மல்ல': 'மல்லி', 'மல்லி தூள்': 'மல்லி தூள்',
    'கடுகு': 'கடுகு', 'கடுக': 'கடுகு',
    'வெந்தயம்': 'வெந்தயம்', 'வெந்தய': 'வெந்தயம்',
    'பெருங்காயம்': 'பெருங்காயம்', 'பெருங்காய': 'பெருங்காயம்', 'பெருங்கா': 'பெருங்காயம்',
    'மஞ்சள்': 'மஞ்சள்', 'மஞ்சல்': 'மஞ்சள்', 'மஞ்சள் தூள்': 'மஞ்சள் தூள்',
    'இஞ்சி': 'இஞ்சி', 'இஞ்ச': 'இஞ்சி',
    'பூண்டு': 'பூண்டு', 'பூண்ட': 'பூண்டு',
    'கருவேப்பிலை': 'கருவேப்பிலை', 'கருவேப்பில': 'கருவேப்பிலை',
    'சோம்பு': 'சோம்பு', 'சோம்ப': 'சோம்பு',
    'வசம்பு': 'வசம்பு', 'வசம்ப': 'வசம்பு',
    'ஓமம்': 'ஓமம்', 'ஓம': 'ஓமம்',
    'சேர்க்கை': 'சேர்க்கை', 'சேர்க்க': 'சேர்க்கை',

    // Vegetables
    'தக்காளி': 'தக்காளி', 'தக்காள': 'தக்காளி', 'தக்காலி': 'தக்காளி',
    'வெங்காயம்': 'வெங்காயம்', 'வெங்காய': 'வெங்காயம்', 'வெங்கா': 'வெங்காயம்',
    'உருளைக்கிழங்கு': 'உருளைக்கிழங்கு', 'உருளை': 'உருளைக்கிழங்கு',
    'முட்டைக்கோஸ்': 'முட்டைக்கோஸ்', 'முட்டைக்கோ': 'முட்டைக்கோஸ்',
    'காலிஃப்ளவர்': 'காலிஃப்ளவர்', 'காலிஃப்': 'காலிஃப்ளவர்',
    'பீன்ஸ்': 'பீன்ஸ்', 'பீன': 'பீன்ஸ்',
    'கத்திரிக்காய்': 'கத்திரிக்காய்', 'கத்திரி': 'கத்திரிக்காய்',
    'வெள்ளரி': 'வெள்ளரி', 'வெள்ளர': 'வெள்ளரி',
    'மிளகாய் தூள்': 'மிளகாய் தூள்',
    'பச்சை மிளகாய்': 'பச்சை மிளகாய்',
    'குடைமிளகாய்': 'குடைமிளகாய்',
    'பொடிமிளகாய்': 'பொடிமிளகாய்',
    'தேங்காய்': 'தேங்காய்', 'தேங்காய': 'தேங்காய்', 'தேங்கா': 'தேங்காய்',
    'தேங்காய் துருவல்': 'தேங்காய் துருவல்',

    // Dairy & Eggs
    'பால்': 'பால்', 'பால': 'பால்',
    'தயிர்': 'தயிர்', 'தயிர': 'தயிர்',
    'வெண்ணெய்': 'வெண்ணெய்', 'வெண்ணெய': 'வெண்ணெய்',
    'நெய்': 'நெய்', 'நெய': 'நெய்',
    'மோர்': 'மோர்', 'மோர': 'மோர்',
    'பன்னீர்': 'பன்னீர்', 'பன்னீர': 'பன்னீர்',
    'கிரீம்': 'கிரீம்', 'கிரீம': 'கிரீம்',
    'சீஸ்': 'சீஸ்', 'சீஸ': 'சீஸ்',
    'முட்டை': 'முட்டை', 'முட்ட': 'முட்டை',

    // Cooking Essentials
    'எண்ணெய்': 'எண்ணெய்', 'எண்ணெய': 'எண்ணெய்', 'எண்ணெ': 'எண்ணெய்',
    'சன்னா எண்ணெய்': 'சன்னா எண்ணெய்',
    'நல்லெண்ணெய்': 'நல்லெண்ணெய்',
    'கடலை எண்ணெய்': 'கடலை எண்ணெய்',
    'பாம் ஆயில்': 'பாம் ஆயில்',
    'சோயா எண்ணெய்': 'சோயா எண்ணெய்',
    'உப்பு': 'உப்பு', 'உப்ப': 'உப்பு',
    'சர்க்கரை': 'சர்க்கரை', 'சக்கரை': 'சர்க்கரை', 'சர்க்கர': 'சர்க்கரை',
    'நாட்டுச் சர்க்கரை': 'நாட்டுச் சர்க்கரை',
    'ஜாம்': 'ஜாம்', 'ஜாம': 'ஜாம்',

    // Beverages
    'தேநீர்': 'தேநீர்', 'டீ': 'தேநீர்', 'டீ தூள்': 'டீ தூள்',
    'காபி': 'காபி', 'கஃபி': 'காபி', 'காப்பி': 'காபி',
    'காபி தூள்': 'காபி தூள்',
    'ஹார்லிக்ஸ்': 'ஹார்லிக்ஸ்', 'ஹார்லிக்ஸ': 'ஹார்லிக்ஸ்',
    'பூஸ்ட்': 'பூஸ்ட்', 'பூஸ்ட': 'பூஸ்ட்',
    'கோமல்': 'கோமல்', 'கோமல': 'கோமல்',
    'சாக்லேட்': 'சாக்லேட்', 'சாக்லேட': 'சாக்லேட்',
    'குளிர்பானம்': 'குளிர்பானம்', 'குளிர்பான': 'குளிர்பானம்',
    'புட்டில்': 'புட்டில்', 'புட்டி': 'புட்டில்',
    'மினரல் வாட்டர்': 'மினரல் வாட்டர்',
    'சோடா': 'சோடா', 'சோட': 'சோடா',

    // Snacks & Packaged Foods
    'பிஸ்கட்': 'பிஸ்கட்', 'பிஸ்க': 'பிஸ்கட்', 'பிஸ்கெட்': 'பிஸ்கட்',
    'சிப்ஸ்': 'சிப்ஸ்', 'சிப': 'சிப்ஸ்',
    'நூடுல்ஸ்': 'நூடுல்ஸ்', 'நூடுல்': 'நூடுல்ஸ்',
    'மேகி': 'மேகி', 'மகி': 'மேகி',
    'குக்கீஸ்': 'குக்கீஸ்', 'குக்கி': 'குக்கீஸ்',
    'பாப்கார்ன்': 'பாப்கார்ன்', 'பாப்கார்ந்': 'பாப்கார்ன்',
    'கார்ன் ஃப்ளேக்ஸ்': 'கார்ன் ஃப்ளேக்ஸ்',
    ' ஓட்ஸ்': 'ஓட்ஸ்', 'ஓட்ஸ்': 'ஓட்ஸ்',
    'செரியல்': 'செரியல்',

    // Cleaning & Household
    'சோப்பு': 'சோப்பு', 'சோப': 'சோப்பு',
    'ஷாம்பு': 'ஷாம்பு', 'ஷாம்ப': 'ஷாம்பு',
    'சர்ப்': 'சர்ப்', 'சப்': 'சர்ப்', 'சர்ப் பொடி': 'சர்ப் பொடி',
    'டவ்': 'டவ்', 'டப்': 'டவ்',
    'விம்': 'விம்', 'விம': 'விம்',
    'எக்ஸல்': 'எக்ஸல்', 'எக்ஸல': 'எக்ஸல்',
    'கிளோராக்ஸ்': 'கிளோராக்ஸ்',
    'ஃபினைல்': 'ஃபினைல்', 'ஃபினை': 'ஃபினைல்',
    'பாத்ரூம் கிளீனர்': 'பாத்ரூம் கிளீனர்',
    'கிச்சன் கிளீனர்': 'கிச்சன் கிளீனர்',
    'ஸ்பாஞ்ச்': 'ஸ்பாஞ்ச்', 'ஸ்பாஞ்ச': 'ஸ்பாஞ்ச்',
    'மாப்': 'மாப்', 'மாப': 'மாப்',
    'துடைப்பம்': 'துடைப்பம்', 'துடைப்ப': 'துடைப்பம்',

    // Personal Care
    'சோப்பு பார்': 'சோப்பு பார்',
    'பேஸ்ட்': 'பேஸ்ட்', 'பேஸ்ட': 'பேஸ்ட்',
    'பிரஷ்': 'பிரஷ்', 'பிரஷ': 'பிரஷ்',
    'லோஷன்': 'லோஷன்', 'லோஷன': 'லோஷன்',
    'பவுடர்': 'பவுடர்', 'பவுட': 'பவுடர்',
    'டால்கம்': 'டால்கம்',
    'ரோல் ஆன்': 'ரோல் ஆன்',
    'டியோ': 'டியோ', 'டியோடரண்ட்': 'டியோடரண்ட்',
    'பேர்ஷன்': 'பேர்ஷன்', 'பேர்ஷ': 'பேர்ஷன்',
    'ஷேவிங்': 'ஷேவிங்',
    'ரேஸர்': 'ரேஸர்', 'ரேஸ': 'ரேஸர்',

    // Brands (common Tamil speech variations)
    'ரின்': 'ரின்', 'ரினீ': 'ரின்',
    'நிரமா': 'நிரமா', 'நிரம': 'நிரமா',
    'வீல்': 'வீல்', 'வீல': 'வீல்',
    'பிரியா': 'பிரியா', 'பிரிய': 'பிரியா',
    'அரியா': 'அரியா', 'அரிய': 'அரியா',
    'சன் லайட்': 'சன் லைட்',
    'கோல்ட்': 'கோல்ட்', 'கோல்ட': 'கோல்ட்',
    'ரோஸ்': 'ரோஸ்', 'ரோஸஸ்': 'ரோஸ்',
    'லக்ஸ்': 'லக்ஸ்', 'லக்ஸ': 'லக்ஸ்',
    'ஹமம்': 'ஹமம்', 'ஹம்மம்': 'ஹமம்',
    'கல்கேட்': 'கல்கேட்', 'கல்கேட': 'கல்கேட்',
    'பார்லே': 'பார்லே', 'பார்ல': 'பார்லே',
    'டைட்': 'டைட்', 'டைட': 'டைட்',
    'ஐயா': 'ஐயா', 'ஐய': 'ஐயா',
    'நேச்சுரல்': 'நேச்சுரல்',
    'மேங்கோ': 'மேங்கோ', 'மேங்க': 'மேங்கோ',

    // Units & Measurements
    'கிலோகிராம்': 'கிலோ', 'கிலோ': 'கிலோ',
    'கிராம்': 'கிராம்', 'கிராம': 'கிராம்', 'கிரா': 'கிராம்',
    'லிட்டர்': 'லிட்டர்', 'லிற்றர்': 'லிட்டர்', 'லிட்ட': 'லிட்டர்',
    'மில்லி': 'மில்லி', 'மில்லி லிட்டர்': 'மில்லி லிட்டர்',
    'பாக்கெட்': 'பாக்கெட்', 'பேக்கெட்': 'பாக்கெட்', 'பாக்கெ': 'பாக்கெட்',
    'பாட்டில்': 'பாட்டில்', 'பாட்டி': 'பாட்டில்',
    'டப்பா': 'டப்பா', 'டப்ப': 'டப்பா',
    'டின்': 'டின்', 'டின': 'டின்',
    'மூடி': 'மூடி', 'மூட': 'மூடி',
    'கேன்': 'கேன்', 'கேன': 'கேன்',
    'சாக்கு': 'சாக்கு', 'சாக்': 'சாக்கு',
    'கவர்': 'கவர்', 'கவர': 'கவர்',
    'பெட்டி': 'பெட்டி', 'பெட்ட': 'பெட்டி',
    'மூட்டை': 'மூட்டை', 'மூட்ட': 'மூட்டை',
  };

  // ── Tamil product synonyms (spoken → canonical) ──
  static final Map<String, String> _tamilSynonyms = {
    'டீ': 'தேநீர்',
    'காப்பி': 'காபி',
    'சோப': 'சோப்பு',
    'ஷாம்ப': 'ஷாம்பு',
    'சர்ப்': 'சர்ப் பொடி',
    'டவ்': 'டவ்',
    'மகி': 'மேகி',
    'பிஸ்க': 'பிஸ்கட்',
    'சிப்': 'சிப்ஸ்',
    'சாக்லேட': 'சாக்லேட்',
    'ரோஸ்': 'ரோஸ்',
    'லக்ஸ்': 'லக்ஸ்',
    'ஹமம்': 'ஹமம்',
    'கல்கேட்': 'கல்கேட்',
    'பார்லே': 'பார்லே',
    'கோல்ட்': 'கோல்ட்',
    'நெய்': 'நெய்',
    'மோர்': 'மோர்',
  };

  // ── Tamil number words ──
  static final Map<String, double> _tamilNumbers = {
    'ஒன்று': 1.0, 'ஒரு': 1.0,
    'இரண்டு': 2.0, 'ரெண்டு': 2.0, 'இரண்ட': 2.0,
    'மூன்று': 3.0, 'மூணு': 3.0, 'மூன்ற': 3.0,
    'நான்கு': 4.0, 'நாலு': 4.0, 'நான்க': 4.0,
    'ஐந்து': 5.0, 'அஞ்சு': 5.0, 'ஐந்த': 5.0,
    'ஆறு': 6.0,
    'ஏழு': 7.0, 'ஏழ': 7.0,
    'எட்டு': 8.0, 'எட்ட': 8.0,
    'ஒன்பது': 9.0, 'ஒன்பத': 9.0,
    'பத்து': 10.0, 'பத்த': 10.0,
    'பதினொன்று': 11.0, 'பன்னிரண்டு': 12.0,
    'பதிமூன்று': 13.0, 'பதிநான்கு': 14.0,
    'பதினைந்து': 15.0, 'பதினாறு': 16.0, 'பதினேழு': 17.0,
    'பதினெட்டு': 18.0, 'பத்தொன்பது': 19.0,
    'இருபது': 20.0, 'இருபத': 20.0,
    'முப்பது': 30.0, 'முப்பத': 30.0,
    'நாற்பது': 40.0, 'நாற்பத': 40.0,
    'ஐம்பது': 50.0, 'ஐம்பத': 50.0,
    'அறுபது': 60.0, 'அறுபத': 60.0,
    'எழுபது': 70.0, 'எழுபத': 70.0,
    'எண்பது': 80.0, 'எண்பத': 80.0,
    'தொண்ணூறு': 90.0, 'தொண்ணூற': 90.0,
    'நூறு': 100.0, 'நூற': 100.0,
    'அரை': 0.5, 'கால்': 0.25, 'முக்கால்': 0.75,
  };

  // ── Tamil unit words ──
  static final List<String> _tamilUnits = [
    'கிலோகிராம்', 'கிலோகிரா', 'கிலோ', 'கி',
    'கிராம்', 'கிராம', 'கிரா',
    'லிட்டர்', 'லிற்றர்', 'லிட்ட', 'லிட்ட',
    'மில்லி லிட்டர்', 'மில்லி', 'மி',
    'பாக்கெட்', 'பேக்கெட்', 'பாக்',
    'பாட்டில்', 'பாட்டி', 'பாட்',
    'டப்பா', 'டப்ப', 'டப்',
    'டின்', 'டின',
    'பெட்டி', 'பெட்',
    'கேன்', 'கேன்',
    'சாக்கு', 'சாக்',
    'கவர்', 'கவர்',
    'டஜன்', 'டசன்',
    'எண்ணம்', 'எண்',
    'மூட்டை', 'மூட்',
    'கட்டு', 'கட்',
    'தொகுப்பு', 'தொகு',
    'பேக்', 'பேக்',
    'ரோல்', 'ரோல்',
    'பேர்', 'பேர்',
    'பேட்', 'பேட்',
    'ஸ்பூன்', 'ஸ்பூன்',
    'கப்', 'கப்',
    'கிண்ணம்', 'கிண்ண',
    'தட்டு', 'தட்',
    'பிளேட்', 'பிளேட்',
  ];

  // ── Tamil phrase patterns for quantity ──
  static final Map<String, double> _tamilPhrases = {
    'அரை கிலோகிராம்': 0.5, 'அரை கிலோ': 0.5,
    'கால் கிலோகிராம்': 0.25, 'கால் கிலோ': 0.25,
    'முக்கால் கிலோ': 0.75, 'முக்கால் கிலோகிராம்': 0.75,
    'ஒரு கிலோ': 1.0, 'ஒரு கிலோகிராம்': 1.0,
    'ஒரு லிட்டர்': 1.0, 'ஒரு லிற்றர்': 1.0,
    'ஒரு டஜன்': 12.0, 'ஒரு டசன்': 12.0,
    'அரை லிட்டர்': 0.5, 'கால் லிட்டர்': 0.25,
    'இரண்டு கிலோ': 2.0, 'மூன்று கிலோ': 3.0,
    'நான்கு கிலோ': 4.0, 'ஐந்து கிலோ': 5.0,
    'பத்து கிலோ': 10.0, 'இருபது கிலோ': 20.0,
  };

  Future<bool> initialize() async {
    _initialized = await _speech.initialize(
      onError: (error) => Logger.error('VoiceBilling', error),
      onStatus: (status) => Logger.info('VoiceBilling status: $status'),
    );
    return _initialized;
  }

  bool get isListening => _speech.isListening;

  Future<void> startListening({
    required Function(String) onPartialResult,
    required Function(List<VoiceBillingResult>) onResults,
    required List<Product> products,
    bool useTamil = false,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    final localeId = useTamil ? 'ta_IN' : 'en_IN';

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        onPartialResult(result.recognizedWords);
        if (result.finalResult) {
          Logger.info(
            'Voice (${useTamil ? "Tamil" : "English"}): "${result.recognizedWords}"',
          );
          final results = _parseSpokenText(
            result.recognizedWords,
            products,
            useTamil,
          );
          onResults(results);
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        localeId: localeId,
      ),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  // ── Apply Tamil corrections ──
  String _applyTamilCorrections(String text) {
    String result = text;
    // Apply corrections (longer patterns first for accuracy)
    final sortedEntries = _tamilCorrections.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in sortedEntries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  // ── Apply Tamil synonyms ──
  String _applyTamilSynonyms(String text) {
    String result = text;
    for (final entry in _tamilSynonyms.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  // ── Parse spoken text ──
  List<VoiceBillingResult> _parseSpokenText(
    String text,
    List<Product> products,
    bool useTamil,
  ) {
    final results = <VoiceBillingResult>[];

    // Apply corrections and synonyms for Tamil
    var correctedText = useTamil ? _applyTamilCorrections(text) : text;
    correctedText = useTamil ? _applyTamilSynonyms(correctedText) : correctedText;

    // Split by separators (Tamil has more patterns)
    final separators = useTamil
        ? RegExp(
            r'\s*,\s*|\s+ஆகிய\s+|\s+மற்றும்\s+|\s+வும்\s+|\s+ம்\s+|\s+and\s+|\s+பிறகு\s+|\s+அப்புறம்\s+',
          )
        : RegExp(r'\s*,\s*|\s+and\s+');

    final segments = correctedText.split(separators);

    for (final segment in segments) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;

      final parsed = _parseSegment(trimmed, products, useTamil);
      if (parsed != null) results.add(parsed);
    }

    return results;
  }

  // ── Parse a single segment ──
  VoiceBillingResult? _parseSegment(
    String text,
    List<Product> products,
    bool useTamil,
  ) {
    final lower = text.toLowerCase().trim();

    // Try compound pattern first: "2 கிலோ அரிசி" or "அரிசி 2 கிலோ"
    final compound = _parseCompoundPattern(lower, products, useTamil);
    if (compound != null) return compound;

    // Extract quantity
    final qty = _extractQuantity(lower);
    final qtyValue = qty ?? 1.0;

    // Clean the product name
    final searchText = _cleanProductName(lower);

    if (searchText.trim().isEmpty) return null;

    // Find best match
    final matches = _findMatches(searchText.trim(), products, useTamil);
    if (matches.isEmpty) return null;

    return VoiceBillingResult(
      product: matches.first.product,
      qty: qtyValue,
      spokenText: text,
      alternatives: matches.skip(1).take(4).map((m) => m.product).toList(),
    );
  }

  // ── Parse compound pattern like "2 கிலோ அரிசி" ──
  VoiceBillingResult? _parseCompoundPattern(
    String text,
    List<Product> products,
    bool useTamil,
  ) {
    if (!useTamil) return null;

    // Pattern: number + unit + product name
    // e.g., "2 கிலோ அரிசி", "அரை கிலோ பருப்பு", "ஒரு லிட்டர் பால்"
    final compoundPattern = RegExp(
      r'(\d+(?:\.\d+)?)\s*(' +
      _tamilUnits.join('|') +
      r')\s+(.+)',
    );
    var match = compoundPattern.firstMatch(text);
    if (match != null) {
      final qty = double.tryParse(match.group(1)!) ?? 1.0;
      final productName = match.group(3)!.trim();
      final matches = _findMatches(productName, products, true);
      if (matches.isNotEmpty) {
        return VoiceBillingResult(
          product: matches.first.product,
          qty: qty,
          spokenText: text,
          alternatives: matches.skip(1).take(4).map((m) => m.product).toList(),
        );
      }
    }

    // Pattern: Tamil number + unit + product name
    for (final entry in _tamilPhrases.entries) {
      if (text.contains(entry.key)) {
        final remaining = text.replaceAll(entry.key, '').trim();
        if (remaining.isNotEmpty) {
          final matches = _findMatches(remaining, products, true);
          if (matches.isNotEmpty) {
            return VoiceBillingResult(
              product: matches.first.product,
              qty: entry.value,
              spokenText: text,
              alternatives: matches.skip(1).take(4).map((m) => m.product).toList(),
            );
          }
        }
      }
    }

    // Pattern: Tamil number word + unit + product name
    for (final numEntry in _tamilNumbers.entries) {
      if (text.startsWith(numEntry.key) || text.contains(' ${numEntry.key} ')) {
        for (final unit in _tamilUnits) {
          if (text.contains(unit)) {
            final remaining = text
                .replaceAll(numEntry.key, '')
                .replaceAll(unit, '')
                .trim();
            if (remaining.isNotEmpty) {
              final matches = _findMatches(remaining, products, true);
              if (matches.isNotEmpty) {
                return VoiceBillingResult(
                  product: matches.first.product,
                  qty: numEntry.value,
                  spokenText: text,
                  alternatives: matches.skip(1).take(4).map((m) => m.product).toList(),
                );
              }
            }
          }
        }
      }
    }

    // Pattern: product name + number + unit
    // e.g., "அரிசி 2 கிலோ"
    final reversePattern = RegExp(
      r'(.+?)\s+(\d+(?:\.\d+)?)\s*(' +
      _tamilUnits.join('|') +
      r')',
    );
    match = reversePattern.firstMatch(text);
    if (match != null) {
      final productName = match.group(1)!.trim();
      final qty = double.tryParse(match.group(2)!) ?? 1.0;
      final matches = _findMatches(productName, products, true);
      if (matches.isNotEmpty) {
        return VoiceBillingResult(
          product: matches.first.product,
          qty: qty,
          spokenText: text,
          alternatives: matches.skip(1).take(4).map((m) => m.product).toList(),
        );
      }
    }

    return null;
  }

  // ── Extract quantity ──
  double? _extractQuantity(String text) {
    // Check Tamil phrases first (longer patterns first)
    final sortedPhrases = _tamilPhrases.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in sortedPhrases) {
      if (text.contains(entry.key)) return entry.value;
    }

    // Check Tamil number words
    for (final entry in _tamilNumbers.entries) {
      if (text.contains(entry.key)) return entry.value;
    }

    // English numbers
    final englishNumbers = {
      'one': 1.0, 'two': 2.0, 'three': 3.0, 'four': 4.0, 'five': 5.0,
      'six': 6.0, 'seven': 7.0, 'eight': 8.0, 'nine': 9.0, 'ten': 10.0,
      'twenty': 20.0, 'thirty': 30.0, 'forty': 40.0, 'fifty': 50.0,
      'hundred': 100.0, 'half': 0.5, 'quarter': 0.25, 'dozen': 12.0,
    };
    for (final entry in englishNumbers.entries) {
      if (text.contains(entry.key)) return entry.value;
    }

    // Digit numbers
    final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (numMatch != null) return double.tryParse(numMatch.group(1)!);

    return null;
  }

  // ── Clean product name ──
  String _cleanProductName(String text) {
    String result = text;

    // Remove English number words
    result = result.replaceAll(
      RegExp(
        r'\b(one|two|three|four|five|six|seven|eight|nine|ten|twenty|thirty|forty|fifty|hundred|half|quarter|dozen)\b',
      ),
      '',
    );

    // Remove Tamil number words (longer first)
    final sortedNumWords = [
      'அரை கிலோகிராம்', 'அரை கிலோ', 'ஒரு டஜன்', 'ஒரு டசன்',
      'பதினொன்று', 'பன்னிரண்டு', 'பதிமூன்று', 'பதிநான்கு',
      'பதினைந்து', 'பதினாறு', 'பதினேழு', 'பதினெட்டு', 'பத்தொன்பது',
      'இருபது', 'முப்பது', 'நாற்பது', 'ஐம்பது', 'அறுபது',
      'எழுபது', 'எண்பது', 'தொண்ணூறு', 'நூறு',
      'ஒன்று', 'ஒரு', 'இரண்டு', 'ரெண்டு', 'மூன்று', 'மூணு',
      'நான்கு', 'நாலு', 'ஐந்து', 'அஞ்சு', 'ஆறு', 'ஏழு',
      'எட்டு', 'ஒன்பது', 'பத்து', 'அரை', 'கால்', 'முக்கால்',
    ];
    for (final word in sortedNumWords) {
      result = result.replaceAll(word, '');
    }

    // Remove digit numbers
    result = result.replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), '');

    // Remove English unit words
    final englishUnits = [
      'kg', 'gms', 'grams', 'gram', 'kilo', 'kilogram',
      'packet', 'packets', 'pcs', 'piece', 'pieces',
      'box', 'boxes', 'dozen', 'ltr', 'litre', 'liter', 'litres',
      'ml', 'bottle', 'bottles', 'bag', 'bags',
      'roll', 'rolls', 'pad', 'pads', 'pack', 'packs',
      'bundle', 'unit', 'units', 'no', 'nos',
      'tin', 'tins', 'can', 'cans', 'sachet', 'sachets',
      'pouch', 'pouches', 'jar', 'jars', 'tube', 'tubes',
    ];
    for (final unitWord in englishUnits) {
      result = result.replaceAll(RegExp(r'\b$unitWord\b', caseSensitive: false), '');
    }

    // Remove Tamil unit words (sorted by length, longest first)
    final sortedUnits = List<String>.from(_tamilUnits)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final unit in sortedUnits) {
      result = result.replaceAll(unit, '');
    }

    // Remove price indicators
    result = result.replaceAll(
      RegExp(
        r'\b(rs|rupees|ra|ரூபாய்|ரூ|mrp|price|விலை)\b',
        caseSensitive: false,
      ),
      '',
    );

    // Clean up whitespace
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    return result;
  }

  // ── Strip price from product name ──
  String _stripPriceFromName(String name) {
    String result = name.toLowerCase();
    result = result.replaceAll(
      RegExp(r'\d+\s*(?:rs|ra|rupees|g|kg|ml|ltr|ltrs)\b'),
      '',
    );
    result = result.replaceAll(RegExp(r'\d+\s*rs\b'), '');
    result = result.replaceAll(RegExp(r'\d+\+?\d*\b'), '');
    result = result.replaceAll(RegExp(r'\b\d+\b'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }

  // ── Generate Tamil variations for fuzzy matching ──
  List<String> _getTamilVariations(String text) {
    final variations = <String>[text];

    // Common ending variations
    if (text.endsWith('ம்')) {
      variations.add(text.substring(0, text.length - 1));
    }
    if (text.endsWith('ய்')) {
      variations.add(text.substring(0, text.length - 1));
    }
    if (text.endsWith('ள்')) {
      variations.add(text.substring(0, text.length - 1));
    }
    if (text.endsWith('ன்')) {
      variations.add(text.substring(0, text.length - 1));
    }
    if (text.endsWith('ற்')) {
      variations.add(text.substring(0, text.length - 1));
    }

    // Common vowel variations
    variations.add(text.replaceAll('ா', ''));
    variations.add(text.replaceAll('ி', ''));
    variations.add(text.replaceAll('ு', ''));
    variations.add(text.replaceAll('ெ', ''));
    variations.add(text.replaceAll('ே', ''));
    variations.add(text.replaceAll('ை', ''));
    variations.add(text.replaceAll('ோ', ''));
    variations.add(text.replaceAll('ௌ', ''));

    // Double consonant variations
    variations.add(text.replaceAll('க்க', 'க'));
    variations.add(text.replaceAll('த்த', 'த'));
    variations.add(text.replaceAll('ப்ப', 'ப'));
    variations.add(text.replaceAll('ம்ம', 'ம'));
    variations.add(text.replaceAll('ன்ன', 'ன'));

    return variations.toSet().toList();
  }

  // ── Find best match ──
  List<_ScoredProduct> _findMatches(String query, List<Product> products, bool useTamil) {
    if (query.isEmpty) return [];

    final scored = <_ScoredProduct>[];

    for (final p in products) {
      final pNameLower = p.name.toLowerCase().trim();
      final pTamil = (p.tamilName ?? '').toLowerCase().trim();

      double bestScore = 0;

      // Score against English name
      final score1 = _calculateScore(query, pNameLower);
      final stripped = _stripPriceFromName(p.name);
      final score2 =
          stripped.isNotEmpty ? _calculateScore(query, stripped) : 0.0;
      bestScore = [score1, score2].reduce((a, b) => a > b ? a : b);

      // Score against Tamil name (with variations for fuzzy matching)
      if (pTamil.isNotEmpty) {
        final score3 = _calculateScore(query, pTamil);
        if (score3 > bestScore) bestScore = score3;

        // Try Tamil variations
        if (useTamil && score3 < 70) {
          final variations = _getTamilVariations(query);
          for (final variation in variations) {
            final varScore = _calculateScore(variation, pTamil);
            if (varScore > bestScore) bestScore = varScore;
          }

          // Also try variations of the product name
          final productVariations = _getTamilVariations(pTamil);
          for (final pVar in productVariations) {
            final varScore = _calculateScore(query, pVar);
            if (varScore > bestScore) bestScore = varScore;
          }
        }
      }

      // Bonus for partial matches (product name contains spoken word or vice versa)
      if (useTamil) {
        if (pNameLower.contains(query) || query.contains(pNameLower)) {
          bestScore = [bestScore, 65.0].reduce((a, b) => a > b ? a : b);
        }
        if (pTamil.isNotEmpty &&
            (pTamil.contains(query) || query.contains(pTamil))) {
          bestScore = [bestScore, 65.0].reduce((a, b) => a > b ? a : b);
        }
      }

      if (bestScore > 0) {
        scored.add(_ScoredProduct(p, bestScore));
      }
    }

    if (scored.isEmpty) return [];

    scored.sort((a, b) {
      if (b.score != a.score) return b.score.compareTo(a.score);
      return a.product.name.length.compareTo(b.product.name.length);
    });

    Logger.info('Voice matches for "$query":');
    for (int i = 0; i < scored.length && i < 5; i++) {
      Logger.info(
        '  ${i + 1}. ${scored[i].product.name} (score: ${scored[i].score.toStringAsFixed(1)})',
      );
    }

    return scored;
  }

  // ── Score matching ──
  double _calculateScore(String query, String target) {
    if (query.isEmpty || target.isEmpty) return 0;

    if (query == target) return 100;
    if (target.startsWith(query)) return 90;
    if (query.startsWith(target)) return 85;
    if (target.contains(query)) return 70;
    if (query.contains(target)) return 60;

    // Character-level similarity for Tamil (handles partial matches)
    if (query.length >= 3 && target.length >= 3) {
      final commonChars = _countCommonChars(query, target);
      final charScore = (commonChars / query.length) * 50;
      if (charScore > 30) return charScore;
    }

    // Word-level matching
    final queryWords =
        query.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final targetWords =
        target.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();

    if (queryWords.isEmpty || targetWords.isEmpty) return 0;

    int exactWordMatches = 0;
    int prefixMatches = 0;
    int containedMatches = 0;

    for (final qw in queryWords) {
      for (final tw in targetWords) {
        if (qw == tw) {
          exactWordMatches++;
          break;
        } else if (tw.startsWith(qw) || qw.startsWith(tw)) {
          prefixMatches++;
          break;
        } else if (tw.contains(qw) || qw.contains(tw)) {
          containedMatches++;
          break;
        }
      }
    }

    final totalQueryWords = queryWords.length;

    if (exactWordMatches == totalQueryWords) return 55;
    if (exactWordMatches + prefixMatches == totalQueryWords) return 50;

    final matchRatio =
        (exactWordMatches + prefixMatches + containedMatches) / totalQueryWords;
    if (matchRatio >= 0.8) return 45;
    if (matchRatio >= 0.6) return 35;
    if (matchRatio >= 0.4) return 25;
    if (matchRatio > 0) return 15;

    return 0;
  }

  // ── Count common characters ──
  int _countCommonChars(String a, String b) {
    int count = 0;
    final bChars = b.split('');
    for (final char in a.split('')) {
      if (bChars.remove(char)) count++;
    }
    return count;
  }

  void dispose() {
    _speech.cancel();
  }
}
