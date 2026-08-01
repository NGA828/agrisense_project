import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Lightweight localization for AgriSense AI.
///
/// Supports English (default) and French. Add strings here (EN + FR) and
/// reference them via `AppLocalizations.of(context).title`. Keeping it small
/// and explicit avoids the generated-code + toolchain requirements of the full
/// `flutter gen-l10n` pipeline while still shipping a real FR/EN toggle.
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<String> supportedLocales = ['en', 'fr'];

  bool get isFrench => locale.languageCode == 'fr';

  String t(String en, String fr) => isFrench ? fr : en;

  // ── App strings ──────────────────────────────────────────────────────
  String get appTitle => t('AgriSense AI', 'AgriSense IA');
  String get tagline => t('Smart Farming · Better Tomorrow',
      'Agriculture intelligente · Meilleur avenir');
  String get loadingYourFarm => t('Loading your farm...', 'Chargement de votre ferme...');

  // Auth
  String get login => t('Login', 'Connexion');
  String get logout => t('Logout', 'Déconnexion');
  String get username => t('Username', "Nom d'utilisateur");
  String get password => t('Password', 'Mot de passe');
  String get register => t('Register', "S'inscrire");
  String get farmer => t('Farmer', 'Agriculteur');
  String get dealer => t('Dealer', 'Revendeur');
  String get selectRole => t('I am a', 'Je suis');

  // Farmer
  String get dashboard => t('Dashboard', 'Tableau de bord');
  String get marketplace => t('Marketplace', 'Marché');
  String get diagnoseDisease => t('Diagnose Disease', 'Diagnostiquer une maladie');
  String get weather => t('Weather', 'Météo');
  String get chat => t('Chat', 'Discussion');
  String get history => t('History', 'Historique');
  String get buyNow => t('Buy now', 'Acheter');

  // Diagnosis
  String get takePhoto => t('Take a photo', 'Prendre une photo');
  String get gallery => t('Photo gallery', 'Galerie photos');
  String get analyze => t('Analyze', 'Analyser');
  String get healthy => t('Healthy', 'Sain');
  String get inconclusive => t('Inconclusive', 'Non concluant');
  String get consultAgronomist => t('Consult an agronomist',
      'Consulter un agronome');

  // Dealer
  String get myProducts => t('My Products', 'Mes produits');
  String get orders => t('Orders', 'Commandes');
  String get addProduct => t('Add product', 'Ajouter un produit');
  String get salesAnalytics => t('Sales Analytics', 'Analyse des ventes');

  // Admin
  String get analytics => t('Analytics', 'Analyses');
  String get userManagement => t('User Management', 'Gestion des utilisateurs');
  String get auditLog => t('Audit Log', "Journal d'audit");
  String get systemHealth => t('System Health', "Santé du système");

  // Notifications
  String get notifications => t('Notifications', 'Notifications');
  String get noNotifications => t('No notifications yet', 'Aucune notification');

  // Offline
  String get offlineMode => t('Offline mode', 'Mode hors ligne');
  String get offlineNotice => t('You are offline. Showing last saved data.',
      'Vous êtes hors ligne. Affichage des dernières données.');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
