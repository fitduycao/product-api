const express = require('express');
const mongoose = require('mongoose');
const { getHealthcheckTimeout } = require('./config/env');
const productRoutes = require('./routes/productRoutes');
const errorHandler = require('./middleware/errorHandler');

const app = express();

app.use(express.json({ limit: '100kb' }));

app.get('/health', async (req, res) => {
  res.set('Cache-Control', 'no-store');
  const database = mongoose.connection.name || null;

  if (mongoose.connection.readyState !== 1 || !mongoose.connection.db) {
    return res.status(503).json({ status: 'unavailable', database, mongodb: 'disconnected' });
  }

  try {
    const result = await mongoose.connection.db.command(
      { ping: 1 },
      { timeoutMS: getHealthcheckTimeout() }
    );
    if (result.ok !== 1) throw new Error('MongoDB ping failed.');
    return res.json({ status: 'ok', database, mongodb: 'connected' });
  } catch {
    return res.status(503).json({ status: 'unavailable', database, mongodb: 'unavailable' });
  }
});

app.use('/api/products', productRoutes);

app.use((req, res) => {
  res.status(404).json({ message: 'Đường dẫn không tồn tại.' });
});

// Express 5 tu chuyen loi tu async controller den middleware nay.
app.use(errorHandler);

module.exports = app;
