import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/invoices/invoice_screen.dart';
import 'features/pos/checkout_screen.dart';
import 'features/pos/pos_screen.dart';
import 'features/products/products_screen.dart';
import 'features/products/product_detail_screen.dart';
import 'features/products/product_form_screen.dart';
import 'features/products/variant_photos_screen.dart';
import 'features/category/category_list_screen.dart';
import 'features/category/category_form_screen.dart';
import 'features/core/core_auth.dart';
import 'features/core/core_home_screen.dart';
import 'features/core/core_sign_in_screen.dart';
import 'features/core/new_record_screen.dart';
import 'features/core/photographs_screen.dart';
import 'features/core/records_list_screen.dart';
import 'features/core/record_detail_screen.dart';
import 'features/core/record_photos_screen.dart';
import 'features/core/stock_records_screen.dart';
import 'features/stock/stock_screen.dart';
import 'features/stock/movements_screen.dart';
import 'features/pieces/scan_identify_screen.dart';
import 'features/pieces/piece_detail_screen.dart';
import 'features/pieces/tag_pieces_screen.dart';
import 'features/pieces/goods_in_screen.dart';
import 'features/pieces/dispatch_pieces_screen.dart';
import 'features/pieces/receive_pieces_screen.dart';
import 'features/pieces/scan_sale_screen.dart';
import 'features/transfers/transfers_screen.dart';
import 'features/transfers/new_transfer_screen.dart';
import 'features/transfers/transfer_detail_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/invoices/invoices_screen.dart';
import 'features/reports/reconciliation_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/master_data_screen.dart';
import 'features/settings/photo_guide_screen.dart';
import 'features/production/production_screen.dart';
import 'features/production/batches_screen.dart';
import 'features/production/batch_detail_screen.dart';
import 'features/production/dispatch_screen.dart';
import 'features/production/job_board_screen.dart';
import 'features/production/receive_screen.dart';
import 'features/production/piece_lookup_screen.dart';
import 'features/production/finish_screen.dart';
import 'widgets/placeholder_screen.dart';

