# Bài 13: Chạy bản Product API từ Docker Hub trên local

File `docker-compose-prod.yaml` dùng image đã publish ở bài 12.
Service API không có `build:`; Dockerfile và source không cần thiết để khởi động
bản triển khai này. Máy local cần Docker Engine đang chạy Linux containers.

## 1. Cấu hình

Trong terminal PowerShell của VS Code, tại `D:\Project\product-api`:

```powershell
# Chỉ copy khi chưa có file để giữ cấu hình đã chỉnh.
if (-not (Test-Path .env.prod)) {
    Copy-Item .env.prod.example .env.prod
}
code .env.prod
```

Sửa `DOCKERHUB_IMAGE=yourusername/product-api` thành đúng giá trị
`DOCKERHUB_IMAGE` đã cấu hình trong GitHub Actions ở bài 12.
`yourusername` là ví dụ và cần thay trước khi pull.

```dotenv
DOCKERHUB_IMAGE=yourusername/product-api
IMAGE_TAG=latest
NODE_ENV=production
HOST=0.0.0.0
PORT=3000
API_HOST_PORT=3000
MONGO_URI=mongodb://nammongodb:27017/productdb
HEALTHCHECK_TIMEOUT_MS=2000
```

`--env-file .env.prod` cung cấp biến cho Compose thay vào image và cổng.
`env_file: .env.prod` cung cấp cấu hình cho ứng dụng bên trong container.
API kết nối `nammongodb:27017` qua mạng Compose, không dùng localhost trong container.
File `.env.prod` được Git bỏ qua; chỉ commit `.env.prod.example`.

## 2. Pull và chạy sau khi CD thành công

Với repository Docker Hub private, chạy `docker login` trước và nhập credentials
qua lời nhắc của Docker. Repository public có thể pull trực tiếp.

```powershell
# Idempotent: giữ volume đã có; tạo mới nếu máy chưa có volume.
docker volume create nammongodb_data

docker compose --env-file .env.prod -f docker-compose-prod.yaml config --quiet
docker compose --env-file .env.prod -f docker-compose-prod.yaml pull api
docker compose --env-file .env.prod -f docker-compose-prod.yaml up -d --no-build --wait --wait-timeout 180
docker compose --env-file .env.prod -f docker-compose-prod.yaml ps
Invoke-RestMethod http://127.0.0.1:3000/health
```

Chỉ tiếp tục lệnh sau khi lệnh trước thành công. Pull trước giúp phát hiện image
chưa được publish hoặc sai tên trước khi cập nhật API đang chạy. `pull_policy: always`
khiến Compose lấy image từ registry mỗi lần chạy `up`.

`up --wait` chỉ hoàn tất khi cả MongoDB và API healthy; API còn có
`depends_on: condition: service_healthy` để chờ MongoDB trước khi khởi động.
Kết quả `/health` mong đợi:

```json
{"status":"ok","database":"productdb","mongodb":"connected"}
```

Nếu đổi `API_HOST_PORT`, thay cổng trong URL kiểm tra cho tương ứng.
Đây là cấu hình chạy local, các cổng chỉ bind trên `127.0.0.1`.

## 3. Chuyển từ Compose bài 8 sang image Docker Hub

Cả `compose.yaml` cũ và file production dùng project `product-api`, service
`mongodb`/`api`, container `nammongodb`/`product-api` và external volume
`nammongodb_data`. Với stack hiện tại, dùng trực tiếp các lệnh ở bước 2 để
cập nhật API trong cùng project. Không cần `down` hay đổi tên container.

Sau khi chuyển, dùng đầy đủ `--env-file .env.prod -f docker-compose-prod.yaml`
cho các lệnh vận hành; lệnh `docker compose up` không có `-f` sẽ chọn file cũ.
Nếu container đang thuộc project khác hoặc là container tạo thủ công, cần kiểm tra
nguồn sở hữu trước khi chuyển. Không chạy hai MongoDB đồng thời cùng volume dữ liệu.

## 4. Cập nhật, xem log, dừng, chọn bản cũ

Sau lần CD tiếp theo, chạy lại `pull api` và `up --no-build --wait` như bước 2.
Để dùng đúng một bản đã phát hành, sửa `.env.prod` thành:

```dotenv
IMAGE_TAG=sha-<full-commit-sha>
```

Sau đó chạy lại hai lệnh pull/up. Tag đó phải tồn tại trên Docker Hub.

```powershell
docker compose --env-file .env.prod -f docker-compose-prod.yaml logs --tail 100 api mongodb
docker compose --env-file .env.prod -f docker-compose-prod.yaml stop
# Khi muốn khởi động lại, dùng up --no-build --wait như bước 2.
```

Volume `nammongodb_data` là external nên được tái sử dụng và không do Compose xóa
khi `down`. Không dùng `docker volume rm nammongodb_data` để cập nhật ứng dụng.
`restart: unless-stopped` khởi động lại container khi process thoát; riêng trạng thái
unhealthy không tự kích hoạt restart.

## 5. Khi pull chưa được

`pull access denied`/`manifest unknown`: kiểm tra tên image, tag, quyền truy cập và
job CD đã publish thành công chưa. Không thể pull image chưa tồn tại trên Hub.
Có thể chạy `config --quiet` để kiểm tra file trước khi hoàn tất bài 12.

Tài liệu: https://docs.docker.com/reference/cli/docker/compose/up/
và https://docs.docker.com/reference/compose-file/volumes/
