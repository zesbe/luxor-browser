import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/sync_service.dart';
import '../dialogs/auto_save_password_dialog.dart';

// ============================================================================
// PASSWORD WEBVIEW INTEGRATION - Auto-fill and Auto-save for WebView
// ============================================================================

class PasswordWebViewIntegration {
  final SyncService syncService;
  final BuildContext context;
  final Color accentColor;
  final InAppWebViewController? webViewController;

  bool _isInitialized = false;
  Set<String> _processedUrls = {};

  PasswordWebViewIntegration({
    required this.syncService,
    required this.context,
    required this.accentColor,
    this.webViewController,
  });

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  Future<void> initialize(InAppWebViewController controller) async {
    if (_isInitialized) return;

    try {
      // Inject password detection JavaScript
      await controller.evaluateJavascript(source: _getPasswordDetectionScript());

      // Register JavaScript handlers
      controller.addJavaScriptHandler(
        handlerName: 'onPasswordDetected',
        callback: (args) => _handlePasswordDetected(args[0], controller),
      );

      controller.addJavaScriptHandler(
        handlerName: 'requestAutoFill',
        callback: (args) => _handleAutoFillRequest(args[0], controller),
      );

      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize password integration: $e');
    }
  }

  // ============================================================================
  // PAGE LOAD HANDLERS
  // ============================================================================

  Future<void> onPageStarted(String url, InAppWebViewController controller) async {
    // Reset processed URLs for new page
    if (!_processedUrls.contains(url)) {
      _processedUrls.add(url);
    }
  }

  Future<void> onPageFinished(String url, InAppWebViewController controller) async {
    try {
      await initialize(controller);

      // Check if page has login form and auto-fill if credentials exist
      await _checkAndAutoFillPage(url, controller);

    } catch (e) {
      debugPrint('Error on page finished: $e');
    }
  }

  Future<void> onLoadStop(String url, InAppWebViewController controller) async {
    try {
      // Re-inject scripts for single page applications
      await controller.evaluateJavascript(source: _getPasswordDetectionScript());

      // Auto-fill passwords if available
      await _checkAndAutoFillPage(url, controller);

    } catch (e) {
      debugPrint('Error on load stop: $e');
    }
  }

  // ============================================================================
  // PASSWORD DETECTION
  // ============================================================================

  Future<void> _handlePasswordDetected(
    Map<String, dynamic> data,
    InAppWebViewController controller,
  ) async {
    try {
      final url = data['url']?.toString() ?? '';
      final username = data['username']?.toString() ?? '';
      final password = data['password']?.toString() ?? '';

      if (url.isEmpty || username.isEmpty || password.isEmpty) return;

      // Check if we should auto-save for this site
      if (await _shouldShowAutoSaveDialog(url, username)) {
        final shouldSave = await AutoSavePasswordDialog.show(
          context: context,
          url: url,
          username: username,
          password: password,
          syncService: syncService,
          accentColor: accentColor,
        );

        if (shouldSave == true) {
          // Password was saved successfully via the dialog
          debugPrint('Password saved for $url');
        }
      }
    } catch (e) {
      debugPrint('Error handling password detection: $e');
    }
  }

  Future<void> _handleAutoFillRequest(
    Map<String, dynamic> data,
    InAppWebViewController controller,
  ) async {
    try {
      final url = data['url']?.toString() ?? '';
      if (url.isEmpty) return;

      await _performAutoFill(url, controller);
    } catch (e) {
      debugPrint('Error handling auto-fill request: $e');
    }
  }

  // ============================================================================
  // AUTO-FILL FUNCTIONALITY
  // ============================================================================

  Future<void> _checkAndAutoFillPage(
    String url,
    InAppWebViewController controller,
  ) async {
    try {
      // Wait a bit for page to fully load
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if page has login form
      final hasLoginForm = await controller.evaluateJavascript(
        source: _getCheckLoginFormScript(),
      );

      if (hasLoginForm == true) {
        await _performAutoFill(url, controller);
      }
    } catch (e) {
      debugPrint('Error checking and auto-filling page: $e');
    }
  }

  Future<void> _performAutoFill(
    String url,
    InAppWebViewController controller,
  ) async {
    try {
      // Get saved passwords for this URL
      final credentials = await _getCredentialsForUrl(url);

      if (credentials.isNotEmpty) {
        // Inject auto-fill script with credentials
        final autoFillScript = _getAutoFillScript(credentials);
        await controller.evaluateJavascript(source: autoFillScript);

        // Show auto-fill notification
        _showAutoFillNotification(credentials.length);
      }
    } catch (e) {
      debugPrint('Error performing auto-fill: $e');
    }
  }

  // ============================================================================
  // CREDENTIAL MANAGEMENT
  // ============================================================================

