import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Note: If AppTheme is imported from your project, keep it. 
// We provide fallback/placeholder colors to ensure compilation works flawlessly.
import '../../theme/app_theme.dart';
import '../auth/role_selection_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingData> _pages = [
    _OnboardingData(
      icon: Icons.camera_alt_rounded,
      title: 'Detect Crop\nDiseases Instantly',
      subtitle: 'Take a photo of your plant and our AI identifies the disease, severity, and provides treatment plans in seconds.',
      primaryColor: const Color(0xFF4CAF50), // Fallback if AppTheme.primary is unavailable
      bgGradient: [
        const Color(0xFF0C2B11),
        const Color(0xFF1B5E20),
        const Color(0xFF388E3C),
      ],
      glowColor: const Color(0xFF4CAF50).withOpacity(0.4),
    ),
    _OnboardingData(
      icon: Icons.wb_sunny_rounded,
      title: 'Smart Weather\n& Farming Advice',
      subtitle: 'Get localized weather forecasts and AI-powered farming recommendations tailored to your crops.',
      primaryColor: const Color(0xFF2196F3), // Fallback if AppTheme.info is unavailable
      bgGradient: [
        const Color(0xFF0D1E36),
        const Color(0xFF1565C0),
        const Color(0xFF1976D2),
      ],
      glowColor: const Color(0xFF42A5F5).withOpacity(0.4),
    ),
    _OnboardingData(
      icon: Icons.shopping_cart_rounded,
      title: 'Buy From\nVerified Dealers',
      subtitle: 'Browse quality seeds, fertilizers, and pesticides from trusted agro-dealers. Pay securely via MoMo.',
      primaryColor: const Color(0xFFFF9800), // Fallback if AppTheme.accent is unavailable
      bgGradient: [
        const Color(0xFF2E1502),
        const Color(0xFFE65100),
        const Color(0xFFF57C00),
      ],
      glowColor: const Color(0xFFFF9800).withOpacity(0.4),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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
            // Ambient Decorative Glow Bubbles for Organic Depth
            Positioned(
              top: -100,
              left: -100,
              child: _AmbientGlowBubble(color: activePage.primaryColor.withOpacity(0.25)),
            ),
            Positioned(
              top: screenHeight * 0.4,
              right: -150,
              child: _AmbientGlowBubble(color: activePage.primaryColor.withOpacity(0.15)),
            ),

            SafeArea(
              child: Column(
                children: [
                  // App Branding & Skip Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // App Brand Logo/Text
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.eco_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'AgriSense AI',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        // Skip Button
                        TextButton(
                          onPressed: _navigateToLogin,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.1),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            'Skip',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Carousel Area (Adaptive Layout)
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
                            // Beautiful Breathing Glassmorphic Icon Container
                            _FloatingWidget(
                              child: Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Soft Outer Glow ring
                                    Container(
                                      width: 170,
                                      height: 170,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: page.glowColor,
                                            blurRadius: 40,
                                            spreadRadius: 10,
                                          )
                                        ],
                                      ),
                                    ),
                                    // Inner Glassmorphic Box
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(40),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                        child: Container(
                                          width: 140,
                                          height: 140,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(40),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.25),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Icon(
                                            page.icon,
                                            size: 64,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // Integrated Content & Control Bottom Card
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(38),
                      topRight: Radius.circular(38),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121511).withOpacity(0.45), // Modern Dark Glass look
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(38),
                            topRight: Radius.circular(38),
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
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
                                  duration: const Duration(milliseconds: 350),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: _currentPage == index ? 28 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _currentPage == index
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: _currentPage == index
                                        ? [
                                            BoxShadow(
                                              color: Colors.white.withOpacity(0.4),
                                              blurRadius: 6,
                                              offset: const Offset(0, 1),
                                            )
                                          ]
                                        : [],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Dynamic Text Content Container
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.0, 0.15),
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
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.25,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      activePage.subtitle,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 14.5,
                                        height: 1.5,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 36),

                            // Styled Primary Action Button
                            SizedBox(
                              width: double.infinity,
                              height: 56,
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
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  elevation: 4,
                                  shadowColor: activePage.primaryColor.withOpacity(0.3),
                                ),
                                child: Text(
                                  _currentPage < _pages.length - 1 ? 'Continue' : 'Get Started',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: activePage.primaryColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Already have account Log In Link
                            GestureDetector(
                              onTap: _navigateToLogin,
                              child: Text.rich(
                                TextSpan(
                                  text: 'Already have an account? ',
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withOpacity(0.65),
                                    fontSize: 13,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Log In',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
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

// Custom widget to create ambient organic glowing background blobs
class _AmbientGlowBubble extends StatelessWidget {
  final Color color;
  const _AmbientGlowBubble({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

// Helper widget to implement a fluid breathing float animation
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

    _animation = Tween<double>(begin: -10, end: 10).animate(
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
