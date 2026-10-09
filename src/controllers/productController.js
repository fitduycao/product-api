const Product = require('../models/Product');

const fields = ['pid', 'pname', 'price', 'quantity'];

function productBody(body, requireAll) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    const error = new Error('Body phải là một đối tượng JSON.');
    error.status = 400;
    throw error;
  }

  const providedFields = fields.filter((field) => Object.hasOwn(body, field));
  if (requireAll && providedFields.length !== fields.length) {
    const error = new Error('Cần đủ pid, pname, price và quantity.');
    error.status = 400;
    throw error;
  }
  if (!providedFields.length) {
    const error = new Error('Cần ít nhất một trường Product để cập nhật.');
    error.status = 400;
    throw error;
  }

  // Chi cho phep bon truong cua Product; khong nhan toan tu MongoDB tu client.
  return Object.fromEntries(providedFields.map((field) => [field, body[field]]));
}

function notFound(res) {
  return res.status(404).json({ message: 'Không tìm thấy sản phẩm.' });
}

async function createProduct(req, res) {
  const product = await Product.create(productBody(req.body, true));
  res.location(`/api/products/${encodeURIComponent(product.pid)}`);
  return res.status(201).json(product);
}

async function getProducts(req, res) {
  const products = await Product.find().sort({ pid: 1 });
  return res.json(products);
}

async function getProduct(req, res) {
  const product = await Product.findOne({ pid: req.params.pid });
  return product ? res.json(product) : notFound(res);
}

async function updateProduct(req, res) {
  // PUT gui du bon truong; PATCH chi gui nhung truong can thay doi.
  const values = productBody(req.body, req.method === 'PUT');
  const product = await Product.findOneAndUpdate(
    { pid: req.params.pid },
    { $set: values },
    { returnDocument: 'after', runValidators: true }
  );

  return product ? res.json(product) : notFound(res);
}

async function deleteProduct(req, res) {
  const product = await Product.findOneAndDelete({ pid: req.params.pid });
  if (!product) return notFound(res);
  return res.json({ message: 'Đã xóa sản phẩm.', product });
}

module.exports = {
  createProduct,
  getProducts,
  getProduct,
  updateProduct,
  deleteProduct
};
