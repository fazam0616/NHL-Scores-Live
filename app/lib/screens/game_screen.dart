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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${gameProvider.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      context.go('/');
                    }
                  },
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }

        final game = gameProvider.selectedGame;
        if (game == null) {
          return const Center(child: CircularProgressIndicator());
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
                    child: Column(
                      children: [
                        // Team full name
                        Text(
                          game.homeData.teamName,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                  // Divider
                  Container(
                    width: 2,
                    height: 180,
                    color: Colors.grey.shade300,
                  ),
                  // Away team column (right)
                  Expanded(
                    child: Column(
                      children: [
                        // Team full name
                        Text(
                          game.awayData.teamName,
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                ],
              ),
              const SizedBox(height: 32),
              // Goals section
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: game.goals == null || game.goals!.isEmpty
                      ? const Center(
                          child: Text(
                            'No goals yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: game.goals!.length,
                          itemBuilder: (context, index) {
                            final entry = game.goals!.entries.elementAt(index);
                            final timeKey = entry.key;
                            final goal = entry.value;

                            // Determine if goal was scored by home or away team
                            final isHomeGoal = goal.teamId.toString() ==
                                    game.homeData.teamId ||
                                (goal.teamId == null && index % 2 == 0);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  if (isHomeGoal) ...[
                                    // Home goal - left aligned
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            goal.scorer,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (goal.primaryAssist != null ||
                                              goal.secondaryAssist != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Assists: ${[
                                                goal.primaryAssist,
                                                goal.secondaryAssist
                                              ].where((a) => a != null).join(', ')}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      timeKey,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ] else ...[
                                    // Away goal - right aligned
                                    Text(
                                      timeKey,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            goal.scorer,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                          if (goal.primaryAssist != null ||
                                              goal.secondaryAssist != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Assists: ${[
                                                goal.primaryAssist,
                                                goal.secondaryAssist
                                              ].where((a) => a != null).join(', ')}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                              ),
                                              textAlign: TextAlign.right,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16),
              // Team view buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Close bottom sheet if present
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                        context.go(
                            '/game/${widget.gameId}/team/${game.homeData.teamId}');
                      },
                      child: Text('View ${game.homeData.teamId}'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Close bottom sheet if present
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                        context.go(
                            '/game/${widget.gameId}/team/${game.awayData.teamId}');
                      },
                      child: Text('View ${game.awayData.teamId}'),
                    ),
                  ),
                ],
              ),
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
