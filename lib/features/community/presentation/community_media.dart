import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

bool safeCommunityUrl(String value) {
  final u = Uri.tryParse(value);
  return u != null &&
      u.scheme == 'https' &&
      u.host.isNotEmpty &&
      u.userInfo.isEmpty;
}

Future<void> openCommunityLink(BuildContext context, String value) async {
  try {
    if (!safeCommunityUrl(value) ||
        !await launchUrl(
          Uri.parse(value),
          mode: LaunchMode.externalApplication,
        )) {
      throw StateError('link');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح الرابط على هذا الجهاز')),
      );
    }
  }
}

class CommunityMediaView extends StatefulWidget {
  const CommunityMediaView({
    super.key,
    required this.row,
    this.beforePlay,
    this.onEnded,
  });
  final Map<String, dynamic> row;
  final Future<void> Function()? beforePlay;
  final VoidCallback? onEnded;
  @override
  State<CommunityMediaView> createState() => _CommunityMediaViewState();
}

class _CommunityMediaViewState extends State<CommunityMediaView>
    with WidgetsBindingObserver {
  VideoPlayerController? player;
  WebViewController? web;
  bool loading = false, ended = false;
  bool _foreground = true;
  int _attempt = 0;
  String? error;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> start() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    final attempt = ++_attempt;
    bool current() => mounted && _foreground && attempt == _attempt;
    VideoPlayerController? preparing;
    try {
      if (!supported) throw StateError('هذا المشغّل متاح على Android وiOS');
      await widget.beforePlay?.call();
      if (!current()) return;
      final youtube = widget.row['youtube_id'] as String?;
      if (youtube != null) {
        if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(youtube)) {
          throw const FormatException('YouTube');
        }
        final controller = WebViewController();
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.addJavaScriptChannel(
          'HaqVideo',
          onMessageReceived: (m) {
            if (!mounted) return;
            if (m.message == 'ended') {
              widget.onEnded?.call();
            } else if (m.message == 'error') {
              setState(() => error = 'تعذّر تشغيل فيديو YouTube');
            }
          },
        );
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (!request.isMainFrame) return NavigationDecision.navigate;
              return request.url == 'about:blank' ||
                      request.url.startsWith(
                        'https://www.youtube-nocookie.com/embed/',
                      )
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
            onWebResourceError: (e) {
              if (e.isForMainFrame == true && mounted) {
                setState(() => error = 'تعذّر تحميل المشغّل؛ أعد المحاولة');
              }
            },
          ),
        );
        if (!current()) return;
        await controller.loadHtmlString(
          '''<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>html,body,#player{margin:0;width:100%;height:100%;background:#081722}</style></head><body><div id="player"></div><script src="https://www.youtube.com/iframe_api"></script><script>var player;function onYouTubeIframeAPIReady(){player=new YT.Player('player',{host:'https://www.youtube-nocookie.com',videoId:'$youtube',playerVars:{playsinline:1},events:{onError:function(){HaqVideo.postMessage('error')},onStateChange:function(e){if(e.data===0)HaqVideo.postMessage('ended')}}});}</script></body></html>''',
          baseUrl: 'https://www.youtube-nocookie.com',
        );
        if (!current()) {
          await controller.loadHtmlString('');
          return;
        }
        setState(() => web = controller);
      } else {
        final value = widget.row['media_url'] as String?;
        if (value == null || !safeCommunityUrl(value)) {
          throw StateError('لا يوجد مصدر HTTPS صالح للفيديو');
        }
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(value),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
        );
        preparing = controller;
        await controller.initialize();
        if (!current()) {
          await controller.dispose();
          return;
        }
        player?.removeListener(changed);
        await player?.dispose();
        if (!current()) {
          await controller.dispose();
          return;
        }
        player = controller..addListener(changed);
        await controller.play();
      }
    } catch (e) {
      if (preparing != null && !identical(preparing, player)) {
        await preparing.dispose();
      }
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'تعذّر تشغيل الفيديو. تحقق من الاتصال ثم أعد المحاولة.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void changed() {
    if (!mounted) return;
    final value = player!.value;
    if (value.hasError) error = 'تعذّر تشغيل ملف الفيديو';
    if (value.isCompleted && !ended) {
      ended = true;
      widget.onEnded?.call();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      ++_attempt;
      unawaited(player?.pause());
      unawaited(
        web
            ?.runJavaScript(
              'if(window.player && player.pauseVideo) player.pauseVideo();',
            )
            .catchError((Object _) {}),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player?.removeListener(changed);
    unawaited(player?.dispose());
    unawaited(
      web
          ?.runJavaScript(
            'if(window.player && player.stopVideo) player.stopVideo();',
          )
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Padding(padding: const EdgeInsets.all(14), child: Text(error!)),
      if (web != null)
        AspectRatio(
          aspectRatio: 16 / 9,
          child: WebViewWidget(controller: web!),
        ),
      if (player?.value.isInitialized == true) ...[
        AspectRatio(
          aspectRatio: player!.value.aspectRatio,
          child: VideoPlayer(player!),
        ),
        VideoProgressIndicator(player!, allowScrubbing: true),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: player!.value.isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
              onPressed: () async {
                if (player!.value.isPlaying) {
                  await player!.pause();
                } else {
                  ended = false;
                  await widget.beforePlay?.call();
                  await player!.play();
                }
              },
              icon: Icon(
                player!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
            Text(
              '${player!.value.position.inMinutes}:${(player!.value.position.inSeconds % 60).toString().padLeft(2, '0')} / ${player!.value.duration.inMinutes}:${(player!.value.duration.inSeconds % 60).toString().padLeft(2, '0')}',
            ),
          ],
        ),
      ],
      if (player == null && web == null || error != null)
        FilledButton.icon(
          onPressed: loading ? null : start,
          icon: const Icon(Icons.play_circle_outline),
          label: Text(loading ? 'جارٍ التحميل…' : 'تشغيل الفيديو'),
        ),
      if (widget.row['youtube_id'] != null)
        TextButton(
          onPressed: () => openCommunityLink(
            context,
            'https://www.youtube.com/watch?v=${widget.row['youtube_id']}',
          ),
          child: const Text('فتح في YouTube'),
        ),
    ],
  );
}
