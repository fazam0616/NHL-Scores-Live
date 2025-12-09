const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { Timestamp, FieldValue } = require("firebase-admin/firestore");

// Initialize with demo project for emulator
admin.initializeApp({
  projectId: "quadlii-nhl-scores",
});

const db = admin.firestore();

/**
 * Helper function: Update teams from Stats API (includes all historical teams)
 */
async function updateTeams() {
  try {
    // Retry logic for rate limiting
    let retries = 3;
    let teamsResponse;
    
    while (retries > 0) {
      teamsResponse = await fetch("https://api.nhle.com/stats/rest/en/team");
      
      if (teamsResponse.status === 429) {
        const retryAfter = parseInt(teamsResponse.headers.get('retry-after') || '60');
        console.log(`Rate limited. Waiting ${retryAfter} seconds before retry...`);
        await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
        retries--;
        continue;
      }
      
      if (!teamsResponse.ok) {
        throw new Error(`Failed to fetch teams: ${teamsResponse.status} ${teamsResponse.statusText}`);
      }
      
      break;
    }
    
    if (teamsResponse.status === 429) {
      throw new Error('Failed to fetch teams after multiple retries due to rate limiting');
    }

    const teamsData = await teamsResponse.json();

    const teams = teamsData.data || [];
    
    for (const team of teams) {
      // Check if team already exists by abbreviation
      const existingTeams = await db.collection("teams")
        .where("abbreviation", "==", team.triCode)
        .limit(1)
        .get();
      
      if (existingTeams.empty) {
        const teamRef = db.collection("teams").doc();
        
        await teamRef.set({
          team_id: team.triCode,
          team_name: team.fullName,
          abbreviation: team.triCode,
          franchise_id: team.franchiseId,
          logourl: `https://assets.nhle.com/logos/nhl/svg/${team.triCode}_light.svg`,
        });
        
        console.log(`Team ${team.triCode} (${team.fullName}) created with ID: ${teamRef.id}`);
        
        // Wait 100ms between team operations to avoid rate limiting
      }
    }
  } catch (error) {
    console.error("Error updating teams:", error);
    throw error;
  }
}

/**
 * Helper function: Fetch team data with caching
 * Returns team stats including recent games, wins, losses, and total goals
 * @param {string} teamId - Team abbreviation (e.g., 'TOR', 'MTL')
 */
