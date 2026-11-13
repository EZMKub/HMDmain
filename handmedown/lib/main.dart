import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

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
              backgroundColor: Colors.black,
              body: Center(
                child: Text(
                  'Run the program using the steps in RunInstructions.md',
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
  @override
  void initState() {
    super.initState();
    _textbooks = _loadTextbooks();
  }

  Future<List<Map<String, dynamic>>> _loadTextbooks() async {
    final rows = await Supabase.instance.client
        .from('textbooks')
        .select('id, title, author, isbn, condition, created_at')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

Future<Map<String, dynamic>> _loadTextbook() async {
    final book = await Supabase.instance.client
        .from('textbooks')
        .select('id, title, author, isbn, condition, created_at')
        .maybeSingle();
    return Map<String, dynamic>.from(book ?? {});
  }


  // Reloads the catalog after a user refreshes or adds a textbook.
  Future<void> _refresh() {

    final request = _loadTextbooks();
    setState(() { _textbooks = request;});

    return request.then<void>(
      
      // A call back function, empty callback is (_), {} is 'do nothing'when successful
      (_) {},
      onError: (Object error) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh textbooks: $error')),
        );
      },
    );
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
            Text('ISBN: ${textbook['isbn']}'),
            const SizedBox(height: 12),
            Text('Condition: ${textbook['condition']}'),
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

  // Shows the add-listing form, validates it, then inserts the textbook if valid.
  Future<void> _addTextbook() async {
    final formKey = GlobalKey<FormState>();
    final _courseController = TextEditingController();
    final _titleController = TextEditingController();
    final _authorController = TextEditingController();
    final _isbnController = TextEditingController();
    final _communicationController = TextEditingController();
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
              // Update to be drop down?
              _textField(
                controller : _courseController, 
                label: 'Course name',
                error: 'Enter a name',
                onSaved: (value) => textbook['course'] = value,
              ),
              _textField(
                controller: _titleController,
                label: 'Textbook title',
                error: 'Enter a title',
                onSaved: (value) => textbook['title'] = value,
              ),
              _textField(
                controller: _authorController, 
                label: 'Author',
                error: 'Enter an author',
                onSaved: (value) => textbook['author'] = value,
              ),
              _textField(
                controller: _isbnController,
                label: 'ISBN',
                error: 'Enter ISBN',
                isRequired: false,
                onSaved: (value) => textbook['isbn'] = value,
              ),
              // Update to be drop down
              DropdownButtonFormField<String>(
                initialValue: 'Fair',
                decoration: const InputDecoration(labelText: 'Condition'),
                items: <DropdownMenuItem<String>>[
                  // Initializes the value of the dropdown, assigned text as a child of the value
                  DropdownMenuItem(value: 'New', child: Text('New')),
                  DropdownMenuItem(value: 'Good', child: Text('Good')),
                  DropdownMenuItem(value: 'Fair', child: Text('Fair')),
                  DropdownMenuItem(value: 'Damaged', child: Text('Damaged')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    textbook['condition'] = value;
                  }
                },

                onSaved: (value) {
                  if (value != null) {
                    textbook['condition'] = value;
                  }
                },
              ),
              _textField(
                controller: _communicationController,
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
      // Retrieve the code needed to edit
     final editCode = Random().nextInt(1000).toString();
      
      await Supabase.instance.client.from('textbooks').insert({
         // Condition is 'Fair by default
        ...textbook,
        'edit_code' : editCode,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Textbook added')));
      _refresh();

      await _codePopup(editCode);
      
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add textbook: $error')));
    }
  }

  // Shows the add-listing form, validates it, then inserts the textbook.
  Future<void> _codePopup(String code) {
    return showDialog<void>
    (
      context: context,
      builder: (dialogContext) => AlertDialog
      (
        title : const Text('Remember or save this code'),
        content : Text
        (
          'Remember this code or write it down, you will need it to edit or delete this post later: \n\n$code',
        ),
        actions: 
        [
          TextButton
          (
            onPressed: () => Navigator.pop(dialogContext),
            child : const Text('Close'),
          )
        ],
      )
    );
  }

  // Prompt user for code
  Future<String?> _askForCode() async {
  final controller = TextEditingController();

  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter your edit code'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Edit Code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<Map<String, dynamic>> _loadTextbookById(String textbookId) async {
  final row = await Supabase.instance.client
      .from('textbooks')
      .select(
        'id, course, title, author, isbn, condition, communication_method',
      )
      .eq('id', textbookId)
      .single();

  return Map<String, dynamic>.from(row);
}

Future<void> _editTextbook(Map<String, dynamic> selectedTextbook) async {
  final enteredCode = await _askForCode();
  if (enteredCode == null || !mounted) return;

  try {
    final textbookId = selectedTextbook['id'].toString();
    final oldTextbook = await _loadTextbookById(textbookId);
    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    final updatedTextbook = <String, String>{};

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit textbook'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _textField(
                controller: TextEditingController(
                  text: oldTextbook['course']?.toString() ?? '',
                ),
                label: 'Course name',
                error: 'Enter a name',
                onSaved: (value) => updatedTextbook['course'] = value,
              ),
              _textField(
                controller: TextEditingController(
                  text: oldTextbook['title']?.toString() ?? '',
                ),
                label: 'Textbook title',
                error: 'Enter a title',
                onSaved: (value) => updatedTextbook['title'] = value,
              ),
              _textField(
                controller: TextEditingController(
                  text: oldTextbook['author']?.toString() ?? '',
                ),
                label: 'Author',
                error: 'Enter an author',
                onSaved: (value) => updatedTextbook['author'] = value,
              ),
              _textField(
                controller: TextEditingController(
                  text: oldTextbook['isbn']?.toString() ?? '',
                ),
                label: 'ISBN',
                error: 'Enter ISBN',
                isRequired: false,
                onSaved: (value) => updatedTextbook['isbn'] = value,
              ),
              DropdownButtonFormField<String>(
                initialValue: oldTextbook['condition'] as String?,
                decoration: const InputDecoration(labelText: 'Condition'),
                items: const [
                  DropdownMenuItem(value: 'New', child: Text('New')),
                  DropdownMenuItem(value: 'Good', child: Text('Good')),
                  DropdownMenuItem(value: 'Fair', child: Text('Fair')),
                  DropdownMenuItem(value: 'Damaged', child: Text('Damaged')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    updatedTextbook['condition'] = value;
                  }
                },
                onSaved: (value) {
                  if (value != null) {
                    updatedTextbook['condition'] = value;
                  }
                },
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
            child: const Text('Edit'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final result = await Supabase.instance.client.rpc(
      'edit_textbook',
      params: {
        'p_id': textbookId,
        'p_code': enteredCode,
        'p_title': updatedTextbook['title'] ?? oldTextbook['title'],
        'p_author': updatedTextbook['author'] ?? oldTextbook['author'],
        'p_isbn': updatedTextbook['isbn'] ?? oldTextbook['isbn'],
        'p_course': updatedTextbook['course'] ?? oldTextbook['course'],
        'p_condition':
            updatedTextbook['condition'] ?? oldTextbook['condition'],
        'p_communication_method': oldTextbook['communication_method'],
      },
    );

    if (result != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect code or textbook listing not found'),
        ),
      );
      return;
    }

    if (!mounted) return;
    await _refresh();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Textbook edited')),
    );
  } catch (error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not edit textbook: $error')),
    );
  }
}

  // Text input used in the add form, change whether or not it's optional by using isRequired.
  Widget _textField({
  required String label,
  required String error,
  required ValueChanged<String> onSaved,
  required TextEditingController controller,
  bool isRequired = true,
}) {
  return TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    validator: isRequired
        ? (value) =>
            value == null || value.trim().isEmpty ? 'Enter $label' : null
        : null,
    onSaved: (value) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) {
        onSaved(text);
      }
    },
  );
}

