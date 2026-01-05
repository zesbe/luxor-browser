# 🏛️ Luxor Browser

<div align="center">

![Luxor Browser](https://img.shields.io/badge/Luxor-Browser-FFD700?style=for-the-badge&logo=safari&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.2+-02569B?style=for-the-badge&logo=flutter)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Linux-3DDC84?style=for-the-badge&logo=android)

**A Luxury, Privacy-Focused Mobile Browser with AI Integration**

[Features](#-features) • [Installation](#-installation) • [Usage](#-usage) • [Contributing](#-contributing) • [License](#-license)

</div>

---

## ✨ Features

### 🔐 Privacy & Security
- **DNS over HTTPS (DoH)** - Secure DNS queries with multiple providers (Cloudflare, Google, Quad9, AdGuard, NextDNS)
- **Tracking Protection** - Built-in content blockers to prevent tracking
- **Ad Blocker** - Advanced ad blocking technology
- **Biometric Lock** - Secure your browser with fingerprint/face unlock
- **Incognito Mode** - Private browsing with no history tracking
- **Popup Blocker** - Automatic popup blocking
- **HTTPS-Only** - Prefer secure connections

### 🎨 Modern Interface
- **Split Tab View** - View 2-4 tabs simultaneously (adaptive to screen size)
- **Customizable Themes** - Multiple color schemes (Gold, Cyan, Pink, Blue, Purple)
- **Dark Mode** - Force dark mode on any website
- **Reader Mode** - Distraction-free reading experience
- **Zen Mode** - Minimalist browsing interface
- **Game Mode** - Full-screen landscape mode with wake lock

### 🌐 Advanced Browsing
- **User Agent Switcher** - Switch between Android, iOS, Desktop, and custom UAs
- **Site-Specific Settings** - Configure JavaScript, images, cookies per domain
- **Page Info** - Detailed information about websites (SSL, load time, page size)
- **Desktop Mode** - Request desktop versions of websites
- **Translation** - Built-in page translation
- **QR Code Scanner** - Scan QR codes to navigate to URLs
- **Voice Search** - Search using voice commands
- **Text-to-Speech** - Listen to web content

### 📚 Organization
- **Bookmarks** - Save and organize your favorite sites with folders
- **Reading List** - Save articles to read later
- **History** - Browse your browsing history with search
- **Speed Dials** - Quick access to frequently visited sites (editable)
- **Downloads** - Built-in download manager with progress tracking

### 🤖 AI Integration
- **AI Sidebar** - Chat with AI assistant while browsing
- **Voice Commands** - Control browser with natural language
- **Smart Suggestions** - AI-powered search and navigation suggestions

### 🛠️ Developer Tools
- **Console** - View JavaScript console logs
- **Network Monitor** - Track network requests
- **User Scripts** - Inject custom JavaScript
- **Inspect Mode** - Debug web content

### 🎯 Additional Features
- **Multi-Tab Management** - Efficient tab switching and organization
- **Find in Page** - Quick text search with navigation
- **Page Archiving** - Save pages for offline viewing
- **Screenshot Sharing** - Capture and share screenshots
- **Print Support** - Print web pages
- **Custom Search Engines** - Google, DuckDuckGo, Bing, Brave
- **Data Export/Import** - Backup and restore your data
- **Pull to Refresh** - Refresh pages with pull gesture

---

## 📱 Screenshots

<div align="center">
<img src="screenshots/home.png" width="200"/> <img src="screenshots/browser.png" width="200"/> <img src="screenshots/split-view.png" width="200"/> <img src="screenshots/settings.png" width="200"/>
</div>

---

## 🚀 Installation

### Prerequisites
- Flutter SDK 3.2 or higher
- Android SDK (API level 21+) for Android builds
- Linux build dependencies for Linux builds
- Git

### Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/zesbe/luxor-browser.git
   cd luxor-browser
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   # Android
   flutter run

   # Linux Desktop
   flutter run -d linux
   ```

4. **Build APK (Android)**
   ```bash
   flutter build apk --release
   ```
   The APK will be available at `build/app/outputs/flutter-apk/app-release.apk`

5. **Build for Linux (Mint/Ubuntu/Debian)**
   ```bash
   # Install dependencies first
   sudo apt-get install -y ninja-build libgtk-3-dev libwebkit2gtk-4.1-dev

   # Enable Linux desktop
   flutter config --enable-linux-desktop

   # Build
   flutter build linux --release
   ```
   The binary will be available at `build/linux/x64/release/bundle/luxor_browser`

### Download Pre-built Releases

Download the latest release from [GitHub Releases](https://github.com/zesbe/luxor-browser/releases)

#### Linux Installation (Mint/Ubuntu/Debian)
```bash
# Download and extract
tar -xzf luxor-browser-linux-x64.tar.gz

# Install runtime dependencies
sudo apt install libgtk-3-0 libwebkit2gtk-4.1-0

# Run
./luxor_browser
```

---

## 📖 Usage

### Basic Navigation
- **Search/Navigate**: Tap the search bar and enter a URL or search query
- **Back/Forward**: Use navigation buttons in the bottom toolbar
- **Refresh**: Pull down on the page or tap the refresh button
- **Home**: Tap the home button to return to the start page

### Tab Management
- **New Tab**: Tap the tab counter and select "New Tab"
- **Switch Tabs**: Tap the tab counter to view all tabs
- **Close Tab**: Swipe tab left or tap the X button
- **Incognito**: Long-press the tab counter for incognito mode

### Split View
1. Tap the split icon in the bottom toolbar
2. Select tabs to view side-by-side
3. Tap on a split to make it active
4. Exit by tapping the exit split button

### User Agent Switching
1. Open Settings
2. Navigate to "User Agent"
3. Choose from presets or enter custom UA
4. Changes apply immediately

### Page Info
- Long-press the lock icon in URL bar
- View SSL certificate, page size, load time
- Access site-specific settings

### Bookmarks
- Tap the bookmark icon to save current page
- Long-press for edit/delete options
- Organize with folders

---

## 🏗️ Architecture

```
lib/
├── main.dart              # Entry point & core logic
├── models/                # Data models (planned)
│   ├── browser_tab.dart
│   ├── bookmark.dart
│   └── settings.dart
├── providers/             # State management (planned)
│   ├── browser_provider.dart
│   └── ai_provider.dart
└── widgets/               # Reusable widgets (planned)
    ├── glass_box.dart
    └── search_sheet.dart
```

### Key Technologies
- **Flutter/Dart** - Cross-platform framework
- **flutter_inappwebview** - Advanced WebView with Chromium engine
- **Provider** - State management
- **SharedPreferences** - Local data persistence
- **mobile_scanner** - QR code scanning
- **local_auth** - Biometric authentication
- **speech_to_text** - Voice recognition

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Style
- Follow Dart style guide
- Use meaningful variable names
- Comment complex logic
- Write tests for new features

---

## 🗺️ Roadmap

- [x] Basic browsing functionality
- [x] Tab management with split view
- [x] Privacy features (DoH, tracking protection)
- [x] User Agent switcher
- [x] Download manager
- [x] AI integration
- [x] Sync across devices (Google Account)
- [x] Password Manager with Import/Export
- [x] Linux Desktop version (Mint/Ubuntu/Debian)
- [ ] PWA support
- [ ] Extension system
- [ ] iOS support
- [ ] Windows Desktop version
- [ ] macOS Desktop version

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- InAppWebView contributors
- Icon pack by Iconsax
- All open-source dependencies

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/zesbe/ai-browser-flutter/issues)
- **Discussions**: [GitHub Discussions](https://github.com/zesbe/ai-browser-flutter/discussions)
- **Email**: support@luxorbrowser.com

---

<div align="center">

**Made with ❤️ by the Luxor Team**

⭐ Star this repository if you find it helpful!

</div>
