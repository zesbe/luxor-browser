import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../services/sync_service.dart';

// ============================================================================
// AUTO-SAVE PASSWORD DIALOG - Chrome-style password save prompt
// ============================================================================

class AutoSavePasswordDialog {
  static Future<bool?> show({
    required BuildContext context,
    required String url,
    required String username,
    required String password,
    required SyncService syncService,
    Color accentColor = Colors.amber,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AutoSavePasswordDialog(
        url: url,
        username: username,
        password: password,
        syncService: syncService,
        accentColor: accentColor,
      ),
    );
  }
}

class _AutoSavePasswordDialog extends StatefulWidget {
  final String url;
  final String username;
  final String password;
  final SyncService syncService;
  final Color accentColor;

  const _AutoSavePasswordDialog({
    required this.url,
    required this.username,
    required this.password,
    required this.syncService,
    required this.accentColor,
  });

  @override
  State<_AutoSavePasswordDialog> createState() => _AutoSavePasswordDialogState();
}

class _AutoSavePasswordDialogState extends State<_AutoSavePasswordDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isLoading = false;
  bool _neverForThisSite = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final siteName = _extractSiteName(widget.url);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.accentColor.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                _buildHeader(siteName),

                // Content
                _buildContent(siteName),

                // Actions
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String siteName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.accentColor.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.accentColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Iconsax.key,
              color: widget.accentColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Save password?',
                  style: TextStyle(
                    color: widget.accentColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Luxor can save this password for $siteName',
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
    );
  }

  Widget _buildContent(String siteName) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Website info
          _buildInfoRow(
            icon: Icons.language,
            label: 'Website',
            value: siteName,
            subtitle: widget.url,
          ),
          const SizedBox(height: 12),

          // Username info
          _buildInfoRow(
            icon: Icons.person,
            label: 'Username',
            value: widget.username,
            isPassword: false,
          ),
          const SizedBox(height: 12),

          // Password info
          _buildInfoRow(
            icon: Icons.key,
            label: 'Password',
            value: '•' * widget.password.length,
            subtitle: _getPasswordStrengthText(),
            subtitleColor: _getPasswordStrengthColor(),
            isPassword: true,
          ),
          const SizedBox(height: 16),

          // Sync info
          if (widget.syncService.isSignedIn && widget.syncService.syncPasswords) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[900]?.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[700]!.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_done, color: Colors.green[400], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Will sync to your Google account',
                      style: TextStyle(
                        color: Colors.green[300],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (widget.syncService.isSignedIn && !widget.syncService.syncPasswords) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[900]?.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[700]!.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.orange[400], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Saved locally only. Enable password sync to sync across devices.',
                      style: TextStyle(
                        color: Colors.orange[300],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[900]?.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[700]!.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue[400], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Saved locally. Sign in to sync across devices.',
                      style: TextStyle(
                        color: Colors.blue[300],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Never save option
          Row(
            children: [
              Checkbox(
                value: _neverForThisSite,
                onChanged: (value) => setState(() => _neverForThisSite = value ?? false),
                activeColor: widget.accentColor,
              ),
              Expanded(
                child: Text(
                  'Never save passwords for this site',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    Color? subtitleColor,
    bool isPassword = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: widget.accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: widget.accentColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: subtitleColor ?? Colors.grey[500],
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Primary actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[400],
                    side: BorderSide(color: Colors.grey[600]!),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleSavePassword,
                  icon: _isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : Icon(Iconsax.tick_circle, size: 18),
                  label: Text(_isLoading ? 'Saving...' : 'Save Password'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Secondary action
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _isLoading ? null : () => _showPasswordSettings(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.settings, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Text(
                    'Password settings',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  Future<void> _handleSavePassword() async {
    setState(() => _isLoading = true);

    try {
      if (_neverForThisSite) {
        // Save to never save list (would implement this in SyncService)
        await _addToNeverSaveList(widget.url);
      } else {
        // Save password using credential manager
        final success = await widget.syncService.savePasswordWithCredentialManager(
          url: widget.url,
          username: widget.username,
          password: widget.password,
        );

        if (success) {
          Navigator.pop(context, true);
          _showSuccess();
        } else {
          _showError('Failed to save password');
        }
      }
    } catch (e) {
      _showError('Error saving password: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showPasswordSettings() {
    Navigator.pop(context, false);
    // Navigate to password settings (sync settings page)
    Navigator.pushNamed(context, '/sync-settings');
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  String _extractSiteName(String url) {
    try {
      final uri = Uri.parse(url);
      String domain = uri.host.toLowerCase();

      // Remove www prefix
      if (domain.startsWith('www.')) {
        domain = domain.substring(4);
      }

      // Get main domain (remove subdomains for known sites)
      final parts = domain.split('.');
      if (parts.length >= 2) {
        final mainDomain = parts[parts.length - 2];
        return mainDomain.substring(0, 1).toUpperCase() + mainDomain.substring(1);
      }

      return domain;
    } catch (e) {
      return 'Website';
    }
  }

  String _getPasswordStrengthText() {
    final length = widget.password.length;
    if (length < 6) return 'Weak password';
    if (length < 8) return 'Fair password';

    bool hasUpper = widget.password.contains(RegExp(r'[A-Z]'));
    bool hasLower = widget.password.contains(RegExp(r'[a-z]'));
    bool hasNumber = widget.password.contains(RegExp(r'[0-9]'));
    bool hasSpecial = widget.password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    int score = 0;
    if (hasUpper) score++;
    if (hasLower) score++;
    if (hasNumber) score++;
    if (hasSpecial) score++;
    if (length >= 12) score++;

    if (score >= 4) return 'Strong password';
    if (score >= 3) return 'Good password';
    return 'Fair password';
  }

  Color _getPasswordStrengthColor() {
    final strength = _getPasswordStrengthText();
    switch (strength) {
      case 'Strong password': return Colors.green;
      case 'Good password': return Colors.blue;
      case 'Fair password': return Colors.orange;
      default: return Colors.red;
    }
  }

  Future<void> _addToNeverSaveList(String url) async {
    // Implementation would save to a "never save" list in shared preferences
    // For now, just mark as handled
    Navigator.pop(context, false);
  }

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Password saved successfully'),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }
}

// ============================================================================
// PASSWORD DETECTION HELPER - JavaScript injection for WebView
// ============================================================================

class PasswordDetectionHelper {
  // JavaScript code to inject into WebView to detect login forms
  static const String detectionScript = '''
    (function() {
      let passwordDetector = {
        detected: false,

        // Detect form submissions
        detectFormSubmission: function() {
          const forms = document.querySelectorAll('form');

          forms.forEach(form => {
            form.addEventListener('submit', (e) => {
              const passwordField = form.querySelector('input[type="password"]');
              const emailField = form.querySelector('input[type="email"]') ||
                                form.querySelector('input[type="text"]') ||
                                form.querySelector('input[name*="email"]') ||
                                form.querySelector('input[name*="user"]') ||
                                form.querySelector('input[name*="login"]');

              if (passwordField && emailField && !passwordDetector.detected) {
                passwordDetector.detected = true;

                const username = emailField.value;
                const password = passwordField.value;

                if (username && password && username.length > 0 && password.length > 2) {
                  // Send to Flutter
                  window.flutter_inappwebview.callHandler('onPasswordDetected', {
                    url: window.location.href,
                    username: username,
                    password: password,
                    siteName: document.title || window.location.hostname
                  });
                }
              }
            });
          });
        },

        // Auto-fill functionality
        autoFillPasswords: function(credentials) {
          const passwordField = document.querySelector('input[type="password"]');
          const emailField = document.querySelector('input[type="email"]') ||
                            document.querySelector('input[type="text"]') ||
                            document.querySelector('input[name*="email"]') ||
                            document.querySelector('input[name*="user"]') ||
                            document.querySelector('input[name*="login"]');

          if (emailField && passwordField && credentials.length > 0) {
            const credential = credentials[0]; // Use first match

            // Fill fields
            emailField.value = credential.username;
            passwordField.value = credential.password;

            // Trigger events
            emailField.dispatchEvent(new Event('input', { bubbles: true }));
            passwordField.dispatchEvent(new Event('input', { bubbles: true }));
            emailField.dispatchEvent(new Event('change', { bubbles: true }));
            passwordField.dispatchEvent(new Event('change', { bubbles: true }));

            // Show auto-fill indicator
            emailField.style.backgroundColor = '#e8f5e8';
            passwordField.style.backgroundColor = '#e8f5e8';

            setTimeout(() => {
              emailField.style.backgroundColor = '';
              passwordField.style.backgroundColor = '';
            }, 2000);
          }
        }
      };

      // Initialize when DOM is ready
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', passwordDetector.detectFormSubmission);
      } else {
        passwordDetector.detectFormSubmission();
      }

      // Make available globally for auto-fill
      window.passwordDetector = passwordDetector;

      return passwordDetector;
    })();
  ''';

  // JavaScript for checking if login form exists
  static const String checkLoginFormScript = '''
    (function() {
      const forms = document.querySelectorAll('form');
      let hasLoginForm = false;

      forms.forEach(form => {
        const passwordField = form.querySelector('input[type="password"]');
        const emailField = form.querySelector('input[type="email"]') ||
                          form.querySelector('input[type="text"]') ||
                          form.querySelector('input[name*="email"]') ||
                          form.querySelector('input[name*="user"]') ||
                          form.querySelector('input[name*="login"]');

        if (passwordField && emailField) {
          hasLoginForm = true;
        }
      });

      return hasLoginForm;
    })();
  ''';

  // JavaScript for auto-filling saved passwords
  static String getAutoFillScript(List<Map<String, dynamic>> credentials) {
    final credentialsJson = credentials.map((c) => {
      'username': c['username'],
      'password': c['password'],
    }).toList();

    return '''
      (function() {
        const credentials = ${credentialsJson.toString()};
        if (window.passwordDetector) {
          window.passwordDetector.autoFillPasswords(credentials);
        }
      })();
    ''';
  }
}