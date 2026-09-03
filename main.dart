import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// GLOBAL
// ============================================================
String baseUrl = 'https://ungained-comatosely-viva.ngrok-free.dev';

ValueNotifier<bool> isUzbek = ValueNotifier(true);
ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);
String tr(String uz, String ru) => isUzbek.value ? uz : ru;

Map<String, String> userData = {
  'name': '',
  'phone': '',
  'city': '',
};

// Dizayn bosqichida admin telefon orqali ajratiladi.
// Keyin bu tekshiruv server tomonidan majburiy tasdiqlanadi.
const String adminPhone = '+998995442358';
const String _catalogStorageKey = 'pixdrop_catalog_local_v1';
const String _searchStatsStorageKey = 'pixdrop_search_stats_v1';

bool get isCurrentUserAdmin =>
    (userData['phone'] ?? '').trim() == adminPhone;

Future<void> rememberProductSearch(Map data) async {
  final code = (data['code'] ?? '').toString().trim();
  final name = (data['name'] ?? '').toString().trim();
  final key = code.isNotEmpty ? code : name;
  if (key.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  Map<String, dynamic> stats = {};
  final raw = prefs.getString(_searchStatsStorageKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) stats = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }

  final current = int.tryParse('${stats[key] ?? 0}') ?? 0;
  stats[key] = current + 1;
  await prefs.setString(_searchStatsStorageKey, json.encode(stats));
}

// ============================================================
// DESIGN SYSTEM
// ============================================================
class AppColors {
  static const bg = Color(0xFF050B10);
  static const bgSoft = Color(0xFF09131B);
  static const surface = Color(0xFF0D1B24);
  static const surface2 = Color(0xFF112630);
  static const cyan = Color(0xFF31E7FF);
  static const green = Color(0xFF45F3A2);
  static const text = Color(0xFFF4F8FA);
  static const muted = Color(0xFF8497A3);
  static const danger = Color(0xFFFF6B75);
  static const lightBg = Color(0xFFF4F7F9);
  static const lightSurface = Colors.white;
  static const lightText = Color(0xFF14212A);
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyan,
        secondary: AppColors.green,
        surface: AppColors.surface,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.text,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        labelStyle: const TextStyle(color: AppColors.muted),
        hintStyle: const TextStyle(color: AppColors.muted),
        prefixIconColor: AppColors.cyan,
        suffixIconColor: AppColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withOpacity(.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.cyan, width: 1.2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface2,
        contentTextStyle: const TextStyle(color: AppColors.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0096A8),
        secondary: Color(0xFF009A64),
        surface: AppColors.lightSurface,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.lightText,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        labelStyle: const TextStyle(color: Color(0xFF6F828F)),
        hintStyle: const TextStyle(color: Color(0xFF8A9AA5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E9ED)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF0096A8), width: 1.2),
        ),
      ),
    );
  }
}

bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

Color surfaceColor(BuildContext context) =>
    isDark(context) ? AppColors.surface : AppColors.lightSurface;

Color primaryText(BuildContext context) =>
    isDark(context) ? AppColors.text : AppColors.lightText;

Color mutedText(BuildContext context) =>
    isDark(context) ? AppColors.muted : const Color(0xFF6F828F);

BoxDecoration cardDecoration(BuildContext context, {bool glow = false}) {
  return BoxDecoration(
    color: surfaceColor(context),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: isDark(context)
          ? Colors.white.withOpacity(.06)
          : const Color(0xFFE1E8EC),
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(isDark(context) ? .22 : .06),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
      if (glow)
        BoxShadow(
          color: AppColors.cyan.withOpacity(.08),
          blurRadius: 28,
          spreadRadius: 1,
        ),
    ],
  );
}

class BrandMark extends StatelessWidget {
  final double logoHeight;
  final bool centered;
  final String assetPath;
  const BrandMark({
    super.key,
    this.logoHeight = 72,
    this.centered = true,
    this.assetPath = 'assets/logo.png',
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Image.asset(
          assetPath,
          height: logoHeight,
          errorBuilder: (_, __, ___) => Container(
            width: logoHeight,
            height: logoHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [AppColors.cyan, AppColors.green],
              ),
            ),
            child: const Icon(Icons.view_in_ar_rounded,
                color: Colors.black, size: 42),
          ),
        ),
        const SizedBox(height: 10),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 31,
              fontWeight: FontWeight.w800,
              letterSpacing: -.6,
              color: primaryText(context),
            ),
            children: const [
              TextSpan(
                text: 'Pix',
                style: TextStyle(color: Color(0xFF16D9C4)),
              ),
              TextSpan(text: 'Drop'),
            ],
          ),
        ),
      ],
    );
    return content;
  }
}

class GradientButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  const GradientButton({
    super.key,
    required this.text,
    this.icon,
    required this.onPressed,
    this.height = 58,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [AppColors.cyan, AppColors.green],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withOpacity(.16),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.black87, size: 22),
                const SizedBox(width: 9),
              ],
              Text(
                text,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionTitle({super.key, required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: primaryText(context),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

// ============================================================
// AUTH / SUBSCRIPTION
// ============================================================
class AuthResult {
  final bool ok;
  final int statusCode;
  final String message;
  final Map<String, dynamic>? data;

  const AuthResult({
    required this.ok,
    required this.statusCode,
    required this.message,
    this.data,
  });
}

class AuthService {
  static const _tokenKey = 'auth_token';

  static Future<Map<String, String>> authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey) ?? '';
    return {
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
  }

  static Future<void> _saveSession(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final token = (payload['token'] ?? '').toString();
    final user = payload['user'] is Map
        ? Map<String, dynamic>.from(payload['user'] as Map)
        : <String, dynamic>{};

    if (token.isEmpty) {
      throw Exception('Server token qaytarmadi');
    }

    final name = (user['name'] ?? '').toString();
    final phone = (user['phone'] ?? '').toString();
    final city = (user['district'] ?? user['city'] ?? '').toString();

    await prefs.setString(_tokenKey, token);
    await prefs.setString('name', name);
    await prefs.setString('phone', phone);
    await prefs.setString('city', city);

    userData = {'name': name, 'phone': phone, 'city': city};
  }

  static Future<void> clearLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove('name');
    await prefs.remove('phone');
    await prefs.remove('city');
    userData = {'name': '', 'phone': '', 'city': ''};
  }

  static String _messageFromBody(String body, String fallback) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return fallback;
  }

  static Future<AuthResult> login({
    required String phone,
    required String password,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/login'),
            body: {'phone': phone.trim(), 'password': password},
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic>? data;
      try {
        final decoded = json.decode(res.body);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (res.statusCode == 200 && data != null) {
        try {
          await _saveSession(data);
        } catch (_) {
          return const AuthResult(
            ok: false,
            statusCode: 500,
            message: 'Server token qaytarmadi. Server auth patchini o‘rnating.',
          );
        }
        return AuthResult(
          ok: true,
          statusCode: 200,
          message: (data['subscription'] is Map &&
                  (data['subscription'] as Map)['warning'] != null)
              ? (data['subscription'] as Map)['warning'].toString()
              : '',
          data: data,
        );
      }

      return AuthResult(
        ok: false,
        statusCode: res.statusCode,
        message: _messageFromBody(
          res.body,
          res.statusCode == 403
              ? 'Obuna aktiv emas yoki foydalanuvchi bloklangan.'
              : 'Telefon yoki parol xato.',
        ),
        data: data,
      );
    } on TimeoutException {
      return const AuthResult(
        ok: false,
        statusCode: 0,
        message: 'Server javob bermadi. Internetni tekshiring.',
      );
    } catch (_) {
      return const AuthResult(
        ok: false,
        statusCode: 0,
        message: 'Server bilan aloqa yo‘q.',
      );
    }
  }

  static Future<AuthResult> register({
    required String name,
    required String phone,
    required String district,
    required String password,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/register'),
            body: {
              'name': name.trim(),
              'phone': phone.trim(),
              'district': district.trim(),
              'password': password,
            },
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic>? data;
      try {
        final decoded = json.decode(res.body);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      return AuthResult(
        ok: res.statusCode == 200,
        statusCode: res.statusCode,
        message: data?['message']?.toString() ??
            (res.statusCode == 200
                ? 'Ro‘yxatdan o‘tildi.'
                : 'Ro‘yxatdan o‘tishda xatolik.'),
        data: data,
      );
    } on TimeoutException {
      return const AuthResult(
        ok: false,
        statusCode: 0,
        message: 'Server javob bermadi. Internetni tekshiring.',
      );
    } catch (_) {
      return const AuthResult(
        ok: false,
        statusCode: 0,
        message: 'Server bilan aloqa yo‘q.',
      );
    }
  }

  static Future<AuthResult> checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      return const AuthResult(
        ok: false,
        statusCode: 401,
        message: 'Tizimga kirish kerak.',
      );
    }

    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/auth/check'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic>? data;
      try {
        final decoded = json.decode(res.body);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (res.statusCode == 200 && data != null) {
        final user = data['user'] is Map
            ? Map<String, dynamic>.from(data['user'] as Map)
            : <String, dynamic>{};
        final name = (user['name'] ?? prefs.getString('name') ?? '').toString();
        final phone = (user['phone'] ?? prefs.getString('phone') ?? '').toString();
        final city = (user['district'] ??
                user['city'] ??
                prefs.getString('city') ??
                '')
            .toString();
        userData = {'name': name, 'phone': phone, 'city': city};
        await prefs.setString('name', name);
        await prefs.setString('phone', phone);
        await prefs.setString('city', city);

        final subscription = data['subscription'] is Map
            ? Map<String, dynamic>.from(data['subscription'] as Map)
            : <String, dynamic>{};
        return AuthResult(
          ok: true,
          statusCode: 200,
          message: subscription['warning']?.toString() ?? '',
          data: data,
        );
      }

      if (res.statusCode == 401 || res.statusCode == 403) {
        await clearLocalSession();
      }

      return AuthResult(
        ok: false,
        statusCode: res.statusCode,
        message: _messageFromBody(
          res.body,
          res.statusCode == 403
              ? 'Obuna muddati tugagan yoki akkaunt bloklangan.'
              : 'Sessiya tugagan. Qayta kiring.',
        ),
        data: data,
      );
    } on TimeoutException {
      return const AuthResult(
        ok: false,
        statusCode: 0,
        message: 'Server javob bermadi. Internetni tekshiring.',
      );
    } catch (_) {
      return const AuthResult(
        ok: false,
        statusCode: 0,
        message: 'Server bilan aloqa yo‘q.',
      );
    }
  }

  static Future<void> logout() async {
    try {
      final headers = await authHeaders();
      await http
          .post(Uri.parse('$baseUrl/logout'), headers: headers)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    await clearLocalSession();
  }
}

// ============================================================
// APP
// ============================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PixDropApp());
}

class PixDropApp extends StatelessWidget {
  const PixDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, currentTheme, __) => ValueListenableBuilder<bool>(
        valueListenable: isUzbek,
        builder: (_, __, ___) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PixDrop',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: currentTheme,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<AuthResult> _future;

  @override
  void initState() {
    super.initState();
    _future = AuthService.checkSession();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupPage();
        }

        final result = snapshot.data;
        if (result != null && result.ok) {
          return SessionGuard(initialWarning: result.message);
        }

        return LoginPage(
          initialMessage: result != null && result.statusCode == 403
              ? result.message
              : null,
        );
      },
    );
  }
}

