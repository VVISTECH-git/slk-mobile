import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';
import '../../widgets/theme_button.dart';
import '../auth/auth_controller.dart';
import '../production/production_providers.dart' show jobBoardProvider;

class _Module {
  const _Module(this.label, this.icon, this.route, {this.ownerOnly = false});
  final String label;
  final IconData icon;
  final String route;
  final bool ownerOnly;
}

// Phase 1: focus on Category only. The rest are parked (hidden from Home, not
// deleted) — uncomment to bring a module back.
const _modules = [
  // The first screen on slk-core, the stock system. It signs in separately
  // and lives beside the tantu screens while the migration runs.
  _Module('New record', Icons.add_box_outlined, '/core/records/new'),
  _Module('Catalogue', Icons.category_outlined, '/category'),
  _Module('Products', Icons.inventory_2_outlined, '/products'),
  _Module('Tag pieces', Icons.qr_code_2, '/tag', ownerOnly: true),
  _Module('Identify item', Icons.qr_code_scanner, '/scan'),
  _Module('Sell (scan)', Icons.point_of_sale, '/pieces/sell'),
  // _Module('Point of Sale', Icons.point_of_sale, '/pos'),
  // _Module('Dashboard', Icons.dashboard_outlined, '/dashboard'),
  // _Module('Stock', Icons.warehouse_outlined, '/stock'),
  // _Module('Transfers', Icons.local_shipping_outlined, '/transfers'),
  // _Module('Production', Icons.precision_manufacturing_outlined, '/production'),
  // _Module('Invoices', Icons.receipt_long_outlined, '/invoices'),
  // _Module('Daily report', Icons.summarize_outlined, '/reports'),
  // _Module('Settings', Icons.settings_outlined, '/settings', ownerOnly: true),
];

/// Pieces currently out at vendors — shown as a badge on the Production tile.
final _prodPendingProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(jobBoardProvider).maybeWhen(
        data: (orders) => orders.fold<int>(0, (s, o) => s + ((o as Map)['pending'] as num).toInt()),
        orElse: () => 0,
      );
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).session;
    final isOwner = session?.isOwner ?? false;
    final modules = _modules.where((m) => !m.ownerOnly || isOwner).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SLK Mobile'),
        actions: [
          const ThemeButton(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) {
              if (v == 'logout') {
                ref.read(authControllerProvider.notifier).signOut();
              } else if (v == 'settings') {
                context.push('/settings');
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${session?.storeName ?? ''} · ${isOwner ? 'Owner' : 'Cashier'}',
                        style: TextStyle(fontSize: 12, color: context.p.textSecondary)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              if (isOwner)
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Settings'),
                  ),
                ),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _StoreBanner(store: session?.storeName ?? '', name: session?.name ?? ''),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.15,
              children: [for (final m in modules) _ModuleTile(module: m)],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreBanner extends StatelessWidget {
  const _StoreBanner({required this.store, required this.name});
  final String store;
  final String name;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      color: context.p.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, color: context.p.primaryDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('$store  ·  $name',
                style: TextStyle(fontWeight: FontWeight.w600, color: context.p.primaryDark)),
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends ConsumerWidget {
  const _ModuleTile({required this.module});
  final _Module module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = module.route == '/production' ? ref.watch(_prodPendingProvider) : 0;
    return Material(
      color: context.p.surface2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(module.route),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.p.border),
          ),
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: context.p.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(module.icon, color: context.p.primary, size: 26),
                    ),
                    const SizedBox(height: 12),
                    Text(module.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w600, color: context.p.text)),
                  ],
                ),
              ),
              if (badge > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: context.p.danger, borderRadius: BorderRadius.circular(20)),
                    child: Text('$badge',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
