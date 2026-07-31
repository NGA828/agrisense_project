import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../providers/diagnosis_provider.dart';
import '../diagnosis/diagnosis_result_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  bool _isScanning = false;
  String _selectedCrop = 'Tomato';
  final List<String> _crops = ['Tomato', 'Maize', 'Cassava', 'Pepper', 'Cocoa'];

  late final AnimationController _scanPulseController;
  late final AnimationController _scanRotateController;
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _scanPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scanRotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _scanPulseController.dispose();
    _scanRotateController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            _buildHeader(),

            // ── Content ──
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FadeTransition(
                  opacity: _fadeController,
                  child: Column(
                    children: [
                      const SizedBox(height: 24),

                      // ── Branding ──
                      _buildBranding(),
                      const SizedBox(height: 28),

                      // ── Scan Circle ──
                      _buildScanArea(),
                      const SizedBox(height: 28),

                      // ── Instructions ──
                      _buildInstructions(),
                      const SizedBox(height: 24),

                      // ── Crop Selector ──
                      _buildCropSelector(),
                      const SizedBox(height: 24),

                      // ── Action Buttons ──
                      _buildActionButtons(),
                      const SizedBox(height: 24),

                      // ── Photo Tips ──
                      _buildPhotoTips(),
                      const SizedBox(height: 32),
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

  // ─────────────────────────────────────────────
  //  HEADER
  // ─────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1B5E20),
            AppTheme.primary,
            const Color(0xFF43A047),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button
          Container(
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detect Crop Disease',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                Text(
                  'AI-powered plant health analysis',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Scan count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.analytics_rounded,
                    color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Text(
                  '38 diseases',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  BRANDING
  // ─────────────────────────────────────────────
  Widget _buildBranding() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary,
                AppTheme.primary.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.eco_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 12),
        Text(
          'AgriSense AI',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.primaryDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Smart Farming · Better Tomorrow',
          style: GoogleFonts.poppins(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  SCAN AREA
  // ─────────────────────────────────────────────
  Widget _buildScanArea() {
    final pulseScale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _scanPulseController, curve: Curves.easeInOut),
    );

    return Center(
      child: AnimatedBuilder(
        animation: pulseScale,
        builder: (context, child) {
          return Transform.scale(
            scale: _isScanning ? 1.0 : pulseScale.value,
            child: child,
          );
        },
        child: Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.6,
              colors: [
                AppTheme.primary.withOpacity(0.06),
                AppTheme.primary.withOpacity(0.03),
                Colors.transparent,
              ],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Rotating dashed ring ──
              if (_isScanning)
                AnimatedBuilder(
                  animation: _scanRotateController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _scanRotateController.value * 6.28,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primary.withOpacity(0.5),
                        width: 2,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                    ),
                    child: CustomPaint(
                      painter: _DashedCirclePainter(
                        color: AppTheme.primary.withOpacity(0.6),
                        dashWidth: 8,
                        dashGap: 6,
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),

              // ── Outer glow ring ──
              Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(
                        _isScanning ? 0.6 : 0.25),
                    width: _isScanning ? 3 : 2,
                  ),
                ),
              ),

              // ── Inner scan zone ──
              Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withOpacity(0.04),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Plant image placeholder
                    ClipOval(
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.06),
                          image: const DecorationImage(
                            image: NetworkImage(
                              'https://images.unsplash.com/photo-1574323347407-f5e1ad6d020b?w=400',
                            ),
                            fit: BoxFit.cover,
                            opacity: 0.25,
                          ),
                        ),
                      ),
                    ),

                    // ── Scan frame corners ──
                    if (!_isScanning)
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.primary.withOpacity(0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Top-left corner
                            _buildCorner(Alignment.topLeft, top: true, left: true),
                            // Top-right corner
                            _buildCorner(Alignment.topRight, top: true, right: true),
                            // Bottom-left corner
                            _buildCorner(Alignment.bottomLeft, bottom: true, left: true),
                            // Bottom-right corner
                            _buildCorner(Alignment.bottomRight, bottom: true, right: true),
                          ],
                        ),
                      ),

                    // ── Scanning animation overlay ──
                    if (_isScanning)
                      _buildScanningOverlay(),

                    // ── Center icon ──
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withOpacity(0.8),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _isScanning
                          ? Padding(
                              padding: const EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.eco_rounded,
                              color: Colors.white, size: 34),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCorner(Alignment alignment,
      {bool top = false, bool bottom = false, bool left = false, bool right = false}) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: top && left ? Radius.circular(16) : Radius.zero,
            topRight: top && right ? Radius.circular(16) : Radius.zero,
            bottomLeft: bottom && left ? Radius.circular(16) : Radius.zero,
            bottomRight: bottom && right ? Radius.circular(16) : Radius.zero,
          ),
          border: Border(
            top: top
                ? BorderSide(color: AppTheme.primary, width: 3)
                : BorderSide.none,
            bottom: bottom
                ? BorderSide(color: AppTheme.primary, width: 3)
                : BorderSide.none,
            left: left
                ? BorderSide(color: AppTheme.primary, width: 3)
                : BorderSide.none,
            right: right
                ? BorderSide(color: AppTheme.primary, width: 3)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildScanningOverlay() {
    return AnimatedBuilder(
      animation: _scanPulseController,
      builder: (context, child) {
        final progress = _scanPulseController.value;
        return ClipOval(
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              gradient: SweepGradient(
                center: Alignment.center,
                startAngle: 0,
                endAngle: 6.28,
                colors: [
                  AppTheme.primary.withOpacity(0.0),
                  AppTheme.primary.withOpacity(0.0),
                  AppTheme.primary.withOpacity(0.15 * progress),
                  AppTheme.primary.withOpacity(0.0),
                ],
                stops: const [0.0, 0.4, 0.6, 1.0],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  INSTRUCTIONS
  // ─────────────────────────────────────────────
  Widget _buildInstructions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.camera_alt_rounded,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to get best results',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Take a clear, well-lit photo of the affected part of the plant. Focus on the diseased area.',
                  style: GoogleFonts.poppins(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  CROP SELECTOR
  // ─────────────────────────────────────────────
  Widget _buildCropSelector() {
    final cropData = {
      'Tomato': {'icon': Icons.local_florist_rounded, 'color': const Color(0xFFE53935)},
      'Maize': {'icon': Icons.grain_rounded, 'color': const Color(0xFFFFB300)},
      'Cassava': {'icon': Icons.eco_rounded, 'color': const Color(0xFF43A047)},
      'Pepper': {'icon': Icons.whatshot_rounded, 'color': const Color(0xFFFF6D00)},
      'Cocoa': {'icon': Icons.coffee_rounded, 'color': const Color(0xFF5D4037)},
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Crop Type',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _crops.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final crop = _crops[index];
              final data = cropData[crop]!;
              final isSelected = crop == _selectedCrop;

              return GestureDetector(
                onTap: () => setState(() => _selectedCrop = crop),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? data['color'] as Color
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? (data['color'] as Color).withOpacity(0.3)
                          : Colors.grey.shade200,
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: (data['color'] as Color).withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        data['icon'] as IconData,
                        size: 18,
                        color: isSelected ? Colors.white : data['color'] as Color,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        crop,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  ACTION BUTTONS
  // ─────────────────────────────────────────────
  Widget _buildActionButtons() {
    return Column(
      children: [
        // Take Photo (Primary)
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppTheme.primary,
                const Color(0xFF43A047),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _isScanning ? null : _captureImage,
            icon: const Icon(Icons.camera_alt_rounded,
                color: Colors.white, size: 22),
            label: Text(
              'Take Photo',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              disabledBackgroundColor: AppTheme.primary.withOpacity(0.5),
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Upload Image (Secondary)
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
          ),
          child: OutlinedButton.icon(
            onPressed: _isScanning ? null : _pickImage,
            icon: Icon(Icons.photo_library_rounded,
                color: AppTheme.primary, size: 22),
            label: Text(
              'Upload from Gallery',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
                fontSize: 15,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.primary.withOpacity(0.5), width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: AppTheme.primary.withOpacity(0.04),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  PHOTO TIPS
  // ─────────────────────────────────────────────
  Widget _buildPhotoTips() {
    final tips = [
      {
        'icon': Icons.wb_sunny_rounded,
        'color': const Color(0xFFFF9800),
        'bg': const Color(0xFFFFF3E0),
        'title': 'Good Lighting',
        'desc': 'Shoot in natural daylight for best clarity',
      },
      {
        'icon': Icons.center_focus_strong_rounded,
        'color': const Color(0xFF2196F3),
        'bg': const Color(0xFFE3F2FD),
        'title': 'Focus on Area',
        'desc': 'Zoom into the affected leaves or stems',
      },
      {
        'icon': Icons.filter_none_rounded,
        'color': const Color(0xFF4CAF50),
        'bg': const Color(0xFFE8F5E9),
        'title': 'Single Leaf',
        'desc': 'One leaf per photo gives better results',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb_outline_rounded,
                color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Tips for Better Scanning',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: tips.map((tip) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tip['bg'] as Color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (tip['color'] as Color).withOpacity(0.15),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      tip['icon'] as IconData,
                      color: tip['color'] as Color,
                      size: 22,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tip['title'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tip['desc'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w400,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  IMAGE HANDLING
  // ─────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      _analyzeImage(bytes, pickedFile.name);
    }
  }

  Future<void> _captureImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      _analyzeImage(bytes, pickedFile.name);
    }
  }

  void _analyzeImage(List<int> imageBytes, String fileName) async {
    setState(() => _isScanning = true);
    final provider = context.read<DiagnosisProvider>();
    await provider.analyzeImage(
        Uint8List.fromList(imageBytes), fileName, _selectedCrop);
    if (mounted) {
      setState(() => _isScanning = false);
      final diagnosis = provider.currentDiagnosis;
      if (diagnosis != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DiagnosisResultScreen(
              diseaseName: diagnosis.diseaseName,
              confidence: diagnosis.confidence,
              severity:
                  diagnosis.severity.toLowerCase() == 'high' ? 78 : 45,
              cropType: _selectedCrop,
            ),
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────
//  DASHED CIRCLE PAINTER
// ─────────────────────────────────────────────
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;

  _DashedCirclePainter({
    required this.color,
    required this.dashWidth,
    required this.dashGap,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    double startAngle = 0;
    final totalAngle = 2 * 3.14159265;
    final dashAngle = dashWidth / radius;
    final gapAngle = dashGap / radius;

    while (startAngle < totalAngle) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle,
        false,
        paint,
      );
      startAngle += dashAngle + gapAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
