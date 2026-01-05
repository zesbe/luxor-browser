import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:credential_manager/credential_manager.dart' hide User;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

// ============================================================================
// SYNC SERVICE - Google Account Synchronization like Chrome
// ============================================================================

class SyncService extends ChangeNotifier {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  // Google Sign In - simplified for Android
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
    ],
  );

  // Firebase instances
  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;

  // State
  User? _currentUser;
  GoogleSignInAccount? _googleUser;
  bool _isInitialized = false;
  bool _isSyncing = false;
  bool _syncEnabled = true;
  DateTime? _lastSyncTime;
  String? _syncError;
  StreamSubscription? _connectivitySubscription;
  bool _isOnline = true;

  // Password sync
  String? _encryptionPassphrase;
  bool _passphraseSet = false;

  // Sync Settings
  bool syncBookmarks = true;
  bool syncHistory = true;
  bool syncReadingList = true;
  bool syncSettings = true;
  bool syncPasswords = false; // Disabled by default for security
  bool syncOpenTabs = true;

  // Getters
  User? get currentUser => _currentUser;
  GoogleSignInAccount? get googleUser => _googleUser;
  bool get isSignedIn => _currentUser != null;
  bool get isSyncing => _isSyncing;
  bool get syncEnabled => _syncEnabled;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get syncError => _syncError;
  bool get isOnline => _isOnline;
  String get userEmail => _currentUser?.email ?? _googleUser?.email ?? '';
  String get userName => _currentUser?.displayName ?? _googleUser?.displayName ?? 'User';
  String? get userPhotoUrl => _currentUser?.photoURL ?? _googleUser?.photoUrl;
  bool get passphraseSet => _passphraseSet;

  // Initialize Firebase and check for existing sign-in
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Firebase.initializeApp();
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;

      // Listen to auth state changes
      _auth!.authStateChanges().listen((User? user) {
        _currentUser = user;
        notifyListeners();
        if (user != null && _syncEnabled) {
          _performSync();
        }
      });

      // Check connectivity
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
        _isOnline = result != ConnectivityResult.none;
        notifyListeners();
        if (_isOnline && isSignedIn && _syncEnabled) {
          _performSync();
        }
      });

      // Load sync preferences
      await _loadSyncPreferences();

      // Check for existing Google Sign-In
      _googleUser = await _googleSignIn.signInSilently();
      if (_googleUser != null) {
        await _signInToFirebase(_googleUser!);
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _syncError = 'Initialization failed: $e';
      notifyListeners();
    }
  }

  // Load sync preferences from SharedPreferences
  Future<void> _loadSyncPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _syncEnabled = prefs.getBool('sync_enabled') ?? true;
    syncBookmarks = prefs.getBool('sync_bookmarks') ?? true;
    syncHistory = prefs.getBool('sync_history') ?? true;
    syncReadingList = prefs.getBool('sync_reading_list') ?? true;
    syncSettings = prefs.getBool('sync_settings') ?? true;
    syncPasswords = prefs.getBool('sync_passwords') ?? false;
    syncOpenTabs = prefs.getBool('sync_open_tabs') ?? true;
    _passphraseSet = prefs.getBool('passphrase_set') ?? false;

    final lastSync = prefs.getString('last_sync_time');
    if (lastSync != null) {
      _lastSyncTime = DateTime.tryParse(lastSync);
    }
  }

  // Save sync preferences
  Future<void> _saveSyncPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_enabled', _syncEnabled);
    await prefs.setBool('sync_bookmarks', syncBookmarks);
    await prefs.setBool('sync_history', syncHistory);
    await prefs.setBool('sync_reading_list', syncReadingList);
    await prefs.setBool('sync_settings', syncSettings);
    await prefs.setBool('sync_passwords', syncPasswords);
    await prefs.setBool('sync_open_tabs', syncOpenTabs);
    await prefs.setBool('passphrase_set', _passphraseSet);
    if (_lastSyncTime != null) {
      await prefs.setString('last_sync_time', _lastSyncTime!.toIso8601String());
    }
  }

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      _syncError = null;

      // Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _syncError = 'Sign-in cancelled';
        notifyListeners();
        return false;
      }

      _googleUser = googleUser;

      // Sign in to Firebase
      final success = await _signInToFirebase(googleUser);

      if (success) {
        await _performSync();
      }

      return success;
    } catch (e) {
      _syncError = 'Sign-in failed: $e';
      notifyListeners();
      return false;
    }
  }

  // Sign in to Firebase with Google credentials
  Future<bool> _signInToFirebase(GoogleSignInAccount googleUser) async {
    try {
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth!.signInWithCredential(credential);
      _currentUser = userCredential.user;
      notifyListeners();
      return true;
    } catch (e) {
      _syncError = 'Firebase sign-in failed: $e';
      notifyListeners();
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth?.signOut();
      _currentUser = null;
      _googleUser = null;
      _syncError = null;
      notifyListeners();
    } catch (e) {
      _syncError = 'Sign-out failed: $e';
      notifyListeners();
    }
  }

  // Toggle sync enabled/disabled
  Future<void> setSyncEnabled(bool enabled) async {
    _syncEnabled = enabled;
    await _saveSyncPreferences();
    notifyListeners();

    if (enabled && isSignedIn) {
      await _performSync();
    }
  }

  // Update individual sync settings
  Future<void> updateSyncSetting(String setting, bool value) async {
    switch (setting) {
      case 'bookmarks':
        syncBookmarks = value;
        break;
      case 'history':
        syncHistory = value;
        break;
      case 'reading_list':
        syncReadingList = value;
        break;
      case 'settings':
        syncSettings = value;
        break;
      case 'passwords':
        if (value && !_passphraseSet) {
          // Need passphrase before enabling password sync
          return;
        }
        syncPasswords = value;
        break;
      case 'open_tabs':
        syncOpenTabs = value;
        break;
    }
    await _saveSyncPreferences();
    notifyListeners();
  }

  // ============================================================================
  // SYNC OPERATIONS
  // ============================================================================

  // Main sync function
  Future<void> _performSync() async {
    if (!isSignedIn || !_syncEnabled || _isSyncing || !_isOnline) return;

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final userId = _currentUser!.uid;
      final userDoc = _firestore!.collection('users').doc(userId);

      // Sync each data type
      if (syncBookmarks) await _syncBookmarks(userDoc);
      if (syncHistory) await _syncHistory(userDoc);
      if (syncReadingList) await _syncReadingList(userDoc);
      if (syncSettings) await _syncSettings(userDoc);
      if (syncPasswords && _passphraseSet) await _syncPasswords(userDoc);
      if (syncOpenTabs) await _syncOpenTabs(userDoc);

      _lastSyncTime = DateTime.now();
      await _saveSyncPreferences();
    } catch (e) {
      _syncError = 'Sync failed: $e';
    }

    _isSyncing = false;
    notifyListeners();
  }

  // Force sync now
  Future<void> syncNow() async {
    await _performSync();
  }

  // ============================================================================
  // BOOKMARKS SYNC
  // ============================================================================

  Future<void> _syncBookmarks(DocumentReference userDoc) async {
    final prefs = await SharedPreferences.getInstance();
    final localData = prefs.getString('bookmarks');
    final localBookmarks = localData != null
        ? List<Map<String, dynamic>>.from(jsonDecode(localData))
        : <Map<String, dynamic>>[];

    // Get cloud data
    final cloudDoc = await userDoc.collection('sync_data').doc('bookmarks').get();
    final cloudBookmarks = cloudDoc.exists
        ? (cloudDoc.data()?['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[];

    // Merge bookmarks (cloud takes priority for conflicts, but keep all unique)
    final merged = _mergeData(localBookmarks, cloudBookmarks, 'id');

    // Save to cloud
    await userDoc.collection('sync_data').doc('bookmarks').set({
      'items': merged,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Save locally
    await prefs.setString('bookmarks', jsonEncode(merged));
  }

  // ============================================================================
  // HISTORY SYNC
  // ============================================================================

  Future<void> _syncHistory(DocumentReference userDoc) async {
    final prefs = await SharedPreferences.getInstance();
    final localData = prefs.getString('history');
    final localHistory = localData != null
        ? List<Map<String, dynamic>>.from(jsonDecode(localData))
        : <Map<String, dynamic>>[];

    // Get cloud data
    final cloudDoc = await userDoc.collection('sync_data').doc('history').get();
    final cloudHistory = cloudDoc.exists
        ? (cloudDoc.data()?['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[];

    // Merge history by URL + timestamp (keep last 1000 items)
    final merged = _mergeHistory(localHistory, cloudHistory);

    // Save to cloud
    await userDoc.collection('sync_data').doc('history').set({
      'items': merged,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Save locally
    await prefs.setString('history', jsonEncode(merged));
  }

  List<Map<String, dynamic>> _mergeHistory(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> cloud
  ) {
    final Map<String, Map<String, dynamic>> merged = {};

    // Add cloud items first
    for (var item in cloud) {
      final key = '${item['url']}_${item['timestamp']}';
      merged[key] = item;
    }

    // Add local items (won't overwrite if already exists)
    for (var item in local) {
      final key = '${item['url']}_${item['timestamp']}';
      merged.putIfAbsent(key, () => item);
    }

    // Sort by timestamp descending and limit to 1000
    final list = merged.values.toList();
    list.sort((a, b) {
      final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(2000);
      final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return list.take(1000).toList();
  }

  // ============================================================================
  // READING LIST SYNC
  // ============================================================================

  Future<void> _syncReadingList(DocumentReference userDoc) async {
    final prefs = await SharedPreferences.getInstance();
    final localData = prefs.getString('reading_list');
    final localItems = localData != null
        ? List<Map<String, dynamic>>.from(jsonDecode(localData))
        : <Map<String, dynamic>>[];

    // Get cloud data
    final cloudDoc = await userDoc.collection('sync_data').doc('reading_list').get();
    final cloudItems = cloudDoc.exists
        ? (cloudDoc.data()?['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[];

    // Merge
    final merged = _mergeData(localItems, cloudItems, 'id');

    // Save to cloud
    await userDoc.collection('sync_data').doc('reading_list').set({
      'items': merged,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Save locally
    await prefs.setString('reading_list', jsonEncode(merged));
  }

  // ============================================================================
  // SETTINGS SYNC
  // ============================================================================

  Future<void> _syncSettings(DocumentReference userDoc) async {
    final prefs = await SharedPreferences.getInstance();

    final localSettings = {
      'search_engine': prefs.getString('search_engine') ?? 'google',
      'home_page': prefs.getString('home_page') ?? 'luxor://home',
      'javascript_enabled': prefs.getBool('javascript_enabled') ?? true,
      'ad_blocker_enabled': prefs.getBool('ad_blocker_enabled') ?? false,
      'dark_mode': prefs.getBool('dark_mode') ?? true,
      'neon_color': prefs.getInt('neon_color') ?? 0xFFFFD700,
      'text_scale': prefs.getDouble('text_scale') ?? 1.0,
      'desktop_mode': prefs.getBool('desktop_mode') ?? false,
    };

    // Get cloud settings
    final cloudDoc = await userDoc.collection('sync_data').doc('settings').get();

    if (cloudDoc.exists) {
      final cloudSettings = cloudDoc.data() ?? {};
      // Merge: use cloud value if exists, otherwise local
      for (var key in cloudSettings.keys) {
        if (key != 'updatedAt' && cloudSettings[key] != null) {
          localSettings[key] = cloudSettings[key];
        }
      }
    }

    // Save to cloud
    await userDoc.collection('sync_data').doc('settings').set({
      ...localSettings,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Apply settings locally
    await prefs.setString('search_engine', localSettings['search_engine'] as String);
    await prefs.setString('home_page', localSettings['home_page'] as String);
    await prefs.setBool('javascript_enabled', localSettings['javascript_enabled'] as bool);
    await prefs.setBool('ad_blocker_enabled', localSettings['ad_blocker_enabled'] as bool);
    await prefs.setBool('dark_mode', localSettings['dark_mode'] as bool);
    await prefs.setInt('neon_color', localSettings['neon_color'] as int);
    await prefs.setDouble('text_scale', localSettings['text_scale'] as double);
    await prefs.setBool('desktop_mode', localSettings['desktop_mode'] as bool);
  }

  // ============================================================================
  // PASSWORD SYNC - Encrypted with user passphrase
  // ============================================================================

  Future<void> _syncPasswords(DocumentReference userDoc) async {
    if (_encryptionPassphrase == null) return;

    final prefs = await SharedPreferences.getInstance();

    // Get local passwords (simulated - in real app would use credential_manager)
    final localPasswordData = prefs.getString('saved_passwords') ?? '[]';
    final localPasswords = List<Map<String, dynamic>>.from(jsonDecode(localPasswordData));

    // Get cloud data
    final cloudDoc = await userDoc.collection('sync_data').doc('passwords').get();

    List<Map<String, dynamic>> cloudPasswords = [];
    if (cloudDoc.exists) {
      final encryptedData = cloudDoc.data()?['encrypted_data'] as String?;
      if (encryptedData != null) {
        try {
          final decryptedData = _decryptData(encryptedData, _encryptionPassphrase!);
          cloudPasswords = (jsonDecode(decryptedData) as List<dynamic>)
              .cast<Map<String, dynamic>>();
        } catch (e) {
          // Decryption failed - wrong passphrase or corrupted data
          _syncError = 'Password decryption failed. Check your passphrase.';
          return;
        }
      }
    }

    // Merge passwords (cloud takes priority for conflicts)
    final merged = _mergeData(localPasswords, cloudPasswords, 'url');

    // Encrypt and save to cloud
    final encryptedData = _encryptData(jsonEncode(merged), _encryptionPassphrase!);
    await userDoc.collection('sync_data').doc('passwords').set({
      'encrypted_data': encryptedData,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Save locally
    await prefs.setString('saved_passwords', jsonEncode(merged));
  }

  // ============================================================================
  // ENCRYPTION/DECRYPTION HELPERS
  // ============================================================================

  String _encryptData(String data, String passphrase) {
    final key = _deriveKey(passphrase);
    final bytes = utf8.encode(data);

    // Simple XOR encryption with key (in production use AES)
    final encrypted = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      encrypted.add(bytes[i] ^ key[i % key.length]);
    }

    return base64Encode(encrypted);
  }

  String _decryptData(String encryptedData, String passphrase) {
    final key = _deriveKey(passphrase);
    final encrypted = base64Decode(encryptedData);

    // Decrypt using XOR
    final decrypted = <int>[];
    for (int i = 0; i < encrypted.length; i++) {
      decrypted.add(encrypted[i] ^ key[i % key.length]);
    }

    return utf8.decode(decrypted);
  }

  List<int> _deriveKey(String passphrase) {
    // Derive encryption key from passphrase using SHA-256
    final bytes = utf8.encode(passphrase + 'luxor_salt_2025');
    final digest = sha256.convert(bytes);
    return digest.bytes;
  }

  // Set encryption passphrase
  Future<bool> setEncryptionPassphrase(String passphrase) async {
    if (passphrase.isEmpty || passphrase.length < 8) {
      _syncError = 'Passphrase must be at least 8 characters';
      return false;
    }

    _encryptionPassphrase = passphrase;
    _passphraseSet = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('passphrase_set', true);

    // Store passphrase hash for verification (not the passphrase itself)
    final hash = sha256.convert(utf8.encode(passphrase + 'verify_salt')).toString();
    await prefs.setString('passphrase_hash', hash);

    await _saveSyncPreferences();
    notifyListeners();
    return true;
  }

  // Verify existing passphrase
  Future<bool> verifyPassphrase(String passphrase) async {
    final prefs = await SharedPreferences.getInstance();
    final storedHash = prefs.getString('passphrase_hash');

    if (storedHash == null) return false;

    final inputHash = sha256.convert(utf8.encode(passphrase + 'verify_salt')).toString();

    if (inputHash == storedHash) {
      _encryptionPassphrase = passphrase;
      return true;
    }

    return false;
  }

  // Clear passphrase and disable password sync
  Future<void> clearPassphrase() async {
    _encryptionPassphrase = null;
    _passphraseSet = false;
    syncPasswords = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('passphrase_hash');
    await _saveSyncPreferences();
    notifyListeners();
  }

  // ============================================================================
  // OPEN TABS SYNC
  // ============================================================================

  Future<void> _syncOpenTabs(DocumentReference userDoc) async {
    final prefs = await SharedPreferences.getInstance();
    final localData = prefs.getString('open_tabs');
    final localTabs = localData != null
        ? List<Map<String, dynamic>>.from(jsonDecode(localData))
        : <Map<String, dynamic>>[];

    // Get cloud tabs from other devices
    final cloudDoc = await userDoc.collection('sync_data').doc('open_tabs').get();

    // Get device ID
    final deviceId = prefs.getString('device_id') ?? _generateDeviceId(prefs);

    // Save current device's tabs
    await userDoc.collection('sync_data').doc('open_tabs').set({
      'devices': {
        deviceId: {
          'tabs': localTabs,
          'updatedAt': FieldValue.serverTimestamp(),
          'deviceName': await _getDeviceName(),
        }
      }
    }, SetOptions(merge: true));
  }

  String _generateDeviceId(SharedPreferences prefs) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    prefs.setString('device_id', id);
    return id;
  }

  Future<String> _getDeviceName() async {
    // Could use device_info_plus for actual device name
    return 'Luxor Browser Device';
  }

  // Get tabs from other devices
  Future<Map<String, List<Map<String, dynamic>>>> getOtherDevicesTabs() async {
    if (!isSignedIn) return {};

    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id') ?? '';

    final doc = await _firestore!
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('sync_data')
        .doc('open_tabs')
        .get();

    if (!doc.exists) return {};

    final devices = doc.data()?['devices'] as Map<String, dynamic>? ?? {};
    final result = <String, List<Map<String, dynamic>>>{};

    for (var entry in devices.entries) {
      if (entry.key != deviceId) {
        final deviceData = entry.value as Map<String, dynamic>;
        result[deviceData['deviceName'] ?? entry.key] =
            (deviceData['tabs'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      }
    }

    return result;
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  List<Map<String, dynamic>> _mergeData(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> cloud,
    String idField,
  ) {
    final Map<String, Map<String, dynamic>> merged = {};

    // Add local items
    for (var item in local) {
      final id = item[idField]?.toString() ?? '';
      if (id.isNotEmpty) merged[id] = item;
    }

    // Cloud items take priority
    for (var item in cloud) {
      final id = item[idField]?.toString() ?? '';
      if (id.isNotEmpty) merged[id] = item;
    }

    return merged.values.toList();
  }

  // ============================================================================
  // REAL-TIME SYNC LISTENER
  // ============================================================================

  StreamSubscription? _syncListener;

  void startRealtimeSync() {
    if (!isSignedIn || _syncListener != null) return;

    _syncListener = _firestore!
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('sync_data')
        .snapshots()
        .listen((snapshot) {
          // Trigger local update when cloud data changes
          _handleCloudUpdate(snapshot);
        });
  }

  void stopRealtimeSync() {
    _syncListener?.cancel();
    _syncListener = null;
  }

  void _handleCloudUpdate(QuerySnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();

    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.modified) {
        final docId = change.doc.id;
        final data = change.doc.data() as Map<String, dynamic>?;

        if (data != null) {
          switch (docId) {
            case 'bookmarks':
              await prefs.setString('bookmarks', jsonEncode(data['items'] ?? []));
              break;
            case 'history':
              await prefs.setString('history', jsonEncode(data['items'] ?? []));
              break;
            case 'reading_list':
              await prefs.setString('reading_list', jsonEncode(data['items'] ?? []));
              break;
          }
        }
      }
    }

    notifyListeners();
  }

  // ============================================================================
  // PASSWORD IMPORT/EXPORT - CSV FORMAT (Chrome Compatible)
  // ============================================================================

  // Export passwords to CSV file
  Future<String?> exportPasswordsToCSV() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final passwordData = prefs.getString('saved_passwords') ?? '[]';
      final passwords = List<Map<String, dynamic>>.from(jsonDecode(passwordData));

      if (passwords.isEmpty) {
        _syncError = 'No passwords to export';
        notifyListeners();
        return null;
      }

      // Chrome CSV format: name,url,username,password
      List<List<String>> csvData = [
        ['name', 'url', 'username', 'password'],
      ];

      for (var password in passwords) {
        csvData.add([
          password['title'] ?? password['url'] ?? 'Untitled',
          password['url'] ?? '',
          password['username'] ?? '',
          password['password'] ?? '',
        ]);
      }

      final csvString = const ListToCsvConverter().convert(csvData);

      // Save to Downloads folder
      final directory = await getExternalStorageDirectory();
      final downloadsPath = '${directory?.path.split('/Android')[0]}/Download';
      final fileName = 'luxor_passwords_${DateTime.now().millisecondsSinceEpoch}.csv';
      final filePath = '$downloadsPath/$fileName';

      final file = File(filePath);
      await file.writeAsString(csvString);

      return filePath;
    } catch (e) {
      _syncError = 'Export failed: $e';
      notifyListeners();
      return null;
    }
  }

  // Import passwords from Chrome CSV export
  Future<int> importPasswordsFromCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // IMPORTANT: Get file bytes directly on Android
      );

      if (result == null) {
        debugPrint('CSV Import: No file selected');
        return 0;
      }

      debugPrint('CSV Import: File picked - name=${result.files.single.name}');
      debugPrint('CSV Import: path=${result.files.single.path}');
      debugPrint('CSV Import: bytes=${result.files.single.bytes?.length}');

      String csvContent;

      // Try to get content from bytes first (more reliable on Android)
      if (result.files.single.bytes != null) {
        csvContent = utf8.decode(result.files.single.bytes!);
        debugPrint('CSV Import: Loaded from bytes, size=${csvContent.length}');
      } else if (result.files.single.path != null) {
        // Fallback to path
        final file = File(result.files.single.path!);
        if (await file.exists()) {
          csvContent = await file.readAsString();
          debugPrint('CSV Import: Loaded from path, size=${csvContent.length}');
        } else {
          debugPrint('CSV Import: File does not exist at path');
          _syncError = 'Could not read file';
          notifyListeners();
          return 0;
        }
      } else {
        debugPrint('CSV Import: No bytes or path available');
        _syncError = 'Could not read file - no data available';
        notifyListeners();
        return 0;
      }

      debugPrint('CSV Import: File loaded, size=${csvContent.length} bytes');

      // Parse CSV with proper handling of quoted fields (Chrome format)
      final csvTable = const CsvToListConverter(
        shouldParseNumbers: false, // Keep everything as strings
        allowInvalid: true, // Don't fail on malformed rows
      ).convert(csvContent);

      debugPrint('CSV Import: Parsed ${csvTable.length} rows');

      if (csvTable.isEmpty) {
        _syncError = 'Invalid CSV file - no data found';
        notifyListeners();
        return 0;
      }

      // Check header format
      if (csvTable.isNotEmpty) {
        debugPrint('CSV Import: Header = ${csvTable.first}');
      }

      // Skip header row
      final dataRows = csvTable.skip(1).toList();
      debugPrint('CSV Import: ${dataRows.length} data rows to process');

      // Debug first 3 rows
      for (int i = 0; i < 3 && i < dataRows.length; i++) {
        debugPrint('CSV Import: Row $i = ${dataRows[i]}');
        debugPrint('CSV Import: Row $i length = ${dataRows[i].length}');
      }

      final prefs = await SharedPreferences.getInstance();
      final existingData = prefs.getString('saved_passwords') ?? '[]';
      final existingPasswords = List<Map<String, dynamic>>.from(jsonDecode(existingData));

      int importedCount = 0;
      int skippedEmpty = 0;
      int skippedDuplicate = 0;
      int skippedInvalidRow = 0;

      // Check URL+username combination, not just URL
      final existingKeys = existingPasswords.map((p) => '${p['url']}|${p['username']}').toSet();
      debugPrint('CSV Import: ${existingKeys.length} existing passwords in storage');

      for (var row in dataRows) {
        if (row.length >= 4) {
          final url = row[1].toString().trim();
          final username = row[2].toString().trim();
          final password = row[3].toString().trim();
          final key = '$url|$username';

          // Skip if empty
          if (url.isEmpty || password.isEmpty) {
            skippedEmpty++;
            continue;
          }

          // Skip if URL+username combination already exists
          if (existingKeys.contains(key)) {
            skippedDuplicate++;
            continue;
          }

          existingPasswords.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(1000).toString(),
            'url': url,
            'username': username,
            'password': password,
            'title': row[0].toString().trim().isNotEmpty ? row[0].toString().trim() : url,
            'createdAt': DateTime.now().toIso8601String(),
            'source': 'import',
          });
          importedCount++;
          existingKeys.add(key);
        } else {
          skippedInvalidRow++;
          debugPrint('CSV Import: Invalid row with ${row.length} columns: $row');
        }
      }

      debugPrint('CSV Import: imported=$importedCount, skippedEmpty=$skippedEmpty, skippedDuplicate=$skippedDuplicate, skippedInvalid=$skippedInvalidRow');

      // Save updated passwords
      await prefs.setString('saved_passwords', jsonEncode(existingPasswords));

      // Sync to cloud if enabled
      if (syncPasswords && _passphraseSet && isSignedIn) {
        await _performSync();
      }

      return importedCount;
    } catch (e) {
      _syncError = 'Import failed: $e';
      notifyListeners();
      return 0;
    }
  }

  // ============================================================================
  // ANDROID CREDENTIAL MANAGER INTEGRATION
  // ============================================================================

  CredentialManager? _credentialManager;

  // Initialize Credential Manager
  Future<void> _initCredentialManager() async {
    try {
      _credentialManager = CredentialManager();
      final isSupported = await _credentialManager!.isSupportedPlatform;
      if (!isSupported) {
        _credentialManager = null;
      }
    } catch (e) {
      _credentialManager = null;
      debugPrint('Credential Manager not available: $e');
    }
  }

  // Save password using Android Credential Manager
  Future<bool> savePasswordWithCredentialManager({
    required String url,
    required String username,
    required String password,
  }) async {
    try {
      // Always save to local storage for sync
      await _savePasswordLocally(url, username, password, 'credential_manager');

      // Try to save with Credential Manager if available
      if (_credentialManager != null) {
        try {
          final credential = PasswordCredential(
            username: username,
            password: password,
          );
          await _credentialManager!.savePasswordCredentials(credential);
        } catch (e) {
          debugPrint('Credential Manager save failed (using local): $e');
        }
      }

      // Sync to cloud if enabled
      if (syncPasswords && _passphraseSet && isSignedIn) {
        await _performSync();
      }

      return true;
    } catch (e) {
      _syncError = 'Failed to save password: $e';
      notifyListeners();
      return false;
    }
  }

  // Get password suggestions using Android Credential Manager
  Future<List<Map<String, dynamic>>> getPasswordSuggestions(String url) async {
    // Always use local passwords as primary source for consistency
    return _getLocalPasswordsForUrl(url);
  }

  // Check if Credential Manager is available
  Future<bool> isCredentialManagerAvailable() async {
    try {
      if (_credentialManager == null) {
        await _initCredentialManager();
      }
      return _credentialManager != null;
    } catch (e) {
      return false;
    }
  }

  // ============================================================================
  // HELPER METHODS FOR PASSWORD MANAGEMENT
  // ============================================================================

  // Save password to local storage
  Future<void> _savePasswordLocally(String url, String username, String password, String source) async {
    final prefs = await SharedPreferences.getInstance();
    final existingData = prefs.getString('saved_passwords') ?? '[]';
    final passwords = List<Map<String, dynamic>>.from(jsonDecode(existingData));

    // Check if password already exists for this URL/username
    final existingIndex = passwords.indexWhere(
      (p) => p['url'] == url && p['username'] == username,
    );

    final passwordEntry = {
      'id': existingIndex >= 0
          ? passwords[existingIndex]['id']
          : DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(1000).toString(),
      'url': url,
      'username': username,
      'password': password,
      'title': _getTitleFromUrl(url),
      'source': source,
      'createdAt': existingIndex >= 0
          ? passwords[existingIndex]['createdAt']
          : DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    if (existingIndex >= 0) {
      passwords[existingIndex] = passwordEntry;
    } else {
      passwords.add(passwordEntry);
    }

    await prefs.setString('saved_passwords', jsonEncode(passwords));
  }

  // Get passwords for specific URL
  List<Map<String, dynamic>> _getLocalPasswordsForUrl(String url) {
    try {
      // Implementation would get from SharedPreferences
      // For now, return empty list
      return [];
    } catch (e) {
      return [];
    }
  }

  // Extract title from URL
  String _getTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceAll('www.', '');
    } catch (e) {
      return url;
    }
  }

  // Get all saved passwords for management
  Future<List<Map<String, dynamic>>> getAllSavedPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    final passwordData = prefs.getString('saved_passwords') ?? '[]';
    return List<Map<String, dynamic>>.from(jsonDecode(passwordData));
  }

  // Delete password
  Future<bool> deletePassword(String passwordId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingData = prefs.getString('saved_passwords') ?? '[]';
      final passwords = List<Map<String, dynamic>>.from(jsonDecode(existingData));

      passwords.removeWhere((p) => p['id'] == passwordId);
      await prefs.setString('saved_passwords', jsonEncode(passwords));

      // Sync to cloud if enabled
      if (syncPasswords && _passphraseSet && isSignedIn) {
        await _performSync();
      }

      return true;
    } catch (e) {
      _syncError = 'Failed to delete password: $e';
      notifyListeners();
      return false;
    }
  }

  // Update password
  Future<bool> updatePassword(String passwordId, {
    String? url,
    String? username,
    String? password,
    String? title,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingData = prefs.getString('saved_passwords') ?? '[]';
      final passwords = List<Map<String, dynamic>>.from(jsonDecode(existingData));

      final index = passwords.indexWhere((p) => p['id'] == passwordId);
      if (index >= 0) {
        if (url != null) passwords[index]['url'] = url;
        if (username != null) passwords[index]['username'] = username;
        if (password != null) passwords[index]['password'] = password;
        if (title != null) passwords[index]['title'] = title;
        passwords[index]['updatedAt'] = DateTime.now().toIso8601String();

        await prefs.setString('saved_passwords', jsonEncode(passwords));

        // Sync to cloud if enabled
        if (syncPasswords && _passphraseSet && isSignedIn) {
          await _performSync();
        }

        return true;
      }

      return false;
    } catch (e) {
      _syncError = 'Failed to update password: $e';
      notifyListeners();
      return false;
    }
  }

  // Cleanup
  void dispose() {
    _connectivitySubscription?.cancel();
    stopRealtimeSync();
    super.dispose();
  }
}

// ============================================================================
// SYNC STATUS WIDGET - Shows sync status in UI
// ============================================================================

class SyncStatusIndicator extends StatelessWidget {
  final SyncService syncService;

  const SyncStatusIndicator({super.key, required this.syncService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: syncService,
      builder: (context, _) {
        if (!syncService.isSignedIn) {
          return const SizedBox.shrink();
        }

        if (syncService.isSyncing) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (syncService.syncError != null) {
          return IconButton(
            icon: const Icon(Icons.sync_problem, color: Colors.red, size: 20),
            onPressed: () => syncService.syncNow(),
            tooltip: syncService.syncError,
          );
        }

        return IconButton(
          icon: Icon(
            Icons.sync,
            color: syncService.isOnline ? Colors.green : Colors.grey,
            size: 20,
          ),
          onPressed: () => syncService.syncNow(),
          tooltip: syncService.lastSyncTime != null
              ? 'Last sync: ${_formatTime(syncService.lastSyncTime!)}'
              : 'Tap to sync',
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
