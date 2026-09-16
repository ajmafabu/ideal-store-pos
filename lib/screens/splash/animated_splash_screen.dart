import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _productController;
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _shimmerController;
  late AnimationController _gradientController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  final List<_FallingProduct> _products = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _initProducts();

    // Product fall controller (1.5s)
    _productController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Logo zoom-out controller (starts after products begin falling)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _logoScale = Tween<double>(begin: 3.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.4)),
    );

    // Text fade + slide
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
      duration: const Duration(milliseconds: 1500),
    );

    // Gradient
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _startAnimations();
  }

  void _initProducts() {
    final assets = [
      'assets/products/rice_bag.png',
      'assets/products/oil_bottle.png',
      'assets/products/detergent.png',
      'assets/products/shampoo.png',
      'assets/products/toothpaste.png',
      'assets/products/tea_packet.png',
      'assets/products/biscuit.png',
      'assets/products/dal_pack.png',
      'assets/products/soap.png',
      'assets/products/hair_oil.png',
    ];

    for (int i = 0; i < assets.length; i++) {
      _products.add(_FallingProduct(
        asset: assets[i],
        startX: 0.1 + _random.nextDouble() * 0.8,
        delay: i * 0.08,
        rotation: _random.nextDouble() * 0.6 - 0.3,
        rotationSpeed: _random.nextDouble() * 2 - 1,
        size: 40.0 + _random.nextDouble() * 25,
      ));
    }
  }

  Future<void> _startAnimations() async {
    _gradientController.repeat();

    // Start product fall immediately
    _productController.forward();

    // Logo starts zooming out after 1s
    await Future.delayed(const Duration(milliseconds: 1000));
    _logoController.forward();

    // Text appears
    await Future.delayed(const Duration(milliseconds: 1000));
    _textController.forward();
    _shimmerController.repeat();

    // Navigate after all animations
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _productController.dispose();
    _logoController.dispose();
    _textController.dispose();
    _shimmerController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      animation: _productController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = (_productController.value + i * 0.33) % 1.0;
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
        animation: _productController,
        builder: (context, child) {
          final screenSize = MediaQuery.of(context).size;
          final progress = (_productController.value - product.delay).clamp(0.0, 1.0);

          // Fall from top to middle area
          final fallProgress = Curves.easeIn.transform(progress);
          final startY = -80.0;
          final endY = screenSize.height * 0.15 + (index % 3) * 60.0;
          final y = startY + (endY - startY) * fallProgress;

          // Horizontal wobble
          final wobbleX = sin(progress * pi * 3) * 15;

          // Rotation
          final rotation = product.rotation + product.rotationSpeed * progress * pi;

          // Fade out after landing (products scatter)
          final fadeStart = 0.6;
          final fadeProgress = ((progress - fadeStart) / (1.0 - fadeStart)).clamp(0.0, 1.0);
          final opacity = progress < fadeStart ? 1.0 : (1.0 - fadeProgress);

          // Scale down when fading
          final scale = progress < fadeStart ? 1.0 : (1.0 - fadeProgress * 0.5);

          // Move outward when fading
          final centerX = screenSize.width / 2;
          final offsetX = (product.startX * screenSize.width - centerX) * fadeProgress * 2;

          return Positioned(
            left: product.startX * screenSize.width - product.size / 2 + wobbleX + offsetX,
            top: y,
            child: Transform.rotate(
              angle: rotation,
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Image.asset(
                    product.asset,
                    width: product.size,
                    height: product.size,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: product.size,
                      height: product.size,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
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
