import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_theme.dart';
import '../../widgets/picker_field.dart';
import '../../widgets/theme_button.dart';
import 'piece_labels_pdf.dart';
import 'piece_providers.dart';

/// Detail of a SINGLE piece (one QR tag): its design, colour, location and
/// status. Opened by tapping a piece in the Products list.
class PieceDetailScreen extends ConsumerStatefulWidget {
  const PieceDetailScreen({super.key, required this.tag});
  final String tag;

  @override
  ConsumerState<PieceDetailScreen> createState() => _PieceDetailScreenState();
}

class _PieceDetailScreenState extends ConsumerState<PieceDetailScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(pieceRepositoryProvider).identify(widget.tag);
  }

  void _reload() {
    setState(() {
      _future = ref.read(pieceRepositoryProvider).identify(widget.tag);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Piece'), actions: const [ThemeButton()]),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${snap.error}', style: TextStyle(color: context.p.danger)),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: _reload, child: const Text('Try again')),
              ]),
            );
          }
          final p = snap.data;
          if (p == null) {
            return Center(child: Text('No piece found for “${widget.tag}”.'));
          }
          return _detail(context, p);
        },
      ),
    );
  }

  Widget _detail(BuildContext context, Map<String, dynamic> p) {
    final colour = (p['color'] ?? '') as String? ?? '';
    final size = (p['size'] ?? '') as String? ?? '';
    final status = (p['status'] ?? '') as String;
    final statusColor = switch (status) {
      'available' => context.p.success,
      'sold' => context.p.textSecondary,
      'in_transit' => context.p.accent,
      _ => context.p.danger,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Scannable QR for this piece — tap to enlarge.
        Center(
          child: GestureDetector(
            onTap: () => _showQrPopup(context, '${p['tagCode']}'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.p.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: '${p['tagCode']}',
                    version: QrVersions.auto,
                    size: 180,
                    gapless: false,
                  ),
                  const SizedBox(height: 8),
                  Text('${p['tagCode']}',
                      style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_out_map, size: 13, color: context.p.textMuted),
                      const SizedBox(width: 4),
                      Text('Tap to enlarge',
                          style: TextStyle(fontSize: 11, color: context.p.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => printPieceLabels(
            codes: ['${p['tagCode']}'],
            productName: '${p['productName']}',
            variantLabel: (colour.isEmpty ? null : colour),
          ),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print / share QR tag'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: context.p.primary,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // QR tag + status
                Row(
                  children: [
                    Icon(Icons.qr_code_2, size: 22, color: context.p.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${p['tagCode']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: 0.4)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(status.replaceAll('_', ' '),
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('${p['productName']}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (colour.isNotEmpty || size.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (colour.isNotEmpty) ...[
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: colourSwatch(colour),
                            shape: BoxShape.circle,
                            border: Border.all(color: context.p.border),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          [if (colour.isNotEmpty) colour, if (size.isNotEmpty) size].join(' · '),
                          style: TextStyle(color: context.p.textSecondary, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Price — prominent.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(_money(p['price']),
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800, color: context.p.primaryDark)),
                    const SizedBox(width: 8),
                    if ((p['gstRate'] ?? '') != '')
                      Flexible(
                        child: Text('incl. ${p['gstRate']}% GST',
                            style: TextStyle(fontSize: 12, color: context.p.textSecondary),
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
                const Divider(height: 26),
                _kv(context, 'Item code', '${p['tagCode']}'),
                _kv(context, 'SKU', '${p['sku'] ?? '—'}'),
                _kv(context, 'Location', '${p['locationName'] ?? '—'}'),
                _kv(context, 'Status', status.replaceAll('_', ' ')),
                _kv(context, 'Tagged', _date(p['createdAt'])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Design details — all derived from the category.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.p.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.category_outlined, size: 16, color: context.p.textSecondary),
                const SizedBox(width: 6),
                Text('Design',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.p.textSecondary)),
              ]),
              const SizedBox(height: 10),
              _kv(context, 'Design', '${p['categoryName'] ?? '—'}'),
              _kv(context, 'Colour', colour.isEmpty ? '—' : colour),
              _kv(context, 'Fabric', '${p['fabric'] ?? '—'}'),
              _kv(context, 'Technique', '${p['technique'] ?? '—'}'),
              if ((p['dyeType'] ?? '') != '') _kv(context, 'Dye type', '${p['dyeType']}'),
              if ((p['borderStyle'] ?? '') != '') _kv(context, 'Border style', '${p['borderStyle']}'),
              _kv(context, 'HSN code', '${p['hsnCode'] ?? '—'}'),
              _kv(context, 'GST %', (p['gstRate'] ?? '') != '' ? '${p['gstRate']}%' : '—'),
            ],
          ),
        ),
      ],
    );
  }

  // Full-screen QR lightbox — tap anywhere to close.
  void _showQrPopup(BuildContext context, String code) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: LayoutBuilder(
                    builder: (_, c) {
                      final side = MediaQuery.of(ctx).size.width * 0.72;
                      return QrImageView(
                        data: code,
                        version: QrVersions.auto,
                        size: side.clamp(220.0, 420.0),
                        gapless: false,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(code,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 0.5)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _shareQr(code),
                  icon: const Icon(Icons.share),
                  label: const Text('Share QR image'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Tap anywhere to close',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Render the QR to a white PNG and open the OS share sheet (WhatsApp, etc.).
  Future<void> _shareQr(String code) async {
    try {
      final painter = QrPainter(
        data: code,
        version: QrVersions.auto,
        gapless: false,
        // This paints a standalone PNG for sharing, not a widget in a tree —
        // there is no container to inherit a background from, so the
        // deprecation's suggested alternative doesn't apply. Without this,
        // the exported image is transparent and unreadable over a dark chat
        // background.
        // ignore: deprecated_member_use
        emptyColor: Colors.white,
      );
      final bytes = await painter.toImageData(720);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$code.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    }
  }

  String _money(dynamic v) {
    if (v == null || '$v'.trim().isEmpty) return 'No price';
    final n = double.tryParse('$v');
    if (n == null) return '₹$v';
    return '₹${n.toStringAsFixed(0)}';
  }

  String _date(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return '—';
    // Backend sends e.g. "14/8/2026, 10:00:00 am" — keep the date part.
    return s.split(',').first.trim();
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: context.p.textSecondary)),
            Flexible(
                child: Text(v,
                    textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
