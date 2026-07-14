// Basic rule-based phonetic transliteration between English and Thai.
//
// These are simplified, deterministic approximations (not a full
// linguistic transliteration engine). They exist to give users a
// starting suggestion, which can then be corrected and saved to the
// shared Firestore database by the community.

/// Converts an English name/word into an approximate Thai spelling.
///
/// This version is syllable-aware for vowels, which matters in Thai:
/// - A vowel that attaches to a consonant does NOT get its own carrier.
///   e.g. "ga" -> "กา" (consonant ก + vowel sign า), NOT "กอา".
///   The carrier อ is only used when a vowel has no consonant to attach
///   to (start of a word/syllable, e.g. "a" alone -> "อา").
/// - Some Thai vowels are written BEFORE their consonant even though the
///   English spelling has the consonant first (e.g. "jo" -> "โจ", not
///   "จโอ"). This function reorders those automatically.
///
/// Examples: "ga" -> "กา" (not "กอา"), "jo" -> "โจ", "mary" -> "มารย"
/// These are still approximations — spelling alone can't capture silent
/// letters or irregular English pronunciation (e.g. the silent "h" in
/// "John", or the "air" sound of "a" in "Mary").
String englishToThai(String input) {
  final String text = input.trim().toLowerCase();
  if (text.isEmpty) return '';

  // Consonants and pre-formed clusters: matched greedily (longest first),
  // then written to the output as-is.
  const Map<String, String> consonants = <String, String>{
    'tch': 'ช',
    'dge': 'จ',
    'ck': 'ก',
    'ph': 'ฟ',
    'th': 'ธ',
    'sh': 'ช',
    'ch': 'ช',
    'ng': 'ง',
    'ny': 'ญ',
    'wh': 'ว',
    'qu': 'คว',
    'kh': 'ค',
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
  };

  // Vowels that attach directly AFTER a consonant (no carrier needed).
  // "bare" = form used right after a consonant; "standalone" = form used
  // when there's no consonant to attach to, so it needs an อ carrier.
  const Map<String, List<String>> trailingVowels = <String, List<String>>{
    // key: [bare, standalone]
    'ee': ['ี', 'อี'],
    'ea': ['ี', 'อี'],
    'ey': ['ี', 'อี'],
    'oo': ['ู', 'อู'],
    'ough': ['ู', 'อู'],
    'ou': ['าว', 'อาว'],
    'oy': ['อย', 'ออย'],
    'ue': ['ือ', 'อือ'],
    'a': ['า', 'อา'],
    'i': ['ิ', 'อิ'],
    'u': ['ุ', 'อุ'],
  };

  // Vowels that must be written BEFORE the consonant they attach to (Thai
  // "leading vowels"). "leading" = glyph placed before the consonant;
  // "standalone" = form used with no consonant (word starts with the
  // vowel sound, or it's at the end with nothing to attach to).
  const Map<String, List<String>> leadingVowels = <String, List<String>>{
    // key: [leading, standalone]
    'igh': ['ไ', 'ไอ'],
    'ai': ['ไ', 'ไอ'],
    'ay': ['ไ', 'ไอ'],
    'ie': ['ไ', 'ไอ'],
    // "Magic/silent e" endings: a lone vowel + trailing "e" at the end of
    // a word usually makes the vowel say its own name and the "e" itself
    // stays silent (e.g. "Moe", "Joe", "Doe", "Rae"). Matched as a single
    // 2-letter unit so it isn't read as two separate vowel sounds.
    'oe': ['โ', 'โอ'],
    'ae': ['ไ', 'ไอ'],
    'ow': ['โ', 'โอ'],
    'e': ['เ', 'เอ'],
    'o': ['โ', 'โอ'],
  };

  // Pre-formed syllables that already include their own vowel — written
  // as-is, no carrier/reorder logic needed.
  const Map<String, String> complete = <String, String>{
    'tion': 'ชั่น',
    'sion': 'ชั่น',
  };

  // --- Pass 1: tokenize into consonant / trailing-vowel / leading-vowel /
  // complete / literal units, longest match first. ---
  final List<MapEntry<String, String>> tokens = <MapEntry<String, String>>[];
  final Set<String> allKeys = <String>{
    ...complete.keys,
    ...consonants.keys,
    ...trailingVowels.keys,
    ...leadingVowels.keys,
  };
  final int maxLen = allKeys.map((k) => k.length).fold(0, (a, b) => a > b ? a : b);

  int i = 0;
  while (i < text.length) {
    final String ch = text[i];

    if (ch == ' ' || ch == '-' || ch == "'" || RegExp(r'[0-9]').hasMatch(ch)) {
      tokens.add(MapEntry('literal', ch));
      i++;
      continue;
    }
    if (!RegExp(r'[a-z]').hasMatch(ch)) {
      i++; // Unrecognized character (e.g. already non-Latin): skip.
      continue;
    }

    bool matched = false;
    final int remaining = text.length - i;
    final int upperBound = remaining < maxLen ? remaining : maxLen;
    for (int len = upperBound; len >= 1; len--) {
      final String chunk = text.substring(i, i + len);
      if (complete.containsKey(chunk)) {
        tokens.add(MapEntry('complete', chunk));
        i += len;
        matched = true;
        break;
      }
      if (leadingVowels.containsKey(chunk)) {
        tokens.add(MapEntry('leadingVowel', chunk));
        i += len;
        matched = true;
        break;
      }
      if (trailingVowels.containsKey(chunk)) {
        tokens.add(MapEntry('trailingVowel', chunk));
        i += len;
        matched = true;
        break;
      }
      if (consonants.containsKey(chunk)) {
        tokens.add(MapEntry('consonant', chunk));
        i += len;
        matched = true;
        break;
      }
    }

    if (!matched) {
      tokens.add(MapEntry('literal', ch));
      i++;
    }
  }

  // --- Pass 2: assemble Thai text, attaching vowels to the correct side
  // of their consonant and skipping the redundant carrier when possible. ---
  final StringBuffer out = StringBuffer();
  int idx = 0;
  while (idx < tokens.length) {
    final MapEntry<String, String> tok = tokens[idx];

    switch (tok.key) {
      case 'literal':
        out.write(tok.value);
        idx++;
        break;

      case 'complete':
        out.write(complete[tok.value]);
        idx++;
        break;

      case 'consonant':
        final String consonantGlyph = consonants[tok.value]!;
        final bool hasNext = idx + 1 < tokens.length;
        final MapEntry<String, String>? next = hasNext ? tokens[idx + 1] : null;

        if (next != null && next.key == 'leadingVowel') {
          // e.g. "t" + "e" -> "เ" + "ท" (leading vowel goes first)
          out.write(leadingVowels[next.value]![0]);
          out.write(consonantGlyph);
          idx += 2;
        } else if (next != null && next.key == 'trailingVowel') {
          // e.g. "g" + "a" -> "ก" + "า" (bare form, no extra อ carrier)
          out.write(consonantGlyph);
          out.write(trailingVowels[next.value]![0]);
          idx += 2;
        } else {
          out.write(consonantGlyph);
          idx++;
        }
        break;

      case 'trailingVowel':
        // Reached only when there's no preceding consonant to attach to
        // (start of word/syllable) -> needs its own carrier.
        out.write(trailingVowels[tok.value]![1]);
        idx++;
        break;

      case 'leadingVowel':
        // Same idea: nothing to attach before, so use the standalone form.
        out.write(leadingVowels[tok.value]![1]);
        idx++;
        break;
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
