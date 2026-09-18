import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
import 'thaan_providers.dart';

/// What a scanned Thaan QR resolves to — read-only, the same properties
/// slk-core's own Thaans table shows per row, for whoever just scanned a
/// label and wants to know what it is rather than move it anywhere.
class ThaanDetailScreen extends ConsumerWidget {
  const ThaanDetailScreen({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thaan = ref.watch(_thaanProvider(code));
    final p = context.p;

    return Scaffold(
      appBar: AppBar(
        title: Text(code, style: const TextStyle(fontFamily: 'monospace')),
        actions: [const ThemeButton()],
      ),
      body: AsyncView<CoreThaan>(
        value: thaan,
        onRetry: () => ref.invalidate(_thaanProvider(code)),
        data: (t) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (t.voidedAt != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text('Voided on ${t.voidedAt}', style: TextStyle(color: p.danger, fontWeight: FontWeight.w600)),
              ),
            _Card(
              children: [
                _Row('Status', t.pipelineStatus),
                _Row('Bale', t.baleCode),
                _Row('Supplier', t.supplierName),
                _Row('Item', '${t.itemName} · ${t.baleType}'),
                _Row('Bale received', t.billEntryDate),
                if (t.perThaanMetres != null) _Row('Metres (this Thaan\'s share)', '${t.perThaanMetres}'),
                _Row('QR generated', t.qrGeneratedAt ?? 'Not yet'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final _thaanProvider = FutureProvider.autoDispose.family<CoreThaan, String>(
  (ref, code) => ref.watch(thaanRepositoryProvider).lookupByCode(code),
);

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 12.5, color: p.textSecondary))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text))),
        ],
      ),
    );
  }
}
