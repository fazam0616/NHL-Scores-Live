class TeamData {
  final String teamId;
  final String teamName;
  final int teamScore;

  TeamData({
    required this.teamId,
    required this.teamName,
    required this.teamScore,
  });

  factory TeamData.fromMap(Map<String, dynamic> data) {
    return TeamData(
      teamId: data['team_id'] ?? '',
      teamName: data['team_name'] ?? '',
      teamScore: data['team_score'] ?? 0,
    );
  }
}

class Goal {
  final String scorer;
  final String goalie;
  final String? primaryAssist;
  final String? secondaryAssist;
  final int period;
  final String timeInPeriod;
  final String? totalTime;
  final bool? isHome;

  Goal({
    required this.scorer,
    required this.goalie,
    this.primaryAssist,
    this.secondaryAssist,
    required this.period,
    required this.timeInPeriod,
    this.totalTime,
    this.isHome,
  });

  factory Goal.fromMap(Map<String, dynamic> data) {
    return Goal(
      scorer: data['scorer'] ?? 'Unknown',
      goalie: data['goalie'] ?? 'Unknown',
      primaryAssist: data['primaryAssist'],
      secondaryAssist: data['secondaryAssist'],
      period: data['period'] ?? 1,
      timeInPeriod: data['timeInPeriod'] ?? '00:00',
      totalTime: data['totalTime'],
      isHome: data['isHome'],
    );
  }
}

class Game {
  final String id;
  final TeamData homeData;
  final TeamData awayData;
  final DateTime startTime;
  final String status;
  final Map<String, dynamic>? raw;
  final Map<String, Goal>? goals;

  Game({
    required this.id,
    required this.homeData,
    required this.awayData,
    required this.startTime,
    required this.status,
    this.raw,
    this.goals,
  });

  factory Game.fromFirestore(Map<String, dynamic> data, String id) {
    Map<String, Goal>? goalsMap;
    if (data['goals'] != null) {
      final goalsData = data['goals'] as Map<String, dynamic>;
      goalsMap = goalsData.map(
        (key, value) =>
            MapEntry(key, Goal.fromMap(value as Map<String, dynamic>)),
      );
    }

    return Game(
      id: id,
      homeData: TeamData.fromMap(data['home_data'] ?? {}),
      awayData: TeamData.fromMap(data['away_data'] ?? {}),
      startTime: (data['start_time'] as dynamic)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'SCHEDULED',
      raw: data['raw'] as Map<String, dynamic>?,
      goals: goalsMap,
    );
  }

  bool get isLive => status == 'LIVE' || status == 'CRIT';
  bool get isFinal => status == 'FINAL' || status == 'OFF';
  bool get isScheduled => status == 'SCHEDULED' || status == 'PREGAME';
}
