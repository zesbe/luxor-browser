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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrowserProvider()),
        ChangeNotifierProvider(create: (_) => AiAgentProvider()),
        ChangeNotifierProvider(create: (_) => DevToolsProvider()),
      ],
      child: const AiBrowserApp(),
    ),
  );
}

class AiBrowserApp extends StatelessWidget {
  const AiBrowserApp({super.key});

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
  GlobalKey webViewKey = GlobalKey();
  BrowserTab({required this.id, this.url = "luxor://home", this.title = "Start Page", this.isIncognito = false});
}

class HistoryItem {
  final String url, title;
  HistoryItem({required this.url, required this.title});
  Map<String, dynamic> toJson() => {'url': url, 'title': title};
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(url: json['url'] ?? "", title: json['title'] ?? "");
}

class BookmarkItem {
  final String url, title;
  BookmarkItem({required this.url, required this.title});
  Map<String, dynamic> toJson() => {'url': url, 'title': title};
  factory BookmarkItem.fromJson(Map<String, dynamic> json) => BookmarkItem(url: json['url'] ?? "", title: json['title'] ?? "");
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

// --- PROVIDERS ---

class DevToolsProvider extends ChangeNotifier {
  List<String> consoleLogs = [];
  void addLog(String message, ConsoleMessageLevel level) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final levelName = level.toString().split('.').last.toUpperCase();
    consoleLogs.add("[$timestamp] $levelName: $message");
    notifyListeners();
  }
  void clearLogs() { consoleLogs.clear(); notifyListeners(); }
}

class BrowserProvider extends ChangeNotifier {
  List<BrowserTab> tabs = [];
  int currentTabIndex = 0;
  List<HistoryItem> history = [];
  List<BookmarkItem> bookmarks = [];
  List<String> downloads = [];
  List<UserScript> userScripts = [];
  List<SpeedDialItem> speedDials = [];

  String searchEngine = "https://www.google.com/search?q=";
  String customUserAgent = "";
  bool isDesktopMode = false, isAdBlockEnabled = true, isForceDarkWeb = false, isJsEnabled = true, isImagesEnabled = true;
  bool isBiometricEnabled = false, isZenMode = false, isGameMode = false, isLocked = false;
  int blockedAdsCount = 0;
  Color neonColor = const Color(0xFFFFD700); // Luxor Gold

  double progress = 0;
  bool isSecure = true, isMenuOpen = false, showFindBar = false, showAiSidebar = false, showTabGrid = false;
  bool isMediaPlaying = false;
  SslCertificate? sslCertificate;

  // Split View
  bool isSplitMode = false;
  List<int> splitTabIndices = [];
  int activeSplitIndex = 0;

  // Biometric stability fix
  bool _isAuthenticating = false;
  DateTime? _lastPausedTime;
  static const int _lockDelaySeconds = 5; // Only lock after 5 seconds in background

  TextEditingController urlController = TextEditingController(), findController = TextEditingController();
  stt.SpeechToText _speech = stt.SpeechToText();
  FlutterTts _flutterTts = FlutterTts();
  final LocalAuthentication auth = LocalAuthentication();
  bool isSpeaking = false;

  BrowserProvider() { _loadData(); _addNewTab(); _initTts(); }

  BrowserTab get currentTab => tabs[currentTabIndex];

