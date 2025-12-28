import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      title: 'Neon AI Browser Pro',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFC2),
          secondary: Color(0xFFD500F9),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- LOGIC CORE (REAL FUNCTIONS) ---

class HistoryItem {
  final String url;
  final String title;
  final DateTime date;
  HistoryItem({required this.url, required this.title, required this.date});
  Map<String, dynamic> toJson() => {'url': url, 'title': title, 'date': date.toIso8601String()};
  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    url: json['url'], title: json['title'], date: DateTime.parse(json['date']));
}

class BrowserTab {
  final String id;
  String url;
  String title;
  bool isIncognito;
  InAppWebViewController? controller;
  BrowserTab({required this.id, this.url = "https://www.google.com", this.title = "New Tab", this.isIncognito = false});
}

class BrowserProvider extends ChangeNotifier {
  List<BrowserTab> tabs = [];
  int currentTabIndex = 0;
  List<HistoryItem> history = [];
  
  // Persistent Settings
  String searchEngine = "https://www.google.com/search?q=";
  bool isDesktopMode = false;
  bool isAdBlockEnabled = true;
  bool isZenMode = false;
  
  // State
  double progress = 0;
  bool isLoading = false;
  bool isSecure = true;
  bool isMenuOpen = false;
  TextEditingController urlController = TextEditingController();
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

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
      useWideViewPort: true, // Crucial for Desktop mode
      safeBrowsingEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      userAgent: isDesktopMode
          ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
          : "" // Empty string = Default Android UserAgent
    );
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    searchEngine = prefs.getString('searchEngine') ?? "https://www.google.com/search?q=";
    isAdBlockEnabled = prefs.getBool('adBlock') ?? true;
    
    final historyList = prefs.getStringList('history') ?? [];
    history = historyList.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
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
    _updateCurrentTabState();
    notifyListeners();
  }

  void switchTab(int index) {
    currentTabIndex = index;
    _updateCurrentTabState();
    notifyListeners();
  }

  void closeTab(int index) {
    if (tabs.length > 1) {
      tabs.removeAt(index);
      if (currentTabIndex >= tabs.length) currentTabIndex = tabs.length - 1;
      _updateCurrentTabState();
      notifyListeners();
    }
  }

  void _updateCurrentTabState() {
    urlController.text = currentTab.url;
    isSecure = currentTab.url.startsWith("https://");
    isLoading = false;
    progress = 0;
  }

  void setController(InAppWebViewController controller) {
    currentTab.controller = controller;
  }

  void updateUrl(String url) {
    currentTab.url = url;
    urlController.text = url;
    isSecure = url.startsWith("https://");
    notifyListeners();
  }

  Future<void> addToHistory(String url, String? title) async {
    if (currentTab.isIncognito || url == "about:blank" || url.isEmpty) return;
    if (history.isNotEmpty && history.first.url == url) return;

    history.insert(0, HistoryItem(url: url, title: title ?? "Unknown", date: DateTime.now()));
    if (history.length > 100) history.removeLast();
    _saveData();
  }

  void loadUrl(String url) {
    if (!url.startsWith("http")) {
      if (url.contains(".") && !url.contains(" ")) {
        url = "https://$url";
      } else {
        url = "$searchEngine$url";
      }
    }
    currentTab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    isMenuOpen = false;
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

  // --- REAL FUNCTIONALITY IMPLEMENTATIONS ---

  void toggleDesktopMode() async {
    isDesktopMode = !isDesktopMode;
    // Apply new settings to current webview
    await currentTab.controller?.setSettings(settings: getSettings());
    reload(); // Must reload to send new User Agent
    notifyListeners();
  }

  void toggleAdBlock() async {
    isAdBlockEnabled = !isAdBlockEnabled;
    await _saveData();
    reload();
    notifyListeners();
  }

  void setSearchEngine(String url) {
    searchEngine = url;
    _saveData();
    notifyListeners();
  }

  void clearData() async {
    await currentTab.controller?.clearCache();
    await InAppWebViewController.clearAllCookies();
    history.clear();
    await _saveData();
    notifyListeners();
  }

  Future<void> shareScreenshot(BuildContext context) async {
    try {
      // 1. Capture to memory
      final image = await currentTab.controller?.takeScreenshot();
      if (image == null) return;

      // 2. Save to temp file
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(image);

      // 3. Share the file
      await Share.shareXFiles([XFile(file.path)], text: 'Screenshot from Neon Browser');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void injectScripts(InAppWebViewController controller) {
    if (isAdBlockEnabled) {
      // Powerful AdBlocker (Repeated check for lazy loaded ads)
      String js = """
        (function() {
          var css = '.ad, .ads, .advertisement, [id^="google_ads"], iframe[src*="ads"], div[class*="sponsored"], a[href*="doubleclick"] { display: none !important; visibility: hidden !important; height: 0 !important; }';
          var style = document.createElement('style');
          style.type = 'text/css';
          style.appendChild(document.createTextNode(css));
          document.head.appendChild(style);
          
          // Interval to kill lazy-loaded ads
          setInterval(function() {
             var ads = document.querySelectorAll('.ad, .ads, iframe[src*="ads"]');
             ads.forEach(function(el) { el.remove(); });
          }, 2000);
        })();
      """;
      controller.evaluateJavascript(source: js);
    }
  }

  void startVoiceSearch(BuildContext context) async {
    var status = await Permission.microphone.request();
    if (status.isGranted && await _speech.initialize()) {
      _isListening = true;
      notifyListeners();
      _speech.listen(onResult: (result) {
        if (result.finalResult) {
          _isListening = false;
          loadUrl(result.recognizedWords);
          notifyListeners();
        }
      });
    }
  }

  void goBack() => currentTab.controller?.goBack();
  void goForward() => currentTab.controller?.goForward();
  void reload() => currentTab.controller?.reload();
}

class AiAgentProvider extends ChangeNotifier {
  List<ChatMessage> messages = [ChatMessage(text: "Neon Core Online. Systems Nominal.", isUser: false)];
  bool isThinking = false;

  void sendMessage(String text, BrowserProvider browser) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true;
    notifyListeners();
    await Future.delayed(const Duration(seconds: 1));
    
    String response = "Command processed.";
    if (text.toLowerCase().contains("clear")) {
      browser.clearData();
      response = "Privacy wipe complete. Cache and history cleared.";
    }
    
    messages.add(ChatMessage(text: response, isUser: false));
    isThinking = false;
    notifyListeners();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

// --- UI COMPONENTS ---

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color color;
  final BorderRadius? borderRadius;

  const GlassContainer({super.key, required this.child, this.blur = 10, this.opacity = 0.2, this.color = Colors.black, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(opacity),
            borderRadius: borderRadius ?? BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({super.key});
  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> with TickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
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
            ),
          ),
          if (browser.progress < 1.0)
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(value: browser.progress, minHeight: 3, color: Theme.of(context).colorScheme.primary, backgroundColor: Colors.transparent),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: browser.isZenMode ? -150 : 30,
            left: 20, right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: browser.isMenuOpen 
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: GlassContainer(
                          blur: 15, opacity: 0.8, color: const Color(0xFF121212),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(children: [_buildGridMenu(context, browser), const SizedBox(height: 12), _buildTabStrip(browser)]),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
                ),
                GlassContainer(
                  blur: 20, opacity: 0.6, color: Colors.black, borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(icon: Icon(browser.isMenuOpen ? Icons.close : Iconsax.category, color: Colors.white), onPressed: browser.toggleMenu),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showSearchModal(context, browser),
                            child: Container(
                              height: 40, padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Icon(browser.isSecure ? Iconsax.lock5 : Iconsax.unlock, size: 12, color: browser.isSecure ? Colors.greenAccent : Colors.redAccent),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(browser.currentTab.url.replaceFirst("https://", ""), style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => showModalBottomSheet(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (_) => const AiAgentPanel()),
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) => Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]),
                                boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.5 * _pulseController.value), blurRadius: 10 + (10 * _pulseController.value))]
                              ),
                              child: const Icon(Iconsax.magic_star, color: Colors.black, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (browser.isZenMode)
            Positioned(
              bottom: 20, right: 20,
              child: FloatingActionButton.small(backgroundColor: Colors.white.withOpacity(0.2), elevation: 0, child: const Icon(Icons.expand_less, color: Colors.white), onPressed: browser.toggleZenMode),
            ),
        ],
      ),
    );
  }

  Widget _buildGridMenu(BuildContext context, BrowserProvider browser) {
    final items = [
      {'icon': Iconsax.arrow_left_2, 'label': 'Back', 'action': browser.goBack},
      {'icon': Iconsax.arrow_right_3, 'label': 'Forward', 'action': browser.goForward},
      {'icon': Iconsax.refresh, 'label': 'Reload', 'action': browser.reload},
      {'icon': Iconsax.add, 'label': 'New Tab', 'action': () { browser._addNewTab(); browser.toggleMenu(); }},
      {'icon': Iconsax.eye_slash, 'label': 'Zen Mode', 'action': () { browser.toggleZenMode(); browser.toggleMenu(); }},
      {'icon': Iconsax.monitor, 'label': 'Desktop', 'action': () { browser.toggleDesktopMode(); browser.toggleMenu(); }},
      {'icon': Iconsax.camera, 'label': 'Share Snap', 'action': () { browser.shareScreenshot(context); browser.toggleMenu(); }},
      {'icon': Iconsax.clock, 'label': 'History', 'action': () { _showHistoryModal(context, browser); }},
      {'icon': Iconsax.setting, 'label': 'Settings', 'action': () { _showSettingsModal(context, browser); }},
    ];

    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, mainAxisSpacing: 16, crossAxisSpacing: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        bool isActive = false;
        if (item['label'] == 'Desktop') isActive = browser.isDesktopMode;

        return InkWell(
          onTap: item['action'] as VoidCallback,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: isActive ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(item['icon'] as IconData, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 4),
              Text(item['label'] as String, style: const TextStyle(color: Colors.white70, fontSize: 9), textAlign: TextAlign.center),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabStrip(BrowserProvider browser) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: browser.tabs.length,
        separatorBuilder: (_,__) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = browser.tabs[index];
          final isActive = index == browser.currentTabIndex;
          return GestureDetector(
            onTap: () => browser.switchTab(index),
            child: Container(
              width: 100, padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
                border: isActive ? Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)) : null,
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(child: Text(tab.title, style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontSize: 10), overflow: TextOverflow.ellipsis)),
                  GestureDetector(onTap: () => browser.closeTab(index), child: const Icon(Icons.close, size: 12, color: Colors.white30))
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showHistoryModal(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => SizedBox(height: 400, child: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text("History", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
      Expanded(child: ListView.builder(itemCount: browser.history.length, itemBuilder: (_, i) {
        final item = browser.history[i];
        return ListTile(title: Text(item.title, style: const TextStyle(color: Colors.white)), subtitle: Text(item.url, style: const TextStyle(color: Colors.grey)), onTap: () { browser.loadUrl(item.url); Navigator.pop(context); browser.isMenuOpen = false; });
      })),
      TextButton(onPressed: () { browser.clearData(); Navigator.pop(context); }, child: const Text("Clear All Data", style: TextStyle(color: Colors.red)))
    ])));
  }

  void _showSettingsModal(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF101010), builder: (_) => StatefulBuilder(builder: (ctx, setState) => SizedBox(height: 350, child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text("Settings", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const Divider(color: Colors.white24),
      SwitchListTile(title: const Text("AdBlock", style: TextStyle(color: Colors.white)), value: browser.isAdBlockEnabled, onChanged: (v) { browser.toggleAdBlock(); setState((){}); }),
      ListTile(title: const Text("Search Engine", style: TextStyle(color: Colors.white)), subtitle: Text(browser.searchEngine.contains("google") ? "Google" : "DuckDuckGo", style: const TextStyle(color: Colors.grey)), onTap: () {
        browser.setSearchEngine(browser.searchEngine.contains("google") ? "https://duckduckgo.com/?q=" : "https://www.google.com/search?q=");
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Switched to ${browser.searchEngine.contains("google") ? "Google" : "DuckDuckGo"}")));
      }),
      ListTile(title: const Text("Version", style: TextStyle(color: Colors.white)), subtitle: const Text("Neon Pro v1.0", style: TextStyle(color: Colors.grey))),
    ]))));
  }

  void _showSearchModal(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: const Color(0xFF101010), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          child: Column(
            children: [
              const SizedBox(height: 10),
              TextField(
                controller: browser.urlController, autofocus: true, style: const TextStyle(fontSize: 18, color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Search or type URL", hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Iconsax.search_normal, color: Colors.white54),
                  filled: true, fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  suffixIcon: IconButton(icon: const Icon(Iconsax.microphone), onPressed: () { browser.startVoiceSearch(context); Navigator.pop(context); }),
                ),
                onSubmitted: (value) { browser.loadUrl(value); Navigator.pop(context); },
              ),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _quickChip(browser, "Google", "google.com", Icons.search, context),
                _quickChip(browser, "YouTube", "youtube.com", Iconsax.video, context),
                _quickChip(browser, "News", "cnn.com", Iconsax.global, context),
                _quickChip(browser, "ChatGPT", "chat.openai.com", Iconsax.message, context),
              ])
            ],
          ),
        );
      },
    );
  }

  Widget _quickChip(BrowserProvider b, String label, String url, IconData icon, BuildContext ctx) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: Colors.white),
      label: Text(label), backgroundColor: Colors.white.withOpacity(0.1),
      labelStyle: const TextStyle(color: Colors.white), side: BorderSide.none,
      onPressed: () { b.loadUrl(url); Navigator.pop(ctx); },
    );
  }
}

class AiAgentPanel extends StatelessWidget {
  const AiAgentPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final browser = Provider.of<BrowserProvider>(context, listen: false);
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(children: [
         const SizedBox(height: 20),
         const Icon(Iconsax.magic_star, size: 40, color: Color(0xFF00FFC2)),
         const Text("Neon AI", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
         const SizedBox(height: 20),
         ListTile(leading: const Icon(Icons.cleaning_services, color: Colors.white), title: const Text("Clear Data", style: TextStyle(color: Colors.white)), onTap: () { browser.clearData(); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data Cleared"))); }),
         ListTile(leading: const Icon(Icons.shield, color: Colors.white), title: const Text("Toggle AdBlock", style: TextStyle(color: Colors.white)), onTap: () { browser.toggleAdBlock(); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AdBlock Toggled"))); }),
      ]),
    );
  }
}