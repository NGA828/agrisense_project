import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../services/api/api_service.dart';
import '../farmer/farmer_dashboard.dart';
import '../dealer/dealer_dashboard.dart';
import '../admin/admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  final String? selectedRole;
  
  const LoginScreen({super.key, this.selectedRole});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.gradientBackground,
        child: Stack(
          children: [
            // Floating orbs
            Positioned(
              top: -80,
              right: -40,
              child: _buildOrb(180, AppTheme.primaryLight.withOpacity(0.3)),
            ),
            Positioned(
              bottom: -120,
              left: -60,
              child: _buildOrb(250, AppTheme.primaryDark.withOpacity(0.2)),
            ),
            Positioned(
              top: 200,
              left: -100,
              child: _buildOrb(150, Colors.white.withOpacity(0.08)),
            ),
            
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      ClipOval(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.eco_rounded,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'AgriSense AI',
                        style: AppTheme.displayMedium.copyWith(
                          color: Colors.white,
                          fontSize: 28,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isLogin ? 'Welcome back!' : 'Create your account',
                        style: AppTheme.bodyMedium.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Glass card form
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                                width: 1.5,
                              ),
                            ),
                            child: Form(
                              key: _formKey,
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                child: Column(
                                  children: [
                                    // Toggle
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () => setState(() => _isLogin = true),
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 300),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                decoration: BoxDecoration(
                                                  color: _isLogin
                                                      ? Colors.white.withOpacity(0.95)
                                                      : Colors.transparent,
                                                  borderRadius: BorderRadius.circular(30),
                                                ),
                                                child: Text(
                                                  'Login',
                                                  textAlign: TextAlign.center,
                                                  style: AppTheme.bodyMedium.copyWith(
                                                    color: _isLogin
                                                        ? AppTheme.primary
                                                        : Colors.white.withOpacity(0.7),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: GestureDetector(
                                              // Admin accounts are provisioned by platform
                                              // staff, so self-registration is hidden.
                                              onTap: widget.selectedRole == 'admin'
                                                  ? null
                                                  : () => setState(() => _isLogin = false),
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 300),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                decoration: BoxDecoration(
                                                  color: !_isLogin
                                                      ? Colors.white.withOpacity(0.95)
                                                      : Colors.transparent,
                                                  borderRadius: BorderRadius.circular(30),
                                                ),
                                                child: Text(
                                                  widget.selectedRole == 'admin'
                                                      ? 'Login'
                                                      : 'Register',
                                                  textAlign: TextAlign.center,
                                                  style: AppTheme.bodyMedium.copyWith(
                                                    color: !_isLogin
                                                        ? AppTheme.primary
                                                        : Colors.white.withOpacity(0.7),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    
                                    // Register-only fields
                                    if (!_isLogin) ...[
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildGlassTextField(
                                              controller: _firstNameController,
                                              hint: 'First Name',
                                              icon: Icons.person_outline_rounded,
                                              validator: (v) => v!.isEmpty ? 'Required' : null,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildGlassTextField(
                                              controller: _lastNameController,
                                              hint: 'Last Name',
                                              icon: Icons.person_outline_rounded,
                                              validator: (v) => v!.isEmpty ? 'Required' : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      _buildGlassTextField(
                                        controller: _emailController,
                                        hint: 'Email',
                                        icon: Icons.email_outlined,
                                        keyboardType: TextInputType.emailAddress,
                                        validator: (v) {
                                          if (v!.isEmpty) return 'Required';
                                          if (!v.contains('@')) return 'Invalid email';
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      _buildGlassTextField(
                                        controller: _phoneController,
                                        hint: 'Phone Number',
                                        icon: Icons.phone_outlined,
                                        keyboardType: TextInputType.phone,
                                        validator: (v) => v!.isEmpty ? 'Required' : null,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    
                                    // Username
                                    _buildGlassTextField(
                                      controller: _usernameController,
                                      hint: 'Username',
                                      icon: Icons.person_outline_rounded,
                                      validator: (v) => v!.isEmpty ? 'Required' : null,
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    // Password
                                    _buildGlassTextField(
                                      controller: _passwordController,
                                      hint: 'Password',
                                      icon: Icons.lock_outline_rounded,
                                      obscure: _obscurePassword,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          color: Colors.white.withOpacity(0.6),
                                        ),
                                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                      ),
                                      validator: (v) {
                                        if (v!.isEmpty) return 'Required';
                                        if (v.length < 6) return 'Min 6 characters';
                                        return null;
                                      },
                                    ),
                                    
                                    // Confirm password (register only)
                                    if (!_isLogin) ...[
                                      const SizedBox(height: 16),
                                      _buildGlassTextField(
                                        controller: _confirmPasswordController,
                                        hint: 'Confirm Password',
                                        icon: Icons.lock_outline_rounded,
                                        obscure: _obscureConfirmPassword,
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscureConfirmPassword
                                                ? Icons.visibility_off_rounded
                                                : Icons.visibility_rounded,
                                            color: Colors.white.withOpacity(0.6),
                                          ),
                                          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                        ),
                                        validator: (v) {
                                          if (v != _passwordController.text) {
                                            return 'Passwords do not match';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],
                                    
                                    const SizedBox(height: 12),
                                    
                                    // Forgot password (login only)
                                    if (_isLogin)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _showPasswordResetDialog,
                                          child: Text(
                                            'Forgot Password?',
                                            style: AppTheme.bodySmall.copyWith(
                                              color: Colors.white.withOpacity(0.8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    
                                    // Submit button
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: ElevatedButton(
                                        onPressed: _isLoading ? null : _handleSubmit,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: AppTheme.primary,
                                          disabledBackgroundColor: Colors.white.withOpacity(0.5),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(30),
                                          ),
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppTheme.primary,
                                                ),
                                              )
                                            : Text(
                                                _isLogin ? 'Login' : 'Create Account',
                                                style: AppTheme.titleMedium.copyWith(
                                                  color: AppTheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                      ),
                                    ),
                                    
                                    const SizedBox(height: 16),
                                    
                                    // Role indicator
                                    if (widget.selectedRole != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          'Signing in as: ${widget.selectedRole!.toUpperCase()}',
                                          style: AppTheme.bodySmall.copyWith(
                                            color: Colors.white.withOpacity(0.8),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Demo credentials hint
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Demo Credentials',
                              style: AppTheme.bodySmall.copyWith(
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Farmer: farmer1 / password123\nDealer: dealer1 / password123\nAdmin: admin1 / password123',
                              style: AppTheme.bodySmall.copyWith(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
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
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.6), size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.error, width: 2),
        ),
        errorStyle: const TextStyle(color: AppTheme.error, fontSize: 12),
      ),
    );
  }

  Widget _buildOrb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final auth = context.read<AuthProvider>();
      
      if (_isLogin) {
        // Login through the auth provider so the app-wide session is set.
        await auth.login(_usernameController.text, _passwordController.text);
        final user = auth.currentUser;
        if (mounted && user != null) {
          _navigateToDashboard(user.role);
        }
      } else {
        // Register
        final api = ApiService();
        await api.register(
          username: _usernameController.text,
          password: _passwordController.text,
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          email: _emailController.text,
          phoneNumber: _phoneController.text,
          role: widget.selectedRole ?? 'farmer',
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.selectedRole == 'dealer'
                    ? 'Account created! Your dealer profile is pending admin verification.'
                    : 'Account created! Please login.',
              ),
              backgroundColor: AppTheme.success,
            ),
          );
          setState(() => _isLogin = true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_isLogin ? "Login" : "Registration"} failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Self-service password reset, verified by the registered phone number.
  Future<void> _showPasswordResetDialog() async {
    final username = TextEditingController();
    final phone = TextEditingController();
    final newPassword = TextEditingController();
    var submitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Reset Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your username and the phone number you registered '
                  'with. Your password will be reset immediately.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_rounded, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Registered phone number',
                    prefixIcon: Icon(Icons.phone_android_rounded, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    prefixIcon: Icon(Icons.lock_rounded, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      try {
                        await ApiService().resetPassword(
                          username: username.text.trim(),
                          phoneNumber: phone.text.trim(),
                          newPassword: newPassword.text,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password reset! You can now log in.'),
                              backgroundColor: AppTheme.success,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Reset failed: $e'),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                      }
                    },
              child: Text(submitting ? 'Resetting...' : 'Reset Password'),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDashboard(String role) {
    Widget dashboard;
    switch (role) {
      case 'dealer':
        dashboard = const DealerDashboard();
        break;
      case 'admin':
        dashboard = const AdminDashboard();
        break;
      default:
        dashboard = const FarmerDashboard();
    }
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => dashboard),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
