import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/theme_button.dart';
import '../pos/barcode_scan_screen.dart';
import 'production_providers.dart';

class PieceLookupScreen extends ConsumerStatefulWidget {
  const PieceLookupScreen({super.key});

  @override
  ConsumerState<PieceLookupScreen> createState() => _PieceLookupScreenState();
}

class _PieceLookupScreenState extends ConsumerState<PieceLookupScreen> {
  Map<String, dynamic>? _piece;
  String? _error;
  bool _busy = false;

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen(title: 'Scan a tag')),
    );
    if (code != null) _lookup(code);
  }

  Future<void> _lookup(String tag) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await ref.read(productionRepositoryProvider).lookupPiece(tag.trim());
      setState(() => _piece = p);
    } catch (e) {
      setState(() {
        _piece = null;
        _error = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Piece lookup'), actions: const [ThemeButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan a tag'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 20),
          if (_busy) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: context.p.danger)),
            ),
          if (_piece != null) _pieceCard(context, _piece!),
        ],
      ),
    );
  }

  Widget _pieceCard(BuildContext context, Map<String, dynamic> p) {
    final events = (p['events'] as List? ?? []);
    final statusColor = switch (p['status']) {
      'in_warehouse' => context.p.success,
      'at_vendor' => context.p.accent,
      'finished' => context.p.primary,
      _ => context.p.danger,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['tagCode']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Text('Batch ${p['batchCode'] ?? '—'}${p['size'] != null ? ' · ${p['size']}' : ''}',
                    style: TextStyle(color: context.p.textSecondary)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text('${p['status']}'.replaceAll('_', ' '),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
                  ),
                  if (p['vendorName'] != null)
                    Text('at ${p['vendorName']}', style: TextStyle(fontSize: 13, color: context.p.textSecondary)),
                  if (p['stageName'] != null)
                    Text('· last stage: ${p['stageName']}', style: TextStyle(fontSize: 13, color: context.p.textSecondary)),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('History', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.circle, size: 8, color: context.p.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${'${(e as Map)['event']}'.replaceAll('_', ' ')}'
                        '${e['stageName'] != null ? ' · ${e['stageName']}' : ''}'
                        '${e['vendorName'] != null ? ' → ${e['vendorName']}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${e['detail'] != null ? '${e['detail']} · ' : ''}${e['actor'] ?? ''} · ${e['createdAt']}',
                        style: TextStyle(fontSize: 12, color: context.p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