async function fetchTeamData(teamId) {
  try {
    // Find team document by abbreviation
    const teamQuery = await db.collection("teams")
      .where("abbreviation", "==", teamId)
      .limit(1)
      .get();
    
    if (teamQuery.empty) {
      throw new Error(`Team ${teamId} not found`);
    }
    
    const teamDoc = teamQuery.docs[0];
    const teamData = teamDoc.data();
    const franchiseId = teamData.franchise_id;
    
    if (!franchiseId || franchiseId === -1) {
      throw new Error(`Team ${teamId} has no valid franchise ID`);
    }
    
    // Check if we need to update cached data
    let needsUpdate = true;
    if (teamData.last_updated) {
      const lastUpdated = teamData.last_updated.toDate();
      
      // Check if there are any FINAL games since last update
      const recentGamesQuery = await db.collection("games")
        .where("status", "==", "FINAL")
        .where("start_time", ">", Timestamp.fromDate(lastUpdated))
        .limit(1)
        .get();
      
      needsUpdate = !recentGamesQuery.empty;
    }
    
    if (!needsUpdate && teamData.recent_games) {
      // Return cached data
      return {
        success: true,
        teamId,
        franchiseId,
        teamName: teamData.team_name,
        recentGames: teamData.recent_games || [],
        gamesPlayed: teamData.games_played || 0,
        wins: teamData.wins || 0,
        losses: teamData.losses || 0,
        totalGoals: teamData.total_goals || 0,
        source: "cache",
      };
    }
    
    // Fetch recent games (2 queries: home and away)
    const homeGamesQuery = await db.collection("games")
      .where("home_data.franchise_id", "==", franchiseId)
      .where("status", "==", "FINAL")
      .orderBy("start_time", "desc")
      .limit(5)
      .get();
    
    const awayGamesQuery = await db.collection("games")
      .where("away_data.franchise_id", "==", franchiseId)
      .where("status", "==", "FINAL")
      .orderBy("start_time", "desc")
      .limit(5)
      .get();
    
    // Combine and sort by start_time
    const allGames = [];
    homeGamesQuery.forEach((doc) => {
      allGames.push({ id: doc.id, ...doc.data() });
    });
    awayGamesQuery.forEach((doc) => {
      allGames.push({ id: doc.id, ...doc.data() });
    });
    
    // Sort by start_time descending and take last 5
    allGames.sort((a, b) => b.start_time.toDate() - a.start_time.toDate());
    const recentGames = allGames.slice(0, 5);
    
    // Calculate stats from ALL final games (not just recent 5)
    const allHomeGamesQuery = await db.collection("games")
      .where("home_data.franchise_id", "==", franchiseId)
      .where("status", "==", "FINAL")
      .get();
    
    const allAwayGamesQuery = await db.collection("games")
      .where("away_data.franchise_id", "==", franchiseId)
      .where("status", "==", "FINAL")
      .get();
    
    let gamesPlayed = 0;
    let wins = 0;
    let losses = 0;
    let totalGoals = 0;
    
    // Process home games
    allHomeGamesQuery.forEach((doc) => {
      const game = doc.data();
      gamesPlayed++;
      const homeScore = game.home_data.team_score || 0;
      const awayScore = game.away_data.team_score || 0;
      totalGoals += homeScore;
      
      if (homeScore > awayScore) {
        wins++;
      } else {
        losses++;
      }
    });
    
    // Process away games
    allAwayGamesQuery.forEach((doc) => {
      const game = doc.data();
      gamesPlayed++;
      const homeScore = game.home_data.team_score || 0;
      const awayScore = game.away_data.team_score || 0;
      totalGoals += awayScore;
      
      if (awayScore > homeScore) {
        wins++;
      } else {
        losses++;
      }
    });
    
    // Update team document with cached data
    const recentGameIds = recentGames.map(g => g.id);
    await teamDoc.ref.update({
      recent_games: recentGameIds,
      games_played: gamesPlayed,
      wins,
      losses,
      total_goals: totalGoals,
      last_updated: FieldValue.serverTimestamp(),
    });
    
    return {
      success: true,
      teamId,
      franchiseId,
      teamName: teamData.team_name,
      recentGames: recentGameIds,
      gamesPlayed,
      wins,
      losses,
      totalGoals,
      source: "api",
    };
  } catch (error) {
    console.error(`Error fetching team data for ${teamId}:`, error);
    throw error;
  }
}

/**
 * Helper function: Create a new game document from either Schedule API or Stats API format
 * @param {Object} gameData - Game data from either API
 * @param {Object} options - Options object with optional teamLookup and gameDate
 * @param {boolean} setDB - Whether to write to database
 */
