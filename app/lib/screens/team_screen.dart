import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TeamScreen extends StatelessWidget {
  final String gameId;
  final String teamId;

  const TeamScreen({
    super.key,
    required this.gameId,
    required this.teamId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Team: $teamId'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Game ID: $gameId',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Team ID: $teamId',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            const Text(
              'Team information will be displayed here.',
              style: TextStyle(fontSize: 16),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () => context.go('/game/$gameId'),
              child: const Text('Back to Game'),
            ),
          ],
        ),
      ),
    );
  }
}
