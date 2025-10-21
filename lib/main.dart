/*
 * App Launcher
 * 
 * Simple Android app launcher with TV support
 * 
 * Author: Moe Jayyusi
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:async';
import 'dart:io';

void main() {
  runApp(const AppLauncher());
}

class AppLauncher extends StatelessWidget {
  const AppLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Launcher',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LauncherHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LauncherHomePage extends StatefulWidget {
  const LauncherHomePage({super.key});

  @override
  State<LauncherHomePage> createState() => _LauncherHomePageState();
}

class _LauncherHomePageState extends State<LauncherHomePage>
    with WidgetsBindingObserver {
  List<AppInfo> _installedApps = [];
  String? _selectedAppPackage;
  bool _isLoading = true;
  bool _hasSelectedApp = false;
  int _focusedIndex = 0;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  // Focus nodes for buttons
  final FocusNode _changeSelectionFocus = FocusNode();
  final FocusNode _launchNowFocus = FocusNode();
  final FocusNode _settingsFocus = FocusNode();
  final FocusNode _cancelFocus = FocusNode();
  final FocusNode _toggleFocus = FocusNode();
  final FocusNode _countdownFocus = FocusNode();
  // Whether the apps grid currently has focus (controls highlight)
  bool _gridActive = true;
  // Grid settings for app selection view
  final ItemScrollController _itemScrollController = ItemScrollController();
  int _focusedButtonIndex =
      0; // 0 = Change Selection, 1 = Launch Now, 2 = Settings
  int _focusedAppIndex = 0; // For app selection view
  // Countdown timer variables
  bool _isCountingDown = false;
  int _countdownSeconds = 10;
  Timer? _countdownTimer;
  bool _isFlashing = false;
  bool _showSystemApps = false;
  // Exit confirmation
  bool _showExitConfirmation = false;
  // TV detection
  bool? _isTVDeviceCached;
  bool _isTV = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Show loading screen immediately
    setState(() {
      _isLoading = true;
    });

    // Load data asynchronously
    _loadData();

    // Set up method channel for back button handling
    _setupMethodChannel();

    // Ensure focus is available for TV remote navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _setupMethodChannel() {
    const platform = MethodChannel('launcher_exit');
    platform.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onBackPressed':
          _handleBack();
          break;
      }
    });
  }

  Future<void> _loadData() async {
    await _loadSelectedApp();
    await _loadInstalledApps();
    _isTV = await _isTVDevice();

    // Always start countdown when an app is selected and not already counting
    if (_hasSelectedApp && !_isCountingDown) {
      _startCountdown();
    }
  }

  // Removed lifecycle-based countdown cancellation to ensure countdown runs consistently

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _focusNode.dispose();
    _scrollController.dispose();
    _changeSelectionFocus.dispose();
    _launchNowFocus.dispose();
    _settingsFocus.dispose();
    _cancelFocus.dispose();
    _toggleFocus.dispose();
    _countdownFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSelectedApp() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedPackage = prefs.getString('selected_app_package');

    if (selectedPackage != null) {
      setState(() {
        _selectedAppPackage = selectedPackage;
        _hasSelectedApp = true;
      });

      // NEVER show countdown automatically - only show when user explicitly requests it
      // This prevents countdown from showing when navigating back to the launcher
    }
  }

  Future<void> _loadInstalledApps() async {
    try {
      List<AppInfo> apps;

      if (!_showSystemApps) {
        // Toggle OFF: Use simple, efficient query for user-installed apps only
        print('Loading user-installed apps only (simple query)...');
        apps = await InstalledApps.getInstalledApps(true, true);
        print('User-installed apps found: ${apps.length} apps');
      } else {
        // Toggle ON: Use the full InstalledApps class with all filtering logic
        print('Loading all apps with full filtering logic...');
        apps = await InstalledApps.getInstalledApps(false, true);
        print('All apps found: ${apps.length} apps');

        // Apply all the existing filtering logic for built-in apps
        print('Before filtering: ${apps.length} apps');
      }

      List<AppInfo> filteredApps;

      if (!_showSystemApps) {
        // Toggle OFF: Simple filtering - just remove launcher and empty names
        print('Applying simple filtering for user-installed apps...');
        filteredApps = apps.where((app) {
          // Only exclude the launcher itself and empty names
          if (app.name.isEmpty ||
              app.packageName == 'com.example.applauncher') {
            return false;
          }
          print('Keeping user-installed app: ${app.name} (${app.packageName})');
          return true;
        }).toList();
      } else {
        // Toggle ON: Use full filtering logic for built-in apps
        print('Applying built-in apps filtering logic...');
        filteredApps = apps.where((app) {
          // Always exclude the launcher itself and empty names
          if (app.name.isEmpty ||
              app.packageName == 'com.example.applauncher') {
            return false;
          }

          // Always filter out non-app packages (system services)
          if (_isNonAppPackage(app)) {
            print(
              'Filtering out non-app package: ${app.name} (${app.packageName})',
            );
            return false;
          }

          // When showing built-in apps, show user-installed + built-in apps
          bool isBuiltIn = _isBuiltInApp(app);
          if (isBuiltIn) {
            print('Showing built-in app: ${app.name} (${app.packageName})');
          } else {
            print(
              'Showing user-installed app: ${app.name} (${app.packageName})',
            );
          }
          return true;
        }).toList();
      }

      // Sort apps: Tawkit apps first, then user-installed apps, then built-in apps
      filteredApps.sort((a, b) {
        // 1. Tawkit apps always at the top
        bool aIsTawkit = _isTawkitApp(a);
        bool bIsTawkit = _isTawkitApp(b);
        if (aIsTawkit && !bIsTawkit) return -1;
        if (!aIsTawkit && bIsTawkit) return 1;
        if (aIsTawkit && bIsTawkit) return a.name.compareTo(b.name);

        // 2. When built-in apps are shown, user-installed apps come first
        if (_showSystemApps) {
          bool aIsBuiltIn = _isBuiltInApp(a);
          bool bIsBuiltIn = _isBuiltInApp(b);
          if (!aIsBuiltIn && bIsBuiltIn) return -1;
          if (aIsBuiltIn && !bIsBuiltIn) return 1;
        }

        // 3. Alphabetical order within each category
        return a.name.compareTo(b.name);
      });

      print('After filtering: ${filteredApps.length} apps');
      print('Built-in apps toggle state: $_showSystemApps');

      setState(() {
        _installedApps = filteredApps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('Failed to load installed apps: $e');
    }
  }

  bool _isBuiltInApp(AppInfo app) {
    // Google Pixel Launcher approach: Check if app has system package prefixes
    // System apps = apps with com.android.* or com.google.android.* packages
    // This is the dynamic approach used by Android launchers

    // Check for Android system apps
    if (app.packageName.startsWith('com.android.') ||
        app.packageName.startsWith('android.') ||
        app.packageName == 'android') {
      // Android System
      return true;
    }

    // Check for Google system apps
    if (app.packageName.startsWith('com.google.android.') ||
        app.packageName.startsWith('com.google.mainline.')) {
      return true;
    }

    // Check for manufacturer system apps
    if (app.packageName.startsWith('com.samsung.') ||
        app.packageName.startsWith('com.lge.') ||
        app.packageName.startsWith('com.sec.') ||
        app.packageName.startsWith('com.huawei.') ||
        app.packageName.startsWith('com.xiaomi.') ||
        app.packageName.startsWith('com.oneplus.') ||
        app.packageName.startsWith('com.sony.') ||
        app.packageName.startsWith('com.motorola.') ||
        app.packageName.startsWith('com.qualcomm.') ||
        app.packageName.startsWith('com.mediatek.')) {
      return true;
    }

    return false;
  }

  bool _isTawkitApp(AppInfo app) {
    // Check if app is from net.tawkit package (should always be at top)
    return app.packageName.startsWith('net.tawkit');
  }

  bool _isNonAppPackage(AppInfo app) {
    // Google Pixel Launcher approach: Apps without launcher intents are non-app packages
    // Since we can't check for launcher intent directly, we filter by checking if the
    // InstalledApps API already filtered them out (it only returns launchable apps)
    // So we just need to filter out the obvious system services based on package patterns

    // Filter out system internal packages
    if (app.packageName.startsWith('com.android.internal.') ||
        app.packageName.startsWith('com.android.systemui.') ||
        app.packageName.startsWith('com.android.providers.') ||
        app.packageName.startsWith('com.android.server.') ||
        app.packageName.startsWith('com.google.android.ext.') ||
        app.packageName.startsWith('com.google.android.overlay.') ||
        app.packageName.startsWith('com.google.mainline.') ||
        app.packageName.contains('.auto_generated_')) {
      return true;
    }

    // Filter out packages with empty names (system services)
    if (app.name.isEmpty) {
      return true;
    }

    return false;
  }

  Future<void> _launchSelectedApp() async {
    if (_selectedAppPackage == null) return;

    // Cancel any running countdown and hide the countdown UI
    _cancelCountdown();

    // Add a small delay to ensure countdown UI is hidden before launching
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      // First check if the app is still installed
      final isInstalled = await InstalledApps.isAppInstalled(
        _selectedAppPackage!,
      );
      if (isInstalled == false) {
        _showErrorDialog('Selected app is no longer installed');
        // Clear the selection if app is no longer installed
        await _clearSelection();
        return;
      }

      // Use InstalledApps.startApp which is the proper way to launch apps on Android
      final launched = await InstalledApps.startApp(_selectedAppPackage!);
      if (launched == true) {
        // Wait a moment for the target app to fully start
        await Future.delayed(const Duration(milliseconds: 500));

        // Self-kill the launcher app after successful launch
        // This frees memory and ensures the target app gets full system resources
        exit(0);
      } else {
        _showErrorDialog(
          'Cannot launch selected app. The app may not be available.',
        );
      }
    } catch (e) {
      _showErrorDialog('Failed to launch app: $e');
    }
  }

  Future<void> _selectApp(AppInfo app) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_app_package', app.packageName);

    setState(() {
      _selectedAppPackage = app.packageName;
      _hasSelectedApp = true;
    });
  }

  Future<void> _clearSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_app_package');

    setState(() {
      _selectedAppPackage = null;
      _hasSelectedApp = false;
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSystemApps() async {
    setState(() {
      _showSystemApps = !_showSystemApps;
      // Show loading indicator when toggling ON (loading all apps)
      if (_showSystemApps) {
        _isLoading = true;
      }
    });

    // Reload apps with new filter
    await _loadInstalledApps();

    // Debug information
    print('Built-in apps toggle: $_showSystemApps');
    print('Total apps found: ${_installedApps.length}');
    if (_installedApps.isNotEmpty) {
      print(
        'First few apps: ${_installedApps.take(3).map((app) => app.name).toList()}',
      );
    } else {
      print('No apps found! This might indicate a filtering issue.');
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Handle TV remote navigation
      final orientation = MediaQuery.of(context).orientation;
      final isLandscape = ((orientation == Orientation.landscape) && !_isTV);

      switch (event.logicalKey) {
        // Navigation keys
        case LogicalKeyboardKey.arrowUp:
          if (isLandscape) {
            _navigateRight(); // Up becomes Right in landscape
          } else {
            _navigateUp();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          if (isLandscape) {
            _navigateLeft(); // Down becomes Left in landscape
          } else {
            _navigateDown();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowLeft:
          if (isLandscape) {
            _navigateUp(); // Left becomes Up in landscape
          } else {
            _navigateLeft();
          }
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          if (isLandscape) {
            _navigateDown(); // Right becomes Down in landscape
          } else {
            _navigateRight();
          }
          return KeyEventResult.handled;

        // Selection keys
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.space:
          if (_hasSelectedApp) {
            // Handle button selection in selected app view
            _handleButtonSelection();
          } else {
            // Handle app selection or toggle
            if (_focusedAppIndex < _installedApps.length) {
              _selectCurrentApp();
            } else {
              // Toggle system apps
              _toggleSystemApps();
            }
          }
          return KeyEventResult.handled;

        // Back/Cancel keys
        case LogicalKeyboardKey.escape:
        case LogicalKeyboardKey.backspace:
          _handleBack();
          return KeyEventResult.handled;

        // TV remote specific keys
        case LogicalKeyboardKey.home:
          _handleHome();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.contextMenu:
          _handleMenu();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyS:
          // Toggle system apps with 'S' key
          _toggleSystemApps();
          return KeyEventResult.handled;

        // Number keys for quick selection (0-9)
        case LogicalKeyboardKey.digit0:
        case LogicalKeyboardKey.digit1:
        case LogicalKeyboardKey.digit2:
        case LogicalKeyboardKey.digit3:
        case LogicalKeyboardKey.digit4:
        case LogicalKeyboardKey.digit5:
        case LogicalKeyboardKey.digit6:
        case LogicalKeyboardKey.digit7:
        case LogicalKeyboardKey.digit8:
        case LogicalKeyboardKey.digit9:
          _handleNumberKey(event.logicalKey);
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _navigateUp() {
    if (_hasSelectedApp) {
      // Selected app view: up navigation depends on orientation
      final orientation = MediaQuery.of(context).orientation;
      final isLandscape = orientation == Orientation.landscape;

      if (isLandscape) {
        // Landscape: all buttons in one row, up/down disabled
        return;
      } else {
        // Portrait: up moves from Launch Now (2) to Settings (1)
        if (_focusedButtonIndex == 2) {
          setState(() {
            _focusedButtonIndex = 1;
          });
          _updateButtonFocus();
        }
      }
    } else {
      // Grid navigation: move up by one row
      final orientation = MediaQuery.of(context).orientation;
      final cols = orientation == Orientation.landscape ? 6 : 4;

      if (_focusedAppIndex >= cols) {
        // Move up one row
        setState(() {
          _focusedAppIndex = _focusedAppIndex - cols;
          _focusedIndex = _focusedAppIndex;
          _gridActive = true;
        });
        _scrollToFocusedItem();
      } else {
        // At top row, move to toggle
        _focusNode.unfocus();
        setState(() {
          _gridActive = false;
          _focusedIndex = -1;
          _focusedAppIndex = -1;
        });
        _toggleFocus.requestFocus();
      }
    }
  }

  void _navigateDown() {
    if (_hasSelectedApp) {
      // Selected app view: down navigation depends on orientation
      final orientation = MediaQuery.of(context).orientation;
      final isLandscape = orientation == Orientation.landscape;

      if (isLandscape) {
        // Landscape: all buttons in one row, up/down disabled
        return;
      } else {
        // Portrait: down from top row buttons goes to Launch Now (2)
        if (_focusedButtonIndex == 0 || _focusedButtonIndex == 1) {
          setState(() {
            _focusedButtonIndex = 2;
          });
          _updateButtonFocus();
        }
      }
    } else {
      // Grid navigation: move down by one row
      final orientation = MediaQuery.of(context).orientation;
      final cols = orientation == Orientation.landscape ? 6 : 4;

      if (!_gridActive) {
        // Coming from toggle, start at first item
        _toggleFocus.unfocus();
        setState(() {
          _focusedAppIndex = 0;
          _focusedIndex = 0;
          _gridActive = true;
        });
        _focusNode.requestFocus();
        _scrollToFocusedItem();
        return;
      }

      final nextIndex = _focusedAppIndex + cols;
      if (nextIndex < _installedApps.length) {
        setState(() {
          _focusedAppIndex = nextIndex;
          _focusedIndex = nextIndex;
          _gridActive = true;
        });
        _scrollToFocusedItem();
      } else {
        // Stay at current position when at bottom
        setState(() {
          _focusedAppIndex = _focusedAppIndex.clamp(
            0,
            _installedApps.length - 1,
          );
          _focusedIndex = _focusedAppIndex;
          _gridActive = true;
        });
      }
    }
  }

  void _navigateLeft() {
    if (_hasSelectedApp) {
      // Selected app view: left navigation depends on orientation
      final orientation = MediaQuery.of(context).orientation;
      final isLandscape = orientation == Orientation.landscape;

      if (isLandscape) {
        // Landscape: all buttons in one row, left moves to previous button
        if (_focusedButtonIndex > 0) {
          setState(() {
            _focusedButtonIndex--;
          });
          _updateButtonFocus();
        }
      } else {
        // Portrait: left moves from Settings (1) to Change Selection (0)
        if (_focusedButtonIndex == 1) {
          setState(() {
            _focusedButtonIndex = 0;
          });
          _updateButtonFocus();
        }
      }
    } else {
      // Grid navigation: move left by one
      final orientation = MediaQuery.of(context).orientation;
      final cols = orientation == Orientation.landscape ? 6 : 4;

      final atFirstCol = _focusedAppIndex % cols == 0;
      final atFirstRow = _focusedAppIndex < cols;

      if (atFirstCol && atFirstRow) {
        // At first column of first row, move to toggle
        _focusNode.unfocus();
        setState(() {
          _gridActive = false;
          _focusedIndex = -1;
          _focusedAppIndex = -1;
        });
        _toggleFocus.requestFocus();
      } else if (atFirstCol) {
        // At first column of other rows, move to last item of previous row
        final prevRowLastIndex = _focusedAppIndex - 1;
        setState(() {
          _focusedAppIndex = prevRowLastIndex;
          _focusedIndex = prevRowLastIndex;
          _gridActive = true;
        });
        _scrollToFocusedItem();
      } else {
        setState(() {
          _focusedAppIndex = (_focusedAppIndex - 1).clamp(
            0,
            _installedApps.length - 1,
          );
          _focusedIndex = _focusedAppIndex;
          _gridActive = true;
        });
        _scrollToFocusedItem();
      }
    }
  }

  void _navigateRight() {
    if (_hasSelectedApp) {
      // Selected app view: right navigation depends on orientation
      final orientation = MediaQuery.of(context).orientation;
      final isLandscape = orientation == Orientation.landscape;

      if (isLandscape) {
        // Landscape: all buttons in one row, right moves to next button
        if (_focusedButtonIndex < 2) {
          setState(() {
            _focusedButtonIndex++;
          });
          _updateButtonFocus();
        }
      } else {
        // Portrait: right moves from Change Selection (0) to Settings (1)
        if (_focusedButtonIndex == 0) {
          setState(() {
            _focusedButtonIndex = 1;
          });
          _updateButtonFocus();
        }
      }
    } else {
      // Grid navigation: move right by one
      if (!_gridActive) {
        // Coming from toggle, start at first item
        _toggleFocus.unfocus();
        setState(() {
          _focusedAppIndex = 0;
          _focusedIndex = 0;
          _gridActive = true;
        });
        _focusNode.requestFocus();
        _scrollToFocusedItem();
        return;
      }

      setState(() {
        _focusedAppIndex = (_focusedAppIndex + 1).clamp(
          0,
          _installedApps.length - 1,
        );
        _focusedIndex = _focusedAppIndex;
        _gridActive = true;
      });
      _scrollToFocusedItem();
    }
  }

  void _updateButtonFocus() {
    // Update focus based on current button index
    // Order: 1. Change Selection, 2. Settings, 3. Launch Now
    switch (_focusedButtonIndex) {
      case 0:
        _changeSelectionFocus.requestFocus();
        break;
      case 1:
        _settingsFocus.requestFocus();
        break;
      case 2:
        _launchNowFocus.requestFocus();
        break;
    }
  }

  void _handleButtonSelection() {
    // Handle button selection based on current focus
    // Order: 1. Change Selection, 2. Settings, 3. Launch Now
    switch (_focusedButtonIndex) {
      case 0:
        _clearSelection();
        break;
      case 1:
        _openSystemSettings();
        break;
      case 2:
        _startCountdownForLaunch();
        break;
    }
  }

  void _handleBack() {
    if (_showExitConfirmation) {
      // Second back press - actually exit
      SystemNavigator.pop();
    } else if (_hasSelectedApp) {
      // First back press in selected app view - clear selection
      _clearSelection();
    } else {
      // First back press in app selection view - show exit confirmation
      setState(() {
        _showExitConfirmation = true;
      });

      // Auto-hide confirmation after 3 seconds
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showExitConfirmation = false;
          });
        }
      });
    }
  }

  void _scrollToFocusedItem() {
    if (_itemScrollController.isAttached && _focusedIndex >= 0) {
      // Calculate which row contains the focused item
      final orientation = MediaQuery.of(context).orientation;
      final crossAxis = orientation == Orientation.landscape ? 6 : 4;
      final rowIndex = _focusedIndex ~/ crossAxis;

      _itemScrollController.scrollTo(
        index: rowIndex,
        duration: const Duration(milliseconds: 300),
        alignment: 0.0, // 0.0 aligns the item to the top
      );
    }
  }

  void _selectCurrentApp() {
    if (_installedApps.isNotEmpty && _focusedIndex < _installedApps.length) {
      _selectApp(_installedApps[_focusedIndex]);
    }
  }

  void _handleHome() {
    // Home key should only show the launcher app, do nothing
    // This prevents the launcher from launching other apps when Home is pressed
  }

  void _handleMenu() {
    // Show app info or options
    if (_installedApps.isNotEmpty && _focusedIndex < _installedApps.length) {
      _showAppInfo(_installedApps[_focusedIndex]);
    }
  }

  void _handleNumberKey(LogicalKeyboardKey key) {
    final number = int.tryParse(key.keyLabel);
    if (number != null && number < _installedApps.length) {
      setState(() {
        _focusedIndex = number;
      });
      _scrollToFocusedItem();
    }
  }

  void _startCountdown() {
    // Cancel any existing countdown first
    _cancelCountdown();

    setState(() {
      _isCountingDown = true;
      _countdownSeconds = 10;
    });

    // Request focus for countdown screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _countdownFocus.requestFocus();
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _countdownSeconds--;
      });

      if (_countdownSeconds <= 0) {
        timer.cancel();
        _launchSelectedApp();
      }
    });

    // Start flashing animation
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || !_isCountingDown) {
        timer.cancel();
        return;
      }

      setState(() {
        _isFlashing = !_isFlashing;
      });
    });
  }

  void _startCountdownForLaunch() {
    // Only start countdown if we have a selected app
    if (_selectedAppPackage != null && _hasSelectedApp) {
      _startCountdown();
    }
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _isCountingDown = false;
      _countdownSeconds = 10;
      _isFlashing = false;
    });
  }

  void _showAppInfo(AppInfo app) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(app.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Package: ${app.packageName}'),
            if (app.versionName.isNotEmpty) Text('Version: ${app.versionName}'),
            if (app.versionCode > 0) Text('Version Code: ${app.versionCode}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _selectApp(app);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            SafeArea(
              child: _isLoading
                  ? _buildLoadingView()
                  : _isCountingDown
                      ? _buildCountdownView()
                      : _hasSelectedApp
                          ? _buildSelectedAppView()
                          : _buildAppSelectionView(),
            ),
            // Exit confirmation overlay
            if (_showExitConfirmation)
              Container(
                color: Colors.black.withOpacity(0.8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.warning,
                          color: Colors.white,
                          size: 50,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Exit App?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Press Back again to exit\nor wait 3 seconds to cancel',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Press Back to Exit',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: Colors.blue, width: 3),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.blue,
                      strokeWidth: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  _showSystemApps
                      ? 'Loading Built-in Apps...'
                      : 'Loading App Launcher...',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _showSystemApps
                      ? 'Loading all apps including built-in system apps...'
                      : 'Please wait while we load your apps',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownView() {
    final selectedApp = _installedApps.firstWhere(
      (app) => app.packageName == _selectedAppPackage,
      orElse: () => AppInfo(
        packageName: _selectedAppPackage ?? '',
        name: 'Unknown App',
        versionName: '',
        versionCode: 0,
        icon: null,
        builtWith: BuiltWith.flutter,
        installedTimestamp: 0,
      ),
    );

    return Focus(
      focusNode: _countdownFocus,
      autofocus: true,
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          // Any key press cancels the countdown
          _cancelCountdown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;
      },
      child: Stack(
        children: [
          // Main content
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 20,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Adaptive sizing based on screen dimensions
                    Builder(
                      builder: (context) {
                        final size = MediaQuery.of(context).size;
                        final shortestSide = size.shortestSide;
                        final scale = (shortestSide / 720).clamp(0.9, 1.6);
                        final iconSize = 160.0 * scale; // Bigger app icon
                        final iconRadius = 32.0 * scale;
                        final iconBorder = 4.0 * scale;
                        final appNameFont = 24.0 * scale;
                        final buttonFont = 28.0 * scale; // Bigger button text

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // App icon
                            Container(
                              width: iconSize,
                              height: iconSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(iconRadius),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: iconBorder,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  iconRadius - 2.0,
                                ),
                                child: selectedApp.icon != null
                                    ? Image.memory(
                                        selectedApp.icon!,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.blue.withOpacity(
                                              0.2,
                                            ),
                                            child: const Icon(
                                              Icons.apps,
                                              color: Colors.blue,
                                            ),
                                          );
                                        },
                                      )
                                    : Container(
                                        color: Colors.blue.withOpacity(0.2),
                                        child: const Icon(
                                          Icons.apps,
                                          color: Colors.blue,
                                        ),
                                      ),
                              ),
                            ),
                            SizedBox(height: 10.0 * scale),
                            // App name
                            Text(
                              selectedApp.name,
                              style: TextStyle(
                                fontSize: appNameFont,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 40.0 * scale),
                            // Cancel button - compact
                            Focus(
                              focusNode: _cancelFocus,
                              autofocus: true,
                              child: Builder(
                                builder: (BuildContext context) {
                                  final isFocused = Focus.of(context).hasFocus;
                                  return ElevatedButton.icon(
                                    onPressed: _cancelCountdown,
                                    icon: Icon(Icons.cancel,
                                        size: buttonFont * 0.8),
                                    label: Text(
                                      'Cancel',
                                      style:
                                          TextStyle(fontSize: buttonFont * 0.9),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isFocused
                                          ? Colors.red.shade700
                                          : Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: buttonFont * 1.2,
                                        vertical: buttonFont * 0.3,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      minimumSize: Size(0, 0),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Countdown timer in top-right corner
          Positioned(
            top: 10,
            right: 10,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _countdownSeconds <= 5
                    ? (_isFlashing
                        ? Colors.red.withOpacity(0.8)
                        : Colors.red.withOpacity(0.3))
                    : _countdownSeconds <= 8
                        ? (_isFlashing
                            ? Colors.yellow.withOpacity(0.8)
                            : Colors.yellow.withOpacity(0.3))
                        : (_isFlashing
                            ? Colors.green.withOpacity(0.8)
                            : Colors.green.withOpacity(0.3)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _countdownSeconds <= 5
                      ? Colors.red
                      : _countdownSeconds <= 8
                          ? Colors.yellow
                          : Colors.green,
                  width: 3,
                ),
              ),
              child: Center(
                child: Text(
                  '$_countdownSeconds',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedAppView() {
    final selectedApp = _installedApps.firstWhere(
      (app) => app.packageName == _selectedAppPackage,
      orElse: () => AppInfo(
        packageName: _selectedAppPackage ?? '',
        name: 'Unknown App',
        versionName: '',
        versionCode: 0,
        icon: null,
        builtWith: BuiltWith.flutter,
        installedTimestamp: 0,
      ),
    );

    // Initialize button focus when view is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateButtonFocus();
    });

    return Builder(
      builder: (context) {
        final orientation = MediaQuery.of(context).orientation;
        final isLandscape = orientation == Orientation.landscape;

        return Align(
          alignment: Alignment.center,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // App icon
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: selectedApp.icon != null
                            ? Image.memory(
                                selectedApp.icon!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.blue.withOpacity(0.2),
                                    child: const Icon(
                                      Icons.apps,
                                      size: 50,
                                      color: Colors.blue,
                                    ),
                                  );
                                },
                              )
                            : Container(
                                color: Colors.blue.withOpacity(0.2),
                                child: const Icon(
                                  Icons.apps,
                                  size: 50,
                                  color: Colors.blue,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Success indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Selected App',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      selectedApp.name,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: const Text(
                        'This app will launch automatically on startup.',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (context) {
                        final orientation = MediaQuery.of(context).orientation;
                        final isLandscape =
                            orientation == Orientation.landscape;

                        if (isLandscape) {
                          // Landscape: All 3 buttons in one row
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Focus(
                                focusNode: _changeSelectionFocus,
                                child: Builder(
                                  builder: (BuildContext context) {
                                    final isFocused = Focus.of(
                                      context,
                                    ).hasFocus;
                                    return ElevatedButton.icon(
                                      onPressed: _clearSelection,
                                      icon: const Icon(Icons.edit),
                                      label: const Text('Change Selection'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isFocused
                                            ? Colors.orange.shade700
                                            : Colors.orange,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        side: isFocused
                                            ? const BorderSide(
                                                color: Colors.white,
                                                width: 3,
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Focus(
                                focusNode: _settingsFocus,
                                child: Builder(
                                  builder: (BuildContext context) {
                                    final isFocused = Focus.of(
                                      context,
                                    ).hasFocus;
                                    return ElevatedButton.icon(
                                      onPressed: _openSystemSettings,
                                      icon: const Icon(Icons.settings),
                                      label: const Text('Settings'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isFocused
                                            ? Colors.blue.shade700
                                            : Colors.blue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        side: isFocused
                                            ? const BorderSide(
                                                color: Colors.white,
                                                width: 3,
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Focus(
                                focusNode: _launchNowFocus,
                                child: Builder(
                                  builder: (BuildContext context) {
                                    final isFocused = Focus.of(
                                      context,
                                    ).hasFocus;
                                    return ElevatedButton.icon(
                                      onPressed: _startCountdownForLaunch,
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('Launch Now'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isFocused
                                            ? Colors.green.shade700
                                            : Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        side: isFocused
                                            ? const BorderSide(
                                                color: Colors.white,
                                                width: 3,
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        } else {
                          // Portrait: Top row with 2 buttons, bottom row with 1 button
                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Focus(
                                    focusNode: _changeSelectionFocus,
                                    child: Builder(
                                      builder: (BuildContext context) {
                                        final isFocused = Focus.of(
                                          context,
                                        ).hasFocus;
                                        return ElevatedButton.icon(
                                          onPressed: _clearSelection,
                                          icon: const Icon(Icons.edit),
                                          label: const Text('Change Selection'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isFocused
                                                ? Colors.orange.shade700
                                                : Colors.orange,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 15,
                                              vertical: 10,
                                            ),
                                            side: isFocused
                                                ? const BorderSide(
                                                    color: Colors.white,
                                                    width: 3,
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 15),
                                  Focus(
                                    focusNode: _settingsFocus,
                                    child: Builder(
                                      builder: (BuildContext context) {
                                        final isFocused = Focus.of(
                                          context,
                                        ).hasFocus;
                                        return ElevatedButton.icon(
                                          onPressed: _openSystemSettings,
                                          icon: const Icon(Icons.settings),
                                          label: const Text('Settings'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isFocused
                                                ? Colors.blue.shade700
                                                : Colors.blue,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 15,
                                              vertical: 10,
                                            ),
                                            side: isFocused
                                                ? const BorderSide(
                                                    color: Colors.white,
                                                    width: 3,
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 15),
                              Focus(
                                focusNode: _launchNowFocus,
                                child: Builder(
                                  builder: (BuildContext context) {
                                    final isFocused = Focus.of(
                                      context,
                                    ).hasFocus;
                                    return ElevatedButton.icon(
                                      onPressed: _startCountdownForLaunch,
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('Launch Now'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isFocused
                                            ? Colors.green.shade700
                                            : Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                        side: isFocused
                                            ? const BorderSide(
                                                color: Colors.white,
                                                width: 3,
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openSystemSettings() async {
    try {
      // Use method channel to open system settings (same as reference app)
      const platform = MethodChannel('launcher_exit');
      await platform.invokeMethod('openSystemSettings');
    } catch (e) {
      _showErrorDialog(
        'Cannot open system settings. Please use your TV remote:\n\n'
        '1. Press the Settings button on your remote\n'
        '2. Or go to Apps > Settings\n'
        '3. Or use voice command "Open Settings"',
      );
    }
  }

  /// Detects if the current device is a TV/Android TV device
  /// Returns true if it's a TV device, false if it's a regular Android device
  Future<bool> _isTVDevice() async {
    if (_isTVDeviceCached != null) {
      return _isTVDeviceCached!;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      // Check for TV-specific features
      final hasTVFeatures =
          androidInfo.systemFeatures.contains('android.software.leanback') ||
              androidInfo.systemFeatures
                  .contains('android.hardware.type.television');

      // Additional checks for TV-specific characteristics
      final hasTVArchitecture = androidInfo.supportedAbis.contains('x86') ||
          androidInfo.supportedAbis.contains('x86_64');

      // Check device type from model/manufacturer
      final model = androidInfo.model.toLowerCase();
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      final hasTVKeywords = model.contains('tv') ||
          model.contains('android tv') ||
          manufacturer.contains('tv') ||
          model.contains('set-top') ||
          model.contains('stb');

      _isTVDeviceCached = hasTVFeatures || hasTVArchitecture || hasTVKeywords;

      print('Device TV Detection:');
      print('  - hasTVFeatures: $hasTVFeatures');
      print('  - hasTVArchitecture: $hasTVArchitecture');
      print('  - hasTVKeywords: $hasTVKeywords');
      print('  - systemFeatures: ${androidInfo.systemFeatures}');
      print('  - model: $model');
      print('  - manufacturer: $manufacturer');
      print('  - Final result: $_isTVDeviceCached');

      return _isTVDeviceCached!;
    } catch (e) {
      print('Error detecting TV device: $e');
      // Default to false if detection fails
      _isTVDeviceCached = false;
      return false;
    }
  }

  Widget _buildAppSelectionView() {
    // Initialize focus when view is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ensure both indices are synchronized
      _focusedIndex = _focusedAppIndex;
      if (_focusedAppIndex >= 0 &&
          _focusedAppIndex < _installedApps.length &&
          _gridActive) {
        _focusNode.requestFocus(); // Request focus on main focus node
        _scrollToFocusedItem();
      } else {
        // Start with toggle focused if grid is not active
        _toggleFocus.requestFocus();
      }
    });

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Column(
            children: [
              Text(
                'Select an App to Launch',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Toggle for system apps
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Show Built-in Apps:',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Focus(
                    focusNode: _toggleFocus,
                    onFocusChange: (hasFocus) {
                      if (hasFocus) {
                        setState(() {
                          _gridActive = false;
                          _focusedIndex = -1;
                          _focusedAppIndex =
                              -1; // Clear app index when toggle gets focus
                        });
                      }
                    },
                    onKey: (node, event) {
                      if (event is RawKeyDownEvent &&
                          (event.logicalKey == LogicalKeyboardKey.select ||
                              event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey == LogicalKeyboardKey.space)) {
                        _toggleSystemApps();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (BuildContext context) {
                        final isFocused = Focus.of(context).hasFocus;
                        return Container(
                          decoration: isFocused
                              ? BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                )
                              : null,
                          child: Switch(
                            value: _showSystemApps,
                            onChanged: (value) => _toggleSystemApps(),
                            activeThumbColor: Colors.blue,
                            inactiveThumbColor: Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final orientation = MediaQuery.of(context).orientation;
              final crossAxis = orientation == Orientation.landscape ? 6 : 4;
              // Calculate number of rows needed for grid
              final rows = (_installedApps.length / crossAxis).ceil();

              return ScrollablePositionedList.builder(
                itemScrollController: _itemScrollController,
                itemCount: rows,
                itemBuilder: (context, rowIndex) {
                  final startIndex = rowIndex * crossAxis;

                  return Container(
                    height: 90, // Fixed height for each row
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: List.generate(crossAxis, (colIndex) {
                        if (startIndex + colIndex >= _installedApps.length) {
                          // Empty space for incomplete row
                          return Expanded(child: Container());
                        }

                        final appIndex = startIndex + colIndex;
                        final app = _installedApps[appIndex];
                        final isFocused =
                            _gridActive && appIndex == _focusedIndex;

                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            child: RepaintBoundary(
                              key: ValueKey('app_${app.packageName}_$appIndex'),
                              child: GestureDetector(
                                onTap: () => _selectApp(app),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isFocused
                                        ? Colors.blue.withOpacity(0.35)
                                        : Colors.grey.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isFocused
                                          ? Colors.blue
                                          : Colors.grey.withOpacity(0.3),
                                      width: isFocused ? 3 : 1,
                                    ),
                                    boxShadow: isFocused
                                        ? [
                                            BoxShadow(
                                              color: Colors.blue.withOpacity(
                                                0.25,
                                              ),
                                              blurRadius: 10,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: app.icon != null
                                            ? Image.memory(
                                                app.icon!,
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                                errorBuilder: (
                                                  context,
                                                  error,
                                                  stackTrace,
                                                ) {
                                                  return Container(
                                                    width: 40,
                                                    height: 40,
                                                    color: isFocused
                                                        ? Colors.blue
                                                        : Colors.grey[600],
                                                    child: const Icon(
                                                      Icons.apps,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                  );
                                                },
                                              )
                                            : Container(
                                                width: 40,
                                                height: 40,
                                                color: isFocused
                                                    ? Colors.blue
                                                    : Colors.grey[600],
                                                child: const Icon(
                                                  Icons.apps,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                      ),
                                      const SizedBox(height: 4),
                                      Flexible(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            app.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isFocused
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              color: isFocused
                                                  ? Colors.white
                                                  : Colors.grey[300],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
