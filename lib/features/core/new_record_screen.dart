import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import 'core_auth.dart';
import 'core_sign_in_screen.dart';
import 'record_fields.dart';
import 'record_form_fields.dart';
import 'record_photos_screen.dart';

/// A new record, with every question the web editor asks.
///
/// Field-for-field parity with /records, laid out as tabs rather than a
/// wizard: the web editor's steps assume a mouse and a wide screen, and a
/// phone that hides Prices three taps deep is a phone somebody stops using.
///
/// The rules are ported, not re-invented — which matters more than the fields.
/// Product Type narrows to the industry and switches list entirely for the
/// home one; Motif narrows to its category; Textile Material narrows to the
/// fibre and falls through to the unparented ten when that fibre names none;
/// Unit of Measure is shown and never asked. Getting a rule slightly different
/// here from the web is how two people filing the same saree produce two
/// different records.
///
/// The fields themselves live in [RecordFormFields], shared with
/// [RecordDetailScreen] — this screen supplies what is particular to
/// creating: opening stock instead of a ledger, an idempotency key, and a
/// reset for the next delivery rather than a save that returns to a record.
class NewRecordScreen extends ConsumerStatefulWidget {
  const NewRecordScreen({super.key});

  @override
  ConsumerState<NewRecordScreen> createState() => _NewRecordScreenState();
}

