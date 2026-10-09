# Câu 7 — Dockerize product-api

Dockerize là đóng gói ứng dụng Node.js và thư viện vào một image, sau đó chạy API bằng container. MongoDB tiếp tục chạy trong container `nammongodb` đã tạo ở câu trước.

## 1. Các file được thêm

```text
product-api/
├── Dockerfile
├── .dockerignore
├── .env                  # Cau 6: API chay tren Windows
├── .env.docker           # Cau 7: API chay trong Docker
├── .env.docker.example
├── DOCKER.md
└── scripts/
    └── test-docker-api.ps1
```

Mã CRUD của câu 6 giữ nguyên. `dotenv` cho phép các biến đã được Docker đưa vào `process.env` hoạt động khi không có file `.env` bên trong image.

## 2. Dockerfile

```dockerfile
FROM node:24-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

COPY --chown=node:node src ./src

USER node

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 CMD node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/health', { signal: AbortSignal.timeout(2000) }).then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "src/server.js"]
```

| Lệnh | Giải thích |
| --- | --- |
| `FROM` | Dùng image Node.js 24 chính thức làm môi trường chạy. |
| `WORKDIR /app` | Đặt thư mục làm việc trong container. |
| `COPY package...` | Sao chép thông tin thư viện trước mã nguồn để tận dụng cache. |
| `RUN npm ci...` | Cài đúng phiên bản theo lockfile, chỉ các dependency phục vụ chạy ứng dụng. |
| `COPY ... src` | Sao chép mã nguồn API. |
| `USER node` | Chạy ứng dụng bằng user `node`. |
| `EXPOSE 3000` | Khai báo cổng API trong image; ánh xạ ra Windows bằng `docker run -p`. |
| `HEALTHCHECK` | Gọi `/health` để kiểm tra kết nối MongoDB từ API. |
| `CMD` | Chạy trực tiếp Node.js để ứng dụng nhận tín hiệu dừng container. |

