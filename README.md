# Câu 6 — RESTful API CRUD Product với Mongoose và MongoDB Docker

Ứng dụng chạy bằng Node.js trong terminal VS Code trên Windows. MongoDB chạy trong container `nammongodb` và được ánh xạ ra `127.0.0.1:27017`.

## 1. Công nghệ và cấu trúc

- Express 5: nhận HTTP request, định tuyến và trả JSON.
- Mongoose 9: định nghĩa Product và thực hiện truy vấn MongoDB.
- dotenv 17: đọc các thông tin cấu hình từ `.env`.
- Node.js từ 20.19 trở lên; có thể dùng Node.js 24.

```text
product-api/
├── .env
├── .env.example
├── .gitignore
├── package.json
├── package-lock.json
├── requests.http
├── README.md
├── src/
│   ├── app.js
│   ├── server.js
│   ├── config/
│   │   ├── env.js
│   │   └── database.js
│   ├── models/
│   │   └── Product.js
│   ├── controllers/
│   │   └── productController.js
│   ├── routes/
│   │   └── productRoutes.js
│   └── middleware/
│       └── errorHandler.js
└── test/
    └── product-api.test.js
```

Luồng xử lý: HTTP request → Express route → controller → Mongoose model → MongoDB trong `nammongodb` → JSON response.

## 2. Cấu hình `.env`

Đặt `.env` cùng cấp với `package.json`:

```dotenv
HOST=127.0.0.1
PORT=3000
MONGO_URI=mongodb://127.0.0.1:27017/productdb
TEST_MONGO_URI=mongodb://127.0.0.1:27017/product_api_test
```

| Biến | Ý nghĩa |
| --- | --- |
| `HOST` | Địa chỉ API lắng nghe trên máy Windows. |
| `PORT` | Cổng HTTP của API, ở đây là `3000`. |
| `MONGO_URI` | Địa chỉ MongoDB và tên database ứng dụng. |
| `TEST_MONGO_URI` | Database dùng cho kiểm thử tự động. |

Giải thích `mongodb://127.0.0.1:27017/productdb`:

- `mongodb://`: giao thức kết nối MongoDB.
- `127.0.0.1`: máy Windows đang chạy API.
- `27017`: cổng container đã publish ra máy Windows.
- `productdb`: database lưu sản phẩm; MongoDB lưu database khi có dữ liệu hoặc collection đầu tiên.

API chạy trên Windows nên kết nối qua `127.0.0.1`, không dùng tên container `nammongodb` làm hostname. Cấu hình này phù hợp với container đã tạo trong câu trước, chưa bật xác thực.