class _NewRecordScreenState extends ConsumerState<NewRecordScreen>
    with RecordFormFields {
  String? _location;
  final _qty = TextEditingController();

  bool _defaultsApplied = false;
  bool _busy = false;

  /// Held so the Basic tab can name who is filing, without threading the
  /// actor through five layers of builder to reach one chip.
  CoreActor? _actor;

  /// The name of the save in progress.
  ///
  /// Minted on the first Create and kept for every retry of the same draft, so
  /// a lost answer followed by a second press is recognised as the same intent
  /// rather than becoming a second record. Cleared only on success, which is
  /// what makes the next record a genuinely new one.
  ///
  /// Minting it per tap instead would be the bug: that is precisely how
  /// SAR-GEN-COT-0009 came to exist.
  String? _saveKey;

  @override
  void dispose() {
    disposeFormFields();
    _qty.dispose();
    super.dispose();
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  Future<void> _submit(CoreOptions options) async {
    // Kept across retries, minted only when there is no save in flight.
    final key = _saveKey ??= idempotencyKey();

    setState(() {
      _busy = true;
      fieldErrors = const {};
    });

    try {
      final api = ref.read(coreApiProvider);

      final created = await api.post('/records', headers: {
        'Idempotency-Key': key,
      }, body: {
        'attributes': attributesForSubmit(options),
        'descriptors': descriptors,
        'colourId': colourId,
        'secondaryColourId': secondaryColourId,
        'prices': {
          for (final p in priceKinds) p.key: prices[p.key]!.text.trim(),
        },
        'openingStock': [
          if (_location != null && _qty.text.trim().isNotEmpty)
            {'locationId': _location, 'qty': _qty.text.trim()},
        ],
        'imageSlots': imageSlots,
        'notes': notesField.text.trim(),
        'name': nameIsCustom ? nameField.text.trim() : '',
        'nameIsCustom': nameIsCustom,
      });

      final answer = (created as Map).cast<String, dynamic>();
      final id = answer['id'] as String;

      /*
        The product code — 300042 — not the design code.

        The design code is internal and repeats; it describes what somebody
        answered on this form, and two people filing the same saree will mint
        different ones. The product code is the consignment that just arrived,
        and it is the number on the paperwork in their hands. Confirming with
        the design code told them the one thing they would never be asked
        about.

        It comes back from the create itself. This used to create, then GET
        the record, then take `consignments[0]` — and against production that
        second request returned an empty list, so a real submission announced
        "Created SAR-GEN-COT-0002". Reading it from the write cannot race.
      */
      final minted = [
        for (final c in (answer['productCodes'] as List? ?? const [])) '$c',
      ];

      String? code = minted.isEmpty ? null : minted.join(', ');

      /*
        Nothing minted, so ask.

        Two ways to get here and they mean different things. A retry answered
        from the idempotency store carries no codes even though the first
        attempt minted some — the record has consignments and this finds them.
        A record filed before any stock arrived has none to find, and then the
        design code is all there is to say.
      */
      if (code == null) {
        try {
          final record =
              ((await api.get('/records/$id')) as Map).cast<String, dynamic>();

          final consignments = record['consignments'] as List? ?? const [];

          code = consignments.isEmpty
              ? record['code'] as String?
              : ((consignments.first as Map).cast<String, dynamic>()['code']
                  as String?);
        } catch (_) {
          // The record exists either way.
        }
      }

      if (!mounted) return;

      showOk(context, code == null ? 'Record created.' : 'Created $code.');

      final slots = imageSlots.isNotEmpty;
      _resetForNext();

      /*
        Straight on to the camera, if this record asked for photographs.

        The record now exists, which is the only reason it could not be done
        before — a photograph belongs to a colourway. Making somebody find the
        record again afterwards is how shot lists stay empty.
      */
      if (slots && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecordPhotosScreen(
              recordId: id,
              code: code ?? 'new record',
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.errors.isNotEmpty) setState(() => fieldErrors = e.errors);
      showError(context, e);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Keep what repeats, clear what does not.
  ///
  /// A delivery is ten of nearly the same thing: same taxonomy, same location,
  /// different colour, price and count. Clearing everything would make the
  /// second record as slow as the first.
  void _resetForNext() {
    setState(() {
      // The save that key named is finished. The next record is a new intent
      // and gets a new name; keeping this one would make it a "duplicate" of
      // the record just created and be refused.
      _saveKey = null;
      colourId = null;
      secondaryColourId = null;
      for (final c in prices.values) {
        c.clear();
      }
      _qty.clear();
      notesField.clear();
      nameField.clear();
      nameIsCustom = false;
      fieldErrors = const {};
    });
  }

  // ── Building ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(coreAuthProvider);
    if (!auth.isSignedIn) return const _SignInPrompt();

    final options = ref.watch(coreOptionsProvider);
    final locations = ref.watch(coreLocationsProvider);

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: context.p.surface1,
        appBar: AppBar(
          title: const Text('Product Management'),
          actions: [
            IconButton(
              tooltip: 'Sign out of slk-core',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(coreAuthProvider.notifier).signOut(),
            ),
          ],
          /*
            Six fixed tabs, none of them scrollable.

            A scrollable bar put Basic off the left edge — the first tab, on a
            form that opens on it — and even fixed that, a bar you have to
            scroll hides half the form from somebody who does not know it is
            there. Six short labels fit, so the whole shape of the record is
            visible at a glance.

            "Craft" rather than the web's "Craft & Design", for the same
            reason: the tab has to fit a sixth of a phone.
          */
          bottom: TabBar(
            /*
              Colours stated, not inherited.

              The app defines no TabBarTheme, so Material 3 defaults the
              selected label to colorScheme.primary — which is this app bar's
              own terracotta. The selected tab painted itself onto its own
              background and vanished, and since the form opens on Basic, the
              tab that vanished was the one you were looking at.
            */
            labelColor: context.p.onAppBar,
            unselectedLabelColor: context.p.onAppBar.withValues(alpha: 0.72),
            indicatorColor: context.p.onAppBar,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 12.5),
            tabs: const [
              Tab(text: 'Basic'),
              Tab(text: 'Craft'),
              Tab(text: 'Details'),
              Tab(text: 'Prices'),
              Tab(text: 'Images'),
              Tab(text: 'Stock'),
            ],
          ),
        ),
        body: AsyncView<CoreOptions>(
          value: options,
          onRetry: () => ref.invalidate(coreOptionsProvider),
          data: (opts) => AsyncView<List<CoreLocation>>(
            value: locations,
            onRetry: () => ref.invalidate(coreLocationsProvider),
            data: (places) {
              // Applied once, after the vocabulary arrives — Clothing, Saree
              // and the rest, so the common case is already filled in.
              if (!_defaultsApplied) {
                _defaultsApplied = true;
                attrs.addAll(defaultAttributes(opts));
              }

              return _tabs(opts, places, auth.actor!);
            },
          ),
        ),
        bottomNavigationBar: RecordSaveBar(
          busy: _busy,
          errors: fieldErrors,
          label: 'Create record',
          onSave: () {
            final opts = options.value;
            if (opts != null) _submit(opts);
          },
        ),
      ),
    );
  }

  Widget _tabs(CoreOptions o, List<CoreLocation> places, CoreActor actor) {
    _actor = actor;

    final industry = labelOf(o, 'industry', attrs['industry']);
    final home = isHomeIndustry(industry);

    final productType = home
        ? labelOf(o, 'home_product_type', attrs['homeProductType'])
        : labelOf(o, 'product_type', attrs['productType']);

    final isSaree = !home && productType == 'Saree';

    // Which sub types a product type has is data, not code — a saree's are its
    // layouts, a garment's its cuts, and a type with none is not asked.
    final subTypes = narrow(o['garment_type'], attrs['productType']);
    final hasSubTypes = !home && subTypes.isNotEmpty;

    final isGarment = hasSubTypes && !isSaree && (attrs['garmentType'] != null);

    final withBlouse =
        labelOf(o, 'garment_type', attrs['garmentType']) == 'With Blouse';

    final uom = labelOf(o, 'uom', attrs['uom']);
    final craft = labelOf(o, 'craft_technique', attrs['craftTechnique']);

    return TabBarView(
      children: [
        buildBasicTab(
          o: o,
          home: home,
          hasSubTypes: hasSubTypes,
          isSaree: isSaree,
          isGarment: isGarment,
          uom: uom,
          header: [
            // Who is filing this. On a shared floor phone that is not
            // obvious, and every movement this record opens with is
            // recorded against them.
            SignedInActor(actor: _actor!),
            const SizedBox(height: 14),
          ],
          footer: [
            const SizedBox(height: 12),
            Text(
              'The design code is built from product type, region and fibre '
              'when you save.',
              style: TextStyle(fontSize: 12, color: context.p.textMuted),
            ),
          ],
        ),
        buildCraftTab(o, craft),
        buildDetailsTab(o, isSaree, withBlouse),
        buildPricesTab(uom),
        buildImagesTab(o, home),
        _stock(places, uom),
      ],
    );
  }

  // ── Stock ─────────────────────────────────────────────────────────────────

  Widget _stock(List<CoreLocation> places, String? uom) {
    final internal = [for (final l in places) if (l.isInternal) l];

    return RecordTabBody(
      children: [
        const RecordSectionHeading('Opening stock'),
        Text(
          'What is in the building now. Recorded as arriving from Production, '
          'so the count can be explained a year from now.',
          style: TextStyle(fontSize: 12, color: context.p.textSecondary),
        ),
        const SizedBox(height: 12),
        RecordFieldWrap(
          child: PickerField(
            label: 'Where',
            value: _location,
            allowClear: true,
            options: [for (final l in internal) PickerOption(l.id, l.name)],
            onChanged: (v) => setState(() => _location = v),
          ),
        ),
        RecordFieldWrap(
          error: fieldErrors['quantity'],
          child: TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: uom == null ? 'How many' : 'How many ($uom)',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        RecordNote(
          'Moving stock that already exists is a transfer, which is a '
          'different act and gets its own screen.',
        ),
      ],
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.p.surface1,
      appBar: AppBar(title: const Text('Product Management')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This screen uses the stock system, which signs in separately.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.p.textSecondary),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CoreSignInScreen(),
                  ),
                ),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
