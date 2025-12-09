import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../models/game_model.dart';
import '../providers/game_provider.dart';
import '../widgets/game_card.dart';
import 'game_screen.dart';

class TeamScreen extends StatefulWidget {
  final String gameId;
  final String teamId;

  const TeamScreen({
    super.key,
    required this.gameId,
    required this.teamId,
  });

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _teamData;
  List<Game> _recentGames = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTeamData();
  }

  Future<void> _loadTeamData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Call fetchTeamData function
      final callable = _functions.httpsCallable('fetchTeamData');
      final result = await callable.call({'teamId': widget.teamId});

      _teamData = result.data as Map<String, dynamic>;

      // Fetch the recent games
      final recentGameIds = List<String>.from(_teamData!['recentGames'] ?? []);
      final games = <Game>[];

      for (final gameId in recentGameIds) {
        final doc = await _firestore.collection('games').doc(gameId).get();
        if (doc.exists) {
          games.add(Game.fromFirestore(doc.data()!, doc.id));
        }
      }

      setState(() {
        _recentGames = games;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamName = _teamData?['teamName'] ?? widget.teamId;
    final season = _teamData?['season'] ?? '';
    final seasonDisplay = season.isNotEmpty
        ? '${season.substring(0, 4)}-${season.substring(4)}'
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(teamName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadTeamData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTeamData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
                    children: [
                      // Team logo and name
                      Center(
                        child: Column(
                          children: [
                            SvgPicture.network(
                              'https://assets.nhle.com/logos/nhl/svg/${widget.teamId}_light.svg',
                              width: 120,
                              height: 120,
                              placeholderBuilder: (context) => const SizedBox(
                                width: 120,
                                height: 120,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              teamName,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (seasonDisplay.isNotEmpty)
                              Text(
                                seasonDisplay,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (_teamData?['source'] == 'cache')
                              const Text(
                                '(Cached)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Team stats
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Season Stats',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (seasonDisplay.isNotEmpty)
                                    Text(
                                      seasonDisplay,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildStatRow(
                                'Games Played',
                                '${_teamData?['gamesPlayed'] ?? 0}',
                              ),
                              _buildStatRow(
                                'Wins',
                                '${_teamData?['wins'] ?? 0}',
                              ),
                              _buildStatRow(
                                'Losses',
                                '${_teamData?['losses'] ?? 0}',
                              ),
                              _buildStatRow(
                                'Total Goals',
                                '${_teamData?['totalGoals'] ?? 0}',
                              ),
                              _buildStatRow(
                                'Win Rate',
                                _calculateWinRate(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // All-time stats
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'All Time Stats',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildStatRow(
                                'Games Played',
                                '${_teamData?['allTimeGamesPlayed'] ?? 0}',
                              ),
                              _buildStatRow(
                                'Wins',
                                '${_teamData?['allTimeWins'] ?? 0}',
                              ),
                              _buildStatRow(
                                'Losses',
                                '${_teamData?['allTimeLosses'] ?? 0}',
                              ),
                              _buildStatRow(
                                'Total Goals',
                                '${_teamData?['allTimeTotalGoals'] ?? 0}',
                              ),
                              _buildStatRow(
                                'Win Rate',
                                _calculateAllTimeWinRate(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Recent games
                      const Text(
                        'Recent Games',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_recentGames.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Text('No recent games found'),
                          ),
                        )
                      else
                        ..._recentGames.map(
                          (game) => GameCard(
                            game: game,
                            backgroundColor: _getGameColor(game),
                            onTap: () => _showGameDetails(context, game.id),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  void _showGameDetails(BuildContext context, String gameId) {
    // Start live updates for selected game
    context.read<GameProvider>().selectGameAndStartLiveUpdates(gameId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {},
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Game details content
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: GameScreen(gameId: gameId, showScaffold: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      // Clear selected game when bottom sheet closes
      context.read<GameProvider>().clearSelectedGame();
    });
  }

  Color? _getGameColor(Game game) {
    // Only color final games
    if (!game.isFinal) return null;

    final franchiseId = _teamData?['franchiseId'];
    if (franchiseId == null) return null;

    // Determine if this team is home or away
    final isHome = game.homeData.teamId == widget.teamId;
    final teamScore =
        isHome ? game.homeData.teamScore : game.awayData.teamScore;
    final opponentScore =
        isHome ? game.awayData.teamScore : game.homeData.teamScore;

    if (teamScore > opponentScore) {
      // Win - pale green
      return Colors.green.shade50;
    } else if (teamScore < opponentScore) {
      // Loss - pale red
      return Colors.red.shade50;
    } else {
      // Draw - pale yellow
      return Colors.yellow.shade50;
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _calculateWinRate() {
    final gamesPlayed = _teamData?['gamesPlayed'] ?? 0;
    final wins = _teamData?['wins'] ?? 0;

    if (gamesPlayed == 0) return '0.0%';

    final winRate = (wins / gamesPlayed * 100).toStringAsFixed(1);
    return '$winRate%';
  }

  String _calculateAllTimeWinRate() {
    final allTimeGamesPlayed = _teamData?['allTimeGamesPlayed'] ?? 0;
    final allTimeWins = _teamData?['allTimeWins'] ?? 0;

    if (allTimeGamesPlayed == 0) return '0.0%';

    final winRate = (allTimeWins / allTimeGamesPlayed * 100).toStringAsFixed(1);
    return '$winRate%';
  }
}
