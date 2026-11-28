import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/pages/settings/appearance_settings.dart';
import 'package:kover/pages/settings/credentials_settings.dart';
import 'package:kover/pages/settings/data_management_settings.dart';
import 'package:kover/pages/settings/drive_settings.dart';
import 'package:kover/pages/settings/general_settings.dart';
import 'package:kover/pages/settings/keybinds_settings.dart';
import 'package:kover/pages/settings/settings_section.dart';
import 'package:kover/pages/settings/version_label.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/widgets/util/sliver_adaptive_padding.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';

class SettingsPage extends ConsumerWidget {
  final SettingsSection section;

  const SettingsPage({super.key, this.section = .general});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    return DefaultTabController(
      length: SettingsSection.values.length,
      initialIndex: section.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.settings),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: .start,
            tabs: [
              Tab(text: l.general),
              Tab(text: l.sourceKavita),
              Tab(text: l.sourceGoogleDrive),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SettingsTab(
              children: [
                GeneralSettings(),
                AppearanceSettings(),
                KeybindsSettings(),
                StorageSettings(),
                Center(child: VersionLabel()),
              ],
            ),
            _SettingsTab(
              children: [
                CredentialsSettings(),
                DataManagementSettings(),
              ],
            ),
            _SettingsTab(children: [DriveSettings()]),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  final List<Widget> children;

  const _SettingsTab({required this.children});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAdaptivePadding(
          padding: const .fromLTRB(
            LayoutConstants.mediumPadding,
            LayoutConstants.mediumPadding,
            LayoutConstants.mediumPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: LayoutConstants.listSpacing,
              children: children,
            ),
          ),
        ),
        const SliverBottomPadding(),
      ],
    );
  }
}
