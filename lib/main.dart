import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/sync_service.dart';
import 'pages/sync_settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize SyncService
  final syncService = SyncService();
  await syncService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrowserProvider()),
        ChangeNotifierProvider(create: (_) => AiAgentProvider()),
        ChangeNotifierProvider(create: (_) => DevToolsProvider()),
        ChangeNotifierProvider.value(value: syncService),
      ],
      child: const LuxorBrowserApp(),
    ),
  );
}

class LuxorBrowserApp extends StatelessWidget {
  const LuxorBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);
    return MaterialApp(
      title: 'Luxor Browser',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: browser.neonColor,
          secondary: Colors.white,
          surface: const Color(0xFF121212),
        ),
      ),
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- DATA MODELS ---

class BrowserTab {
  final String id;
  String url, title;
  bool isIncognito;
  InAppWebViewController? controller;
  Uint8List? thumbnail;
  String? favicon;
  int progress = 0;
  DateTime? loadStartTime;
  BrowserTab({required this.id, this.url = "luxor://home", this.title = "Start Page", this.isIncognito = false});
}

class HistoryItem {
  final String url, title;
  final DateTime timestamp;
  HistoryItem({required this.url, required this.title, DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();
  Map<String, dynamic> toJson() => {'url': url, 'title': title, 'timestamp': timestamp.toIso8601String()};
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    url: json['url'] ?? "",
    title: json['title'] ?? "",
    timestamp: json['timestamp'] != null ? DateTime.tryParse(json['timestamp']) : null,
  );
}

class BookmarkItem {
  String url, title;
  final String id;
  String folder;
  final DateTime createdAt;
  BookmarkItem({required this.url, required this.title, String? id, this.folder = "Default", DateTime? createdAt})
    : id = id ?? const Uuid().v4(), createdAt = createdAt ?? DateTime.now();
  Map<String, dynamic> toJson() => {'id': id, 'url': url, 'title': title, 'folder': folder, 'createdAt': createdAt.toIso8601String()};
  factory BookmarkItem.fromJson(Map<String, dynamic> json) => BookmarkItem(
    id: json['id'], url: json['url'] ?? "", title: json['title'] ?? "",
    folder: json['folder'] ?? "Default",
    createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
  );
}

class ReadingListItem {
  final String id, url, title;
  bool isRead;
  final DateTime addedAt;
  ReadingListItem({required this.url, required this.title, String? id, this.isRead = false, DateTime? addedAt})
    : id = id ?? const Uuid().v4(), addedAt = addedAt ?? DateTime.now();
  Map<String, dynamic> toJson() => {'id': id, 'url': url, 'title': title, 'isRead': isRead, 'addedAt': addedAt.toIso8601String()};
  factory ReadingListItem.fromJson(Map<String, dynamic> json) => ReadingListItem(
    id: json['id'], url: json['url'] ?? "", title: json['title'] ?? "",
    isRead: json['isRead'] ?? false,
    addedAt: json['addedAt'] != null ? DateTime.tryParse(json['addedAt']) : null,
  );
}

class SpeedDialItem {
  final String url, label;
  final int colorValue;
  SpeedDialItem({required this.url, required this.label, required this.colorValue});
  Map<String, dynamic> toJson() => {'url': url, 'label': label, 'color': colorValue};
  factory SpeedDialItem.fromJson(Map<String, dynamic> json) => SpeedDialItem(url: json['url'] ?? "", label: json['label'] ?? "", colorValue: json['color'] ?? 0xFFFFD700);
}

class UserScript {
  String id, name, code;
  bool active;
  UserScript({required this.id, required this.name, required this.code, this.active = true});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code, 'active': active};
  factory UserScript.fromJson(Map<String, dynamic> json) => UserScript(id: json['id'] ?? "", name: json['name'] ?? "", code: json['code'] ?? "", active: json['active'] ?? true);
}

class DownloadItem {
  final String id, url, filename;
  int progress;
  String status; // downloading, completed, failed, paused, queued
  final DateTime startedAt;
  String? filePath;
  int totalBytes;
  int downloadedBytes;
  double speed; // bytes per second
  String? mimeType;
  String? error;
  HttpClient? _httpClient;
  IOSink? _fileSink;
  StreamSubscription? _subscription;
  bool _isPaused = false;

  DownloadItem({
    required this.url,
    required this.filename,
    String? id,
    this.progress = 0,
    this.status = "queued",
    DateTime? startedAt,
    this.filePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.speed = 0,
    this.mimeType,
    this.error,
  }) : id = id ?? const Uuid().v4(), startedAt = startedAt ?? DateTime.now();

  String get formattedSpeed {
    if (speed < 1024) return "${speed.toStringAsFixed(0)} B/s";
    if (speed < 1024 * 1024) return "${(speed / 1024).toStringAsFixed(1)} KB/s";
    return "${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s";
  }

  String get formattedSize {
    if (totalBytes == 0) return "Unknown";
    if (totalBytes < 1024) return "$totalBytes B";
    if (totalBytes < 1024 * 1024) return "${(totalBytes / 1024).toStringAsFixed(1)} KB";
    if (totalBytes < 1024 * 1024 * 1024) return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  String get formattedDownloaded {
    if (downloadedBytes < 1024) return "$downloadedBytes B";
    if (downloadedBytes < 1024 * 1024) return "${(downloadedBytes / 1024).toStringAsFixed(1)} KB";
    if (downloadedBytes < 1024 * 1024 * 1024) return "${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(downloadedBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  String get eta {
    if (speed <= 0 || totalBytes <= 0) return "--:--";
    final remaining = totalBytes - downloadedBytes;
    final seconds = (remaining / speed).round();
    if (seconds < 60) return "${seconds}s";
    if (seconds < 3600) return "${seconds ~/ 60}m ${seconds % 60}s";
    return "${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m";
  }

  void cancel() {
    _subscription?.cancel();
    _fileSink?.close();
    _httpClient?.close(force: true);
    status = "failed";
    error = "Cancelled";
  }
}

// User Agent Presets
class UserAgentPreset {
  final String name;
  final String ua;
  final IconData icon;

  const UserAgentPreset({required this.name, required this.ua, required this.icon});

  static const List<UserAgentPreset> presets = [
    UserAgentPreset(
      name: "Default",
      ua: "",
      icon: Iconsax.mobile,
    ),
    UserAgentPreset(
      name: "Android Mobile",
      ua: "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      icon: Iconsax.mobile,
    ),
    UserAgentPreset(
      name: "iOS Mobile",
      ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
      icon: Icons.phone_iphone,
    ),
    UserAgentPreset(
      name: "Desktop Chrome",
      ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      icon: Iconsax.monitor,
    ),
    UserAgentPreset(
      name: "Desktop Safari",
      ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15",
      icon: Iconsax.monitor,
    ),
    UserAgentPreset(
      name: "Desktop Firefox",
      ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0",
      icon: Iconsax.monitor,
    ),
    UserAgentPreset(
      name: "iPad",
      ua: "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
      icon: Iconsax.mobile,
    ),
    UserAgentPreset(
      name: "Bot/Crawler",
      ua: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      icon: Iconsax.code_1,
    ),
  ];
}

// --- PROVIDERS ---

class DevToolsProvider extends ChangeNotifier {
  List<String> consoleLogs = [];
  void addLog(String message, ConsoleMessageLevel level) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final levelName = level.toString().split('.').last.toUpperCase();
    consoleLogs.add("[$timestamp] $levelName: $message");
    if (consoleLogs.length > 500) consoleLogs.removeAt(0);
    notifyListeners();
  }
  void clearLogs() { consoleLogs.clear(); notifyListeners(); }
}

class BrowserProvider extends ChangeNotifier {
  List<BrowserTab> tabs = [];
  int currentTabIndex = 0;
  List<HistoryItem> history = [];
  List<BookmarkItem> bookmarks = [];
  List<ReadingListItem> readingList = [];
  List<DownloadItem> downloads = [];
  List<UserScript> userScripts = [];
  List<SpeedDialItem> speedDials = [];

  // DNS over HTTPS Settings
  String dohProvider = "https://cloudflare-dns.com/dns-query"; // Cloudflare DoH
  bool isDohEnabled = true;

  // Available DoH Providers
  static const Map<String, String> dohProviders = {
    "Cloudflare": "https://cloudflare-dns.com/dns-query",
    "Google": "https://dns.google/dns-query",
    "Quad9": "https://dns.quad9.net/dns-query",
    "AdGuard": "https://dns.adguard.com/dns-query",
    "NextDNS": "https://dns.nextdns.io",
  };

  String searchEngine = "https://www.google.com/search?q=";
  String customUserAgent = "";
  String currentUserAgentPreset = "Default";
  bool isDesktopMode = false, isAdBlockEnabled = true, isForceDarkWeb = false, isJsEnabled = true, isImagesEnabled = true;
  bool isBiometricEnabled = false, isZenMode = false, isGameMode = false, isLocked = false;
  bool isTrackingProtection = true, isPopupBlocked = true, isCookiesEnabled = true;
  int blockedAdsCount = 0, blockedTrackersCount = 0;
  Color neonColor = const Color(0xFFFFD700);

  double progress = 0;
  bool isSecure = true, isMenuOpen = false, showFindBar = false, showAiSidebar = false, showTabGrid = false;
  bool isMediaPlaying = false;
  SslCertificate? sslCertificate;

  // Split View
  bool isSplitMode = false;
  List<int> splitTabIndices = [];
  int activeSplitIndex = 0;

  // Biometric
  bool _isAuthenticating = false;
  DateTime? _lastPausedTime;
  static const int _lockDelaySeconds = 5;

  TextEditingController urlController = TextEditingController(), findController = TextEditingController();
  stt.SpeechToText _speech = stt.SpeechToText();
  FlutterTts _flutterTts = FlutterTts();
  final LocalAuthentication auth = LocalAuthentication();
  bool isSpeaking = false;

  BrowserProvider() { _loadData(); _addNewTab(); _initTts(); }

  BrowserTab get currentTab => tabs[currentTabIndex];