`.dockerignore` loại `node_modules`, `.git`, `.env` và `.env.*` khỏi build context. Cấu hình được truyền lúc chạy bằng `--env-file`. [Docker build best practices](https://docs.docker.com/build/building/best-practices/), [Node official image](https://hub.docker.com/_/node).

## 3. Cấu hình `.env.docker`

```dotenv
NODE_ENV=production
HOST=0.0.0.0
PORT=3000
MONGO_URI=mongodb://nammongodb:27017/productdb
TEST_MONGO_URI=mongodb://nammongodb:27017/product_api_test
```

| Nội dung | API trên Windows — câu 6 | API trong Docker — câu 7 |
| --- | --- | --- |
| File cấu hình | `.env` | `.env.docker` |
| HOST của API | `127.0.0.1` | `0.0.0.0` |
| Hostname MongoDB | `127.0.0.1` | `nammongodb` |
| Database | `productdb` | `productdb` |

Trong container API, `127.0.0.1` trỏ về chính container API. Trên mạng Docker riêng, hostname `nammongodb` được Docker phân giải thành địa chỉ container MongoDB. `HOST=0.0.0.0` cho phép API nhận kết nối qua giao diện mạng của container. [Docker bridge networks](https://docs.docker.com/engine/network/drivers/bridge/).

`.env` dành cho Windows được giữ nguyên. `.env.docker` được Git bỏ qua; `.env.docker.example` là mẫu có thể chia sẻ. Khi clone dự án mới, nếu chưa có file này, chạy `Copy-Item .env.docker.example .env.docker`.

## 4. Tạo mạng và kết nối MongoDB hiện có

Trong terminal PowerShell của VS Code:

```powershell
Set-Location 'D:\Project\product-api'
docker ps --filter "name=^/nammongodb$"
docker network create product-network
docker network connect product-network nammongodb
```

Nếu MongoDB đang dừng, chạy `docker start nammongodb`. Chỉ tạo mạng một lần. Nếu mạng đã tồn tại hoặc MongoDB đã kết nối vào mạng này, bỏ qua thao tác tương ứng.

Kiểm tra mạng:

```powershell
docker network inspect product-network
```

Kết nối thêm mạng không thay đổi volume `nammongodb_data` và ánh xạ cổng MongoDB đã có.

## 5. Build image API

```powershell
docker build -t product-api:1.0 .
```

- `-t product-api:1.0`: đặt tên image và tag.
- Dấu `.`: dùng thư mục hiện tại làm build context.
- Docker đọc `Dockerfile`, tải image Node.js nếu cần, cài thư viện, sao chép mã và tạo image.

Kiểm tra image:

```powershell
docker images product-api
```

## 6. Chạy container API

Nếu API của câu 6 còn chạy bằng `npm.cmd run dev` trên cổng `3000`, nhấn Ctrl+C ở terminal đó để giải phóng cổng trước.

```powershell
docker run -d --name product-api --network product-network --env-file .env.docker -p 127.0.0.1:3000:3000 product-api:1.0
```

| Tùy chọn | Ý nghĩa |
| --- | --- |
| `-d` | Chạy container ngầm. |
| `--name product-api` | Đặt tên container API. |
| `--network product-network` | Cho API và MongoDB giao tiếp trên cùng mạng. |
| `--env-file .env.docker` | Đọc biến môi trường khi tạo container. |
| `-p 127.0.0.1:3000:3000` | Ánh xạ cổng Windows 3000 vào cổng container 3000. |
| `product-api:1.0` | Image đã build. |

Nếu đã có container `product-api` do bước này tạo, dùng `docker start product-api` để chạy lại. Khi đổi mã hoặc `.env.docker`, cần build/recreate theo phần 9.

## 7. Kiểm tra hoạt động và kết nối

```powershell
docker ps
docker logs product-api
Invoke-RestMethod -Uri 'http://127.0.0.1:3000/health'
```

Log mong đợi:

```text
MongoDB connected: productdb
Product API: http://0.0.0.0:3000
```

Response mong đợi:

```json
{
  "status": "ok",
  "database": "productdb",
  "mongodb": "connected"
}
```

Docker healthcheck chạy định kỳ. Xem trạng thái bằng:

```powershell
docker inspect product-api --format '{{.State.Health.Status}}'
```

Khi các lần kiểm tra thành công, trạng thái là `healthy`.

Các URL CRUD giữ nguyên: POST/GET `/api/products`, GET/PUT/PATCH/DELETE `/api/products/:pid`. Dùng `requests.http` và các ví dụ PowerShell/Postman trong README của câu 6.

## 8. Kiểm thử CRUD của API thực sự chạy trong Docker

```powershell
.\scripts\test-docker-api.ps1
```

Script gọi HTTP đến container API, thử tạo/đọc/cập nhật/xóa, lỗi trùng mã và giá âm. Nó đọc trực tiếp document trong `nammongodb` để xác nhận dữ liệu được lưu ở MongoDB. Mã sản phẩm thử có tiền tố `TEST-DOCKER-` và được xóa khi kết thúc.

Nếu PowerShell không cho chạy file script do execution policy, có thể chạy riêng script trong tiến trình PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-docker-api.ps1
```

Lệnh này đặt policy cho tiến trình đó, không sửa policy chung của máy.

Để xem dữ liệu sản phẩm bạn tạo bằng API:

```powershell
docker exec -it nammongodb mongosh productdb
```

Trong MongoDB Shell:

```javascript
db.products.find()
```

## 9. Dừng, chạy lại và cập nhật

Dừng container API:

```powershell
docker stop product-api
```

Chạy lại với cùng cấu hình:

```powershell
docker start product-api
```

Sau khi sửa mã nguồn hoặc cấu hình `.env.docker`, tạo lại container API:

```powershell
docker stop product-api
docker rm product-api
docker build -t product-api:1.0 .
docker run -d --name product-api --network product-network --env-file .env.docker -p 127.0.0.1:3000:3000 product-api:1.0
```

Các thao tác trên chỉ thay container API. Dữ liệu Product vẫn nằm trong MongoDB và volume `nammongodb_data`.

## 10. Lỗi thường gặp

- **EAI_AGAIN/ENOTFOUND nammongodb:** kiểm tra cả hai container đều ở `product-network`.
- **ECONNREFUSED 127.0.0.1:27017 trong container API:** kiểm tra `.env.docker` dùng hostname `nammongodb`, rồi tạo lại container với đúng env-file.
- **Không truy cập được API dù log đã chạy:** kiểm tra `HOST=0.0.0.0` trong `.env.docker`, cổng publish và trạng thái `/health`.
- **Cổng 3000 đã sử dụng:** dừng bản API chạy trên Windows, hoặc dùng `-p 127.0.0.1:3001:3000`; khi đó truy cập `http://127.0.0.1:3001` và chạy test với `-BaseUrl http://127.0.0.1:3001`.
- **Tên product-api đã tồn tại:** xem `docker ps -a`, dùng `docker start` nếu chỉ cần chạy lại, hoặc stop/rm đúng container API để tạo lại.

Bằng chứng cho bài thực hành: image `product-api:1.0`; container API `healthy`; container MongoDB `Up`; log kết nối; response `/health`; và kết quả CRUD.
