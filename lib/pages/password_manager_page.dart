import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import '../services/sync_service.dart';

// ============================================================================
// PASSWORD MANAGER PAGE - Chrome-style Password Management
// ============================================================================

class PasswordManagerPage extends StatefulWidget {
  final SyncService syncService;
  final Color accentColor;

  const PasswordManagerPage({
    super.key,
    required this.syncService,
    this.accentColor = Colors.amber,
  });

  @override
  State<PasswordManagerPage> createState() => _PasswordManagerPageState();
}

class _PasswordManagerPageState extends State<PasswordManagerPage> {
  List<Map<String, dynamic>> _passwords = [];
  List<Map<String, dynamic>> _filteredPasswords = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _obscurePasswords = true;
  String _sortBy = 'title'; // 'title', 'url', 'updatedAt'
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadPasswords();
    _searchController.addListener(_filterPasswords);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================================
  // DATA LOADING
  // ============================================================================

  Future<void> _loadPasswords() async {
    setState(() => _isLoading = true);
    try {
      final passwords = await widget.syncService.getAllSavedPasswords();
      setState(() {
        _passwords = passwords;
        _filteredPasswords = List.from(passwords);
        _sortPasswords();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load passwords: $e');
    }
  }

  void _filterPasswords() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredPasswords = List.from(_passwords);
      } else {
        _filteredPasswords = _passwords.where((password) {
          final title = (password['title'] ?? '').toString().toLowerCase();
          final url = (password['url'] ?? '').toString().toLowerCase();
          final username = (password['username'] ?? '').toString().toLowerCase();
          return title.contains(query) || url.contains(query) || username.contains(query);
        }).toList();
      }
      _sortPasswords();
    });
  }

  void _sortPasswords() {
    _filteredPasswords.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'url':
          result = (a['url'] ?? '').toString().compareTo((b['url'] ?? '').toString());
          break;
        case 'updatedAt':
          final aDate = DateTime.tryParse(a['updatedAt'] ?? '') ?? DateTime(2000);
          final bDate = DateTime.tryParse(b['updatedAt'] ?? '') ?? DateTime(2000);
          result = aDate.compareTo(bDate);
          break;
        default: // title
          result = (a['title'] ?? '').toString().compareTo((b['title'] ?? '').toString());
          break;
      }
      return _sortAscending ? result : -result;
    });
  }

  // ============================================================================
  // UI BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Password Manager',
          style: TextStyle(color: widget.accentColor),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: widget.accentColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _obscurePasswords ? Iconsax.eye_slash : Iconsax.eye,
              color: widget.accentColor,
            ),
            onPressed: () => setState(() => _obscurePasswords = !_obscurePasswords),
            tooltip: _obscurePasswords ? 'Show passwords' : 'Hide passwords',
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.sort, color: widget.accentColor),
            onSelected: (value) {
              if (value == _sortBy) {
                setState(() => _sortAscending = !_sortAscending);
              } else {
                setState(() {
                  _sortBy = value;
                  _sortAscending = true;
                });
              }
              _sortPasswords();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'title',
                child: Row(
                  children: [
                    Icon(Icons.sort_by_alpha, size: 18),
                    SizedBox(width: 8),
                    Text('Sort by Name'),
                    if (_sortBy == 'title') ...[
                      Spacer(),
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'url',
                child: Row(
                  children: [
                    Icon(Icons.link, size: 18),
                    SizedBox(width: 8),
                    Text('Sort by URL'),
                    if (_sortBy == 'url') ...[
                      Spacer(),
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'updatedAt',
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 18),
                    SizedBox(width: 8),
                    Text('Sort by Date'),
                    if (_sortBy == 'updatedAt') ...[
                      Spacer(),
                      Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: widget.accentColor),
            onPressed: _loadPasswords,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          _buildSearchBar(),

          // Stats Bar
          _buildStatsBar(),

          // Password List
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _filteredPasswords.isEmpty
                    ? _buildEmptyState()
                    : _buildPasswordList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: widget.accentColor,
        foregroundColor: Colors.black,
        onPressed: () => _showAddPasswordDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.accentColor.withOpacity(0.3)),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search passwords, websites, usernames...',
          hintStyle: TextStyle(color: Colors.grey[500]),
          prefixIcon: Icon(Iconsax.search_normal_1, color: widget.accentColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Iconsax.key, color: widget.accentColor, size: 18),
          const SizedBox(width: 8),
          Text(
            '${_filteredPasswords.length} of ${_passwords.length} passwords',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const Spacer(),
          if (widget.syncService.isSignedIn && widget.syncService.syncPasswords) ...[
            Icon(Icons.cloud_done, color: Colors.green[400], size: 16),
            const SizedBox(width: 4),
            Text(
              'Synced',
              style: TextStyle(color: Colors.green[400], fontSize: 12),
            ),
          ] else ...[
            Icon(Icons.cloud_off, color: Colors.orange[400], size: 16),
            const SizedBox(width: 4),
            Text(
              'Local only',
              style: TextStyle(color: Colors.orange[400], fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading passwords...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchController.text.isNotEmpty ? Iconsax.search_normal : Iconsax.key,
            size: 64,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isNotEmpty
                ? 'No passwords found'
                : 'No passwords saved yet',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty
                ? 'Try a different search term'
                : 'Add your first password or import from Chrome',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          if (_searchController.text.isEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showAddPasswordDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Password'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.accentColor,
                    side: BorderSide(color: widget.accentColor.withOpacity(0.5)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/sync-settings'),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Import'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.accentColor,
                    side: BorderSide(color: widget.accentColor.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredPasswords.length,
      itemBuilder: (context, index) {
        final password = _filteredPasswords[index];
        return _buildPasswordItem(password, index);
      },
    );
  }

  Widget _buildPasswordItem(Map<String, dynamic> password, int index) {
    final title = password['title']?.toString() ?? 'Untitled';
    final url = password['url']?.toString() ?? '';
    final username = password['username']?.toString() ?? '';
    final passwordValue = password['password']?.toString() ?? '';
    final source = password['source']?.toString() ?? 'manual';
    final updatedAt = DateTime.tryParse(password['updatedAt'] ?? '');

    final strength = _getPasswordStrength(passwordValue);
    final strengthColor = _getPasswordStrengthColor(strength);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: widget.accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _buildWebsiteIcon(url),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (source == 'import') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'IMPORTED',
                  style: TextStyle(
                    color: Colors.blue[300],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              url.isNotEmpty ? url : 'No URL',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person, color: Colors.grey[500], size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    username.isNotEmpty ? username : 'No username',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: strengthColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  strength,
                  style: TextStyle(
                    color: strengthColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (updatedAt != null)
              Text(
                'Updated ${_formatDate(updatedAt)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.grey[400]),
          onSelected: (value) => _handlePasswordAction(value, password),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'copy_username',
              child: Row(
                children: [
                  Icon(Icons.person, size: 18),
                  SizedBox(width: 8),
                  Text('Copy Username'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'copy_password',
              child: Row(
                children: [
                  Icon(Icons.key, size: 18),
                  SizedBox(width: 8),
                  Text('Copy Password'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'view_details',
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 18),
                  SizedBox(width: 8),
                  Text('View Details'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _showPasswordDetails(password),
      ),
    );
  }

  Widget _buildWebsiteIcon(String url) {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host.toLowerCase();

      // Common website icons
      if (domain.contains('google')) {
        return Icon(Icons.g_mobiledata, color: widget.accentColor, size: 24);
      } else if (domain.contains('facebook')) {
        return Icon(Icons.facebook, color: widget.accentColor, size: 24);
      } else if (domain.contains('twitter') || domain.contains('x.com')) {
        return Icon(Icons.alternate_email, color: widget.accentColor, size: 24);
      } else if (domain.contains('github')) {
        return Icon(Icons.code, color: widget.accentColor, size: 24);
      } else if (domain.contains('instagram')) {
        return Icon(Icons.camera_alt, color: widget.accentColor, size: 24);
      } else {
        return Icon(Icons.language, color: widget.accentColor, size: 24);
      }
    } catch (e) {
      return Icon(Iconsax.key, color: widget.accentColor, size: 24);
    }
  }

  // ============================================================================
  // PASSWORD ACTIONS
  // ============================================================================

  void _handlePasswordAction(String action, Map<String, dynamic> password) async {
    switch (action) {
      case 'copy_username':
        _copyToClipboard(password['username']?.toString() ?? '', 'Username copied');
        break;
      case 'copy_password':
        _copyToClipboard(password['password']?.toString() ?? '', 'Password copied');
        break;
      case 'view_details':
        _showPasswordDetails(password);
        break;
      case 'edit':
        _showEditPasswordDialog(password);
        break;
      case 'delete':
        _showDeleteConfirmation(password);
        break;
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================================================
  // DIALOGS
  // ============================================================================

  void _showPasswordDetails(Map<String, dynamic> password) {
    showDialog(
      context: context,
      builder: (context) => _PasswordDetailsDialog(
        password: password,
        accentColor: widget.accentColor,
        obscurePassword: _obscurePasswords,
      ),
    );
  }

  void _showAddPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => _PasswordEntryDialog(
        accentColor: widget.accentColor,
        onSave: (data) async {
          final success = await widget.syncService.savePasswordWithCredentialManager(
            url: data['url']!,
            username: data['username']!,
            password: data['password']!,
          );
          if (success) {
            _loadPasswords();
            _showSuccess('Password saved successfully');
          } else {
            _showError('Failed to save password');
          }
        },
      ),
    );
  }

  void _showEditPasswordDialog(Map<String, dynamic> password) {
    showDialog(
      context: context,
      builder: (context) => _PasswordEntryDialog(
        password: password,
        accentColor: widget.accentColor,
        onSave: (data) async {
          final success = await widget.syncService.updatePassword(
            password['id'],
            url: data['url'],
            username: data['username'],
            password: data['password'],
            title: data['title'],
          );
          if (success) {
            _loadPasswords();
            _showSuccess('Password updated successfully');
          } else {
            _showError('Failed to update password');
          }
        },
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> password) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Password?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently delete the password for "${password['title']}".',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await widget.syncService.deletePassword(password['id']);
              if (success) {
                _loadPasswords();
                _showSuccess('Password deleted');
              } else {
                _showError('Failed to delete password');
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red[300])),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  String _getPasswordStrength(String password) {
    if (password.length < 6) return 'WEAK';
    if (password.length < 8) return 'FAIR';

    bool hasUpper = password.contains(RegExp(r'[A-Z]'));
    bool hasLower = password.contains(RegExp(r'[a-z]'));
    bool hasNumber = password.contains(RegExp(r'[0-9]'));
    bool hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    int score = 0;
    if (hasUpper) score++;
    if (hasLower) score++;
    if (hasNumber) score++;
    if (hasSpecial) score++;
    if (password.length >= 12) score++;

    if (score >= 4) return 'STRONG';
    if (score >= 3) return 'GOOD';
    return 'FAIR';
  }

  Color _getPasswordStrengthColor(String strength) {
    switch (strength) {
      case 'STRONG': return Colors.green;
      case 'GOOD': return Colors.blue;
      case 'FAIR': return Colors.orange;
      default: return Colors.red;
    }
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    return '${(diff.inDays / 30).floor()} months ago';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[700],
      ),
    );
  }
}

// ============================================================================
// PASSWORD DETAILS DIALOG
// ============================================================================

class _PasswordDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> password;
  final Color accentColor;
  final bool obscurePassword;

  const _PasswordDetailsDialog({
    required this.password,
    required this.accentColor,
    required this.obscurePassword,
  });

  @override
  State<_PasswordDetailsDialog> createState() => _PasswordDetailsDialogState();
}

class _PasswordDetailsDialogState extends State<_PasswordDetailsDialog> {
  late bool _obscurePassword;

  @override
  void initState() {
    super.initState();
    _obscurePassword = widget.obscurePassword;
  }

  @override
  Widget build(BuildContext context) {
    final password = widget.password;
    final title = password['title']?.toString() ?? 'Untitled';
    final url = password['url']?.toString() ?? '';
    final username = password['username']?.toString() ?? '';
    final passwordValue = password['password']?.toString() ?? '';
    final source = password['source']?.toString() ?? 'manual';
    final createdAt = DateTime.tryParse(password['createdAt'] ?? '');
    final updatedAt = DateTime.tryParse(password['updatedAt'] ?? '');

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: widget.accentColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Website', url, Icons.language, canCopy: true),
            _buildDetailRow('Username', username, Icons.person, canCopy: true),
            _buildDetailRow(
              'Password',
              _obscurePassword ? '•' * passwordValue.length : passwordValue,
              Icons.key,
              canCopy: true,
              trailing: IconButton(
                icon: Icon(
                  _obscurePassword ? Iconsax.eye : Iconsax.eye_slash,
                  color: widget.accentColor,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            const Divider(color: Colors.grey),
            _buildDetailRow('Source', source == 'import' ? 'Imported from CSV' : 'Added manually', Icons.info),
            if (createdAt != null)
              _buildDetailRow('Created', _formatDetailDate(createdAt), Icons.schedule),
            if (updatedAt != null)
              _buildDetailRow('Updated', _formatDetailDate(updatedAt), Icons.update),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, {bool canCopy = false, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: widget.accentColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isNotEmpty ? value : 'Not provided',
                  style: TextStyle(
                    color: value.isNotEmpty ? Colors.white : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else if (canCopy && value.isNotEmpty)
            IconButton(
              icon: Icon(Icons.copy, color: Colors.grey[500], size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied'),
                    backgroundColor: Colors.green[700],
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatDetailDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// PASSWORD ENTRY DIALOG (Add/Edit)
// ============================================================================

class _PasswordEntryDialog extends StatefulWidget {
  final Map<String, dynamic>? password;
  final Color accentColor;
  final Function(Map<String, String>) onSave;

  const _PasswordEntryDialog({
    this.password,
    required this.accentColor,
    required this.onSave,
  });

  @override
  State<_PasswordEntryDialog> createState() => _PasswordEntryDialogState();
}

class _PasswordEntryDialogState extends State<_PasswordEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.password != null) {
      _titleController.text = widget.password!['title']?.toString() ?? '';
      _urlController.text = widget.password!['url']?.toString() ?? '';
      _usernameController.text = widget.password!['username']?.toString() ?? '';
      _passwordController.text = widget.password!['password']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.password != null;

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Password' : 'Add Password',
                      style: TextStyle(
                        color: widget.accentColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _titleController,
                label: 'Site Name',
                hint: 'e.g. Google, Facebook',
                icon: Icons.title,
                validator: (value) => value?.trim().isEmpty == true ? 'Site name is required' : null,
              ),
              _buildTextField(
                controller: _urlController,
                label: 'Website URL',
                hint: 'https://example.com',
                icon: Icons.language,
                validator: (value) => value?.trim().isEmpty == true ? 'URL is required' : null,
              ),
              _buildTextField(
                controller: _usernameController,
                label: 'Username/Email',
                hint: 'username@example.com',
                icon: Icons.person,
                validator: (value) => value?.trim().isEmpty == true ? 'Username is required' : null,
              ),
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'Enter a strong password',
                icon: Icons.key,
                obscureText: _obscurePassword,
                validator: (value) => value?.trim().isEmpty == true ? 'Password is required' : null,
                trailing: IconButton(
                  icon: Icon(
                    _obscurePassword ? Iconsax.eye : Iconsax.eye_slash,
                    color: widget.accentColor,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Colors.grey),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        foregroundColor: Colors.black,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isEditing ? 'Update' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? trailing,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white),
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: widget.accentColor),
          suffixIcon: trailing,
          labelStyle: TextStyle(color: Colors.grey[400]),
          hintStyle: TextStyle(color: Colors.grey[600]),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey[600]!),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: widget.accentColor),
            borderRadius: BorderRadius.circular(8),
          ),
          errorBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.red),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.red),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final data = {
        'title': _titleController.text.trim(),
        'url': _urlController.text.trim(),
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
      };

      await widget.onSave(data);
      Navigator.pop(context);
    } finally {
      setState(() => _isLoading = false);
    }
  }
}