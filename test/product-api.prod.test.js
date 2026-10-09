const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { execFileSync } = require('node:child_process');
const { test } = require('node:test');

// Exercise the running Docker image through HTTP, without importing app code.
test('Production Docker API: CRUD and MongoDB persistence', { timeout: 120000 }, async (t) => {
  assert.ok(process.env.API_BASE_URL, 'API_BASE_URL is required.');
  assert.equal(process.env.COMPOSE_FILE, 'compose.ci.yaml', 'Use the isolated CI stack.');
  const baseUrl = process.env.API_BASE_URL.replace(/\/$/, '');
  const pid = `CI-PROD-${randomUUID()}`;
  const renamedPid = `${pid}-RENAMED`;
  const route = (id) => `/api/products/${encodeURIComponent(id)}`;
  const original = { pid, pname: 'CI keyboard', price: 350000, quantity: 10 };

  async function request(method, path, body) {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      signal: AbortSignal.timeout(10000),
      ...(body === undefined ? {} : {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      })
    });
    return { status: response.status, body: await response.json() };
  }

  function storedProduct(id) {
    const output = execFileSync('docker', [
      'compose', 'exec', '-T', 'mongodb', 'mongosh', '--quiet', 'product_api_ci',
      '--eval', `print(EJSON.stringify(db.products.findOne({ pid: ${JSON.stringify(id)} })))`
    ], { encoding: 'utf8', timeout: 20000 });
    return JSON.parse(output.trim());
  }

  function productFields(product) {
    return Object.fromEntries(['pid', 'pname', 'price', 'quantity'].map((key) => [key, product[key]]));
  }

  t.after(async () => {
    // Clean up only this run's products, including when an assertion fails.
    for (const id of [pid, renamedPid]) {
      const result = await request('DELETE', route(id));
      assert.ok([200, 404].includes(result.status), 'Test data cleanup failed.');
    }
  });

  await t.test('health reports the CI MongoDB connection', async () => {
    const result = await request('GET', '/health');
    assert.equal(result.status, 200);
    assert.equal(result.body.status, 'ok');
    assert.equal(result.body.mongodb, 'connected');
    assert.equal(result.body.database, 'product_api_ci');
  });

  await t.test('POST creates a product and MongoDB stores all four fields', async () => {
    const result = await request('POST', '/api/products', original);
    assert.equal(result.status, 201);
    assert.deepEqual(productFields(result.body), original);
    assert.deepEqual(productFields(storedProduct(pid)), original);
  });

  await t.test('duplicate pid returns 409', async () => {
    assert.equal((await request('POST', '/api/products', original)).status, 409);
  });

  await t.test('GET list and GET by pid return the stored product', async () => {
    const list = await request('GET', '/api/products');
    assert.equal(list.status, 200);
    assert.ok(list.body.some((product) => product.pid === pid));
    const item = await request('GET', route(pid));
    assert.equal(item.status, 200);
    assert.deepEqual(productFields(item.body), original);
  });

  const updated = { ...original, pname: 'CI mechanical keyboard', price: 500000, quantity: 8 };
  await t.test('PUT updates all fields in MongoDB', async () => {
    const result = await request('PUT', route(pid), updated);
    assert.equal(result.status, 200);
    assert.deepEqual(productFields(result.body), updated);
    assert.deepEqual(productFields(storedProduct(pid)), updated);
  });

  await t.test('PATCH updates quantity and preserves other fields', async () => {
    const result = await request('PATCH', route(pid), { quantity: 5 });
    assert.equal(result.status, 200);
    assert.deepEqual(productFields(result.body), { ...updated, quantity: 5 });
    assert.deepEqual(productFields(storedProduct(pid)), { ...updated, quantity: 5 });
  });

  await t.test('invalid price and quantity return 400 without changing MongoDB', async () => {
    assert.equal((await request('PATCH', route(pid), { price: -1 })).status, 400);
    assert.equal((await request('PATCH', route(pid), { quantity: 1.5 })).status, 400);
    assert.deepEqual(productFields(storedProduct(pid)), { ...updated, quantity: 5 });
  });

  await t.test('missing fields and empty PATCH return 400', async () => {
    assert.equal((await request('POST', '/api/products', { pid })).status, 400);
    assert.equal((await request('PUT', route(pid), { quantity: 1 })).status, 400);
    assert.equal((await request('PATCH', route(pid), {})).status, 400);
  });

  await t.test('malformed JSON returns 400', async () => {
    const response = await fetch(`${baseUrl}/api/products`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{invalid json',
      signal: AbortSignal.timeout(10000)
    });
    assert.equal(response.status, 400);
  });

  await t.test('PATCH renames pid in the API and MongoDB', async () => {
    assert.equal((await request('PATCH', route(pid), { pid: renamedPid })).status, 200);
    assert.equal((await request('GET', route(pid))).status, 404);
    assert.equal((await request('GET', route(renamedPid))).status, 200);
    assert.equal(storedProduct(pid), null);
    assert.deepEqual(productFields(storedProduct(renamedPid)), { ...updated, pid: renamedPid, quantity: 5 });
  });

  await t.test('DELETE removes the product from MongoDB', async () => {
    assert.equal((await request('DELETE', route(renamedPid))).status, 200);
    assert.equal(storedProduct(renamedPid), null);
    assert.equal((await request('GET', route(renamedPid))).status, 404);
    assert.equal((await request('DELETE', route(renamedPid))).status, 404);
  });

  await t.test('PUT and PATCH for a missing product return 404', async () => {
    assert.equal((await request('PUT', route(pid), original)).status, 404);
    assert.equal((await request('PATCH', route(pid), { quantity: 1 })).status, 404);
  });
});
