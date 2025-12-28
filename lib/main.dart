import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
      title: 'Neon AI Browser',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505), // Deep Black
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FFC2), // Cyberpunk Cyan
          secondary: Color(0xFFD500F9), // Neon Purple
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const BrowserHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Models & Providers (Logic Preserved & Enhanced) ---

class BrowserTab {
  final String id;
  String url;
  String title;
  bool isIncognito;
  InAppWebViewController? controller;
  Color themeColor; // Adaptive color

  BrowserTab({
    required this.id, 
    this.url = "https://www.google.com", 
    this.title = "New Tab",
    this.isIncognito = false,
    this.themeColor = const Color(0xFF00FFC2),
  });
}

class BrowserProvider extends ChangeNotifier {
  List<BrowserTab> tabs = [];
  int currentTabIndex = 0;
  
  // Settings
  bool isDesktopMode = false;
  bool isAdBlockEnabled = true;
  bool isZenMode = false; // Hide UI completely
  
  // State
  double progress = 0;
  bool isLoading = false;
  bool isSecure = true;
  bool isMenuOpen = false;
  TextEditingController urlController = TextEditingController();
  
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  BrowserProvider() {
    _addNewTab();
  }

  BrowserTab get currentTab => tabs[currentTabIndex];

  InAppWebViewSettings getSettings() {
    return InAppWebViewSettings(
      isInspectable: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      cacheEnabled: !currentTab.isIncognito,
      useWideViewPort: true,
      safeBrowsingEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      userAgent: isDesktopMode
          ? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
          : ""
    );
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
    if (isAdBlockEnabled) _injectAdBlocker(controller);
  }

  void updateUrl(String url) {
    currentTab.url = url;
    urlController.text = url;
    isSecure = url.startsWith("https://");
    notifyListeners();
  }

