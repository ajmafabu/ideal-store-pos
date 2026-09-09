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
  late AnimationController _logoController;
  late AnimationController _gradientController;
  late AnimationController _particleController;
  late AnimationController _textController;
  late AnimationController _shimmerController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();

    // Logo fade + scale
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.5)),
    );

    // Gradient animation
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // Particles
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
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

    _startAnimations();
  }

  Future<void> _startAnimations() async {
    // Start gradient immediately
    _gradientController.repeat();
    _particleController.repeat();

    // Stagger logo animation
    await Future.delayed(const Duration(milliseconds: 300));
    _logoController.forward();

    // Text appears after logo
    await Future.delayed(const Duration(milliseconds: 600));
    _textController.forward();

    // Shimmer effect
    await Future.delayed(const Duration(milliseconds: 400));
    _shimmerController.repeat();

    // Navigate after all animations
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _gradientController.dispose();
    _particleController.dispose();
    _textController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _gradientController,
        builder: (context, child) {
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
                // Particles
                ...List.generate(20, (i) => _buildParticle(i)),

                // Center content
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo with scale + fade
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
      animation: _particleController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = (_particleController.value + i * 0.33) % 1.0;
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

  Widget _buildParticle(int index) {
    final random = Random(index);
    final size = random.nextDouble() * 4 + 2;
    final startX = random.nextDouble();
    final startY = random.nextDouble();
    final speed = random.nextDouble() * 0.3 + 0.1;

    return AnimatedBuilder(
      animation: _particleController,
      builder: (context, child) {
        final progress = (_particleController.value * speed + index * 0.1) % 1.0;
        final x = startX * MediaQuery.of(context).size.width;
        final y = startY * MediaQuery.of(context).size.height -
            progress * MediaQuery.of(context).size.height * 0.5;
        final opacity = (sin(progress * pi) * 0.4).clamp(0.0, 0.4);

        return Positioned(
          left: x,
          top: y,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
