import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/recording_item.dart';
import '../theme/app_theme.dart';

class ShareSheet extends StatefulWidget {
  final RecordingItem recording;

  const ShareSheet({
    super.key,
    required this.recording,
  });

  static Future<void> show(BuildContext context, {required RecordingItem recording}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet(recording: recording),
    );
  }

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  bool _copied = false;
  String _access = 'anyone'; // 'anyone' | 'private'
  String _expiry = 'never'; // 'never' | '24h' | '7d'

  String get _shareUrl =>
      widget.recording.shareUrl ??
      'https://share.qamate.io/r/${widget.recording.uploadId ?? widget.recording.id}';

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _shareUrl));
    setState(() => _copied = true);
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.successEmerald, size: 18),
            SizedBox(width: 8),
            Text('Streaming link copied to clipboard'),
          ],
        ),
        duration: Duration(milliseconds: 2000),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surface : AppTheme.lightSurface;
    final surfaceSubtle = isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight;
    final borderColor = isDark ? AppTheme.border : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.lightTextMuted;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: borderColor, width: 1),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Share Recording',
                style: AppTheme.titleStyle.copyWith(color: textColor),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stream URL box with instant Copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: surfaceSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, size: 20, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _shareUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const ValueKey('share_sheet_copy_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _copied ? AppTheme.successEmerald : AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(80, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  onPressed: _copyUrl,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _copied ? 'Copied' : 'Copy',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Access Permissions
          Text(
            'ACCESS PERMISSION',
            style: AppTheme.captionStyle.copyWith(
              color: textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildChoiceChip(
                label: 'Anyone with link',
                icon: Icons.public_rounded,
                isSelected: _access == 'anyone',
                isDark: isDark,
                onTap: () => setState(() => _access = 'anyone'),
              ),
              const SizedBox(width: 8),
              _buildChoiceChip(
                label: 'Private / Team',
                icon: Icons.lock_outline_rounded,
                isSelected: _access == 'private',
                isDark: isDark,
                onTap: () => setState(() => _access = 'private'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Expiry options
          Text(
            'EXPIRY',
            style: AppTheme.captionStyle.copyWith(
              color: textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildChoiceChip(
                label: 'Never',
                icon: Icons.all_inclusive_rounded,
                isSelected: _expiry == 'never',
                isDark: isDark,
                onTap: () => setState(() => _expiry = 'never'),
              ),
              const SizedBox(width: 8),
              _buildChoiceChip(
                label: '24 Hours',
                icon: Icons.timer_outlined,
                isSelected: _expiry == '24h',
                isDark: isDark,
                onTap: () => setState(() => _expiry = '24h'),
              ),
              const SizedBox(width: 8),
              _buildChoiceChip(
                label: '7 Days',
                icon: Icons.calendar_today_rounded,
                isSelected: _expiry == '7d',
                isDark: isDark,
                onTap: () => setState(() => _expiry = '7d'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Native Share Pill Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Open System Share Sheet'),
              onPressed: () {
                Navigator.pop(context);
                // ignore: deprecated_member_use
                Share.share(
                  'Watch my screen recording: $_shareUrl',
                  subject: widget.recording.fileName,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppTheme.primary.withValues(alpha: 0.2) : const Color(0xFFEEF2FF))
                : (isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primary
                  : (isDark ? AppTheme.border : AppTheme.lightBorder),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? AppTheme.primary
                    : (isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.captionStyle.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppTheme.primary
                        : (isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