  void loadUrl(String url) {
    if (!url.startsWith("http")) {
      url = url.contains(".") && !url.contains(" ") ? "https://$url" : "https://www.google.com/search?q=$url";
    }
    currentTab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    isMenuOpen = false; // Close menu on navigation
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

  Future<void> takeScreenshot(BuildContext context) async {
    final image = await currentTab.controller?.takeScreenshot();
    if (image != null) {
      // In a real app, save to gallery. Here we just show a snackbar.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Screenshot Captured (Memory)")));
    }
  }

  void _injectAdBlocker(InAppWebViewController controller) {
    String css = ".ad, .ads, [id^='google_ads'], iframe[src*='ads'] { display: none !important; }";
    controller.injectCSSCode(source: css);
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
  List<ChatMessage> messages = [ChatMessage(text: "System Online. Ready to assist.", isUser: false)];
  bool isThinking = false;

  void sendMessage(String text, BrowserProvider browser) async {
    messages.add(ChatMessage(text: text, isUser: true));
    isThinking = true;
    notifyListeners();
    await Future.delayed(const Duration(seconds: 1));
    messages.add(ChatMessage(text: "I've analyzed that for you. Anything else?", isUser: false));
    isThinking = false;
    notifyListeners();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

// --- FUTURISTIC UI WIDGETS ---

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color color;
  final BorderRadius? borderRadius;

  const GlassContainer({
    super.key, 
    required this.child, 
    this.blur = 10, 
    this.opacity = 0.2, 
    this.color = Colors.black,
    this.borderRadius
  });

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
          // 1. WEBVIEW LAYER (Fullscreen)
          Positioned.fill(
            child: InAppWebView(
              key: ValueKey(browser.currentTab.id),
              initialUrlRequest: URLRequest(url: WebUri(browser.currentTab.url)),
              initialSettings: browser.getSettings(),
              onWebViewCreated: (c) => browser.setController(c),
              onLoadStart: (c, url) => browser.updateUrl(url.toString()),
              onLoadStop: (c, url) {
                browser.progress = 1.0;
                browser.updateUrl(url.toString());
              },
              onProgressChanged: (c, p) => browser.progress = p / 100,
              onScrollChanged: (c, x, y) {
                 if (y > 100 && !browser.isZenMode) {
                   // Optional: Auto-hide logic could go here
                 }
              },
            ),
          ),

          // 2. LOADING INDICATOR (Top Line)
          if (browser.progress < 1.0)
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(
                value: browser.progress,
                minHeight: 3,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Colors.transparent,
              ),
            ),

          // 3. FLOATING COMMAND CAPSULE (Bottom)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: browser.isZenMode ? -100 : 30, // Hide in Zen Mode
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Expanded Menu
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: browser.isMenuOpen 
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: GlassContainer(
                          blur: 15,
                          opacity: 0.8,
                          color: const Color(0xFF121212),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                _buildGridMenu(context, browser),
                                const SizedBox(height: 12),
                                _buildTabStrip(browser),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
                ),

                // Main Bar
                GlassContainer(
                  blur: 20,
                  opacity: 0.6,
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        // Menu Trigger
                        IconButton(
                          icon: Icon(browser.isMenuOpen ? Icons.close : Iconsax.category, color: Colors.white),
                          onPressed: browser.toggleMenu,
                        ),
                        
                        // URL / Search Capsule
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showSearchModal(context, browser),
                            child: Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Icon(browser.isSecure ? Iconsax.lock5 : Iconsax.unlock, size: 12, color: browser.isSecure ? Colors.greenAccent : Colors.redAccent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      browser.currentTab.url.replaceFirst("https://", "").replaceFirst("www.", ""),
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // AI ORB (Pulsing)
                        GestureDetector(
                          onTap: () => showModalBottomSheet(
                            context: context, 
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (_) => const AiAgentPanel()
                          ),
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5 * _pulseController.value),
                                      blurRadius: 10 + (10 * _pulseController.value),
                                      spreadRadius: 2 * _pulseController.value,
                                    )
                                  ]
                                ),
                                child: const Icon(Iconsax.magic_star, color: Colors.black, size: 24),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // ZEN MODE TRIGGER (When Hidden)
          if (browser.isZenMode)
            Positioned(
              bottom: 20, right: 20,
              child: FloatingActionButton.small(
                backgroundColor: Colors.white.withOpacity(0.2),
                elevation: 0,
                child: const Icon(Icons.expand_less, color: Colors.white),
                onPressed: browser.toggleZenMode,
              ),
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
      {'icon': Iconsax.monitor, 'label': 'Desktop', 'action': () { browser.isDesktopMode = !browser.isDesktopMode; browser.reload(); }},
      {'icon': Iconsax.camera, 'label': 'Snap', 'action': () { browser.takeScreenshot(context); browser.toggleMenu(); }},
      {'icon': Iconsax.setting, 'label': 'Settings', 'action': () {}},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, mainAxisSpacing: 16, crossAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: item['action'] as VoidCallback,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(item['icon'] as IconData, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 4),
              Text(item['label'] as String, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabStrip(BrowserProvider browser) {
    return SizedBox(
      height: 50,
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
              width: 120,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
                border: isActive ? Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)) : null,
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(child: Text(tab.title, style: TextStyle(color: isActive ? Colors.white : Colors.white54, fontSize: 12), overflow: TextOverflow.ellipsis)),
                  GestureDetector(
                    onTap: () => browser.closeTab(index),
                    child: const Icon(Icons.close, size: 14, color: Colors.white30),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSearchModal(BuildContext context, BrowserProvider browser) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF101010),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.2), blurRadius: 20)]
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              TextField(
                controller: browser.urlController,
                autofocus: true,
                style: const TextStyle(fontSize: 18, color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Search or type URL",
                  hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Iconsax.search_normal, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: const Icon(Iconsax.microphone), 
                    onPressed: () {
                      browser.startVoiceSearch(context);
                      Navigator.pop(context);
                    },
                  ),
                ),
                onSubmitted: (value) {
                  browser.loadUrl(value);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 20),
              const Text("QUICK ACCESS", style: TextStyle(color: Colors.white30, letterSpacing: 1.5, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: [
                  _quickChip(browser, "Google", "google.com", Icons.search),
                  _quickChip(browser, "YouTube", "youtube.com", Iconsax.video),
                  _quickChip(browser, "Twitter", "twitter.com", Iconsax.hashtag),
                  _quickChip(browser, "News", "cnn.com", Iconsax.global),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _quickChip(BrowserProvider b, String label, String url, IconData icon) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: Colors.white),
      label: Text(label),
      backgroundColor: Colors.white.withOpacity(0.1),
      labelStyle: const TextStyle(color: Colors.white),
      side: BorderSide.none,
      onPressed: () {
        b.loadUrl(url);
        Navigator.pop(context);
      },
    );
  }
}

class AiAgentPanel extends StatelessWidget {
  const AiAgentPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Icon(Iconsax.magic_star, size: 40, color: Color(0xFF00FFC2)),
            const SizedBox(height: 10),
            const Text("AI Neural Core", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white12),
            Expanded(
              child: Center(
                child: Text("Waiting for input...", style: TextStyle(color: Colors.white.withOpacity(0.3))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
