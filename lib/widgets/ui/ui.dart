/// The component library. Import this one file on any screen:
///
///     import '../../widgets/ui/ui.dart';
///
/// and build from these, not from raw Material widgets — so every screen
/// gets the same buttons, cards, fields, headers, badges, dialogs, rows and
/// the same four states (loading, empty, error, success).
///
/// Rules the library encodes, so screens don't have to remember them:
///   • one primary action per screen, pinned in a [BottomActionBar];
///   • 48 px buttons, 56 px rows, 44 px icon buttons — nothing smaller;
///   • borders and spacing separate things, never shadows or gradients;
///   • one accent colour (the palette's `primary`); status colours are
///     semantic ([BadgeTone]) and never used as decoration;
///   • no animation beyond ripples and the loading shimmer.
library;

export '../../theme/app_theme.dart';
export '../async_view.dart';
export '../picker_field.dart';
export '../skeleton.dart';
export '../theme_button.dart';
export 'app_button.dart';
export 'app_card.dart';
export 'app_dialog.dart';
export 'app_list_row.dart';
export 'app_page.dart';
export 'app_text_field.dart';
export 'states.dart';
export 'status_badge.dart';
