import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'theme_button.dart';

/// Temporary stand-in for a module still under construction. Replaced screen by
/// screen as each module lands.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [ThemeButton()],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_outlined, size: 48, color: context.p.textSecondary),
              SizedBox(height: 12),
              Text('Coming together — this screen is being built.',
                  textAlign: TextAlign.center, style: TextStyle(color: context.p.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown while the app checks whether a token is already stored, before it
/// knows to route to sign-in or straight to Home. The OS's own native splash
/// (flutter_native_splash — terracotta + splash_logo.png) already covers the
/// cold-start instant before Flutter's first frame; this one picks up
/// exactly where that leaves off — same colour, same mark — instead of
/// cutting to a bare spinner on a different background the moment Flutter
/// takes over. Deliberately not `context.p.surface1`: this runs before
/// there's any reason to show the signed-in-in account's chosen theme, and a
/// splash that changed colour per theme would just trade one jarring cut for
/// another.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const _brand = Color(0xFFB5533B);

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _brand,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image(image: AssetImage('assets/icon/splash_logo.png'), width: 104, height: 104),
              SizedBox(height: 22),
              Text(
                'SLK Stock',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.4),
              ),
              SizedBox(height: 32),
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
