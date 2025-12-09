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
  bool _isLoadingGoals = false;
  String? _error;
  Timer? _gameUpdateTimer;
  Timer? _homeScreenTimer;
  StreamSubscription<DocumentSnapshot>? _gameStreamSubscription;

  List<Game> get games => _games;
  Game? get selectedGame => _selectedGame;
  bool get isLoading => _isLoading;
  bool get isLoadingGoals => _isLoadingGoals;
  String? get error => _error;

  /// Fetch games from Firestore for a specific date
  Future<void> getGamesOnDate(DateTime date) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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

      final snapshot = await _firestore
          .collection('games')
          .where(
            'start_time',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDayUTC),
          )
          .where('start_time', isLessThan: Timestamp.fromDate(endOfDayUTC))
          .orderBy('start_time', descending: false)
          .get();

      _games = snapshot.docs
          .map((doc) => Game.fromFirestore(doc.data(), doc.id))
          .toList();

      // If no games found and querying today, trigger ingestion
      if (_games.isEmpty && _isToday(date)) {
        debugPrint('No games found for today, triggering ingestion...');
        await _callIngestTodaysGames();

        // Retry query after ingestion
        final retrySnapshot = await _firestore
            .collection('games')
            .where(
              'start_time',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDayUTC),
            )
            .where('start_time', isLessThan: Timestamp.fromDate(endOfDayUTC))
            .orderBy('start_time', descending: false)
            .get();

        _games = retrySnapshot.docs
            .map((doc) => Game.fromFirestore(doc.data(), doc.id))
            .toList();
      }

      // Trigger updates for non-final games (don't await)
      for (final game in _games) {
        if (game.status != 'FINAL') {
          _callUpdateGameFunction(game.id);
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if date is today
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Fetch today's games from Firestore (for home screen)
  Future<void> fetchTodaysGames() async {
    await getGamesOnDate(DateTime.now());
  }

  /// Start periodic updates for home screen (every 10 seconds)
  void startHomeScreenUpdates() {
    stopHomeScreenUpdates(); // Clear any existing home screen timer
    fetchTodaysGames(); // Initial fetch
    _homeScreenTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      fetchTodaysGames();
    });
  }

  /// Stop home screen updates
  void stopHomeScreenUpdates() {
    _homeScreenTimer?.cancel();
    _homeScreenTimer = null;
  }

  /// Select a game and start live updates via Firebase Functions (every 1 second)
  void selectGameAndStartLiveUpdates(String gameId) {
    // Clear existing game-specific timers/subscriptions only
    _gameUpdateTimer?.cancel();
    _gameUpdateTimer = null;
    _gameStreamSubscription?.cancel();
    _gameStreamSubscription = null;

    // Listen to Firestore for real-time updates
    _gameStreamSubscription =
        _firestore.collection('games').doc(gameId).snapshots().listen(
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
    _gameUpdateTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
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
      // Silently handle rate limiting errors (update too frequent)
      final errorMessage = e.toString().toLowerCase();
      if (!errorMessage.contains('too frequent') &&
          !errorMessage.contains('minimum 2 seconds')) {
        // Only print non-rate-limit errors
        debugPrint('Error calling updateGame function: $e');
      }
      // Firestore listener will handle updates regardless
    }
  }

  /// Call Firebase Function to ingest today's games
  Future<void> _callIngestTodaysGames() async {
    try {
      debugPrint('🔵 Calling ingestTodaysGames function...');
      final callable = _functions.httpsCallable('ingestTodaysGames');
      final result = await callable.call({});
      debugPrint('✅ Ingestion complete: ${result.data}');
    } catch (e) {
      debugPrint('❌ Error calling ingestTodaysGames function: $e');
      // Don't throw - allow app to continue even if ingestion fails
    }
  }

  /// Call Firebase Function to fetch goals for a game
  Future<void> fetchGoalsForGame(String gameId) async {
    _isLoadingGoals = true;
    notifyListeners();

    try {
      debugPrint('🔵 Attempting to call fetchGoals for game: $gameId');
      debugPrint('🔵 Functions instance: $_functions');

      final callable = _functions.httpsCallable('fetchGoals');
      debugPrint('🔵 Created callable function');

      final result = await callable.call({'gameId': gameId});
      debugPrint('✅ Successfully called fetchGoals: ${result.data}');

      // Goals will be updated via Firestore listener
      _isLoadingGoals = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error fetching goals: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');
      if (e is Exception) {
        debugPrint('❌ Exception details: $e');
      }
      _isLoadingGoals = false;
      notifyListeners();
    }
  }

  /// Stop all timers and subscriptions
  void stopUpdates() {
    _gameUpdateTimer?.cancel();
    _gameUpdateTimer = null;
    _homeScreenTimer?.cancel();
    _homeScreenTimer = null;
    _gameStreamSubscription?.cancel();
    _gameStreamSubscription = null;
  }

  /// Clear selected game
  void clearSelectedGame() {
    _gameUpdateTimer?.cancel();
    _gameUpdateTimer = null;
    _gameStreamSubscription?.cancel();
    _gameStreamSubscription = null;
    _selectedGame = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopUpdates();
    super.dispose();
  }
}
