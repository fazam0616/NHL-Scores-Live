import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/game_provider.dart';
import '../widgets/game_card.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameProvider>().startHomeScreenUpdates();
    });
  }

  @override
  void dispose() {
    context.read<GameProvider>().stopUpdates();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      context.read<GameProvider>().stopUpdates();
      context.read<GameProvider>().getGamesOnDate(_selectedDate);
    }
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
              child: SingleChildScrollView(
                controller: scrollController,
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
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.85,
                      child: GameScreen(gameId: gameId, showScaffold: false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      // Clear selected game and resume home screen updates when bottom sheet closes
      context.read<GameProvider>().clearSelectedGame();
      // Fetch games for the currently selected date, not today
      context.read<GameProvider>().getGamesOnDate(_selectedDate);
    });
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('NHL Games on '),
            GestureDetector(
              onTap: () => _selectDate(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDate(_selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.calendar_today, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<GameProvider>(
        builder: (context, gameProvider, child) {
          if (gameProvider.isLoading && gameProvider.games.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

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
                    onPressed: () => gameProvider.fetchTodaysGames(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (gameProvider.games.isEmpty) {
            return const Center(child: Text('No games found'));
          }

          return ListView.builder(
            itemCount: gameProvider.games.length,
            itemBuilder: (context, index) {
              final game = gameProvider.games[index];
              return GameCard(
                game: game,
                onTap: () => _showGameDetails(context, game.id),
              );
            },
          );
        },
      ),
    );
  }
}
