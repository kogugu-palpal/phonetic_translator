import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'phonetic_rules.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBOBiE-RtQuzzW4Doi_NZKc_f1dSa83haU",
      authDomain: "phonetic-translator-32c9e.firebaseapp.com",
      projectId: "phonetic-translator-32c9e",
      storageBucket: "phonetic-translator-32c9e.firebasestorage.app",
      messagingSenderId: "69781164580",
      appId: "1:69781164580:web:a7908c75d41f798002beb1",
    ),
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phonetic Translator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TranslationScreen(),
    );
  }
}

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String _selectedLanguage = 'thai';
  List<TranslationSuggestion> _suggestions = [];
  bool _showSuggestions = false;
  bool _isLoading = false;
  String _selectedTranslation = '';

  // Direction toggle: false = English -> other language, true = Thai -> English
  bool _thaiToEnglish = false;
  // Last rule-based guess computed, used to prefill the "suggest" dialog.
  String? _lastRuleGuess;

  // The name/word actually used for lookups, normalized per direction.
  // Thai text has no case, so we only lowercase for English input.
  String get _currentSourceText =>
      _thaiToEnglish ? _nameController.text.trim() : _nameController.text.trim().toLowerCase();

  // The Firestore 'targetLanguage' value for the current direction.
  String get _effectiveTargetLanguage => _thaiToEnglish ? 'english' : _selectedLanguage;
  
  // Admin state
  bool _isAdmin = false;
  String _adminName = '';
  
  // Admin credentials (stored in code for now, can move to Firebase later)
  final String _adminPassword = 'phonetic2024';
  
  final Map<String, String> _languages = {
    'thai': 'Thai (ไทย)',
    'chinese': 'Chinese (中文)',
    'japanese': 'Japanese (日本語)',
  };
  
  // Admin login dialog
  void _showAdminLogin() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Text('👹', style: TextStyle(fontSize: 24)),
              SizedBox(width: 8),
              Text('Admin Login'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Admin Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                String name = nameController.text.trim();
                String password = passwordController.text;
                
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please enter your name'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                if (password == _adminPassword) {
                  setState(() {
                    _isAdmin = true;
                    _adminName = name;
                  });
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Welcome, Admin $name! 👹'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Wrong password!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: Text('Login'),
            ),
          ],
        );
      },
    );
  }
  
  // Admin logout
  void _adminLogout() {
    setState(() {
      _isAdmin = false;
      _adminName = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged out'),
        backgroundColor: Colors.grey,
      ),
    );
  }
  
  // Delete translation (admin only)
  Future<void> _deleteTranslation(TranslationSuggestion suggestion) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Delete Translation?'),
          content: Text('Are you sure you want to delete "${suggestion.text}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
    
    if (confirm == true) {
      try {
        await _firestore.collection('translations').doc(suggestion.id).delete();
        
        setState(() {
          _suggestions.removeWhere((s) => s.id == suggestion.id);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Translation deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
  
  // Edit translation (admin only)
  void _editTranslation(TranslationSuggestion suggestion) {
    final TextEditingController editController = TextEditingController(text: suggestion.text);
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Edit Translation'),
          content: TextField(
            controller: editController,
            decoration: InputDecoration(
              labelText: 'Translation',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                String newText = editController.text.trim();
                if (newText.isNotEmpty && newText != suggestion.text) {
                  try {
                    await _firestore.collection('translations').doc(suggestion.id).update({
                      'translation': newText,
                    });
                    
                    setState(() {
                      int index = _suggestions.indexWhere((s) => s.id == suggestion.id);
                      if (index != -1) {
                        _suggestions[index] = TranslationSuggestion(
                          id: suggestion.id,
                          text: newText,
                          votes: suggestion.votes,
                          isUserSubmitted: suggestion.isUserSubmitted,
                        );
                      }
                    });
                    
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Translation updated'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }
  
  // Search function
  Future<void> _searchTranslations() async {
    String query = _searchController.text.trim().toLowerCase();
    
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a search term'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('translations')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(50)
          .get();
      
      List<TranslationSuggestion> results = [];
      
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        results.add(TranslationSuggestion(
          id: doc.id,
          text: '${data['name']} → ${data['translation']} (${data['targetLanguage']})',
          votes: data['votes'] ?? 0,
          isUserSubmitted: data['isUserSubmitted'] ?? false,
        ));
      }
      
      setState(() {
        _suggestions = results;
        _showSuggestions = true;
        _isLoading = false;
      });
      
      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No results found for "$query"'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Load translations from Firebase, combined with a basic phonetic-rule
  // suggestion (English <-> Thai) so users always have a starting point
  // even if nobody has added that name to the database yet.
  Future<void> _translateName() async {
    String name = _currentSourceText;
    
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_thaiToEnglish ? 'Please enter a Thai name to translate' : 'Please enter a name to translate'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
      _showSuggestions = false;
      _lastRuleGuess = null;
    });
    
    final String targetLanguage = _effectiveTargetLanguage;
    
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('translations')
          .where('name', isEqualTo: name)
          .where('targetLanguage', isEqualTo: targetLanguage)
          .orderBy('votes', descending: true)
          .get();
      
      List<TranslationSuggestion> loadedSuggestions = [];
      
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        loadedSuggestions.add(TranslationSuggestion(
          id: doc.id,
          text: data['translation'] ?? '',
          votes: data['votes'] ?? 0,
          isUserSubmitted: data['isUserSubmitted'] ?? false,
        ));
      }
      
      // Combine with a basic phonetic-rule guess (English <-> Thai only).
      String? ruleGuess;
      if (_thaiToEnglish) {
        ruleGuess = thaiToEnglish(name);
      } else if (targetLanguage == 'thai') {
        ruleGuess = englishToThai(name);
      }
      
      if (ruleGuess != null && ruleGuess.trim().isNotEmpty) {
        _lastRuleGuess = ruleGuess;
        final bool alreadyInDatabase = loadedSuggestions.any(
          (s) => s.text.trim().toLowerCase() == ruleGuess!.trim().toLowerCase(),
        );
        if (!alreadyInDatabase) {
          loadedSuggestions.insert(
            0,
            TranslationSuggestion(
              id: 'phonetic_rule',
              text: ruleGuess,
              votes: 0,
              isUserSubmitted: false,
              isRuleBased: true,
            ),
          );
        }
      }
      
      setState(() {
        _suggestions = loadedSuggestions;
        _showSuggestions = true;
        _isLoading = false;
        _selectedTranslation = '';
      });
      
      if (loadedSuggestions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Name "$name" not found. Please suggest a translation!'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext dialogCtx) {
            return AlertDialog(
              title: const Text('Error'),
              content: Text('$e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      }
    }
  }
  
  // Splits text on whitespace into individual words, dropping empties.
  List<String> _splitIntoWords(String text) =>
      text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  // Saves a name -> translation pair to Firestore. If the source and the
  // translation both split into the same number of whitespace-separated
  // words (e.g. "John Smith" / "จอห์น สมิธ"), each word pair is *also*
  // saved as its own dictionary entry, so multi-word names grow the
  // word-by-word database automatically. If the word counts don't line
  // up, only the full phrase is saved (safer than guessing an alignment).
  Future<_SavePairResult> _saveTranslationPair({
    required String sourceText,
    required String translationText,
    required String targetLanguage,
    bool isRuleGenerated = false,
  }) async {
    final String name = targetLanguage == 'english'
        ? sourceText.trim()
        : sourceText.trim().toLowerCase();
    final String translation = translationText.trim();

    Map<String, dynamic> buildData(String n, String t) => {
          'name': n,
          'translation': t,
          'targetLanguage': targetLanguage,
          'votes': 0,
          'isUserSubmitted': true,
          if (isRuleGenerated) 'isRuleGenerated': true,
          'timestamp': FieldValue.serverTimestamp(),
        };

    final WriteBatch batch = _firestore.batch();
    final DocumentReference fullRef = _firestore.collection('translations').doc();
    batch.set(fullRef, buildData(name, translation));
    int entryCount = 1;

    final List<String> sourceWords = _splitIntoWords(name);
    final List<String> translationWords = _splitIntoWords(translation);

    if (sourceWords.length > 1 && sourceWords.length == translationWords.length) {
      for (int i = 0; i < sourceWords.length; i++) {
        final DocumentReference wordRef = _firestore.collection('translations').doc();
        batch.set(wordRef, buildData(sourceWords[i], translationWords[i]));
        entryCount++;
      }
    }

    await batch.commit();
    return _SavePairResult(fullEntryId: fullRef.id, entryCount: entryCount);
  }
  
  // Persist a phonetic-rule-generated suggestion into the shared database,
  // so it becomes a normal, votable, community entry from now on. Also
  // splits multi-word names into individual word entries (see above).
  Future<void> _saveRuleSuggestionToDatabase(TranslationSuggestion suggestion) async {
    try {
      final _SavePairResult result = await _saveTranslationPair(
        sourceText: _currentSourceText,
        translationText: suggestion.text,
        targetLanguage: _effectiveTargetLanguage,
        isRuleGenerated: true,
      );
      
      setState(() {
        int index = _suggestions.indexWhere((s) => s.id == 'phonetic_rule' && s.text == suggestion.text);
        if (index != -1) {
          _suggestions[index] = TranslationSuggestion(
            id: result.fullEntryId,
            text: suggestion.text,
            votes: 0,
            isUserSubmitted: true,
            isRuleBased: false,
          );
        }
      });
      
      if (mounted) {
        final int wordCount = result.entryCount - 1;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wordCount > 0
                ? 'Saved to the shared database (+ $wordCount word${wordCount == 1 ? '' : 's'} added individually)!'
                : 'Saved to the shared database!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _selectSuggestion(TranslationSuggestion suggestion) async {
    setState(() {
      _selectedTranslation = suggestion.text;
    });
    
    // Rule-based suggestions aren't saved in Firestore yet, so there's
    // no document to vote on. Users can tap "Save" to add it first.
    if (suggestion.isRuleBased) {
      return;
    }
    
    try {
      await _firestore.collection('translations').doc(suggestion.id).update({
        'votes': FieldValue.increment(1),
      });
      
      setState(() {
        int index = _suggestions.indexWhere((s) => s.id == suggestion.id);
        if (index != -1) {
          _suggestions[index] = TranslationSuggestion(
            id: suggestion.id,
            text: suggestion.text,
            votes: suggestion.votes + 1,
            isUserSubmitted: suggestion.isUserSubmitted,
          );
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voted for: ${suggestion.text}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error voting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Copies text to the clipboard — wired to its own dedicated button,
  // separate from voting/selecting, so it never interferes with them.
  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied "$text" to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  void _showAddTranslationDialog() {
    final TextEditingController suggestionController =
        TextEditingController(text: _lastRuleGuess ?? '');
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Suggest Translation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_thaiToEnglish ? 'Thai' : 'English'}: ${_nameController.text.trim()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Target: ${_thaiToEnglish ? 'English' : _languages[_selectedLanguage]}'),
              const SizedBox(height: 16),
              TextField(
                controller: suggestionController,
                decoration: InputDecoration(
                  labelText: 'Your translation',
                  hintText: 'Enter phonetic translation',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Tip: for multi-word names (e.g. "John Smith"), matching words on both sides are also saved individually.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                String suggestion = suggestionController.text.trim();
                if (suggestion.isNotEmpty) {
                  Navigator.of(dialogContext).pop();
                  
                  try {
                    final _SavePairResult result = await _saveTranslationPair(
                      sourceText: _currentSourceText,
                      translationText: suggestion,
                      targetLanguage: _effectiveTargetLanguage,
                    );
                    
                    setState(() {
                      _suggestions.add(TranslationSuggestion(
                        id: result.fullEntryId,
                        text: suggestion,
                        votes: 0,
                        isUserSubmitted: true,
                      ));
                      _selectedTranslation = suggestion;
                    });
                    
                    if (mounted) {
                      final int wordCount = result.entryCount - 1;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(wordCount > 0
                              ? 'Thank you! Saved, plus $wordCount word${wordCount == 1 ? '' : 's'} added individually to the dictionary.'
                              : 'Thank you! Your suggestion has been saved.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error saving suggestion: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }
  
  void _clearAll() {
    setState(() {
      _nameController.clear();
      _searchController.clear();
      _suggestions = [];
      _showSuggestions = false;
      _selectedTranslation = '';
      _lastRuleGuess = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Phonetic Translator'),
            Row(
              children: [
                Text(
                  'v002.26.07.13',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                SizedBox(width: 16),
                if (_isAdmin)
                  Row(
                    children: [
                      Text(
                        _adminName,
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                      SizedBox(width: 8),
                      InkWell(
                        onTap: _adminLogout,
                        child: Text('👹', style: TextStyle(fontSize: 20)),
                      ),
                    ],
                  )
                else
                  InkWell(
                    onTap: _showAdminLogin,
                    child: Text('👹', style: TextStyle(fontSize: 20)),
                  ),
              ],
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Name Transliteration',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _thaiToEnglish ? 'Thai → English (Beta)' : 'English → Other Languages (Beta)',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            // Direction toggle
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!_thaiToEnglish) return;
                        setState(() {
                          _thaiToEnglish = false;
                          _showSuggestions = false;
                          _suggestions = [];
                          _selectedTranslation = '';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_thaiToEnglish ? Colors.blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'English → Other',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: !_thaiToEnglish ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_thaiToEnglish) return;
                        setState(() {
                          _thaiToEnglish = true;
                          _showSuggestions = false;
                          _suggestions = [];
                          _selectedTranslation = '';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _thaiToEnglish ? Colors.blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          'Thai → English',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _thaiToEnglish ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: _thaiToEnglish ? 'Enter Thai name' : 'Enter English name',
                hintText: _thaiToEnglish ? 'e.g. จอห์น, มารี, เดวิด' : 'e.g., John, Mary, David',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.person),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              style: const TextStyle(fontSize: 18),
              onSubmitted: (_) => _translateName(),
            ),
            const SizedBox(height: 24),
            
            if (_thaiToEnglish)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[50],
                ),
                child: Row(
                  children: const [
                    Icon(Icons.language, color: Colors.blue),
                    SizedBox(width: 12),
                    Text('Target: English', style: TextStyle(fontSize: 16)),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[50],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language, color: Colors.blue),
                    const SizedBox(width: 12),
                    const Text('Target:', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLanguage,
                          isExpanded: true,
                          items: _languages.entries.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedLanguage = newValue;
                                _showSuggestions = false;
                                _suggestions = [];
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 32),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _translateName,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.translate),
                    label: Text(
                      _isLoading ? 'Loading...' : 'Translate',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            
            if (_showSuggestions) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Suggestions:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _showAddTranslationDialog,
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          label: const Text('Add New'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    if (_suggestions.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No suggestions yet. Be the first to add one!',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ...(_suggestions.map((suggestion) {
                        bool isSelected = _selectedTranslation == suggestion.text;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue[100] : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: suggestion.isRuleBased
                                  ? Colors.purple[200]!
                                  : (isSelected ? Colors.blue : Colors.grey[300]!),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              suggestion.text,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.blue[900] : Colors.black,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Icon(
                                  Icons.thumb_up,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text('${suggestion.votes} votes'),
                                if (suggestion.isRuleBased) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Phonetic Rule',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.purple,
                                      ),
                                    ),
                                  ),
                                ] else if (suggestion.isUserSubmitted) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Community',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: suggestion.isRuleBased
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.copy, color: Colors.grey[600], size: 20),
                                        tooltip: 'Copy to clipboard',
                                        onPressed: () => _copyToClipboard(suggestion.text),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.bookmark_add, color: Colors.purple),
                                        tooltip: 'Save to database',
                                        onPressed: () => _saveRuleSuggestionToDatabase(suggestion),
                                      ),
                                    ],
                                  )
                                : (_isAdmin
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.copy, color: Colors.grey[600], size: 20),
                                            tooltip: 'Copy to clipboard',
                                            onPressed: () => _copyToClipboard(suggestion.text),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.edit, color: Colors.orange),
                                            onPressed: () => _editTranslation(suggestion),
                                            tooltip: 'Edit',
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete, color: Colors.red),
                                            onPressed: () => _deleteTranslation(suggestion),
                                            tooltip: 'Delete',
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isSelected)
                                            const Padding(
                                              padding: EdgeInsets.only(right: 4),
                                              child: Icon(Icons.check_circle, color: Colors.blue),
                                            ),
                                          IconButton(
                                            icon: Icon(Icons.copy, color: Colors.grey[600], size: 20),
                                            tooltip: 'Copy to clipboard',
                                            onPressed: () => _copyToClipboard(suggestion.text),
                                          ),
                                        ],
                                      )),
                            onTap: () => _selectSuggestion(suggestion),
                          ),
                        );
                      }).toList()),
                  ],
                ),
              ),
            ],
            
            // Search bar moved to bottom
            const SizedBox(height: 40),
            Divider(),
            const SizedBox(height: 24),
            
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search, color: Colors.purple),
                      SizedBox(width: 8),
                      Text(
                        'Search Database',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple[900],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search existing translations...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onSubmitted: (_) => _searchTranslations(),
                        ),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _searchTranslations,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        child: Text('Search'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Footer
            const SizedBox(height: 60),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  Text(
                    'For reference in changing names or calling names',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'to sound nearly like the real voice pronunciation',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Powered by ',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        'GuGuThetKhaing',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}

class TranslationSuggestion {
  final String id;
  final String text;
  final int votes;
  final bool isUserSubmitted;
  final bool isRuleBased;
  
  TranslationSuggestion({
    required this.id,
    required this.text,
    required this.votes,
    required this.isUserSubmitted,
    this.isRuleBased = false,
  });
}

// Result of saving a (possibly multi-word) translation pair: the
// Firestore document id of the full-phrase entry, plus how many
// documents were written in total (1 if it wasn't split into words).
class _SavePairResult {
  final String fullEntryId;
  final int entryCount;

  _SavePairResult({required this.fullEntryId, required this.entryCount});
}