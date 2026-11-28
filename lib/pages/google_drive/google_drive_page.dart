import 'dart:async';
import 'dart:io';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kover/generated/l10n/app_localizations.dart';
import 'package:kover/models/drive_item_model.dart';
import 'package:kover/pages/local_library/local_book_card.dart';
import 'package:kover/riverpod/providers/google_drive.dart';
import 'package:kover/riverpod/providers/google_drive_auth.dart';
import 'package:kover/riverpod/providers/router.dart';
import 'package:kover/riverpod/repository/local_library_repository.dart';
import 'package:kover/sync/google_drive_operations.dart';
import 'package:kover/utils/constants/kover_icons.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:kover/utils/extensions/int.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:kover/widgets/util/sliver_bottom_padding.dart';
import 'package:material_ui/material_ui.dart';

/// Browses a Google Drive folder. The root is shown when [folderId] is
/// `root`; folders are pushed as new pages so back goes up one level.
class DriveBrowserPage extends HookConsumerWidget {
  final String folderId;
  final String? title;

  const DriveBrowserPage({super.key, this.folderId = 'root', this.title});

  bool get _isRoot => folderId == 'root';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final auth = ref.watch(googleDriveAuthProvider);
    final searching = useState(false);
    final controller = useTextEditingController();
    final shared = useState(false);

    final signedIn = auth.value is DriveSignedIn;
    final text = useValueListenable(controller).text.trim();
    final search = useDebounced(text, const Duration(milliseconds: 300)) ?? '';

    return Scaffold(
      appBar: AppBar(
        title: searching.value
            ? TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.searchDrive,
                  border: InputBorder.none,
                ),
              )
            : Text(title ?? (_isRoot ? l.sourceGoogleDrive : '')),
        actions: [
          if (signedIn)
            IconButton(
              icon: Icon(
                searching.value ? KoverIcons.close : KoverIcons.search,
              ),
              onPressed: () {
                searching.value = !searching.value;
                if (!searching.value) controller.clear();
              },
            ),
          if (signedIn && _isRoot)
            PopupMenuButton<void>(
              icon: const Icon(KoverIcons.cloud),
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text((auth.value as DriveSignedIn).email),
                ),
                PopupMenuItem(
                  onTap: () =>
                      ref.read(googleDriveAuthProvider.notifier).signOut(),
                  child: Text(l.signOutGoogle),
                ),
              ],
            ),
        ],
      ),
      body: Async(
        asyncValue: auth,
        data: (state) => switch (state) {
          DriveNotSupported() => _Message(
            icon: KoverIcons.cloudOff,
            title: l.driveNotSupported,
          ),
          DriveNotConfigured() => _Message(
            icon: KoverIcons.cloudOff,
            title: l.driveNotConfiguredTitle,
            description: l.driveNotConfiguredDescription,
          ),
          DriveSignedOut() => _SignedOut(),
          DriveSignedIn() => Column(
            children: [
              if (_isRoot && search.isEmpty)
                Padding(
                  padding: LayoutConstants.smallEdgeInsets,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: false, label: Text(l.myDrive)),
                      ButtonSegment(value: true, label: Text(l.sharedWithMe)),
                    ],
                    selected: {shared.value},
                    onSelectionChanged: (value) => shared.value = value.first,
                  ),
                ),
              Expanded(
                child: _DriveList(
                  folderId: shared.value && _isRoot
                      ? GoogleDriveOperations.sharedFolderId
                      : folderId,
                  search: search,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _SignedOut extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final busy = useState(false);

    return _Message(
      icon: KoverIcons.cloud,
      title: l.driveSignedOutTitle,
      description: l.driveSignedOutDescription,
      action: FilledButton(
        onPressed: busy.value
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                busy.value = true;
                try {
                  await ref.read(googleDriveAuthProvider.notifier).signIn();
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                }
                if (context.mounted) busy.value = false;
              },
        child: Text(l.signInWithGoogle),
      ),
    );
  }
}

class _DriveList extends ConsumerWidget {
  final String folderId;
  final String search;

  const _DriveList({required this.folderId, required this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final provider = driveFolderProvider(folderId, search);
    final listing = ref.watch(provider);

    return listing.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        final offline =
            error is SocketException || error is http.ClientException;
        return _Message(
          icon: offline ? KoverIcons.cloudOff : KoverIcons.alert,
          title: offline ? l.driveOffline : l.driveLoadError,
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(provider),
            icon: const Icon(KoverIcons.retry),
            label: Text(l.retry),
          ),
        );
      },
      data: (data) {
        final items = data.items;
        return RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Message(
                    icon: KoverIcons.folder,
                    title: l.driveEmptyFolder,
                  ),
                )
              else
                SliverPadding(
                  padding: LayoutConstants.smallEdgeInsets,
                  sliver: SliverList.separated(
                    itemCount:
                        items.length + (data.nextPageToken == null ? 0 : 1),
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: LayoutConstants.listSpacing),
                    itemBuilder: (context, index) => index == items.length
                        ? _LoadMore(
                            onVisible: ref.read(provider.notifier).loadMore,
                          )
                        : _DriveTile(item: items[index]),
                  ),
                ),
              const SliverBottomPadding(),
            ],
          ),
        );
      },
    );
  }
}

