import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    return MaterialApp(
      title: 'Neon AI Browser Ultra',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFC2), // Cyan
          secondary: Color(0xFFFF0055), // Neon Red
          surface: Color(0xFF121212),
        ),
      ),
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- PROVIDERS & LOGIC ---

class BrowserTab {
  final String id;
  String url;
  String title;
  bool isIncognito;
  InAppWebViewController? controller;
  BrowserTab({required this.id, this.url = "https://www.google.com", this.title = "New Tab", this.isIncognito = false});
}

class HistoryItem {
  final String url, title;
  HistoryItem({required this.url, required this.title});
  Map<String, dynamic> toJson() => {'url': url, 'title': title};
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(url: json['url'], title: json['title']);
}

class DevToolsProvider extends ChangeNotifier {
  List<String> consoleLogs = [];
  bool isDevMode = false;

  void addLog(String message, ConsoleMessageLevel level) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final levelName = level.toString().split('.').last.toUpperCase();
    consoleLogs.add("[$timestamp] $levelName: $message");
    notifyListeners();
  }

  void clearLogs() {
    consoleLogs.clear();
    notifyListeners();
  }
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
  bool isZenMode = false;
  
  // State
  double progress = 0;
  bool isSecure = true;
  bool isMenuOpen = false; // Toggles the quick menu
  TextEditingController urlController = TextEditingController();
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
    final h = prefs.getStringList('history') ?? [];
    history = h.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    notifyListeners();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('searchEngine', searchEngine);
    prefs.setBool('adBlock', isAdBlockEnabled);
    prefs.setStringList('history', history.map((e) => jsonEncode(e.toJson())).toList());
  }

  void _addNewTab([String url = "https://www.google.com", bool incognito = false]) {
    final newTab = BrowserTab(id: const Uuid().v4(), url: url, isIncognito: incognito);
    tabs.add(newTab);
    currentTabIndex = tabs.length - 1;
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
    _updateState();
    notifyListeners();
  }

  void _updateState() {
    urlController.text = currentTab.url;
    isSecure = currentTab.url.startsWith("https://");
    progress = 0;
  }

  void setController(InAppWebViewController c) => currentTab.controller = c;

  void updateUrl(String url) {
    currentTab.url = url;
    urlController.text = url;
    isSecure = url.startsWith("https://");
    notifyListeners();
  }

  void loadUrl(String url) {
    if (!url.startsWith("http")) {
      url = (url.contains(".") && !url.contains(" ")) ? "https://$url" : "$searchEngine$url";
    }
    currentTab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    notifyListeners();
  }

  void toggleMenu() {
    isMenuOpen = !isMenuOpen;
    notifyListeners();
  }

  void toggleZenMode() {
    isZenMode = !isZenMode;
    notifyListeners();
  }

  void toggleDesktopMode() async {
    isDesktopMode = !isDesktopMode;
    await currentTab.controller?.setSettings(settings: getSettings());
    currentTab.controller?.reload();
    notifyListeners();
  }

  void setCustomUA(String ua) async {
    customUserAgent = ua;
    await currentTab.controller?.setSettings(settings: getSettings());
    currentTab.controller?.reload();
    notifyListeners();
  }

  Future<void> viewSource(BuildContext context) async {
    final html = await currentTab.controller?.getHtml();
    if (html != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SourceViewerPage(html: html)));
    }
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

  void injectScripts(InAppWebViewController c) {
    if (isAdBlockEnabled) {
      c.evaluateJavascript(source: """
        (function() {
          var style = document.createElement('style');
          style.innerHTML = '.ad, .ads, .advertisement, iframe[src*="ads"], [id^="google_ads"] { display: none !important; }';
          document.head.appendChild(style);
        })();
      """);
    }
  }

  void startVoice(BuildContext context) async {
    if (await Permission.microphone.request().isGranted && await _speech.initialize()) {
      _speech.listen(onResult: (r) {
        if (r.finalResult) loadUrl(r.recognizedWords);
      });
    }
  }

  void addToHistory(String url, String? title) {
    if (!currentTab.isIncognito && url != "about:blank" && url.isNotEmpty) {
      if (history.isEmpty || history.first.url != url) {
        history.insert(0, HistoryItem(url: url, title: title ?? "Unknown"));
        if (history.length > 50) history.removeLast();
        _saveData();
      }
    }
  }

  void goBack() => currentTab.controller?.goBack();
  void goForward() => currentTab.controller?.goForward();
  void reload() => currentTab.controller?.reload();
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [ChatMessage(text: "Ready.", isUser: false)];
  bool isThinking = false;
  void sendMessage(String text, BrowserProvider b) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true; notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600)); // Fast response
    String resp = "OK.";
    if (text.contains("desktop")) { b.toggleDesktopMode(); resp = "Desktop Mode Toggled."; }
    else if (text.contains("source")) { resp = "Use the Tools menu to view source."; }
    else { resp = "I can control settings or search for you."; }
    messages.add(ChatMessage(text: resp, isUser: false));
    isThinking = false; notifyListeners();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

