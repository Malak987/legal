import { env } from './config/env.js';
import { initializeFirebase } from './config/firebase.js';
import app from './app.js';

async function start() {
  try {
    initializeFirebase();
    console.log('✅ Firebase Admin SDK initialized');
  } catch (err) {
    console.error('❌ Failed to initialize Firebase:\n' + err.message);
    process.exit(1);
  }

  // Automatic seeding is disabled in Cloud Functions and production, and only
  // runs locally when explicitly requested with SEED_ON_START=true.
  if (env.seedOnStart && !env.isCloudFunction && env.nodeEnv !== 'production') {
    console.log('🌱 Running seed check (SEED_ON_START=true)...');
    const { seed } = await import('./seed.js');
    await seed();
  }

  app.listen(env.port, () => {
    console.log('=====================================================');
    console.log('🚀 Legal Services Backend Running (Standalone Dev Mode)');
    console.log(`   URL:         http://localhost:${env.port}/api`);
    console.log(`   Health:      http://localhost:${env.port}/api/health`);
    console.log(`   Environment: ${env.nodeEnv}`);
    console.log('=====================================================');
  });
}

start();

export default app;
