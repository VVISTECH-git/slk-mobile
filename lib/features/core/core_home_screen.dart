import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/theme_button.dart';
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

    // Job role decides what shows, same as the web sidebar (see slk-core's
    // sidebar.tsx) — not Role, which grants nothing anymore. Filtered here
    // rather than left to the API's own 403: a tile that opens onto a wall
    // is worse than no tile, and this screen already has the file's own
    // "shown anyway, said plainly" rule for something that doesn't exist yet
    // — the same courtesy applies to something that exists but isn't this
    // actor's to open.
    final visible = [
      for (final module in _modules)
        if (actor != null && actor.hasAnyJobRole(module.jobRoles)) module,
    ];

    return Scaffold(
      backgroundColor: p.surface1,
      appBar: AppBar(
        title: const Text('SLK Stock'),
        actions: [
          const ThemeButton(),
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

          if (visible.isEmpty)
            const _NoJobRoles()
          else
            for (final module in visible)
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
  const _Module(this.label, this.detail, this.icon, this.route, this.jobRoles);

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

  /// Which job role(s) unlock this — matches the gate slk-core's own API
  /// actually enforces for the route behind it (see each module's own
  /// comment below for exactly which one). Never empty: everything requires
  /// something now that Role grants nothing on its own.
  final List<String> jobRoles;
}

class _NoJobRoles extends StatelessWidget {
  const _NoJobRoles();

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Text(
        "Signed in, but nothing is assigned yet. Ask whoever manages Staff "
        'to give this account a job role.',
        style: TextStyle(fontSize: 13, color: p.textSecondary, height: 1.4),
      ),
    );
  }
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
// Every gate below matches an actual API check in slk-core, not a guess —
// see that repo's api/v1 route files for each one, all still `guarded`
// (Admin-only) except the three the bale/vendor pipeline carved job roles
// out for.
const _modules = [
  _Module(
    'Product Management',
    'File something that has arrived',
    Icons.add_box_outlined,
    '/core/records/new',
    ['Admin'],
  ),
  _Module(
    'Products List',
    'Find one, and photograph it',
    Icons.inventory_2_outlined,
    '/core/records',
    ['Admin'],
  ),
  _Module(
    'Stock Records',
    'Scan a piece, count what is here',
    Icons.qr_code_scanner,
    '/core/stock',
    ['Admin'],
  ),
  _Module(
    'Photographs',
    'Everything still waiting to be shot',
    Icons.photo_camera_outlined,
    '/core/photographs',
    ['Admin'],
  ),
  _Module(
    'Picking',
    'Pack an order that is waiting',
    Icons.local_shipping_outlined,
    '/core/picking',
    ['Admin'],
  ),
  _Module(
    'Bale Intake',
    'Log a bale of raw cloth as it arrives',
    Icons.inventory_outlined,
    '/core/bales/new',
    ['Bale Custodian'],
  ),
  _Module(
    'Record Cutting',
    'Find a bale, log what was just cut',
    Icons.content_cut,
    '/core/bales/cut',
    ['Bale Custodian'],
  ),
  _Module(
    'Handovers',
    'Scan a Thaan out, scan it back',
    Icons.sync_alt,
    '/core/handovers',
    ['Bale Custodian', 'Handler'],
  ),
  _Module(
    'Print QR Labels',
    "Pick a bale, print the codes it's already generated",
    Icons.print_outlined,
    '/core/thaans/print',
    ['Bale Custodian'],
  ),
  _Module(
    'Scan a Thaan',
    'See a printed label\'s bale, stage and status',
    Icons.qr_code_scanner,
    '/core/thaans/scan',
    ['Bale Custodian', 'Handler'],
  ),
  _Module(
    'Vendor Ledger',
    'Price, approve and pay vendor work',
    Icons.receipt_long_outlined,
    '/core/vendors',
    ['Finance Manager'],
  ),
  _Module(
    'Stage Summary',
    'How many Thaans sit at each stage, and which',
    Icons.bar_chart_outlined,
    '/core/thaans/stage-summary',
    ['Production Manager', 'Operations Manager'],
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
              // person records is recorded against them. Job roles, not
              // Role, since that's what actually says what they can do here
              // — see CoreActor.hasAnyJobRole.
              actor.jobRoles.isEmpty
                  ? 'Signed in as ${actor.name}'
                  : 'Signed in as ${actor.name} · ${actor.jobRoles.join(", ")}',
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
