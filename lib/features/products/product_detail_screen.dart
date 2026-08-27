import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/theme_button.dart';
import '../../widgets/async_view.dart';
import '../../widgets/photo_viewer.dart';
import 'product_providers.dart';
import 'variant_photos_screen.dart';

/// Read view of a product: identity, tax, and each variant with its prices and
/// per-location stock. (Editing happens on the web portal / a later form.)
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(productDetailProvider(productId));
    final lookups = ref.watch(lookupsProvider);

    // Map location id → name for the per-variant stock breakdown.
    final locNames = <String, String>{};
    lookups.whenData((l) {
      for (final loc in (l['locations'] as List? ?? [])) {
        final m = (loc as Map).cast<String, dynamic>();
        locNames[m['id'] as String] = m['name'] as String;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product'),
        actions: [
          const ThemeButton(),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await context.push('/products/$productId/edit');
              ref.invalidate(productDetailProvider(productId));
            },
          ),
        ],
      ),
      body: AsyncView<Map<String, dynamic>>(
        value: detail,
        onRetry: () => ref.invalidate(productDetailProvider(productId)),
        data: (p) {
          final variants = (p['variants'] as List? ?? []).cast<dynamic>();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((p['name'] ?? '') as String,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text((p['productCode'] ?? '') as String,
                          style: TextStyle(color: context.p.textSecondary)),
                      if (((p['description'] ?? '') as String).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(p['description'] as String),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _tag(context, 'Status', (p['status'] ?? '') as String),
                          if (((p['hsnCode'] ?? '') as String).isNotEmpty)
                            _tag(context, 'HSN', p['hsnCode'] as String),
                          if (((p['gstRate'] ?? '') as String).isNotEmpty)
                            _tag(context, 'GST', '${p['gstRate']}%'),
                          if (((p['unitType'] ?? '') as String).isNotEmpty)
                            _tag(context, 'Unit', p['unitType'] as String),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (((p['categoryId'] ?? '') as String).isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VariantPhotosScreen(
                      categoryId: p['categoryId'] as String,
                      designName: (p['name'] ?? '') as String,
                    ),
                  )),
                  icon: const Icon(Icons.photo_camera_back_outlined),
                  label: const Text('Add / manage product photos'),
                ),
              const SizedBox(height: 16),
              _PhotoGallery(groups: ((p['photoGroups'] as List?) ?? const [])),
              Text('Colours (${variants.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              for (final v in variants)
                _VariantCard(v: (v as Map).cast<String, dynamic>(), locNames: locNames),
              const SizedBox(height: 20),
              _PiecesSection(productId: productId),
            ],
          );
        },
      ),
    );
  }

  Widget _tag(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.p.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.p.border),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({required this.v, required this.locNames});
  final Map<String, dynamic> v;
  final Map<String, String> locNames;

  @override
  Widget build(BuildContext context) {
    final label = [v['color'], v['size']].where((s) => (s as String).isNotEmpty).join(' / ');
    final inv = (v['inv'] as Map?)?.cast<String, dynamic>() ?? {};
    int total = 0;
    for (final e in inv.values) {
      total += int.tryParse(((e as Map)['onHand'] ?? '0').toString()) ?? 0;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label.isEmpty ? (v['sku'] as String) : label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text('$total in stock',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: total <= 3 ? context.p.danger : context.p.text)),
              ],
            ),
            Text(v['sku'] as String, style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              children: [
                if (((v['b2c'] ?? '') as String).isNotEmpty)
                  _price(context, 'Retail', double.tryParse(v['b2c'] as String)),
                if (((v['cost'] ?? '') as String).isNotEmpty)
                  _price(context, 'Cost', double.tryParse(v['cost'] as String)),
                if (((v['b2b'] ?? '') as String).isNotEmpty)
                  _price(context, 'B2B', double.tryParse(v['b2b'] as String)),
              ],
            ),
            if (inv.isNotEmpty) ...[
              const Divider(height: 18),
              for (final e in inv.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(locNames[e.key] ?? 'Location',
                          style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
                      Text('${(e.value as Map)['onHand']}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _price(BuildContext context, String label, double? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: context.p.textSecondary)),
        Text(value == null ? '—' : money0(value),
            style: TextStyle(fontWeight: FontWeight.w700, color: context.p.primaryDark)),
      ],
    );
  }
}

// Individual serialized pieces (each with its own QR). Each physical unit is
// listed separately here, even though the catalogue shows an aggregate count.
class _PiecesSection extends ConsumerWidget {
  const _PiecesSection({required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(productPiecesProvider(productId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (pieces) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pieces (${pieces.length})',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            if (pieces.isEmpty)
              Text('No individual pieces tagged yet. Use “Receive stock” to tag pieces with QR codes.',
                  style: TextStyle(fontSize: 13, color: context.p.textSecondary))
            else
              for (final raw in pieces) _PieceRow(p: (raw).cast<String, dynamic>()),
          ],
        );
      },
    );
  }
}

class _PieceRow extends StatelessWidget {
  const _PieceRow({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final status = (p['status'] ?? '') as String;
    final colour = (p['colour'] ?? '') as String?;
    final location = (p['location'] ?? '') as String?;
    final sub = [
      if ((colour ?? '').isNotEmpty) colour,
      if ((location ?? '').isNotEmpty) location,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.qr_code_2, color: context.p.primary),
        title: Text('${p['tagCode']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: sub.isEmpty ? null : Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: _PieceStatusChip(status: status),
      ),
    );
  }
}

class _PieceStatusChip extends StatelessWidget {
  const _PieceStatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'available'
        ? context.p.success
        : status == 'sold'
            ? context.p.textSecondary
            : status == 'in_transit'
                ? context.p.accent
                : context.p.danger;
    final label = status.isEmpty ? '—' : status.replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// Product photos grouped by colour (shared across sizes). One thumbnail strip
// per colour that has photos.
class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.groups});
  final List groups;

  @override
  Widget build(BuildContext context) {
    final withPhotos = groups
        .map((g) => (g as Map).cast<String, dynamic>())
        .where((g) => ((g['images'] as List?) ?? const []).isNotEmpty)
        .toList();
    if (withPhotos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Photos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        for (final g in withPhotos) ...[
          if (((g['color'] ?? '') as String).trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${g['color']}',
                  style: TextStyle(fontSize: 12, color: context.p.textSecondary, fontWeight: FontWeight.w600)),
            ),
          Builder(builder: (context) {
            final data = [for (final im in (g['images'] as List)) ((im as Map)['data'] ?? '') as String];
            final title = ((g['color'] ?? '') as String).trim();
            return SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < data.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => openPhotoViewer(
                          context,
                          images: data,
                          initialIndex: i,
                          title: title,
                          heroPrefix: 'photo_${title}_',
                        ),
                        child: Hero(
                          tag: 'photo_${title}_$i',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              base64Decode(data[i]),
                              height: 84,
                              width: 84,
                              fit: BoxFit.cover,
                              cacheWidth: 220,
                              cacheHeight: 220,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