// --- PAGES & WIDGETS ---

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});
  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> with TickerProviderStateMixin {
  late AnimationController _menuController;
  late Animation<double> _menuScale;

  @override
  void initState() {
    super.initState();
    _menuController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _menuScale = CurvedAnimation(parent: _menuController, curve: Curves.easeOutBack);
  }

  @override
  Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);
    final devTools = Provider.of<DevToolsProvider>(context);
    
    // Sync Animation with Provider State
    if (browser.isMenuOpen && _menuController.status != AnimationStatus.completed) {
      _menuController.forward();
    } else if (!browser.isMenuOpen && _menuController.status != AnimationStatus.dismissed) {
      _menuController.reverse();
    }

    return Scaffold(
      resizeToAvoidBottomInset: false, // Prevent webview resize on keyboard
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. WebView
          Column(
            children: [
              Expanded(
                child: InAppWebView(
                  key: ValueKey(browser.currentTab.id),
                  initialUrlRequest: URLRequest(url: WebUri(browser.currentTab.url)),
                  initialSettings: browser.getSettings(),
                  onWebViewCreated: (c) => browser.setController(c),
                  onLoadStart: (c, url) => browser.updateUrl(url.toString()),
                  onLoadStop: (c, url) async {
                    browser.progress = 1.0;
                    browser.updateUrl(url.toString());
                    browser.injectScripts(c);
                    browser.addToHistory(url.toString(), await c.getTitle());
                  },
                  onProgressChanged: (c, p) => browser.progress = p / 100,
                  onConsoleMessage: (c, msg) => devTools.addLog(msg.message, msg.messageLevel),
                ),
              ),
              // Space for Floating Bar (so web content isn't covered if scrolled to bottom)
              if (!browser.isZenMode) const SizedBox(height: 80), 
            ],
          ),

          // 2. Loading Bar (Top)
          if (browser.progress < 1.0)
            Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(value: browser.progress, minHeight: 2, color: const Color(0xFF00FFC2), backgroundColor: Colors.transparent)),

          // 3. Floating Menu (Separate Layer for Performance)
          Positioned(
            bottom: 90, // Just above the capsule
            left: 20, right: 20,
            child: ScaleTransition(
              scale: _menuScale,
              alignment: Alignment.bottomCenter,
              child: GlassBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildGridMenu(context, browser),
                    const Divider(color: Colors.white10),
                    _buildTabStrip(browser),
                  ],
                ),
              ),
            ),
          ),

          // 4. Control Capsule (Always Visible, Static Position)
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
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(browser.isSecure ? Iconsax.lock5 : Iconsax.unlock, size: 12, color: browser.isSecure ? Colors.green : Colors.red),
                            const SizedBox(width: 8),
                            Expanded(child: Text(browser.currentTab.url.replaceFirst("https://", ""), style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _circleBtn(Iconsax.magic_star, () => _showAI(context), color: const Color(0xFF00FFC2)),
                ],
              ),
            ),
          ),
          
          // 5. Zen Mode Trigger
          if (browser.isZenMode)
            Positioned(bottom: 20, right: 20, child: FloatingActionButton.small(backgroundColor: Colors.white10, child: const Icon(Icons.expand_less, color: Colors.white), onPressed: browser.toggleZenMode)),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        width: 44, height: 44,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _buildGridMenu(BuildContext context, BrowserProvider b) {
    return GridView.count(
      shrinkWrap: true, crossAxisCount: 5, mainAxisSpacing: 15, crossAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _menuItem(Iconsax.arrow_left_2, "Back", b.goBack),
        _menuItem(Iconsax.arrow_right_3, "Fwd", b.goForward),
        _menuItem(Iconsax.refresh, "Reload", b.reload),
        _menuItem(Iconsax.add, "New", () { b._addNewTab(); b.toggleMenu(); }),
        _menuItem(Iconsax.mask, "Private", () { b._addNewTab("https://google.com", true); b.toggleMenu(); }),
        _menuItem(Iconsax.monitor, "Desktop", b.toggleDesktopMode, isActive: b.isDesktopMode),
        _menuItem(Iconsax.code, "Source", () { b.toggleMenu(); b.viewSource(context); }),
        _menuItem(Iconsax.command, "Console", () { b.toggleMenu(); _showDevConsole(context); }),
        _menuItem(Iconsax.mobile, "UA", () { b.toggleMenu(); _showUAPicker(context, b); }),
        _menuItem(Iconsax.setting, "Settings", () { }),
      ],
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: isActive ? const Color(0xFF00FFC2) : Colors.white10, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: isActive ? Colors.black : Colors.white),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70), maxLines: 1),
        ],
      ),
    );
  }

  Widget _buildTabStrip(BrowserProvider b) {
    return Container(
      height: 40, margin: const EdgeInsets.only(bottom: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal, itemCount: b.tabs.length, padding: const EdgeInsets.symmetric(horizontal: 10),
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () => b.switchTab(i),
          child: Container(
            margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: i == b.currentTabIndex ? const Color(0xFF00FFC2).withOpacity(0.2) : Colors.white10, borderRadius: BorderRadius.circular(10), border: i == b.currentTabIndex ? Border.all(color: const Color(0xFF00FFC2), width: 0.5) : null),
            child: Row(children: [
              Text(b.tabs[i].title, style: TextStyle(fontSize: 10, color: i == b.currentTabIndex ? Colors.white : Colors.white54), maxLines: 1),
              const SizedBox(width: 4),
              GestureDetector(onTap: () => b.closeTab(i), child: const Icon(Icons.close, size: 10, color: Colors.white30))
            ]),
          ),
        ),
      ),
    );
  }

  void _showSearch(BuildContext context, BrowserProvider b) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => SearchSheet(browser: b));
  }

  void _showAI(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => const AiSheet());
  }

  void _showDevConsole(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => const DevConsoleSheet());
  }

  void _showUAPicker(BuildContext context, BrowserProvider b) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF222222),
      title: const Text("Custom User Agent", style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text("iPhone 14", style: TextStyle(color: Colors.white)), onTap: () { b.setCustomUA("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"); Navigator.pop(context); }),
        ListTile(title: const Text("Windows Chrome", style: TextStyle(color: Colors.white)), onTap: () { b.setCustomUA("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"); Navigator.pop(context); }),
        ListTile(title: const Text("Google Bot", style: TextStyle(color: Colors.white)), onTap: () { b.setCustomUA("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"); Navigator.pop(context); }),
      ]),
    ));
  }
}

