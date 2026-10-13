import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'models/models.dart';
import 'screens/chart_screen.dart';
import 'screens/comments_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/player_screen.dart';
import 'screens/podcast_detail_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/subscriptions_screen.dart';
import 'screens/theme_screen.dart';
import 'screens/user_screen.dart';
import 'services/auth_service.dart';
import 'services/now_playing_service.dart';
import 'services/player_service.dart';
import 'services/settings_service.dart';
import 'services/xyz_service.dart';
import 'widgets/detail_scaffold.dart';
import 'widgets/mini_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final api = XyzApiClient();
  final xyz = XyzService(api);
  final auth = AuthService(api);
  final player = PlayerService(xyz);
  final settings = SettingsService();
  await settings.init();
  await auth.init();
  // iOS 锁屏/控制中心媒体信息同步（内部判断平台）
  // 通过 player 的 listener 持有引用，不会被回收
  NowPlayingService(player);

  runApp(
    MultiProvider(
      providers: [
        Provider<XyzApiClient>.value(value: api),
        Provider<XyzService>.value(value: xyz),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<PlayerService>.value(value: player),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
      ],
      child: const XyzFmApp(),
    ),
  );
}

class XyzFmApp extends StatelessWidget {
  const XyzFmApp({super.key});

  @override
  Widget build(BuildContext context) {
    // M3 主题：主题模式（跟随系统/浅色/深色）+ 动态取色/种子色 + 纯黑模式
    final settings = context.watch<SettingsService>();
    final seedColor = settings.effectiveSeedColor;
    return MaterialApp(
      title: 'xyzFM',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(brightness: Brightness.light, seedColor: seedColor),
      darkTheme: buildTheme(
        brightness: Brightness.dark,
        seedColor: seedColor,
        pureBlack: settings.pureBlack,
      ),
      home: const AppShell(),
      onGenerateRoute: (settings) {
        final args = settings.arguments;
        switch (settings.name) {
          case '/search':
            return MaterialPageRoute(
              builder: (_) => DetailScaffold(
                child: SearchScreen(autofocus: args is bool ? args : false),
              ),
            );
          case '/podcast':
            if (args is String) {
              return MaterialPageRoute(
                builder: (_) => DetailScaffold(
                  child: PodcastDetailScreen(pid: args),
                ),
              );
            }
          case '/player':
            return MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const PlayerScreen(),
            );
          case '/login':
            return MaterialPageRoute(builder: (_) => const LoginScreen());
          case '/settings':
            return MaterialPageRoute(
                builder: (_) => const DetailScaffold(child: SettingsScreen()));
          case '/theme':
            return MaterialPageRoute(
                builder: (_) => const DetailScaffold(child: ThemeScreen()));
          case '/comments':
            if (args is Episode) {
              return MaterialPageRoute(
                builder: (_) =>
                    DetailScaffold(child: CommentsScreen(episode: args)),
              );
            }
          case '/chart':
            if (args is Map) {
              return MaterialPageRoute(
                builder: (_) => DetailScaffold(
                  child: ChartScreen(
                    title: '${args['title'] ?? '榜单'}',
                    category: '${args['category'] ?? 'HOT'}',
                  ),
                ),
              );
            }
        }
        return null;
      },
    );
  }
}

/// 底部导航：发现 / 订阅 / 搜索 / 我的 + 迷你播放器
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tabIndex = 0;

  final _tabs = const [
    HomeScreen(),
    SubscriptionsScreen(),
    SearchScreen(),
    UserScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 桌面端（宽屏）：左侧栏；移动端：底部导航
        if (constraints.maxWidth >= 900) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _tabIndex,
                  onDestinationSelected: (i) =>
                      setState(() => _tabIndex = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: Text('发现'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.subscriptions_outlined),
                      selectedIcon: Icon(Icons.subscriptions),
                      label: Text('订阅'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.search_outlined),
                      selectedIcon: Icon(Icons.search),
                      label: Text('搜索'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(Icons.person),
                      label: Text('我的'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: IndexedStack(
                            index: _tabIndex, children: _tabs),
                      ),
                      const MiniPlayer(),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: IndexedStack(
                    index: _tabIndex, children: _tabs),
              ),
              const MiniPlayer(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) =>
                setState(() => _tabIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '发现',
              ),
              NavigationDestination(
                icon: Icon(Icons.subscriptions_outlined),
                selectedIcon: Icon(Icons.subscriptions),
                label: '订阅',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: '搜索',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          ),
        );
      },
    );
  }
}
