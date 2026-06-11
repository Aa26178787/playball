import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/game_provider.dart';
import 'providers/team_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api/api_service.dart';
import 'utils/app_theme.dart';
import 'utils/app_config.dart';
import 'utils/web_update/web_back_stub.dart'
    if (dart.library.html) 'utils/web_update/web_back_web.dart';
import 'utils/web_update/web_theme_stub.dart'
    if (dart.library.html) 'utils/web_update/web_theme_web.dart';

final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'playball_default',
  'PlayBall 알림',
  description: '경기 득점, 시작/종료, 등록말소 알림',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 백그라운드 알림 수신 — OS가 자동 표시
}

Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Crashlytics — Flutter 프레임워크 에러 + 비동기 에러 자동 수집
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // 로컬 알림 초기화 (포그라운드용)
    await _localNotif.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    debugPrint('[FCM] 권한 상태: ${settings.authorizationStatus}');
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    final token = await messaging.getToken();
    debugPrint('[FCM] 토큰: ${token?.substring(0, 30)}...');
    if (token != null) {
      await ApiService.registerFcmToken(token);
    }

    messaging.onTokenRefresh.listen((newToken) async {
      await ApiService.registerFcmToken(newToken);
    });

    // 포그라운드 수신 → 로컬 알림으로 표시
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final n = msg.notification;
      if (n == null) return;
      _localNotif.show(
        msg.hashCode,
        n.title,
        n.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    });
  } catch (_) {
    // Firebase 미설정 시 무시
  }
}

// 웹 back-trap에서 라우트 pop용 (브라우저 뒤로가기 → 앱 내 뒤로가기)
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  // 웹: 브라우저 back/스와이프백 → Navigator.pop (SPA 이탈 → 흰화면 방지)
  installWebBackHandler(() {
    final nav = appNavigatorKey.currentState;
    if (nav != null && nav.canPop()) nav.pop();
    return true;
  });
  await _initFirebase();
  runApp(const PlayBallApp());
}

class PlayBallApp extends StatelessWidget {
  const PlayBallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GameProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          // 웹 브라우저 툴바(작업표시줄) 색을 테마와 동기화 (meta theme-color)
          final mq = MediaQuery.maybePlatformBrightnessOf(context);
          final dark = themeProvider.themeMode == ThemeMode.dark ||
              (themeProvider.themeMode == ThemeMode.system && mq == Brightness.dark);
          setWebThemeColor(dark ? '#111113' : '#FAFAFB');
          return MaterialApp(
          title: 'PlayBall',
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          restorationScopeId: 'playball_root',
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ko', 'KR'),
          ],
          themeMode: themeProvider.themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          // a11y 큰 글자 사용자 1.3 이하 clamp — UI 레이아웃 깨짐 방지
          builder: (ctx, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.3,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const AppEntryPoint(),
        );
        },
      ),
    );
  }
}

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().checkLoginStatus();
      _checkAppConfig();
    });
  }

  Future<void> _checkAppConfig() async {
    await AppConfig.load();
    if (!mounted || !AppConfig.forceUpdate) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('업데이트가 필요합니다'),
          content: const Text('원활한 사용을 위해 최신 버전으로 업데이트해주세요.'),
          actions: [
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(
                    'https://play.google.com/store/apps/details?id=com.playball.app'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('업데이트'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isInitializing) {
          return const SplashScreen();
        }
        return FadeTransition(
          opacity: _fadeAnim,
          child: auth.isLoggedIn ? const HomeScreen() : const LoginScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111113),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sports_baseball,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 16),
            Text(
              'PlayBall',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'KBO 야구 앱',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 48),
            CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}