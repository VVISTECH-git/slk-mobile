import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
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

    return AppPage(
      title: 'Print QR Labels',
      actions: const [ThemeButton()],
      padded: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: AppTextField(
              label: 'Search',
              hint: 'Search any bale by code',
              controller: _search,
              textCapitalization: TextCapitalization.characters,
              suffix: _query.isEmpty
                  ? null
                  : AppIconButton(
                      icon: Icons.clear,
                      tooltip: 'Clear',
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
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
                  return EmptyState(
                    icon: Icons.qr_code_2,
                    title: _query.isEmpty ? 'No bale has a QR code generated yet.' : 'No bale matches "$_query".',
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    AppListGroup(
                      children: [
                        for (final b in shown)
                          AppListRow(
                            title: '${b.code} · ${b.supplierName}',
                            subtitle: '${b.itemName} · ${b.qrGeneratedCount} of ${b.thaanCount} Thaans coded',
                            chevron: true,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ThaanLabelsScreen(baleId: b.id)),
                            ),
                          ),
                      ],
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
