import 'package:kover/utils/constants/kover_icons.dart';
import 'package:material_ui/material_ui.dart';

/// Switches a list between grid and list layout.
class ListLayoutToggleButton extends StatelessWidget {
  final bool isGrid;
  final VoidCallback onPressed;

  const ListLayoutToggleButton({
    super.key,
    required this.isGrid,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(isGrid ? KoverIcons.list : KoverIcons.grid),
      onPressed: onPressed,
    );
  }
}
