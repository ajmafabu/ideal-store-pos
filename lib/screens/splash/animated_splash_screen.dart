import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:video_player/video_player.dart';

/// Opening screen (about 5 s with the video, 2.6 s with the photo; any tap
/// skips it).
///
/// Video (owner, 14 Oct 2026): rice, sugar and dal bursting from their packs
/// and scattering (Gemini clip, trimmed to 5 s, watermark removed, no
/// sound). If the video cannot play on a PC (no Media Foundation, slow
/// start), the photo below is shown instead, so the splash never breaks.
///
/// Redesigned 14 Oct 2026: the wide logo was cropped into a small square
/// ("IDE / STO / PO") over a purple background with falling clip-art.
/// Now: a photograph of premium rice, sugar and dal bursting from their
/// packs (owner's choice) with a slow cinematic zoom, a soft vignette and
/// light glints on the sugar; the whole logo on a white card in the dark
/// centre, one light sweep, a thin progress line and the version.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  // logo colours
  static const _navyDeep = Color(0xFF040A1A);
  static const _blue = Color(0xFF1E40AF);
  static const _green = Color(0xFF22A33A);
  static const _orange = Color(0xFFF97316);

  static const _videoAsset = 'assets/splash_video.mp4';
  static const _photo = 'assets/splash_bg.jpg';
  static const _photoSize = Size(1672, 940);
  // sugar crystals in the photo (photo pixels) that catch the light
  static const _glints = [
    Offset(1160, 150), Offset(1232, 262), Offset(1300, 112), Offset(1108, 352),
    Offset(1196, 212), Offset(1262, 64), Offset(1085, 262), Offset(1350, 330),
    Offset(1140, 455), Offset(1220, 400),
  ];

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  // the photo fades in from dark and slowly settles (cinematic zoom)
  late final Animation<double> _photoIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
  );
  late final Animation<double> _zoom = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOutCubic,
  );

  // card: fade + rise + slight zoom in the first half
  late final Animation<double> _cardIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
  );
  // light sweep across the logo
  late final Animation<double> _sweep = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.35, 0.85, curve: Curves.easeInOut),
  );
  // text and progress line
  late final Animation<double> _footerIn = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
  );

  // the progress line runs over the whole splash (video or photo)
  late final AnimationController _progressCtl = AnimationController(vsync: this);
  late final Animation<double> _progressCurve =
      CurvedAnimation(parent: _progressCtl, curve: Curves.easeInOutCubic);
  // a short fade to dark before the login screen (no hard cut)
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  VideoPlayerController? _video;
  bool _videoReady = false;
  String _version = '';
  bool _left = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    }).catchError((_) {});
    // the logo is pre-loaded with the screen's settings: after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final video = VideoPlayerController.asset(_videoAsset);
    final videoOk = video
        .initialize()
        .then((_) => true)
        .timeout(const Duration(milliseconds: 1500), onTimeout: () => false)
        .catchError((_) => false);
    // let the logo (and the fallback photo) decode meanwhile
    await Future.any([
      Future.wait([
        precacheImage(const AssetImage('assets/app_logo_clear.png'), context),
        precacheImage(const AssetImage(_photo), context),
      ]),
      Future.delayed(const Duration(milliseconds: 400)),
    ]).catchError((_) {});
    final ok = await videoOk && video.value.isInitialized && video.value.duration > Duration.zero;
    if (!mounted || _left) {
      video.dispose();
      return;
    }

    if (ok) {
      await video.setVolume(0);
      setState(() {
        _video = video;
        _videoReady = true;
      });
      final length = video.value.duration;
      _progressCtl.duration = length;
      _progressCtl.forward();
      _intro.forward();
      await video.play();
      await _videoEnd(video, length);
    } else {
      video.dispose();
      _progressCtl.duration = const Duration(milliseconds: 2400);
      _progressCtl.forward();
      await _intro.forward();
      // a moment to enjoy the picture
      await Future.delayed(const Duration(milliseconds: 900));
    }
    _go();
  }

  /// Completes when the video reaches its end (or a little after its
  /// length, if the player never says so).
  Future<void> _videoEnd(VideoPlayerController video, Duration length) {
    final done = Completer<void>();
    void listener() {
      final v = video.value;
      if (!done.isCompleted &&
          (v.hasError || (v.isInitialized && v.position >= length - const Duration(milliseconds: 120)))) {
        done.complete();
      }
    }
    video.addListener(listener);
    return done.future
        .timeout(length + const Duration(milliseconds: 800), onTimeout: () {})
        .whenComplete(() => video.removeListener(listener));
  }

  /// Leave the splash (once): at the end, or on a tap. A short fade to dark
  /// instead of a hard cut.
  Future<void> _go() async {
    if (_left || !mounted) return;
    _left = true;
    await _exit.forward();
    if (mounted) context.go('/login');
  }

  @override
  void dispose() {
    _video?.dispose();
    _intro.dispose();
    _ambient.dispose();
    _progressCtl.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // the logo is about 2 : 1. On wide screens it sits in the photo's dark
    // centre between the rice and the dal; on a phone it takes the width.
    final cardWidth = size.aspectRatio > 1.2
        ? min(size.width * 0.36, 480.0)
        : min(size.width * 0.80, 420.0);

    return Scaffold(
      backgroundColor: _navyDeep,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _go,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_videoReady && _video != null) _videoBackground() else _background(size),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _logoCard(cardWidth),
                  const SizedBox(height: 40),
                  _footer(cardWidth),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: FadeTransition(
                opacity: _footerIn,
                child: Text(
                  _version.isEmpty ? '' : 'Ideal Store POS  ·  $_version',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    letterSpacing: 1.6,
                    // readable over the grains in the photo
                    shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                  ),
                ),
              ),
            ),
            // fade to dark at the end
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _exit,
                builder: (context, _) => Opacity(
                  opacity: _exit.value,
                  child: const ColoredBox(color: _navyDeep),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The video filling the screen (cropped like a photo), with the same
  /// vignette so the logo stands out.
  Widget _videoBackground() {
    final v = _video!;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: v.value.size.width,
              height: v.value.size.height,
              child: VideoPlayer(v),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.05,
              colors: [Color(0x22040A1A), Color(0x11040A1A), Color(0xAA040A1A)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  /// The photo with a slow zoom, a vignette for the logo, and glints on
  /// the sugar.
  Widget _background(Size size) {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _ambient]),
      builder: (context, _) {
        final zoom = 1.10 - 0.08 * _zoom.value;
        // where the photo lands with BoxFit.cover, then the zoom around the centre
        final cover = max(size.width / _photoSize.width, size.height / _photoSize.height) * zoom;
        final dx = (size.width - _photoSize.width * cover) / 2;
        final dy = (size.height - _photoSize.height * cover) / 2;
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: _photoIn.value,
              child: Transform.scale(
                scale: zoom,
                child: Image.asset(
                  _photo,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: _navyDeep),
                ),
              ),
            ),
            // vignette: darker edges and a calm centre for the logo
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.05,
                  colors: [Color(0x33040A1A), Color(0x22040A1A), Color(0xCC040A1A)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
            // light catching a few sugar crystals
            for (var i = 0; i < _glints.length; i++)
              _glint(
                Offset(dx + _glints[i].dx * cover, dy + _glints[i].dy * cover),
                // each crystal twinkles at its own moment
                (sin(_ambient.value * 2 * pi * 1.5 + i * 1.9) + 1) / 2 * _photoIn.value,
                8 + (i % 3) * 4.0,
              ),
          ],
        );
      },
    );
  }

  /// A small four-point star of light.
  Widget _glint(Offset at, double strength, double radius) {
    final a = (strength * strength).clamp(0.0, 1.0);
    return Positioned(
      left: at.dx - radius * 2,
      top: at.dy - radius * 2,
      width: radius * 4,
      height: radius * 4,
      child: IgnorePointer(
        child: CustomPaint(painter: _GlintPainter(a)),
      ),
    );
  }

  /// The logo on frosted glass: the video shows softly through, a hairline
  /// border in the brand colours, a glow behind, then one light sweep.
  /// (Was a plain white box that looked pasted on the video — 14 Oct 2026.)
  Widget _logoCard(double width) {
    const radius = 26.0;
    final glass = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // milky glass: bright at the top, a touch clearer at the bottom
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.90),
                Colors.white.withValues(alpha: 0.76),
              ],
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: width * 0.07, vertical: width * 0.06),
          child: AspectRatio(
            aspectRatio: 1454 / 656,
            child: Image.asset(
              'assets/app_logo_clear.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => Image.asset('assets/app_logo.png', fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );

    // hairline border in the logo's blue → green → orange
    final framed = Container(
      padding: const EdgeInsets.all(1.6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 1.6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.95),
            _blue.withValues(alpha: 0.85),
            _green.withValues(alpha: 0.85),
            _orange.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.35, 0.7, 1.0],
        ),
        // soft coloured glow + a grounding shadow (outside the clip)
        boxShadow: [
          BoxShadow(color: _blue.withValues(alpha: 0.45), blurRadius: 70, spreadRadius: 4),
          BoxShadow(color: _green.withValues(alpha: 0.18), blurRadius: 90, offset: const Offset(40, 30)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 30, offset: const Offset(0, 16)),
        ],
      ),
      child: Stack(
        children: [
          glass,
          // one soft light passing over the glass
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    final x = -1.6 + 3.2 * _sweep.value;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(x - 0.5, -1),
                          end: Alignment(x + 0.5, 1),
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: _sweep.value > 0 && _sweep.value < 1 ? 0.6 : 0),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.35, 0.5, 0.65],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: _intro,
      builder: (context, child) {
        final v = _cardIn.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - v)),
            child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
          ),
        );
      },
      child: framed,
    );
  }

  /// "Preparing your store…" and a thin progress line in the logo colours.
  Widget _footer(double width) {
    final lineWidth = min(width * 0.55, 260.0);
    return FadeTransition(
      opacity: _footerIn,
      child: Column(
        children: [
          SizedBox(
            width: lineWidth,
            height: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.white.withValues(alpha: 0.10)),
                  AnimatedBuilder(
                    animation: _progressCurve,
                    builder: (context, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      heightFactor: 1, // full 3 px (it had no height: invisible)
                      widthFactor: _progressCurve.value.clamp(0.02, 1.0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [_blue, _green, _orange]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Preparing your store…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              shadows: const [Shadow(color: Colors.black, blurRadius: 10)],
              fontSize: 13,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlintPainter extends CustomPainter {
  _GlintPainter(this.alpha);
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.02) return;
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // soft halo
    canvas.drawCircle(
      c,
      r * 0.45,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // four thin rays
    final ray = Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withValues(alpha: alpha),
        Colors.white.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r, c.dy)
        ..lineTo(c.dx, c.dy - r * 0.07)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r * 0.07)
        ..close(),
      ray,
    );
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * 0.07, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r * 0.07, c.dy)
        ..close(),
      ray,
    );
    canvas.drawCircle(c, 1.6, Paint()..color = Colors.white.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(covariant _GlintPainter old) => old.alpha != alpha;
}
