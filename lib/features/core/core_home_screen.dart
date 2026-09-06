import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import 'core_auth.dart';

/// What the phone can do, on one screen.
///
/// Not the web's sidebar. That has five entries and three of them — Master
/// Lists, Locations, Staff — are desk work: maintaining a vocabulary,
/// describing a warehouse, provisioning an account. Nobody does those holding
/// a saree, and putting them here would be mistaking "the same system" for
/// "the same job".
///
/// What the floor does is narrower and physical: file what arrived, find what
/// is in your hands, count it, photograph it.
class CoreHomeScreen extends ConsumerWidget {
  const CoreHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.p;
    final actor = ref.watch(coreAuthProvider).actor;

    return Scaffold(
      backgroundColor: p.surface1,
      appBar: AppBar(
        title: const Text('SLK Stock'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(coreAuthProvider.notifier).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (actor != null) _Signed(actor: actor),
          const SizedBox(height: 18),

          for (final module in _modules)
            _Tile(
              module: module,
              onTap: module.route == null
                  ? null
                  : () => context.push(module.route!),
            ),
        ],
      ),
    );
  }
}

class _Module {
  const _Module(this.label, this.detail, this.icon, this.route);

  final String label;
  final String detail;
  final IconData icon;

  /// Null while the screen behind it does not exist.
  ///
  /// Shown anyway, and said plainly. A floor that can see what is coming is a
  /// floor that stops asking; a tile that silently does nothing is worse than
  /// no tile, and one quietly missing is how somebody concludes the app cannot
  /// do a thing it will.
  final String? route;
}

/*
  The labels are the web portal's, deliberately.

  Somebody who files a record at a desk in the morning and on a phone in the
  afternoon is doing one job, and a screen that renames it in between makes
  them stop and work out whether it is the same thing. The portal's sidebar is
  the vocabulary; this follows it rather than inventing a second one.

  Photographs is the exception — the portal has no such screen, because
  uploading there happens inside the record editor.
*/
const _modules = [
  _Module(
    'Product Management',
    'File something that has arrived',
    Icons.add_box_outlined,
    '/core/records/new',
  ),
  _Module(
    'Products List',
    'Find one, and photograph it',
    Icons.inventory_2_outlined,
    '/core/records',
  ),
  _Module(
    'Stock Records',
    'Scan a piece, count what is here',
    Icons.qr_code_scanner,
    '/core/stock',
  ),
  _Module(
    'Photographs',
    'Everything still waiting to be shot',
    Icons.photo_camera_outlined,
    '/core/photographs',
  ),
  _Module(
    'Picking',
    'Pack an order that is waiting',
    Icons.local_shipping_outlined,
    '/core/picking',
  ),
];

class _Tile extends StatelessWidget {
  const _Tile({required this.module, this.onTap});

  final _Module module;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final ready = onTap != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
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
                decoration: BoxDecoration(
                  color: ready
                      ? p.primary.withValues(alpha: 0.10)
                      : p.surface3,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  module.icon,
                  color: ready ? p.primary : p.textMuted,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: ready ? p.text : p.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      module.detail,
                      // One line. The chip beside it is vertically centred, so
                      // a wrapping description makes the two look tangled.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              if (ready)
                Icon(Icons.chevron_right, color: p.textMuted)
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.surface3,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Not built yet',
                    style: TextStyle(fontSize: 11, color: p.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Signed extends StatelessWidget {
  const _Signed({required this.actor});

  final CoreActor actor;

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 18, color: p.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Named, because a floor phone is shared and every movement this
              // person records is recorded against them.
              'Signed in as ${actor.name} · ${actor.role}',
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
