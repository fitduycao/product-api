const mongoose = require('mongoose');

const productSchema = new mongoose.Schema(
  {
    pid: {
      type: String,
      required: [true, 'pid là bắt buộc.'],
      trim: true,
      unique: true
    },
    pname: {
      type: String,
      required: [true, 'pname là bắt buộc.'],
      trim: true
    },
    price: {
      type: Number,
      required: [true, 'price là bắt buộc.'],
      min: [0, 'price phải lớn hơn hoặc bằng 0.'],
      validate: {
        validator: Number.isFinite,
        message: 'price phải là số hữu hạn.'
      }
    },
    quantity: {
      type: Number,
      required: [true, 'quantity là bắt buộc.'],
      min: [0, 'quantity phải lớn hơn hoặc bằng 0.'],
      validate: {
        validator: Number.isSafeInteger,
        message: 'quantity phải là số nguyên trong phạm vi an toàn.'
      }
    }
  },
  { versionKey: false, collection: 'products' }
);

module.exports = mongoose.model('Product', productSchema);
