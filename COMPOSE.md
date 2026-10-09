# Câu 8 — Sử dụng Docker Compose cho product-api và MongoDB

Docker Compose đọc `compose.yaml` để build và quản lý cả API lẫn MongoDB bằng một nhóm lệnh. Câu 8 dùng lại Dockerfile của câu 7 và mã CRUD của câu 6.

## 1. File compose.yaml

```yaml
name: product-api

services:
  mongodb:
    image: mongo:8.0
    container_name: nammongodb
    restart: unless-stopped
    ports:
      - "127.0.0.1:27017:27017"
    volumes:
      - mongodb_data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--eval", "quit(db.runCommand({ ping: 1 }).ok === 1 ? 0 : 1)"]
      interval: 5s
      timeout: 5s
      retries: 12
      start_period: 10s

  api:
    build:
      context: .
      dockerfile: Dockerfile
    image: product-api:1.0
    container_name: product-api
    restart: unless-stopped
    env_file:
      - .env.docker
    ports:
      - "127.0.0.1:3000:3000"
    depends_on:
      mongodb:
        condition: service_healthy

volumes:
  mongodb_data:
    external: true
    name: nammongodb_data
```

Không cần khai báo trường `version`. Compose dùng file `compose.yaml` trong thư mục hiện tại.

## 2. Giải thích cấu hình

| Thành phần | Ý nghĩa |
| --- | --- |
| `name: product-api` | Tên project Compose, giúp các lệnh xác định đúng nhóm service. |
| `services.mongodb` | Service MongoDB sử dụng image `mongo:8.0`. |
| `services.api` | Service API được build từ Dockerfile của dự án. |
| `container_name` | Giữ tên quen thuộc `nammongodb` và `product-api`. |
| `restart: unless-stopped` | Tự khởi động lại container khi phù hợp với chính sách Docker, trừ khi người dùng đã dừng. |
| `ports` | Publish MongoDB trên cổng Windows 27017 và API trên cổng 3000, chỉ ở localhost. |
| `env_file` | Đưa cấu hình từ `.env.docker` vào môi trường container API. |
| `healthcheck` | Gọi MongoDB ping để xác định MongoDB có thể nhận truy vấn. |
| `depends_on` | Chờ MongoDB đạt `healthy` rồi khởi động API. |
| `volumes` | Gắn volume dữ liệu đã có vào `/data/db`. |

