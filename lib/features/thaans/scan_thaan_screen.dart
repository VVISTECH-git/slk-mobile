import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
import '../pos/barcode_scan_screen.dart';
import 'thaan_providers.dart';

/// Scan (camera) or type a Thaan's code → see its bale, stage and status.
/// Read-only — this never moves a Thaan anywhere, unlike Handovers' own
/// scanning, which only ever adds a Thaan to a batch, never shows what it
/// actually is. Same manual-entry-plus-camera shape as Identify Item and
/// Stock Records use for pieces, so scanning works the same way everywhere
/// in the app.
class ScanThaanScreen extends ConsumerStatefulWidget {
  const ScanThaanScreen({super.key});

  @override
  ConsumerState<ScanThaanScreen> createState() => _ScanThaanScreenState();
}

class _ScanThaanScreenState extends ConsumerState<ScanThaanScreen> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  CoreThaan? _result;
  String? _notFoundCode;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _result = null;
      _notFoundCode = null;
    });
    try {
      final thaan = await ref.read(thaanRepositoryProvider).lookupByCode(code);
      setState(() => _result = thaan);
    } on ApiException catch (e) {
      if (e.status == 404) {
        setState(() => _notFoundCode = code);
      } else if (mounted) {
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
      _field.clear();
      _focus.requestFocus();
    }
  }

  Future<void> _cameraScan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen(title: 'Scan a Thaan')),
    );
    if (code != null) await _lookup(code);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan a Thaan'), actions: const [ThemeButton()]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Scan a printed label's QR with the camera, or type its code.",
            style: TextStyle(color: p.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _field,
                  focusNode: _focus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Thaan code',
                    hintText: 'e.g. T00002048',
                    prefixIcon: Icon(Icons.qr_code),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: _lookup,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _cameraScan,
                icon: const Icon(Icons.photo_camera_outlined),
                tooltip: 'Scan with camera',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_notFoundCode != null && !_busy)
            Card(
              color: p.danger.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: p.danger),
                    const SizedBox(width: 10),
                    Expanded(child: Text('No Thaan found for "$_notFoundCode".')),
                  ],
                ),
              ),
            ),
          if (_result != null && !_busy) _ThaanCard(thaan: _result!),
        ],
      ),
    );
  }
}

class _ThaanCard extends StatelessWidget {
  const _ThaanCard({required this.thaan});
  final CoreThaan thaan;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final t = thaan;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.code ?? '—', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 17))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: p.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(t.pipelineStatus, style: TextStyle(color: p.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
            if (t.voidedAt != null) ...[
              const SizedBox(height: 6),
              Text('Voided on ${t.voidedAt}', style: TextStyle(color: p.danger, fontWeight: FontWeight.w600)),
            ],
            const Divider(height: 20),
            _kv(context, 'Bale', t.baleCode),
            _kv(context, 'Supplier', t.supplierName),
            _kv(context, 'Item', '${t.itemName} · ${t.baleType}'),
            _kv(context, 'Bale received', t.billEntryDate),
            if (t.perThaanMetres != null) _kv(context, 'Metres (this Thaan\'s share)', '${t.perThaanMetres}'),
            _kv(context, 'QR generated', t.qrGeneratedAt ?? 'Not yet'),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: context.p.textSecondary)),
            const SizedBox(width: 12),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
