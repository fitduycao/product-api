const mongoose = require("mongoose");

const productSchema = new mongoose.Schema({
  pid: { type: String, required: false, unique: true },
  pname: { type: String, required: true },
  price: { type: Number, required: false },
  quantity: { type: Number, required :false},
});

module.exports = mongoose.model("Product", productSchema);