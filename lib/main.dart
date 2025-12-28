import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      title: 'Neon AI Browser Ultimate',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: browser.neonColor, // Dynamic Theme
          secondary: Colors.white,
          surface: const Color(0xFF121212),
        ),
      ),
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- PROVIDERS ---

class BrowserTab {
  final String id;
  String url;
  String title;
  bool isIncognito;
  InAppWebViewController? controller;
  Uint8List? thumbnail; // Tab Thumbnail
  BrowserTab({required this.id, this.url = "neon://home", this.title = "Start Page", this.isIncognito = false});
}

class HistoryItem {
  final String url, title;
  HistoryItem({required this.url, required this.title});
  Map<String, dynamic> toJson() => {'url': url, 'title': title};
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(url: json['url'], title: json['title']);
}

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
  
  // Settings
  String searchEngine = "https://www.google.com/search?q=";
  String customUserAgent = "";
  bool isDesktopMode = false;
  bool isAdBlockEnabled = true;
  bool isForceDarkWeb = false;
  bool isJsEnabled = true;
  bool isZenMode = false;
  
  // Theme Engine
  Color neonColor = const Color(0xFF00FFC2); // Default Cyan

  // State
  double progress = 0;
  bool isSecure = true;
  bool isMenuOpen = false;
  bool showFindBar = false;
  bool showAiSidebar = false;
  bool showTabGrid = false; // New: Show Tab Grid
  SslCertificate? sslCertificate;
  
  TextEditingController urlController = TextEditingController();
  TextEditingController findController = TextEditingController();
  stt.SpeechToText _speech = stt.SpeechToText();

  BrowserProvider() {
    _loadData();
    _addNewTab();
  }

  BrowserTab get currentTab => tabs[currentTabIndex];

  InAppWebViewSettings getSettings() {
    return InAppWebViewSettings(
      isInspectable: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      javaScriptEnabled: isJsEnabled,
      cacheEnabled: !currentTab.isIncognito,
      domStorageEnabled: !currentTab.isIncognito,
      useWideViewPort: true,
      safeBrowsingEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      userAgent: customUserAgent.isNotEmpty 
          ? customUserAgent 
          : (isDesktopMode ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" : "")
    );
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    searchEngine = prefs.getString('searchEngine') ?? "https://www.google.com/search?q=";
    isAdBlockEnabled = prefs.getBool('adBlock') ?? true;
    isForceDarkWeb = prefs.getBool('forceDark') ?? false;
    isJsEnabled = prefs.getBool('jsEnabled') ?? true;
    
    // Load Theme
    int? colorValue = prefs.getInt('neonColor');
    if (colorValue != null) neonColor = Color(colorValue);

    final h = prefs.getStringList('history') ?? [];
    history = h.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('searchEngine', searchEngine);
    prefs.setBool('adBlock', isAdBlockEnabled);
    prefs.setBool('forceDark', isForceDarkWeb);
    prefs.setBool('jsEnabled', isJsEnabled);
    prefs.setInt('neonColor', neonColor.value);
    prefs.setStringList('history', history.map((e) => jsonEncode(e.toJson())).toList());
  }

  void changeTheme(Color color) {
    neonColor = color;
    _saveData();
    notifyListeners();
  }

  void _addNewTab([String url = "neon://home", bool incognito = false]) {
    final newTab = BrowserTab(id: const Uuid().v4(), url: url, isIncognito: incognito);
    tabs.add(newTab);
    currentTabIndex = tabs.length - 1;
    showTabGrid = false; // Auto switch to new tab
    _updateState();
    notifyListeners();
  }

  void closeTab(int index) {
    if (tabs.length > 1) {
      tabs.removeAt(index);
      if (currentTabIndex >= tabs.length) currentTabIndex = tabs.length - 1;
      _updateState();
      notifyListeners();
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
      // Capture thumbnail before showing grid
      try {
        currentTab.thumbnail = await currentTab.controller?.takeScreenshot();
      } catch (e) { /* ignore */ }
    }
    showTabGrid = !showTabGrid;
    notifyListeners();
  }

  void _updateState() {
    urlController.text = currentTab.url == "neon://home" ? "" : currentTab.url;
    isSecure = currentTab.url.startsWith("https://");
    progress = 0;
    showFindBar = false;
    sslCertificate = null;
  }

  void setController(InAppWebViewController c) => currentTab.controller = c;

  void updateUrl(String url) {
    currentTab.url = url;
    urlController.text = url == "neon://home" ? "" : url;
    isSecure = url.startsWith("https://");
    notifyListeners();
  }

  void loadUrl(String url) {
    if (url == "home" || url == "neon://home") {
      updateUrl("neon://home");
      return;
    }
    if (!url.startsWith("http")) {
      url = (url.contains(".") && !url.contains(" ")) ? "https://$url" : "$searchEngine$url";
    }
    currentTab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    notifyListeners();
  }

  void toggleMenu() { isMenuOpen = !isMenuOpen; notifyListeners(); }
  void toggleZenMode() { isZenMode = !isZenMode; notifyListeners(); }
  void toggleAiSidebar() { showAiSidebar = !showAiSidebar; notifyListeners(); }

  // --- FEATURES ---
  void findInPage(String text) {
    if (text.isEmpty) { currentTab.controller?.clearMatches(); } 
    else { currentTab.controller?.findAllAsync(find: text); }
  }
  void findNext() => currentTab.controller?.findNext(forward: true);
  void findPrev() => currentTab.controller?.findNext(forward: false);
  void toggleFindBar() { showFindBar = !showFindBar; if (!showFindBar) currentTab.controller?.clearMatches(); notifyListeners(); }

  void toggleReaderMode() {
    String js = """(function(){var p=document.getElementsByTagName('p');var txt='';for(var i=0;i<p.length;i++)txt+='<p>'+p[i].innerHTML+'</p>';document.body.innerHTML='<div style="max-width:800px;margin:0 auto;padding:20px;font-family:sans-serif;line-height:1.6;color:#e0e0e0;background:#121212;">'+txt+'</div>';document.body.style.backgroundColor='#121212';})();""";
    currentTab.controller?.evaluateJavascript(source: js);
    toggleMenu();
  }

  void toggleDesktopMode() async { isDesktopMode = !isDesktopMode; await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void toggleAdBlock() async { isAdBlockEnabled = !isAdBlockEnabled; await _saveData(); reload(); notifyListeners(); }
  void toggleForceDark() async { isForceDarkWeb = !isForceDarkWeb; await _saveData(); reload(); notifyListeners(); }
  void toggleJs() async { isJsEnabled = !isJsEnabled; await _saveData(); await currentTab.controller?.setSettings(settings: getSettings()); reload(); notifyListeners(); }
  void setSearchEngine(String url) { searchEngine = url; _saveData(); notifyListeners(); }
  void clearData() async { await currentTab.controller?.clearCache(); await CookieManager.instance().deleteAllCookies(); history.clear(); await _saveData(); notifyListeners(); }

  void injectScripts(InAppWebViewController c) {
    if (isAdBlockEnabled) { c.evaluateJavascript(source: """(function(){var style=document.createElement('style');style.innerHTML='.ad,.ads,.advertisement,iframe[src*="ads"],[id^="google_ads"]{display:none !important;}';document.head.appendChild(style);})();"""); }
    if (isForceDarkWeb) { c.evaluateJavascript(source: """(function(){var style=document.createElement('style');style.innerHTML='html{filter:invert(1) hue-rotate(180deg) !important;}img,video,iframe,canvas{filter:invert(1) hue-rotate(180deg) !important;}';document.head.appendChild(style);})();"""); }
  }

  void startVoice(BuildContext context) async {
    if (await Permission.microphone.request().isGranted && await _speech.initialize()) {
      _speech.listen(onResult: (r) { if (r.finalResult) loadUrl(r.recognizedWords); });
    }
  }

  void addToHistory(String url, String? title) {
    if (!currentTab.isIncognito && url != "neon://home" && url != "about:blank" && url.isNotEmpty) {
      if (history.isEmpty || history.first.url != url) {
        history.insert(0, HistoryItem(url: url, title: title ?? "Unknown"));
        if (history.length > 50) history.removeLast();
        _saveData();
      }
    }
  }

  Future<void> viewSource(BuildContext context) async {
    final html = await currentTab.controller?.getHtml();
    if (html != null) Navigator.push(context, MaterialPageRoute(builder: (_) => SourceViewerPage(html: html)));
  }

  Future<void> shareScreenshot(BuildContext context) async {
    try {
      final image = await currentTab.controller?.takeScreenshot();
      if (image == null) return;
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/shot_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(image);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) { /* ignore */ }
  }

  void setCustomUA(String ua) async { customUserAgent = ua; await currentTab.controller?.setSettings(settings: getSettings()); currentTab.controller?.reload(); notifyListeners(); }
  void updateSSL(SslCertificate? ssl) { sslCertificate = ssl; notifyListeners(); }
  void goBack() => currentTab.controller?.goBack();
  void goForward() => currentTab.controller?.goForward();
  void reload() => currentTab.controller?.reload();
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [ChatMessage(text: "System Ready.", isUser: false)];
  bool isThinking = false;
  void sendMessage(String text, BrowserProvider b) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true; notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600));
    String resp = "OK.";
    if (text.contains("home")) { b.loadUrl("neon://home"); resp = "Going Home."; }
    else if (text.contains("dark")) { b.toggleForceDark(); resp = "Dark Mode Toggled."; }
    else { resp = "I can navigate or change settings."; }
    messages.add(ChatMessage(text: resp, isUser: false));
    isThinking = false; notifyListeners();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

