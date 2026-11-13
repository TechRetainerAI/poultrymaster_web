// Pieces shared by Generic Deliveries, Drivers and Routes (the web's three
// pages under app/generic-deliveries, generic-drivers and generic-routes).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/ui/inputs.dart';
import '../../poultry/trackers/tracker_widgets.dart';
import 'generic_places.dart';

import 'package:poultrycore_mobile/design/tone.dart';

const genericTransportModes = ['Car', 'Motorcycle', 'Bicycle', 'Truck', 'Van', 'Tricycle', 'On Foot', 'Other'];
const genericDeliveryUnits = ['Piece', 'Unit', 'Kg', 'Bag', 'Box', 'Crate', 'Tray', 'Dozen', 'Bundle', 'Litre'];

/// A form row: the label over its input (the web's FormField).
Widget dField(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (label.isNotEmpty) ...[
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate700)),
          const SizedBox(height: 6),
        ],
        child,
      ]),
    );

Widget dNumber(TextEditingController c, {Key? key, ValueChanged<String>? onChanged}) => AppInput(
      key: key,
      controller: c,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    );

num dNum(TextEditingController c) => num.tryParse(c.text) ?? 0;

/// Active / Inactive, as the Drivers and Routes lists show it.
Widget activeBadge(bool on) =>
    on ? const TBadge('Active', bg: TColors.emerald100, fg: TColors.emerald700) : const TBadge('Inactive', bg: TColors.slate100, fg: TColors.slate600);

/// A place box with its "My location" and "Search" buttons. [gpsFirst] is the
/// web's button order for that box. [onPlace] gets the found place, so a
/// caller can work out the travel time.
class PlaceField extends StatefulWidget {
  const PlaceField({
    super.key,
    required this.controller,
    required this.hint,
    required this.keyPrefix,
    this.gpsFirst = true,
    this.onPlace,
    this.onBusy,
    this.busy = false,
  });
  final TextEditingController controller;
  final String hint, keyPrefix;
  final bool gpsFirst;
  final void Function(Place p)? onPlace;
  final ValueChanged<bool>? onBusy;

  /// The page's shared "locating" flag: every place button waits for it.
  final bool busy;
  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  void _busy(bool b) => widget.onBusy?.call(b);

  Future<void> _gps() async {
    _busy(true);
    try {
      final p = await GenericPlaces.myLocation();
      widget.controller.text = p.name;
      widget.onPlace?.call(p);
    } catch (e) {
      if (mounted) trackerToast(context, 'Could not get location', description: '$e', error: true);
    }
    _busy(false);
  }

  Future<void> _search() async {
    final q = widget.controller.text;
    if (q.trim().isEmpty) return trackerToast(context, 'Type a location name first', error: true);
    _busy(true);
    try {
      final p = await GenericPlaces.search(q);
      if (p != null) {
        widget.controller.text = p.name;
        widget.onPlace?.call(p);
      } else if (mounted) {
        trackerToast(context, 'Location not found', description: 'Could not find "$q".', error: true);
      }
    } catch (_) {
      if (mounted) trackerToast(context, 'Search failed', error: true);
    }
    _busy(false);
  }

  @override
  Widget build(BuildContext context) {
    final gps = IconButton.outlined(
      key: ValueKey('${widget.keyPrefix}-gps'),
      tooltip: 'My location',
      onPressed: widget.busy ? null : _gps,
      icon: const Icon(Icons.my_location, size: 18),
    );
    final search = IconButton.outlined(
      key: ValueKey('${widget.keyPrefix}-search'),
      tooltip: 'Search',
      onPressed: widget.busy ? null : _search,
      icon: const Icon(Icons.search, size: 18),
    );
    return Row(children: [
      Expanded(child: AppInput(key: ValueKey('${widget.keyPrefix}-text'), controller: widget.controller, hintText: widget.hint)),
      const SizedBox(width: 4),
      if (widget.gpsFirst) ...[gps, search] else ...[search, gps],
    ]);
  }
}

/// The page's buttons under a dialog: Cancel and the action.
List<Widget> dialogButtons(BuildContext context, {required String label, required bool saving, required VoidCallback onSave, Key? saveKey}) => [
      OutlinedButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        key: saveKey,
        onPressed: saving ? null : onSave,
        child: saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      ),
    ];

/// The web's page header: an emerald icon, the title and its subtitle.
Widget dHeader(IconData icon, String title, String blurb) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 22, color: const Tone.fg(0xFF059669)),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: TColors.slate900))),
      ]),
      Text(blurb, style: const TextStyle(fontSize: 12, color: TColors.slate500)),
    ]);

/// The web's `grid-cols-2` summary cards: two to a row, each row as tall as
/// its tallest card.
Widget kpiGrid(List<Widget> cards) => Column(children: [
      for (var i = 0; i < cards.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
            ]),
          ),
        ),
    ]);
