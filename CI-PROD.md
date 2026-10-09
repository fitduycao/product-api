# Production CI for Product API (bai 11)

Workflow: `.github/workflows/test-productci-prod.yml`.

Moi lan push, pull request, hoac chay thu cong, GitHub cap mot may Ubuntu.
Workflow build Dockerfile hien co (`npm ci --omit=dev`, user `node`) va chay
API voi `NODE_ENV=production` cung MongoDB 8.0 qua `compose.ci.yaml`.
Day la kiem thu ban dong goi de trien khai; workflow khong publish image hay deploy server.

## Ket noi

- Test HTTP tren may runner -> `http://127.0.0.1:13000` -> API container port 3000.
- API container -> `mongodb://mongodb:27017/product_api_ci` qua mang Compose.
- MongoDB khong publish cong ra may host.
- `.env.ci` duoc workflow tao luc chay va da duoc `.gitignore` bo qua.
- Volume CI do Compose quan ly, khong su dung `nammongodb_data`.

`docker compose up --build --wait --wait-timeout 180` cho ca MongoDB va API
healthy. Test dung Node.js 24, native fetch va node:test, khong can npm ci tren
may runner; dependencies cua API da duoc cai trong Docker image.

## Kiem thu

`test/product-api.prod.test.js` goi API dang chay qua HTTP. Test xac nhan
health/database, POST, GET, PUT, PATCH, DELETE, pid trung, du lieu sai,
JSON sai va 404. Mongosh doc truc tiep database de kiem tra viec tao,
cap nhat, doi pid va xoa san pham.

Test chi xoa san pham co pid ngau nhien do chinh no tao. Workflow in log khi
loi va luon don stack CI (ke ca volume test) sau khi chay.

## Chay lai tu PowerShell tai thu muc du an

Tao `.env.ci` voi noi dung sau (khong ghi de `.env.docker`):

```dotenv
NODE_ENV=production
HOST=0.0.0.0
PORT=3000
MONGO_URI=mongodb://mongodb:27017/product_api_ci
HEALTHCHECK_TIMEOUT_MS=2000
```

```powershell
$env:COMPOSE_FILE = 'compose.ci.yaml'
$env:COMPOSE_PROJECT_NAME = 'product-api-prod-ci'
$env:API_BASE_URL = 'http://127.0.0.1:13000'
docker compose config --quiet
docker compose up --build --wait --wait-timeout 180
node --test --test-reporter=tap test/product-api.prod.test.js
# Chi don stack va du lieu test CI vua tao.
docker compose down --volumes --remove-orphans
Remove-Item Env:COMPOSE_FILE, Env:COMPOSE_PROJECT_NAME, Env:API_BASE_URL
```

Commit/push workflow, compose.ci.yaml, test, Dockerfile, package.json,
package-lock.json va src cung nhau. Vao GitHub -> Actions -> Product API
Production CI de xem ket qua. Run workflow thu cong can workflow tren default branch.
