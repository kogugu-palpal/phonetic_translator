/// Basic rule-based phonetic transliteration between English and Thai.
///
/// These are simplified, deterministic approximations (not a full
/// linguistic transliteration engine). They exist to give users a
/// starting suggestion, which can then be corrected and saved to the
/// shared Firestore database by the community.
library phonetic_rules;

/// Converts an English name/word into an approximate Thai spelling.
///
/// Example: "john" -> "จอน", "mary" -> "แมรี"
String englishToThai(String input) {
  final String text = input.trim().toLowerCase();
  if (text.isEmpty) return '';

  // Longest-match-first table. Multi-letter clusters are listed so they
  // are matched before their single-letter components.
  final Map<String, String> rules = <String, String>{
    // Common English name endings / clusters
    'tion': 'ชั่น',
    'sion': 'ชั่น',
    'tch': 'ช',
    'dge': 'จ',
    'igh': 'ไอ',
    'ough': 'อู',
    'ck': 'ก',
    'ph': 'ฟ',
    'th': 'ธ',
    'sh': 'ช',
    'ch': 'ช',
    'ng': 'ง',
    'ny': 'ญ',
    'wh': 'ว',
    'qu': 'คว',
    // Vowel digraphs (checked before single vowels)
    'ee': 'อี',
    'ea': 'อี',
    'ay': 'เอ',
    'ai': 'ไอ',
    'oo': 'อู',
    'ou': 'เอา',
    'ow': 'โอ',
    'oy': 'ออย',
    'ie': 'ไอ',
    'ue': 'อู',
    'ey': 'เอ',
    // Single consonants
    'b': 'บ',
    'c': 'ค',
    'd': 'ด',
    'f': 'ฟ',
    'g': 'ก',
    'h': 'ฮ',
    'j': 'จ',
    'k': 'ค',
    'l': 'ล',
    'm': 'ม',
    'n': 'น',
    'p': 'พ',
    'q': 'ค',
    'r': 'ร',
    's': 'ส',
    't': 'ท',
    'v': 'ว',
    'w': 'ว',
    'x': 'ซ',
    'y': 'ย',
    'z': 'ซ',
    // Single vowels
    'a': 'อา',
    'e': 'เอ',
    'i': 'อิ',
    'o': 'โอ',
    'u': 'อุ',
  };

  final int maxRuleLen = rules.keys
      .map((String k) => k.length)
      .fold(0, (int a, int b) => a > b ? a : b);

  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < text.length) {
    final String ch = text[i];

    // Pass through spaces, hyphens, apostrophes and digits untouched.
    if (ch == ' ' || ch == '-' || ch == "'" || RegExp(r'[0-9]').hasMatch(ch)) {
      out.write(ch);
      i++;
      continue;
    }

    if (!RegExp(r'[a-z]').hasMatch(ch)) {
      // Unrecognized character (e.g. already Thai/other script): skip.
      i++;
      continue;
    }

    bool matched = false;
    final int remaining = text.length - i;
    final int upperBound = remaining < maxRuleLen ? remaining : maxRuleLen;
    for (int len = upperBound; len >= 1; len--) {
      final String chunk = text.substring(i, i + len);
      final String? mapped = rules[chunk];
      if (mapped != null) {
        out.write(mapped);
        i += len;
        matched = true;
        break;
      }
    }

    if (!matched) {
      // Fallback: keep the raw character rather than dropping it.
      out.write(ch);
      i++;
    }
  }

  return out.toString();
}

/// Converts a Thai name/word into an approximate romanized English
/// spelling, loosely following the Royal Thai General System (RTGS).
///
/// Example: "จอห์น" -> "chn" (approximate), "มารี" -> "mari"
String thaiToEnglish(String input) {
  final String text = input.trim();
  if (text.isEmpty) return '';

  // Leading ("front") vowels: written before the consonant, pronounced
  // after it. We buffer these and flush them once the consonant is seen.
  const Map<String, String> leadingVowels = <String, String>{
    'เ': 'e',
    'แ': 'ae',
    'โ': 'o',
    'ไ': 'ai',
    'ใ': 'ai',
  };

  // Consonants (initial sound, simplified RTGS-style mapping).
  const Map<String, String> consonants = <String, String>{
    'ก': 'k',
    'ข': 'kh',
    'ฃ': 'kh',
    'ค': 'kh',
    'ฅ': 'kh',
    'ฆ': 'kh',
    'ง': 'ng',
    'จ': 'ch',
    'ฉ': 'ch',
    'ช': 'ch',
    'ซ': 's',
    'ฌ': 'ch',
    'ญ': 'y',
    'ฎ': 'd',
    'ฏ': 't',
    'ฐ': 'th',
    'ฑ': 'th',
    'ฒ': 'th',
    'ณ': 'n',
    'ด': 'd',
    'ต': 't',
    'ถ': 'th',
    'ท': 'th',
    'ธ': 'th',
    'น': 'n',
    'บ': 'b',
    'ป': 'p',
    'ผ': 'ph',
    'ฝ': 'f',
    'พ': 'ph',
    'ฟ': 'f',
    'ภ': 'ph',
    'ม': 'm',
    'ย': 'y',
    'ร': 'r',
    'ฤ': 'rue',
    'ล': 'l',
    'ฦ': 'lue',
    'ว': 'w',
    'ศ': 's',
    'ษ': 's',
    'ส': 's',
    'ห': 'h',
    'ฬ': 'l',
    'อ': '', // vowel carrier, silent as an initial consonant
    'ฮ': 'h',
  };

  // Vowel signs that attach directly above/below/after the consonant.
  const Map<String, String> trailingVowels = <String, String>{
    'ะ': 'a',
    'ั': 'a',
    'า': 'a',
    'ำ': 'am',
    'ิ': 'i',
    'ี': 'i',
    'ึ': 'ue',
    'ื': 'ue',
    'ุ': 'u',
    'ู': 'u',
    'ๅ': 'a',
    'ฯ': '',
  };

  // Tone marks and other diacritics: silent in a basic romanization.
  const Set<String> silentMarks = <String>{
    '่', '้', '๊', '๋', '์', '๎', 'ํ',
  };

  final StringBuffer out = StringBuffer();
  String pendingLeadingVowel = '';

  for (int i = 0; i < text.length; i++) {
    final String ch = text[i];

    if (ch == ' ' || ch == '-') {
      out.write(ch);
      continue;
    }

    if (leadingVowels.containsKey(ch)) {
      pendingLeadingVowel += leadingVowels[ch]!;
      continue;
    }

    if (consonants.containsKey(ch)) {
      out.write(consonants[ch]);
      if (pendingLeadingVowel.isNotEmpty) {
        out.write(pendingLeadingVowel);
        pendingLeadingVowel = '';
      }
      continue;
    }

    if (trailingVowels.containsKey(ch)) {
      out.write(trailingVowels[ch]);
      continue;
    }

    if (silentMarks.contains(ch)) {
      continue;
    }

    // Non-Thai / unrecognized character: keep as-is (e.g. Latin letters,
    // digits, punctuation already present in the input).
    out.write(ch);
  }

  // Any leading vowel that never found a following consonant (rare, but
  // possible with unusual input) is appended at the end so nothing is lost.
  if (pendingLeadingVowel.isNotEmpty) {
    out.write(pendingLeadingVowel);
  }

  return out.toString();
}