  Future<List<Map<String, dynamic>>> _getCredentialsForUrl(String url) async {
    try {
      // Get all saved passwords
      final allPasswords = await syncService.getAllSavedPasswords();

      // Filter by URL domain
      final domain = _extractDomain(url);
      final matchingPasswords = allPasswords.where((password) {
        final savedUrl = password['url']?.toString() ?? '';
        final savedDomain = _extractDomain(savedUrl);
        return savedDomain == domain;
      }).toList();

      return matchingPasswords;
    } catch (e) {
      debugPrint('Error getting credentials for URL: $e');
      return [];
    }
  }

  Future<bool> _shouldShowAutoSaveDialog(String url, String username) async {
    try {
      // Check if password already exists for this URL/username combination
      final existingPasswords = await _getCredentialsForUrl(url);
      final exists = existingPasswords.any(
        (p) => p['username']?.toString().toLowerCase() == username.toLowerCase(),
      );

      if (exists) return false;

      // Check never-save list (would implement this)
      if (await _isInNeverSaveList(url)) return false;

      return true;
    } catch (e) {
      debugPrint('Error checking if should show auto-save dialog: $e');
      return false;
    }
  }

  Future<bool> _isInNeverSaveList(String url) async {
    // Implementation would check shared preferences for never-save list
    // For now, return false
    return false;
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      String domain = uri.host.toLowerCase();

      // Remove www prefix
      if (domain.startsWith('www.')) {
        domain = domain.substring(4);
      }

      return domain;
    } catch (e) {
      return '';
    }
  }

  // ============================================================================
  // JAVASCRIPT INJECTION SCRIPTS
  // ============================================================================

  String _getPasswordDetectionScript() {
    return '''
      (function() {
        if (window.luxorPasswordDetector) return window.luxorPasswordDetector;

        let passwordDetector = {
          detected: false,
          forms: [],

          // Initialize form detection
          init: function() {
            this.detectForms();
            this.attachFormListeners();
            this.attachAutoFillListeners();

            // Re-detect forms when DOM changes
            const observer = new MutationObserver(() => {
              this.detectForms();
              this.attachFormListeners();
            });
            observer.observe(document.body, { childList: true, subtree: true });
          },

          // Detect all login forms
          detectForms: function() {
            const forms = document.querySelectorAll('form');
            this.forms = [];

            forms.forEach(form => {
              const passwordField = form.querySelector('input[type="password"]');
              const usernameField = form.querySelector('input[type="email"]') ||
                                   form.querySelector('input[type="text"]') ||
                                   form.querySelector('input[name*="email"]') ||
                                   form.querySelector('input[name*="user"]') ||
                                   form.querySelector('input[name*="login"]');

              if (passwordField && usernameField) {
                this.forms.push({
                  form: form,
                  usernameField: usernameField,
                  passwordField: passwordField
                });
              }
            });

            if (this.forms.length > 0) {
              // Request auto-fill for detected forms
              setTimeout(() => {
                window.flutter_inappwebview.callHandler('requestAutoFill', {
                  url: window.location.href,
                  formCount: this.forms.length
                });
              }, 100);
            }
          },

          // Attach form submission listeners
          attachFormListeners: function() {
            this.forms.forEach(formData => {
              const { form, usernameField, passwordField } = formData;

              // Remove existing listeners to avoid duplicates
              form.removeEventListener('submit', this.handleFormSubmit);

              // Add submit listener
              const submitHandler = (e) => {
                const username = usernameField.value.trim();
                const password = passwordField.value;

                if (username && password && password.length >= 3) {
                  setTimeout(() => {
                    window.flutter_inappwebview.callHandler('onPasswordDetected', {
                      url: window.location.href,
                      username: username,
                      password: password,
                      siteName: document.title || window.location.hostname
                    });
                  }, 100);
                }
              };

              form.addEventListener('submit', submitHandler);
            });
          },

          // Auto-fill functionality
          autoFillPasswords: function(credentials) {
            if (!credentials || credentials.length === 0) return;

            this.forms.forEach(formData => {
              const { usernameField, passwordField } = formData;
              const credential = credentials.find(c =>
                c.username && c.password
              );

              if (credential && !usernameField.value && !passwordField.value) {
                // Fill fields
                usernameField.value = credential.username;
                passwordField.value = credential.password;

                // Trigger events for frameworks
                [usernameField, passwordField].forEach(field => {
                  field.dispatchEvent(new Event('input', { bubbles: true }));
                  field.dispatchEvent(new Event('change', { bubbles: true }));
                  field.dispatchEvent(new Event('blur', { bubbles: true }));
                });

                // Visual feedback
                this.showAutoFillIndicator(usernameField);
                this.showAutoFillIndicator(passwordField);
              }
            });
          },

          // Visual indicator for auto-filled fields
          showAutoFillIndicator: function(field) {
            const originalBg = field.style.backgroundColor;
            const originalBorder = field.style.border;

            field.style.backgroundColor = '#e8f5e8';
            field.style.border = '2px solid #4caf50';
            field.style.transition = 'all 0.3s ease';

            setTimeout(() => {
              field.style.backgroundColor = originalBg;
              field.style.border = originalBorder;
            }, 2000);
          },

          // Auto-fill button functionality
          attachAutoFillListeners: function() {
            this.forms.forEach(formData => {
              const { usernameField } = formData;

              // Create auto-fill button if not exists
              if (!usernameField.nextElementSibling?.classList?.contains('luxor-autofill-btn')) {
                const button = document.createElement('button');
                button.type = 'button';
                button.classList.add('luxor-autofill-btn');
                button.innerHTML = '🔑';
                button.style.cssText = `
                  position: absolute;
                  right: 5px;
                  top: 50%;
                  transform: translateY(-50%);
                  background: #4caf50;
                  border: none;
                  border-radius: 3px;
                  width: 24px;
                  height: 24px;
                  cursor: pointer;
                  font-size: 12px;
                  z-index: 9999;
                `;

                // Position the parent relatively if needed
                const fieldContainer = usernameField.parentElement;
                if (getComputedStyle(fieldContainer).position === 'static') {
                  fieldContainer.style.position = 'relative';
                }

                fieldContainer.appendChild(button);

                button.addEventListener('click', (e) => {
                  e.preventDefault();
                  window.flutter_inappwebview.callHandler('requestAutoFill', {
                    url: window.location.href,
                    manual: true
                  });
                });
              }
            });
          }
        };

        // Initialize when DOM is ready
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', () => passwordDetector.init());
        } else {
          passwordDetector.init();
        }

        // Make available globally
        window.luxorPasswordDetector = passwordDetector;
        return passwordDetector;
      })();
    ''';
  }

  String _getCheckLoginFormScript() {
    return '''
      (function() {
        const forms = document.querySelectorAll('form');
        let hasLoginForm = false;

        forms.forEach(form => {
          const passwordField = form.querySelector('input[type="password"]');
          const usernameField = form.querySelector('input[type="email"]') ||
                               form.querySelector('input[type="text"]') ||
                               form.querySelector('input[name*="email"]') ||
                               form.querySelector('input[name*="user"]') ||
                               form.querySelector('input[name*="login"]');

          if (passwordField && usernameField) {
            hasLoginForm = true;
          }
        });

        return hasLoginForm;
      })();
    ''';
  }

  String _getAutoFillScript(List<Map<String, dynamic>> credentials) {
    final credentialsJson = credentials.map((c) => {
      'username': c['username'],
      'password': c['password'],
    }).toList();

    return '''
      (function() {
        const credentials = ${jsonEncode(credentialsJson)};
        if (window.luxorPasswordDetector) {
          window.luxorPasswordDetector.autoFillPasswords(credentials);
          return true;
        }
        return false;
      })();
    ''';
  }

  // ============================================================================
  // UI FEEDBACK
  // ============================================================================

  void _showAutoFillNotification(int credentialCount) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.key, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Auto-filled $credentialCount password${credentialCount > 1 ? 's' : ''}'),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================

  void dispose() {
    _processedUrls.clear();
    _isInitialized = false;
  }
}

