// Script to run the ingestData function
// Set environment variables for Firestore emulator
process.env.FIRESTORE_EMULATOR_HOST = 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = 'localhost:9099';

const { ingestData } = require('../src/index');

console.log(process.argv);

// Parse command line arguments
// When running via npm, args come after the script name
// Example: npm run ingest -- --backfill=2023
const args = process.argv.slice(2);
const backfillArg = args.find(arg => arg.startsWith('backfill='));
const backfillYear = backfillArg ? parseInt(backfillArg.split('=')[1]) : null;

console.log('Starting NHL data ingestion...\n');

if (backfillYear) {
  console.log(`Backfill mode enabled: Starting from ${backfillYear} season\n`);
}

ingestData({ backfillYear })
  .then((result) => {
    console.log('Ingestion successful!');
    console.log(`\nSummary: ${result.gamesCreated} games created, ${result.gamesSkipped} games skipped`);
    process.exit(0);
  })
  .catch((error) => {
    console.error('Ingestion failed:', error);
    process.exit(1);
  });
