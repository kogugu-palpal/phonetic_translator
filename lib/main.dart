import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

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
                    
                    Navigator.of(dialogContext).pop();
                    
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
  
  // Load translations from Firebase
  Future<void> _translateName() async {
    String name = _nameController.text.trim().toLowerCase();
    
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name to translate'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
      _showSuggestions = false;
    });
    
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('translations')
          .where('name', isEqualTo: name)
          .where('targetLanguage', isEqualTo: _selectedLanguage)
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
  
  Future<void> _selectSuggestion(TranslationSuggestion suggestion) async {
    setState(() {
      _selectedTranslation = suggestion.text;
    });
    
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
  
  void _showAddTranslationDialog() {
    final TextEditingController suggestionController = TextEditingController();
    
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
                'English: ${_nameController.text.trim()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Target: ${_languages[_selectedLanguage]}'),
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
                    DocumentReference docRef = await _firestore.collection('translations').add({
                      'name': _nameController.text.trim().toLowerCase(),
                      'translation': suggestion,
                      'targetLanguage': _selectedLanguage,
                      'votes': 0,
                      'isUserSubmitted': true,
                      'timestamp': FieldValue.serverTimestamp(),
                    });
                    
                    setState(() {
                      _suggestions.add(TranslationSuggestion(
                        id: docRef.id,
                        text: suggestion,
                        votes: 0,
                        isUserSubmitted: true,
                      ));
                      _selectedTranslation = suggestion;
                    });
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thank you! Your suggestion has been saved.'),
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
                  'v001.25.12.11',
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
            const Text(
              'English → Other Languages (Beta)',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Enter English name',
                hintText: 'e.g., John, Mary, David',
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
                              color: isSelected ? Colors.blue : Colors.grey[300]!,
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
                                if (suggestion.isUserSubmitted) ...[
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
                            trailing: _isAdmin
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
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
                                : (isSelected
                                    ? const Icon(Icons.check_circle, color: Colors.blue)
                                    : null),
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
  
  TranslationSuggestion({
    required this.id,
    required this.text,
    required this.votes,
    required this.isUserSubmitted,
  });
}