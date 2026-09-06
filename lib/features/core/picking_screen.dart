import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import 'core_auth.dart';

/// Orders Shopify has already reserved, waiting to actually leave.
///
/// A reservation and a movement are different acts — nothing physical
/// happens when an order arrives, so nothing is written to the ledger until
/// somebody here says the piece has actually left. Packing writes the same
/// "sold" movement a walk-in sale does; this screen is only the trigger.
///
/// autoDispose for the same reason [coreRecordsProvider] is: a reservation
/// packed a minute ago should not still be sitting in the list the next time
/// somebody opens this screen.
final corePickingProvider =
    FutureProvider.autoDispose<List<CoreReservation>>((ref) async {
  final data = await ref.read(coreApiProvider).get('/picking');

  return [
    for (final row in (data as List))
      CoreReservation.fromJson((row as Map).cast<String, dynamic>()),
  ];
});

class PickingScreen extends ConsumerWidget {
  const PickingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(corePickingProvider);
    final p = context.p;

    return Scaffold(
      backgroundColor: p.surface1,
      appBar: AppBar(title: const Text('Picking')),
      body: AsyncView<List<CoreReservation>>(
        value: reservations,
        onRetry: () => ref.invalidate(corePickingProvider),
        data: (rows) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(corePickingProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Column(
                    children: [
                      Icon(Icons.inventory_outlined, size: 40, color: p.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        'Nothing waiting to be packed.',
                        style: TextStyle(color: p.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                for (final r in rows)
                  _ReservationCard(
                    reservation: r,
                    onPacked: () => ref.invalidate(corePickingProvider),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReservationCard extends ConsumerStatefulWidget {
  const _ReservationCard({required this.reservation, required this.onPacked});

  final CoreReservation reservation;
  final VoidCallback onPacked;

  @override
  ConsumerState<_ReservationCard> createState() => _ReservationCardState();
}

class _ReservationCardState extends ConsumerState<_ReservationCard> {
  String? _locationId;
  bool _busy = false;
  String? _error;

  Future<void> _pack() async {
    final locationId = _locationId;
    if (locationId == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final data = await ref.read(coreApiProvider).post(
        '/picking/${widget.reservation.id}/pack',
        body: {'locationId': locationId},
      );
      final message = (data as Map)['message'] as String? ?? 'Packed.';
      if (mounted) {
        showOk(context, message);
        widget.onPacked();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final r = widget.reservation;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.designName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        r.productCode,
                        if (r.colour != null) r.colour!,
                        r.channelName,
                      ].join('  ·  '),
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                '${r.qty}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (r.externalOrderName != null) r.externalOrderName!,
              r.createdAt,
            ].join('  ·  '),
            style: TextStyle(fontSize: 11.5, color: p.textMuted),
          ),
          const SizedBox(height: 12),
          if (r.holding.isEmpty)
            Text(
              'Nowhere internal currently holds this — nothing to pack from.',
              style: TextStyle(fontSize: 12.5, color: p.danger),
            )
          else ...[
            PickerField(
              label: 'Pack from',
              value: _locationId,
              options: [
                for (final h in r.holding)
                  PickerOption(h.id, '${h.name}  ·  ${h.qty}'),
              ],
              onChanged: (v) => setState(() => _locationId = v),
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(fontSize: 12, color: p.danger)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_busy || _locationId == null) ? null : _pack,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pack'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
