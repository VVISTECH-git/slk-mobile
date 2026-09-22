import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../widgets/ui/ui.dart';
import 'vendor_providers.dart';

/// Every vendor with what's owed and what's been paid — Finance Manager's
/// own landing screen. Tap a vendor to price, approve, pay and settle
/// damaged Thaans against them (see vendor_detail_screen.dart). Mirrors
/// slk-core's own Vendors page, narrowed to what a phone needs — no adding
/// a vendor or editing rates here, that stays desk work on the web.
class VendorLedgerScreen extends ConsumerWidget {
  const VendorLedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(coreVendorsFinanceProvider);

    return AppPage(
      title: 'Vendor Ledger',
      actions: const [ThemeButton()],
      padded: false,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(coreVendorsFinanceProvider),
        child: AsyncView(
          value: vendors,
          onRetry: () => ref.invalidate(coreVendorsFinanceProvider),
          isEmpty: (rows) => rows.isEmpty,
          emptyMessage: 'No vendors yet.',
          data: (rows) {
            final totalBilled = rows.fold<double>(0, (s, v) => s + v.totalEarned);
            final totalPaid = rows.fold<double>(0, (s, v) => s + v.totalPaid);
            final balanceDue = totalBilled - totalPaid;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Row(
                  children: [
                    Expanded(child: _StatCard(label: 'Billed', value: totalBilled)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(label: 'Paid', value: totalPaid, tone: BadgeTone.success)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Balance due',
                        value: balanceDue,
                        tone: balanceDue > 0 ? BadgeTone.danger : BadgeTone.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppListGroup(children: [for (final v in rows) _VendorTile(vendor: v)]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.tone = BadgeTone.neutral});
  final String label;
  final double value;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      // Three abreast on a phone; a six-figure rupee total scales down
      // rather than clipping.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: StatTile(value: '₹${value.toStringAsFixed(0)}', label: label, tone: tone),
      ),
    );
  }
}

class _VendorTile extends StatelessWidget {
  const _VendorTile({required this.vendor});
  final CoreVendorFinance vendor;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppListRow(
      onTap: () => context.push('/core/vendors/${vendor.id}', extra: vendor.name),
      title: vendor.name,
      subtitle: vendor.stages.isEmpty ? vendor.code : '${vendor.code} · ${vendor.stages.join(", ")}',
      chevron: true,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            vendor.balanceDue > 0 ? '₹${vendor.balanceDue.toStringAsFixed(0)}' : '—',
            style: TextStyle(
              color: vendor.balanceDue > 0 ? p.danger : p.textMuted,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (vendor.currentlyHolding > 0)
            Text('${vendor.currentlyHolding} out', style: TextStyle(color: p.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
