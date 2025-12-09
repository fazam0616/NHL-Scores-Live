# Quadlii Assignment - NHL Game Tracker

A real-time NHL game tracking application built with Flutter and Firebase. Features live game updates, team statistics, historical data, and season-aware caching.

## Project Overview

This Android application tracks NHL games with the following capabilities:
- **Real-time game updates** - Live scores and goal tracking with automatic polling
- **Team statistics** - Season-specific and all-time team performance metrics
- **Historical data** - Browse games from any date with intelligent caching
- **Smart ingestion** - Automatic data fetching from open source NHL API's
- **Season awareness** - Automatically detects and handles season transitions

**Primary Platform**: Android (with web support for rapid testing)

## Prerequisites

- **Flutter SDK** (3.0.0 or higher) - [Install Flutter](https://flutter.dev/docs/get-started/install)
- **Android Studio** (required for Android development) - [Download Android Studio](https://developer.android.com/studio)
- **Node.js** (18.x or higher) - [Download Node.js](https://nodejs.org/)
- **Firebase CLI** - Install globally: `npm install -g firebase-tools`
- **Chrome** (optional, for web testing)

## Backend Architecture

### Firebase Functions

The backend consists of several callable Cloud Functions that interact with NHL's public APIs:

#### Core Functions

1. **`ingestTodaysGames`** - Fetches today's game schedule from NHL Schedule API
   - Automatically called when no games found for today by client
   - Creates game documents with team data, scores, and status
   - Updates teams collection with franchise IDs

2. **`updateGame`** - Updates a specific game's score and status
   - Fetches live data from NHL Score API
   - Implements transaction locking to prevent race conditions
   - Skips API calls for already-FINAL games
   - Used by client for live updates

3. **`fetchGoals`** - Retrieves play-by-play data for a game
   - Fetches from NHL Play-by-Play API
   - Extracts scorer, assists, goalie, and timing information
   - Stores goals as nested map in game document

4. **`fetchTeamData`** - Returns team statistics with intelligent caching
   - **Season-aware**: Automatically detects current NHL season (Oct-Sep boundary)
   - **Season stats**: Games played, wins, losses, goals (since Oct 1st of season)
   - **All-time stats**: Lifetime statistics across all seasons
   - **Recent games**: Last 5 completed games for current season
   - **Cache invalidation**: Updates only when new games completed or season changes
   - Returns cached data if up-to-date, reducing API load

#### Data Ingestion Script

- **`npm run ingest`** - Standalone script for bulk data ingestion
  - `npm run ingest -- backfill=2023` - Backfills data from specific year
  - Fetches historical games from NHL Stats API
  - Populates teams collection with all NHL franchises
  - Creates game documents for specified date ranges

### Firestore Collections

- **`games`** - Individual game documents
  - Fields: `id`, `status`, `start_time`, `home_data`, `away_data`, `goals`
  - Indexed by `start_time` for efficient date queries
  - Goals stored as nested map: `{period}_{time}: {scorer, assists, goalie, etc.}`

- **`teams`** - Team information with cached statistics
  - Fields: `abbreviation`, `team_name`, `franchise_id`, `last_updated`
  - Season fields: `season`, `season_games_played`, `season_wins`, `season_losses`, `season_total_goals`, `season_recent_games`
  - All-time fields: `alltime_games_played`, `alltime_wins`, `alltime_losses`, `alltime_total_goals`

## Flutter Application

### Features

#### Home Screen (`home_screen.dart`)
- Displays games for selected date (defaults to today)
- Date picker to browse historical games
- Auto-refresh every 10 seconds for today's games
- Modal bottom sheet for game details
- Maintains update timer when viewing game details

#### Game Screen (`game_screen.dart`)
- Live game scores with team logos
- Real-time Firestore listener for instant updates
- Expandable goal cards showing:
  - Scorer with game time
  - Primary and secondary assists
  - Goalie who allowed the goal
  - Aligned by scoring team (left=home, right=away)
- Team names split intelligently across multiple lines
- Navigate to team details by tapping team cards
- 2-second polling for live games (in addition to Firestore listener)

#### Team Screen (`team_screen.dart`)
- Team logo and name
- **Current Season Stats**: Games played, wins, losses, goals, win rate
  - Displays season year (e.g., "2024-2025")
  - Resets every October 1st
- **All-Time Stats**: Lifetime performance across all seasons
- **Recent Games**: Last 5 completed games with color coding (green=win, red=loss, yellow=draw)
- Auto-refresh when season changes

### State Management

Uses **Provider** pattern with `GameProvider`:

- **Home screen updates**: `Timer.periodic` every 10 seconds
  - Fetches games for selected date
  - Continues running when game details modal is open
  - Stops when viewing historical dates

- **Game screen updates**: Dual update mechanism
  - `Firestore.snapshots()` listener for real-time database changes
  - `Timer.periodic` every 2 seconds calling `updateGame` function (for live games only)
  - Rate-limit error suppression (silent handling of "too frequent" errors)

- **Separate timers**: Home screen and game screen timers run independently
  - Opening game details doesn't stop home screen updates
  - Closing game details cleans up game-specific resources only

### Navigation

Uses **go_router** for URL-based navigation:
- `/` - Home screen with today's games
- `/game/:gameId` - Full-screen game details (via router)
- Modal bottom sheets - Game details overlay (from home/team screens)
  - Draggable with scroll physics
  - Tap outside to dismiss
  - Proper cleanup on close

### UI Components

- **GameCard widget**: Reusable card with optional background color
- **Status indicators**: Color-coded badges (LIVE=red, FINAL=blue, SCHEDULED=yellow)
- **Team logos**: SVG images from NHL CDN
- **Responsive layout**: Optimized for Android devices, with web support for testing

## Setup Instructions

### 1. Clone and Install Dependencies

```powershell
# Clone the repository
git clone <repository-url>
cd "Quadlii Assignment"

# Install Flutter dependencies
cd app
flutter pub get
cd ..

# Install Firebase Functions dependencies
cd backend
npm install
cd ..
```

### 2. Firebase Emulator Setup

This project **uses Firebase emulators only**

The emulators are pre-configured in `firebase.json`:
- **Firestore**: Port 8080 (database)
- **Functions**: Port 5001 (cloud functions)
- **UI**: Port 4000 (emulator dashboard)

### 3. Flutter Firebase Configuration

The app is pre-configured with demo credentials in `app/lib/firebase_options.dart`:
- Uses `quadlii-nhl-scores` as demo project ID
- Automatically connects to emulators in debug mode (see `main.dart`)

## Running the Application

### Step 1: Start Firebase Emulators

Open a terminal and start the emulators:

```powershell
cd "Quadlii Assignment"
firebase emulators:start --only functions,firestore
```

You should see:
```
✔  functions: Emulator started at http://127.0.0.1:5001
✔  firestore: Emulator started at http://127.0.0.1:8080
✔  View Emulator UI at http://127.0.0.1:4000
```

**Keep this terminal running** - the emulators must stay active while using the app.

### Step 2: Ingest Sample Data (Optional)

In a new terminal, populate the database with historical data:

```powershell
cd backend

# Ingest today's games
npm run ingest

# OR ingest historical data from specific year to present day
npm run ingest -- backfill=2023
npm run ingest -- backfill=2024
```

This creates:
- Team documents with franchise IDs
- Game documents with scores and status
- Historical data for testing

**Note**: The app will auto-ingest today's games when you first open it, so this step is optional unless you want historical data.

### Step 3: Run Flutter App

In a new terminal:

**For Android (primary platform):**
```powershell
cd app
flutter run -d <device-id>
```

**List available devices:**
```powershell
flutter devices
```

**Note**: Connect an Android device via USB or start an Android emulator from Android Studio before running.

### Step 4: Using the App

1. **Home Screen**: Browse today's games (auto-refreshes every 10 seconds)
2. **Date Picker**: Tap the date in the header to view historical games
3. **Game Details**: Tap any game card to see live scores and goals
4. **Team Details**: Tap team logos in game details to view team stats

## Emulator Dashboard

Access the Firebase Emulator UI at: **http://localhost:4000**

Features:
- View Firestore collections and documents
- Monitor function calls and logs
- Inspect database queries
- Clear data between tests

## Development Workflow

### Typical Development Session

1. **Start Firebase emulators** (Terminal 1):
   ```powershell
   firebase emulators:start --only functions,firestore
   ```

2. **Run Flutter app on Android** (Terminal 2):
   ```powershell
   cd app
   flutter run  # Defaults to connected Android device
   ```

3. **Optional - Ingest data** (Terminal 3):
   ```powershell
   cd backend
   npm run ingest -- backfill=2024
   ```

### Hot Reload

Flutter supports hot reload - press `r` in the terminal to reload changes without restarting.

### Function Changes

If you modify Firebase Functions (`backend/src/index.js`):
1. Stop the emulator (Ctrl+C)
2. Restart: `firebase emulators:start --only functions,firestore`

The emulator automatically reloads function code on restart.

### Database Inspection

View data in real-time:
- Open http://localhost:4000
- Navigate to Firestore tab
- Explore `games` and `teams` collections

### Clearing Data

To reset the database:
1. Stop emulators (Ctrl+C)
2. Delete emulator data: `firebase emulators:start --only functions,firestore --import=./data --export-on-exit=./data`
3. Or use the "Clear all data" button in the Emulator UI

## Architecture Highlights

### Real-Time Updates Strategy

The app uses a **hybrid update mechanism** for optimal performance:

1. **Home Screen** (10-second polling)
   - Queries Firestore every 10 seconds for game list
   - Stops when viewing historical dates

2. **Game Screen** (Real-time + 2-second polling)
   - Firestore `.snapshots()` listener for instant database updates
   - Only polls API for live games (skips FINAL games)
   - Rate-limit protection with silent error handling

3. **Team Screen** (On-demand with cache)
   - Fetches data once on load
   - Invalidates cache when season changes

### Season Detection Logic

NHL seasons run October-September:
- **Season calculation**: 
  - Oct-Dec: Season is `currentYear` to `currentYear+1`
  - Jan-Sep: Season is `currentYear-1` to `currentYear`
- **Season boundary**: October 1st triggers cache reset
- **Format**: Stored as `"20242025"`, displayed as `"2024-2025"`

### Caching Strategy

**Team Data Caching:**
- Checks `last_updated` timestamp and `season` field
- Updates only if:
  - New FINAL games completed since last update
  - Current season differs from cached season
  - No cache exists
- Reduces API calls and improves response time

**Game Data:**
- FINAL games skip API updates (status never changes)
- LIVE games poll every 2 seconds
- SCHEDULED games checked periodically for status change

### Error Handling

- **Rate limiting**: Silent suppression of "too frequent" errors
- **Missing data**: Auto-triggers ingestion when no games found
- **Network errors**: Displayed with retry button
- **Transaction locking**: Prevents concurrent write conflicts


## Project Status

### Implemented Features
- ✅ Real-time game tracking with live scores
- ✅ Goal details with play-by-play data
- ✅ Team statistics (season and all-time)
- ✅ Historical game browsing with date picker
- ✅ Intelligent caching with season awareness
- ✅ Color-coded game results (win/loss/draw)
- ✅ Modal bottom sheets with smooth scroll physics
- ✅ Automatic data ingestion
- ✅ Rate-limit protection
- ✅ Transaction locking for concurrent updates
- ✅ Native Android UI optimized for mobile devices

### Known Limitations
- NHL API rate limits may affect rapid updates
- Emulator data is ephemeral (cleared on restart without export)
- No authentication (demo project only)

## API References

This project uses Open Sourced API's for NHL data:

- **Schedule API**: `https://api-web.nhle.com/v1/schedule/{date}`
- **Score API**: `https://api-web.nhle.com/v1/score/{date}`
- **Play-by-Play API**: `https://api-web.nhle.com/v1/gamecenter/{gameId}/play-by-play`
- **Stats API**: `https://api.nhle.com/stats/rest/en/team`

**Note**: These are unofficial APIs and may change without notice.

## Quick Start Summary

For the impatient developer:

```powershell
# Terminal 1: Start Firebase emulators
firebase emulators:start --only functions,firestore

# Terminal 2: Run app on Android
cd app
flutter run  # Ensure Android device/emulator is connected

# Terminal 3 (optional): Load historical data
cd backend
npm run ingest -- backfill=2024
```

Open http://localhost:4000 to view the Emulator UI.

**That's it!** The app will auto-ingest today's games when you open it.
