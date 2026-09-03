import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import 'core_auth.dart';

/// Signing in to slk-core.
///
/// A code and a PIN, and nothing else. Unlike the tantu login there is no
/// staff picker: that one lists everybody who works here before anyone has
/// proved who they are, and slk-core's login refuses to say whether a code
/// exists at all. Typing the code is what keeps that true.
class CoreSignInScreen extends ConsumerStatefulWidget {
  const CoreSignInScreen({super.key});

  @override
  ConsumerState<CoreSignInScreen> createState() => _CoreSignInScreenState();
}

class _CoreSignInScreenState extends ConsumerState<CoreSignInScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _busy = false;

  /// The last failure, kept on screen.
  ///
  /// It was a snackbar and nothing else, which is how a real bug stayed
  /// invisible: the sign-in failed, the message faded after four seconds, and
  /// what was left was a screen that looked like nothing had happened. A
  /// person cannot report what they did not see, and neither could I.
  String? _failure;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final pin = _pin.text.trim();

    if (code.isEmpty) {
      showError(context, 'Enter your code.');
      return;
    }
    // Six, matching what slk-core will accept. Checked here only to save a
    // round trip and a wasted attempt against the lockout — the server is
    // still the one that decides.
    if (pin.length < 6) {
      showError(context, 'Your PIN is at least 6 digits.');
      return;
    }

    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      await ref.read(coreAuthProvider.notifier).signIn(
            code: code,
            pin: pin,
            // Names the handset in the office's list of sign-ins, so a lost
            // phone can be revoked by itself rather than by signing everybody
            // out. Best effort — a blank one is fine.
            device: _deviceLabel(),
          );

      if (!mounted) return;

      /*
        Pop only if there is something to pop back to.

        This screen is reached two ways now: pushed from a record screen that
        found nobody signed in, and routed as the app's front door. Popping the
        front door would close the app; the router's redirect moves you on
        instead, the moment the session changes.
      */
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    } catch (e) {
      // Both: the snackbar catches the eye, the inline copy is still there
      // when somebody looks up from the saree in their hands.
      if (mounted) {
        setState(() => _failure = '$e');
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _deviceLabel() {
    final media = MediaQuery.maybeOf(context);
    final size = media == null
        ? ''
        : ' ${media.size.width.round()}×${media.size.height.round()}';

    return '${defaultTargetPlatform.name}$size';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;

    return Scaffold(
      backgroundColor: p.surface1,
      appBar: AppBar(title: const Text('Sign in to slk-core')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'The stock system',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Separate from your till sign-in. Ask the office for a code.',
                    style: TextStyle(fontSize: 13, color: p.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  TextField(
                    controller: _code,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _pinFocus.requestFocus(),
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _pin,
                    focusNode: _pinFocus,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_failure != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: p.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: p.danger.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _failure!,
                        style: TextStyle(fontSize: 12.5, color: p.danger, height: 1.4),
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),

                  const SizedBox(height: 18),
                  // Which server this build talks to. On a floor with a
                  // staging handset and a live one in the same drawer, this is
                  // the difference between a puzzling bug and an obvious one.
                  Text(
                    CoreConfig.baseUrl,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: p.textMuted),
                  ),

                  // No link to the till: it is retired, and an app that offers
                  // a way into a system nobody uses is an app that has to
                  // explain itself.
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
