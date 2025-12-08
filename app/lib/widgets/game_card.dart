import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/game_model.dart';

class GameCard extends StatelessWidget {
  final Game game;
  final VoidCallback? onTap;

  const GameCard({
    super.key,
    required this.game,
    this.onTap,
  });

  static const double logoSize = 50;

  Color _getStatusColor() {
    if (game.isLive) return Colors.green;
    if (game.isFinal) return Colors.blue;
    return Colors.yellow.shade700;
  }

  String _getStatusText() {
    if (game.isLive) return 'LIVE';
    if (game.isFinal) return 'FINAL';
    // Format start time (e.g., "7:00 PM")
    final hour = game.startTime.hour;
    final minute = game.startTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            // Status sliver on left edge
            Container(
              width: 24,
              height: 74, // Match the content padding (12*2) + logo size (50)
              decoration: BoxDecoration(
                color: _getStatusColor(),
              ),
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    _getStatusText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Away team logo
                    SvgPicture.network(
                      'https://assets.nhle.com/logos/nhl/svg/${game.awayData.teamId}_light.svg',
                      width: logoSize,
                      height: logoSize,
                      placeholderBuilder: (context) => const SizedBox(
                        width: logoSize,
                        height: logoSize,
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Away team abbreviation
                    Text(
                      game.awayData.teamId,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Centered score
                    Text(
                      '${game.awayData.teamScore} - ${game.homeData.teamScore}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // Home team abbreviation
                    Text(
                      game.homeData.teamId,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Home team logo
                    SvgPicture.network(
                      'https://assets.nhle.com/logos/nhl/svg/${game.homeData.teamId}_light.svg',
                      width: logoSize,
                      height: logoSize,
                      placeholderBuilder: (context) => const SizedBox(
                        width: logoSize,
                        height: logoSize,
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