class _StartupPage extends StatelessWidget {
  const _StartupPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(logoHeight: 90),
            const SizedBox(height: 28),
            const CircularProgressIndicator(color: AppColors.cyan),
            const SizedBox(height: 14),
            Text(
              tr('Obuna tekshirilmoqda...', 'Проверка подписки...'),
              style: TextStyle(color: mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class SessionGuard extends StatefulWidget {
  final String initialWarning;
  const SessionGuard({super.key, this.initialWarning = ''});

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard>
    with WidgetsBindingObserver {
  Timer? _timer;
  String _lastWarning = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialWarning.isNotEmpty) _showWarning(widget.initialWarning);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _showWarning(String text) {
    if (!mounted || text.isEmpty || text == _lastWarning) return;
    _lastWarning = text;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    final result = await AuthService.checkSession();
    _checking = false;
    if (!mounted) return;

    if (result.ok) {
      _showWarning(result.message);
      return;
    }

    if (result.statusCode == 401 || result.statusCode == 403) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginPage(initialMessage: result.message),
        ),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) => const HomePage();
}

// ============================================================
// LOGIN
// ============================================================
class LoginPage extends StatefulWidget {
  final String? initialMessage;
  const LoginPage({super.key, this.initialMessage});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;
  bool _initialShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialShown && (widget.initialMessage ?? '').isNotEmpty) {
        _initialShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.initialMessage!)),
        );
      }
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validPhone(String phone) => RegExp(r'^\+998\d{9}$').hasMatch(phone);

  Future<void> _login() async {
    final phone = _phone.text.trim();
    final password = _password.text;

    if (!_validPhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Telefon: +998901234567 formatida bo‘lsin', 'Телефон: формат +998901234567'))),
      );
      return;
    }
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Parolni kiriting', 'Введите пароль'))),
      );
      return;
    }

    setState(() => _loading = true);
    final result = await AuthService.login(phone: phone, password: password);
    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => SessionGuard(initialWarning: result.message),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -90,
            right: -75,
            child: _GlowOrb(color: AppColors.cyan.withOpacity(.13), size: 250),
          ),
          Positioned(
            bottom: -120,
            left: -100,
            child: _GlowOrb(color: AppColors.green.withOpacity(.10), size: 280),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    children: [
                      const BrandMark(logoHeight: 76),
                      const SizedBox(height: 12),
                      Text(
                        tr('Mahsulotni tez toping', 'Находите товары быстрее'),
                        style: TextStyle(color: mutedText(context), fontSize: 15),
                      ),
                      const SizedBox(height: 34),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: cardDecoration(context, glow: true),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Tizimga kirish', 'Вход в систему'),
                              style: TextStyle(
                                color: primaryText(context),
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr('Telefon raqam va parolingizni kiriting',
                                  'Введите номер телефона и пароль'),
                              style: TextStyle(color: mutedText(context), fontSize: 14),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: tr('Telefon raqam', 'Номер телефона'),
                                hintText: '+998901234567',
                                prefixIcon: const Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _password,
                              obscureText: _hidePassword,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) {
                                if (!_loading) _login();
                              },
                              decoration: InputDecoration(
                                labelText: tr('Parol', 'Пароль'),
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                  icon: Icon(_hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            _loading
                                ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                                : GradientButton(
                                    text: tr('KIRISH', 'ВОЙТИ'),
                                    icon: Icons.arrow_forward_rounded,
                                    onPressed: _login,
                                  ),
                            const SizedBox(height: 14),
                            Center(
                              child: TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const RegisterPage()),
                                        ),
                                child: Text(
                                  tr('Ro‘yxatdan o‘tish', 'Регистрация'),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        tr('PixDrop • Inventory Assistant', 'PixDrop • Inventory Assistant'),
                        style: TextStyle(color: mutedText(context), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _district = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _district.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validPhone(String phone) => RegExp(r'^\+998\d{9}$').hasMatch(phone);

  Future<void> _register() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final district = _district.text.trim();
    final password = _password.text;

    if (name.isEmpty || district.isEmpty || password.isEmpty || !_validPhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(
            'Barcha maydonlarni to‘g‘ri to‘ldiring. Telefon +998901234567 formatida.',
            'Заполните все поля. Телефон в формате +998901234567.',
          )),
        ),
      );
      return;
    }
    if (password.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Parol kamida 4 ta belgidan iborat bo‘lsin', 'Пароль минимум 4 символа'))),
      );
      return;
    }

    setState(() => _loading = true);
    final result = await AuthService.register(
      name: name,
      phone: phone,
      district: district,
      password: password,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    if (result.ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Ro‘yxatdan o‘tish', 'Регистрация'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: cardDecoration(context, glow: true),
                child: Column(
                  children: [
                    const BrandMark(logoHeight: 62),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: tr('Ism Familiya', 'Имя Фамилия'),
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: tr('Telefon raqam', 'Номер телефона'),
                        hintText: '+998901234567',
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _district,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: tr('Tuman / Shahar', 'Район / Город'),
                        prefixIcon: const Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_loading) _register();
                      },
                      decoration: InputDecoration(
                        labelText: tr('Parol', 'Пароль'),
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _loading
                        ? const CircularProgressIndicator(color: AppColors.cyan)
                        : GradientButton(
                            text: tr('RO‘YXATDAN O‘TISH', 'ЗАРЕГИСТРИРОВАТЬСЯ'),
                            icon: Icons.person_add_alt_1_rounded,
                            onPressed: _register,
                          ),
                    const SizedBox(height: 14),
                    Text(
                      tr(
                        'Ro‘yxatdan o‘tgach, admin obunani yoqishi kerak.',
                        'После регистрации администратор должен активировать подписку.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedText(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 40)],
      ),
    );
  }
}

// ============================================================
// HOME
// ============================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _products = [];
  bool _loadingProducts = true;

  @override
  void initState() {
    super.initState();
    _loadHomeProducts();
  }

  Future<void> _loadHomeProducts() async {
    if (mounted) setState(() => _loadingProducts = true);
    try {
      final phone = Uri.encodeQueryComponent(userData['phone'] ?? '');
      final headers = await AuthService.authHeaders();
      final res = await http.get(
        Uri.parse('$baseUrl/products?shop_id=$phone'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        final List<Map<String, dynamic>> items = decoded is List
            ? decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];

        final prefs = await SharedPreferences.getInstance();
        Map<String, dynamic> stats = {};
        final raw = prefs.getString(_searchStatsStorageKey);
        if (raw != null && raw.isNotEmpty) {
          try {
            final d = json.decode(raw);
            if (d is Map) stats = Map<String, dynamic>.from(d);
          } catch (_) {}
        }

        int countFor(Map<String, dynamic> p) {
          final code = (p['code'] ?? '').toString().trim();
          final name = (p['name'] ?? '').toString().trim();
          final key = code.isNotEmpty ? code : name;
          return int.tryParse('${stats[key] ?? 0}') ?? 0;
        }

        items.sort((a, b) {
          final bySearch = countFor(b).compareTo(countFor(a));
          if (bySearch != 0) return bySearch;
          return (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase());
        });

        if (mounted) {
          setState(() {
            _products = items.take(5).toList();
            _loadingProducts = false;
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) setState(() => _loadingProducts = false);
  }

  Future<void> _openPage(Widget page, {bool refreshAfter = false}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (refreshAfter && mounted) _loadHomeProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: AppColors.cyan,
                onRefresh: _loadHomeProducts,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  children: [
                    const SizedBox(height: 6),
                    const Center(
                      child: BrandMark(
                        logoHeight: 150,
                        assetPath: 'assets/home_logo_dark.png',
                      ),
                    ),
                    const SizedBox(height: 34),
                    if (_loadingProducts)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 70),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.cyan,
                          ),
                        ),
                      )
                    else if (_products.isEmpty)
                      _HomeEmptyProducts(
                        onAdd: () => _openPage(
                          const AddProductPage(),
                          refreshAfter: true,
                        ),
                      )
                    else
                      ..._products.map(
                        (product) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _HomeProductCard(
                            product: product,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductDetailPage(
                                    product: product,
                                  ),
                                ),
                              );
                              _loadHomeProducts();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: _PixBottomMenu(
                onSettings: () => _openPage(const SettingsPage()),
                onCatalog: () => _openPage(const CatalogPage()),
                onScan: () => _openPage(const ScanPage()),
                onAdd: () => _openPage(
                  const AddProductPage(),
                  refreshAfter: true,
                ),
                onWarehouse: () => _openPage(
                  const ProductsPage(),
                  refreshAfter: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeEmptyProducts extends StatelessWidget {
  final VoidCallback onAdd;
  const _HomeEmptyProducts({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: const Color(0xFF071A24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF00D7C2).withOpacity(.22)),
      ),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined,
              color: Color(0xFF16D9C4), size: 46),
          const SizedBox(height: 12),
          Text(
            tr('Omborda mahsulot yo‘q', 'На складе пока нет товаров'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primaryText(context),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Mahsulot qo‘shilgach shu yerda ko‘rinadi.',
                'После добавления товары появятся здесь.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText(context)),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Mahsulot qo‘shish', 'Добавить товар')),
          ),
        ],
      ),
    );
  }
}

