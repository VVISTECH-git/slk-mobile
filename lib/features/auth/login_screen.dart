import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import '../../widgets/theme_button.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late Future<Map<String, dynamic>> _optionsFuture;
  String? _staffId;
  String? _staffStoreId; // the staff member's fixed store (null for owners)
  String? _pickedStoreId; // owner-chosen store
  final _pin = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _optionsFuture = ref.read(authControllerProvider.notifier).loginOptions();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_staffId == null) {
      showError(context, 'Pick who is signing in.');
      return;
    }
    if (_pin.text.trim().length != 4) {
      showError(context, 'Enter your 4-digit PIN.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).signIn(
            staffId: _staffId!,
            pin: _pin.text.trim(),
            storeId: _staffStoreId ?? _pickedStoreId,
          );
      // Router redirect takes over on success.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar here, so set the status-bar icon brightness ourselves — dark
    // icons on the light themes, light icons on Dark — otherwise the clock is
    // invisible against the cream background.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlay = (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: context.p.surface1,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: _optionsFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return _Connecting(
                            onRetry: () => setState(() {
                              _optionsFuture =
                                  ref.read(authControllerProvider.notifier).loginOptions();
                            }),
                          );
                        }
                        if (snap.hasError) {
                          return _ErrorRetry(
                            message: '${snap.error}',
                            onRetry: () => setState(() {
                              _optionsFuture =
                                  ref.read(authControllerProvider.notifier).loginOptions();
                            }),
                          );
                        }
                        final staff = (snap.data!['staff'] as List).cast<Map<String, dynamic>>();
                        final stores = (snap.data!['stores'] as List).cast<Map<String, dynamic>>();
                        return _form(staff, stores);
                      },
                    ),
                  ),
                ),
              ),
              // App-wide theme switch is also reachable here, before sign-in.
              const Positioned(top: 0, right: 4, child: ThemeButton()),

              /*
                The way through to slk-core, the stock system.

                Outside the FutureBuilder above, deliberately. That builder
                shows an error state when the till's staff list cannot be
                loaded — which is exactly the moment somebody needs the other
                system, and the moment a link placed inside the form would
                have disappeared.

                Here at all because the two systems sign in separately and
                this screen is where the app lands. Without it the stock
                screens are unreachable whenever nobody is signed in to the
                till, which is most mornings.
              */
              const Positioned(left: 0, right: 0, bottom: 8, child: _StockSystemLink()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(List<Map<String, dynamic>> staff, List<Map<String, dynamic>> stores) {
    final selected = staff.where((s) => s['id'] == _staffId).firstOrNull;
    final needsStorePick = selected != null && selected['storeId'] == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Brand(),
        const SizedBox(height: 28),
        Text('Sign in to the till',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.p.text)),
        const SizedBox(height: 4),
        Text('Choose your name and enter your PIN.',
            style: TextStyle(color: context.p.textSecondary)),
        const SizedBox(height: 20),
        PickerField(
          label: 'Staff member',
          hint: 'Select who is signing in',
          value: _staffId,
          options: [
            for (final s in staff)
              PickerOption(
                s['id'] as String,
                '${s['name']}'
                    '${s['storeName'] != null ? '  ·  ${s['storeName']}' : ''}',
              ),
          ],
          onChanged: (v) => setState(() {
            _staffId = v;
            _staffStoreId = staff.where((s) => s['id'] == v).firstOrNull?['storeId'] as String?;
            _pickedStoreId = null;
          }),
        ),
        if (needsStorePick) ...[
          const SizedBox(height: 14),
          PickerField(
            label: 'Operate at store',
            hint: 'Select a store',
            value: _pickedStoreId,
            options: [
              for (final s in stores) PickerOption(s['id'] as String, '${s['name']}'),
            ],
            onChanged: (v) => setState(() => _pickedStoreId = v),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: 'PIN',
            hintText: 'Enter your 4-digit PIN',
            counterText: '',
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Sign in'),
        ),
      ],
    );
  }
}

/// A quiet way into slk-core from the till's login screen.
///
/// Understated on purpose. Nearly everybody arriving here wants the till, and
/// this is for the warehouse — loud enough to find when you are looking for
/// it, quiet enough not to be tapped by mistake at a counter.
///
/// Temporary in the way the migration is temporary: when the till moves onto
/// slk-core too there is one sign-in again and this goes away.
class _StockSystemLink extends StatelessWidget {
  const _StockSystemLink();

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Center(
      child: TextButton.icon(
        onPressed: () => context.push('/core/records/new'),
        icon: Icon(Icons.warehouse_outlined, size: 18, color: p.textSecondary),
        label: Text(
          'Stock system',
          style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            color: context.p.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Center(
            child: Text('SLK',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
        ),
        const SizedBox(height: 12),
        Text('SLK Mobile',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.p.primaryDark)),
      ],
    );
  }
}

/// Loading state for the login options fetch. Shows the brand + a clear
/// "Connecting…" message, and after a few seconds offers a Retry — so a slow
/// or waking server never looks like a frozen, endless spinner.
class _Connecting extends StatefulWidget {
  const _Connecting({required this.onRetry});
  final VoidCallback onRetry;

  @override
  State<_Connecting> createState() => _ConnectingState();
}

class _ConnectingState extends State<_Connecting> {
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Brand(),
        const SizedBox(height: 28),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('Connecting to the server…',
            textAlign: TextAlign.center, style: TextStyle(color: context.p.textSecondary)),
        if (_slow) ...[
          const SizedBox(height: 8),
          Text('Taking longer than usual — tap retry if it doesn\'t load.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.p.textMuted)),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: widget.onRetry, child: const Text('Retry')),
        ],
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Brand(),
        const SizedBox(height: 24),
        Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.p.textSecondary)),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