  InAppWebViewSettings getSettings([int? tabIndex]) {
    final tab = tabIndex != null && tabIndex < tabs.length ? tabs[tabIndex] : currentTab;
    return InAppWebViewSettings(
      isInspectable: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      javaScriptEnabled: isJsEnabled,
      loadsImagesAutomatically: isImagesEnabled,
      cacheEnabled: !tab.isIncognito,
      domStorageEnabled: !tab.isIncognito,
      databaseEnabled: true,
      useWideViewPort: true,
      loadWithOverviewMode: true,
      safeBrowsingEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowFileAccessFromFileURLs: true,
      allowUniversalAccessFromFileURLs: true,
      supportMultipleWindows: true,
      javaScriptCanOpenWindowsAutomatically: !isPopupBlocked,
      thirdPartyCookiesEnabled: isCookiesEnabled,
      hardwareAcceleration: true,
      transparentBackground: true,
      // DNS over HTTPS - using content blockers for tracking protection
      contentBlockers: isTrackingProtection ? _getContentBlockers() : [],
      userAgent: customUserAgent.isNotEmpty ? customUserAgent : (isDesktopMode
        ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        : "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
    );
  }

  List<ContentBlocker> _getContentBlockers() {
    return [
      // Block trackers
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".*", resourceType: [ContentBlockerTriggerResourceType.SCRIPT]),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK, selector: "[src*='tracking'], [src*='analytics'], [src*='tracker']"),
      ),
    ];
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    _flutterTts.setCompletionHandler(() { isSpeaking = false; notifyListeners(); });
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    searchEngine = prefs.getString('searchEngine') ?? "https://www.google.com/search?q=";
    isAdBlockEnabled = prefs.getBool('adBlock') ?? true;
    isForceDarkWeb = prefs.getBool('forceDark') ?? false;
    isJsEnabled = prefs.getBool('jsEnabled') ?? true;
    isImagesEnabled = prefs.getBool('imagesEnabled') ?? true;
    isBiometricEnabled = prefs.getBool('biometric') ?? false;
    isDohEnabled = prefs.getBool('dohEnabled') ?? true;
    dohProvider = prefs.getString('dohProvider') ?? "https://cloudflare-dns.com/dns-query";
    isTrackingProtection = prefs.getBool('trackingProtection') ?? true;
    isPopupBlocked = prefs.getBool('popupBlocked') ?? true;
    blockedAdsCount = prefs.getInt('blockedAds') ?? 0;
    blockedTrackersCount = prefs.getInt('blockedTrackers') ?? 0;
    customUserAgent = prefs.getString('customUserAgent') ?? "";
    currentUserAgentPreset = prefs.getString('userAgentPreset') ?? "Default";
    int? colorValue = prefs.getInt('neonColor'); if (colorValue != null) neonColor = Color(colorValue);

    history = (prefs.getStringList('history') ?? []).map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    bookmarks = (prefs.getStringList('bookmarks') ?? []).map((e) => BookmarkItem.fromJson(jsonDecode(e))).toList();
    readingList = (prefs.getStringList('readingList') ?? []).map((e) => ReadingListItem.fromJson(jsonDecode(e))).toList();
    userScripts = (prefs.getStringList('userScripts') ?? []).map((e) => UserScript.fromJson(jsonDecode(e))).toList();

    final sd = prefs.getStringList('speedDials');
    if (sd != null && sd.isNotEmpty) {
      speedDials = sd.map((e) => SpeedDialItem.fromJson(jsonDecode(e))).toList();
    } else {
      speedDials = [
        SpeedDialItem(url: "https://google.com", label: "Google", colorValue: Colors.blue.value),
        SpeedDialItem(url: "https://youtube.com", label: "YouTube", colorValue: Colors.red.value),
        SpeedDialItem(url: "https://github.com", label: "GitHub", colorValue: Colors.purple.value),
        SpeedDialItem(url: "https://twitter.com", label: "Twitter", colorValue: Colors.lightBlue.value),
      ];
    }
    isLocked = isBiometricEnabled;
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('searchEngine', searchEngine);
    prefs.setBool('adBlock', isAdBlockEnabled);
    prefs.setBool('forceDark', isForceDarkWeb);
    prefs.setBool('jsEnabled', isJsEnabled);
    prefs.setBool('imagesEnabled', isImagesEnabled);
    prefs.setBool('biometric', isBiometricEnabled);
    prefs.setBool('dohEnabled', isDohEnabled);
    prefs.setString('dohProvider', dohProvider);
    prefs.setBool('trackingProtection', isTrackingProtection);
    prefs.setBool('popupBlocked', isPopupBlocked);
    prefs.setInt('blockedAds', blockedAdsCount);
    prefs.setInt('blockedTrackers', blockedTrackersCount);
    prefs.setString('customUserAgent', customUserAgent);
    prefs.setString('userAgentPreset', currentUserAgentPreset);
    prefs.setInt('neonColor', neonColor.value);
    prefs.setStringList('history', history.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('bookmarks', bookmarks.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('readingList', readingList.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('userScripts', userScripts.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('speedDials', speedDials.map((e) => jsonEncode(e.toJson())).toList());
  }

  void _addNewTab([String url = "luxor://home", bool incognito = false]) {
    final newTab = BrowserTab(id: const Uuid().v4(), url: url, isIncognito: incognito);
    tabs.add(newTab);
    currentTabIndex = tabs.length - 1;
    showTabGrid = false;
    _updateState();
    notifyListeners();
  }

  void addNewTab([String url = "luxor://home", bool incognito = false]) => _addNewTab(url, incognito);

  void closeTab(int index) {
    if (tabs.length > 1) {
      tabs.removeAt(index);
      if (currentTabIndex >= tabs.length) currentTabIndex = tabs.length - 1;
      if (isSplitMode) {
        splitTabIndices.removeWhere((i) => i == index);
        splitTabIndices = splitTabIndices.map((i) => i > index ? i - 1 : i).toList();
        if (splitTabIndices.length < 2) { isSplitMode = false; splitTabIndices.clear(); }
      }
      _updateState();
      notifyListeners();
    } else {
      loadUrl("luxor://home");
    }
  }

  void switchTab(int index) {
    currentTabIndex = index;
    showTabGrid = false;
    _updateState();
    notifyListeners();
  }

  void toggleTabGrid() async {
    if (!showTabGrid) {
      try { currentTab.thumbnail = await currentTab.controller?.takeScreenshot(); } catch (e) {}
    }
    showTabGrid = !showTabGrid;
    notifyListeners();
  }

  void _updateState() {
    urlController.text = currentTab.url == "luxor://home" ? "" : currentTab.url;
    isSecure = currentTab.url.startsWith("https://");
    progress = 0;
    showFindBar = false;
    sslCertificate = null;
    isMediaPlaying = false;
  }

  void setController(InAppWebViewController c, [int? tabIndex]) {
    if (tabIndex != null && tabIndex < tabs.length) {
      tabs[tabIndex].controller = c;
    } else {
      currentTab.controller = c;
    }
  }

  void updateUrl(String url, [int? tabIndex]) {
    final tab = tabIndex != null && tabIndex < tabs.length ? tabs[tabIndex] : currentTab;
    tab.url = url;
    if (tabIndex == null || tabIndex == currentTabIndex) {
      urlController.text = url == "luxor://home" ? "" : url;
      isSecure = url.startsWith("https://");
      isMediaPlaying = (url.contains("youtube") || url.contains("video") || url.contains("spotify"));
    }
    notifyListeners();
  }

  void loadUrl(String url, [int? tabIndex]) {
    final tab = tabIndex != null && tabIndex < tabs.length ? tabs[tabIndex] : currentTab;

    if (url.trim().isEmpty) {
      tab.url = "luxor://home";
      if (tabIndex == null || tabIndex == currentTabIndex) urlController.text = "";
      notifyListeners();
      return;
    }

    url = url.trim();

    if (url == "home" || url == "luxor://home" || url == "about:home") {
      tab.url = "luxor://home";
      if (tabIndex == null || tabIndex == currentTabIndex) urlController.text = "";
      notifyListeners();
      return;
    }

    if (url.startsWith("luxor://")) {
      tab.url = url;
      notifyListeners();
      return;
    }

    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      if (url.contains(" ") || !url.contains(".")) {
        String encodedQuery = Uri.encodeComponent(url);
        url = "$searchEngine$encodedQuery";
      } else {
        url = "https://$url";
      }
    }

    tab.url = url;
    if (tabIndex == null || tabIndex == currentTabIndex) {
      urlController.text = url;
      isSecure = url.startsWith("https://");
    }

    if (tab.controller != null) {
      try {
        tab.controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      } catch (e) {
        String encodedQuery = Uri.encodeComponent(url);
        final searchUrl = "$searchEngine$encodedQuery";
        tab.url = searchUrl;
        tab.controller!.loadUrl(urlRequest: URLRequest(url: WebUri(searchUrl)));
      }
    }

    notifyListeners();
  }

  void goHome() => loadUrl("luxor://home");
  void toggleMenu() { isMenuOpen = !isMenuOpen; notifyListeners(); }
  void toggleZenMode() { isZenMode = !isZenMode; notifyListeners(); }
  void toggleAiSidebar() { showAiSidebar = !showAiSidebar; notifyListeners(); }

  void toggleGameMode() {
    isGameMode = !isGameMode;
    if (isGameMode) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      WakelockPlus.enable();
      isZenMode = true;
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      WakelockPlus.disable();
      isZenMode = false;
    }
    notifyListeners();
  }

  void swipeTab(bool isLeft) {
    if (isLeft) { if (currentTabIndex > 0) switchTab(currentTabIndex - 1); }
    else { if (currentTabIndex < tabs.length - 1) switchTab(currentTabIndex + 1); }
  }

  // Split View
  void toggleSplitMode(int maxSplits) {
    if (isSplitMode) {
      isSplitMode = false;
      splitTabIndices.clear();
    } else {
      if (tabs.length >= 2) {
        isSplitMode = true;
        splitTabIndices = [currentTabIndex];
        int nextTab = (currentTabIndex + 1) % tabs.length;
        if (!splitTabIndices.contains(nextTab)) splitTabIndices.add(nextTab);
        activeSplitIndex = 0;
      }
    }
    notifyListeners();
  }

  void addTabToSplit(int tabIndex, int maxSplits) {
    if (!isSplitMode) return;
    if (splitTabIndices.length < maxSplits && !splitTabIndices.contains(tabIndex)) {
      splitTabIndices.add(tabIndex);
      notifyListeners();
    }
  }

  void removeTabFromSplit(int tabIndex) {
    if (!isSplitMode) return;
    splitTabIndices.remove(tabIndex);
    if (splitTabIndices.length < 2) { isSplitMode = false; splitTabIndices.clear(); }
    notifyListeners();
  }

  void setActiveSplit(int index) {
    if (index < splitTabIndices.length) {
      activeSplitIndex = index;
      currentTabIndex = splitTabIndices[index];
      _updateState();
      notifyListeners();
    }
  }

  // Biometric
  void onAppPaused() => _lastPausedTime = DateTime.now();

  void onAppResumed(BuildContext context) {
    if (!isBiometricEnabled || _lastPausedTime == null) return;
    if (DateTime.now().difference(_lastPausedTime!).inSeconds >= _lockDelaySeconds) {
      isLocked = true;
      notifyListeners();
      checkBiometricLock(context);
    }
    _lastPausedTime = null;
  }

  Future<void> checkBiometricLock(BuildContext context) async {
    if (!isBiometricEnabled) { isLocked = false; notifyListeners(); return; }
    if (_isAuthenticating) return;

    try {
      final canAuth = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canAuth) { isLocked = false; notifyListeners(); return; }

      _isAuthenticating = true;
      final authenticated = await auth.authenticate(
        localizedReason: 'Unlock Luxor Browser',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (authenticated) isLocked = false;
    } catch (e) {
      isLocked = false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  void toggleBiometric() async {
    if (!isBiometricEnabled) {
      try {
        final canAuth = await auth.canCheckBiometrics || await auth.isDeviceSupported();
        if (!canAuth) return;
        final authenticated = await auth.authenticate(
          localizedReason: 'Enable biometric lock',
          options: const AuthenticationOptions(biometricOnly: false),
        );
        if (authenticated) { isBiometricEnabled = true; isLocked = false; }
      } catch (e) { return; }
    } else {
      isBiometricEnabled = false;
      isLocked = false;
    }
    _saveData();
    notifyListeners();
  }

  // DoH DNS
  void toggleDoh() { isDohEnabled = !isDohEnabled; _saveData(); notifyListeners(); }
  void setDohProvider(String provider) { dohProvider = provider; _saveData(); notifyListeners(); }

  // User Agent
  void setUserAgent(String preset, [String? customUa]) async {
    currentUserAgentPreset = preset;
    if (customUa != null) {
      customUserAgent = customUa;
    } else {
      final presetObj = UserAgentPreset.presets.firstWhere((p) => p.name == preset, orElse: () => UserAgentPreset.presets[0]);
      customUserAgent = presetObj.ua;
    }
    await _saveData();
    await currentTab.controller?.setSettings(settings: getSettings());
    reload();
    notifyListeners();
  }

  // Privacy
  void toggleTrackingProtection() { isTrackingProtection = !isTrackingProtection; _saveData(); reload(); notifyListeners(); }
  void togglePopupBlock() { isPopupBlocked = !isPopupBlocked; _saveData(); notifyListeners(); }

  // Bookmarks
  void addBookmark(String url, String title, [String folder = "Default"]) {
    if (bookmarks.any((b) => b.url == url)) return;
    bookmarks.insert(0, BookmarkItem(url: url, title: title, folder: folder));
    _saveData();
    notifyListeners();
  }

  void updateBookmark(String id, String url, String title, [String? folder]) {
    final idx = bookmarks.indexWhere((b) => b.id == id);
    if (idx != -1) {
      bookmarks[idx].url = url;
      bookmarks[idx].title = title;
      if (folder != null) bookmarks[idx].folder = folder;
      _saveData();
      notifyListeners();
    }
  }

  void deleteBookmark(String id) {
    bookmarks.removeWhere((b) => b.id == id);
    _saveData();
    notifyListeners();
  }

  void toggleBookmark() {
    if (currentTab.url == "luxor://home") return;
    final idx = bookmarks.indexWhere((b) => b.url == currentTab.url);
    if (idx != -1) {
      bookmarks.removeAt(idx);
    } else {
      bookmarks.insert(0, BookmarkItem(url: currentTab.url, title: currentTab.title));
    }
    _saveData();
    notifyListeners();
  }

  bool isBookmarked([String? url]) => bookmarks.any((b) => b.url == (url ?? currentTab.url));

  // Reading List
  void addToReadingList(String url, String title) {
    if (readingList.any((r) => r.url == url)) return;
    readingList.insert(0, ReadingListItem(url: url, title: title));
    _saveData();
    notifyListeners();
  }

  void markAsRead(String id) {
    final idx = readingList.indexWhere((r) => r.id == id);
    if (idx != -1) {
      readingList[idx].isRead = true;
      _saveData();
      notifyListeners();
    }
  }

  void removeFromReadingList(String id) {
    readingList.removeWhere((r) => r.id == id);
    _saveData();
    notifyListeners();
  }

  // Speed Dials
  void addSpeedDial(String label, String url) {
    speedDials.add(SpeedDialItem(url: url, label: label, colorValue: Colors.primaries[speedDials.length % Colors.primaries.length].value));
    _saveData();
    notifyListeners();
  }

  void removeSpeedDial(int index) {
    speedDials.removeAt(index);
    _saveData();
    notifyListeners();
  }

  void editSpeedDial(int index, String label, String url) {
    if (index < speedDials.length) {
      speedDials[index] = SpeedDialItem(url: url, label: label, colorValue: speedDials[index].colorValue);
      _saveData();
      notifyListeners();
    }
  }

  void removeDownload(String id) {
    downloads.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  // History
  void addToHistory(String u, String? t, [int? tabIndex]) {
    final tab = tabIndex != null && tabIndex < tabs.length ? tabs[tabIndex] : currentTab;
    if (!tab.isIncognito && u != "luxor://home" && u != "about:blank" && u.isNotEmpty) {
      if (history.isEmpty || history.first.url != u) {
        history.insert(0, HistoryItem(url: u, title: t ?? "Unknown"));
        if (history.length > 1000) history.removeLast();
        _saveData();
      }
    }
  }

  void clearHistory() {
    history.clear();
    _saveData();
    notifyListeners();
  }

  void deleteHistoryItem(int index) {
    if (index < history.length) {
      history.removeAt(index);
      _saveData();
      notifyListeners();
    }
  }

  // Other browser functions
  void incrementAdsBlocked() { blockedAdsCount++; if (blockedAdsCount % 5 == 0) _saveData(); notifyListeners(); }
  void incrementTrackersBlocked() { blockedTrackersCount++; if (blockedTrackersCount % 5 == 0) _saveData(); notifyListeners(); }
  void findInPage(String t) { if (t.isEmpty) currentTab.controller?.clearMatches(); else currentTab.controller?.findAllAsync(find: t); }
  void findNext() => currentTab.controller?.findNext(forward: true);
  void findPrev() => currentTab.controller?.findNext(forward: false);
  void toggleFindBar() { showFindBar = !showFindBar; if (!showFindBar) currentTab.controller?.clearMatches(); notifyListeners(); }

  void toggleReaderMode() {
    String js = """
    (function(){
      var article = document.querySelector('article') || document.querySelector('main') || document.body;
      var content = '';
      var title = document.title;
      article.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote').forEach(function(el) {
        content += '<' + el.tagName.toLowerCase() + '>' + el.innerHTML + '</' + el.tagName.toLowerCase() + '>';
      });
      document.body.innerHTML = '<div style="max-width:700px;margin:40px auto;padding:20px;font-family:Georgia,serif;line-height:1.8;color:#e0e0e0;background:#121212;"><h1 style="color:#FFD700;">' + title + '</h1>' + content + '</div>';
      document.body.style.backgroundColor='#121212';
    })();
    """;
    currentTab.controller?.evaluateJavascript(source: js);
    toggleMenu();
  }

  void translatePage([String targetLang = "en"]) {
    final url = "https://translate.google.com/translate?sl=auto&tl=$targetLang&u=${Uri.encodeComponent(currentTab.url)}";
    loadUrl(url);
  }

  void toggleDesktopMode() async { isDesktopMode = !isDesktopMode; await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void toggleAdBlock() async { isAdBlockEnabled = !isAdBlockEnabled; await _saveData(); reload(); notifyListeners(); }
  void toggleForceDark() async { isForceDarkWeb = !isForceDarkWeb; await _saveData(); reload(); notifyListeners(); }
  void toggleJs() async { isJsEnabled = !isJsEnabled; await _saveData(); await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void toggleDataSaver() async { isImagesEnabled = !isImagesEnabled; await _saveData(); await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void setSearchEngine(String url) { searchEngine = url; _saveData(); notifyListeners(); }

  void clearBrowsingData({bool clearHistory = true, bool clearCache = true, bool clearCookies = true}) async {
    if (clearCache) await currentTab.controller?.clearCache();
    if (clearCookies) await CookieManager.instance().deleteAllCookies();
    if (clearHistory) { history.clear(); }
    await _saveData();
    notifyListeners();
  }

  void changeTheme(Color color) { neonColor = color; _saveData(); notifyListeners(); }

  void addUserScript(String n, String c) { userScripts.add(UserScript(id: const Uuid().v4(), name: n, code: c)); _saveData(); notifyListeners(); }
  void toggleUserScript(String id) { final s = userScripts.firstWhere((e) => e.id == id); s.active = !s.active; _saveData(); reload(); notifyListeners(); }
  void deleteUserScript(String id) { userScripts.removeWhere((e) => e.id == id); _saveData(); notifyListeners(); }

  void toggleTts() async {
    if (isSpeaking) { await _flutterTts.stop(); isSpeaking = false; }
    else {
      final text = await currentTab.controller?.evaluateJavascript(source: "document.body.innerText");
      if (text != null && text.toString().isNotEmpty) { isSpeaking = true; await _flutterTts.speak(text.toString()); }
    }
    notifyListeners();
  }

  void injectScripts(InAppWebViewController c) {
    if (isAdBlockEnabled) {
      c.evaluateJavascript(source: """
        (function(){
          var blocked = 0;
          var selectors = ['.ad', '.ads', '.advertisement', '[class*="ad-"]', '[id*="ad-"]', 'iframe[src*="ads"]', '[id^="google_ads"]', '.sponsored', '.adsbygoogle'];
          selectors.forEach(function(s) {
            var els = document.querySelectorAll(s);
            if (els.length > 0) { blocked += els.length; els.forEach(function(x) { x.style.display = 'none'; }); }
          });
          if (blocked > 0) console.log('BLOCKED_ADS:' + blocked);
        })();
      """);
    }
    if (isForceDarkWeb) {
      c.evaluateJavascript(source: """
        (function(){
          var s = document.createElement('style');
          s.innerHTML = 'html{filter:invert(1) hue-rotate(180deg)!important;background:#121212!important;}img,video,iframe,canvas,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important;}';
          document.head.appendChild(s);
        })();
      """);
    }
    for (var s in userScripts) {
      if (s.active) c.evaluateJavascript(source: "(function(){ try { ${s.code} } catch(e) { console.log('UserScript Error: ' + e); } })();");
    }
  }

  Future<void> savePageOffline(BuildContext ctx) async {
    try {
      final temp = await getTemporaryDirectory();
      final path = "${temp.path}/offline_${DateTime.now().millisecondsSinceEpoch}.mht";
      await currentTab.controller?.saveWebArchive(filePath: path, autoname: false);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("Saved: $path"), backgroundColor: neonColor));
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Failed to save"), backgroundColor: Colors.red));
    }
  }

  Future<void> shareScreenshot(BuildContext ctx) async {
    try {
      final i = await currentTab.controller?.takeScreenshot();
      if (i == null) return;
      final t = await getTemporaryDirectory();
      final f = File('${t.path}/luxor_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(i);
      await Share.shareXFiles([XFile(f.path)], text: currentTab.title);
    } catch (e) {}
  }

  void sharePage() => Share.share("${currentTab.title}\n${currentTab.url}");
  void setCustomUA(String ua) async { customUserAgent = ua; await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void updateSSL(SslCertificate? s) { sslCertificate = s; notifyListeners(); }
  void goBack() => currentTab.controller?.goBack();
  void goForward() => currentTab.controller?.goForward();
  void reload() => currentTab.controller?.reload();
  void stopLoading() => currentTab.controller?.stopLoading();
  void printPage() async { await currentTab.controller?.printCurrentPage(); }

  Future<void> exportData(BuildContext ctx) async {
    final d = {
      'history': history.map((e) => e.toJson()).toList(),
      'bookmarks': bookmarks.map((e) => e.toJson()).toList(),
      'readingList': readingList.map((e) => e.toJson()).toList(),
      'speedDials': speedDials.map((e) => e.toJson()).toList(),
    };
    await Share.share(jsonEncode(d));
  }

  Future<void> importData(BuildContext ctx, String s) async {
    try {
      final d = jsonDecode(s);
      if (d['history'] != null) history = (d['history'] as List).map((e) => HistoryItem.fromJson(e)).toList();
      if (d['bookmarks'] != null) bookmarks = (d['bookmarks'] as List).map((e) => BookmarkItem.fromJson(e)).toList();
      if (d['readingList'] != null) readingList = (d['readingList'] as List).map((e) => ReadingListItem.fromJson(e)).toList();
      if (d['speedDials'] != null) speedDials = (d['speedDials'] as List).map((e) => SpeedDialItem.fromJson(e)).toList();
      await _saveData();
      notifyListeners();
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Data restored!")));
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Import failed"), backgroundColor: Colors.red));
    }
  }

  void factoryReset() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
    _loadData();
    notifyListeners();
  }
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [ChatMessage(text: "Luxor AI Ready. How can I help?", isUser: false)];
  bool isThinking = false;

  void sendMessage(String text, BrowserProvider b) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true; notifyListeners();
    await Future.delayed(const Duration(milliseconds: 500));

    String resp = "I can help you with browser controls.";
    final lower = text.toLowerCase();

    if (lower.contains("game")) { b.toggleGameMode(); resp = "Game Mode toggled!"; }
    else if (lower.contains("home")) { b.goHome(); resp = "Going home!"; }
    else if (lower.contains("split")) { b.toggleSplitMode(2); resp = "Split mode toggled!"; }
    else if (lower.contains("dark")) { b.toggleForceDark(); resp = "Dark mode toggled!"; }
    else if (lower.contains("desktop")) { b.toggleDesktopMode(); resp = "Desktop mode toggled!"; }
    else if (lower.contains("translate")) { b.translatePage(); resp = "Translating page..."; }
    else if (lower.contains("bookmark")) { b.toggleBookmark(); resp = b.isBookmarked() ? "Bookmarked!" : "Removed from bookmarks."; }
    else if (lower.contains("read")) { b.toggleReaderMode(); resp = "Reader mode activated!"; }
    else if (lower.contains("search") || lower.contains("go to")) {
      final query = text.replaceAll(RegExp(r'(search|go to|open|visit)', caseSensitive: false), '').trim();
      if (query.isNotEmpty) { b.loadUrl(query); resp = "Navigating to: $query"; }
    }

    messages.add(ChatMessage(text: resp, isUser: false));
    isThinking = false; notifyListeners();
  }

  void clearChat() { messages = [ChatMessage(text: "Chat cleared. How can I help?", isUser: false)]; notifyListeners(); }
}

class ChatMessage { final String text; final bool isUser; ChatMessage({required this.text, required this.isUser}); }

// --- UI COMPONENTS ---

class BrowserHomePage extends StatefulWidget { const BrowserHomePage({super.key}); @override State<BrowserHomePage> createState() => _BrowserHomePageState(); }

class _BrowserHomePageState extends State<BrowserHomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _menuController;
  late Animation<double> _menuScale;
  late PullToRefreshController _pullToRefreshController;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _menuController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _menuScale = CurvedAnimation(parent: _menuController, curve: Curves.easeOutBack);
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xFFFFD700), backgroundColor: Colors.black),
      onRefresh: () async {
        final b = Provider.of<BrowserProvider>(context, listen: false);
        if (b.currentTab.url != "luxor://home") b.reload();
        _pullToRefreshController.endRefreshing();
      }
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final browser = Provider.of<BrowserProvider>(context, listen: false);
      if (browser.isBiometricEnabled && browser.isLocked) browser.checkBiometricLock(context);
    });
  }

  @override void dispose() { WidgetsBinding.instance.removeObserver(this); _menuController.dispose(); super.dispose(); }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    final browser = Provider.of<BrowserProvider>(context, listen: false);
    if (state == AppLifecycleState.paused) browser.onAppPaused();
    else if (state == AppLifecycleState.resumed) browser.onAppResumed(context);
  }

  int _getMaxSplits(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);
    final devTools = Provider.of<DevToolsProvider>(context);
    final maxSplits = _getMaxSplits(context);

    if (browser.isBiometricEnabled && browser.isLocked) return LockScreen(onUnlock: () => browser.checkBiometricLock(context));
    if (browser.isMenuOpen) _menuController.forward(); else _menuController.reverse();
    if (browser.showTabGrid) return TabGridPage(browser: browser, maxSplits: maxSplits);

    if (browser.isSplitMode && browser.splitTabIndices.length >= 2) {
      return _buildSplitView(context, browser, devTools, maxSplits);
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: browser.showAiSidebar ? MediaQuery.of(context).size.width * 0.7 : MediaQuery.of(context).size.width,
          child: Column(children: [
            Expanded(child: _buildWebView(browser, devTools, browser.currentTabIndex)),
            if (!browser.isZenMode) const SizedBox(height: 80),
          ])
        ),
        if (browser.progress < 1.0 && browser.currentTab.url != "luxor://home")
          Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(value: browser.progress, minHeight: 2, color: browser.neonColor, backgroundColor: Colors.transparent)),
        AnimatedPositioned(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut, right: browser.showAiSidebar ? 0 : -300, top: 0, bottom: 0, width: MediaQuery.of(context).size.width * 0.75, child: const GlassBox(borderRadius: 0, padding: EdgeInsets.only(top: 40), child: AiSidebar())),
        Positioned(bottom: 90, left: 20, right: 20, child: ScaleTransition(scale: _menuScale, alignment: Alignment.bottomCenter, child: GlassBox(child: _buildGridMenu(context, browser, maxSplits)))),
        if (browser.showFindBar) Positioned(bottom: browser.isZenMode ? 20 : 140, left: 20, right: 20, child: GlassBox(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [Expanded(child: TextField(controller: browser.findController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Find in page...", border: InputBorder.none, hintStyle: TextStyle(color: Colors.white38)), onChanged: (v) => browser.findInPage(v))), IconButton(icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white), onPressed: browser.findPrev), IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white), onPressed: browser.findNext), IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: browser.toggleFindBar)]))),
        if (!browser.showAiSidebar && !browser.isZenMode) _buildBottomBar(context, browser, maxSplits),
        if (browser.isZenMode) Positioned(bottom: 20, right: 20, child: FloatingActionButton.small(backgroundColor: Colors.white10, child: Icon(browser.isGameMode ? Icons.videogame_asset_off : Icons.expand_less, color: Colors.white), onPressed: () => browser.isGameMode ? browser.toggleGameMode() : browser.toggleZenMode()))
      ])
    );
  }

  Widget _buildSplitView(BuildContext context, BrowserProvider browser, DevToolsProvider devTools, int maxSplits) {
    final splitCount = browser.splitTabIndices.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(children: [
        // Split URL Bar
        Container(
          color: const Color(0xFF1A1A1A),
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 8, right: 8, bottom: 8),
          child: Column(children: [
            // Tab headers
            Row(children: [
              ...browser.splitTabIndices.asMap().entries.map((entry) {
                final idx = entry.key;
                final tabIdx = entry.value;
                final tab = browser.tabs[tabIdx];
                final isActive = idx == browser.activeSplitIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => browser.setActiveSplit(idx),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? browser.neonColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: isActive ? Border.all(color: browser.neonColor, width: 1) : null,
                      ),
                      child: Row(children: [
                        Expanded(child: Text(tab.title, style: TextStyle(color: isActive ? browser.neonColor : Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
                        GestureDetector(onTap: () => browser.removeTabFromSplit(tabIdx), child: const Icon(Icons.close, size: 14, color: Colors.white54)),
                      ]),
                    ),
                  ),
                );
              }),
              if (splitCount < maxSplits && browser.tabs.length > splitCount)
                IconButton(icon: const Icon(Icons.add, color: Colors.white54, size: 20), onPressed: () => _showAddSplitDialog(context, browser, maxSplits)),
              IconButton(icon: const Icon(Icons.fullscreen_exit, color: Colors.red, size: 20), onPressed: () => browser.toggleSplitMode(maxSplits)),
            ]),
            const SizedBox(height: 8),
            // Active tab URL bar
            GestureDetector(
              onTap: () => _showSplitSearch(context, browser),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(25)),
                child: Row(children: [
                  Icon(browser.currentTab.url.startsWith("https://") ? Iconsax.lock : Iconsax.unlock, size: 14, color: browser.currentTab.url.startsWith("https://") ? Colors.green : Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(browser.currentTab.url == "luxor://home" ? "Search or enter URL..." : browser.currentTab.url.replaceFirst("https://", "").replaceFirst("www.", ""), style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)),
                  GestureDetector(onTap: browser.reload, child: const Icon(Iconsax.refresh, size: 18, color: Colors.white54)),
                ]),
              ),
            ),
          ]),
        ),
        // Split WebViews
        Expanded(
          child: Row(
            children: browser.splitTabIndices.asMap().entries.map((entry) {
              final idx = entry.key;
              final tabIdx = entry.value;
              return Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: idx < splitCount - 1 ? BorderSide(color: browser.neonColor.withOpacity(0.3), width: 1) : BorderSide.none,
                      top: idx == browser.activeSplitIndex ? BorderSide(color: browser.neonColor, width: 2) : BorderSide.none,
                    ),
                  ),
                  child: GestureDetector(
                    onTap: () => browser.setActiveSplit(idx),
                    child: _buildWebView(browser, devTools, tabIdx, isSplit: true),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Bottom Bar
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF1A1A1A),
          child: SafeArea(
            top: false,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _navBtn(Iconsax.arrow_left_2, browser.goBack),
              _navBtn(Iconsax.arrow_right_3, browser.goForward),
              _navBtn(Iconsax.home, browser.goHome, color: browser.neonColor),
              _navBtn(Iconsax.bookmark, browser.toggleBookmark, color: browser.isBookmarked() ? browser.neonColor : Colors.white),
              _navBtn(Iconsax.maximize_4, () => browser.toggleSplitMode(maxSplits), color: browser.neonColor),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(50), child: Container(width: 44, height: 44, alignment: Alignment.center, child: Icon(icon, color: color, size: 22)));

  Widget _buildWebView(BrowserProvider browser, DevToolsProvider devTools, int tabIndex, {bool isSplit = false}) {
    final tab = browser.tabs[tabIndex];
    if (tab.url == "luxor://home") return StartPage(browser: browser, tabIndex: isSplit ? tabIndex : null);

    return InAppWebView(
      key: ValueKey('${tab.id}_$tabIndex'),
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
      initialSettings: browser.getSettings(tabIndex),
      pullToRefreshController: isSplit ? null : _pullToRefreshController,
      onWebViewCreated: (c) => browser.setController(c, tabIndex),
      onLoadStart: (c, url) { browser.tabs[tabIndex].loadStartTime = DateTime.now(); browser.updateUrl(url.toString(), tabIndex); },
      onLoadStop: (c, url) async {
        if (tabIndex == browser.currentTabIndex) browser.progress = 1.0;
        browser.updateUrl(url.toString(), tabIndex);
        browser.tabs[tabIndex].title = await c.getTitle() ?? "Unknown";
        browser.injectScripts(c);
        browser.addToHistory(url.toString(), browser.tabs[tabIndex].title, tabIndex);
        if (tabIndex == browser.currentTabIndex) browser.updateSSL(await c.getCertificate());
        browser.notifyListeners();
      },
      onProgressChanged: (c, p) {
        browser.tabs[tabIndex].progress = p;
        if (tabIndex == browser.currentTabIndex) browser.progress = p / 100;
        browser.notifyListeners();
      },
      onConsoleMessage: (c, m) {
        if (m.message.startsWith("BLOCKED_ADS:")) browser.incrementAdsBlocked();
        devTools.addLog(m.message, m.messageLevel);
      },
      onTitleChanged: (c, title) { browser.tabs[tabIndex].title = title ?? "Unknown"; browser.notifyListeners(); },
      onDownloadStartRequest: (c, req) async {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download: ${req.suggestedFilename ?? 'file'}"), action: SnackBarAction(label: "Open", onPressed: () => launchUrl(req.url, mode: LaunchMode.externalApplication))));
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, BrowserProvider browser, int maxSplits) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: 20, left: 16, right: 16,
      child: GestureDetector(
        onHorizontalDragEnd: (d) { if (d.primaryVelocity! > 0) browser.swipeTab(true); else if (d.primaryVelocity! < 0) browser.swipeTab(false); },
        child: GlassBox(
          borderRadius: 30,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(children: [
            _circleBtn(browser.isMenuOpen ? Icons.close : Iconsax.category, () => browser.toggleMenu()),
            _circleBtn(Iconsax.home, browser.goHome, color: browser.neonColor),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => _showSearch(context, browser),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    Icon(browser.isSecure ? Iconsax.lock : Iconsax.unlock, size: 12, color: browser.isSecure ? Colors.green : Colors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(browser.currentTab.url == "luxor://home" ? "Search or enter URL..." : browser.currentTab.url.replaceFirst("https://", "").replaceFirst("www.", ""), style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis)),
                    GestureDetector(onTap: browser.toggleBookmark, child: Icon(browser.isBookmarked() ? Iconsax.bookmark_25 : Iconsax.bookmark, size: 16, color: browser.isBookmarked() ? browser.neonColor : Colors.white38)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: browser.toggleTabGrid,
                      child: Container(
                        width: 24, height: 24, alignment: Alignment.center,
                        decoration: BoxDecoration(border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(6)),
                        child: Text("${browser.tabs.length}", style: const TextStyle(fontSize: 11, color: Colors.white))
                      )
                    )
                  ])
                )
              )
            ),
            const SizedBox(width: 4),
            _circleBtn(browser.isSplitMode ? Iconsax.maximize_4 : Iconsax.document_copy, () => browser.toggleSplitMode(maxSplits), color: browser.isSplitMode ? browser.neonColor : Colors.white),
            _circleBtn(Iconsax.magic_star, browser.toggleAiSidebar, color: browser.neonColor),
          ])
        )
      )
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(50), child: Container(width: 38, height: 38, alignment: Alignment.center, child: Icon(icon, color: color, size: 20)));

  Widget _buildGridMenu(BuildContext context, BrowserProvider b, int maxSplits) => GridView.count(
    shrinkWrap: true, crossAxisCount: 5, mainAxisSpacing: 10, crossAxisSpacing: 5, padding: const EdgeInsets.all(12),
    children: [
      _menuItem(Iconsax.arrow_left_2, "Back", b.goBack),
      _menuItem(Iconsax.arrow_right_3, "Forward", b.goForward),
      _menuItem(Iconsax.refresh, "Reload", b.reload),
      _menuItem(Iconsax.home_2, "Home", () { b.goHome(); b.toggleMenu(); }),
      _menuItem(Iconsax.document_copy, "Split", () { b.toggleSplitMode(maxSplits); b.toggleMenu(); }, isActive: b.isSplitMode),
      _menuItem(Iconsax.bookmark, "Bookmarks", () { b.toggleMenu(); _showBookmarks(context, b); }),
      _menuItem(Iconsax.clock, "History", () { b.toggleMenu(); _showHistory(context, b); }),
      _menuItem(Iconsax.document_download, "Downloads", () { b.toggleMenu(); _showDownloads(context, b); }),
      _menuItem(Iconsax.translate, "Translate", () { b.translatePage(); b.toggleMenu(); }),
      _menuItem(Iconsax.book_1, "Read Mode", () { b.toggleReaderMode(); }),
      _menuItem(Iconsax.search_normal, "Find", () { b.toggleFindBar(); b.toggleMenu(); }),
      _menuItem(Iconsax.share, "Share", () { b.sharePage(); b.toggleMenu(); }),
      _menuItem(Iconsax.printer, "Print", () { b.printPage(); b.toggleMenu(); }),
      _menuItem(Iconsax.game, "Game Mode", () { b.toggleGameMode(); b.toggleMenu(); }),
      _menuItem(Iconsax.info_circle, "Page Info", () { b.toggleMenu(); _showPageInfo(context, b); }),
      _menuItem(Iconsax.setting_2, "Settings", () { b.toggleMenu(); _showSettings(context, b); }),
    ]
  );

  Widget _menuItem(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) {
    final b = Provider.of<BrowserProvider>(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isActive ? b.neonColor : Colors.white10, shape: BoxShape.circle), child: Icon(icon, size: 18, color: isActive ? Colors.black : Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white70), textAlign: TextAlign.center)
      ])
    );
  }

  void _showSearch(BuildContext context, BrowserProvider b) => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => SearchSheet(browser: b));
  void _showSplitSearch(BuildContext context, BrowserProvider b) => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => SearchSheet(browser: b, tabIndex: b.currentTabIndex));
  void _showAddSplitDialog(BuildContext context, BrowserProvider browser, int maxSplits) {
    final availableTabs = browser.tabs.asMap().entries.where((e) => !browser.splitTabIndices.contains(e.key)).toList();
    if (availableTabs.isEmpty) return;
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF101010),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Add Tab to Split", style: TextStyle(color: browser.neonColor, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...availableTabs.map((entry) => ListTile(
            leading: const Icon(Iconsax.document, color: Colors.white54),
            title: Text(entry.value.title, style: const TextStyle(color: Colors.white)),
            subtitle: Text(entry.value.url, style: const TextStyle(color: Colors.grey, fontSize: 11), overflow: TextOverflow.ellipsis),
            onTap: () { browser.addTabToSplit(entry.key, maxSplits); Navigator.pop(context); },
          )),
        ]),
      ),
    );
  }

  void _showBookmarks(BuildContext context, BrowserProvider b) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF101010), isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("Bookmarks (${b.bookmarks.length})", style: TextStyle(color: b.neonColor, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: () => _showAddBookmark(context, b)),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: b.bookmarks.isEmpty
                ? const Center(child: Text("No bookmarks yet", style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    controller: controller,
                    itemCount: b.bookmarks.length,
                    itemBuilder: (_, i) {
                      final bookmark = b.bookmarks[i];
                      return ListTile(
                        leading: Container(
                          width: 40, height: 40, alignment: Alignment.center,
                          decoration: BoxDecoration(color: b.neonColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(bookmark.title.isNotEmpty ? bookmark.title[0].toUpperCase() : "?", style: TextStyle(color: b.neonColor, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(bookmark.title, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(bookmark.url, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white54),
                          color: const Color(0xFF2A2A2A),
                          onSelected: (v) {
                            if (v == "edit") _showEditBookmark(context, b, bookmark);
                            else if (v == "delete") b.deleteBookmark(bookmark.id);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: "edit", child: Text("Edit", style: TextStyle(color: Colors.white))),
                            const PopupMenuItem(value: "delete", child: Text("Delete", style: TextStyle(color: Colors.red))),
                          ],
                        ),
                        onTap: () { b.loadUrl(bookmark.url); Navigator.pop(context); },
                      );
                    }
                  ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showAddBookmark(BuildContext context, BrowserProvider b) {
    final urlCtrl = TextEditingController(text: b.currentTab.url == "luxor://home" ? "" : b.currentTab.url);
    final titleCtrl = TextEditingController(text: b.currentTab.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text("Add Bookmark", style: TextStyle(color: b.neonColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Title", labelStyle: TextStyle(color: Colors.white54))),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "URL", labelStyle: TextStyle(color: Colors.white54))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () { if (urlCtrl.text.isNotEmpty) { b.addBookmark(urlCtrl.text, titleCtrl.text); Navigator.pop(context); } }, child: const Text("Save")),
        ],
      ),
    );
  }

  void _showEditBookmark(BuildContext context, BrowserProvider b, BookmarkItem bookmark) {
    final urlCtrl = TextEditingController(text: bookmark.url);
    final titleCtrl = TextEditingController(text: bookmark.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text("Edit Bookmark", style: TextStyle(color: b.neonColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Title", labelStyle: TextStyle(color: Colors.white54))),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "URL", labelStyle: TextStyle(color: Colors.white54))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () { b.updateBookmark(bookmark.id, urlCtrl.text, titleCtrl.text); Navigator.pop(context); }, child: const Text("Save")),
        ],
      ),
    );
  }

  void _showHistory(BuildContext context, BrowserProvider b) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF101010), isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("History (${b.history.length})", style: TextStyle(color: b.neonColor, fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton(onPressed: () { b.clearHistory(); Navigator.pop(context); }, child: const Text("Clear All", style: TextStyle(color: Colors.red))),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: b.history.isEmpty
                ? const Center(child: Text("No history", style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    controller: controller,
                    itemCount: b.history.length,
                    itemBuilder: (_, i) => Dismissible(
                      key: Key(b.history[i].url + i.toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                      onDismissed: (_) => b.deleteHistoryItem(i),
                      child: ListTile(
                        leading: const Icon(Iconsax.clock, color: Colors.white38),
                        title: Text(b.history[i].title, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(b.history[i].url, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () { b.loadUrl(b.history[i].url); Navigator.pop(context); },
                      ),
                    ),
                  ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showDownloads(BuildContext context, BrowserProvider b) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF101010), isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("Downloads (${b.downloads.length})", style: TextStyle(color: b.neonColor, fontSize: 18, fontWeight: FontWeight.bold)),
              if (b.downloads.isNotEmpty) TextButton(onPressed: () { b.downloads.clear(); Navigator.pop(context); }, child: const Text("Clear All", style: TextStyle(color: Colors.red))),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: b.downloads.isEmpty
                ? const Center(child: Text("No downloads yet", style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    controller: controller,
                    itemCount: b.downloads.length,
                    itemBuilder: (_, i) {
                      final dl = b.downloads[i];
                      return Card(
                        color: const Color(0xFF1A1A1A),
                        child: ListTile(
                          leading: Icon(
                            dl.status == "completed" ? Iconsax.tick_circle : dl.status == "failed" ? Iconsax.close_circle : Iconsax.document_download,
                            color: dl.status == "completed" ? Colors.green : dl.status == "failed" ? Colors.red : b.neonColor,
                          ),
                          title: Text(dl.filename, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dl.status == "completed" ? "Completed" : dl.status == "failed" ? "Failed" : "Downloading...",
                                style: TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                              if (dl.status == "downloading") LinearProgressIndicator(value: dl.progress / 100, color: b.neonColor, backgroundColor: Colors.grey),
                              if (dl.totalBytes != null) Text(
                                "${(dl.downloadedBytes / 1024 / 1024).toStringAsFixed(2)} MB / ${(dl.totalBytes! / 1024 / 1024).toStringAsFixed(2)} MB",
                                style: const TextStyle(color: Colors.grey, fontSize: 10),
                              ),
                            ],
                          ),
                          trailing: dl.status == "completed"
                            ? IconButton(icon: const Icon(Iconsax.folder_open, color: Colors.white54), onPressed: () {})
                            : IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => b.removeDownload(dl.id)),
                        ),
                      );
                    },
                  ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showPageInfo(BuildContext context, BrowserProvider b) async {
    final tab = b.currentTab;
    if (tab.url == "luxor://home") return;

    String? pageSize;
    String? loadTime;

    if (tab.loadStartTime != null) {
      final duration = DateTime.now().difference(tab.loadStartTime!);
      loadTime = "${duration.inMilliseconds}ms";
    }

    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF101010),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Page Information", style: TextStyle(color: b.neonColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          _infoRow(Iconsax.global, "URL", tab.url, b),
          _infoRow(Iconsax.document_text, "Title", tab.title, b),
          _infoRow(b.isSecure ? Iconsax.lock : Iconsax.unlock, "Security", b.isSecure ? "Secure (HTTPS)" : "Not Secure (HTTP)", b),

          if (b.sslCertificate != null) ...[
            const Divider(color: Colors.white24),
            Text("SSL Certificate", style: TextStyle(color: b.neonColor, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _infoRow(Iconsax.user, "Issued to", b.sslCertificate!.issuedTo?.CName ?? "Unknown", b),
            _infoRow(Iconsax.shield_tick, "Issued by", b.sslCertificate!.issuedBy?.CName ?? "Unknown", b),
          ],

          const Divider(color: Colors.white24),
          if (loadTime != null) _infoRow(Iconsax.timer, "Load Time", loadTime, b),
          _infoRow(Iconsax.code, "User Agent", b.currentUserAgentPreset, b),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showSiteSettings(context, b);
              },
              icon: const Icon(Iconsax.setting_2),
              label: const Text("Site Settings"),
              style: ElevatedButton.styleFrom(
                backgroundColor: b.neonColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, BrowserProvider b) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: b.neonColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSiteSettings(BuildContext context, BrowserProvider b) {
    // TODO: Implement site-specific settings
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text("Site Settings", style: TextStyle(color: b.neonColor)),
        content: const Text("Site-specific settings coming soon!", style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context, BrowserProvider b) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF101010), isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setState) => DraggableScrollableSheet(
        initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(16),
          child: ListView(controller: controller, children: [
            Text("Settings", style: TextStyle(color: b.neonColor, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // Sync & Account Section
            _buildSyncAccountTile(context, b),
            const SizedBox(height: 16),

            _settingsSection("Privacy & Security", b),
            SwitchListTile(activeColor: b.neonColor, title: const Text("DNS over HTTPS (DoH)", style: TextStyle(color: Colors.white)), subtitle: const Text("Secure DNS queries", style: TextStyle(color: Colors.grey, fontSize: 12)), value: b.isDohEnabled, onChanged: (v) { b.toggleDoh(); setState((){}); }),
            if (b.isDohEnabled) ListTile(
              title: const Text("DoH Provider", style: TextStyle(color: Colors.white)),
              subtitle: Text(BrowserProvider.dohProviders.entries.firstWhere((e) => e.value == b.dohProvider, orElse: () => const MapEntry("Custom", "")).key, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () => _showDohPicker(context, b, setState),
            ),
            SwitchListTile(activeColor: b.neonColor, title: const Text("Tracking Protection", style: TextStyle(color: Colors.white)), value: b.isTrackingProtection, onChanged: (v) { b.toggleTrackingProtection(); setState((){}); }),
            SwitchListTile(activeColor: b.neonColor, title: const Text("Block Popups", style: TextStyle(color: Colors.white)), value: b.isPopupBlocked, onChanged: (v) { b.togglePopupBlock(); setState((){}); }),
            SwitchListTile(activeColor: b.neonColor, title: const Text("Biometric Lock", style: TextStyle(color: Colors.white)), subtitle: const Text("Lock when leaving app", style: TextStyle(color: Colors.grey, fontSize: 12)), value: b.isBiometricEnabled, onChanged: (v) { b.toggleBiometric(); setState((){}); }),

            _settingsSection("Content", b),
            SwitchListTile(activeColor: b.neonColor, title: const Text("AdBlocker", style: TextStyle(color: Colors.white)), subtitle: Text("Blocked: ${b.blockedAdsCount}", style: const TextStyle(color: Colors.grey, fontSize: 12)), value: b.isAdBlockEnabled, onChanged: (v) { b.toggleAdBlock(); setState((){}); }),
            SwitchListTile(activeColor: b.neonColor, title: const Text("Force Dark Mode", style: TextStyle(color: Colors.white)), value: b.isForceDarkWeb, onChanged: (v) { b.toggleForceDark(); setState((){}); }),
            SwitchListTile(activeColor: b.neonColor, title: const Text("JavaScript", style: TextStyle(color: Colors.white)), value: b.isJsEnabled, onChanged: (v) { b.toggleJs(); setState((){}); }),
            SwitchListTile(activeColor: b.neonColor, title: const Text("Load Images", style: TextStyle(color: Colors.white)), value: b.isImagesEnabled, onChanged: (v) { b.toggleDataSaver(); setState((){}); }),
            SwitchListTile(activeColor: b.neonColor, title: const Text("Desktop Mode", style: TextStyle(color: Colors.white)), value: b.isDesktopMode, onChanged: (v) { b.toggleDesktopMode(); setState((){}); }),

            _settingsSection("User Agent", b),
            ListTile(
              title: const Text("Current User Agent", style: TextStyle(color: Colors.white)),
              subtitle: Text(b.currentUserAgentPreset, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onTap: () => _showUserAgentPicker(context, b, setState),
            ),

            _settingsSection("Search Engine", b),
            _searchEngineTile(b, "Google", "https://www.google.com/search?q=", setState),
            _searchEngineTile(b, "DuckDuckGo", "https://duckduckgo.com/?q=", setState),
            _searchEngineTile(b, "Bing", "https://www.bing.com/search?q=", setState),
            _searchEngineTile(b, "Brave", "https://search.brave.com/search?q=", setState),

            _settingsSection("Theme", b),
            Wrap(spacing: 12, children: [
              _colorDot(b, const Color(0xFFFFD700), setState),
              _colorDot(b, const Color(0xFF00FFC2), setState),
              _colorDot(b, const Color(0xFFFF0055), setState),
              _colorDot(b, const Color(0xFF00BFFF), setState),
              _colorDot(b, const Color(0xFFAA00FF), setState),
            ]),

            _settingsSection("Data", b),
            ListTile(title: const Text("Export Data", style: TextStyle(color: Colors.white)), leading: const Icon(Iconsax.export_1, color: Colors.white54), onTap: () => b.exportData(context)),
            ListTile(title: const Text("Clear Browsing Data", style: TextStyle(color: Colors.orange)), leading: const Icon(Iconsax.trash, color: Colors.orange), onTap: () => _showClearDataDialog(context, b)),
            ListTile(title: const Text("Factory Reset", style: TextStyle(color: Colors.red)), leading: const Icon(Iconsax.refresh, color: Colors.red), onTap: () => b.factoryReset()),

            const SizedBox(height: 40),
            Center(child: Text("Luxor Browser v2.0", style: TextStyle(color: b.neonColor.withOpacity(0.5)))),
          ]),
        ),
      )),
    );
  }

  void _showDohPicker(BuildContext context, BrowserProvider b, StateSetter setState) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text("Select DoH Provider", style: TextStyle(color: b.neonColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: BrowserProvider.dohProviders.entries.map((e) => RadioListTile<String>(
          title: Text(e.key, style: const TextStyle(color: Colors.white)),
          value: e.value,
          groupValue: b.dohProvider,
          activeColor: b.neonColor,
          onChanged: (v) { b.setDohProvider(v!); setState((){}); Navigator.pop(context); },
        )).toList()),
      ),
    );
  }

  void _showUserAgentPicker(BuildContext context, BrowserProvider b, StateSetter setState) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text("Select User Agent", style: TextStyle(color: b.neonColor)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: UserAgentPreset.presets.map((preset) => RadioListTile<String>(
              title: Row(
                children: [
                  Icon(preset.icon, color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(preset.name, style: const TextStyle(color: Colors.white))),
                ],
              ),
              value: preset.name,
              groupValue: b.currentUserAgentPreset,
              activeColor: b.neonColor,
              onChanged: (v) {
                b.setUserAgent(v!);
                setState((){});
                Navigator.pop(context);
              },
            )).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _showCustomUADialog(context, b, setState),
            child: Text("Custom UA", style: TextStyle(color: b.neonColor)),
          ),
        ],
      ),
    );
  }

  void _showCustomUADialog(BuildContext context, BrowserProvider b, StateSetter setState) {
    final controller = TextEditingController(text: b.customUserAgent);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text("Custom User Agent", style: TextStyle(color: b.neonColor)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: "Enter custom user agent string...",
            hintStyle: TextStyle(color: Colors.grey),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                b.setUserAgent("Custom", controller.text);
                setState((){});
              }
              Navigator.pop(context);
            },
            child: const Text("Apply")
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog(BuildContext context, BrowserProvider b) {
    bool clearHistory = true, clearCache = true, clearCookies = true;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text("Clear Browsing Data", style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          CheckboxListTile(title: const Text("History", style: TextStyle(color: Colors.white)), value: clearHistory, activeColor: b.neonColor, onChanged: (v) => setState(() => clearHistory = v!)),
          CheckboxListTile(title: const Text("Cache", style: TextStyle(color: Colors.white)), value: clearCache, activeColor: b.neonColor, onChanged: (v) => setState(() => clearCache = v!)),
          CheckboxListTile(title: const Text("Cookies", style: TextStyle(color: Colors.white)), value: clearCookies, activeColor: b.neonColor, onChanged: (v) => setState(() => clearCookies = v!)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () { b.clearBrowsingData(clearHistory: clearHistory, clearCache: clearCache, clearCookies: clearCookies); Navigator.pop(context); }, child: const Text("Clear", style: TextStyle(color: Colors.red))),
        ],
      )),
    );
  }

  Widget _buildSyncAccountTile(BuildContext context, BrowserProvider b) {
    final syncService = Provider.of<SyncService>(context, listen: true);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: b.neonColor.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: syncService.isSignedIn
            ? CircleAvatar(
                radius: 20,
                backgroundColor: b.neonColor.withOpacity(0.2),
                backgroundImage: syncService.userPhotoUrl != null
                    ? NetworkImage(syncService.userPhotoUrl!)
                    : null,
                child: syncService.userPhotoUrl == null
                    ? Icon(Icons.person, color: b.neonColor, size: 20)
                    : null,
              )
            : Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: b.neonColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Iconsax.cloud_add, color: b.neonColor, size: 20),
              ),
        title: Text(
          syncService.isSignedIn ? syncService.userName : "Sync & Google Account",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          syncService.isSignedIn
              ? (syncService.isSyncing ? "Syncing..." : "Signed in • ${syncService.userEmail}")
              : "Sign in to sync your data",
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (syncService.isSignedIn && syncService.isSyncing)
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (syncService.isSignedIn)
              Icon(
                syncService.syncEnabled ? Icons.cloud_done : Icons.cloud_off,
                color: syncService.syncEnabled ? Colors.green : Colors.grey,
                size: 18,
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SyncSettingsPage(
                syncService: syncService,
                accentColor: b.neonColor,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _settingsSection(String title, BrowserProvider b) => Padding(padding: const EdgeInsets.only(top: 24, bottom: 8), child: Text(title, style: TextStyle(color: b.neonColor, fontSize: 14, fontWeight: FontWeight.bold)));
  Widget _searchEngineTile(BrowserProvider b, String name, String url, StateSetter setState) => RadioListTile<String>(title: Text(name, style: const TextStyle(color: Colors.white)), value: url, groupValue: b.searchEngine, activeColor: b.neonColor, onChanged: (v) { b.setSearchEngine(v!); setState((){}); });
  Widget _colorDot(BrowserProvider b, Color color, StateSetter setState) => GestureDetector(onTap: () { b.changeTheme(color); setState((){}); }, child: Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: b.neonColor == color ? Border.all(color: Colors.white, width: 3) : null)));
}

// Start Page
class StartPage extends StatelessWidget {
  final BrowserProvider browser;
  final int? tabIndex;
  const StartPage({super.key, required this.browser, this.tabIndex});

  @override Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const SizedBox(height: 40),
            // Logo
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [browser.neonColor.withOpacity(0.3), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight), border: Border.all(color: browser.neonColor, width: 2)),
              child: Icon(Iconsax.global, size: 50, color: browser.neonColor),
            ),
            const SizedBox(height: 16),
            Text("LUXOR", style: TextStyle(color: browser.neonColor, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8)),
            const SizedBox(height: 30),

            // Search Bar
            GestureDetector(
              onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => SearchSheet(browser: browser, tabIndex: tabIndex)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(30), border: Border.all(color: browser.neonColor.withOpacity(0.3))),
                child: Row(children: [
                  Icon(Iconsax.search_normal, color: browser.neonColor, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(child: Text("Search or enter URL...", style: TextStyle(color: Colors.white54, fontSize: 15))),
                  Icon(Iconsax.microphone, color: browser.neonColor, size: 20),
                ]),
              ),
            ),

            const SizedBox(height: 40),

            // Speed Dials
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 16, crossAxisSpacing: 16),
              itemCount: browser.speedDials.length + 1,
              itemBuilder: (_, i) {
                if (i == browser.speedDials.length) {
                  return GestureDetector(
                    onTap: () => _showAddSpeedDial(context, browser),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle, border: Border.all(color: Colors.white24, style: BorderStyle.solid)),
                        child: const Icon(Icons.add, color: Colors.white38),
                      ),
                      const SizedBox(height: 8),
                      const Text("Add", style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ]),
                  );
                }
                final dial = browser.speedDials[i];
                return GestureDetector(
                  onTap: () => browser.loadUrl(dial.url, tabIndex),
                  onLongPress: () => _showSpeedDialOptions(context, browser, i),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(color: Color(dial.colorValue).withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: Color(dial.colorValue).withOpacity(0.4))),
                      child: Center(child: Text(dial.label.isNotEmpty ? dial.label[0].toUpperCase() : "?", style: TextStyle(color: Color(dial.colorValue), fontSize: 22, fontWeight: FontWeight.bold))),
                    ),
                    const SizedBox(height: 8),
                    Text(dial.label, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                );
              },
            ),

            // Stats
            if (browser.blockedAdsCount > 0 || browser.history.isNotEmpty) ...[
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _stat("Ads Blocked", browser.blockedAdsCount.toString(), browser.neonColor),
                  _stat("Pages Visited", browser.history.length.toString(), Colors.white),
                  _stat("Bookmarks", browser.bookmarks.length.toString(), Colors.white),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(children: [
    Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
    Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
  ]);

  void _showAddSpeedDial(BuildContext context, BrowserProvider b) {
    final urlCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text("Add Shortcut", style: TextStyle(color: b.neonColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: labelCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Name", labelStyle: TextStyle(color: Colors.white54))),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "URL", labelStyle: TextStyle(color: Colors.white54))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () { if (urlCtrl.text.isNotEmpty && labelCtrl.text.isNotEmpty) { b.addSpeedDial(labelCtrl.text, urlCtrl.text); Navigator.pop(context); } }, child: const Text("Add")),
        ],
      ),
    );
  }

  void _showSpeedDialOptions(BuildContext context, BrowserProvider b, int index) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF101010),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Iconsax.edit, color: Colors.white), title: const Text("Edit", style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); _showEditSpeedDial(context, b, index); }),
          ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Remove", style: TextStyle(color: Colors.red)), onTap: () { b.removeSpeedDial(index); Navigator.pop(context); }),
        ]),
      ),
    );
  }

  void _showEditSpeedDial(BuildContext context, BrowserProvider b, int index) {
    final dial = b.speedDials[index];
    final urlCtrl = TextEditingController(text: dial.url);
    final labelCtrl = TextEditingController(text: dial.label);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: Text("Edit Shortcut", style: TextStyle(color: b.neonColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: labelCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Name", labelStyle: TextStyle(color: Colors.white54))),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "URL", labelStyle: TextStyle(color: Colors.white54))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () { b.editSpeedDial(index, labelCtrl.text, urlCtrl.text); Navigator.pop(context); }, child: const Text("Save")),
        ],
      ),
    );
  }
}

