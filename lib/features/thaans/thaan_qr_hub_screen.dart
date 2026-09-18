import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
import '../bales/bale_providers.dart';
import '../bales/thaan_labels_screen.dart';
import '../core/core_auth.dart';
import '../pos/barcode_scan_screen.dart';
import 'thaan_detail_screen.dart';

/// Everything about a Thaan's QR code in one place: print a bale's labels,
/// or scan one to see what it is. Two different scopes — printing needs a
/// bale picked first, scanning goes straight from a code to a Thaan — so
/// this is a hub rather than one form, same as Stock Records mixes manual
/// entry and scan-to-look-up for pieces.
class ThaanQrHubScreen extends ConsumerWidget {
  const ThaanQrHubScreen({super.key});

  Future<void> _scan(BuildContext context) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen(title: 'Scan a Thaan')),
    );
    if (code != null && context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThaanDetailScreen(code: code)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Printing hits routes gated to Bale Custodian only — see
    // generate-qr/route.ts and the GET on bales/[id]/thaans. Scanning
    // (lookup route) allows Handler too, so both see this tile, but only a
    // Bale Custodian sees the print entry point inside it.
    final actor = ref.watch(coreAuthProvider).actor;
    final canPrint = actor?.hasAnyJobRole(['Bale Custodian']) ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Thaan QR Codes'), actions: [const ThemeButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            icon: Icons.qr_code_scanner,
            title: 'Scan a Thaan',
            detail: 'Point the camera at a printed label to see its bale, stage and status.',
            onTap: () => _scan(context),
          ),
          if (canPrint) ...[
            const SizedBox(height: 12),
            _Card(
              icon: Icons.print_outlined,
              title: 'Print labels',
              detail: "Pick a bale, print the QR codes it's already generated.",
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _PickBaleForPrintScreen()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.detail, required this.onTap});
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: p.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: p.text)),
                    const SizedBox(height: 2),
                    Text(detail, style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which bale to print labels for — defaults to bales that actually have a
/// QR-coded Thaan (nothing to print otherwise), searchable by code for
/// anything older. Mirrors Record Cutting's own default-filter + search.
class _PickBaleForPrintScreen extends ConsumerStatefulWidget {
  const _PickBaleForPrintScreen();

  @override
  ConsumerState<_PickBaleForPrintScreen> createState() => _PickBaleForPrintScreenState();
}

class _PickBaleForPrintScreenState extends ConsumerState<_PickBaleForPrintScreen> {
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
      appBar: AppBar(title: const Text('Print labels — pick a bale'), actions: [const ThemeButton()]),
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
                    : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _search.clear(); _query = ''; })),
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
