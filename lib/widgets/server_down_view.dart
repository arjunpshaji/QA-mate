import 'package:flutter/material.dart';
import '../providers/upload_provider.dart';
import '../theme/app_theme.dart';

class ServerDownView extends StatefulWidget {
  final UploadProvider uploadProvider;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const ServerDownView({
    super.key,
    required this.uploadProvider,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  State<ServerDownView> createState() => _ServerDownViewState();
}

class _ServerDownViewState extends State<ServerDownView> {
  bool _isCheckingHealth = false;
  bool? _isServerBackOnline;

  Future<void> _checkServerStatus() async {
    setState(() {
      _isCheckingHealth = true;
      _isServerBackOnline = null;
    });

    final isHealthy = await widget.uploadProvider.checkServerHealth();

    if (mounted) {
      setState(() {
        _isCheckingHealth = false;
        _isServerBackOnline = isHealthy;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusCode = widget.uploadProvider.serverStatusCode;
    final isBillingOrQuota = statusCode == 402 || statusCode == 429;
    final statusText = statusCode != null
        ? 'Error $statusCode · ${isBillingOrQuota ? 'Quota / Billing Limit' : 'Server Paused / Maintenance'}'
        : 'Cloud Server Offline';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.warningAmber.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.warningAmber.withValues(alpha: 0.12),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon badge with glowing background
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.warningAmber.withValues(alpha: 0.15),
              border: Border.all(
                color: AppTheme.warningAmber.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              color: AppTheme.warningAmber,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.warningAmber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.warningAmber.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              statusText,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.warningAmber,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            isBillingOrQuota
                ? 'Cloud Storage Quota Exceeded'
                : 'Cloud Server Temporarily Paused',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),

          // Message
          Text(
            widget.uploadProvider.errorMessage ??
                'The upload service is currently paused or undergoing maintenance. Your video has not been uploaded to the cloud.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),

          // Reassurance Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.successEmerald,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your recording is safely saved locally on this device in your history.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Live ping health indicator if checked
          if (_isServerBackOnline != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isServerBackOnline!
                    ? AppTheme.successEmerald.withValues(alpha: 0.15)
                    : AppTheme.recordRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isServerBackOnline!
                        ? Icons.check_circle_outline_rounded
                        : Icons.wifi_off_rounded,
                    size: 16,
                    color: _isServerBackOnline!
                        ? AppTheme.successEmerald
                        : AppTheme.recordRed,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isServerBackOnline!
                        ? 'Server is back online! Tap Retry to upload.'
                        : 'Server still offline or paused. Please try later.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isServerBackOnline!
                          ? AppTheme.successEmerald
                          : AppTheme.recordRed,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: widget.onCancel,
                  child: const Text('Keep Local'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Diagnostics Check Status Text Button
          TextButton.icon(
            onPressed: _isCheckingHealth ? null : _checkServerStatus,
            icon: _isCheckingHealth
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryLight,
                    ),
                  )
                : const Icon(
                    Icons.network_ping_rounded,
                    size: 16,
                    color: AppTheme.primaryLight,
                  ),
            label: Text(
              _isCheckingHealth ? 'Pinging server...' : 'Check Server Status',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