// Other Widgets
class TabGridPage extends StatelessWidget {
  final BrowserProvider browser;
  final int maxSplits;
  const TabGridPage({super.key, required this.browser, required this.maxSplits});

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text("Tabs (${browser.tabs.length})", style: const TextStyle(fontSize: 16)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: browser.toggleTabGrid),
        actions: [
          IconButton(icon: const Icon(Iconsax.document_copy), tooltip: "Split View", onPressed: () { browser.toggleSplitMode(maxSplits); browser.toggleTabGrid(); }),
          IconButton(icon: const Icon(Icons.add), onPressed: () => browser.addNewTab()),
        ]
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.75),
        itemCount: browser.tabs.length,
        itemBuilder: (_, i) => _TabCard(browser: browser, index: i, maxSplits: maxSplits),
      ),
      floatingActionButton: FloatingActionButton(backgroundColor: browser.neonColor, onPressed: () => browser.addNewTab("luxor://home", true), child: const Icon(Iconsax.eye_slash, color: Colors.black)),
    );
  }
}

class _TabCard extends StatelessWidget {
  final BrowserProvider browser;
  final int index;
  final int maxSplits;
  const _TabCard({required this.browser, required this.index, required this.maxSplits});

  @override Widget build(BuildContext context) {
    final tab = browser.tabs[index];
    final isActive = index == browser.currentTabIndex;
    return GestureDetector(
      onTap: () => browser.switchTab(index),
      onLongPress: () => _showOptions(context),
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: isActive ? browser.neonColor : Colors.white10, width: isActive ? 2 : 1)),
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              child: tab.thumbnail != null
                ? Image.memory(tab.thumbnail!, fit: BoxFit.cover, width: double.infinity)
                : Container(color: Colors.black, child: Center(child: Icon(tab.url.contains("luxor://") ? Iconsax.home : Iconsax.global, color: Colors.white24, size: 40))),
            )
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFF2A2A2A), borderRadius: BorderRadius.vertical(bottom: Radius.circular(11))),
            child: Row(children: [
              if (tab.isIncognito) Container(margin: const EdgeInsets.only(right: 6), child: const Icon(Iconsax.eye_slash, size: 12, color: Colors.purple)),
              Expanded(child: Text(tab.title, style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
              GestureDetector(onTap: () => browser.closeTab(index), child: const Icon(Icons.close, size: 16, color: Colors.white54)),
            ]),
          ),
        ])
      )
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF101010),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Iconsax.document_copy, color: Colors.white), title: const Text("Add to Split View", style: TextStyle(color: Colors.white)), onTap: () { browser.addTabToSplit(index, maxSplits); Navigator.pop(context); }),
          ListTile(leading: const Icon(Iconsax.share, color: Colors.white), title: const Text("Share URL", style: TextStyle(color: Colors.white)), onTap: () { Share.share(browser.tabs[index].url); Navigator.pop(context); }),
          ListTile(leading: const Icon(Icons.close, color: Colors.red), title: const Text("Close Tab", style: TextStyle(color: Colors.red)), onTap: () { browser.closeTab(index); Navigator.pop(context); }),
        ]),
      ),
    );
  }
}