async function createGame(gameData, options = {}, setDB = true) {
  const gameId = gameData.id.toString();
  
  // Detect API format based on presence of teamLookup
  // If teamLookup is provided, we're using Stats API format
  // Otherwise, we're using Schedule API format
  const isStatsAPI = options.teamLookup !== undefined;
  
  let gameDoc;
  
  if (isStatsAPI) {
    // Stats API format - uses teamLookup to map numeric IDs to team data
    const { teamLookup } = options;
    
    const homeTeam = teamLookup.get(gameData.homeTeamId) || { triCode: "UNK", fullName: "Unknown" };
    const awayTeam = teamLookup.get(gameData.visitingTeamId) || { triCode: "UNK", fullName: "Unknown" };
    const startTime = Timestamp.fromDate(new Date(gameData.easternStartTime));
    
    // Map gameStateId to readable status
    const statusMap = {
      1: "SCHEDULED",
      2: "PREGAME", 
      3: "LIVE",
      4: "LIVE",
      5: "LIVE",
      6: "FINAL",
      7: "FINAL"
    };
    
    gameDoc = {
      gameid: gameId,
      start_time: startTime,
      home_data: {
        team_id: homeTeam.triCode,
        team_name: homeTeam.fullName,
        team_score: gameData.homeScore || 0,
        franchise_id: homeTeam.franchiseId || -1,
      },
      away_data: {
        team_id: awayTeam.triCode,
        team_name: awayTeam.fullName ,
        team_score: gameData.visitingScore || 0,
        franchise_id: awayTeam.franchiseId || -1,
      },
      status: statusMap[gameData.gameStateId] || "SCHEDULED",
      raw: gameData,
    };
  } else {
    // Schedule API format - has embedded team data, fetch live scores
    const { gameDate } = options;
    const startTime = Timestamp.fromDate(new Date(gameData.startTimeUTC));
    
    // Fetch current scores from API
    const scoreResponse = await fetch(`https://api-web.nhle.com/v1/score/${gameDate}`);
    const scoreData = await scoreResponse.json();
    
    // Find the specific game in the games list
    const games = scoreData.games || [];
    const currentGame = games.find((g) => g.id.toString() === gameId);
    
    // Use scores from API if found, otherwise default to 0
    const awayScore = currentGame?.awayTeam?.score || 0;
    const homeScore = currentGame?.homeTeam?.score || 0;

    // Get franchise IDs from teams collection
    const homeTeamDoc = await db.collection("teams")
      .where("abbreviation", "==", gameData.homeTeam.abbrev)
      .limit(1)
      .get();
    const awayTeamDoc = await db.collection("teams")
      .where("abbreviation", "==", gameData.awayTeam.abbrev)
      .limit(1)
      .get();
    
    const home_franchiseId = homeTeamDoc.docs[0]?.data()?.franchise_id || -1;
    const away_franchiseId = awayTeamDoc.docs[0]?.data()?.franchise_id || -1;      
    
    gameDoc = {
      gameid: gameId,
      start_time: startTime,
      home_data: {
        team_id: gameData.homeTeam.abbrev,
        team_name: gameData.homeTeam.commonName.default,
        team_score: homeScore,
        franchise_id: home_franchiseId,
      },
      away_data: {
        team_id: gameData.awayTeam.abbrev,
        team_name: gameData.awayTeam.commonName.default,
        team_score: awayScore,
        franchise_id: away_franchiseId,
      },
      status: gameData.gameState || "SCHEDULED",
      raw: gameData,
    };
  }
  
  if (setDB) {
    await db.collection("games").doc(gameId).set(gameDoc);
    console.log(`Game ${gameId} created`);
  }

  return {
    gameId: gameId,
    gameDoc: gameDoc,
  };
}

/**
 * Standalone function to ingest game/team data
 * Call this with: npm run ingest
 * @param {Object} options - Ingestion options
 * @param {number} options.backfillYear - Optional year to start backfilling from (e.g., 2024)
 */