// ============================================================================
// PASSWORD MANAGER BUTTON - Floating button for quick access
// ============================================================================

class PasswordManagerButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color accentColor;

  const PasswordManagerButton({
    super.key,
    required this.onPressed,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: FloatingActionButton.small(
        onPressed: onPressed,
        backgroundColor: accentColor.withOpacity(0.9),
        foregroundColor: Colors.black,
        heroTag: 'password_manager',
        child: const Icon(Icons.key, size: 20),
      ),
    );
  }
}

// ============================================================================
// AUTO-FILL SUGGESTION WIDGET - Shows available passwords
// ============================================================================

class AutoFillSuggestion extends StatelessWidget {
  final List<Map<String, dynamic>> credentials;
  final Function(Map<String, dynamic>) onCredentialSelected;
  final Color accentColor;

  const AutoFillSuggestion({
    super.key,
    required this.credentials,
    required this.onCredentialSelected,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (credentials.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.key, color: accentColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Saved passwords',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ...credentials.take(3).map((credential) => ListTile(
            dense: true,
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.person, color: accentColor, size: 16),
            ),
            title: Text(
              credential['username']?.toString() ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              credential['title']?.toString() ?? credential['url']?.toString() ?? '',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onCredentialSelected(credential),
          )),
        ],
      ),
    );
  }
}