import 'package:flutter_test/flutter_test.dart';

import 'package:slk_mobile/features/core/core_auth.dart';
import 'package:slk_mobile/models/core.dart';

void main() {
  group('restoreMayApply', () {
    test('REGRESSION: a late restore must not overwrite a live session', () {
      // The bug this guards. `_restore()` runs from build(), reads the Android
      // keystore — seconds on a first run — and then writes what it found. In
      // that window the sign-in screen is already up and somebody can sign in
      // and succeed. Without this rule the stale read lands afterwards and
      // sets "signed out", and the person who just signed in is looking at the
      // sign-in screen with a token minted server-side that they cannot use.
      expect(restoreMayApply(CoreAuthStatus.signedIn), isFalse);
    });

    test('nor a session someone has deliberately ended', () {
      // Signing out during the restore is also newer than the restore.
      expect(restoreMayApply(CoreAuthStatus.signedOut), isFalse);
    });

    test('applies only while nothing else has happened', () {
      expect(restoreMayApply(CoreAuthStatus.unknown), isTrue);
    });
  });

  group('CoreAuthState', () {
    test('is only signed in with an actor to be signed in as', () {
      const noActor = CoreAuthState(status: CoreAuthStatus.signedIn);
      expect(noActor.isSignedIn, isFalse,
          reason: 'signedIn without an actor is not a usable session');

      const real = CoreAuthState(
        status: CoreAuthStatus.signedIn,
        actor: CoreActor(id: 'a', code: 'c', name: 'n', role: 'floor'),
      );
      expect(real.isSignedIn, isTrue);
    });

    test('unknown is not signed in — it is the state before we know', () {
      expect(const CoreAuthState(status: CoreAuthStatus.unknown).isSignedIn, isFalse);
    });
  });
}
