import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../models/core.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_view.dart';
import '../../widgets/picker_field.dart';
import 'core_auth.dart';
import 'core_photos.dart';
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
  const NewRecordScreen({super.key, this.seedFrom});

  /// An existing record to copy the design from — every attribute, the craft
  /// and details answers, and which photographs are wanted.
  ///
  /// Colour, prices, name and opening stock are left for the form to ask
  /// fresh: those are what make one colourway different from the next under
  /// the same design (see [RecordFormFields._resetForNext] downstream, which
  /// treats the same split the other way — repeats kept, colourway cleared).
  /// Filing five colours of one saree should mean answering "which colour"
  /// five times, not the other thirty questions five times too.
  final CoreRecordDetail? seedFrom;

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

  /// Slot id → a photograph already taken for it. Purely local until the
  /// record exists — a photograph belongs to a colourway, and there is
  /// nowhere to send one before there is a colourway. Sent the moment
  /// Create succeeds, then cleared: the next record (see [_resetForNext])
  /// is a new intent and starts its own shot list.
  final Map<String, File> _capturedPhotos = {};

  @override
  void dispose() {
    disposeFormFields();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto(CoreOption slot) async {
    final storage = ref.read(coreStorageProvider).valueOrNull;
    if (storage != null && !storage.ready) {
      showError(
        context,
        'Image storage is not set up on the server. Missing '
        '${storage.missing.join(", ")}.',
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.p.surface2,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('Photograph the ${slot.label.toLowerCase()}'),
              onTap: () => Navigator.pop(sheet, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from the gallery'),
              onTap: () => Navigator.pop(sheet, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    // Same limits RecordPhotosScreen uses on the file it eventually sends.
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() => _capturedPhotos[slot.id] = File(picked.path));
  }

  void _removeCapturedPhoto(CoreOption slot) =>
      setState(() => _capturedPhotos.remove(slot.id));

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

      /*
        Sent now that there is finally somewhere to send them — a photograph
        belongs to a colourway, and this is the first moment one exists.
        One failure must not lose another: each slot is its own try, and
        what did not go through is named rather than silently dropped, so
        the next stop is the Photographs screen rather than a shrug.
      */
      final uploaded = <String>{};
      final failed = <String>[];
      if (_capturedPhotos.isNotEmpty) {
        final photos = ref.read(corePhotosProvider);
        for (final entry in _capturedPhotos.entries) {
          try {
            await photos.upload(
              recordId: id,
              slotId: entry.key,
              file: entry.value,
            );
            uploaded.add(entry.key);
          } catch (_) {
            failed.add(labelOf(options, 'image_slot', entry.key) ?? 'a photograph');
          }
        }
        _capturedPhotos.clear();
      }

      if (!mounted) return;

      // One snackbar, not two — showError's hideCurrentSnackBar() would
      // otherwise dismiss showOk's before anyone read it.
      final parts = [code == null ? 'Record created.' : 'Created $code.'];
      if (uploaded.isNotEmpty) {
        parts.add(
          '${uploaded.length} photograph${uploaded.length == 1 ? '' : 's'} saved.',
        );
      }
      if (failed.isNotEmpty) {
        parts.add('${failed.join(", ")} did not upload — retake from the record.');
      }
      final message = parts.join(' ');
      failed.isEmpty ? showOk(context, message) : showError(context, message);

      // Only what is still missing sends anyone straight to the camera —
      // a capture made just now already covered that slot.
      final slots = imageSlots.any((s) => !uploaded.contains(s));
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
    // Watched here purely to start the check early — asked again, cheaply,
    // from cache, the moment somebody actually taps to take a photo.
    ref.watch(coreStorageProvider);

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
                final seed = widget.seedFrom;
                if (seed != null) {
                  attrs.addAll(seed.attributes);
                  descriptors = List.of(seed.descriptors);
                  imageSlots = [
                    for (final image in seed.images)
                      if (image.slotId != null) image.slotId!,
                  ];
                } else {
                  attrs.addAll(defaultAttributes(opts));
                  // Saree is the vocabulary's own default product type, so
                  // the common case never touches setProductType at all —
                  // the form simply opens already on it. Without this, the
                  // "tick all four" convenience only ever fired for someone
                  // who actively picked Saree from a different starting
                  // type.
                  final productTypeId = attrs['productType'];
                  if (productTypeId != null &&
                      labelOf(opts, 'product_type', productTypeId) == 'Saree') {
                    imageSlots = sareeDefaultImageSlots(opts, productTypeId);
                  }
                }
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
            if (widget.seedFrom != null) ...[
              RecordNote(
                'Copied from ${widget.seedFrom!.code} — same design, craft '
                'and photo slots. Colour, price and name are still this '
                "colourway's own.",
              ),
              const SizedBox(height: 4),
            ],
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
        buildImagesTab(
          o,
          home,
          capturedPhotos: _capturedPhotos,
          onCapture: _capturePhoto,
          onRemoveCapture: _removeCapturedPhoto,
        ),
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