  InAppWebViewSettings getSettings() {
    return InAppWebViewSettings(
      isInspectable: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      javaScriptEnabled: isJsEnabled,
      loadsImagesAutomatically: isImagesEnabled,
      cacheEnabled: !currentTab.isIncognito,
      domStorageEnabled: !currentTab.isIncognito,
      useWideViewPort: true,
      safeBrowsingEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowFileAccessFromFileURLs: true,
      allowUniversalAccessFromFileURLs: true,
      supportMultipleWindows: true,
      disableHorizontalScroll: false,
      disableVerticalScroll: false,
      hardwareAcceleration: true,
      userAgent: customUserAgent.isNotEmpty ? customUserAgent : (isDesktopMode ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" : "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
    );
  }

  Future<void> _initTts() async { await _flutterTts.setLanguage("en-US"); await _flutterTts.setSpeechRate(0.5); _flutterTts.setCompletionHandler(() { isSpeaking = false; notifyListeners(); }); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    searchEngine = prefs.getString('searchEngine') ?? "https://www.google.com/search?q=";
    isAdBlockEnabled = prefs.getBool('adBlock') ?? true;
    isForceDarkWeb = prefs.getBool('forceDark') ?? false;
    isJsEnabled = prefs.getBool('jsEnabled') ?? true;
    isImagesEnabled = prefs.getBool('imagesEnabled') ?? true;
    isBiometricEnabled = prefs.getBool('biometric') ?? false;
    blockedAdsCount = prefs.getInt('blockedAds') ?? 0;
    int? colorValue = prefs.getInt('neonColor'); if (colorValue != null) neonColor = Color(colorValue);

    history = (prefs.getStringList('history') ?? []).map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    bookmarks = (prefs.getStringList('bookmarks') ?? []).map((e) => BookmarkItem.fromJson(jsonDecode(e))).toList();
    downloads = prefs.getStringList('downloads') ?? [];
    userScripts = (prefs.getStringList('userScripts') ?? []).map((e) => UserScript.fromJson(jsonDecode(e))).toList();

    final sd = prefs.getStringList('speedDials');
    if (sd != null && sd.isNotEmpty) {
      speedDials = sd.map((e) => SpeedDialItem.fromJson(jsonDecode(e))).toList();
    } else {
      speedDials = [
        SpeedDialItem(url: "https://google.com", label: "Google", colorValue: Colors.blue.value),
        SpeedDialItem(url: "https://youtube.com", label: "YouTube", colorValue: Colors.red.value),
        SpeedDialItem(url: "https://github.com", label: "GitHub", colorValue: Colors.white.value),
      ];
    }
    // Only set locked if biometric is enabled - will be checked on first build
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
    prefs.setInt('blockedAds', blockedAdsCount);
    prefs.setInt('neonColor', neonColor.value);
    prefs.setStringList('history', history.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('bookmarks', bookmarks.map((e) => jsonEncode(e.toJson())).toList());
    prefs.setStringList('downloads', downloads);
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
      // Update split indices if in split mode
      if (isSplitMode) {
        splitTabIndices.removeWhere((i) => i == index);
        splitTabIndices = splitTabIndices.map((i) => i > index ? i - 1 : i).toList();
        if (splitTabIndices.isEmpty) {
          isSplitMode = false;
        }
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
      if (tabIndex == null || tabIndex == currentTabIndex) {
        urlController.text = "";
      }
      notifyListeners();
      return;
    }

    url = url.trim();

    if (url == "home" || url == "luxor://home" || url == "neon://home" || url == "about:home") {
      tab.url = "luxor://home";
      if (tabIndex == null || tabIndex == currentTabIndex) {
        urlController.text = "";
      }
      notifyListeners();
      return;
    }

    if (url.startsWith("luxor://") || url.startsWith("neon://")) {
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
        final uri = WebUri(url);
        tab.controller!.loadUrl(urlRequest: URLRequest(url: uri));
      } catch (e) {
        String encodedQuery = Uri.encodeComponent(url);
        final searchUrl = "$searchEngine$encodedQuery";
        tab.url = searchUrl;
        final searchUri = WebUri(searchUrl);
        tab.controller!.loadUrl(urlRequest: URLRequest(url: searchUri));
      }
    }

    notifyListeners();
  }

  // Home button
  void goHome() {
    loadUrl("luxor://home");
  }

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

  void panicButton() {
    tabs.removeWhere((t) => t.isIncognito);
    if (tabs.isEmpty) _addNewTab();
    else currentTabIndex = 0;
    loadUrl("luxor://home");
    notifyListeners();
  }

  // Split View Functions
  void toggleSplitMode(int maxSplits) {
    if (isSplitMode) {
      // Exit split mode
      isSplitMode = false;
      splitTabIndices.clear();
    } else {
      // Enter split mode
      if (tabs.length >= 2) {
        isSplitMode = true;
        splitTabIndices = [currentTabIndex];
        // Add next available tab
        int nextTab = (currentTabIndex + 1) % tabs.length;
        if (!splitTabIndices.contains(nextTab)) {
          splitTabIndices.add(nextTab);
        }
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
    if (splitTabIndices.length < 2) {
      isSplitMode = false;
      splitTabIndices.clear();
    }
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

  // Improved biometric handling
  void onAppPaused() {
    _lastPausedTime = DateTime.now();
  }

  void onAppResumed(BuildContext context) {
    if (!isBiometricEnabled) return;
    if (_lastPausedTime == null) return;

    final pauseDuration = DateTime.now().difference(_lastPausedTime!);
    if (pauseDuration.inSeconds >= _lockDelaySeconds) {
      isLocked = true;
      notifyListeners();
      checkBiometricLock(context);
    }
    _lastPausedTime = null;
  }

  Future<void> checkBiometricLock(BuildContext context) async {
    if (!isBiometricEnabled) {
      isLocked = false;
      notifyListeners();
      return;
    }

    // Prevent multiple auth dialogs
    if (_isAuthenticating) return;

    try {
      // Check if device supports biometrics
      final canAuth = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canAuth) {
        isLocked = false;
        notifyListeners();
        return;
      }

      _isAuthenticating = true;
      final authenticated = await auth.authenticate(
        localizedReason: 'Unlock Luxor Browser',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        )
      );

      if (authenticated) {
        isLocked = false;
      }
    } catch (e) {
      // On error, unlock to prevent lockout
      isLocked = false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  void toggleBiometric() async {
    if (!isBiometricEnabled) {
      // Enabling - verify first
      try {
        final canAuth = await auth.canCheckBiometrics || await auth.isDeviceSupported();
        if (!canAuth) return;

        final authenticated = await auth.authenticate(
          localizedReason: 'Enable biometric lock',
          options: const AuthenticationOptions(biometricOnly: false),
        );
        if (authenticated) {
          isBiometricEnabled = true;
          isLocked = false;
        }
      } catch (e) {
        return;
      }
    } else {
      isBiometricEnabled = false;
      isLocked = false;
    }
    _saveData();
    notifyListeners();
  }

  void toggleBookmark() { if (currentTab.url == "luxor://home") return; final idx = bookmarks.indexWhere((b) => b.url == currentTab.url); if (idx != -1) bookmarks.removeAt(idx); else bookmarks.insert(0, BookmarkItem(url: currentTab.url, title: currentTab.title)); _saveData(); notifyListeners(); }
  bool isBookmarked() { return bookmarks.any((b) => b.url == currentTab.url); }
  void addDownload(String f) { downloads.insert(0, "${DateTime.now().toString().substring(0,16)} - $f"); _saveData(); }
  void incrementAdsBlocked() { blockedAdsCount++; if (blockedAdsCount % 5 == 0) _saveData(); notifyListeners(); }
  void findInPage(String t) { if (t.isEmpty) currentTab.controller?.clearMatches(); else currentTab.controller?.findAllAsync(find: t); }
  void findNext() => currentTab.controller?.findNext(forward: true);
  void findPrev() => currentTab.controller?.findNext(forward: false);
  void toggleFindBar() { showFindBar = !showFindBar; if (!showFindBar) currentTab.controller?.clearMatches(); notifyListeners(); }
  void toggleReaderMode() { String js = """(function(){var p=document.getElementsByTagName('p');var txt='';for(var i=0;i<p.length;i++)txt+='<p>'+p[i].innerHTML+'</p>';document.body.innerHTML='<div style=\"max-width:800px;margin:0 auto;padding:20px;font-family:sans-serif;line-height:1.6;color:#e0e0e0;background:#121212;\">'+txt+'</div>';document.body.style.backgroundColor='#121212';})();"""; currentTab.controller?.evaluateJavascript(source: js); toggleMenu(); }
  void toggleDesktopMode() async { isDesktopMode = !isDesktopMode; await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void toggleAdBlock() async { isAdBlockEnabled = !isAdBlockEnabled; await _saveData(); reload(); notifyListeners(); }
  void toggleForceDark() async { isForceDarkWeb = !isForceDarkWeb; await _saveData(); reload(); notifyListeners(); }
  void toggleJs() async { isJsEnabled = !isJsEnabled; await _saveData(); await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void toggleDataSaver() async { isImagesEnabled = !isImagesEnabled; await _saveData(); await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void setSearchEngine(String url) { searchEngine = url; _saveData(); notifyListeners(); }
  void clearData() async { await currentTab.controller?.clearCache(); await CookieManager.instance().deleteAllCookies(); history.clear(); downloads.clear(); await _saveData(); notifyListeners(); }
  void changeTheme(Color color) { neonColor = color; _saveData(); notifyListeners(); }

  void addUserScript(String n, String c) { userScripts.add(UserScript(id: const Uuid().v4(), name: n, code: c)); _saveData(); notifyListeners(); }
  void toggleUserScript(String id) { final s = userScripts.firstWhere((e) => e.id == id); s.active = !s.active; _saveData(); reload(); notifyListeners(); }
  void deleteUserScript(String id) { userScripts.removeWhere((e) => e.id == id); _saveData(); notifyListeners(); }
  void toggleTts() async { if (isSpeaking) { await _flutterTts.stop(); isSpeaking = false; } else { final text = await currentTab.controller?.evaluateJavascript(source: "document.body.innerText"); if (text != null && text.toString().isNotEmpty) { isSpeaking = true; await _flutterTts.speak(text.toString()); } } notifyListeners(); }

  void injectScripts(InAppWebViewController c) {
    if (isAdBlockEnabled) c.evaluateJavascript(source: "(function(){var b=0;['.ad','.ads','.advertisement','iframe[src*=\"ads\"]','[id^=\"google_ads\"]'].forEach(s=>{var e=document.querySelectorAll(s);if(e.length>0){b+=e.length;e.forEach(x=>x.style.display='none');}});if(b>0)console.log('BLOCKED_ADS:'+b);})();");
    if (isForceDarkWeb) c.evaluateJavascript(source: "(function(){var s=document.createElement('style');s.innerHTML='html{filter:invert(1) hue-rotate(180deg)!important;}img,video,iframe,canvas{filter:invert(1) hue-rotate(180deg)!important;}';document.head.appendChild(s);})();");
    for (var s in userScripts) { if (s.active) c.evaluateJavascript(source: "(function(){ try { ${s.code} } catch(e) { console.log('UserScript Error'); } })();"); }
  }

  Future<void> savePageOffline(BuildContext ctx) async {
    try {
      final temp = await getTemporaryDirectory();
      final path = "${temp.path}/offline_${DateTime.now().millisecondsSinceEpoch}.mht";
      await currentTab.controller?.saveWebArchive(filePath: path, autoname: false);
      addDownload("Archive: $path"); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Saved Offline")));
    } catch (e) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Failed to save"))); }
  }

  Future<List<String>> sniffMedia() async { final r = await currentTab.controller?.evaluateJavascript(source: "(function(){var v=document.getElementsByTagName('video'),a=document.getElementsByTagName('audio'),l=[];for(var i=0;i<v.length;i++)if(v[i].src)l.push(v[i].src);for(var i=0;i<a.length;i++)if(a[i].src)l.push(a[i].src);return l;})();"); return r != null ? (r as List).map((e) => e.toString()).toList() : []; }
  void startVoice(BuildContext ctx) async { if (await Permission.microphone.request().isGranted && await _speech.initialize()) _speech.listen(onResult: (r) { if (r.finalResult) loadUrl(r.recognizedWords); }); }
  void addToHistory(String u, String? t, [int? tabIndex]) {
    final tab = tabIndex != null && tabIndex < tabs.length ? tabs[tabIndex] : currentTab;
    if (!tab.isIncognito && u != "luxor://home" && u != "neon://home" && u != "about:blank" && u.isNotEmpty) {
      if (history.isEmpty || history.first.url != u) {
        history.insert(0, HistoryItem(url: u, title: t ?? "Unknown"));
        if (history.length > 50) history.removeLast();
        _saveData();
      }
    }
  }
  Future<void> viewSource(BuildContext ctx) async { final h = await currentTab.controller?.getHtml(); if (h != null) Navigator.push(ctx, MaterialPageRoute(builder: (_) => SourceViewerPage(html: h))); }
  Future<void> shareScreenshot(BuildContext ctx) async { try { final i = await currentTab.controller?.takeScreenshot(); if (i == null) return; final t = await getTemporaryDirectory(); final f = File('${t.path}/shot_${DateTime.now().millisecondsSinceEpoch}.png'); await f.writeAsBytes(i); await Share.shareXFiles([XFile(f.path)]); } catch (e) {} }
  void setCustomUA(String ua) async { customUserAgent = ua; await currentTab.controller?.setSettings(settings: getSettings()); currentTab.controller?.reload(); notifyListeners(); }
  void updateSSL(SslCertificate? s) { sslCertificate = s; notifyListeners(); }
  void goBack() => currentTab.controller?.goBack();
  void goForward() => currentTab.controller?.goForward();
  void reload() => currentTab.controller?.reload();
  void printPage() async { await currentTab.controller?.printCurrentPage(); }

  Future<void> exportData(BuildContext ctx) async { final d = {'history': history.map((e) => e.toJson()).toList(), 'bookmarks': bookmarks.map((e) => e.toJson()).toList(), 'speedDials': speedDials.map((e) => e.toJson()).toList()}; await Share.share(jsonEncode(d)); }
  Future<void> importData(BuildContext ctx, String s) async { try { final d = jsonDecode(s); if (d['history'] != null) history = (d['history'] as List).map((e) => HistoryItem.fromJson(e)).toList(); if (d['bookmarks'] != null) bookmarks = (d['bookmarks'] as List).map((e) => BookmarkItem.fromJson(e)).toList(); if (d['speedDials'] != null) speedDials = (d['speedDials'] as List).map((e) => SpeedDialItem.fromJson(e)).toList(); await _saveData(); notifyListeners(); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Restored"))); } catch (e) { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Import Error"))); } }
  void factoryReset() async { final p = await SharedPreferences.getInstance(); await p.clear(); _loadData(); notifyListeners(); }
  void addSpeedDial(String label, String url) { speedDials.add(SpeedDialItem(url: url, label: label, colorValue: Colors.primaries[speedDials.length % Colors.primaries.length].value)); _saveData(); notifyListeners(); }
  void removeSpeedDial(int index) { speedDials.removeAt(index); _saveData(); notifyListeners(); }
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [ChatMessage(text: "Luxor AI Ready.", isUser: false)];
  bool isThinking = false;
  void sendMessage(String text, BrowserProvider b) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true; notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600));
    String resp = "Processed.";
    if (text.toLowerCase().contains("game")) { b.toggleGameMode(); resp = "Game Mode toggled."; }
    else if (text.toLowerCase().contains("home")) { b.loadUrl("luxor://home"); resp = "Going Home."; }
    else if (text.toLowerCase().contains("split")) { b.toggleSplitMode(2); resp = "Split mode toggled."; }
    else { resp = "I can control settings or help you browse."; }
    messages.add(ChatMessage(text: resp, isUser: false));
    isThinking = false; notifyListeners();
  }
}

class ChatMessage { final String text; final bool isUser; ChatMessage({required this.text, required this.isUser}); }

// --- UI COMPONENTS ---

class BrowserHomePage extends StatefulWidget { const BrowserHomePage({super.key}); @override State<BrowserHomePage> createState() => _BrowserHomePageState(); }
class _BrowserHomePageState extends State<BrowserHomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _menuController;
  late Animation<double> _menuScale;
  late PullToRefreshController _pullToRefreshController;
  late AnimationController _visualizerController;

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
    _visualizerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final browser = Provider.of<BrowserProvider>(context, listen: false);
      if (browser.isBiometricEnabled && browser.isLocked) {
        browser.checkBiometricLock(context);
      }
    });
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _menuController.dispose();
    _visualizerController.dispose();
    super.dispose();
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    final browser = Provider.of<BrowserProvider>(context, listen: false);
    if (state == AppLifecycleState.paused) {
      browser.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      browser.onAppResumed(context);
    }
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

    // Split View Mode
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
        if (browser.showFindBar) Positioned(bottom: browser.isZenMode ? 20 : 140, left: 20, right: 20, child: GlassBox(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [Expanded(child: TextField(controller: browser.findController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Find...", border: InputBorder.none), onChanged: (v) => browser.findInPage(v))), IconButton(icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white), onPressed: browser.findPrev), IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white), onPressed: browser.findNext), IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: browser.toggleFindBar)]))),
        if (!browser.showAiSidebar && !browser.isZenMode) _buildBottomBar(context, browser, maxSplits),
        if (browser.isMediaPlaying && !browser.isZenMode) Positioned(bottom: 0, left: 0, right: 0, height: 2, child: AnimatedBuilder(animation: _visualizerController, builder: (context, child) => Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(20, (i) => Container(width: 5, height: 2 + (Random().nextDouble() * 10 * _visualizerController.value), color: browser.neonColor.withOpacity(0.5), margin: const EdgeInsets.symmetric(horizontal: 1)))))),
        if (browser.isZenMode) Positioned(bottom: 20, right: 20, child: FloatingActionButton.small(backgroundColor: Colors.white10, child: Icon(browser.isGameMode ? Icons.videogame_asset_off : Icons.expand_less, color: Colors.white), onPressed: () => browser.isGameMode ? browser.toggleGameMode() : browser.toggleZenMode()))
      ])
    );
  }

  Widget _buildSplitView(BuildContext context, BrowserProvider browser, DevToolsProvider devTools, int maxSplits) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final splitCount = browser.splitTabIndices.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Split Tab Bar
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
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
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  tab.title,
                                  style: TextStyle(color: isActive ? browser.neonColor : Colors.white70, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => browser.removeTabFromSplit(tabIdx),
                                child: const Icon(Icons.close, size: 14, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  if (splitCount < maxSplits && browser.tabs.length > splitCount)
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white54, size: 20),
                      onPressed: () => _showAddSplitDialog(context, browser, maxSplits),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red, size: 20),
                    onPressed: () => browser.toggleSplitMode(maxSplits),
                  ),
                ],
              ),
            ),
          ),
          // Split WebViews
          Expanded(
            child: isLandscape || splitCount <= 2
              ? Row(
                  children: browser.splitTabIndices.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final tabIdx = entry.value;
                    return Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: idx < splitCount - 1
                              ? BorderSide(color: browser.neonColor.withOpacity(0.3), width: 1)
                              : BorderSide.none,
                          ),
                        ),
                        child: GestureDetector(
                          onTap: () => browser.setActiveSplit(idx),
                          child: _buildWebView(browser, devTools, tabIdx, isSplit: true),
                        ),
                      ),
                    );
                  }).toList(),
                )
              : GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: MediaQuery.of(context).size.width / (MediaQuery.of(context).size.height - 100) * 2 / splitCount.clamp(2, 4),
                  children: browser.splitTabIndices.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final tabIdx = entry.value;
                    return GestureDetector(
                      onTap: () => browser.setActiveSplit(idx),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: idx == browser.activeSplitIndex
                              ? browser.neonColor
                              : Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: _buildWebView(browser, devTools, tabIdx, isSplit: true),
                      ),
                    );
                  }).toList(),
                ),
          ),
          // Bottom Bar
          if (!browser.isZenMode) _buildSplitBottomBar(context, browser, maxSplits),
        ],
      ),
    );
  }

  Widget _buildWebView(BrowserProvider browser, DevToolsProvider devTools, int tabIndex, {bool isSplit = false}) {
    final tab = browser.tabs[tabIndex];
    final isHome = tab.url == "luxor://home" || tab.url == "neon://home";

    if (isHome) {
      return StartPage(browser: browser, tabIndex: isSplit ? tabIndex : null);
    }

    return InAppWebView(
      key: ValueKey('${tab.id}_$tabIndex'),
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
      initialSettings: browser.getSettings(),
      pullToRefreshController: isSplit ? null : _pullToRefreshController,
      onWebViewCreated: (c) => browser.setController(c, tabIndex),
      onLoadStart: (c, url) => browser.updateUrl(url.toString(), tabIndex),
      onLoadStop: (c, url) async {
        if (tabIndex == browser.currentTabIndex) browser.progress = 1.0;
        browser.updateUrl(url.toString(), tabIndex);
        browser.tabs[tabIndex].title = await c.getTitle() ?? "Unknown";
        browser.injectScripts(c);
        browser.addToHistory(url.toString(), browser.tabs[tabIndex].title, tabIndex);
        if (tabIndex == browser.currentTabIndex) {
          browser.updateSSL(await c.getCertificate());
        }
      },
      onProgressChanged: (c, p) {
        if (tabIndex == browser.currentTabIndex) {
          browser.progress = p / 100;
        }
      },
      onConsoleMessage: (c, m) {
        if (m.message.startsWith("BLOCKED_ADS:")) browser.incrementAdsBlocked();
        devTools.addLog(m.message, m.messageLevel);
      },
      onTitleChanged: (c, title) {
        browser.tabs[tabIndex].title = title ?? "Unknown";
        browser.notifyListeners();
      },
    );
  }

  Widget _buildBottomBar(BuildContext context, BrowserProvider browser, int maxSplits) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: 20,
      left: 20,
      right: 20,
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity! > 0) browser.swipeTab(true);
          else if (d.primaryVelocity! < 0) browser.swipeTab(false);
        },
        child: GlassBox(
          borderRadius: 50,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: Row(children: [
            _circleBtn(browser.isMenuOpen ? Icons.close : Iconsax.category, () => browser.toggleMenu()),
            const SizedBox(width: 4),
            // Home Button
            _circleBtn(Iconsax.home, () => browser.goHome(), color: browser.neonColor),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () => _showSearch(context, browser),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                  alignment: Alignment.centerLeft,
                  child: Row(children: [
                    Icon(browser.isSecure ? Iconsax.lock5 : Iconsax.unlock, size: 12, color: browser.isSecure ? Colors.green : Colors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(browser.currentTab.url == "luxor://home" ? "Search..." : browser.currentTab.url.replaceFirst("https://", "").replaceFirst("www.", ""), style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis)),
                    if (browser.currentTab.url != "luxor://home")
                      GestureDetector(onTap: () => browser.toggleBookmark(), child: Icon(browser.isBookmarked() ? Iconsax.star1 : Iconsax.star, size: 14, color: browser.isBookmarked() ? browser.neonColor : Colors.white30)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => browser.toggleTabGrid(),
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(5)),
                        child: Text("${browser.tabs.length}", style: const TextStyle(fontSize: 10, color: Colors.white))
                      )
                    )
                  ])
                )
              )
            ),
            const SizedBox(width: 4),
            // Split Button
            _circleBtn(browser.isSplitMode ? Iconsax.document : Iconsax.document_copy, () => browser.toggleSplitMode(maxSplits), color: browser.isSplitMode ? browser.neonColor : Colors.white),
            const SizedBox(width: 4),
            _circleBtn(browser.isSpeaking ? Icons.stop : Iconsax.magic_star, () => browser.isSpeaking ? browser.toggleTts() : browser.toggleAiSidebar(), color: browser.neonColor),
          ])
        )
      )
    );
  }

  Widget _buildSplitBottomBar(BuildContext context, BrowserProvider browser, int maxSplits) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1A1A1A),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _circleBtn(Iconsax.arrow_left_2, () => browser.goBack()),
            _circleBtn(Iconsax.arrow_right_3, () => browser.goForward()),
            _circleBtn(Iconsax.home, () => browser.goHome(), color: browser.neonColor),
            _circleBtn(Iconsax.refresh, () => browser.reload()),
            _circleBtn(Iconsax.document, () => browser.toggleSplitMode(maxSplits), color: browser.neonColor),
          ],
        ),
      ),
    );
  }

  void _showAddSplitDialog(BuildContext context, BrowserProvider browser, int maxSplits) {
    final availableTabs = browser.tabs.asMap().entries
      .where((e) => !browser.splitTabIndices.contains(e.key))
      .toList();

    if (availableTabs.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101010),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Add Tab to Split", style: TextStyle(color: browser.neonColor, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...availableTabs.map((entry) => ListTile(
              title: Text(entry.value.title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(entry.value.url, style: const TextStyle(color: Colors.grey, fontSize: 11), overflow: TextOverflow.ellipsis),
              onTap: () {
                browser.addTabToSplit(entry.key, maxSplits);
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(50), child: Container(width: 40, height: 40, alignment: Alignment.center, child: Icon(icon, color: color, size: 20)));

  Widget _buildGridMenu(BuildContext context, BrowserProvider b, int maxSplits) => GridView.count(
    shrinkWrap: true,
    crossAxisCount: 5,
    mainAxisSpacing: 15,
    padding: const EdgeInsets.all(16),
    children: [
      _menuItem(Iconsax.arrow_left_2, "Back", b.goBack),
      _menuItem(Iconsax.arrow_right_3, "Fwd", b.goForward),
      _menuItem(Iconsax.refresh, "Reload", b.reload),
      _menuItem(Iconsax.home_2, "Home", () { b.goHome(); b.toggleMenu(); }),
      _menuItem(Iconsax.document_copy, "Split", () { b.toggleSplitMode(maxSplits); b.toggleMenu(); }, isActive: b.isSplitMode),
      _menuItem(Iconsax.game, "Game", () { b.toggleGameMode(); b.toggleMenu(); }),
      _menuItem(Iconsax.code_circle, "Script", () { b.toggleMenu(); _showScriptManager(context, b); }),
      _menuItem(Iconsax.volume_high, "Read", () { b.toggleTts(); b.toggleMenu(); }),
      _menuItem(Iconsax.setting, "Settings", () { b.toggleMenu(); _showSettingsModal(context, b); }),
      _menuItem(Iconsax.bookmark, "Saved", () { b.toggleMenu(); _showBookmarks(context, b); }),
    ]
  );

  Widget _menuItem(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) => GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isActive ? Provider.of<BrowserProvider>(context).neonColor : Colors.white10, shape: BoxShape.circle), child: Icon(icon, size: 18, color: isActive ? Colors.black : Colors.white)), const SizedBox(height: 5), Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70))]));

  void _showSettingsModal(BuildContext context, BrowserProvider b) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101010),
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setState) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Settings", style: TextStyle(color: Colors.white, fontSize: 20)),
              const SizedBox(height: 20),
              Expanded(child: ListView(children: [
                _sectionHeader("Data", b),
                ListTile(title: const Text("Backup Data", style: TextStyle(color: Colors.white)), onTap: () => b.exportData(context)),
                ListTile(title: const Text("Restore Data", style: TextStyle(color: Colors.white)), onTap: () { _showImportDialog(context, b); }),
                ListTile(title: const Text("Clear Browsing Data", style: TextStyle(color: Colors.orange)), onTap: () => b.clearData()),
                ListTile(title: const Text("Factory Reset", style: TextStyle(color: Colors.red)), onTap: () => b.factoryReset()),
                _sectionHeader("Theme", b),
                Wrap(spacing: 10, children: [_colorDot(b, const Color(0xFFFFD700)), _colorDot(b, const Color(0xFF00FFC2)), _colorDot(b, const Color(0xFFFF0055)), _colorDot(b, const Color(0xFF00BFFF))]),
                _sectionHeader("Security", b),
                SwitchListTile(activeColor: b.neonColor, title: const Text("Biometric Lock", style: TextStyle(color: Colors.white)), subtitle: const Text("Lock app when leaving", style: TextStyle(color: Colors.grey, fontSize: 12)), value: b.isBiometricEnabled, onChanged: (v) { b.toggleBiometric(); setState((){}); }),
                SwitchListTile(activeColor: b.neonColor, title: const Text("AdBlocker", style: TextStyle(color: Colors.white)), value: b.isAdBlockEnabled, onChanged: (v) { b.toggleAdBlock(); setState((){}); }),
                _sectionHeader("Display", b),
                SwitchListTile(activeColor: b.neonColor, title: const Text("Force Dark Mode", style: TextStyle(color: Colors.white)), value: b.isForceDarkWeb, onChanged: (v) { b.toggleForceDark(); setState((){}); }),
                SwitchListTile(activeColor: b.neonColor, title: const Text("Desktop Mode", style: TextStyle(color: Colors.white)), value: b.isDesktopMode, onChanged: (v) { b.toggleDesktopMode(); setState((){}); }),
              ]))
            ]
          )
        );
      })
    );
  }

  void _showImportDialog(BuildContext context, BrowserProvider b) { final ctrl = TextEditingController(); showDialog(context: context, builder: (_) => AlertDialog(backgroundColor: const Color(0xFF222222), title: const Text("Import JSON", style: TextStyle(color: Colors.white)), content: TextField(controller: ctrl, maxLines: 5, style: const TextStyle(color: Colors.white)), actions: [TextButton(onPressed: () { if(ctrl.text.isNotEmpty) b.importData(context, ctrl.text); Navigator.pop(context); }, child: const Text("Import"))])); }
  void _showBookmarks(BuildContext context, BrowserProvider b) { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => Container(height: 500, padding: const EdgeInsets.all(16), child: Column(children: [const Text("Bookmarks", style: TextStyle(color: Colors.white, fontSize: 18)), const SizedBox(height: 12), Expanded(child: ListView.builder(itemCount: b.bookmarks.length, itemBuilder: (_, i) => ListTile(title: Text(b.bookmarks[i].title, style: const TextStyle(color: Colors.white)), subtitle: Text(b.bookmarks[i].url, style: const TextStyle(color: Colors.grey, fontSize: 11)), onTap: () { b.loadUrl(b.bookmarks[i].url); Navigator.pop(context); }))) ]))); }
  void _showScriptManager(BuildContext context, BrowserProvider b) { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => StatefulBuilder(builder: (ctx, setState) => Container(height: 500, padding: const EdgeInsets.all(16), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Scripts", style: TextStyle(color: Colors.white)), IconButton(icon: const Icon(Icons.add, color: Colors.green), onPressed: () => _showAddScriptDialog(context, b, setState))]), Expanded(child: ListView.builder(itemCount: b.userScripts.length, itemBuilder: (ctx, i) => ListTile(title: Text(b.userScripts[i].name, style: const TextStyle(color: Colors.white)), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { b.deleteUserScript(b.userScripts[i].id); setState((){}); }))))])))); }
  void _showAddScriptDialog(BuildContext context, BrowserProvider b, StateSetter setState) { final n = TextEditingController(), c = TextEditingController(); showDialog(context: context, builder: (_) => AlertDialog(backgroundColor: const Color(0xFF222222), title: const Text("New Script"), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: n, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Name")), TextField(controller: c, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Code"))]), actions: [TextButton(onPressed: () { b.addUserScript(n.text, c.text); setState((){}); Navigator.pop(context); }, child: const Text("Save"))])); }
  void _showSearch(BuildContext context, BrowserProvider b) { showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => SearchSheet(browser: b)); }
  Widget _colorDot(BrowserProvider b, Color color) => GestureDetector(onTap: () => b.changeTheme(color), child: Container(width: 30, height: 30, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: b.neonColor == color ? Border.all(color: Colors.white, width: 2) : null)));
  Widget _sectionHeader(String title, BrowserProvider b) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(title, style: TextStyle(color: b.neonColor, fontSize: 12, fontWeight: FontWeight.bold)));
}