class _HomeProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  const _HomeProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (product['name'] ?? '—').toString();
    final code = (product['code'] ?? '—').toString();
    final price = (product['price'] ?? '0').toString();
    final quantity = product['quantity'] ?? product['qty'];
    final date = product['created_at'] ?? product['date'];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          minHeight: 118,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF06212A), Color(0xFF081A25)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF00CFC1).withOpacity(.24),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00CFC1).withOpacity(.04),
                blurRadius: 18,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ProductImageBox(product: product, size: 86),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primaryText(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${tr('Art', 'Арт')}: $code',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mutedText(context),
                        fontSize: 14,
                      ),
                    ),
                    if (quantity != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        '${tr('Soni', 'Кол-во')}: $quantity ${tr('ta', 'шт.')}',
                        style: TextStyle(
                          color: mutedText(context),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$price ${tr("so‘m", "сум")}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: primaryText(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (date != null)
                    Text(
                      _shortDate(date.toString()),
                      style: TextStyle(
                        color: mutedText(context),
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _shortDate(String value) {
    try {
      final dt = DateTime.parse(value);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return value.length >= 10 ? value.substring(0, 10) : value;
    }
  }
}

class _ProductImageBox extends StatelessWidget {
  final Map<String, dynamic> product;
  final double size;
  const _ProductImageBox({required this.product, this.size = 74});

  @override
  Widget build(BuildContext context) {
    final raw = (product['image_url'] ?? product['image_path'] ?? '').toString();
    Widget image;

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      image = Image.network(
        raw,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    } else if (raw.isNotEmpty && File(raw).existsSync()) {
      image = Image.file(File(raw), fit: BoxFit.contain);
    } else if (raw.isNotEmpty) {
      final normalized = raw.startsWith('/') ? raw.substring(1) : raw;
      image = Image.network(
        '$baseUrl/$normalized',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    } else {
      image = _fallback();
    }

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: image,
      ),
    );
  }

  Widget _fallback() => const Center(
        child: Icon(Icons.inventory_2_outlined,
            color: Color(0xFF5A7180), size: 34),
      );
}

class _PixBottomMenu extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onCatalog;
  final VoidCallback onScan;
  final VoidCallback onAdd;
  final VoidCallback onWarehouse;

  const _PixBottomMenu({
    required this.onSettings,
    required this.onCatalog,
    required this.onScan,
    required this.onAdd,
    required this.onWarehouse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF071A24),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFF00D7C2).withOpacity(.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.28),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _BottomMenuItem(
            icon: Icons.settings_outlined,
            label: tr('Sozlama', 'Настройки'),
            onTap: onSettings,
          ),
          _BottomMenuItem(
            icon: Icons.folder_open_outlined,
            label: tr('Katalog', 'Каталог'),
            onTap: onCatalog,
          ),
          _BottomMenuItem(
            icon: Icons.center_focus_strong_outlined,
            label: tr('Skaner', 'Сканер'),
            onTap: onScan,
            active: true,
          ),
          _BottomMenuItem(
            icon: Icons.add_rounded,
            label: tr('Yuk qo‘shish', 'Добавить'),
            onTap: onAdd,
            filled: true,
          ),
          _BottomMenuItem(
            icon: Icons.view_in_ar_outlined,
            label: tr('Ombor', 'Склад'),
            onTap: onWarehouse,
          ),
        ],
      ),
    );
  }
}

class _BottomMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool active;

  const _BottomMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: filled
                    ? const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF17E2D2), Color(0xFF00B9A7)],
                        ),
                      )
                    : null,
                child: Icon(
                  icon,
                  color: filled
                      ? Colors.white
                      : active
                          ? const Color(0xFF00E6D2)
                          : const Color(0xFF76A9B4),
                  size: filled ? 29 : 30,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: active
                        ? const Color(0xFF00E6D2)
                        : const Color(0xFF76A9B4),
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surfaceColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark(context)
                  ? Colors.white.withOpacity(.07)
                  : const Color(0xFFE0E8EC),
            ),
          ),
          child: Icon(icon, color: AppColors.cyan),
        ),
      ),
    );
  }
}