class GlassBox extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;
  const GlassBox({super.key, required this.child, this.borderRadius = 20, this.padding = const EdgeInsets.all(0)});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(color: const Color(0xFF1E1E1E).withOpacity(0.85), borderRadius: BorderRadius.circular(borderRadius), border: Border.all(color: Colors.white.withOpacity(0.1))),
          child: child,
        ),
      ),
    );
  }
}

class SearchSheet extends StatelessWidget {
  final BrowserProvider browser;
  const SearchSheet({super.key, required this.browser});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Color(0xFF101010), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(children: [
        TextField(
          controller: browser.urlController, autofocus: true, style: const TextStyle(fontSize: 16, color: Colors.white),
          decoration: InputDecoration(
            hintText: "Search or enter URL", filled: true, fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            suffixIcon: IconButton(icon: const Icon(Icons.mic, color: Color(0xFF00FFC2)), onPressed: () { browser.startVoice(context); Navigator.pop(context); }),
          ),
          onSubmitted: (v) { browser.loadUrl(v); Navigator.pop(context); },
        ),
      ]),
    );
  }
}

class AiSheet extends StatelessWidget {
  const AiSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final ai = Provider.of<AiAgentProvider>(context);
    final browser = Provider.of<BrowserProvider>(context, listen: false);
    final ctrl = TextEditingController();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Color(0xFF101010), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Iconsax.magic_star, color: Color(0xFF00FFC2), size: 40),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ListView.builder(itemCount: ai.messages.length, itemBuilder: (c, i) => Text(ai.messages[i].text, style: TextStyle(color: ai.messages[i].isUser ? const Color(0xFF00FFC2) : Colors.white))),
        ),
        TextField(
          controller: ctrl, style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(hintText: "Ask AI...", filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)),
          onSubmitted: (v) { ai.sendMessage(v, browser); ctrl.clear(); },
        )
      ]),
    );
  }
}

class DevConsoleSheet extends StatelessWidget {
  const DevConsoleSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final logs = Provider.of<DevToolsProvider>(context).consoleLogs;
    return Container(
      height: 400, padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Color(0xFF0D0D0D)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("DevTools Console", style: TextStyle(color: Color(0xFF00FFC2), fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => Provider.of<DevToolsProvider>(context, listen: false).clearLogs()),
        ]),
        const Divider(color: Colors.white24),
        Expanded(child: ListView.builder(
          itemCount: logs.length,
          itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(logs[i], style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 10))),
        )),
      ]),
    );
  }
}

class SourceViewerPage extends StatelessWidget {
  final String html;
  const SourceViewerPage({super.key, required this.html});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text("Source Code", style: TextStyle(fontSize: 14))),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(html, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 10))),
    );
  }
}
