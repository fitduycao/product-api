const mongoose = require('mongoose');

async function connectDatabase(uri) {
  // Tra loi ngay neu mat ket noi thay vi giu truy van trong bo dem.
  mongoose.set('bufferCommands', false);
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
}

module.exports = { connectDatabase };
