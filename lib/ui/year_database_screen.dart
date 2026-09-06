import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/year_database.dart';
import 'app_scope.dart';
import 'centered_body.dart';
import 'scanner_screen.dart';
import 'text_input_dialog.dart';

/// Asks for the year belonging to a scanned code.
Future<int?> askForYear(
  BuildContext context, {
  required String code,
  int? initial,
}) async {
  final key = YearDatabase.normalizeKey(code);
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextInputDialog(
      title: 'Set the year',
      confirmLabel: 'Save',
      initialText: initial == null ? '' : '$initial',
      hintText: 'e.g. 1987',
      keyboardType: TextInputType.number,
      helper: Text('Code $key', style: Theme.of(context).textTheme.bodySmall),
      validator: (value) {
        final year = int.tryParse(value);
        return year == null || !YearDatabase.isPlausibleYear(year)
            ? 'Year between 1900 and 2100'
            : null;
      },
    ),
  );
  return text == null ? null : int.tryParse(text);
}

/// Management of the QR code to year mapping.
class YearDatabaseScreen extends StatefulWidget {
  const YearDatabaseScreen({super.key});

  @override
  State<YearDatabaseScreen> createState() => _YearDatabaseScreenState();
}

class _YearDatabaseScreenState extends State<YearDatabaseScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  YearDatabase get _years => AppScope.of(context).years;

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scanAndAdd() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScannerScreen()),
    );
    if (!mounted || code == null) return;
    await _edit(code);
  }

  Future<void> _edit(String code) async {
    final years = _years;
    final year = await askForYear(
      context,
      code: code,
      initial: years.yearFor(code),
    );
    if (year == null) return;
    await years.setYear(code, year);
    if (!mounted) return;
    _toast('${YearDatabase.normalizeKey(code)} → $year saved');
  }

  Future<void> _export() async {
    final json = _years.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    _toast('${_years.entries.length} entries on the clipboard');
  }

  Future<void> _import() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;

    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextInputDialog(
        title: 'Import JSON',
        confirmLabel: 'Import',
        initialText: clip?.text ?? '',
        hintText: '{"years": {"182ca01194a98f0b": 2005}}',
        minLines: 6,
        maxLines: 10,
        monospace: true,
      ),
    );
    if (!mounted || text == null || text.isEmpty) return;

    try {
      final result = await _years.importJson(text);
      if (!mounted) return;
      final skipped = result.skipped == 0 ? '' : ', ${result.skipped} skipped';
      _toast('${result.added} new, ${result.updated} changed$skipped');
    } on FormatException catch (error) {
      if (!mounted) return;
      _toast('Not valid JSON: ${error.message}');
    }
  }

  Future<void> _clearLocal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your own entries?'),
        content: Text(
          '${_years.localCount} years you entered will be removed. The '
          'bundled file stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _years.clearLocal();
    if (!mounted) return;
    _toast('Your own entries were deleted');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Year database'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'import':
                  _import();
                case 'export':
                  _export();
                case 'clear':
                  _clearLocal();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'import',
                child: Text('Import from clipboard'),
              ),
              PopupMenuItem(
                value: 'export',
                child: Text('Export to clipboard'),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text('Delete your own entries'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanAndAdd,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Add a card'),
      ),
      body: CenteredBody(
        child: ListenableBuilder(
          listenable: _years,
          builder: (context, _) {
            final query = _search.text.trim().toLowerCase();
            final all = _years.entries;
            final keys =
                all.keys
                    .where(
                      (key) =>
                          query.isEmpty ||
                          key.contains(query) ||
                          '${all[key]}'.contains(query),
                    )
                    .toList()
                  ..sort((a, b) {
                    final byYear = all[a]!.compareTo(all[b]!);
                    return byYear != 0 ? byYear : a.compareTo(b);
                  });

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${all.length} cards · ${_years.localCount} entered here',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: keys.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              all.isEmpty
                                  ? 'No cards yet.\nScan one below and type in '
                                        'the year from its back.'
                                  : 'Nothing found.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: keys.length,
                          itemBuilder: (context, index) {
                            final key = keys[index];
                            final local = _years.isLocal(key);
                            return ListTile(
                              title: Text('${all[key]}'),
                              subtitle: Text(
                                key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              leading: Icon(
                                local
                                    ? Icons.edit_note
                                    : Icons.inventory_2_outlined,
                                color: local
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              onTap: () => _edit(key),
                              trailing: local
                                  ? IconButton(
                                      tooltip: 'Remove entry',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _years.removeLocal(key),
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
