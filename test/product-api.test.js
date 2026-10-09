const assert = require('node:assert/strict');
const { once } = require('node:events');
const { test } = require('node:test');
const mongoose = require('mongoose');
require('../src/config/env');
const { connectDatabase } = require('../src/config/database');
const Product = require('../src/models/Product');
const app = require('../src/app');

test('Product API: CRUD va cac truong hop loi tren MongoDB thuc', async (t) => {
  assert.ok(process.env.TEST_MONGO_URI, 'Can TEST_MONGO_URI trong .env de chay test.');
  await connectDatabase(process.env.TEST_MONGO_URI);

  const pid = `TEST-${process.pid}-${Date.now()}`;
  const renamedPid = `${pid}-RENAMED`;
  let server;

  t.after(async () => {
    // Chi xoa ban ghi do test tao, khong drop database.
    try {
      await Product.deleteMany({ pid: { $in: [pid, renamedPid] } });
    } finally {
      if (server) await new Promise((resolve) => server.close(resolve));
      await mongoose.disconnect();
    }
  });

  await Product.init();
  server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const original = { pid, pname: 'Ban phim', price: 350000, quantity: 10 };

  async function request(method, route, body) {
    const response = await fetch(`${baseUrl}${route}`, {
      method,
      ...(body === undefined ? {} : {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      })
    });
    return { status: response.status, body: await response.json() };
  }

  await t.test('health xac nhan ket noi MongoDB', async () => {
    const result = await request('GET', '/health');
    assert.equal(result.status, 200);
    assert.equal(result.body.mongodb, 'connected');
  });

  await t.test('POST tao Product va luu vao MongoDB', async () => {
    const result = await request('POST', '/api/products', original);
    assert.equal(result.status, 201);
    assert.equal(result.body.pid, pid);
    const stored = await Product.findOne({ pid }).lean();
    assert.equal(stored.quantity, 10);
  });

  await t.test('pid trung bi tu choi voi 409', async () => {
    const result = await request('POST', '/api/products', original);
    assert.equal(result.status, 409);
  });

  await t.test('GET danh sach va GET theo pid', async () => {
    const list = await request('GET', '/api/products');
    assert.equal(list.status, 200);
    assert.ok(list.body.some((product) => product.pid === pid));
    const item = await request('GET', `/api/products/${pid}`);
    assert.equal(item.status, 200);
    assert.equal(item.body.price, 350000);
  });

  await t.test('PUT cap nhat du thong tin', async () => {
    const result = await request('PUT', `/api/products/${pid}`, {
      ...original, pname: 'Ban phim co', price: 500000, quantity: 8
    });
    assert.equal(result.status, 200);
    assert.equal(result.body.price, 500000);
  });

  await t.test('PATCH cap nhat mot truong, giu cac truong khac', async () => {
    const result = await request('PATCH', `/api/products/${pid}`, { quantity: 5 });
    assert.equal(result.status, 200);
    assert.equal(result.body.quantity, 5);
    assert.equal(result.body.pname, 'Ban phim co');
  });

  await t.test('price am va quantity le bi tu choi, du lieu khong doi', async () => {
    const badPrice = await request('PATCH', `/api/products/${pid}`, { price: -1 });
    assert.equal(badPrice.status, 400);
    const badQuantity = await request('PATCH', `/api/products/${pid}`, { quantity: 1.5 });
    assert.equal(badQuantity.status, 400);
    const stored = await Product.findOne({ pid }).lean();
    assert.equal(stored.price, 500000);
    assert.equal(stored.quantity, 5);
  });

  await t.test('POST thieu truong, PUT thieu truong, PATCH rong bi tu choi', async () => {
    assert.equal((await request('POST', '/api/products', { pid })).status, 400);
    assert.equal((await request('PUT', `/api/products/${pid}`, { quantity: 1 })).status, 400);
    assert.equal((await request('PATCH', `/api/products/${pid}`, {})).status, 400);
  });

  await t.test('JSON sai cu phap tra 400', async () => {
    const response = await fetch(`${baseUrl}/api/products`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{bad json'
    });
    assert.equal(response.status, 400);
  });

  await t.test('PATCH doi pid, URL moi tim duoc san pham', async () => {
    const result = await request('PATCH', `/api/products/${pid}`, { pid: renamedPid });
    assert.equal(result.status, 200);
    assert.equal((await request('GET', `/api/products/${pid}`)).status, 404);
    assert.equal((await request('GET', `/api/products/${renamedPid}`)).status, 200);
  });

  await t.test('DELETE xoa san pham, GET va DELETE lai tra 404', async () => {
    assert.equal((await request('DELETE', `/api/products/${renamedPid}`)).status, 200);
    assert.equal(await Product.findOne({ pid: renamedPid }), null);
    assert.equal((await request('GET', `/api/products/${renamedPid}`)).status, 404);
    assert.equal((await request('DELETE', `/api/products/${renamedPid}`)).status, 404);
  });

  await t.test('cap nhat san pham khong ton tai tra 404', async () => {
    assert.equal((await request('PUT', `/api/products/${pid}`, original)).status, 404);
    assert.equal((await request('PATCH', `/api/products/${pid}`, { quantity: 1 })).status, 404);
  });
});
