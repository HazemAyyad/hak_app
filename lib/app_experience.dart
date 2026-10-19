import 'dart:async';

import 'package:flutter/material.dart';

import 'features/quran/data/quran_audio.dart';
import 'features/quran/presentation/quran_audio_widgets.dart';

/// Shared by the root navigator, feature navigators and bottom destinations.
class AppExperienceController extends ChangeNotifier {
  final navigatorKey = GlobalKey<NavigatorState>();
  final Map<String, List<Route<dynamic>>> _routes = {};
  final Map<QuranMedia, VoidCallback> _listeners = {};
  String surface = 'home';
  bool transitioning = false, collapsed = false, bottomBarVisible = true;
  bool _disposed = false, _queued = false, _asking = false;
  int _popups = 0;
  Timer? _transitionTimer;
  QuranMedia? _media;
  int? _session;
  Object? _origin;
  bool _approved = false;
  bool _minimized = false;
  Future<bool?> Function()? askToContinue;
  VoidCallback? openPlayer;

  QuranMedia? get media => _media;
  Object get location {
    final root = _routes['root'];
    if (root != null && root.length > 1) return root.last;
    final nested = _routes[surface];
    return nested != null && nested.isNotEmpty ? nested.last : surface;
  }

  bool get hasBottomBar =>
      bottomBarVisible && (_routes['root']?.length ?? 0) <= 1;
  bool get needsDecision =>
      _media != null &&
      (_media!.playing || _media!.buffering) &&
      _origin != location &&
      !_approved;
  bool isDocked(QuranMedia audio) =>
      _media == audio &&
      _approved &&
      (_media?.current != null || _media?.loading == true) &&
      (_minimized || _origin != location);
  bool get showDock => _media != null && isDocked(_media!) && _popups == 0;

  void minimize(QuranMedia audio) {
    if (audio.current == null && !audio.loading) return;
    _media = audio;
    _session = audio.playbackSession;
    _origin ??= location;
    _approved = true;
    _minimized = true;
    collapsed = false;
    _update();
  }

  NavigatorObserver observer(String name) => _AppNavigatorObserver(this, name);

  void register(QuranMedia audio) {
    if (_listeners.containsKey(audio)) return;
    void listener() => _audioChanged(audio);
    _listeners[audio] = listener;
    audio.addListener(listener);
    _audioChanged(audio);
  }

  void unregister(QuranMedia audio) {
    final listener = _listeners.remove(audio);
    if (listener != null) audio.removeListener(listener);
    if (_media == audio) _clear();
  }

  void _audioChanged(QuranMedia audio) {
    if (audio.current != null || audio.loading) {
      if (_media != audio || _session != audio.playbackSession) {
        final keepMinimized = _media == audio && _minimized;
        _media = audio;
        _session = audio.playbackSession;
        _origin = location;
        _minimized = keepMinimized;
        _approved = keepMinimized;
        collapsed = false;
      }
    } else if (_media == audio) {
      _clear();
    }
    _update();
  }

  void _clear() {
    _media = null;
    _session = null;
    _origin = null;
    _approved = false;
    _minimized = false;
    collapsed = false;
    _update();
  }

  void changeSurface(String value) {
    if (value == surface) return;
    surface = value;
    transition();
  }

  void setBottomBarVisible(bool visible) {
    if (bottomBarVisible == visible) return;
    bottomBarVisible = visible;
    _update();
  }

  void transition() {
    transitioning = true;
    _transitionTimer?.cancel();
    // Feedback accompanies the animation; it never postpones navigation.
    _transitionTimer = Timer(const Duration(milliseconds: 280), () {
      transitioning = false;
      _update();
    });
    _update();
  }

  void setCollapsed(bool value) {
    collapsed = value;
    _update();
  }

  Future<void> stop() async {
    final audio = _media;
    _clear();
    await audio?.stop();
  }