async function ingestData(options = {}) {
  try {
    console.log("Starting data ingestion...");

    const { backfillYear } = options;
    let gamesToProcess = [];
    let dateRange = "";

    if (backfillYear) {
      // Backfill mode: use Stats API bulk fetch for efficiency
      console.log(`\nBACKFILL MODE: Fetching games from ${backfillYear} season to present\n`);
      
      // Build team lookup map first
      console.log('Building team lookup map...');
      const teamsResponse = await fetch("https://api.nhle.com/stats/rest/en/team");
      const teamsData = await teamsResponse.json();
      const teamLookup = new Map();
      for (const team of teamsData.data || []) {
        teamLookup.set(team.id, { triCode: team.triCode, fullName: team.fullName, franchiseId: team.franchiseId });
      }
      console.log(`Loaded ${teamLookup.size} teams\n`);
      
      // Generate season strings from backfillYear to current year
      const currentYear = new Date().getFullYear();
      const seasons = [];
      for (let year = backfillYear; year <= currentYear; year++) {
        seasons.push(`${year}${year + 1}`);
      }
      
      console.log(`Processing ${seasons.length} seasons: ${seasons.join(", ")}\n`);
      dateRange = `${backfillYear}-${currentYear + 1} seasons`;
      
      // Fetch all games for each season using Stats API
      for (const season of seasons) {
        console.log(`\nFetching season ${season}...`);
        
        try {
          // Use Stats API with season filter - gets all games in one call
          const gamesResponse = await fetch(
            `https://api.nhle.com/stats/rest/en/game?cayenneExp=season=${season}&limit=-1`
          );
          
          if (!gamesResponse.ok) {
            console.warn(`  Failed to fetch season ${season}: ${gamesResponse.status}`);
            continue;
          }
          
          const gamesData = await gamesResponse.json();
          const games = gamesData.data || [];
          
          console.log(`  Season ${season}: Found ${games.length} games`);
          
          // Add games with minimal data needed for processing
          for (const game of games) {
            gamesToProcess.push({
              game,
              gameDate: game.gameDate,
              isStatsAPI: true,
              teamLookup // Pass team lookup to each game for processing
            });
          }
          
        } catch (error) {
          console.warn(`  Error fetching season ${season}:`, error.message);
        }
      }
      
      console.log(`\nTotal games found: ${gamesToProcess.length}\n`);
      
    } else {
      // Normal mode: fetch only today's games
      const today = new Date();
      const estOffset = -5; // EST is UTC-5
      const estDate = new Date(today.getTime() + estOffset * 60 * 60 * 1000);
      const dateString = estDate.toISOString().split("T")[0];
      
      console.log(`Fetching games for date: ${dateString}`);
      dateRange = dateString;


      const scheduleResponse = await fetch(
        `https://api-web.nhle.com/v1/schedule/${dateString}`
      );
      const scheduleData = await scheduleResponse.json();
      
      const gameWeek = scheduleData.gameWeek || [];
      
      for (const day of gameWeek) {
        if (day.date === dateString && day.games) {
          for (const game of day.games) {
            gamesToProcess.push({
              game,
              gameDate: dateString
            });
          }
        }
      }
      
      console.log(`Found ${gamesToProcess.length} games for today`);
    }
    
    // Ensure teams exist (do once at the beginning)
    


    console.log("\nEnsuring teams are up to date...");
    await updateTeams();
    
    // Process each game
    console.log(`\nProcessing ${gamesToProcess.length} games...\n`);
    let created = 0;
    let skipped = 0;
    let updated = 0;
    
    if (backfillYear && gamesToProcess.length > 0 && gamesToProcess[0].isStatsAPI) {
      // Batch processing for Stats API (bulk backfill)
      const BATCH_SIZE = 500; // Firestore limit is 500 operations per batch
      const batches = [];
      
      for (let i = 0; i < gamesToProcess.length; i += BATCH_SIZE) {
        const batchGames = gamesToProcess.slice(i, i + BATCH_SIZE);
        batches.push(batchGames);
      }
      
      console.log(`Processing ${batches.length} batches of up to ${BATCH_SIZE} games each...\n`);
      
      for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        const batch = db.batch();
        const batchGames = batches[batchIndex];
        
        // Check which games don't exist and prepare batch write
        for (const { game, teamLookup } of batchGames) {
          const gameId = game.id.toString();
          const gameRef = db.collection("games").doc(gameId);
          const gameDoc = await gameRef.get();
          
          if (!gameDoc.exists) {
            const { gameDoc: gameData } = await createGame(game, { teamLookup }, false);
            batch.set(gameRef, gameData);
            created++;
          } else {
            const existingData = gameDoc.data();
            const existingStatus = existingData.status;
            
            // Check if game was SCHEDULED or LIVE - need to update
            if (existingStatus === "SCHEDULED" || existingStatus === "LIVE" || existingStatus === "PREGAME" || existingStatus === "CRIT") {
              const { gameDoc: gameData } = await createGame(game, { teamLookup }, false);
              
              // Check if status or scores changed
              const statusChanged = existingStatus !== gameData.status;
              const scoresChanged = 
                existingData.home_data.team_score !== gameData.home_data.team_score ||
                existingData.away_data.team_score !== gameData.away_data.team_score;
              
              if (statusChanged || scoresChanged) {
                batch.update(gameRef, gameData);
                updated++;
              } else {
                skipped++;
              }
            } else {
              skipped++;
            }
          }
        }
        
        // Commit the batch
        await batch.commit();
        
        console.log(`Progress: ${Math.min((batchIndex + 1) * BATCH_SIZE, gamesToProcess.length)}/${gamesToProcess.length} games processed (${created} created, ${updated} updated, ${skipped} skipped)`);
        
        // Add delay between batches to avoid overwhelming emulator
        if (batchIndex < batches.length - 1) {
          await new Promise(resolve => setTimeout(resolve, 500));
        }
      }
    } else {
      // Individual processing for normal mode (Schedule API)
      for (let i = 0; i < gamesToProcess.length; i++) {
        const { game, gameDate } = gamesToProcess[i];
        const gameId = game.id.toString();
        
        // Check if game exists in database
        const gameRef = db.collection("games").doc(gameId);
        const gameDoc = await gameRef.get();
        
        if (!gameDoc.exists) {
          await createGame(game, { gameDate });
          created++;
        } else {
          const existingData = gameDoc.data();
          const existingStatus = existingData.status;
          
          // Only update if game is not FINAL
          if (existingStatus !== "FINAL") {
            const gameStartTime = new Date(game.startTimeUTC);
            const now = new Date();
            
            // Only update if current time is at or after the scheduled start time
            // (game should have started or be close to starting)
            if (now >= gameStartTime) {
              const { gameDoc: gameData } = await createGame(game, { gameDate }, false);
              
              // Check if status or scores changed
              const statusChanged = existingStatus !== gameData.status;
              const scoresChanged = 
                existingData.home_data.team_score !== gameData.home_data.team_score ||
                existingData.away_data.team_score !== gameData.away_data.team_score;
              
              if (statusChanged || scoresChanged) {
                await gameRef.update(gameData);
                updated++;
              } else {
                skipped++;
              }
            } else {
              skipped++;
            }
          } else {
            skipped++;
          }
        }
      }
    }

    console.log("\n=== Data Ingestion Complete ===");
    console.log(`Date Range: ${dateRange}`);
    console.log(`Games Found: ${gamesToProcess.length}`);
    console.log(`Games Created: ${created}`);
    console.log(`Games Updated: ${updated}`);
    console.log(`Games Skipped: ${skipped}`);
    console.log("================================\n");
    
    return {
      success: true,
      message: "Data ingestion completed",
      dateRange,
      gamesFound: gamesToProcess.length,
      gamesCreated: created,
      gamesUpdated: updated,
      gamesSkipped: skipped,
    };
  } catch (error) {
    console.error("Error during ingestion:", error);
    throw error;
  }
}

