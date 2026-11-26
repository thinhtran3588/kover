import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/enums/reading_source.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:material_ui/material_ui.dart';

extension ReadingSourceExtension on ReadingSource {
  IconData get icon => switch (this) {
    .kavita => KoverIcons.library,
    .googleDrive => KoverIcons.cloud,
    .device => KoverIcons.device,
  };

  String getLabel(AppLocalizations l) => switch (this) {
    .kavita => l.sourceKavita,
    .googleDrive => l.sourceGoogleDrive,
    .device => l.onThisDevice,
  };
}
