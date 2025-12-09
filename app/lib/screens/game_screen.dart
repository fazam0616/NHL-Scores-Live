import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/game_provider.dart';

class GameScreen extends StatefulWidget {
  final String gameId;
  final bool showScaffold;

  const GameScreen({super.key, required this.gameId, this.showScaffold = true});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameProvider? _provider;
  final Set<String> _expandedGoals = {};

  String _formatTeamName(String teamName) {
    final spaces = ' '.allMatches(teamName).length;

    if (spaces == 0) {
      // No spaces, return as is
      return teamName;
    } else if (spaces == 1) {
      // One space, split on that space
      return teamName.replaceFirst(' ', '\n');
    } else {
      // Two or more spaces, split to balance line lengths
      final words = teamName.split(' ');
      int bestSplit = 1;
      int minDiff = teamName.length;

      // Try each possible split point
      for (int i = 1; i < words.length; i++) {
        final line1 = words.sublist(0, i).join(' ');
        final line2 = words.sublist(i).join(' ');
        final diff = (line1.length - line2.length).abs();

        if (diff < minDiff) {
          minDiff = diff;
          bestSplit = i;
        }
      }

      final line1 = words.sublist(0, bestSplit).join(' ');
      final line2 = words.sublist(bestSplit).join(' ');
      return '$line1\n$line2';
    }
  }

  Widget _buildGoalWidget({
    required String timeKey,
    required dynamic goal,
    required bool isHomeGoal,
    required String homeTeamId,
    required String awayTeamId,
  }) {
    final isExpanded = _expandedGoals.contains(timeKey);

    // Define alignment based on scoring team
    final scorerAlign =
        isHomeGoal ? Alignment.centerLeft : Alignment.centerRight;
    final defenderAlign =
        isHomeGoal ? Alignment.centerRight : Alignment.centerLeft;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedGoals.remove(timeKey);
            } else {
              _expandedGoals.add(timeKey);
            }
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
                  child: Column(
                    crossAxisAlignment: isHomeGoal
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end,
                    children: [
                      // First line: Scorer and Time
                      SizedBox(
                        height:
                            24, // Fixed height to ensure consistent vertical centering
                        child: Stack(
                          children: [
                            Align(
                              alignment: scorerAlign,
                              child: Text(
                                goal.scorer,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                goal.totalTime ?? timeKey,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Expandable section
              if (isExpanded)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      // Assists aligned with scorer
                      if (goal.primaryAssist != null) ...[
                        Align(
                          alignment: scorerAlign,
                          child: Text(
                            'Primary Assist: ${goal.primaryAssist}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (goal.secondaryAssist != null) ...[
                        Align(
                          alignment: scorerAlign,
                          child: Text(
                            'Secondary Assist: ${goal.secondaryAssist}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      // Goalie aligned opposite to scorer
                      if (goal.goalie != null) ...[
                        Align(
                          alignment: defenderAlign,
                          child: Text(
                            'Goalie: ${goal.goalie}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              // Triangle indicator
              Container(
                padding: const EdgeInsets.only(bottom: 4),
                child: Icon(
                  isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 24,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Only manage lifecycle when showing scaffold (used as route)
    if (widget.showScaffold) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final provider = context.read<GameProvider>();
        provider.selectGameAndStartLiveUpdates(widget.gameId);
        provider.fetchGoalsForGame(widget.gameId);
      });
    } else {
      // When embedded in bottom sheet, just fetch goals
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<GameProvider>().fetchGoalsForGame(widget.gameId);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Save provider reference for safe disposal
    _provider = Provider.of<GameProvider>(context, listen: false);
  }

  @override
  void dispose() {
    // Only clear when showing scaffold (used as route)
    if (widget.showScaffold && _provider != null) {
      _provider!.clearSelectedGame();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        if (gameProvider.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Problem Loading Game',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'There was a problem loading the game details. Please check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          gameProvider
                              .selectGameAndStartLiveUpdates(widget.gameId);
                          gameProvider.fetchGoalsForGame(widget.gameId);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          } else {
                            context.go('/');
                          }
                        },
                        child: const Text('Close'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        final game = gameProvider.selectedGame;
        if (game == null) {
          return const Center(
            child: CircularProgressIndicator(
              color: Colors.blue,
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Game status
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      game.isLive ? Colors.red.shade100 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  game.status,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: game.isLive ? Colors.red : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Two column layout: Home (left) vs Away (right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Home team column (left)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        context.push(
                            '/game/${widget.gameId}/team/${game.homeData.teamId}');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade300,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Team full name
                            Text(
                              _formatTeamName(game.homeData.teamName),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            // Team logo
                            SvgPicture.network(
                              'https://assets.nhle.com/logos/nhl/svg/${game.homeData.teamId}_light.svg',
                              width: 80,
                              height: 80,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 80,
                                height: 80,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Current score
                            Text(
                              game.homeData.teamScore.toString(),
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Away team column (right)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        context.push(
                            '/game/${widget.gameId}/team/${game.awayData.teamId}');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade300,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Team full name
                            Text(
                              _formatTeamName(game.awayData.teamName),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            // Team logo
                            SvgPicture.network(
                              'https://assets.nhle.com/logos/nhl/svg/${game.awayData.teamId}_light.svg',
                              width: 80,
                              height: 80,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 80,
                                height: 80,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Current score
                            Text(
                              game.awayData.teamScore.toString(),
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'Goals',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              // Goals section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: gameProvider.isLoadingGoals
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(
                            color: Colors.blue,
                          ),
                        ),
                      )
                    : game.goals == null || game.goals!.isEmpty
                        ? const Text(
                            'No goals yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          )
                        : Column(
                            children: [
                              for (var entry in game.goals!.entries.toList()
                                ..sort((a, b) {
                                  // Sort by totalTime (MM:SS format)
                                  final timeA = a.value.totalTime ?? '00:00';
                                  final timeB = b.value.totalTime ?? '00:00';

                                  // Convert MM:SS to total seconds for comparison
                                  final partsA = timeA.split(':');
                                  final partsB = timeB.split(':');
                                  final totalSecsA = int.parse(partsA[0]) * 60 +
                                      int.parse(partsA[1]);
                                  final totalSecsB = int.parse(partsB[0]) * 60 +
                                      int.parse(partsB[1]);

                                  return totalSecsA.compareTo(totalSecsB);
                                }))
                                () {
                                  final timeKey = entry.key;
                                  final goal = entry.value;

                                  // Use isHome boolean from goal data
                                  final isHomeGoal = goal.isHome ?? false;

                                  return _buildGoalWidget(
                                    timeKey: timeKey,
                                    goal: goal,
                                    isHomeGoal: isHomeGoal,
                                    homeTeamId: game.homeData.teamId,
                                    awayTeamId: game.awayData.teamId,
                                  );
                                }(),
                            ],
                          ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (widget.showScaffold) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Game Details'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: content,
      );
    }

    return content;
  }
}
