const mongoose = require('mongoose');
const { getConfig } = require('./config/env');
const { connectDatabase } = require('./config/database');
const Product = require('./models/Product');
const app = require('./app');

async function start() {
  const { host, port, mongoUri } = getConfig();
  await connectDatabase(mongoUri);
  // Cho unique index cua pid san sang truoc khi nhan request.
  await Product.init();

  console.log(`MongoDB connected: ${mongoose.connection.name}`);

  const server = app.listen(port, host, () => {
    console.log(`Product API: http://${host}:${port}`);
  });

  server.on('error', async (error) => {
    console.error(`Khong khoi dong duoc API: ${error.message}`);
    await mongoose.disconnect();
    process.exitCode = 1;
  });

  let closing = false;
  function shutdown() {
    if (closing) return;
    closing = true;
    server.close(async () => {
      await mongoose.disconnect();
    });
  }

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

start().catch(async (error) => {
  console.error(`Khong khoi dong duoc API: ${error.message}`);
  await mongoose.disconnect();
  process.exitCode = 1;
});