/// Requests the next page as soon as it is built.
class _LoadMore extends HookWidget {
  final Future<void> Function() onVisible;

  const _LoadMore({required this.onVisible});

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      unawaited(onVisible());
      return null;
    }, const []);

    return const Padding(
      padding: LayoutConstants.mediumEdgeInsets,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _DriveTile extends ConsumerWidget {
  final DriveItemModel item;

  const _DriveTile({required this.item});

  Future<void> _openBook(BuildContext context, WidgetRef ref) async {
    final id = await ref
        .read(localLibraryRepositoryProvider)
        .findDriveBookId(item.id);
    if (id != null && context.mounted) openLocalBook(context, id);
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final id = await ref.read(driveDownloadsProvider.notifier).download(item);
    if (id == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l.downloadedBook(item.name)),
          action: SnackBarAction(
            label: l.open,
            onPressed: () {
              if (!context.mounted) return;
              openLocalBook(context, id);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final localizations = MaterialLocalizations.of(context);

    if (item.isFolder) {
      return Card.filled(
        margin: .zero,
        clipBehavior: .antiAlias,
        child: ListTile(
          leading: const Icon(KoverIcons.folder),
          title: Text(item.name, maxLines: 2, overflow: .ellipsis),
          trailing: const Icon(KoverIcons.chevronRight),
          onTap: () => GoogleDriveFolderRoute(
            folderId: item.id,
            name: item.name,
          ).push(context),
        ),
      );
    }

    final downloaded =
        ref.watch(driveDownloadedIdsProvider).value?.contains(item.id) ?? false;
    final state = ref.watch(driveDownloadsProvider)[item.id];

    final (Widget icon, VoidCallback onTap, String? tooltip) = switch (state) {
      DriveDownloading(:final progress) => (
        SizedBox.square(
          dimension: LayoutConstants.mediumIcon,
          child: CircularProgressIndicator(value: progress, strokeWidth: 3),
        ),
        () => ref.read(driveDownloadsProvider.notifier).cancel(item.id),
        l.cancelDownload,
      ),
      DriveDownloadFailed() => (
        Icon(
          KoverIcons.downloadFailed,
          color: Theme.of(context).colorScheme.error,
        ),
        () => _download(context, ref),
        l.retry,
      ),
      null when downloaded => (
        Icon(KoverIcons.check, color: Theme.of(context).colorScheme.primary),
        () => _openBook(context, ref),
        l.open,
      ),
      null => (
        const Icon(KoverIcons.download),
        () => _download(context, ref),
        null,
      ),
    };

    final subtitle = [
      if (item.size != null) item.size!.prettyBytes(),
      if (item.modifiedTime != null)
        localizations.formatMediumDate(item.modifiedTime!.toLocal()),
    ].join(' · ');

    return Card.filled(
      margin: .zero,
      clipBehavior: .antiAlias,
      child: ListTile(
        leading: Icon(switch (item.format) {
          .epub => KoverIcons.epubFormat,
          .pdf => KoverIcons.pdfFormat,
          .archive => KoverIcons.archiveFormat,
          _ => KoverIcons.unknownFormat,
        }),
        title: Text(item.name, maxLines: 2, overflow: .ellipsis),
        subtitle: subtitle.isEmpty
            ? (state is DriveDownloadFailed
                  ? Text(state.message, maxLines: 1, overflow: .ellipsis)
                  : null)
            : Text(subtitle),
        trailing: IconButton(
          icon: icon,
          tooltip: tooltip,
          onPressed: onTap,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  const _Message({
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: LayoutConstants.mediumEdgeInsets,
        child: Column(
          mainAxisSize: .min,
          children: [
            Icon(
              icon,
              size: LayoutConstants.largestIcon,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: LayoutConstants.mediumPadding),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: .bold),
              textAlign: .center,
            ),
            if (description != null) ...[
              const SizedBox(height: LayoutConstants.smallerPadding),
              Text(description!, textAlign: .center),
            ],
            if (action != null) ...[
              const SizedBox(height: LayoutConstants.mediumPadding),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
