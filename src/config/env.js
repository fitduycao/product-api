const path = require('node:path');
const dotenv = require('dotenv');

// Luon doc .env tai thu muc goc du an.
dotenv.config({ path: path.resolve(__dirname, '../../.env'), quiet: true });

function getHealthcheckTimeout() {
  const timeout = Number(process.env.HEALTHCHECK_TIMEOUT_MS || 2000);
  if (!Number.isInteger(timeout) || timeout < 100 || timeout > 3000) {
    throw new Error('HEALTHCHECK_TIMEOUT_MS phai la so nguyen tu 100 den 3000.');
  }
  return timeout;
}

function getConfig() {
  const { HOST, PORT, MONGO_URI } = process.env;
  const port = Number(PORT);

  if (!HOST || !MONGO_URI) {
    throw new Error('Can khai bao HOST va MONGO_URI trong .env.');
  }
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT trong .env phai la so nguyen tu 1 den 65535.');
  }

  getHealthcheckTimeout();
  return { host: HOST, port, mongoUri: MONGO_URI };
}

module.exports = { getConfig, getHealthcheckTimeout };