/**
 * Helper function: Fetch goals from play-by-play API and store in game document
 */
async function fetchGameGoals(gameId) {
  try {
    const gameRef = db.collection("games").doc(gameId);
    
    // Check if goals already exist
    const gameDoc = await gameRef.get();
    if (!gameDoc.exists) {
      throw new Error(`Game ${gameId} not found`);
    }
    
    const gameData = gameDoc.data();
    
    
    // If goals already exist, return them
    if (gameData.status === "FINAL" && gameData.goals && Object.keys(gameData.goals).length > 0) {
      return {
        success: true,
        gameId,
        goals: gameData.goals,
        source: "database",
      };
    }

    
    // Fetch play-by-play data from API
    const playByPlayResponse = await fetch(
      `https://api-web.nhle.com/v1/gamecenter/${gameId}/play-by-play`
    );
    
    if (!playByPlayResponse.ok) {
      throw new Error(`Failed to fetch play-by-play: ${playByPlayResponse.status}`);
    }
    
    const playByPlayData = await playByPlayResponse.json();
    const plays = playByPlayData.plays || [];
    
    // Filter for goal events (eventId 505)
    const goalPlays = plays.filter((play) => play.typeDescKey === "goal");
    
    // Sort goals by period and time
    goalPlays.sort((a, b) => {
      const periodA = a.periodDescriptor?.number || 1;
      const periodB = b.periodDescriptor?.number || 1;
      
      if (periodA !== periodB) {
        return periodA - periodB;
      }
      
      // If same period, sort by time in period
      const timeA = a.timeInPeriod || "00:00";
      const timeB = b.timeInPeriod || "00:00";
      
      // Convert MM:SS to total seconds for comparison
      const [minA, secA] = timeA.split(':').map(Number);
      const [minB, secB] = timeB.split(':').map(Number);
      const totalSecsA = minA * 60 + secA;
      const totalSecsB = minB * 60 + secB;
      
      return totalSecsA - totalSecsB;
    });
    
    // Build goals object keyed by time
    const goals = {};
    let prevHomeScore = 0;
    let prevAwayScore = 0;
    
    for (const play of goalPlays) {
      const timeInPeriod = play.timeInPeriod || "00:00";
      const period = play.periodDescriptor?.number || 1;

      // Determine current scores from play details
      const homeScore = play.details.homeScore || 0;
      const awayScore = play.details.awayScore || 0;

      // Determine who scored by comparing to previous scores
      const homeScored = homeScore > prevHomeScore;
      const awayScored = awayScore > prevAwayScore;
      
      // Update previous scores for next iteration
      prevHomeScore = homeScore;
      prevAwayScore = awayScore;

      // Get scorer, goalie, and assists
      const details = play.details || {};
      const scoringPlayerId = details.scoringPlayerId;
      const goalieInNetId = details.goalieInNetId;
      const assist1PlayerId = details.assist1PlayerId;
      const assist2PlayerId = details.assist2PlayerId;
      
      // Get player names from rosterSpots
      const rosterSpots = playByPlayData.rosterSpots || [];
      const getPlayerName = (playerId) => {
        if (!playerId) return null;
        const player = rosterSpots.find((spot) => spot.playerId === playerId);
        if (!player) return "Unknown";
        const firstName = player.firstName?.default || "";
        const lastName = player.lastName?.default || "";
        if (!firstName || !lastName) return "Unknown";
        return `${firstName.charAt(0)}. ${lastName}`;
      };
      
      const scorerName = getPlayerName(scoringPlayerId);
      const goalieName = getPlayerName(goalieInNetId);
      const primaryAssist = getPlayerName(assist1PlayerId);
      const secondaryAssist = getPlayerName(assist2PlayerId);
      
      // Calculate total in-game time
      // Each period is 20 minutes, so add (period - 1) * 20 to the time in period
      const [minutes, seconds] = timeInPeriod.split(':').map(Number);
      const totalMinutes = (period - 1) * 20 + minutes;
      const totalTimeFormatted = `${totalMinutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
      
      // Store with period info to make time unique
      const timeKey = `P${period}-${timeInPeriod}`;
      
      goals[timeKey] = {
        scorer: scorerName,
        goalie: goalieName,
        primaryAssist: primaryAssist,
        secondaryAssist: secondaryAssist,
        period: period,
        timeInPeriod: timeInPeriod,
        totalTime: totalTimeFormatted,
        isHome: homeScored,
      };
    }
    
    // Update game document with goals
    await gameRef.update({ goals });
    
    return {
      success: true,
      gameId,
      goals,
      source: "api",
    };
  } catch (error) {
    console.error(`Error fetching goals for game ${gameId}:`, error);
    throw error;
  }
}

/**
 * Helper function: Fetch and update a specific game with locking
 */
async function fetchGame(gameId) {
  const gameRef = db.collection("games").doc(gameId);
  
  // First check game status
  const gameDoc = await gameRef.get();
  
  if (!gameDoc.exists) {
    throw new Error(`Game ${gameId} not found`);
  }
  
  const gameData = gameDoc.data();
  const gameStatus = gameData.status;
  
  // Only skip API call if game is already FINAL
  if (gameStatus === "FINAL") {
    return {
      success: true,
      gameId,
      home_score: gameData.home_data.team_score || 0,
      away_score: gameData.away_data.team_score || 0,
      status: gameStatus,
      source: "database",
    };
  }
  
  // Game is not final - check API for updates (SCHEDULED -> LIVE -> FINAL transitions)
  return db.runTransaction(async (transaction) => {
    const gameDoc = await transaction.get(gameRef);
    
    if (!gameDoc.exists) {
      throw new Error(`Game ${gameId} not found`);
    }
    
    const gameData = gameDoc.data();
    
    // Check last updated timestamp (2 seconds minimum between updates)
    if (gameData?.last_updated) {
      const lastUpdated = gameData.last_updated.toDate();
      const now = new Date();
      const timeDiff = (now.getTime() - lastUpdated.getTime()) / 1000;
      
      if (timeDiff < 2) {
        throw new Error("Update too frequent - minimum 2 seconds between updates");
      }
    }
    
    // Check if locked
    if (gameData?.locked) {
      const error = new Error("Game is locked");
      error.status = 409;
      throw error;
    }
    
    // Set lock
    transaction.update(gameRef, { locked: true });
    
    // Fetch latest score from API
    const scoreResponse = await fetch(`https://api-web.nhle.com/v1/score/now`);

    const scoreData = await scoreResponse.json();
    
    // Find the game in the response
    const games = scoreData.games || [];
    const updatedGame = games.find((g) => g.id.toString() === gameId);
    
    if (!updatedGame) {
      // Remove lock before throwing
      transaction.update(gameRef, { locked: false });
      throw new Error(`Game ${gameId} not found in score API`);
    }
    
    // Update game document
    transaction.update(gameRef, {
      "home_data.team_score": updatedGame.homeTeam.score || 0,
      "away_data.team_score": updatedGame.awayTeam.score || 0,
      status: updatedGame.gameState || "SCHEDULED",
      raw: updatedGame,
      last_updated: FieldValue.serverTimestamp(),
      locked: false, // Remove lock
    });
    
    return {
      success: true,
      gameId,
      home_score: updatedGame.homeTeam.score || 0,
      away_score: updatedGame.awayTeam.score || 0,
      status: updatedGame.gameState,
      source: "api",
    };
  });
}

