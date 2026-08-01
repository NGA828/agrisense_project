import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../auth/role_selection_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  final List<_OnboardingData> _pages = [
    _OnboardingData(
      icon: Icons.camera_alt_rounded,
      title: 'Detect Crop\nDiseases Instantly',
      subtitle: 'Take a photo of your plant and our AI identifies the disease, severity, and provides treatment plans in seconds.',
      primaryColor: const Color(0xFF4CAF50),
      bgGradient: [
        const Color(0xFF0C2B11),
        const Color(0xFF1B5E20),
        const Color(0xFF2E7D32),
      ],
      glowColor: const Color(0xFF4CAF50).withValues(alpha: 0.4),
    ),
    _OnboardingData(
      icon: Icons.wb_sunny_rounded,
      title: 'Smart Weather\n& Farming Advice',
      subtitle: 'Get localized weather forecasts and AI-powered farming recommendations tailored to your crops.',
      primaryColor: const Color(0xFF2196F3),
      bgGradient: [
        const Color(0xFF0D1E36),
        const Color(0xFF1565C0),
        const Color(0xFF1976D2),
      ],
      glowColor: const Color(0xFF42A5F5).withValues(alpha: 0.4),
    ),
    _OnboardingData(
      icon: Icons.shopping_cart_rounded,
      title: 'Buy From\nVerified Dealers',
      subtitle: 'Browse quality seeds, fertilizers, and pesticides from trusted agro-dealers. Pay securely via MoMo.',
      primaryColor: const Color(0xFFFF9800),
      bgGradient: [
        const Color(0xFF2E1502),
        const Color(0xFFE65100),
        const Color(0xFFF57C00),
      ],
      glowColor: const Color(0xFFFF9800).withValues(alpha: 0.4),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final activePage = _pages[_currentPage];
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: activePage.bgGradient,
          ),
        ),
        child: Stack(
          children: [
            // Ambient Decorative Glow
            Positioned(
              top: -120,
              left: -120,
              child: _AmbientGlowBubble(color: activePage.primaryColor.withValues(alpha: 0.25)),
            ),
            Positioned(
              top: screenHeight * 0.35,
              right: -180,
              child: _AmbientGlowBubble(color: activePage.primaryColor.withValues(alpha: 0.15)),
            ),
            Positioned(
              bottom: -100,
              left: -50,
              child: _AmbientGlowBubble(color: activePage.primaryColor.withValues(alpha: 0.1)),
            ),

            SafeArea(
              child: Column(
                children: [
                  // App Branding & Skip Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // App Brand
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.eco_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'AgriSense AI',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Skip Button
                        TextButton(
                          onPressed: _navigateToLogin,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.12),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            'Skip',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Carousel Area
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (index) => setState(() => _currentPage = index),
                      itemBuilder: (context, index) {
                        final page = _pages[index];
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Glassmorphic Icon Container
                            _FloatingWidget(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Outer glow
                                  Container(
                                    width: 180,
                                    height: 180,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: page.glowColor,
                                          blurRadius: 50,
                                          spreadRadius: 15,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Inner Glassmorphic Box
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(45),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                      child: Container(
                                        width: 150,
                                        height: 150,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(45),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.25),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Icon(
                                          page.icon,
                                          size: 70,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // Bottom Card with Content
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121511).withValues(alpha: 0.5),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(40),
                            topRight: Radius.circular(40),
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Page Indicators
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _pages.length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 400),
                                  margin: const EdgeInsets.symmetric(horizontal: 5),
                                  width: _currentPage == index ? 32 : 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _currentPage == index
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(5),
                                    boxShadow: _currentPage == index
                                        ? [
                                            BoxShadow(
                                              color: Colors.white.withValues(alpha: 0.5),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Dynamic Text Content
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 450),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.0, 0.2),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: Column(
                                key: ValueKey<int>(_currentPage),
                                children: [
                                  Text(
                                    activePage.title,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.2,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      activePage.subtitle,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontSize: 15,
                                        height: 1.6,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 40),

                            // Primary Action Button
                            SizedBox(
                              width: double.infinity,
                              height: 58,
                              child: ElevatedButton(
                                onPressed: () {
                                  if (_currentPage < _pages.length - 1) {
                                    _pageController.nextPage(
                                      duration: const Duration(milliseconds: 500),
                                      curve: Curves.easeInOut,
                                    );
                                  } else {
                                    _navigateToLogin();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: activePage.primaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  elevation: 8,
                                  shadowColor: activePage.primaryColor.withValues(alpha: 0.4),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _currentPage < _pages.length - 1 ? 'Continue' : 'Get Started',
                                      style: GoogleFonts.poppins(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: activePage.primaryColor,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    if (_currentPage < _pages.length - 1) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        color: activePage.primaryColor,
                                        size: 20,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Login Link
                            GestureDetector(
                              onTap: _navigateToLogin,
                              child: Text.rich(
                                TextSpan(
                                  text: 'Already have an account? ',
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 14,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Log In',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.underline,
                                        decorationColor: Colors.white,
                                      ),
                                    ),
                                  ],
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
          ],
        ),
      ),
    );
  }

  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
    );
  }
}

// Custom widgets
class _AmbientGlowBubble extends StatelessWidget {
  final Color color;
  const _AmbientGlowBubble({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      height: 350,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _FloatingWidget extends StatefulWidget {
  final Widget child;
  const _FloatingWidget({required this.child});

  @override
  State<_FloatingWidget> createState() => _FloatingWidgetState();
}

class _FloatingWidgetState extends State<_FloatingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -12, end: 12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _OnboardingData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color primaryColor;
  final List<Color> bgGradient;
  final Color glowColor;

  const _OnboardingData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryColor,
    required this.bgGradient,
    required this.glowColor,
  });
}
