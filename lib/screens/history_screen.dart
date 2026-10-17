import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/recording_item.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';
import 'preview_screen.dart';

enum LibraryFilter { all, onDevice, uploaded }

class HistoryScreen extends StatefulWidget {
  final bool isTab;

  const HistoryScreen({super.key, this.isTab = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  LibraryFilter _activeFilter = LibraryFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecordingItem> _filterItems(List<RecordingItem> items) {
    return items.where((item) {
      if (_searchQuery.isNotEmpty) {
        final matches = item.fileName
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            (item.uploadId != null &&
                item.uploadId!
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()));
        if (!matches) return false;
      }

      switch (_activeFilter) {
        case LibraryFilter.all:
          return true;
        case LibraryFilter.onDevice:
          return !item.isUploaded;
        case LibraryFilter.uploaded:
          return item.isUploaded;
      }
    }).toList();
  }

  Map<String, List<RecordingItem>> _groupItems(List<RecordingItem> items) {
    final Map<String, List<RecordingItem>> groups = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final item in items) {
      final date = DateTime(
        item.createdAt.year,
        item.createdAt.month,
        item.createdAt.day,
      );

      String groupKey;
      if (date == today) {
        groupKey = 'Today';
      } else if (date == yesterday) {
        groupKey = 'Yesterday';
      } else {
        groupKey = DateFormat('MMMM d').format(item.createdAt);
      }

      groups.putIfAbsent(groupKey, () => []).add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HistoryProvider>(
      builder: (context, historyProv, _) {
        final allItems = historyProv.items;
        final onDeviceCount = allItems.where((i) => !i.isUploaded).length;
        final uploadedCount = allItems.where((i) => i.isUploaded).length;
        final filteredItems = _filterItems(allItems);
        final groupedItems = _groupItems(filteredItems);

        final bodyContent = historyProv.isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppTheme.primary),
                ),
              )
            : CustomScrollView(
                slivers: [
                  // Search Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search recordings',
                            hintStyle: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppTheme.textSecondary,
                              size: 20,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      color: AppTheme.textMuted,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                          ),
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                        ),
                      ),
                    ),
                  ),

                  // Segmented Filter Chips
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          _buildFilterChip(
                            label: 'All ${allItems.length}',
                            filter: LibraryFilter.all,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'On device $onDeviceCount',
                            filter: LibraryFilter.onDevice,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'Uploaded $uploadedCount',
                            filter: LibraryFilter.uploaded,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Empty State or Grouped Recordings
                  if (allItems.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(context),
                    )
                  else if (filteredItems.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No recordings match "$_searchQuery"',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    for (final entry in groupedItems.entries) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textSecondary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = entry.value[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildRecordingCard(
                                  context,
                                  item,
                                  historyProv,
                                ),
                              );
                            },
                            childCount: entry.value.length,
                          ),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ],
              );

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: widget.isTab
                ? null
                : IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
            title: const Text(
              'Library',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isSelectionMode
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  color: _isSelectionMode ? AppTheme.primary : Colors.white,
                  size: 22,
                ),
                tooltip: 'Select items',
                onPressed: () {
                  setState(() {
                    _isSelectionMode = !_isSelectionMode;
                    if (!_isSelectionMode) _selectedIds.clear();
                  });
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(child: bodyContent),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required LibraryFilter filter,
  }) {
    final isSelected = _activeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.white : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F121C) : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingCard(
    BuildContext context,
    RecordingItem item,
    HistoryProvider historyProv,
  ) {
    final timeStr = DateFormat('h:mm a').format(item.createdAt);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (_selectedIds.contains(item.id)) {
              _selectedIds.remove(item.id);
            } else {
              _selectedIds.add(item.id);
            }
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PreviewScreen(recording: item),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _selectedIds.contains(item.id)
                ? AppTheme.primary
                : AppTheme.border,
            width: _selectedIds.contains(item.id) ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Thumbnail preview with duration badge
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 68,
                height: 68,
                color: const Color(0xFF222C44),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (item.hasThumbnail)
                      Image.file(
                        File(item.thumbnailPath!),
                        fit: BoxFit.cover,
                        width: 68,
                        height: 68,
                      )
                    else
                      // Abstract preview mockup placeholder
                      Container(
                        color: const Color(0xFF1B2338),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              height: 6,
                              width: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF324063),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: 6,
                              width: 26,
                              decoration: BoxDecoration(
                                color: const Color(0xFF283452),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Duration Badge
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.formattedDuration,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Information Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$timeStr · ${item.formattedFileSize}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Cloud / Device status badge
                  if (item.isUploaded)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.cloud_done_rounded,
                          size: 14,
                          color: AppTheme.successEmerald,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Uploaded',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.successEmerald,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.smartphone_rounded,
                          size: 13,
                          color: AppTheme.textMuted,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'On device',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Trailing options menu
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_horiz_rounded,
                color: AppTheme.textSecondary,
              ),
              color: AppTheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppTheme.border),
              ),
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'preview',
                  child: Row(
                    children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 10),
                      Text('Play & Trim', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: AppTheme.recordRed, size: 18),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: AppTheme.recordRed)),
                    ],
                  ),
                ),
              ],
              onSelected: (val) async {
                if (val == 'preview') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PreviewScreen(recording: item),
                    ),
                  );
                } else if (val == 'delete') {
                  await historyProv.deleteRecording(item.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surfaceContainer,
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(
                Icons.video_library_outlined,
                size: 44,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Recordings Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Captured videos will show up here with size and cloud sync status.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