/**
 * Callable function to fetch goals for a specific game (v2)
 * Call with: callable.call({'gameId': '2025020001'})
 */
exports.fetchGoals = onCall(async (request) => {
  const gameId = request?.data?.gameId;
  
  if (!gameId) {
    throw new HttpsError(
      'invalid-argument',
      'gameId parameter is required'
    );
  }
  
  console.log('Fetching goals for game:', gameId);
  
  const result = await fetchGameGoals(gameId);
  
  return result;
});

/**
 * Callable function to fetch and update a specific game (v2)
 * Call with: callable.call({'gameId': '2025020001'})
 */
exports.updateGame = onCall(async (request) => {
  const gameId = request?.data?.gameId;
  
  if (!gameId) {
    throw new HttpsError(
      'invalid-argument',
      'gameId parameter is required'
    );
  }
  
  const result = await fetchGame(gameId);
  
  return result;
});

/**
 * Callable function to ingest today's games (v2)
 * Call with: callable.call({})
 */
exports.ingestTodaysGames = onCall(async (request) => {
  console.log('Ingesting today\'s games');
  
  const result = await ingestData();
  
  return result;
});

/**
 * Callable function to fetch team data (v2)
 * Call with: callable.call({'teamId': 'TOR'})
 */
exports.fetchTeamData = onCall(async (request) => {
  const teamId = request?.data?.teamId;
  
  if (!teamId) {
    throw new HttpsError(
      'invalid-argument',
      'teamId parameter is required'
    );
  }
  
  console.log('Fetching team data for:', teamId);
  
  const result = await fetchTeamData(teamId);
  
  return result;
});

