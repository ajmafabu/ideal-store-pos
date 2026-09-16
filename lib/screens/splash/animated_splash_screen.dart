import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _productFallController;
  late AnimationController _productFadeController;
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _shimmerController;
  late AnimationController _gradientController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  final List<_FallingProduct> _products = [];
  final _random = Random(42);
  bool _imagesLoaded = false;

  @override
  void initState() {
    super.initState();
    _initProducts();
    _initControllers();
    _preloadImages();
  }

  void _initControllers() {
    // Phase 1: Products fall (7s)
    _productFallController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7000),
    );

    // Phase 2: Products fade/scatter (2.5s, starts after fall)
    _productFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Logo zoom-out (3s)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _logoScale = Tween<double>(begin: 3.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.3)),
    );

    // Text fade + slide
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );

    // Shimmer
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Gradient
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  void _initProducts() {
    final assets = [
      'assets/products/rice.png',
      'assets/products/oil.png',
      'assets/products/soap.png',
      'assets/products/buis.png',
      'assets/products/chips.png',
      'assets/products/candy.png',
      'assets/products/candy2.png',
      'assets/products/choco.png',
      'assets/products/masal.png',
      'assets/products/masala2.png',
      'assets/products/kindpng_1621993.png',
      'assets/products/kindpng_7151924.png',
      'assets/products/kindpng_2217232.png',
      'assets/products/kindpng_2298123.png',
      'assets/products/kindpng_3334285.png',
      'assets/products/kindpng_3352361.png',
      'assets/products/kindpng_4815329.png',
      'assets/products/kindpng_4828575.png',
      'assets/products/kindpng_5792844.png',
      'assets/products/kindpng_5792846.png',
      'assets/products/kindpng_7090648.png',
      'assets/products/kindpng_716400.png',
      'assets/products/kindpng_736035.png',
      'assets/products/kindpng_7844553.png',
      'assets/products/kindpng_78543.png',
    ];

    for (int i = 0; i < assets.length; i++) {
      _products.add(_FallingProduct(
        asset: assets[i],
        startX: 0.08 + _random.nextDouble() * 0.84,
        delay: i * 0.06,
        rotation: _random.nextDouble() * 0.4 - 0.2,
        rotationSpeed: _random.nextDouble() * 1.5 - 0.75,
        size: 80.0 + _random.nextDouble() * 30,
      ));
    }
  }

  Future<void> _preloadImages() async {
    for (final p in _products) {
      await precacheImage(AssetImage(p.asset), context);
    }
    setState(() => _imagesLoaded = true);
    _startAnimations();
  }

  Future<void> _startAnimations() async {
    _gradientController.repeat();

    // Phase 1: Products fall (0 - 7s)
    _productFallController.forward();

    // Phase 2: Products scatter/fade (at 7s)
    await Future.delayed(const Duration(milliseconds: 7000));
    _productFadeController.forward();

    // Logo starts zooming at 7.3s
    await Future.delayed(const Duration(milliseconds: 300));
    _logoController.forward();

    // Text at 9.5s
    await Future.delayed(const Duration(milliseconds: 2200));
    _textController.forward();
    _shimmerController.repeat();

    // Navigate at 12.5s
    await Future.delayed(const Duration(milliseconds: 3000));
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _productFallController.dispose();
    _productFadeController.dispose();
    _logoController.dispose();
    _textController.dispose();
    _shimmerController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_imagesLoaded) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      body: AnimatedBuilder(
        animation: _gradientController,
        builder: (context, _) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    const Color(0xFF667eea),
                    const Color(0xFF764ba2),
                    (_gradientController.value * 2) % 1.0,
                  )!,
                  Color.lerp(
                    const Color(0xFF764ba2),
                    const Color(0xFF667eea),
                    (_gradientController.value * 2) % 1.0,
                  )!,
                  Color.lerp(
                    const Color(0xFF667eea),
                    const Color(0xFF4338CA),
                    (_gradientController.value * 2) % 1.0,
                  )!,
                ],
              ),
            ),
            child: Stack(
              children: [
                // Falling products
                ..._buildFallingProducts(),

                // Center content
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo with zoom-out
                      AnimatedBuilder(
                        animation: _logoController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _logoScale.value,
                            child: Opacity(
                              opacity: _logoOpacity.value,
                              child: child,
                            ),
                          );
                        },
                        child: _buildLogo(),
                      ),

                      const SizedBox(height: 24),

                      // Text with slide + fade
                      SlideTransition(
                        position: _textSlide,
                        child: FadeTransition(
                          opacity: _textOpacity,
                          child: Column(
                            children: [
                              _buildShimmerText(
                                'Ideal Store',
                                const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Smart Business Management',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.7),
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Loading dots
                      FadeTransition(
                        opacity: _textOpacity,
                        child: _buildLoadingDots(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Image.asset(
          'assets/app_logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.store_rounded,
            color: Colors.white,
            size: 48,
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerText(String text, TextStyle style) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: const [
                Colors.white,
                Colors.white,
                Color(0xFFFFD700),
                Colors.white,
                Colors.white,
              ],
              stops: [
                (_shimmerController.value - 0.3).clamp(0.0, 1.0),
                (_shimmerController.value - 0.1).clamp(0.0, 1.0),
                _shimmerController.value,
                (_shimmerController.value + 0.1).clamp(0.0, 1.0),
                (_shimmerController.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: Text(text, style: style),
        );
      },
    );
  }

  Widget _buildLoadingDots() {
    return AnimatedBuilder(
      animation: _productFallController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = (_productFallController.value + i * 0.33) % 1.0;
            final opacity = (sin(offset * pi) * 0.5 + 0.5).toDouble();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity * 0.8),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }

  List<Widget> _buildFallingProducts() {
    return List.generate(_products.length, (index) {
      final product = _products[index];
      return AnimatedBuilder(
        animation: Listenable.merge([_productFallController, _productFadeController]),
        builder: (context, child) {
          final screenSize = MediaQuery.of(context).size;

          // Fall phase progress (0 -> 1 over 3s)
          final fallProgress = (_productFallController.value - product.delay).clamp(0.0, 1.0);

          // Fade phase progress (0 -> 1 over 1.5s after fall)
          final fadeProgress = _productFadeController.value;

          // Y position: fall from above screen to bottom of screen
          final startY = -150.0;
          final endY = screenSize.height * 0.95 + (index % 3) * 40.0;
          final fallCurve = Curves.easeIn.transform(fallProgress);
          final y = startY + (endY - startY) * fallCurve;

          // Horizontal wobble during fall
          final wobbleX = sin(fallProgress * pi * 2.5) * 20;

          // Rotation during fall
          final rotation = product.rotation + product.rotationSpeed * fallProgress * pi;

          // During fade phase: scatter outward + shrink + fade
          final centerX = screenSize.width / 2;
          final moveOut = (product.startX * screenSize.width - centerX) * fadeProgress * 3;
          final fadeScale = 1.0 - fadeProgress * 0.6;
          final fadeOpacity = 1.0 - fadeProgress;

          return Positioned(
            left: product.startX * screenSize.width - product.size / 2 + wobbleX + moveOut,
            top: y - fadeProgress * 80,
            child: Transform.rotate(
              angle: rotation,
              child: Transform.scale(
                scale: fadeScale,
                child: Opacity(
                  opacity: fallProgress > 0 ? fadeOpacity : 0,
                  child: Image.asset(
                    product.asset,
                    width: product.size,
                    height: product.size,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

class _FallingProduct {
  final String asset;
  final double startX;
  final double delay;
  final double rotation;
  final double rotationSpeed;
  final double size;

  const _FallingProduct({
    required this.asset,
    required this.startX,
    required this.delay,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
  });
}
