const { getConfig, getHealthcheckTimeout } = require('./config/env');

async function check() {
  const { port } = getConfig();
  const response = await fetch(`http://127.0.0.1:${port}/health`, {
    signal: AbortSignal.timeout(getHealthcheckTimeout() + 1000)
  });

  if (response.status !== 200) {
    throw new Error(`GET /health returned HTTP ${response.status}.`);
  }

  const body = await response.json();
  if (body.status !== 'ok' || body.mongodb !== 'connected') {
    throw new Error('API cannot confirm MongoDB is available.');
  }
}

check().then(
  () => process.exit(0),
  (error) => {
    console.error(`Healthcheck failed: ${error.message}`);
    process.exit(1);
  }
);