class SearchSheet extends StatefulWidget {
  final BrowserProvider browser;
  final int? tabIndex;
  const SearchSheet({super.key, required this.browser, this.tabIndex});
  @override State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  late TextEditingController _ctrl;
  List<dynamic> _suggestions = [];

  @override void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.browser.urlController.text);
    _ctrl.addListener(_onChanged);
  }

  void _onChanged() {
    final q = _ctrl.text.toLowerCase();
    if (q.isEmpty) { setState(() => _suggestions = []); return; }
    setState(() {
      _suggestions = [
        ...widget.browser.bookmarks.where((b) => b.url.toLowerCase().contains(q) || b.title.toLowerCase().contains(q)).take(3).map((b) => {"type": "bookmark", "item": b}),
        ...widget.browser.history.where((h) => h.url.toLowerCase().contains(q) || h.title.toLowerCase().contains(q)).take(5).map((h) => {"type": "history", "item": h}),
      ];
    });
  }

  @override Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Color(0xFF101010), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Container(
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: widget.browser.neonColor.withOpacity(0.3))),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 16, color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search or enter URL...", hintStyle: const TextStyle(color: Colors.white38),
              border: InputBorder.none, contentPadding: const EdgeInsets.all(16),
              prefixIcon: Icon(Iconsax.search_normal, color: widget.browser.neonColor),
              suffixIcon: _ctrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, color: Colors.white38), onPressed: () { _ctrl.clear(); setState(() => _suggestions = []); }) : null,
            ),
            onSubmitted: (v) { widget.browser.loadUrl(v, widget.tabIndex); Navigator.pop(context); }
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _suggestions.isEmpty
            ? _buildQuickAccess()
            : ListView.builder(
                itemCount: _suggestions.length,
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  final isBookmark = s["type"] == "bookmark";
                  final item = s["item"];
                  return ListTile(
                    leading: Icon(isBookmark ? Iconsax.bookmark_2 : Iconsax.clock, color: isBookmark ? widget.browser.neonColor : Colors.white38, size: 20),
                    title: Text(item.title, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.url, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () { widget.browser.loadUrl(item.url, widget.tabIndex); Navigator.pop(context); },
                  );
                },
              ),
        ),
      ])
    );
  }

  Widget _buildQuickAccess() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text("Quick Access", style: TextStyle(color: widget.browser.neonColor, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    Wrap(spacing: 10, runSpacing: 10, children: widget.browser.speedDials.map((s) => ActionChip(
      avatar: Container(width: 20, height: 20, decoration: BoxDecoration(color: Color(s.colorValue).withOpacity(0.2), shape: BoxShape.circle), child: Center(child: Text(s.label.isNotEmpty ? s.label[0] : "?", style: TextStyle(color: Color(s.colorValue), fontSize: 10)))),
      label: Text(s.label),
      backgroundColor: Colors.white10,
      onPressed: () { widget.browser.loadUrl(s.url, widget.tabIndex); Navigator.pop(context); },
    )).toList()),
  ]);

  @override void dispose() { _ctrl.dispose(); super.dispose(); }
}