`src/config/env.js` gọi `dotenv.config()` trước khi đọc cấu hình qua `process.env`. `.gitignore` bỏ qua `.env`; `.env.example` là mẫu để người khác sao chép khi tải dự án. [Tài liệu dotenv](https://www.npmjs.com/package/dotenv), [Mongoose connections](https://mongoosejs.com/docs/connections.html).

## 3. Chạy ứng dụng trong VS Code

Mở thư mục `D:\Project\product-api` trong VS Code, chọn **Terminal → New Terminal**. Chạy:

```powershell
Set-Location 'D:\Project\product-api'
node --version
npm.cmd --version
docker ps --filter "name=^/nammongodb$"
```

Nếu container đang dừng, chạy:

```powershell
docker start nammongodb
```

Nếu bạn lấy mã từ GitHub và chưa có `.env`, tạo từ mẫu:

```powershell
Copy-Item .env.example .env
```

Chỉ sao chép mẫu khi chưa có `.env`, để giữ các cấu hình bạn đã chỉnh.

Cài thư viện theo `package-lock.json`:

```powershell
npm.cmd ci
```

Khởi động API:

```powershell
npm.cmd run dev
```

`node --watch` tự khởi động lại khi sửa mã JavaScript. Sau khi sửa `.env`, dừng bằng **Ctrl + C** và chạy lại API. Nếu không cần theo dõi thay đổi, dùng `npm.cmd start`.

Khi kết nối thành công, terminal in:

```text
MongoDB connected: productdb
Product API: http://127.0.0.1:3000
```

Giữ terminal này chạy. Mở terminal thứ hai để thử API:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:3000/health'
```

Kết quả mong đợi:

```json
{
  "status": "ok",
  "database": "productdb",
  "mongodb": "connected"
}
```

`/health` kiểm tra trạng thái kết nối Mongoose và gửi ping thật đến MongoDB với giới hạn thời gian. Phép kiểm tra tạo sản phẩm và đọc trực tiếp trong MongoDB ở các phần dưới xác nhận dữ liệu được ghi vào container.

## 4. Model Product

Trong `src/models/Product.js`:

| Trường | Kiểu | Quy tắc |
| --- | --- | --- |
| `pid` | String | Bắt buộc, duy nhất; ví dụ `P001`. |
| `pname` | String | Bắt buộc, không được rỗng sau khi bỏ khoảng trắng đầu/cuối. |
| `price` | Number | Bắt buộc, hữu hạn, lớn hơn hoặc bằng 0. |
| `quantity` | Number | Bắt buộc, số nguyên an toàn, lớn hơn hoặc bằng 0. |

MongoDB tạo thêm `_id` cho mỗi document. `pid` là mã sản phẩm do bạn nhập, dùng để tìm, sửa và xóa qua URL. Các document nằm trong collection `products`.

Mongoose thực hiện validation theo schema. Khi cập nhật, controller dùng `runValidators: true` để tiếp tục kiểm tra giá và số lượng, và `returnDocument: 'after'` để trả về sản phẩm sau cập nhật. `unique: true` tạo unique index; lỗi trùng mã được middleware chuyển thành HTTP `409`. Server chờ `Product.init()` trước khi nhận request để index sẵn sàng. [Tài liệu Mongoose validation](https://mongoosejs.com/docs/validation.html).

## 5. Các endpoint CRUD

Base URL: `http://127.0.0.1:3000`

| Method | Endpoint | Chức năng | Thành công |
| --- | --- | --- | --- |
| `GET` | `/health` | Kiểm tra trạng thái kết nối | `200` |
| `POST` | `/api/products` | Tạo sản phẩm | `201` |
| `GET` | `/api/products` | Đọc danh sách sản phẩm | `200` |
| `GET` | `/api/products/:pid` | Đọc một sản phẩm theo mã | `200` |
| `PUT` | `/api/products/:pid` | Cập nhật đủ bốn trường | `200` |
| `PATCH` | `/api/products/:pid` | Cập nhật các trường được gửi | `200` |
| `DELETE` | `/api/products/:pid` | Xóa sản phẩm theo mã | `200` |

POST và PUT yêu cầu đủ `pid`, `pname`, `price`, `quantity`. PATCH chỉ cần ít nhất một trường. Khi sửa `pid`, dùng mã mới trong những request tiếp theo.

Các request có body phải dùng `Content-Type: application/json`. Mã lỗi: `400` cho dữ liệu/JSON không hợp lệ, `404` cho sản phẩm không tồn tại, `409` cho mã trùng, `500` cho lỗi máy chủ. Express 5 chuyển lỗi trong controller `async` đến middleware xử lý lỗi. [Tài liệu Express error handling](https://expressjs.com/en/guide/error-handling/).

## 6. Thử CRUD bằng PowerShell

Mở terminal thứ hai, giữ API chạy trong terminal thứ nhất. Thử theo thứ tự; mẫu này dùng mã `P001` chưa tồn tại.

### Create: tạo sản phẩm

```powershell
$product = @{
    pid = 'P001'
    pname = 'Ban phim'
    price = 350000
    quantity = 10
} | ConvertTo-Json

Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:3000/api/products' -ContentType 'application/json' -Body $product
```

Response chứa `_id` và bốn trường đã gửi. Gửi lại cùng `pid` sẽ nhận `409`.

### Read: đọc danh sách và một sản phẩm

```powershell
Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:3000/api/products'
Invoke-RestMethod -Method Get -Uri 'http://127.0.0.1:3000/api/products/P001'
```

### Update: cập nhật bằng PUT

```powershell
$updatedProduct = @{
    pid = 'P001'
    pname = 'Ban phim co'
    price = 500000
    quantity = 8
} | ConvertTo-Json

Invoke-RestMethod -Method Put -Uri 'http://127.0.0.1:3000/api/products/P001' -ContentType 'application/json' -Body $updatedProduct
```

Response là sản phẩm sau cập nhật. Dùng PATCH khi chỉ cần sửa số lượng:

```powershell
Invoke-RestMethod -Method Patch -Uri 'http://127.0.0.1:3000/api/products/P001' -ContentType 'application/json' -Body '{"quantity":5}'
```

### Kiểm tra dữ liệu nằm trong container

Chạy trước khi xóa sản phẩm:

```powershell
docker exec nammongodb mongosh productdb --quiet --eval 'db.products.find({pid: "P001"}).toArray()'
```

Hoặc mở shell tương tác để tránh vấn đề dấu nháy giữa các phiên bản PowerShell:

```powershell
docker exec -it nammongodb mongosh productdb
```

Trong MongoDB Shell, nhập:

```javascript
db.products.find({ pid: "P001" })
```

Lệnh MongoDB này chạy trong `mongosh`, không nhập trực tiếp vào PowerShell. Gõ `exit` để thoát shell.

### Delete: xóa sản phẩm

```powershell
Invoke-RestMethod -Method Delete -Uri 'http://127.0.0.1:3000/api/products/P001'
```

GET lại `/api/products/P001` trả `404`; GET danh sách sẽ không còn sản phẩm vừa xóa.

## 7. Thử bằng Postman hoặc file requests.http

Trong Postman, chọn method và URL ở bảng trên. Với POST/PUT/PATCH, chọn **Body → raw → JSON** và nhập JSON tương ứng:

```json
{
  "pid": "P001",
  "pname": "Ban phim",
  "price": 350000,
  "quantity": 10
}
```

File `requests.http` có sẵn các request. Bạn có thể dùng nội dung trong Postman, hoặc chạy **Send Request** trong VS Code nếu đã cài extension hỗ trợ HTTP requests như REST Client.

## 8. Kiểm thử tự động

Container phải đang chạy. Trong thư mục dự án:

```powershell
npm.cmd test
```

Bộ test dùng HTTP thật và MongoDB thật qua Mongoose: tạo/đọc/sửa/xóa, trùng mã, dữ liệu không hợp lệ, JSON sai, sản phẩm không tồn tại và đổi mã sản phẩm. Test dùng `TEST_MONGO_URI`, tạo mã riêng rồi xóa đúng các bản ghi đó; không drop database. Server kiểm thử dùng cổng tạm nên không cần dừng API trên cổng `3000`.

## 9. Lỗi thường gặp

- **ECONNREFUSED 127.0.0.1:27017 / server selection timeout:** kiểm tra `docker ps`, chạy `docker start nammongodb`, kiểm tra `MONGO_URI` trong `.env`.
- **EADDRINUSE 127.0.0.1:3000:** một chương trình đang dùng cổng API. Dừng phiên API cũ hoặc đổi `PORT` trong `.env`, rồi chạy lại.
- **npm.ps1 cannot be loaded:** dùng `npm.cmd` như các ví dụ, không cần đổi execution policy.
- **pid đã tồn tại:** dùng một mã khác, hoặc đọc/cập nhật sản phẩm hiện có.
- **PUT thiếu trường:** gửi đủ bốn trường; dùng PATCH nếu chỉ sửa một phần.
- **Không thấy dữ liệu:** vào database `productdb`, collection `products`; database test là `product_api_test`.

## 10. Giải thích mã nguồn

- `config/env.js`: nạp `.env` và kiểm tra host, cổng, URI trước khi chạy.
- `config/database.js`: gọi `mongoose.connect()` đến MongoDB trong container.
- `models/Product.js`: định nghĩa các trường, kiểu dữ liệu và quy tắc kiểm tra.
- `controllers/productController.js`: thực hiện `create`, `find`, `findOne`, `findOneAndUpdate`, `findOneAndDelete`. Bộ lọc dùng `pid`, còn body chỉ nhận các trường Product.
- `routes/productRoutes.js`: ánh xạ các method HTTP đến controller tương ứng.
- `middleware/errorHandler.js`: trả JSON và mã HTTP phù hợp khi có lỗi.
- `app.js`: bật đọc JSON, đăng ký các route và middleware.
- `server.js`: kết nối MongoDB, chờ unique index, rồi mở cổng API. Khi nhấn Ctrl+C, đóng server và kết nối Mongoose.

Khi báo cáo bài tập, có thể chụp: container đang Up trên cổng 27017; log kết nối API; kết quả POST, GET, PUT, DELETE; và document trong collection `products` ở container.

## Cau 7: Dockerize

Xem [DOCKER.md](DOCKER.md) de build image va chay API ket noi voi container nammongodb.


## Cau 8: Docker Compose

Xem [COMPOSE.md](COMPOSE.md) de chay API va MongoDB bang Docker Compose, dung lai volume nammongodb_data.



## Cau 9: Healthcheck

Xem [HEALTHCHECK.md](HEALTHCHECK.md) de kiem tra MongoDB, Product API va thu tinh huong mat ket noi database.

