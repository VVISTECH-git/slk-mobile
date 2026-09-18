import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
import '../bales/bale_providers.dart';
import '../bales/thaan_labels_screen.dart';

/// Which bale to print labels for — defaults to bales that actually have a
/// QR-coded Thaan (nothing to print otherwise), searchable by code for
/// anything older. Mirrors Record Cutting's own default-filter + search.
class PrintLabelsScreen extends ConsumerStatefulWidget {
  const PrintLabelsScreen({super.key});

  @override
  ConsumerState<PrintLabelsScreen> createState() => _PrintLabelsScreenState();
}

class _PrintLabelsScreenState extends ConsumerState<PrintLabelsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bales = ref.watch(coreBalesProvider);
    final p = context.p;

    return Scaffold(
      appBar: AppBar(title: const Text('Print QR Labels'), actions: [const ThemeButton()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Search any bale by code',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: AsyncView<List<CoreBale>>(
              value: bales,
              onRetry: () => ref.invalidate(coreBalesProvider),
              data: (rows) {
                final shown = _query.isEmpty
                    ? rows.where((b) => b.qrGeneratedCount > 0).toList()
                    : rows.where((b) => b.code.toLowerCase().contains(_query.toLowerCase())).toList();

                if (shown.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _query.isEmpty ? 'No bale has a QR code generated yet.' : 'No bale matches "$_query".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.textSecondary),
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (final b in shown)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('${b.code} · ${b.supplierName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${b.itemName} · ${b.qrGeneratedCount} of ${b.thaanCount} Thaans coded'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ThaanLabelsScreen(baleId: b.id)),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
