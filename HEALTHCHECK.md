# Câu 9 — Healthcheck cho MongoDB và Product API

MongoDB được kiểm tra bằng lệnh `ping`. Product API được kiểm tra bằng HTTP `GET /health`; endpoint này tiếp tục gửi một lệnh ping thật đến database trước khi trả thành công.

## 1. Healthcheck MongoDB trong compose.yaml

```yaml
healthcheck:
  test: ["CMD", "mongosh", "--quiet", "--eval", "quit(db.runCommand({ ping: 1 }).ok === 1 ? 0 : 1)"]
  interval: 5s
  timeout: 5s
  retries: 12
  start_period: 10s
```

- `test`: lệnh chạy bên trong container. MongoDB trả `ok: 1` thì mongosh thoát với mã 0; lỗi trả mã khác 0 hoặc bị timeout.
- `interval`: khoảng thời gian giữa các lần kiểm tra.
- `timeout`: thời gian tối đa cho một lần kiểm tra.
- `retries`: số lần thất bại liên tiếp để đánh dấu unhealthy sau giai đoạn khởi động.
- `start_period`: thời gian hỗ trợ khởi động; các lần thất bại trong giai đoạn này chưa được tính vào ngưỡng, trừ khi đã có lần kiểm tra thành công.

## 2. Endpoint /health của API

Trong `src/app.js`, endpoint kiểm tra Mongoose đã kết nối, rồi gọi:

```javascript
await mongoose.connection.db.command(
  { ping: 1 },
  { timeoutMS: getHealthcheckTimeout() }
);
```

Giới hạn thời gian ping được cấu hình trong `.env` hoặc `.env.docker`:

```dotenv
HEALTHCHECK_TIMEOUT_MS=2000
```

Giá trị phải là số nguyên từ 100 đến 3000 ms để phù hợp thời gian chờ của Docker probe. Mặc định là 2000 ms nếu biến chưa được khai báo. MongoDB Node.js driver hỗ trợ `timeoutMS` cho một thao tác để tránh health request treo quá lâu. [MongoDB driver operation timeout](https://www.mongodb.com/docs/drivers/node/current/connect/connection-options/csot/).

Khi ping thành công, API trả HTTP **200**:

```json
{
  "status": "ok",
  "database": "productdb",
  "mongodb": "connected"
}
```

Khi chưa kết nối hoặc ping thất bại, API trả HTTP **503**. `mongodb` là `disconnected` nếu Mongoose chưa kết nối, hoặc `unavailable` nếu thao tác ping thất bại.

Response có `Cache-Control: no-store` để tránh lưu kết quả health cũ. Endpoint không ghi hay thay đổi dữ liệu sản phẩm.

## 3. Healthcheck Product API

Trong service `api` của `compose.yaml`:

```yaml
healthcheck:
  test: ["CMD", "node", "src/healthcheck.js"]
  interval: 5s
  timeout: 5s
  retries: 3
  start_period: 15s
```

`src/healthcheck.js` dùng `fetch` có sẵn trong Node.js 24 để gọi `/health` trên cổng `PORT`. Probe chỉ thoát mã 0 khi nhận HTTP 200 và JSON xác nhận `mongodb: connected`; lỗi HTTP, timeout hoặc JSON không hợp lệ đều trả mã 1.

Dockerfile cũng dùng probe này để container tạo bằng `docker run` có healthcheck. Cấu hình Compose có thể ghi đè healthcheck trong Dockerfile. [Docker Compose healthcheck](https://docs.docker.com/reference/compose-file/services/#healthcheck).

## 4. Chờ database sẵn sàng trước khi khởi động API

```yaml
depends_on:
  mongodb:
    condition: service_healthy
```

Compose đợi healthcheck MongoDB thành công trước khi khởi động API. [Docker startup order](https://docs.docker.com/compose/how-tos/startup-order/).

## 5. Áp dụng và kiểm tra

Trong terminal PowerShell của VS Code:

```powershell
Set-Location 'D:\Project\product-api'
docker compose config --quiet
docker compose up -d --build --wait
docker compose ps
```

Hai container cần có trạng thái `healthy`.

Xem riêng trạng thái health:

```powershell
docker inspect nammongodb --format '{{.State.Health.Status}}'
docker inspect product-api --format '{{.State.Health.Status}}'
```

Xem lịch sử và mã thoát của các lần kiểm tra:

```powershell
docker inspect product-api --format '{{json .State.Health}}'
docker inspect nammongodb --format '{{json .State.Health}}'
```

Kiểm tra endpoint:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:3000/health'
```

Chạy probe API thủ công bên trong container:

```powershell
docker compose exec -T api node src/healthcheck.js
$LASTEXITCODE
```

Khi tốt, mã thoát là `0`.

## 6. Kiểm thử lỗi và phục hồi

Script sau sẽ **tạm dừng MongoDB**, xác nhận `/health` trả 503 và Docker đánh dấu API unhealthy, rồi khởi động lại MongoDB và chờ cả hai healthy. Trong thời gian thử, các request cần database có thể thất bại.

```powershell
.\scripts\test-healthcheck.ps1
```

Script có khối `finally` để khôi phục service sau khi kiểm thử, kể cả khi một assertion thất bại. Volume dữ liệu không bị xóa.

Nếu execution policy chặn script, có thể chạy riêng tiến trình:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-healthcheck.ps1
```

Thử thủ công:

```powershell
docker compose stop mongodb
```

GET `/health` lúc này trả 503; sau các lần probe thất bại liên tiếp, API chuyển `unhealthy`. Khôi phục:

```powershell
docker compose start --wait mongodb
docker compose ps
```

Chờ API kết nối lại và có kết quả `healthy`, rồi thử lại `/health` và CRUD. Khi API đang unhealthy, lệnh `docker compose up --wait` có thể báo lỗi ngay trước khi Mongoose kịp kết nối lại; script kiểm thử sẽ chờ trạng thái phục hồi bằng cách kiểm tra định kỳ.

## 7. Ý nghĩa các trạng thái

| Trạng thái | Ý nghĩa |
| --- | --- |
| `starting` | Docker đang chờ kết quả healthcheck ban đầu. |
| `healthy` | Probe gần nhất thành công. |
| `unhealthy` | Probe đã thất bại liên tiếp đến ngưỡng cấu hình. |

Healthcheck mô tả khả năng phục vụ của ứng dụng. `restart: unless-stopped` xử lý việc container dừng/thoát; Docker Engine không tự restart container chỉ vì healthcheck chuyển sang unhealthy. API sẽ trở lại healthy khi MongoDB phục hồi và probe thành công. [Docker restart policies](https://docs.docker.com/engine/containers/start-containers-automatically/).

Bằng chứng cho câu 9: cấu hình healthcheck của cả hai service; `/health` trả 200 khi database tốt; trả 503 khi database dừng; API chuyển unhealthy rồi phục hồi healthy.