class AiSidebar extends StatelessWidget {
  const AiSidebar({super.key});
  @override Widget build(BuildContext context) {
    final ai = Provider.of<AiAgentProvider>(context);
    final browser = Provider.of<BrowserProvider>(context, listen: false);
    final ctrl = TextEditingController();
    return Column(children: [
      AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: browser.toggleAiSidebar),
        title: Text("Luxor AI", style: TextStyle(color: browser.neonColor)),
        actions: [IconButton(icon: const Icon(Iconsax.trash), onPressed: ai.clearChat)],
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: ai.messages.length,
          itemBuilder: (_, i) => Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ai.messages[i].isUser ? Colors.white10 : browser.neonColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(ai.messages[i].text, style: TextStyle(color: ai.messages[i].isUser ? Colors.white : browser.neonColor))
          ),
        )
      ),
      if (ai.isThinking) Padding(padding: const EdgeInsets.all(12), child: LinearProgressIndicator(color: browser.neonColor, backgroundColor: Colors.white10)),
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Ask anything...", hintStyle: const TextStyle(color: Colors.white38),
            filled: true, fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
            suffixIcon: IconButton(icon: Icon(Iconsax.send_1, color: browser.neonColor), onPressed: () { if (ctrl.text.isNotEmpty) { ai.sendMessage(ctrl.text, browser); ctrl.clear(); } }),
          ),
          onSubmitted: (v) { if (v.isNotEmpty) { ai.sendMessage(v, browser); ctrl.clear(); } }
        )
      ),
    ]);
  }
}