class StartPage extends StatelessWidget {
  final BrowserProvider browser;
  final int? tabIndex;
  const StartPage({super.key, required this.browser, this.tabIndex});

  @override Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: browser.neonColor, width: 2),
                ),
                child: Icon(Iconsax.global, size: 60, color: browser.neonColor),
              ),
              const SizedBox(height: 16),
              Text("Luxor", style: TextStyle(color: browser.neonColor, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4)),
              const SizedBox(height: 30),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(30)),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: "Search or enter URL...",
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                    prefixIcon: Icon(Iconsax.search_normal, color: Colors.white38, size: 20),
                  ),
                  onSubmitted: (v) => browser.loadUrl(v, tabIndex)
                )
              ),
              const SizedBox(height: 40),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: browser.speedDials.map((e) => GestureDetector(
                  onTap: () => browser.loadUrl(e.url, tabIndex),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Color(e.colorValue).withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: Color(e.colorValue).withOpacity(0.3))),
                      child: Icon(Icons.language, color: Color(e.colorValue))
                    ),
                    const SizedBox(height: 8),
                    Text(e.label, style: const TextStyle(color: Colors.white54, fontSize: 12))
                  ])
                )).toList()
              )
            ]
          )
        )
      )
    );
  }
}

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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => browser.toggleTabGrid()),
        actions: [
          IconButton(icon: const Icon(Iconsax.document_copy), onPressed: () { browser.toggleSplitMode(maxSplits); browser.toggleTabGrid(); }, tooltip: "Split View"),
          IconButton(icon: const Icon(Icons.add), onPressed: () => browser.addNewTab()),
        ]
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.8),
        itemCount: browser.tabs.length,
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => browser.switchTab(index),
          onLongPress: () => _showTabOptions(context, browser, index),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: index == browser.currentTabIndex ? browser.neonColor : Colors.white10, width: index == browser.currentTabIndex ? 2 : 1)
            ),
            child: Column(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: browser.tabs[index].thumbnail != null
                    ? Image.memory(browser.tabs[index].thumbnail!, fit: BoxFit.cover, width: double.infinity)
                    : Container(
                        color: Colors.black,
                        child: Center(child: Icon(browser.tabs[index].url.contains("luxor://") ? Iconsax.home : Iconsax.global, color: Colors.white24, size: 40)),
                      ),
                )
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
                ),
                child: Row(
                  children: [
                    if (browser.tabs[index].isIncognito) const Icon(Iconsax.eye_slash, size: 12, color: Colors.purple),
                    if (browser.tabs[index].isIncognito) const SizedBox(width: 4),
                    Expanded(child: Text(browser.tabs[index].title, style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    GestureDetector(
                      onTap: () => browser.closeTab(index),
                      child: const Icon(Icons.close, size: 16, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ])
          )
        )
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: browser.neonColor,
        onPressed: () => browser.addNewTab("luxor://home", true),
        child: const Icon(Iconsax.eye_slash, color: Colors.black),
        tooltip: "New Incognito Tab",
      ),
    );
  }

  void _showTabOptions(BuildContext context, BrowserProvider browser, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101010),
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Iconsax.document_copy, color: Colors.white),
              title: const Text("Add to Split View", style: TextStyle(color: Colors.white)),
              onTap: () {
                browser.addTabToSplit(index, maxSplits);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Iconsax.share, color: Colors.white),
              title: const Text("Share URL", style: TextStyle(color: Colors.white)),
              onTap: () {
                Share.share(browser.tabs[index].url);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.red),
              title: const Text("Close Tab", style: TextStyle(color: Colors.red)),
              onTap: () {
                browser.closeTab(index);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AiSidebar extends StatelessWidget { const AiSidebar({super.key}); @override Widget build(BuildContext context) { final ai = Provider.of<AiAgentProvider>(context); final browser = Provider.of<BrowserProvider>(context, listen: false); final ctrl = TextEditingController(); return Column(children: [AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => browser.toggleAiSidebar()), title: Text("Co-Pilot", style: TextStyle(color: browser.neonColor)), actions: [IconButton(icon: const Icon(Icons.copy), onPressed: () async { final c = await Clipboard.getData(Clipboard.kTextPlain); if(c != null && c.text != null) { ai.sendMessage(c.text!, browser); }})]), Expanded(child: ListView.builder(itemCount: ai.messages.length, itemBuilder: (ctx, i) => Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: ai.messages[i].isUser ? Colors.white10 : browser.neonColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text(ai.messages[i].text, style: TextStyle(color: ai.messages[i].isUser ? Colors.white : browser.neonColor))))), Padding(padding: const EdgeInsets.all(16), child: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "Ask something...", hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)), onSubmitted: (v) { ai.sendMessage(v, browser); ctrl.clear(); }))]); } }