`depends_on` kèm `service_healthy` giúp API chờ database sẵn sàng khi Compose khởi động. [Docker startup order](https://docs.docker.com/compose/how-tos/startup-order/).

Compose tạo mạng mặc định `product-api_default`. Hai service tham gia mạng này; API tiếp tục kết nối qua hostname container `nammongodb` và cổng nội bộ 27017. Không cần chạy `docker network create/connect` cho hệ thống Compose này.

Volume được khai báo `external: true`, `name: nammongodb_data` để dùng đúng dữ liệu từ các câu trước. Compose yêu cầu volume tồn tại và không xóa external volume khi chạy `down`. [Docker Compose volumes](https://docs.docker.com/reference/compose-file/volumes/).

## 3. File .env.docker

Tiếp tục dùng file đã tạo ở câu 7:

```dotenv
NODE_ENV=production
HOST=0.0.0.0
PORT=3000
MONGO_URI=mongodb://nammongodb:27017/productdb
TEST_MONGO_URI=mongodb://nammongodb:27017/product_api_test
```

`.env` là cấu hình cho API chạy trực tiếp trên Windows; `.env.docker` là cấu hình cho container. Compose đưa biến vào API nhờ `env_file`, không đóng gói file cấu hình vào image. [Docker Compose environment variables](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/).

## 4. Chuyển từ container docker run của câu 7 — chỉ cần một lần

Hai container tạo bằng `docker run` đang dùng tên/cổng cần cho Compose. Script chuyển đổi sẽ:

1. Kiểm tra cấu hình và xác nhận container MongoDB đang gắn đúng volume `nammongodb_data`.
2. Build image trước khi dừng ứng dụng cũ.
3. Dừng API, đổi tên thành `product-api-before-compose`.
4. Dừng MongoDB, đổi tên thành `nammongodb-before-compose`.
5. Tạo hai container mới bằng Compose, dùng lại volume dữ liệu.
6. Chờ healthy và kiểm thử CRUD.

Chạy trong terminal PowerShell của VS Code:

```powershell
Set-Location 'D:\Project\product-api'
.\scripts\use-compose.ps1
```

Nếu execution policy chặn script, chỉ chạy file này trong một tiến trình PowerShell riêng:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\use-compose.ps1
```

Hai container cũ được giữ ở trạng thái dừng để có thể quay lại. Chỉ chạy container MongoDB mới trong khi nó đang dùng volume này.

Nếu thao tác chuyển đổi đã hoàn tất, dùng các lệnh Compose ở phần 5 thay vì lặp lại thao tác đổi tên.

## 5. Khởi động và quản lý bằng Compose

Mở Docker Desktop và chờ Engine chạy. Trong thư mục dự án:

```powershell
docker compose version
docker compose config --quiet
docker compose up -d --build --wait
```

- `up`: tạo/khởi động cả hai service.
- `-d`: chạy ngầm.
- `--build`: build image API trước khi chạy.
- `--wait`: chờ các service chạy/healthy.

Kiểm tra:

```powershell
docker compose ps
docker compose logs --tail 50
Invoke-RestMethod -Uri 'http://127.0.0.1:3000/health'
```

Kết quả `/health` mong đợi:

```json
{
  "status": "ok",
  "database": "productdb",
  "mongodb": "connected"
}
```

Xem log API liên tục; Ctrl+C chỉ thoát chế độ xem log:

```powershell
docker compose logs -f api
```

Xem log MongoDB:

```powershell
docker compose logs --tail 50 mongodb
```

Dừng cả hai service, giữ container:

```powershell
docker compose stop
```

Chạy lại container đã dừng:

```powershell
docker compose start --wait
```

Gỡ các container Compose và mạng do Compose tạo:

```powershell
docker compose down
```

Chạy lại cả hệ thống:

```powershell
docker compose up -d --wait
```

External volume `nammongodb_data` vẫn giữ dữ liệu. Hai container backup từ câu 7 cũng được giữ lại.

## 6. Kiểm tra CRUD và dữ liệu

Các endpoint API giữ nguyên như câu 6 và 7. Kiểm tra danh sách:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:3000/api/products'
```

Chạy bộ kiểm thử HTTP với API thực sự ở trong container:

```powershell
.\scripts\test-docker-api.ps1
```

Script tạo sản phẩm có mã riêng, xác nhận document trong MongoDB, thử GET/PUT/PATCH/DELETE và lỗi dữ liệu, sau đó dọn bản ghi thử.

Mở MongoDB Shell bằng tên service Compose:

```powershell
docker compose exec mongodb mongosh productdb
```

Trong shell, nhập:

```javascript
show collections
db.products.find()
db.products.countDocuments()
```

Nhập `exit` để về PowerShell. Dùng tên service `mongodb`, `api` trong các lệnh Compose; dùng tên container `nammongodb`, `product-api` trong các lệnh Docker thông thường.

## 7. Khi sửa mã nguồn hoặc cấu hình

Sau khi sửa mã JavaScript:

```powershell
docker compose up -d --build --wait
```

Sau khi sửa `.env.docker`, chạy `docker compose up -d --wait` để Compose áp dụng cấu hình mới; chỉ `restart` sẽ không đưa các giá trị môi trường mới vào container.

## 8. Quay lại hai container cũ nếu cần

Phần này chỉ áp dụng khi hai container backup còn tồn tại. Dừng và gỡ hai container do Compose quản lý trước:

```powershell
docker compose down
docker rename nammongodb-before-compose nammongodb
docker rename product-api-before-compose product-api
docker start nammongodb
docker start product-api
```

Container cũ tiếp tục sử dụng mạng và volume đã có ở câu 7.

## 9. Máy mới và lỗi thường gặp

Nếu tải dự án lên một máy mới, tạo file cấu hình và volume trước khi chạy:

```powershell
Copy-Item .env.docker.example .env.docker
docker volume create nammongodb_data
docker compose up -d --build --wait
```

- **Docker Engine chưa chạy:** mở Docker Desktop hoặc chạy `docker desktop start` nếu CLI hỗ trợ.
- **Tên container đã tồn tại:** dùng script chuyển đổi ở phần 4 cho hai container thủ công của câu 7.
- **Cổng 3000/27017 bị chiếm:** xác định tiến trình/container đang giữ cổng; chỉ dừng đúng ứng dụng cần chuyển đổi.
- **MongoDB Windows tự chạy lại sau khi bật máy:** kiểm tra `Get-NetTCPConnection -LocalPort 27017 -State Listen`, xác định tiến trình `mongod` và dịch vụ tương ứng. Nếu đúng là dịch vụ `MongoDB`, mở PowerShell bằng Administrator và chạy `Stop-Service -Name MongoDB` trước khi khởi động MongoDB Docker.
- **External volume not found:** kiểm tra `docker volume ls`; trên máy mới tạo volume theo ví dụ trên.
- **MongoDB unhealthy/API không chạy:** xem `docker compose logs mongodb api`, kiểm tra `.env.docker` và volume.

Bằng chứng cho câu 8: file Compose có đủ hai service; `docker compose ps` báo healthy; `/health` kết nối thành công; CRUD hoạt động và MongoDB vẫn gắn volume `nammongodb_data`.