class _ScanHeroCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanHeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF13CFE4), Color(0xFF22D99A)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withOpacity(.18),
            blurRadius: 34,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              Positioned(
                right: -35,
                top: -30,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(.10),
                  ),
                ),
              ),
              Positioned(
                left: -40,
                bottom: -55,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(.05),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(.13),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: const Icon(Icons.center_focus_strong_rounded,
                          color: Colors.white, size: 30),
                    ),
                    const Spacer(),
                    Text(
                      tr('Mahsulotni skan qiling', 'Сканировать товар'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('Kamera orqali mahsulotni tez aniqlash',
                          'Быстрый поиск товара через камеру'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(.78),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          tr('Boshlash', 'Начать'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 20),
                      ],
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
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          height: 142,
          padding: const EdgeInsets.all(18),
          decoration: cardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: AppColors.cyan.withOpacity(.10),
                ),
                child: Icon(icon, color: AppColors.cyan, size: 24),
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  color: primaryText(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mutedText(context), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoStrip({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(context),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.green.withOpacity(.10),
            ),
            child: const Icon(Icons.auto_awesome_outlined, color: AppColors.green),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: primaryText(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: mutedText(context), fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SCAN
// ============================================================
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with SingleTickerProviderStateMixin {
  File? _img;
  bool _loading = true;
  Map? _res;
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanDirectly());
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanDirectly() async {
    final p = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );

    if (p == null) {
      if (mounted && _img == null) Navigator.pop(context);
      return;
    }

    setState(() {
      _img = File(p.path);
      _loading = true;
      _res = null;
    });

    try {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/predict'));
      req.headers.addAll(await AuthService.authHeaders());
      req.fields['shop_id'] = userData['phone'] ?? '';
      req.files.add(await http.MultipartFile.fromPath('image', p.path));
      final res = await req.send();

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(await res.stream.bytesToString());
        setState(() {
          _res = data;
          _loading = false;
        });
        await rememberProductSearch(Map<String, dynamic>.from(data));
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Skan natijasi', 'Результат сканирования'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: _loading ? _loadingView(context) : _resultView(context),
        ),
      ),
    );
  }

  Widget _loadingView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              RotationTransition(
                turns: _animCtrl,
                child: Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cyan.withOpacity(.25), width: 2),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    colors: [AppColors.cyan, AppColors.green],
                  ),
                ),
                child: const Icon(Icons.center_focus_strong_rounded,
                    color: Colors.black87, size: 38),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            tr('Mahsulot qidirilmoqda...', 'Ищем товар...'),
            style: TextStyle(
              color: primaryText(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Rasm AI orqali tahlil qilinmoqda', 'Изображение анализируется AI'),
            style: TextStyle(color: mutedText(context)),
          ),
        ],
      ),
    );
  }

  Widget _resultView(BuildContext context) {
    if (_res == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 58),
            const SizedBox(height: 15),
            Text(
              tr('Xatolik yuz berdi', 'Произошла ошибка'),
              style: TextStyle(
                color: primaryText(context),
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              child: GradientButton(
                text: tr('Qayta urinish', 'Повторить'),
                icon: Icons.refresh_rounded,
                onPressed: _scanDirectly,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 285,
                  padding: const EdgeInsets.all(12),
                  decoration: cardDecoration(context, glow: true),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _img == null
                        ? const Center(child: Icon(Icons.image_outlined))
                        : Image.file(_img!, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: cardDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: AppColors.green.withOpacity(.10),
                            ),
                            child: Text(
                              tr('TOPILDI', 'НАЙДЕНО'),
                              style: const TextStyle(
                                color: AppColors.green,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: .7,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _res!['name'] ?? tr('Topilmadi', 'Не найдено'),
                        style: TextStyle(
                          color: primaryText(context),
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _DetailRow(
                        icon: Icons.payments_outlined,
                        label: tr('Narxi', 'Цена'),
                        value: "${_res!['price'] ?? '0'} UZS",
                        accent: AppColors.green,
                      ),
                      const SizedBox(height: 12),
                      _DetailRow(
                        icon: Icons.qr_code_2_rounded,
                        label: tr('Artikul', 'Артикул'),
                        value: _res!['code'] ?? '—',
                        accent: AppColors.cyan,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        GradientButton(
          text: tr('Qayta skan qilish', 'Сканировать снова'),
          icon: Icons.refresh_rounded,
          onPressed: _scanDirectly,
          height: 62,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withOpacity(.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: accent, size: 22),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: mutedText(context), fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: primaryText(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PRODUCTS
// ============================================================
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  List _items = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    try {
      final headers = await AuthService.authHeaders();
      final res = await http.get(
        Uri.parse('$baseUrl/products?shop_id=${Uri.encodeQueryComponent(userData['phone'] ?? '')}'),
        headers: headers,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _items = json.decode(res.body);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      final name = '${item['name'] ?? ''}'.toLowerCase();
      final code = '${item['code'] ?? ''}'.toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Mahsulotlar', 'Товары'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddProductPage()),
                );
                setState(() => _loading = true);
                _fetchProducts();
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: tr('Nomi yoki artikul bo‘yicha qidirish',
                      'Поиск по названию или артикулу'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => setState(() => _search = ''),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.cyan),
                    )
                  : _filtered.isEmpty
                      ? _EmptyProducts(onAdd: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AddProductPage()),
                          );
                          setState(() => _loading = true);
                          _fetchProducts();
                        })
                      : RefreshIndicator(
                          color: AppColors.cyan,
                          onRefresh: _fetchProducts,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 11),
                            itemBuilder: (_, i) {
                              final item = _filtered[i];
                              return _ProductTile(
                                item: item,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ProductDetailPage(product: item),
                                    ),
                                  );
                                  setState(() => _loading = true);
                                  _fetchProducts();
                                },
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Map item;
  final VoidCallback onTap;
  const _ProductTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: cardDecoration(context),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppColors.cyan, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['name'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primaryText(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item['code'] ?? '—'}',
                      style: TextStyle(color: mutedText(context), fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${item['price'] ?? '0'}',
                    style: const TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('UZS', style: TextStyle(color: mutedText(context), fontSize: 11)),
                  const SizedBox(height: 7),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.cyan, size: 21),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyProducts({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan.withOpacity(.08),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  color: AppColors.cyan, size: 42),
            ),
            const SizedBox(height: 20),
            Text(
              tr('Mahsulot topilmadi', 'Товары не найдены'),
              style: TextStyle(
                color: primaryText(context),
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Yangi mahsulot qo‘shing yoki qidiruvni o‘zgartiring.',
                  'Добавьте товар или измените поисковый запрос.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText(context)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 240,
              child: GradientButton(
                text: tr('Mahsulot qo‘shish', 'Добавить товар'),
                icon: Icons.add_rounded,
                onPressed: onAdd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PRODUCT DETAIL
// ============================================================
class ProductDetailPage extends StatefulWidget {
  final Map product;
  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final _priceCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _priceCtrl.text = '${widget.product['price'] ?? ''}';
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _updatePrice() async {
    if (_priceCtrl.text.trim().isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final headers = await AuthService.authHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/update_price'),
        headers: headers,
        body: {
          'shop_id': userData['phone'] ?? '',
          'kod': '${widget.product['code'] ?? ''}',
          'yangi_narx': _priceCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Narx yangilandi!', 'Цена обновлена!'))),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Saqlashda xatolik', 'Ошибка сохранения'))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Server bilan aloqa yo‘q', 'Нет связи с сервером'))),
      );
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Mahsulotni o‘chirish?', 'Удалить товар?')),
        content: Text(tr('Bu amalni ortga qaytarib bo‘lmaydi.',
            'Это действие нельзя отменить.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Bekor qilish', 'Отмена')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              tr('O‘chirish', 'Удалить'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (yes != true) return;
    setState(() => _isLoading = true);

    try {
      final headers = await AuthService.authHeaders();
      await http.post(
        Uri.parse('$baseUrl/delete_product'),
        headers: headers,
        body: {
          'shop_id': userData['phone'] ?? '',
          'kod': '${widget.product['code'] ?? ''}',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('O‘chirildi!', 'Удалено!')),
          backgroundColor: AppColors.danger,
        ),
      );
      Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Mahsulot', 'Товар'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: cardDecoration(context, glow: true),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withOpacity(.10),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.inventory_2_outlined,
                                color: AppColors.cyan, size: 28),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '${widget.product['name'] ?? ''}',
                            style: TextStyle(
                              color: primaryText(context),
                              fontWeight: FontWeight.w900,
                              fontSize: 24,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.product['code'] ?? '—'}',
                            style: TextStyle(color: mutedText(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      tr('Narxni tahrirlash', 'Изменить цену'),
                      style: TextStyle(
                        color: primaryText(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: tr('Yangi narx (UZS)', 'Новая цена (UZS)'),
                        prefixIcon: const Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 22),
                    GradientButton(
                      text: tr('Narxni saqlash', 'Сохранить цену'),
                      icon: Icons.check_rounded,
                      onPressed: _updatePrice,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(tr('Mahsulotni o‘chirish', 'Удалить товар')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: BorderSide(color: AppColors.danger.withOpacity(.55)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ============================================================
// ADD PRODUCT
// ============================================================
class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _n = TextEditingController();
  final _p = TextEditingController();
  final _c = TextEditingController();
  final List<File?> _f = [null, null, null];
  bool _saving = false;

  @override
  void dispose() {
    _n.dispose();
    _p.dispose();
    _c.dispose();
    super.dispose();
  }

  Future<void> _pickImage(int index) async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );
    if (x != null && mounted) setState(() => _f[index] = File(x.path));
  }

  Future<void> _save() async {
    if (_n.text.trim().isEmpty || _p.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Nom va narxni kiriting', 'Введите название и цену'))),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/add_product'));
      req.headers.addAll(await AuthService.authHeaders());
      req.fields.addAll({
        'name': _n.text.trim(),
        'price': _p.text.trim(),
        'code': _c.text.trim().isEmpty
            ? 'SKU-${DateTime.now().millisecondsSinceEpoch}'
            : _c.text.trim(),
        'shop_id': userData['phone'] ?? '',
      });

      for (final x in _f) {
        if (x != null) {
          req.files.add(await http.MultipartFile.fromPath('images', x.path));
        }
      }

      final response = await req.send();
      if (!mounted) return;

      if (response.statusCode == 200) {
        Navigator.pop(context);
      } else {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Xatolik yuz berdi!', 'Произошла ошибка!'))),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Server bilan aloqa yo‘q', 'Нет связи с сервером'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Yangi mahsulot', 'Новый товар'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Mahsulot rasmlari', 'Фотографии товара'),
                style: TextStyle(
                  color: primaryText(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('3 tagacha rasm olish mumkin', 'Можно добавить до 3 фото'),
                style: TextStyle(color: mutedText(context), fontSize: 13),
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 2 ? 0 : 10),
                      child: _PhotoSlot(
                        file: _f[i],
                        index: i,
                        onTap: () => _pickImage(i),
                        onRemove: () => setState(() => _f[i] = null),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 28),
              Text(
                tr('Asosiy ma’lumotlar', 'Основные данные'),
                style: TextStyle(
                  color: primaryText(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 13),
              TextField(
                controller: _n,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: tr('Mahsulot nomi', 'Название товара'),
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 13),
              TextField(
                controller: _p,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: tr('Narx (UZS)', 'Цена (UZS)'),
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 13),
              TextField(
                controller: _c,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: tr('Artikul', 'Артикул'),
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                ),
              ),
              const SizedBox(height: 28),
              _saving
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.cyan),
                    )
                  : GradientButton(
                      text: tr('Mahsulotni saqlash', 'Сохранить товар'),
                      icon: Icons.check_circle_outline_rounded,
                      onPressed: _save,
                      height: 62,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final File? file;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PhotoSlot({
    required this.file,
    required this.index,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: .9,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: surfaceColor(context),
                    border: Border.all(
                      color: file == null
                          ? (isDark(context)
                              ? Colors.white.withOpacity(.07)
                              : const Color(0xFFE0E8EC))
                          : AppColors.cyan.withOpacity(.7),
                    ),
                  ),
                  child: file == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo_outlined,
                                color: AppColors.cyan, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: mutedText(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(19),
                          child: Image.file(file!, fit: BoxFit.cover),
                        ),
                ),
              ),
            ),
          ),
          if (file != null)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.68),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 17),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// SETTINGS
// ============================================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = themeMode.value == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Sozlamalar', 'Настройки'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: cardDecoration(context, glow: true),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.cyan, AppColors.green],
                      ),
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: Colors.black87, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userData['name']?.isNotEmpty == true
                              ? userData['name']!
                              : tr('Foydalanuvchi', 'Пользователь'),
                          style: TextStyle(
                            color: primaryText(context),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userData['phone'] ?? '',
                          style: TextStyle(color: mutedText(context), fontSize: 13),
                        ),
                        if (userData['city']?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            userData['city']!,
                            style: TextStyle(color: mutedText(context), fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              tr('Ilova', 'Приложение'),
              style: TextStyle(
                color: mutedText(context),
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: cardDecoration(context),
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    value: dark,
                    onChanged: (v) {
                      themeMode.value = v ? ThemeMode.dark : ThemeMode.light;
                      setState(() {});
                    },
                    activeColor: AppColors.cyan,
                    secondary: const Icon(Icons.dark_mode_outlined, color: AppColors.cyan),
                    title: Text(
                      tr('Tungi rejim', 'Тёмная тема'),
                      style: TextStyle(
                        color: primaryText(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      tr('Dark / Light ko‘rinish', 'Тёмное / светлое оформление'),
                      style: TextStyle(color: mutedText(context), fontSize: 12),
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark(context)
                        ? Colors.white.withOpacity(.06)
                        : const Color(0xFFE5ECEF),
                  ),
                  SwitchListTile.adaptive(
                    value: isUzbek.value,
                    onChanged: (v) {
                      isUzbek.value = v;
                      setState(() {});
                    },
                    activeColor: AppColors.green,
                    secondary: const Icon(Icons.language_rounded, color: AppColors.green),
                    title: Text(
                      isUzbek.value ? 'Til: O‘zbekcha' : 'Язык: Русский',
                      style: TextStyle(
                        color: primaryText(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      isUzbek.value ? 'UZ ↔ RU' : 'RU ↔ UZ',
                      style: TextStyle(color: mutedText(context), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: cardDecoration(context),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withOpacity(.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.support_agent_rounded,
                        color: AppColors.cyan),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Yordam', 'Поддержка'),
                          style: TextStyle(
                            color: primaryText(context),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr('Muammo bo‘lsa Telegram orqali yozing:',
                              'Если возникла проблема, напишите в Telegram:'),
                          style: TextStyle(color: mutedText(context), fontSize: 12.5),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '@Jahongir_444',
                          style: TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: Text(tr('Hisobdan chiqish', 'Выйти из аккаунта')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withOpacity(.45)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                'PixDrop • v1.0',
                style: TextStyle(color: mutedText(context), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ============================================================
// CATALOG — UI PROTOTYPE
// Server ulanmaguncha katalog shu qurilmada vaqtincha saqlanadi.
// Admin uchun qo‘shish/tahrirlash/o‘chirish, mijoz uchun faqat ko‘rish.
// ============================================================
class CatalogItem {
  final String id;
  final String name;
  final String price;
  final String code;
  final List<String> images;
  final String updatedAt;

  const CatalogItem({
    required this.id,
    required this.name,
    required this.price,
    required this.code,
    required this.images,
    required this.updatedAt,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> jsonMap) {
    return CatalogItem(
      id: (jsonMap['id'] ?? '').toString(),
      name: (jsonMap['name'] ?? '').toString(),
      price: (jsonMap['price'] ?? '').toString(),
      code: (jsonMap['code'] ?? '').toString(),
      images: (jsonMap['images'] is List)
          ? List<String>.from(jsonMap['images'].map((e) => e.toString()))
          : <String>[],
      updatedAt: (jsonMap['updatedAt'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'code': code,
        'images': images,
        'updatedAt': updatedAt,
      };

  CatalogItem copyWith({
    String? id,
    String? name,
    String? price,
    String? code,
    List<String>? images,
    String? updatedAt,
  }) {
    return CatalogItem(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      code: code ?? this.code,
      images: images ?? this.images,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

Future<List<CatalogItem>> _loadLocalCatalog() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_catalogStorageKey);
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = json.decode(raw);
    if (decoded is! List) return [];
    final items = decoded
        .map((e) => CatalogItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    items.sort(_catalogAlphabeticalSort);
    return items;
  } catch (_) {
    return [];
  }
}

Future<void> _saveLocalCatalog(List<CatalogItem> items) async {
  final prefs = await SharedPreferences.getInstance();
  final sorted = [...items]..sort(_catalogAlphabeticalSort);
  await prefs.setString(
    _catalogStorageKey,
    json.encode(sorted.map((e) => e.toJson()).toList()),
  );
}

int _catalogAlphabeticalSort(CatalogItem a, CatalogItem b) =>
    a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase());

String _firstCatalogLetter(String name) {
  final n = name.trim();
  if (n.isEmpty) return '#';
  return n.substring(0, 1).toUpperCase();
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final TextEditingController _search = TextEditingController();
  List<CatalogItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final data = await _loadLocalCatalog();
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  List<CatalogItem> get _filtered {
    final q = _search.text.trim().toLowerCase();
    final sorted = [..._items]..sort(_catalogAlphabeticalSort);
    if (q.isEmpty) return sorted;

    // Bitta harf yozilsa — aynan shu harf bilan boshlanuvchilar.
    if (q.length == 1) {
      return sorted.where((e) => e.name.trim().toLowerCase().startsWith(q)).toList();
    }

    // To‘liq yoki qisman nom yozilsa — nom ichidan qidiriladi.
    return sorted.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _openAdd() async {
    if (!isCurrentUserAdmin) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CatalogEditPage()),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Katalog', 'Каталог'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              isCurrentUserAdmin
                  ? tr('Admin rejimi', 'Режим администратора')
                  : tr('Faqat ko‘rish', 'Только просмотр'),
              style: TextStyle(
                color: isCurrentUserAdmin ? AppColors.green : mutedText(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          if (isCurrentUserAdmin)
            IconButton(
              tooltip: tr('Katalogga mahsulot qo‘shish', 'Добавить в каталог'),
              onPressed: _openAdd,
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.green),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: tr(
                  'Mahsulot nomi yoki bosh harfini yozing...',
                  'Введите название или первую букву...',
                ),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF18D9C3)),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF071A24),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: const Color(0xFF00D7C2).withOpacity(.22),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: Color(0xFF00D7C2),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            child: Row(
              children: [
                Text(
                  '${tr('Topildi', 'Найдено')}: ${filtered.length}',
                  style: TextStyle(color: mutedText(context), fontSize: 12),
                ),
                const Spacer(),
                const Icon(Icons.sort_by_alpha_rounded,
                    color: Color(0xFF18D9C3), size: 18),
                const SizedBox(width: 6),
                Text(
                  tr('A → Z', 'А → Я'),
                  style: const TextStyle(
                    color: Color(0xFF18D9C3),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.cyan),
                  )
                : filtered.isEmpty
                    ? _CatalogEmpty(isAdmin: isCurrentUserAdmin, onAdd: _openAdd)
                    : RefreshIndicator(
                        color: AppColors.cyan,
                        onRefresh: _reload,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final previousLetter = index == 0
                                ? null
                                : _firstCatalogLetter(filtered[index - 1].name);
                            final currentLetter = _firstCatalogLetter(item.name);
                            final showHeader = previousLetter != currentLetter;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showHeader) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                                    child: Text(
                                      currentLetter,
                                      style: const TextStyle(
                                        color: Color(0xFF18D9C3),
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                                _CatalogTile(
                                  item: item,
                                  adminMode: isCurrentUserAdmin,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CatalogDetailPage(item: item),
                                      ),
                                    );
                                    _reload();
                                  },
                                ),
                                const SizedBox(height: 10),
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: isCurrentUserAdmin
          ? FloatingActionButton.extended(
              onPressed: _openAdd,
              backgroundColor: const Color(0xFF15D9C4),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                tr('Katalogga qo‘shish', 'Добавить в каталог'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
    );
  }
}

class _CatalogEmpty extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onAdd;
  const _CatalogEmpty({required this.isAdmin, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open_rounded,
                color: Color(0xFF18D9C3), size: 60),
            const SizedBox(height: 14),
            Text(
              tr('Katalog hozircha bo‘sh', 'Каталог пока пуст'),
              style: TextStyle(
                color: primaryText(context),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? tr('Admin galereyadan mahsulot rasmlarini tanlab qo‘shishi mumkin.',
                      'Администратор может добавить товар и выбрать несколько фото из галереи.')
                  : tr('Katalog mahsulotlarini admin joylaydi.',
                      'Товары в каталог добавляет администратор.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedText(context)),
            ),
            if (isAdmin) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Birinchi mahsulotni qo‘shish', 'Добавить первый товар')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  final CatalogItem item;
  final bool adminMode;
  final VoidCallback onTap;
  const _CatalogTile({
    required this.item,
    required this.adminMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF071A24),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF00D7C2).withOpacity(.20),
            ),
          ),
          child: Row(
            children: [
              _CatalogImage(path: item.images.isEmpty ? null : item.images.first, size: 76),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primaryText(context),
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${tr('Art', 'Арт')}: ${item.code.isEmpty ? '—' : item.code}',
                      style: TextStyle(color: mutedText(context), fontSize: 13),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${item.price} ${tr("so‘m", "сум")}',
                      style: const TextStyle(
                        color: AppColors.green,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              if (adminMode)
                const Icon(Icons.edit_outlined, color: Color(0xFF18D9C3))
              else
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF6B8B95)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogImage extends StatelessWidget {
  final String? path;
  final double size;
  const _CatalogImage({required this.path, this.size = 80});

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (path != null && path!.isNotEmpty && File(path!).existsSync()) {
      child = Image.file(File(path!), fit: BoxFit.cover);
    } else {
      child = const Center(
        child: Icon(Icons.image_outlined, color: Color(0xFF6E8993), size: 34),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: child,
      ),
    );
  }
}

class CatalogDetailPage extends StatefulWidget {
  final CatalogItem item;
  const CatalogDetailPage({super.key, required this.item});

  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  late CatalogItem _item;
  final PageController _pageController = PageController();
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    if (!isCurrentUserAdmin) return;
    final result = await Navigator.push<CatalogItem>(
      context,
      MaterialPageRoute(builder: (_) => CatalogEditPage(item: _item)),
    );
    if (result != null && mounted) setState(() => _item = result);
  }

  Future<void> _delete() async {
    if (!isCurrentUserAdmin) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Mahsulotni o‘chirish?', 'Удалить товар?')),
            content: Text(_item.name),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Bekor qilish', 'Отмена')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  tr('O‘chirish', 'Удалить'),
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final all = await _loadLocalCatalog();
    all.removeWhere((e) => e.id == _item.id);
    await _saveLocalCatalog(all);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_item.name),
        actions: [
          if (isCurrentUserAdmin)
            IconButton(
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined, color: AppColors.cyan),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          Container(
            height: 310,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            clipBehavior: Clip.antiAlias,
            child: _item.images.isEmpty
                ? const Center(
                    child: Icon(Icons.image_outlined,
                        color: Color(0xFF8A9AA5), size: 70),
                  )
                : PageView.builder(
                    controller: _pageController,
                    itemCount: _item.images.length,
                    onPageChanged: (i) => setState(() => _imageIndex = i),
                    itemBuilder: (_, i) => File(_item.images[i]).existsSync()
                        ? Image.file(File(_item.images[i]), fit: BoxFit.contain)
                        : const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
          ),
          if (_item.images.length > 1) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${_imageIndex + 1} / ${_item.images.length}',
                style: TextStyle(color: mutedText(context)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            _item.name,
            style: TextStyle(
              color: primaryText(context),
              fontWeight: FontWeight.w900,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 14),
          _CatalogInfoRow(
            icon: Icons.qr_code_2_rounded,
            label: tr('Artikul', 'Артикул'),
            value: _item.code.isEmpty ? '—' : _item.code,
          ),
          const SizedBox(height: 10),
          _CatalogInfoRow(
            icon: Icons.payments_outlined,
            label: tr('Narxi', 'Цена'),
            value: '${_item.price} ${tr("so‘m", "сум")}',
            accent: AppColors.green,
          ),
          if (isCurrentUserAdmin) ...[
            const SizedBox(height: 30),
            GradientButton(
              text: tr('Tahrirlash', 'Редактировать'),
              icon: Icons.edit_rounded,
              onPressed: _edit,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 58),
                side: const BorderSide(color: AppColors.danger),
                foregroundColor: AppColors.danger,
              ),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(tr('Katalogdan o‘chirish', 'Удалить из каталога')),
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  const _CatalogInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF071A24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: mutedText(context), fontSize: 12)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: primaryText(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogEditPage extends StatefulWidget {
  final CatalogItem? item;
  const CatalogEditPage({super.key, this.item});

  @override
  State<CatalogEditPage> createState() => _CatalogEditPageState();
}

class _CatalogEditPageState extends State<CatalogEditPage> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _code = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  List<String> _images = [];
  bool _saving = false;

  bool get editing => widget.item != null;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _name.text = widget.item!.name;
      _price.text = widget.item!.price;
      _code.text = widget.item!.code;
      _images = [...widget.item!.images];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _pickManyFromGallery() async {
    if (!isCurrentUserAdmin) return;
    try {
      final files = await _picker.pickMultiImage(imageQuality: 88);
      if (files.isEmpty || !mounted) return;
      setState(() {
        final newPaths = files.map((e) => e.path).where((p) => !_images.contains(p));
        _images.addAll(newPaths);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Galereyani ochib bo‘lmadi.', 'Не удалось открыть галерею.'),
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!isCurrentUserAdmin || _saving) return;
    final name = _name.text.trim();
    final price = _price.text.trim();
    final code = _code.text.trim();

    if (name.isEmpty || price.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Nomi va narxini kiriting.', 'Введите название и цену.')),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final all = await _loadLocalCatalog();
    final now = DateTime.now().toIso8601String();
    final newItem = CatalogItem(
      id: widget.item?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      price: price,
      code: code,
      images: [..._images],
      updatedAt: now,
    );

    final index = all.indexWhere((e) => e.id == newItem.id);
    if (index >= 0) {
      all[index] = newItem;
    } else {
      all.add(newItem);
    }
    await _saveLocalCatalog(all);

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, newItem);
  }

  @override
  Widget build(BuildContext context) {
    if (!isCurrentUserAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Katalog', 'Каталог'))),
        body: Center(
          child: Text(
            tr('Bu bo‘lim faqat admin uchun.', 'Этот раздел только для администратора.'),
            style: TextStyle(color: mutedText(context)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(editing
            ? tr('Katalogni tahrirlash', 'Редактировать каталог')
            : tr('Katalogga mahsulot', 'Товар в каталог')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Mahsulot rasmlari', 'Фотографии товара'),
              style: TextStyle(
                color: primaryText(context),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Faqat admin uchun: galereyadan bir nechta rasmni birdan tanlang.',
                'Только для администратора: выберите сразу несколько фото из галереи.',
              ),
              style: TextStyle(color: mutedText(context), fontSize: 13),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickManyFromGallery,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF071A24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00D7C2).withOpacity(.28),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.photo_library_outlined,
                        color: Color(0xFF16D9C4), size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Galereyadan rasmlar tanlash', 'Выбрать фото из галереи'),
                            style: TextStyle(
                              color: primaryText(context),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tr('${_images.length} ta rasm tanlangan',
                                'Выбрано фото: ${_images.length}'),
                            style: TextStyle(color: mutedText(context), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFF16D9C4)),
                  ],
                ),
              ),
            ),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _CatalogImage(path: _images[i], size: 88),
                      Positioned(
                        top: -5,
                        right: -5,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.removeAt(i)),
                          child: Container(
                            width: 25,
                            height: 25,
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr('Mahsulot nomi', 'Название товара'),
                prefixIcon: const Icon(Icons.inventory_2_outlined,
                    color: AppColors.cyan),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Narxi', 'Цена'),
                prefixIcon: const Icon(Icons.payments_outlined,
                    color: AppColors.green),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              decoration: InputDecoration(
                labelText: tr('Artikul', 'Артикул'),
                prefixIcon: const Icon(Icons.qr_code_2_rounded,
                    color: AppColors.cyan),
              ),
            ),
            const SizedBox(height: 30),
            _saving
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.cyan),
                  )
                : GradientButton(
                    text: editing
                        ? tr('O‘zgarishlarni saqlash', 'Сохранить изменения')
                        : tr('Katalogga saqlash', 'Сохранить в каталог'),
                    icon: Icons.save_outlined,
                    onPressed: _save,
                  ),
          ],
        ),
      ),
    );
  }
}