/**
 * Firestore trigger: Executes when a game document is created
 */
// exports.onGameCreated = functions.firestore
//   .document("games/{gameId}")
//   .onCreate(async (snap, context) => {
//     const gameData = snap.data();
//     functions.logger.info(`New game created: ${context.params.gameId}`, gameData);

//     // TODO: Add any post-creation processing here
//     // e.g., send notifications, update statistics, etc.

//     return null;
//   });

// /**
//  * Firestore trigger: Executes when a game document is updated
//  */
// exports.onGameUpdated = functions.firestore
//   .document("games/{gameId}")
//   .onUpdate(async (change, context) => {
//     const before = change.before.data();
//     const after = change.after.data();

//     functions.logger.info(`Game updated: ${context.params.gameId}`);
//     functions.logger.info("Before:", before);
//     functions.logger.info("After:", after);

//     // TODO: Add update processing logic here

//     return null;
//   });

// Export helper functions for use in other modules (for scripts like ingest.js)
// Note: Cloud Functions are exported via exports.functionName above
module.exports.db = db;
module.exports.updateTeams = updateTeams;
module.exports.fetchTeamData = fetchTeamData;
module.exports.createGame = createGame;
module.exports.fetchGame = fetchGame;
module.exports.fetchGameGoals = fetchGameGoals;
module.exports.ingestData = ingestData;
