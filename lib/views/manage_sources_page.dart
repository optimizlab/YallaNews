import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_source.dart';
import '../database/news_db.dart';

class ManageSourcesPage extends StatefulWidget {
  const ManageSourcesPage({Key? key}) : super(key: key);

  @override
  State<ManageSourcesPage> createState() => _ManageSourcesPageState();
}

class _ManageSourcesPageState extends State<ManageSourcesPage> {
  List<NewsSource> _sources = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _isLoading = true);
    try {
      final sources = await NewsDatabase.instance.getAllSources();
      if (mounted) {
        setState(() {
          _sources = sources;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSourceDialog({NewsSource? source}) {
    final isEditing = source != null;
    final nameController = TextEditingController(text: source?.name ?? '');
    final urlController = TextEditingController(text: source?.url ?? '');
    final categoryController = TextEditingController(text: source?.category ?? 'General');
    
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(isEditing ? l10n.translate('editSource') : l10n.translate('addSource'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l10n.translate('name'),
                    hintText: l10n.translate('exampleName'),
                    labelStyle: GoogleFonts.outfit(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: l10n.translate('link'),
                    hintText: l10n.translate('exampleLink'),
                    labelStyle: GoogleFonts.outfit(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: categoryController,
                  decoration: InputDecoration(
                    labelText: l10n.translate('category'),
                    hintText: l10n.translate('exampleCategory'),
                    labelStyle: GoogleFonts.outfit(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.translate('cancel'), style: GoogleFonts.outfit()),
            ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: () async {
                  if (nameController.text.trim().isEmpty || urlController.text.trim().isEmpty) {
                     return;
                  }
                
                final newSource = NewsSource(
                  id: source?.id ?? 0,
                  country: source?.country ?? 'Global',
                  countryCode: source?.countryCode ?? 'INT',
                  name: nameController.text.trim(),
                  url: urlController.text.trim(),
                  category: categoryController.text.trim(),
                  type: source?.type ?? 'digital_news',
                  language: source?.language ?? 'ar',
                  rank: source?.rank ?? 0,
                );
                
                if (isEditing) {
                  await NewsDatabase.instance.updateSource(newSource);
                } else {
                  await NewsDatabase.instance.addSource(newSource);
                }
                
                if (mounted) {
                   Navigator.pop(context);
                   _loadSources();
                }
              },
              child: Text(l10n.translate('save'), style: GoogleFonts.outfit()),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('manageSources'), style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty 
              ? Center(child: Text(l10n.translate('noSources'), style: GoogleFonts.outfit()))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sources.length,
                  itemBuilder: (context, index) {
                    final src = _sources[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                      color: Theme.of(context).colorScheme.surface,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text(src.name, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             const SizedBox(height: 4),
                             Text(src.url, style: GoogleFonts.outfit(color: Theme.of(context).colorScheme.primary, fontSize: 13)),
                             const SizedBox(height: 4),
                             Container(
                               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                               decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(4),
                               ),
                               child: Text(src.category, style: GoogleFonts.outfit(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            )
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.primary),
                              onPressed: () => _showSourceDialog(source: src),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) {
                                    final dialogL10n = AppLocalizations.of(context);
                                    return AlertDialog(
                                      title: Text(dialogL10n.translate('deleteSource'), style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                                      content: Text(dialogL10n.translate('deleteSourceConfirm').replaceAll('{name}', src.name), style: GoogleFonts.outfit()),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(dialogL10n.translate('cancel'), style: GoogleFonts.outfit())),
                                         ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
                                          onPressed: () => Navigator.pop(context, true), 
                                          child: Text(dialogL10n.translate('delete'), style: GoogleFonts.outfit())
                                        ),
                                      ],
                                    );
                                  }
                                );
                                 
                                if (confirm == true) {
                                  await NewsDatabase.instance.deleteSource(src.id);
                                  _loadSources();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        onPressed: () => _showSourceDialog(),
        child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
      ),
    );
  }
}