Future<void> _deleteTextbook(Map<String, dynamic> textbook) async {
  final enteredCode = await _askForCode();
  if (enteredCode == null || !mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete textbook?'),
      content: Text('“${textbook['title']}” will be permanently deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true || !mounted) return;

  try {
    final result = await Supabase.instance.client.rpc(
      'delete_textbook',
      params: {
        'p_id': textbook['id'].toString(),
        'p_code': enteredCode,
      },
    );

    if (result != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect code or textbook listing not found'),
        ),
      );
      return;
    }

    if (!mounted) return;
    await _refresh();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Textbook deleted')),
    );
  } catch (error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Couldn't delete textbook: $error")),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    // Scaffold provides the app's bar, the catalog body, and the button for adding textbooks.
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange,
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
          final textbooks = snapshot.data!;
          if (textbooks.isEmpty) {
            return const Center(child: Text('No textbooks listed yet.'));
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
                                    '${textbook['author']} · ${textbook['condition']} · '
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
          
                                        child: IconButton(
                                          tooltip: 'edit listing',
                                      
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        // need to change onPressed to request random key,
                                        // then allow user to edit if they input the correct key. 
                                
                                        onPressed: () =>
                                        // could create new function, or simply repurpose add and remove for the most vile product
                                        // need to consider how to fill a form with previously entered data 
                                            _editTextbook(textbook),
                                        icon: const Icon(Icons.edit, size: 16),
                                        ),
                                      ),
                                      //Padding(
                                      // padding: EdgeInsets.only(right: 8),
                                       //child: Icon(Icons.share, size: 16),
                                     // ),
                                     
                                      IconButton(
                                        tooltip: 'Delete textbook',
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        onPressed: () =>
                                            _deleteTextbook(textbook),
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

//Class for processing number codes, like creating and checking for duplicates
class CodeNumberProcessing{
  final codesList = [];
  int validCode = 0;

  //generates a random 3 digit code to validate editing or removing posts (class name isn't finalized)
  Future<void> numberGenerator(){
    var random = Random();
    String codeString = "";
    int codeNumberOne = random.nextInt(10);
    int codeNumberTwo = random.nextInt(10);
    int codeNumberThree = random.nextInt(10);
    codeString += codeNumberOne.toString();
    codeString += codeNumberTwo.toString();
    codeString += codeNumberThree.toString();
    validCode = int.parse(codeString);

    //checks if the generated code is a duplicate, rolls a new one if it is, adds to the list
    for (int i = 0; i < codesList.length; i++){
      if (validCode = codesList[i]){
        numberGenerator();
        i = 0;
      }
    }
    codesList.add(validCode);
    //validCode = 0;

    throw Exception("number not generated");
  }

}
