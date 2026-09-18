import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/theme_button.dart';
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
    final p = context.p;

    return Scaffold(
      appBar: AppBar(title: const Text('Vendor Ledger'), actions: const [ThemeButton()]),
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
                    Expanded(child: _StatCard(label: 'Billed', value: totalBilled, color: p.text)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatCard(label: 'Paid', value: totalPaid, color: p.success)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Balance due',
                        value: balanceDue,
                        color: balanceDue > 0 ? p.danger : p.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final v in rows) _VendorTile(vendor: v),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: p.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '₹${value.toStringAsFixed(0)}',
            style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => context.push('/core/vendors/${vendor.id}', extra: vendor.name),
        title: Text(vendor.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          vendor.stages.isEmpty ? vendor.code : '${vendor.code} · ${vendor.stages.join(", ")}',
          style: TextStyle(color: p.textSecondary, fontSize: 12.5),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              vendor.balanceDue > 0 ? '₹${vendor.balanceDue.toStringAsFixed(0)}' : '—',
              style: TextStyle(
                color: vendor.balanceDue > 0 ? p.danger : p.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (vendor.currentlyHolding > 0)
              Text('${vendor.currentlyHolding} out', style: TextStyle(color: p.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
