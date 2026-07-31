import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'login_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String _selectedRole = 'farmer';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text('Choose Your Role', style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('How will you use AgriSense AI?', style: AppTheme.bodySmall),
              const SizedBox(height: 32),
              _buildRoleCard(
                id: 'farmer',
                icon: Icons.agriculture_rounded,
                title: 'Farmer',
                subtitle: 'Detect diseases & buy inputs',
                bgColor: const Color(0xFFE8F5E9),
                iconColor: AppTheme.primary,
                isSelected: _selectedRole == 'farmer',
              ),
              const SizedBox(height: 12),
              _buildRoleCard(
                id: 'dealer',
                icon: Icons.store_rounded,
                title: 'Agro-Dealer',
                subtitle: 'Sell products & grow business',
                bgColor: const Color(0xFFFFF3E0),
                iconColor: AppTheme.accent,
                isSelected: _selectedRole == 'dealer',
              ),
              const SizedBox(height: 12),
              _buildRoleCard(
                id: 'admin',
                icon: Icons.admin_panel_settings_rounded,
                title: 'Administrator',
                subtitle: 'Manage platform & content',
                bgColor: const Color(0xFFE3F2FD),
                iconColor: AppTheme.info,
                isSelected: _selectedRole == 'admin',
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(selectedRole: _selectedRole))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: Text('Continue', style: AppTheme.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color bgColor,
    required Color iconColor,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F9F0) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppTheme.primary : Colors.grey.shade200, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isSelected ? AppTheme.primary : AppTheme.textPrimary)),
                  Text(subtitle, style: AppTheme.bodySmall),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 20, height: 20,
                decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}