class GlassBox extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;
  const GlassBox({super.key, required this.child, this.borderRadius = 20, this.padding = EdgeInsets.zero});
  @override Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(borderRadius), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(padding: padding, decoration: BoxDecoration(color: const Color(0xFF1E1E1E).withOpacity(0.9), borderRadius: BorderRadius.circular(borderRadius), border: Border.all(color: Colors.white.withOpacity(0.1))), child: child)));
}

class LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  const LockScreen({super.key, required this.onUnlock});
  @override Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(padding: const EdgeInsets.all(30), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: browser.neonColor, width: 2)), child: Icon(Iconsax.lock, size: 60, color: browser.neonColor)),
          const SizedBox(height: 24),
          const Text("Luxor Browser", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Tap to unlock", style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 40),
          ElevatedButton.icon(onPressed: onUnlock, icon: const Icon(Iconsax.finger_scan), label: const Text("Unlock"), style: ElevatedButton.styleFrom(backgroundColor: browser.neonColor, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)))),
        ]),
      ),
    );
  }
}

class ScannerPage extends StatelessWidget {
  const ScannerPage({super.key});
  @override Widget build(BuildContext context) => Scaffold(body: MobileScanner(onDetect: (c) { if (c.barcodes.isNotEmpty) { Provider.of<BrowserProvider>(context, listen: false).loadUrl(c.barcodes.first.rawValue!); Navigator.pop(context); } }));
}