/// App router. Redirects between splash / login / app based on auth status; a
/// ValueNotifier bumped on every auth change tells go_router to re-evaluate.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  // The stock session drives the front door now, so the router has to hear
  // about it too — without this, signing in leaves you on the sign-in screen.
  ref.listen(coreAuthProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    /*
      This is the slk-core app now.

      It opened on tantu's login and the stock screens hung off the side of it.
      tantu is retired, so the relationship is the other way round and then
      gone: the home is slk-core's, the sign-in is slk-core's, and the till
      screens below are dead code awaiting deletion.
    */
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final core = ref.read(coreAuthProvider);
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      /*
        The home is slk-core's now — tantu is retired.

        `/` used to be the till's home and everything hung off it. The till
        screens below still compile and still guard themselves on the tantu
        session, but nothing routes to them any more: they are dead weight to
        be deleted, not a second half of the app.
      */
      final isCore = loc == '/' || loc.startsWith('/core');

      /*
        Splash belongs to whichever system is the front door, and that is
        slk-core. It is shown only while the stored session is being read —
        which on a cold Android keystore takes a second or two — and resolves
        the moment that finishes.
      */
      if (loc == '/splash') {
        if (core.status == CoreAuthStatus.unknown) return null;
        return core.isSignedIn ? '/' : '/core/sign-in';
      }

      if (isCore) {
        if (core.status == CoreAuthStatus.unknown) return '/splash';
        if (!core.isSignedIn) return loc == '/core/sign-in' ? null : '/core/sign-in';
        // Signed in — the sign-in screen has nothing left to ask.
        if (loc == '/core/sign-in') return '/';
        return null;
      }

      // The retired till screens, still guarding themselves. Unreachable from
      // anywhere in the app; here only until they are deleted.
      if (!auth.isSignedIn) return loc == '/login' ? null : '/login';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      // The home. slk-core's, since tantu was retired.
      GoRoute(path: '/', builder: (_, _) => const CoreHomeScreen()),

      /*
        slk-core — which is to say, the app.

        Still under a /core prefix, which is now only history: it marked these
        out while there was another backend to tell them apart from. Worth
        flattening when the till screens go, and not before, or every path in
        the app changes twice.
      */
      // Routed, not only pushed: it is where the app opens when nobody is
      // signed in, so the redirect above has to be able to name it.
      GoRoute(path: '/core/sign-in', builder: (_, _) => const CoreSignInScreen()),

      // Static before dynamic, so /core/records/new is not read as a record
      // whose id happens to be "new".
      GoRoute(path: '/core/records/new', builder: (_, _) => const NewRecordScreen()),
      GoRoute(path: '/core/records', builder: (_, _) => const RecordsListScreen()),

      // A record that already exists — the same fields the create form asks,
      // seeded from what is there and open to correction. Reached by tapping
      // a row in the catalogue.
      GoRoute(
        path: '/core/records/:id',
        builder: (_, state) => RecordDetailScreen(
          recordId: state.pathParameters['id']!,
        ),
      ),

      /*
        Photographs for a record that already exists.

        Routed rather than only pushed after creating, because the two acts are
        days apart: somebody decides which photographs a saree needs when they
        file it, and somebody takes them when they have the saree and the light.
      */
      GoRoute(
        path: '/core/records/:id/photos',
        builder: (_, state) => RecordPhotosScreen(
          recordId: state.pathParameters['id']!,
          code: state.uri.queryParameters['code'] ?? 'record',
        ),
      ),

      // A saree in one hand, a phone in the other. Not a tab on the catalogue:
      // a different question, asked in a different posture.
      GoRoute(path: '/core/stock', builder: (_, _) => const StockRecordsScreen()),

      // The shot list — what to point a camera at next. Reached from the home
      // as well as from a record, because the two are different errands.
      GoRoute(
        path: '/core/photographs',
        builder: (_, _) => const PhotographsScreen(),
      ),

      // POS + invoices — live.
      GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),
      GoRoute(path: '/pos/checkout', builder: (_, _) => const CheckoutScreen()),
      GoRoute(
        path: '/pos/invoice/:id',
        builder: (_, state) =>
            InvoiceScreen(invoiceId: state.pathParameters['id']!, justCreated: true),
      ),
      GoRoute(
        path: '/invoices/:id',
        builder: (_, state) => InvoiceScreen(invoiceId: state.pathParameters['id']!),
      ),

      // Category ( static paths before /:id so they win )
      GoRoute(path: '/category', builder: (_, _) => const CategoryListScreen()),
      GoRoute(
        path: '/category/new',
        builder: (_, state) => CategoryFormScreen(
          initialParentId: (state.extra as Map?)?['parentId'] as String?,
        ),
      ),
      GoRoute(
        path: '/category/browse/:id',
        builder: (_, state) => CategoryListScreen(parentId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/category/:id/edit',
        builder: (_, state) => CategoryFormScreen(categoryId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/category/:id/photos',
        builder: (_, state) => PhotoGuideScreen(
          categoryId: state.pathParameters['id']!,
          categoryName: (state.extra as Map?)?['name'] as String? ?? 'Design',
        ),
      ),
      GoRoute(
        path: '/category/:id/product-photos',
        builder: (_, state) => VariantPhotosScreen(
          categoryId: state.pathParameters['id']!,
          designName: (state.extra as Map?)?['name'] as String? ?? 'Design',
        ),
      ),

      // Catalogue ( /new before /:id so the static path wins )
      GoRoute(path: '/products', builder: (_, _) => const ProductsScreen()),
      GoRoute(path: '/products/new', builder: (_, _) => const ProductFormScreen()),
      GoRoute(
        path: '/products/:id/edit',
        builder: (_, state) => ProductFormScreen(productId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/products/:id',
        builder: (_, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
      ),

      // Stock
      GoRoute(path: '/stock', builder: (_, _) => const StockScreen()),
      GoRoute(path: '/stock/movements', builder: (_, _) => const MovementsScreen()),

      // Serialized pieces (unique QR per unit)
      GoRoute(path: '/scan', builder: (_, _) => const ScanIdentifyScreen()),
      GoRoute(
        path: '/piece/:tag',
        builder: (_, state) => PieceDetailScreen(tag: state.pathParameters['tag']!),
      ),
      GoRoute(path: '/goods-in', builder: (_, _) => const GoodsInScreen()),
      GoRoute(path: '/tag', builder: (_, _) => const TagPiecesScreen()),
      GoRoute(path: '/pieces/dispatch', builder: (_, _) => const DispatchPiecesScreen()),
      GoRoute(path: '/pieces/sell', builder: (_, _) => const ScanSaleScreen()),
      GoRoute(
        path: '/pieces/receive/:orderId',
        builder: (_, state) => ReceivePiecesScreen(orderId: state.pathParameters['orderId']!),
      ),

      // Transfers ( /new before /:id so the static path wins )
      GoRoute(path: '/transfers', builder: (_, _) => const TransfersScreen()),
      GoRoute(path: '/transfers/new', builder: (_, _) => const NewTransferScreen()),
      GoRoute(
        path: '/transfers/:id',
        builder: (_, state) => TransferDetailScreen(transferId: state.pathParameters['id']!),
      ),

      // Production / Job Work
      GoRoute(path: '/production', builder: (_, _) => const ProductionScreen()),
      GoRoute(path: '/production/batches', builder: (_, _) => const BatchesScreen()),
      GoRoute(
        path: '/production/batches/:id',
        builder: (_, state) => BatchDetailScreen(batchId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/production/dispatch', builder: (_, _) => const DispatchScreen()),
      GoRoute(path: '/production/board', builder: (_, _) => const JobBoardScreen()),
      GoRoute(
        path: '/production/orders/:id',
        builder: (_, state) => ReceiveScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/production/lookup', builder: (_, _) => const PieceLookupScreen()),
      GoRoute(path: '/production/finish', builder: (_, _) => const FinishScreen()),

      // Dashboard, invoices, reports, settings
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
      GoRoute(path: '/invoices', builder: (_, _) => const InvoicesScreen()),
      GoRoute(path: '/reports', builder: (_, _) => const ReconciliationScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/master-data', builder: (_, _) => const MasterDataScreen()),
    ],
  );
});