class GlassBox extends StatelessWidget { final Widget child; final double borderRadius; final EdgeInsets padding; const GlassBox({super.key, required this.child, this.borderRadius = 20, this.padding = const EdgeInsets.all(0)}); @override Widget build(BuildContext context) { return ClipRRect(borderRadius: BorderRadius.circular(borderRadius), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(padding: padding, decoration: BoxDecoration(color: const Color(0xFF1E1E1E).withOpacity(0.85), borderRadius: BorderRadius.circular(borderRadius), border: Border.all(color: Colors.white.withOpacity(0.1))), child: child))); } }

class SearchSheet extends StatefulWidget {
  final BrowserProvider browser;
  const SearchSheet({super.key, required this.browser});

  @override State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  late TextEditingController _controller;
  List<HistoryItem> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.browser.urlController.text);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final query = _controller.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
    } else {
      setState(() {
        _suggestions = widget.browser.history
          .where((h) => h.url.toLowerCase().contains(query) || h.title.toLowerCase().contains(query))
          .take(5)
          .toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Color(0xFF101010), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(15),
          ),
          child: TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(fontSize: 16, color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search or enter URL...",
              hintStyle: const TextStyle(color: Colors.white38),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              prefixIcon: Icon(Iconsax.search_normal, color: widget.browser.neonColor),
              suffixIcon: _controller.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, color: Colors.white38), onPressed: () { _controller.clear(); setState(() => _suggestions = []); })
                : null,
            ),
            onSubmitted: (v) {
              widget.browser.loadUrl(v);
              Navigator.pop(context);
            }
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _suggestions.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Iconsax.clock, color: Colors.white38, size: 20),
                title: Text(_suggestions[i].title, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_suggestions[i].url, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  widget.browser.loadUrl(_suggestions[i].url);
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 30),
          Text("Quick Access", style: TextStyle(color: widget.browser.neonColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: widget.browser.speedDials.map((s) => ActionChip(
              avatar: Icon(Icons.language, color: Color(s.colorValue), size: 16),
              label: Text(s.label),
              backgroundColor: Colors.white10,
              onPressed: () {
                widget.browser.loadUrl(s.url);
                Navigator.pop(context);
              },
            )).toList(),
          ),
        ],
      ])
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class SourceViewerPage extends StatelessWidget { final String html; const SourceViewerPage({super.key, required this.html}); @override Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.transparent, title: const Text("Source")), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(html, style: const TextStyle(color: Colors.green, fontSize: 11, fontFamily: 'monospace')))); } }

class ScannerPage extends StatelessWidget { const ScannerPage({super.key}); @override Widget build(BuildContext context) { return Scaffold(body: MobileScanner(onDetect: (c) { if (c.barcodes.isNotEmpty) { Provider.of<BrowserProvider>(context, listen: false).loadUrl(c.barcodes.first.rawValue!); Navigator.pop(context); } })); } }

class LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  const LockScreen({super.key, required this.onUnlock});

  @override Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: browser.neonColor, width: 2),
              ),
              child: Icon(Iconsax.lock, size: 60, color: browser.neonColor),
            ),
            const SizedBox(height: 24),
            const Text("Luxor Browser", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Tap to unlock", style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Iconsax.finger_scan),
              label: const Text("Unlock"),
              style: ElevatedButton.styleFrom(
                backgroundColor: browser.neonColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
