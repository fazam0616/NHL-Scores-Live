import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/game_screen.dart';
import '../screens/team_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/game/:gameId',
      builder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        return GameScreen(gameId: gameId);
      },
    ),
    GoRoute(
      path: '/game/:gameId/team/:teamId',
      builder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        final teamId = state.pathParameters['teamId']!;
        return TeamScreen(gameId: gameId, teamId: teamId);
      },
    ),
  ],
);
