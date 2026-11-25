import 'dart:typed_data';

import 'package:deskpilot/look.dart';
import 'package:deskpilot/pictures.dart';
import 'package:flutter/material.dart';

/// A titled row of chips to pick one of [choices] (value to its name).
class OptionChips extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.title,
    required this.choices,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final Map<String?, String> choices;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(
        title,
        style: TextStyle(color: DeckLook.of(context).muted, fontSize: 12),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final MapEntry(:key, :value) in choices.entries)
            ChoiceChip(
              label: Text(value),
              selected: selected == key,
              onSelected: (_) => onSelect(key),
            ),
        ],
      ),
    ],
  );
}

/// A titled row of small square choices, like icons or colors.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({super.key, required this.title, required this.choices});

  final String title;
  final List<ChoiceSquare> choices;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(
        title,
        style: TextStyle(color: DeckLook.of(context).muted, fontSize: 12),
      ),
      Wrap(spacing: 6, runSpacing: 6, children: choices),
    ],
  );
}

class ChoiceSquare extends StatelessWidget {
  const ChoiceSquare({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    child: Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeckLook.of(context).background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? DeckLook.of(context).text
                  : DeckLook.of(context).cardBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// Choose, change or remove a picture: a button's own or a page's wallpaper.
class PictureField extends StatefulWidget {
  const PictureField({
    super.key,
    required this.noun,
    required this.wallpaper,
    required this.picture,
    required this.chosen,
    required this.pick,
    required this.upload,
    required this.onChanged,
  });

  final String noun;
  final bool wallpaper;
  final Uint8List? picture;
  final bool chosen;
  final PickPicture pick;
  final String Function(Uint8List) upload;

  /// The new picture's id and bytes, or nulls when it was removed.
  final void Function(String? id, Uint8List? bytes) onChanged;

  @override
  State<PictureField> createState() => _PictureFieldState();
}

class _PictureFieldState extends State<PictureField> {
  String? _problem;

  Future<void> _choose() async {
    final bytes = await widget.pick(wallpaper: widget.wallpaper);
    if (bytes == null || !mounted) return;
    if (bytes.length > maxPictureBytes) {
      setState(() => _problem = 'That picture is too big. Pick a smaller one.');
      return;
    }
    setState(() => _problem = null);
    widget.onChanged(widget.upload(bytes), bytes);
  }

  @override
  Widget build(BuildContext context) {
    final picture = widget.picture;
    final problem = _problem;
    final noun = widget.noun;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          noun[0].toUpperCase() + noun.substring(1),
          style: TextStyle(color: DeckLook.of(context).muted, fontSize: 12),
        ),
        Row(
          spacing: 10,
          children: [
            if (picture != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 48,
                  child: Image.memory(
                    picture,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _choose,
              icon: const Icon(Icons.image_rounded),
              label: Text(widget.chosen ? 'Change $noun' : 'Choose $noun'),
            ),
            if (widget.chosen)
              TextButton(
                onPressed: () => widget.onChanged(null, null),
                child: const Text('Remove'),
              ),
          ],
        ),
        if (problem != null)
          Text(problem, style: TextStyle(color: deckColors['red'])),
      ],
    );
  }
}
