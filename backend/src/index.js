const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions/logger");
const admin = require("firebase-admin");

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
    const startTime = admin.firestore.Timestamp.fromDate(new Date(gameData.easternStartTime));
    
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
      },
      away_data: {
        team_id: awayTeam.triCode,
        team_name: awayTeam.fullName,
        team_score: gameData.visitingScore || 0,
      },
      status: statusMap[gameData.gameStateId] || "SCHEDULED",
      raw: gameData,
    };
  } else {
    // Schedule API format - has embedded team data, fetch live scores
    const { gameDate } = options;
    const startTime = admin.firestore.Timestamp.fromDate(new Date(gameData.startTimeUTC));
    
    // Fetch current scores from API
    const scoreResponse = await fetch(`https://api-web.nhle.com/v1/score/${gameDate}`);
    const scoreData = await scoreResponse.json();
    
    // Find the specific game in the games list
    const games = scoreData.games || [];
    const currentGame = games.find((g) => g.id.toString() === gameId);
    
    // Use scores from API if found, otherwise default to 0
    const awayScore = currentGame?.awayTeam?.score || 0;
    const homeScore = currentGame?.homeTeam?.score || 0;
    
    gameDoc = {
      gameid: gameId,
      start_time: startTime,
      home_data: {
        team_id: gameData.homeTeam.abbrev,
        team_name: gameData.homeTeam.commonName.default,
        team_score: homeScore,
      },
      away_data: {
        team_id: gameData.awayTeam.abbrev,
        team_name: gameData.awayTeam.commonName.default,
        team_score: awayScore,
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
        teamLookup.set(team.id, { triCode: team.triCode, fullName: team.fullName });
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


      // To avoid rate limiting, add a small delay before the fetch
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
            skipped++;
          }
        }
        
        // Commit the batch
        await batch.commit();
        
        console.log(`Progress: ${Math.min((batchIndex + 1) * BATCH_SIZE, gamesToProcess.length)}/${gamesToProcess.length} games processed (${created} created, ${skipped} skipped)`);
        
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
          skipped++;
        }
      }
    }

    console.log("\n=== Data Ingestion Complete ===");
    console.log(`Date Range: ${dateRange}`);
    console.log(`Games Found: ${gamesToProcess.length}`);
    console.log(`Games Created: ${created}`);
    console.log(`Games Skipped: ${skipped}`);
    console.log("================================\n");
    
    return {
      success: true,
      message: "Data ingestion completed",
      dateRange,
      gamesFound: gamesToProcess.length,
      gamesCreated: created,
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
    if (gameData.goals && Object.keys(gameData.goals).length > 0) {
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
    
    // Build goals object keyed by time
    const goals = {};
    
    for (const play of goalPlays) {
      const timeInPeriod = play.timeInPeriod || "00:00";
      const period = play.periodDescriptor?.number || 1;
      
      // Get scorer, goalie, and assists
      const details = play.details || {};
      const scoringPlayerId = details.scoringPlayerId;
      const goalieInNetId = details.goalieInNetId;
      const assists = details.assists || [];
      
      // Get player names from rosterSpots
      const rosterSpots = playByPlayData.rosterSpots || [];
      const getPlayerName = (playerId) => {
        const player = rosterSpots.find((spot) => spot.playerId === playerId);
        return player ? `${player.firstName?.default || ""} ${player.lastName?.default || ""}`.trim() : "Unknown";
      };
      
      const scorerName = getPlayerName(scoringPlayerId);
      const goalieName = getPlayerName(goalieInNetId);
      const primaryAssist = assists.length > 0 ? getPlayerName(assists[0].playerId) : null;
      const secondaryAssist = assists.length > 1 ? getPlayerName(assists[1].playerId) : null;
      
      // Store with period info to make time unique
      const timeKey = `P${period}-${timeInPeriod}`;
      
      goals[timeKey] = {
        scorer: scorerName,
        goalie: goalieName,
        primaryAssist: primaryAssist,
        secondaryAssist: secondaryAssist,
        period: period,
        timeInPeriod: timeInPeriod,
        teamId: play.details?.eventOwnerTeamId,
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
  
  // If game is not live, return data from DB directly
  if (gameStatus !== "LIVE" && gameStatus !== "CRIT") {
    return {
      success: true,
      gameId,
      home_score: gameData.home_data.team_score || 0,
      away_score: gameData.away_data.team_score || 0,
      status: gameStatus,
      source: "database",
    };
  }
  
  // Game is live - use transaction with locking
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


    console.log(scoreResponse);

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
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
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
  
  logger.info(`Fetching goals for game: ${gameId}`);
  
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
  
  logger.info(`Updating game: ${gameId}`);
  
  const result = await fetchGame(gameId);
  
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
module.exports.createGame = createGame;
module.exports.fetchGame = fetchGame;
module.exports.fetchGameGoals = fetchGameGoals;
module.exports.ingestData = ingestData;
