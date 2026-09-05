from pathlib import Path

p = Path('lib/main.dart')
s = p.read_text(encoding='utf-8')

# Flutter compatibility.
s = s.replace('minHeight: 118,', 'constraints: const BoxConstraints(minHeight: 118),')

# Telegram package.
if "package:url_launcher/url_launcher.dart" not in s:
    s = s.replace(
        "import 'package:shared_preferences/shared_preferences.dart';",
        "import 'package:shared_preferences/shared_preferences.dart';\nimport 'package:url_launcher/url_launcher.dart';",
    )

# Restore saved language/theme before UI appears.
old_main = """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PixDropApp());
}"""
new_main = """Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  isUzbek.value = prefs.getBool('ui_is_uzbek') ?? true;
  themeMode.value = (prefs.getBool('ui_dark_mode') ?? true)
      ? ThemeMode.dark
      : ThemeMode.light;
  runApp(const PixDropApp());
}"""
s = s.replace(old_main, new_main)

# Instant theme switching + save.
old = """onChanged: (v) {
                      themeMode.value = v ? ThemeMode.dark : ThemeMode.light;
                      setState(() {});
                    },"""
new = """onChanged: (v) async {
                      themeMode.value = v ? ThemeMode.dark : ThemeMode.light;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('ui_dark_mode', v);
                      if (mounted) setState(() {});
                    },"""
s = s.replace(old, new)

# Instant Uzbek/Russian switching + save.
old = """onChanged: (v) {
                      isUzbek.value = v;
                      setState(() {});
                    },"""
new = """onChanged: (v) async {
                      isUzbek.value = v;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('ui_is_uzbek', v);
                      if (mounted) setState(() {});
                    },"""
s = s.replace(old, new)

# Pix uses the same cyan shade as the removed home-section heading.
s = s.replace(
    "TextSpan(text: 'Pix', style: TextStyle(color: AppColors.cyan)),",
    "TextSpan(text: 'Pix', style: TextStyle(color: Color(0xFF16D9C4))),",
)

# Fixed dark surfaces -> theme-aware surfaces.
replacements = {
    'color: const Color(0xFF071A24),': 'color: surfaceColor(context),',
    'color: const Color(0xFF06212A),': 'color: surfaceColor(context),',
    'color: const Color(0xFF06202A),': 'color: surfaceColor(context),',
    'color: const Color(0xFF081A25),': 'color: surfaceColor(context),',
    'fillColor: const Color(0xFF071A24),': 'fillColor: surfaceColor(context),',
    'fillColor: const Color(0xFF06212A),': 'fillColor: surfaceColor(context),',
    'fillColor: const Color(0xFF081A25),': 'fillColor: surfaceColor(context),',
}
for old, new in replacements.items():
    s = s.replace(old, new)

# Strong theme defaults so white/light surfaces always have readable text.
s = s.replace(
    """return base.copyWith(
      scaffoldBackgroundColor: AppColors.lightBg,""",
    """return base.copyWith(
      scaffoldBackgroundColor: AppColors.lightBg,
      textTheme: base.textTheme.apply(bodyColor: AppColors.lightText, displayColor: AppColors.lightText),
      iconTheme: const IconThemeData(color: AppColors.lightText),
      dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white),""",
)
s = s.replace(
    """return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,""",
    """return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      iconTheme: const IconThemeData(color: AppColors.text),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surface),""",
)

# Telegram username is tappable.
old_tg = """const Text(
                          '@Parvizgaybullayev',
                          style: TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w900,
                          ),
                        ),"""
new_tg = """InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final uri = Uri.parse('https://t.me/Parvizgaybullayev');
                            final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
                            if (!opened && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(tr('Telegram ochilmadi', 'Не удалось открыть Telegram'))),
                              );
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              '@Parvizgaybullayev',
                              style: TextStyle(
                                color: AppColors.green,
                                fontWeight: FontWeight.w900,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),"""
s = s.replace(old_tg, new_tg)

p.write_text(s, encoding='utf-8')

# Android app label under launcher icon.
manifest = Path('android/app/src/main/AndroidManifest.xml')
m = manifest.read_text(encoding='utf-8')
if 'android.permission.INTERNET' not in m:
    m = m.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET" />',
    )
m = m.replace('android:label="pixdrop"', 'android:label="PixDrop"')
manifest.write_text(m, encoding='utf-8')

checks = {
    'cyan Pix': "color: Color(0xFF16D9C4)" in s,
    'dark home logo': "assetPath: 'assets/home_logo_dark.png'" in s,
    'removed popular-products heading': 'Eng ko‘p qidirilgan mahsulotlar' not in s,
    'removed all-products link': "tr('Barchasi', 'Все')" not in s,
    'Telegram import': "package:url_launcher/url_launcher.dart" in s,
    'Telegram link': "https://t.me/Parvizgaybullayev" in s,
    'Telegram username': "@Parvizgaybullayev" in s,
    'language persistence': "prefs.setBool('ui_is_uzbek', v)" in s,
    'theme persistence': "prefs.setBool('ui_dark_mode', v)" in s,
    'startup restore': "prefs.getBool('ui_is_uzbek')" in s and "prefs.getBool('ui_dark_mode')" in s,
    'launcher label': 'android:label="PixDrop"' in m,
}
print('PIXDROP FIX CHECKS:', checks)
missing = [key for key, ok in checks.items() if not ok]
if missing:
    raise SystemExit('Missing PixDrop fixes: ' + ', '.join(missing))
