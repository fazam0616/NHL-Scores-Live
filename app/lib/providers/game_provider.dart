import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/game_model.dart';

class GameProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  List<Game> _games = [];
  Game? _selectedGame;
  bool _isLoading = false;
  String? _error;
  Timer? _updateTimer;
  StreamSubscription<DocumentSnapshot>? _gameStreamSubscription;

  List<Game> get games => _games;
  Game? get selectedGame => _selectedGame;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch games from Firestore for a specific date
  Future<void> getGamesOnDate(DateTime date) async {
    try {
      _error = null;

      // Get start and end of the specified date in EST (UTC-5)
      // NHL games are scheduled in EST, so we need to query based on EST dates
      final dateUtc = date.toUtc();
      final estDate = dateUtc.subtract(
        const Duration(hours: 5),
      ); // Convert to EST
      final startOfDayEST = DateTime.utc(
        estDate.year,
        estDate.month,
        estDate.day,
      );
      final endOfDayEST = startOfDayEST.add(const Duration(days: 1));

      // Convert EST boundaries back to UTC for Firestore query
      final startOfDayUTC = startOfDayEST.add(const Duration(hours: 5));
      final endOfDayUTC = endOfDayEST.add(const Duration(hours: 5));

      final snapshot =
          await _firestore
              .collection('games')
              .where(
                'start_time',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDayUTC),
              )
              .where('start_time', isLessThan: Timestamp.fromDate(endOfDayUTC))
              .orderBy('start_time', descending: false)
              .get();

      _games =
          snapshot.docs
              .map((doc) => Game.fromFirestore(doc.data(), doc.id))
              .toList();

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Fetch today's games from Firestore (for home screen)
  Future<void> fetchTodaysGames() async {
    await getGamesOnDate(DateTime.now());
  }

  /// Start periodic updates for home screen (every 4 seconds)
  void startHomeScreenUpdates() {
    stopUpdates(); // Clear any existing timer
    fetchTodaysGames(); // Initial fetch
    _updateTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      fetchTodaysGames();
    });
  }

  /// Select a game and start live updates via Firebase Functions (every 1 second)
  void selectGameAndStartLiveUpdates(String gameId) {
    stopUpdates(); // Clear existing timers/subscriptions

    // Listen to Firestore for real-time updates
    _gameStreamSubscription = _firestore
        .collection('games')
        .doc(gameId)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists) {
              _selectedGame = Game.fromFirestore(snapshot.data()!, snapshot.id);
              _error = null;
            } else {
              _error = 'Game not found';
              _selectedGame = null;
            }
            notifyListeners();
          },
          onError: (error) {
            _error = error.toString();
            notifyListeners();
          },
        );

    // Call updateGame function every 1 second if game is live
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_selectedGame?.isLive == true) {
        await _callUpdateGameFunction(gameId);
      }
    });
  }

  /// Call Firebase Function to update game data
  Future<void> _callUpdateGameFunction(String gameId) async {
    try {
      final callable = _functions.httpsCallable('updateGame');
      await callable.call({'gameId': gameId});
    } catch (e) {
      // Silently fail - Firestore listener will handle updates
      debugPrint('Error calling updateGame function: $e');
    }
  }

  /// Call Firebase Function to fetch goals for a game
  Future<void> fetchGoalsForGame(String gameId) async {
    try {
      debugPrint('🔵 Attempting to call fetchGoals for game: $gameId');
      debugPrint('🔵 Functions instance: $_functions');

      final callable = _functions.httpsCallable('fetchGoals');
      debugPrint('🔵 Created callable function');

      final result = await callable.call({'gameId': gameId});
      debugPrint('✅ Successfully called fetchGoals: ${result.data}');

      // Goals will be updated via Firestore listener
    } catch (e) {
      debugPrint('❌ Error fetching goals: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');
      if (e is Exception) {
        debugPrint('❌ Exception details: $e');
      }
    }
  }

  /// Stop all timers and subscriptions
  void stopUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _gameStreamSubscription?.cancel();
    _gameStreamSubscription = null;
  }

  /// Clear selected game
  void clearSelectedGame() {
    stopUpdates();
    _selectedGame = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopUpdates();
    super.dispose();
  }
}
