import { env } from './config/env.js';
import { initializeSupabase } from './config/supabase.js';
import app from './app.js';

initializeSupabase();

const server = app.listen(env.port, '0.0.0.0', () => {
  console.log(`Legal Services API listening on 0.0.0.0:${env.port} (${env.nodeEnv})`);
});

function shutdown(signal) {
  console.log(`Received ${signal}; closing HTTP server.`);
  server.close((error) => {
    if (error) {
      console.error('Failed to close HTTP server cleanly.');
      process.exitCode = 1;
    }
  });
}

process.once('SIGINT', () => shutdown('SIGINT'));
process.once('SIGTERM', () => shutdown('SIGTERM'));

export default app;