  void _update() {
    if (_disposed || _queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (_disposed) return;
      if (_approved && !_minimized && _origin == location) {
        _approved = false;
        collapsed = false;
      }
      notifyListeners();
      unawaited(_decide());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _decide() async {
    if (!_asking &&
        !_approved &&
        _media?.current != null &&
        !_media!.playing &&
        !_media!.buffering &&
        _origin != location) {
      _approved = true;
      _update();
      return;
    }
    if (_asking || !needsDecision || askToContinue == null) return;
    _asking = true;
    final audio = _media, serial = _session;
    final answer = await askToContinue!();
    if (!_disposed && _media == audio && _session == serial) {
      if (answer == true) {
        _approved = true;
        collapsed = false;
      } else {
        await stop();
      }
    }
    _asking = false;
    _update();
  }

  @override
  void dispose() {
    _disposed = true;
    _transitionTimer?.cancel();
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _listeners.clear();
    super.dispose();
  }
}

class _AppNavigatorObserver extends NavigatorObserver {
  _AppNavigatorObserver(this.controller, this.name);
  final AppExperienceController controller;
  final String name;
  List<Route<dynamic>> get pages =>
      controller._routes.putIfAbsent(name, () => []);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      controller._popups++;
      controller._update();
    }
    if (route is! PageRoute) return;
    if (previousRoute == null) pages.clear();
    pages.add(route);
    if (previousRoute != null) controller.transition();
    controller._update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      controller._popups = (controller._popups - 1).clamp(0, 100);
      controller._update();
    }
    if (route is! PageRoute) return;
    pages.remove(route);
    controller.transition();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      controller._popups = (controller._popups - 1).clamp(0, 100);
      controller._update();
    }
    if (route is! PageRoute) return;
    pages.remove(route);
    controller._update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : pages.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute is PageRoute) {
        pages[index] = newRoute;
      } else {
        pages.removeAt(index);
      }
      controller.transition();
    }
  }
}

class AppExperienceScope extends InheritedWidget {
  const AppExperienceScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final AppExperienceController controller;
  static AppExperienceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppExperienceScope>()
      ?.controller;
  @override
  bool updateShouldNotify(AppExperienceScope oldWidget) =>
      controller != oldWidget.controller;
}

class AppExperienceOverlay extends StatefulWidget {
  const AppExperienceOverlay({
    super.key,
    required this.controller,
    required this.child,
  });
  final AppExperienceController controller;
  final Widget child;
  @override
  State<AppExperienceOverlay> createState() => _AppExperienceOverlayState();
}

class _AppExperienceOverlayState extends State<AppExperienceOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.askToContinue = _ask;
    widget.controller.openPlayer = _openPlayer;
  }

  void _openPlayer() {
    final context = widget.controller.navigatorKey.currentContext;
    final audio = widget.controller.media;
    if (context == null || audio == null) return;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: QuranPlayerPanel(
              media: audio,
              repository: audio.repository(),
              floating: true,
              onMinimize: () {
                widget.controller.minimize(audio);
                Navigator.pop(context);
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _ask() async {
    final context = widget.controller.navigatorKey.currentContext;
    if (context == null) return false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('متابعة الاستماع؟'),
            content: const Text(
              'هل تريد أن يستمر الصوت بعد مغادرة هذه الصفحة؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('لا، إيقاف الصوت'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('نعم، متابعة الاستماع'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.askToContinue = null;
    widget.controller.openPlayer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppExperienceScope(
    controller: widget.controller,
    child: Overlay.wrap(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: [
              widget.child,
              if (widget.controller.transitioning)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 24,
                  right: 24,
                  child: IgnorePointer(
                    child: Semantics(
                      label: 'جارٍ الانتقال',
                      liveRegion: true,
                      child: Material(
                        key: ValueKey('app-navigation-loader'),
                        elevation: 4,
                        borderRadius: BorderRadius.circular(16),
                        color: Theme.of(context).colorScheme.surface,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Flexible(child: Text('جارٍ فتح الصفحة…')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.controller.showDock)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom:
                      (widget.controller.hasBottomBar ? 72.0 : 0.0) +
                      MediaQuery.paddingOf(context).bottom +
                      6,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: AppPlaybackDock(controller: widget.controller),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AppPlaybackDock extends StatelessWidget {
  const AppPlaybackDock({super.key, required this.controller});
  final AppExperienceController controller;
  @override
  Widget build(BuildContext context) {
    final audio = controller.media!;
    return Material(
      key: const ValueKey('app-playback-dock'),
      elevation: 5,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.bottomCenter,
        child: QuranPlayerPanel(
          media: audio,
          repository: audio.repository(),
          compact: true,
          floating: true,
          collapsed: controller.collapsed,
          onToggleCollapsed: () =>
              controller.setCollapsed(!controller.collapsed),
          onOpen: controller.openPlayer,
          onClose: controller.stop,
        ),
      ),
    );
  }
}
