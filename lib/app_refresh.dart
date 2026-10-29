import 'package:flutter/material.dart';

/// One refresh surface above the navigators. Feature pages supply their own
/// data callback without nesting another indicator or replacing their scroll.
class AppRefreshHost extends StatefulWidget {
  const AppRefreshHost({
    super.key,
    required this.onRefresh,
    required this.child,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  @override
  State<AppRefreshHost> createState() => _AppRefreshHostState();
}

class _AppRefreshHostState extends State<AppRefreshHost> {
  Future<void> Function()? _source;
  Future<void>? _pending;

  bool _notification(ScrollNotification notification) {
    final context = notification.context;
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification.metrics.axisDirection != AxisDirection.down ||
        context == null ||
        context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _source =
          context
              .getInheritedWidgetOfExactType<_RefreshCallback>()
              ?.onRefresh ??
          widget.onRefresh;
    }
    return true;
  }

  Future<void> _refresh() =>
      _pending ??= _runRefresh().whenComplete(() => _pending = null);

  Future<void> _runRefresh() async {
    try {
      await Future<void>.sync(_source ?? widget.onRefresh);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('تعذّر التحديث؛ بياناتك المحفوظة ما زالت متاحة'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => _RefreshHostMarker(
    child: ScrollConfiguration(
      behavior: const AppScrollBehavior(),
      child: RefreshIndicator(
        key: const ValueKey('haq-page-refresh'),
        edgeOffset: MediaQuery.paddingOf(context).top,
        onRefresh: _refresh,
        notificationPredicate: _notification,
        child: widget.child,
      ),
    ),
  );
}

class AppRefreshRegion extends StatelessWidget {
  const AppRefreshRegion({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RefreshHostMarker>() == null
      ? RefreshIndicator(onRefresh: onRefresh, color: color, child: child)
      : _RefreshCallback(onRefresh: onRefresh, child: child);
}

class _RefreshCallback extends InheritedWidget {
  const _RefreshCallback({required this.onRefresh, required super.child});
  final Future<void> Function() onRefresh;
  @override
  bool updateShouldNotify(_RefreshCallback oldWidget) =>
      onRefresh != oldWidget.onRefresh;
}

class _RefreshHostMarker extends InheritedWidget {
  const _RefreshHostMarker({required super.child});
  @override
  bool updateShouldNotify(_RefreshHostMarker oldWidget) => false;
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