// --- UI ---

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});
  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> with TickerProviderStateMixin {
  late AnimationController _menuController;
  late Animation<double> _menuScale;
  late PullToRefreshController _pullToRefreshController;

  @override
  void initState() {
    super.initState();
    _menuController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _menuScale = CurvedAnimation(parent: _menuController, curve: Curves.easeOutBack);
    
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: const Color(0xFF00FFC2), backgroundColor: Colors.black),
      onRefresh: () async {
        final b = Provider.of<BrowserProvider>(context, listen: false);
        if (b.currentTab.url != "neon://home") b.reload();
        _pullToRefreshController.endRefreshing();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);
    final devTools = Provider.of<DevToolsProvider>(context);
    
    if (browser.isMenuOpen && _menuController.status != AnimationStatus.completed) {
      _menuController.forward();
    } else if (!browser.isMenuOpen && _menuController.status != AnimationStatus.dismissed) {
      _menuController.reverse();
    }

    final bool isStartPage = browser.currentTab.url == "neon://home";

    // IF TAB GRID IS OPEN, SHOW GRID INSTEAD OF BROWSER
    if (browser.showTabGrid) {
      return TabGridPage(browser: browser);
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: browser.showAiSidebar ? MediaQuery.of(context).size.width * 0.7 : MediaQuery.of(context).size.width,
            child: Column(
              children: [
                Expanded(
                  child: isStartPage 
                  ? StartPage(browser: browser) 
                  : InAppWebView(
                    key: ValueKey(browser.currentTab.id),
                    initialUrlRequest: URLRequest(url: WebUri(browser.currentTab.url)),
                    initialSettings: browser.getSettings(),
                    pullToRefreshController: _pullToRefreshController,
                    onWebViewCreated: (c) => browser.setController(c),
                    onLoadStart: (c, url) => browser.updateUrl(url.toString()),
                    onLoadStop: (c, url) async {
                      browser.progress = 1.0;
                      browser.updateUrl(url.toString());
                      browser.injectScripts(c);
                      browser.addToHistory(url.toString(), await c.getTitle());
                      browser.updateSSL(await c.getCertificate());
                    },
                    onProgressChanged: (c, p) => browser.progress = p / 100,
                    onConsoleMessage: (c, msg) => devTools.addLog(msg.message, msg.messageLevel),
                    onReceivedServerTrustAuthRequest: (c, challenge) async {
                      return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                    },
                  ),
                ),
                if (!browser.isZenMode) const SizedBox(height: 80), 
              ],
            ),
          ),
          
          if (browser.progress < 1.0 && !isStartPage)
            Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(value: browser.progress, minHeight: 2, color: browser.neonColor, backgroundColor: Colors.transparent)),

          // --- AI SIDEBAR ---
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            right: browser.showAiSidebar ? 0 : -300,
            top: 0, bottom: 0,
            width: MediaQuery.of(context).size.width * 0.75,
            child: GlassBox(
              borderRadius: 0,
              padding: const EdgeInsets.only(top: 40),
              child: const AiSidebar(),
            ),
          ),

          // Menu Layer
          Positioned(
            bottom: 90, left: 20, right: 20,
            child: ScaleTransition(
              scale: _menuScale,
              alignment: Alignment.bottomCenter,
              child: GlassBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildGridMenu(context, browser),
                  ],
                ),
              ),
            ),
          ),

          if (browser.showFindBar)
             Positioned(
               bottom: browser.isZenMode ? 20 : 140, left: 20, right: 20,
               child: GlassBox(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [
                 Expanded(child: TextField(controller: browser.findController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Find...", border: InputBorder.none, hintStyle: TextStyle(color: Colors.white30)), onChanged: (v) => browser.findInPage(v))),
                 IconButton(icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white), onPressed: browser.findPrev),
                 IconButton(icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white), onPressed: browser.findNext),
                 IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: browser.toggleFindBar),
               ])),
             ),

          if (!browser.showAiSidebar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: browser.isZenMode ? -100 : 20,
            left: 20, right: 20,
            child: GlassBox(
              borderRadius: 50,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Row(
                children: [
                  _circleBtn(browser.isMenuOpen ? Icons.close : Iconsax.category, () => browser.toggleMenu()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showSearch(context, browser),
                      child: Container(
                        height: 40, padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                        alignment: Alignment.centerLeft,
                        child: Row(children: [
                           GestureDetector(
                             onTap: () => _showSSLCertificate(context, browser),
                             child: Icon(browser.isSecure ? Iconsax.lock5 : Iconsax.unlock, size: 12, color: browser.isSecure ? Colors.green : Colors.red)
                           ),
                           const SizedBox(width: 8),
                           Expanded(child: Text(isStartPage ? "Search or type URL" : browser.currentTab.url.replaceFirst("https://", ""), style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)),
                           // Tab Counter (Triggers Grid)
                           GestureDetector(
                             onTap: () => browser.toggleTabGrid(),
                             child: Container(
                               width: 24, height: 24,
                               alignment: Alignment.center,
                               decoration: BoxDecoration(border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(5)),
                               child: Text("${browser.tabs.length}", style: const TextStyle(fontSize: 10, color: Colors.white)),
                             ),
                           )
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _circleBtn(Iconsax.magic_star, () => browser.toggleAiSidebar(), color: browser.neonColor),
                ],
              ),
            ),
          ),
          
          if (browser.isZenMode)
            Positioned(bottom: 20, right: 20, child: FloatingActionButton.small(backgroundColor: Colors.white10, child: const Icon(Icons.expand_less, color: Colors.white), onPressed: browser.toggleZenMode)),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(50), child: Container(width: 44, height: 44, alignment: Alignment.center, decoration: const BoxDecoration(shape: BoxShape.circle), child: Icon(icon, color: color, size: 22)));
  }

  Widget _buildGridMenu(BuildContext context, BrowserProvider b) {
    return GridView.count(
      shrinkWrap: true, crossAxisCount: 5, mainAxisSpacing: 15, crossAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
      children: [
        _menuItem(Iconsax.arrow_left_2, "Back", b.goBack),
        _menuItem(Iconsax.arrow_right_3, "Fwd", b.goForward),
        _menuItem(Iconsax.refresh, "Reload", b.reload),
        _menuItem(Iconsax.element_plus, "Tabs", () { b.toggleMenu(); b.toggleTabGrid(); }),
        _menuItem(Iconsax.search_status, "Find", () { b.toggleMenu(); b.toggleFindBar(); }),
        _menuItem(Iconsax.monitor, "Desktop", b.toggleDesktopMode, isActive: b.isDesktopMode),
        _menuItem(Iconsax.book_1, "Reader", () { b.toggleReaderMode(); }),
        _menuItem(Iconsax.command, "Console", () { b.toggleMenu(); _showDevConsole(context); }),
        _menuItem(Iconsax.setting, "Settings", () { b.toggleMenu(); _showSettingsModal(context, b); }),
        _menuItem(Iconsax.home, "Home", () { b.loadUrl("neon://home"); b.toggleMenu(); }),
      ],
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isActive ? Provider.of<BrowserProvider>(context).neonColor : Colors.white10, shape: BoxShape.circle), child: Icon(icon, size: 18, color: isActive ? Colors.black : Colors.white)),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70), maxLines: 1),
      ]),
    );
  }

  // --- MODALS ---
  void _showSSLCertificate(BuildContext context, BrowserProvider b) {
    if (b.currentTab.url == "neon://home") return;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Row(children: [Icon(b.isSecure ? Iconsax.lock5 : Iconsax.unlock, color: b.isSecure ? Colors.green : Colors.red), const SizedBox(width: 10), const Text("Security Info", style: TextStyle(color: Colors.white))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Connection is ${b.isSecure ? "Secure" : "Not Secure"}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text("Host: ${Uri.parse(b.currentTab.url).host}", style: const TextStyle(color: Colors.white70)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
    ));
  }

  void _showSettingsModal(BuildContext context, BrowserProvider b) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), isScrollControlled: true, builder: (_) => StatefulBuilder(builder: (ctx, setState) {
      return Container(height: MediaQuery.of(context).size.height * 0.7, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Advanced Settings", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        Expanded(child: ListView(children: [
          _sectionHeader("Theme", b),
          Wrap(spacing: 10, children: [
            _colorDot(b, const Color(0xFF00FFC2)), // Cyan
            _colorDot(b, const Color(0xFFFF0055)), // Neon Red
            _colorDot(b, const Color(0xFFD500F9)), // Purple
            _colorDot(b, const Color(0xFFFFD700)), // Gold
            _colorDot(b, const Color(0xFF00FF00)), // Matrix Green
          ]),
          _sectionHeader("Display", b),
          SwitchListTile(activeColor: b.neonColor, title: const Text("Force Dark Web", style: TextStyle(color: Colors.white)), value: b.isForceDarkWeb, onChanged: (v) { b.toggleForceDark(); setState((){}); }),
          SwitchListTile(activeColor: b.neonColor, title: const Text("Desktop Mode", style: TextStyle(color: Colors.white)), value: b.isDesktopMode, onChanged: (v) { b.toggleDesktopMode(); setState((){}); }),
          _sectionHeader("Security", b),
          SwitchListTile(activeColor: b.neonColor, title: const Text("AdBlocker", style: TextStyle(color: Colors.white)), value: b.isAdBlockEnabled, onChanged: (v) { b.toggleAdBlock(); setState((){}); }),
          SwitchListTile(activeColor: b.neonColor, title: const Text("JavaScript", style: TextStyle(color: Colors.white)), value: b.isJsEnabled, onChanged: (v) { b.toggleJs(); setState((){}); }),
          _sectionHeader("Data", b),
          ListTile(title: const Text("Clear All Data", style: TextStyle(color: Colors.red)), leading: const Icon(Icons.delete, color: Colors.red), onTap: () { b.clearData(); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data Wiped"))); }),
        ])),
      ]));
    }));
  }

  Widget _colorDot(BrowserProvider b, Color color) {
    return GestureDetector(
      onTap: () => b.changeTheme(color),
      child: Container(
        width: 30, height: 30,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: b.neonColor == color ? Border.all(color: Colors.white, width: 2) : null),
      ),
    );
  }

  Widget _sectionHeader(String title, BrowserProvider b) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(title, style: TextStyle(color: b.neonColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)));

  void _showSearch(BuildContext context, BrowserProvider b) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => SearchSheet(browser: b));
  }
  void _showDevConsole(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => const DevConsoleSheet());
  }
}

