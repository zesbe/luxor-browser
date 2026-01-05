import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../services/sync_service.dart';

// ============================================================================
// SYNC SETTINGS PAGE - Google Account & Sync Settings UI
// ============================================================================

class SyncSettingsPage extends StatefulWidget {
  final SyncService syncService;
  final Color accentColor;

  const SyncSettingsPage({
    super.key,
    required this.syncService,
    this.accentColor = Colors.amber,
  });

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Sync & Google Account',
          style: TextStyle(color: widget.accentColor),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: widget.accentColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.syncService,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account Section
                _buildAccountSection(),
                const SizedBox(height: 24),

                // Sync Status Section
                if (widget.syncService.isSignedIn) ...[
                  _buildSyncStatusSection(),
                  const SizedBox(height: 24),

                  // Sync Options
                  _buildSyncOptionsSection(),
                  const SizedBox(height: 24),

                  // Password Import/Export
                  if (widget.syncService.isSignedIn) ...[
                    _buildPasswordImportExportSection(),
                    const SizedBox(height: 24),
                  ],

                  // Other Devices
                  _buildOtherDevicesSection(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================================
  // ACCOUNT SECTION
  // ============================================================================

  Widget _buildAccountSection() {
    final syncService = widget.syncService;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.accentColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          if (syncService.isSignedIn) ...[
            // Signed In State
            Row(
              children: [
                // Profile Picture
                CircleAvatar(
                  radius: 32,
                  backgroundColor: widget.accentColor.withOpacity(0.2),
                  backgroundImage: syncService.userPhotoUrl != null
                      ? NetworkImage(syncService.userPhotoUrl!)
                      : null,
                  child: syncService.userPhotoUrl == null
                      ? Icon(Icons.person, color: widget.accentColor, size: 32)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncService.userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        syncService.userEmail,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Sign Out Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _handleSignOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[300],
                  side: BorderSide(color: Colors.red[300]!.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else ...[
            // Signed Out State
            Icon(
              Iconsax.cloud_add,
              size: 64,
              color: widget.accentColor.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sync with Google',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to sync your bookmarks, history, and settings across all your devices.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleSignIn,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Image.network(
                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                        width: 20,
                        height: 20,
                        errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata),
                      ),
                label: Text(_isLoading ? 'Signing in...' : 'Sign in with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================================
  // SYNC STATUS SECTION
  // ============================================================================

  Widget _buildSyncStatusSection() {
    final syncService = widget.syncService;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sync Status',
                style: TextStyle(
                  color: widget.accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: syncService.syncEnabled,
                onChanged: (value) => syncService.setSyncEnabled(value),
                activeColor: widget.accentColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                syncService.isSyncing
                    ? Icons.sync
                    : syncService.syncError != null
                        ? Icons.sync_problem
                        : syncService.isOnline
                            ? Icons.cloud_done
                            : Icons.cloud_off,
                color: syncService.syncError != null
                    ? Colors.red
                    : syncService.isOnline
                        ? Colors.green
                        : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncService.isSyncing
                      ? 'Syncing...'
                      : syncService.syncError ?? (
                          syncService.isOnline
                              ? (syncService.lastSyncTime != null
                                  ? 'Last synced: ${_formatLastSync(syncService.lastSyncTime!)}'
                                  : 'Ready to sync')
                              : 'Offline - Will sync when online'
                        ),
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (!syncService.isSyncing) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => syncService.syncNow(),
              icon: Icon(Icons.sync, color: widget.accentColor, size: 18),
              label: Text(
                'Sync Now',
                style: TextStyle(color: widget.accentColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================================
  // SYNC OPTIONS SECTION
  // ============================================================================

  Widget _buildSyncOptionsSection() {
    final syncService = widget.syncService;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What to Sync',
            style: TextStyle(
              color: widget.accentColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSyncOption(
            icon: Iconsax.bookmark,
            title: 'Bookmarks',
            subtitle: 'Sync your saved bookmarks',
            value: syncService.syncBookmarks,
            onChanged: (v) => syncService.updateSyncSetting('bookmarks', v),
          ),
          _buildSyncOption(
            icon: Iconsax.clock,
            title: 'History',
            subtitle: 'Sync your browsing history',
            value: syncService.syncHistory,
            onChanged: (v) => syncService.updateSyncSetting('history', v),
          ),
          _buildSyncOption(
            icon: Iconsax.book,
            title: 'Reading List',
            subtitle: 'Sync your reading list items',
            value: syncService.syncReadingList,
            onChanged: (v) => syncService.updateSyncSetting('reading_list', v),
          ),
          _buildSyncOption(
            icon: Iconsax.setting_2,
            title: 'Settings',
            subtitle: 'Sync browser preferences',
            value: syncService.syncSettings,
            onChanged: (v) => syncService.updateSyncSetting('settings', v),
          ),
          _buildSyncOption(
            icon: Iconsax.document,
            title: 'Open Tabs',
            subtitle: 'See tabs from other devices',
            value: syncService.syncOpenTabs,
            onChanged: (v) => syncService.updateSyncSetting('open_tabs', v),
          ),
          _buildSyncOption(
            icon: Iconsax.key,
            title: 'Passwords',
            subtitle: syncService.passphraseSet
                ? 'Sync saved passwords (encrypted)'
                : 'Requires encryption passphrase',
            value: syncService.syncPasswords,
            onChanged: (v) => _handlePasswordSyncToggle(v),
            isSecure: true,
            requiresSetup: !syncService.passphraseSet,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isSecure = false,
    bool requiresSetup = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: widget.accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    if (isSecure) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.shield, color: Colors.green[400], size: 14),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: requiresSetup ? Colors.orange[400] : Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: widget.syncService.syncEnabled ? onChanged : null,
            activeColor: widget.accentColor,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // OTHER DEVICES SECTION
  // ============================================================================

  Widget _buildOtherDevicesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Other Devices',
                style: TextStyle(
                  color: widget.accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: widget.accentColor, size: 20),
                onPressed: () => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
            future: widget.syncService.getOtherDevicesTabs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final devices = snapshot.data ?? {};

              if (devices.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Iconsax.mobile,
                        size: 40,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No other devices found',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sign in on another device to see tabs here',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: devices.entries.map((entry) {
                  return ExpansionTile(
                    leading: Icon(Iconsax.monitor, color: widget.accentColor),
                    title: Text(
                      entry.key,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${entry.value.length} tabs',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    children: entry.value.map((tab) {
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.tab, size: 16),
                        title: Text(
                          tab['title'] ?? 'Untitled',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          tab['url'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                        onTap: () {
                          // Open this tab
                          Navigator.pop(context, tab['url']);
                        },
                      );
                    }).toList(),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // HANDLERS
  // ============================================================================

  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);
    final success = await widget.syncService.signInWithGoogle();
    setState(() => _isLoading = false);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.syncService.syncError ?? 'Sign in failed'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Sign Out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your data will remain on this device but will no longer sync.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out', style: TextStyle(color: Colors.red[300])),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await widget.syncService.signOut();
      setState(() => _isLoading = false);
    }
  }

  // ============================================================================
  // PASSWORD IMPORT/EXPORT SECTION
  // ============================================================================

  Widget _buildPasswordImportExportSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password Import/Export',
            style: TextStyle(
              color: widget.accentColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Import passwords from Chrome or export your Luxor passwords',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleImportPasswords,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Import from CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.accentColor,
                    side: BorderSide(color: widget.accentColor.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleExportPasswords,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Export to CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.accentColor,
                    side: BorderSide(color: widget.accentColor.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Chrome Import Instructions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[900]?.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[700]!.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue[400], size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'How to Import from Chrome:',
                      style: TextStyle(
                        color: Colors.blue[400],
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Open Chrome → Settings → Password Manager\n'
                  '2. Click ⚙️ → Export passwords → Download CSV\n'
                  '3. In Luxor: Import from CSV → Select downloaded file',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Credential Manager Integration
          FutureBuilder<bool>(
            future: widget.syncService.isCredentialManagerAvailable(),
            builder: (context, snapshot) {
              final isAvailable = snapshot.data ?? false;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? Colors.green[900]?.withOpacity(0.2)
                      : Colors.orange[900]?.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isAvailable
                        ? Colors.green[700]!.withOpacity(0.3)
                        : Colors.orange[700]!.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isAvailable ? Icons.security : Icons.warning,
                      color: isAvailable ? Colors.green[400] : Colors.orange[400],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAvailable
                                ? 'Android Autofill Ready'
                                : 'Autofill Limited',
                            style: TextStyle(
                              color: isAvailable ? Colors.green[400] : Colors.orange[400],
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAvailable
                                ? 'Passwords will autofill using Android Credential Manager'
                                : 'Install Google Play Services for full autofill support',
                            style: TextStyle(
                              color: Colors.grey[300],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // PASSWORD SYNC HANDLERS
  // ============================================================================

  Future<void> _handlePasswordSyncToggle(bool value) async {
    if (value && !widget.syncService.passphraseSet) {
      // Need to set up passphrase first
      final passphrase = await _showPassphraseDialog();
      if (passphrase != null) {
        final success = await widget.syncService.setEncryptionPassphrase(passphrase);
        if (success) {
          await widget.syncService.updateSyncSetting('passwords', true);
        } else {
          _showError('Failed to set passphrase: ${widget.syncService.syncError}');
        }
      }
    } else if (value && widget.syncService.passphraseSet) {
      // Verify existing passphrase
      final passphrase = await _showPassphraseDialog(isVerification: true);
      if (passphrase != null) {
        final verified = await widget.syncService.verifyPassphrase(passphrase);
        if (verified) {
          await widget.syncService.updateSyncSetting('passwords', true);
        } else {
          _showError('Incorrect passphrase');
        }
      }
    } else {
      // Disable password sync
      await widget.syncService.updateSyncSetting('passwords', false);
    }
  }

  Future<String?> _showPassphraseDialog({bool isVerification = false}) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          isVerification ? 'Enter Passphrase' : 'Set Encryption Passphrase',
          style: TextStyle(color: widget.accentColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isVerification) ...[
              const Text(
                'Create a strong passphrase to encrypt your passwords. This cannot be recovered if lost.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                labelStyle: TextStyle(color: Colors.grey[400]),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: widget.accentColor),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            if (!isVerification) ...[
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm Passphrase',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[600]!),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: widget.accentColor),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final passphrase = controller.text;

              if (passphrase.isEmpty) {
                _showError('Passphrase cannot be empty');
                return;
              }

              if (!isVerification && passphrase.length < 8) {
                _showError('Passphrase must be at least 8 characters');
                return;
              }

              if (!isVerification && passphrase != confirmController.text) {
                _showError('Passphrases do not match');
                return;
              }

              Navigator.pop(context, passphrase);
            },
            child: Text(
              isVerification ? 'Verify' : 'Set',
              style: TextStyle(color: widget.accentColor),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // IMPORT/EXPORT HANDLERS
  // ============================================================================

  Future<void> _handleImportPasswords() async {
    setState(() => _isLoading = true);

    try {
      final importedCount = await widget.syncService.importPasswordsFromCSV();

      if (importedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported $importedCount passwords'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        final error = widget.syncService.syncError ?? 'No passwords were imported';
        _showError(error);
      }
    } catch (e) {
      _showError('Import failed: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _handleExportPasswords() async {
    setState(() => _isLoading = true);

    try {
      final filePath = await widget.syncService.exportPasswordsToCSV();

      if (filePath != null) {
        final fileName = filePath.split('/').last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Passwords exported successfully!'),
                const SizedBox(height: 4),
                Text(
                  'Saved to: Downloads/$fileName',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'SHARE',
              textColor: Colors.white,
              onPressed: () {
                // Could implement share functionality here
                _showInfo('File saved to Downloads folder');
              },
            ),
          ),
        );
      } else {
        final error = widget.syncService.syncError ?? 'Export failed';
        _showError(error);
      }
    } catch (e) {
      _showError('Export failed: $e');
    }

    setState(() => _isLoading = false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue[700],
      ),
    );
  }

  String _formatLastSync(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}
