import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configured = _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty;
  if (configured) {
    await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  }
  runApp(const HandMeDownApp());
}

class HandMeDownApp extends StatelessWidget {
  const HandMeDownApp({super.key});

  @override
  Widget build(BuildContext context) {
    final configured = _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty;
    // Choose between the textbooks setup guidance when the app starts.
    return MaterialApp(
      title: 'Hand Me Down',
      home: configured
          ? const TextbookListPage()
          : const Scaffold(
              body: Center(
                child: Text(
                  'Configure SUPABASE_URL and SUPABASE_ANON_KEY to start.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}

// App home page: browsing, adding, and opening textbook listings.
class TextbookListPage extends StatefulWidget {
  const TextbookListPage({super.key});

  @override
  State<TextbookListPage> createState() => _TextbookListPageState();
}

class _TextbookListPageState extends State<TextbookListPage> {
  // FutureBuilder uses this request to show loading, error, and catalog states.
  late Future<List<Map<String, dynamic>>> _textbooks;
  final Set<String> _hiddenTextbookIds = {};

  @override
  void initState() {
    super.initState();
    _textbooks = _loadTextbooks();
  }

  Future<List<Map<String, dynamic>>> _loadTextbooks() async {
    final rows = await Supabase.instance.client
        .from('textbooks')
        .select('id, title, author, created_at')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  // Reloads the catalog after a user refreshes or adds a textbook.
  Future<void> _refresh() async {
    final request = _loadTextbooks();
    setState(() => _textbooks = request);
    try {
      await request;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh textbooks: $error')),
      );
    }
  }

  // Opens a detail dialog and fetches the selected listing's contact method.
  Future<void> _showDetails(Map<String, dynamic> textbook) async {
    final contactRequest = Supabase.instance.client
        .from('textbooks')
        .select('communication_method')
        .eq('id', textbook['id'])
        .maybeSingle();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(textbook['title'] as String),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Author: ${textbook['author']}'),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>?>(
              future: contactRequest,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text(
                    'Could not load contact method: ${snapshot.error}',
                  );
                }
                return Text(
                  'Preferred contact: '
                  '${snapshot.data?['communication_method'] ?? 'Not provided'}',
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Hide a listing locally for this session without deleting it from Supabase.
  void _temporarilyRemove(Map<String, dynamic> textbook) {
    final id = textbook['id'] as String;
    setState(() => _hiddenTextbookIds.add(id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Textbook hidden for this session'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => setState(() => _hiddenTextbookIds.remove(id)),
        ),
      ),
    );
  }

  void _restoreHiddenTextbooks() {
    setState(() => _hiddenTextbookIds.clear());
  }

  // Shows the add-listing form, validates it, then inserts the textbook.
  Future<void> _addTextbook() async {
    final formKey = GlobalKey<FormState>();
    final textbook = <String, String>{};
    final values = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lend a textbook'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _requiredField(
                label: 'Textbook title',
                error: 'Enter a title',
                onSaved: (value) => textbook['title'] = value,
              ),
              _requiredField(
                label: 'Author',
                error: 'Enter an author',
                onSaved: (value) => textbook['author'] = value,
              ),
              _requiredField(
                label: 'Preferred communication method',
                error: 'Enter a contact method',
                onSaved: (value) => textbook['communication_method'] = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              formKey.currentState!.save();
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (values != true || !mounted) return;

    try {
      await Supabase.instance.client.from('textbooks').insert({
        ...textbook,
        // Keep compatibility with the original schema's required condition.
        'condition': 'Good',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Textbook added')));
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add textbook: $error')));
    }
  }

  // Required text input used in the add form.
  Widget _requiredField({
    required String label,
    required String error,
    required ValueChanged<String> onSaved,
  }) {
    return TextFormField(
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          value == null || value.trim().isEmpty ? error : null,
      onSaved: (value) => onSaved(value!.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold provides the app's bar, the catalog body, and the buton for adding textbooks.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Textbooks'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _textbooks,
        builder: (context, snapshot) {
          // Error handling
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: _refresh,
                child: Text(
                  'Could not load textbooks. Retry: ${snapshot.error}',
                ),
              ),
            );
          }
          final textbooks = snapshot.data!
              .where(
                (textbook) =>
                    !_hiddenTextbookIds.contains(textbook['id'] as String),
              )
              .toList();
          if (textbooks.isEmpty) {
            return Center(
              child: _hiddenTextbookIds.isEmpty
                  ? const Text('No textbooks listed yet.')
                  : TextButton(
                      onPressed: _restoreHiddenTextbooks,
                      child: const Text('Show hidden textbooks'),
                    ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView.builder(
                itemCount: textbooks.length,
                itemBuilder: (context, index) {
                  final textbook = textbooks[index];
                  final listedAt = DateTime.tryParse(
                    textbook['created_at'] as String? ?? '',
                  );
                  return Container(
                    height: 136,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showDetails(textbook),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    textbook['title'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${textbook['author']} · '
                                    '${listedAt == null ? 'Textbook listing' : listedAt.toLocal().toString().split(' ').first}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(right: 8),
                                        child: Icon(
                                          Icons.bookmark_border_rounded,
                                          size: 16,
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.only(right: 8),
                                        child: Icon(Icons.share, size: 16),
                                      ),
                                      IconButton(
                                        tooltip: 'Temporarily remove',
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        onPressed: () =>
                                            _temporarilyRemove(textbook),
                                        icon: const Icon(Icons.close, size: 16),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Leftover from news widget, can delete or add image later.
                            // Container(
                            //   width: 100,
                            //   height: 100,
                            //   decoration: BoxDecoration(
                            //     color: Colors.grey,
                            //     borderRadius: BorderRadius.circular(8),
                            //     image: DecorationImage(
                            //       fit: BoxFit.cover,
                            //       image: NetworkImage(
                            //         textbook['image_url'] as String,
                            //       ),
                            //     ),
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTextbook,
        tooltip: 'Lend a textbook',
        child: const Icon(Icons.add),
      ),
    );
  }
}