// --- NEW PAGE: TAB GRID ---

class TabGridPage extends StatelessWidget {
  final BrowserProvider browser;
  const TabGridPage({super.key, required this.browser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Tabs", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => browser._addNewTab()),
          IconButton(icon: const Icon(Icons.close), onPressed: () => browser.toggleTabGrid()),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.7),
        itemCount: browser.tabs.length,
        itemBuilder: (context, index) {
          final tab = browser.tabs[index];
          final bool active = index == browser.currentTabIndex;
          return GestureDetector(
            onTap: () => browser.switchTab(index),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: active ? Border.all(color: browser.neonColor, width: 2) : Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                      ),
                      child: tab.thumbnail != null 
                        ? Image.memory(tab.thumbnail!, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.web, color: Colors.white10))
                        : const Icon(Icons.web, color: Colors.white24, size: 50),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      if (tab.isIncognito) const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Iconsax.mask, size: 12, color: Colors.purple)),
                      Expanded(child: Text(tab.title, style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      GestureDetector(onTap: () => browser.closeTab(index), child: const Icon(Icons.close, size: 16, color: Colors.white54))
                    ]),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ... (Other Classes: AiSidebar, StartPage, etc. - Kept as is)
class AiSidebar extends StatelessWidget {
  const AiSidebar({super.key});
  @override
  Widget build(BuildContext context) {
    final ai = Provider.of<AiAgentProvider>(context);
    final browser = Provider.of<BrowserProvider>(context, listen: false);
    final ctrl = TextEditingController();
    return Column(children: [
      AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => browser.toggleAiSidebar()), title: Text("Neon Co-Pilot", style: TextStyle(fontWeight: FontWeight.bold, color: browser.neonColor))),
      const Divider(color: Colors.white12),
      Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: ai.messages.length, itemBuilder: (ctx, i) { final msg = ai.messages[i]; return Align(alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: msg.isUser ? browser.neonColor.withOpacity(0.2) : Colors.white10, borderRadius: BorderRadius.circular(12)), child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 12)))); })),
      if (ai.isThinking) LinearProgressIndicator(minHeight: 1, color: browser.neonColor),
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "Chat...", filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), suffixIcon: IconButton(icon: Icon(Icons.send, color: browser.neonColor), onPressed: () { ai.sendMessage(ctrl.text, browser); ctrl.clear(); })), onSubmitted: (v) { ai.sendMessage(v, browser); ctrl.clear(); })),
      SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
    ]);
  }
}
class StartPage extends StatelessWidget {
  final BrowserProvider browser;
  const StartPage({super.key, required this.browser});
  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.black, child: Center(child: SingleChildScrollView(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Iconsax.global, size: 80, color: browser.neonColor), const SizedBox(height: 20),
      const Text("NEON BROWSER", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)), const SizedBox(height: 40),
      Container(margin: const EdgeInsets.symmetric(horizontal: 40), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white24)), child: TextField(style: const TextStyle(color: Colors.white), textAlign: TextAlign.center, decoration: const InputDecoration(hintText: "Search or enter URL", hintStyle: TextStyle(color: Colors.white30), border: InputBorder.none, contentPadding: EdgeInsets.all(16)), onSubmitted: (v) => browser.loadUrl(v))),
      const SizedBox(height: 40),
      Wrap(spacing: 20, runSpacing: 20, children: [_speedDial(Iconsax.search_normal, "Google", "google.com", Colors.blue, browser), _speedDial(Iconsax.video, "Youtube", "youtube.com", Colors.red, browser), _speedDial(Iconsax.gram, "Instagram", "instagram.com", Colors.purple, browser), _speedDial(Iconsax.code, "GitHub", "github.com", Colors.white, browser)])
    ]))));
  }
  Widget _speedDial(IconData icon, String label, String url, Color color, BrowserProvider b) {
    return GestureDetector(onTap: () => b.loadUrl(url), child: Column(children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle), child: Icon(icon, color: color, size: 28)), const SizedBox(height: 8), Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))]));
  }
}
class GlassBox extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;
  const GlassBox({super.key, required this.child, this.borderRadius = 20, this.padding = const EdgeInsets.all(0)});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(borderRadius), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), child: Container(padding: padding, decoration: BoxDecoration(color: const Color(0xFF1E1E1E).withOpacity(0.85), borderRadius: BorderRadius.circular(borderRadius), border: Border.all(color: Colors.white.withOpacity(0.1))), child: child)));
  }
}
class SearchSheet extends StatelessWidget {
  final BrowserProvider browser;
  const SearchSheet({super.key, required this.browser});
  @override
  Widget build(BuildContext context) {
    return Container(height: MediaQuery.of(context).size.height * 0.9, padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Color(0xFF101010), borderRadius: BorderRadius.vertical(top: Radius.circular(30))), child: Column(children: [
      TextField(controller: browser.urlController, autofocus: true, style: const TextStyle(fontSize: 16, color: Colors.white), decoration: InputDecoration(hintText: "Search or enter URL", filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none), prefixIcon: const Icon(Icons.search, color: Colors.white54), suffixIcon: IconButton(icon: Icon(Icons.mic, color: browser.neonColor), onPressed: () { browser.startVoice(context); Navigator.pop(context); })), onSubmitted: (v) { browser.loadUrl(v); Navigator.pop(context); }),
    ]));
  }
}
class DevConsoleSheet extends StatelessWidget {
  const DevConsoleSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final logs = Provider.of<DevToolsProvider>(context).consoleLogs;
    final b = Provider.of<BrowserProvider>(context);
    return Container(height: 400, padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFF0D0D0D)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("DevTools Console", style: TextStyle(color: b.neonColor, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => Provider.of<DevToolsProvider>(context, listen: false).clearLogs())]),
      const Divider(color: Colors.white24),
      Expanded(child: ListView.builder(itemCount: logs.length, itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(logs[i], style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 10))))),
    ]));
  }
}
class SourceViewerPage extends StatelessWidget {
  final String html;
  const SourceViewerPage({super.key, required this.html});
  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0D0D0D), appBar: AppBar(backgroundColor: Colors.transparent, title: const Text("Source Code", style: TextStyle(fontSize: 14))), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(html, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 10))));
  }
}
