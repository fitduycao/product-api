# Bài 14: GitHub Actions -> Docker Hub -> Docker Engine local

```text
Push lên nhánh mặc định
  -> ci (Ubuntu GitHub): build + MongoDB/API healthcheck + CRUD
  -> cd (Ubuntu GitHub): publish image sha-<commit> và latest
  -> deploy-local (self-hosted runner Windows trên PC)
     -> pull đúng tag sha-<commit>
     -> chờ MongoDB healthy
     -> cập nhật API và chờ healthy
     -> gọi /health
     -> lưu phiên bản đã chạy vào .env.prod
```

Hai job đầu giữ nguyên kiểm thử của bài 12. Job `deploy-local` có `needs: [ci, cd]`;
nếu CI/healthcheck/publish lỗi thì local không được cập nhật. Pull request và nhánh
khác không chạy deploy local. Không dùng `latest` để xác định bản tự động triển khai.

## 1. Cấu hình GitHub và Docker Hub

Chọn đúng repository GitHub trước khi đăng ký runner. Remote hiện tại của checkout
local là `https://github.com/fitduycao/product-api`; link ban đầu trong bài là
`https://github.com/ntthuyvy0205-source/product-api`. Script không tự đổi remote.

Trong GitHub -> Settings -> Secrets and variables -> Actions:

| Loại | Tên | Giá trị |
| --- | --- | --- |
| Variable | DOCKERHUB_USERNAME | Username đăng nhập Docker Hub |
| Variable | DOCKERHUB_IMAGE | namespace/product-api đã tạo trên Hub |
| Variable | LOCAL_DEPLOY_PATH | D:\Project\product-api |
| Secret | DOCKERHUB_TOKEN | Docker Hub PAT có quyền Read/Write |

Workflow sử dụng Docker Hub token để publish và để runner pull, kể cả repository private.
Không ghi token vào .env.prod, mã nguồn hay chat.

## 2. Chuẩn bị PC

- Bật Docker Desktop, chọn Linux containers; mở terminal bằng Windows user đang dùng Docker.
- `docker info` và `docker compose version` phải chạy được trong chính tài khoản chạy runner.
- `.env.prod` tại LOCAL_DEPLOY_PATH phải tồn tại và có HOST=0.0.0.0, PORT, API_HOST_PORT,
  MONGO_URI=mongodb://nammongodb:27017/productdb và HEALTHCHECK_TIMEOUT_MS như bài 13.
- Script lấy image và tag từ job publish, ghi hai giá trị đó vào .env.prod sau khi deploy thành công.
- Không chọn thư mục runner `_work` làm LOCAL_DEPLOY_PATH; đây phải là nơi giữ cấu hình runtime.

## 3. Đăng ký runner một lần

Script setup tải bản Windows x64 chính thức mới nhất từ `actions/runner`, so sánh
SHA256 với metadata GitHub rồi giải nén vào `D:\actions-runner-product-api`.
Nó không tự đăng ký khi dùng `-PrepareOnly` và không ghi token vào file.

Trong PowerShell tại thư mục dự án (thay URL bằng repo đã xác nhận):

```powershell
.\scripts\setup-local-runner.ps1 -RepositoryUrl 'https://github.com/OWNER/product-api'
```

Khi script yêu cầu token, lấy token đăng ký từ **GitHub repository -> Settings ->
Actions -> Runners -> New self-hosted runner -> Windows / x64**, nhập trực tiếp vào
terminal. Đây là token đăng ký runner có thời hạn, khác Docker Hub PAT.

Script gắn label `product-api-local`; các label `self-hosted`, `Windows`, `X64`
do runner cung cấp. Sau khi đăng ký, chạy trong terminal riêng của cùng Windows user:

```powershell
& 'D:\actions-runner-product-api\run.cmd'
```

Giữ runner online (terminal báo Listening for Jobs), Docker Desktop chạy và PC có mạng.
Job deploy sẽ chờ nếu PC/runner offline. Để chạy dưới Windows service sau này,
cần cấu hình service bằng tài khoản có quyền truy cập Docker; chạy tương tác là cách
thiết lập đầu tiên ở bài này, không tự cài service dưới tài khoản hệ thống.

GitHub khuyến nghị self-hosted runner cho repository private. Chỉ dùng PC/runner
cho repository và người có quyền chạy workflow mà bạn tin cậy; điều kiện nhánh trong
job deploy không thay thế việc kiểm soát workflow của repository public.

## 4. Kích hoạt tự động

Commit/push workflow cập nhật, scripts/deploy-local.ps1, docker-compose-prod.yaml
cùng đầy đủ source/test/package của các bài trước lên repository đã chọn.
Giữ .env.prod trên PC; Git bỏ qua file này.

Push tiếp theo lên nhánh mặc định tự chạy cả ba job. Có thể chạy thử bằng
Actions -> Product API CI-CD Docker Hub and Local -> Run workflow, chọn nhánh mặc định.

Runner checkout vào `_work` riêng, không clean thư mục runtime D:\Project\product-api.
Workflow gọi script từ đúng commit đã publish, lấy Compose từ checkout và dùng
`--project-directory`/`--env-file` trỏ về runtime local. Sau khi healthy, Compose và
tag thành công được lưu lại ở thư mục runtime để dùng tiếp lệnh thủ công của bài 13.

Script kiểm tra project sở hữu container và volume trước khi cập nhật. Container
tạo thủ công hoặc thuộc project khác phải được chuyển đúng cách trước; script sẽ
dừng thay vì tự xóa container không thuộc stack này.

## 5. Healthcheck và phục hồi

- Pull thất bại: API cũ tiếp tục chạy.
- API mới không healthy: script thử khởi động lại image API trước đó từ cache và kiểm tra /health.
- Dù phục hồi được, job vẫn báo lỗi để bạn biết bản mới chưa triển khai thành công.
- Nếu đây là lần chạy đầu và không có API cũ, script dừng API lỗi, giữ MongoDB/data để kiểm tra.
- Tag cache `product-api-rollback:previous` giữ image trước lần cập nhật.
- Phục hồi image API không đảo ngược thay đổi dữ liệu hoặc migration database.
- Quy trình deploy không chạy down/volume rm và không xóa nammongodb_data.

Kiểm tra trên PC:

```powershell
docker compose --env-file .env.prod -f docker-compose-prod.yaml ps
Invoke-RestMethod http://127.0.0.1:3000/health
docker inspect product-api --format '{{.Config.Image}}'
```

Image mong đợi: namespace/product-api:sha-<commit vừa publish>.
Đổi URL kiểm tra nếu API_HOST_PORT khác 3000.

## Tài liệu chính thức

- https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners
- https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/use-in-a-workflow
- https://docs.docker.com/reference/cli/docker/compose/up/
