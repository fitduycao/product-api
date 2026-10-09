# Bai 12: CI/CD Product API voi Docker Hub

Workflow: `.github/workflows/product-cicd-dockerhub.yml`.

```text
Push / Pull request / Run workflow
  -> CI: build Dockerfile production
  -> Cho MongoDB + API healthy (toi da 180 giay)
  -> Test CRUD qua HTTP + doc truc tiep MongoDB
  -> Xac nhan hai container van healthy
  -> Luu chinh image da test thanh artifact
  -> CD (chi nhanh mac dinh, CI thanh cong)
  -> Load image, so sanh image ID voi CI
  -> Login Docker Hub -> push tag sha-<commit> va latest
```

## 1. Chuan bi Docker Hub

1. Dang nhap https://hub.docker.com/ va tao repository `product-api` trong namespace cua ban.
2. Vao Account settings -> Personal access tokens -> Generate new token.
3. Tao token cho GitHub Actions voi quyen Read va Write (khong can Delete).
4. Luu token truc tiep vao GitHub Secrets o buoc tiep theo; khong dan token vao source hay chat.

## 2. Cau hinh repository GitHub

Trong DUNG repository se nhan code: Settings -> Secrets and variables -> Actions.

Tab Variables -> New repository variable:

| Ten | Gia tri |
| --- | --- |
| DOCKERHUB_USERNAME | Ten tai khoan Docker Hub dung de dang nhap |
| DOCKERHUB_IMAGE | Ten day du, vi du `yourusername/product-api` (chu thuong, khong kem tag) |

Tab Secrets -> New repository secret:

| Ten | Gia tri |
| --- | --- |
| DOCKERHUB_TOKEN | Personal access token Docker Hub co quyen push repository tren |

Username dang nhap va namespace image co the khac nhau neu dung repository cua to chuc.

## 3. Commit va push code

Can commit workflow nay cung `compose.ci.yaml`, `Dockerfile`, `.dockerignore`,
`package.json`, `package-lock.json`, `src/` va `test/product-api.prod.test.js`.
Workflow tu tao `.env.ci`; khong commit file .env hay token.

Du an hien chua co commit; can dua day du source len GitHub, khong chi workflow.
Chay `git remote -v` va xac nhan repository dung truoc khi push.
Tai thoi diem cai dat, origin local la `https://github.com/fitduycao/product-api`,
khac repository duoc nhac luc dau `https://github.com/ntthuyvy0205-source/product-api`.
Huong dan nay khong tu doi remote hoac push.

Vao Actions -> Product API CI-CD Docker Hub -> xem job ci va cd.
Pull request va nhanh khac chi chay CI. Push hoac Run workflow tren nhanh mac dinh
se chay CD sau khi CI thanh cong. Workflow can nam tren nhanh mac dinh de chay thu cong.
CI hong/healthcheck hong -> CD khong chay. Thieu token/variables -> CD bao loi, khong push.

Hai workflow bai 10 va 11 van co the chay doc lap. Neu giu ca ba workflow,
push/PR se chay them cac bo CI doc lap nay; CD chi phu thuoc job ci cua workflow bai 12.

## 4. Ket qua va cach dung image

Docker Hub se co:

```text
yourusername/product-api:latest
yourusername/product-api:sha-<full-commit-sha>
```

Tag SHA giup chon dung ban khi trien khai hoac quay lai ban cu; latest la tag cap nhat
sau moi lan publish thanh cong. Image la Linux/amd64 tu Ubuntu runner va giu HEALTHCHECK
trong Dockerfile. Runtime config va database khong duoc dong goi vao image.

Vi du trong PowerShell (thay yourusername bang namespace thuc te):

```powershell
docker pull yourusername/product-api:latest
docker image inspect yourusername/product-api:latest --format '{{json .Config.Healthcheck}}'
```

De chay image tu Hub bang Compose hien co, thay `image: product-api:1.0` cua service
api bang `image: yourusername/product-api:latest` va bo muc `build:` cua service api.
Sau do `docker compose pull api` va `docker compose up -d --no-build --wait`.
Giu `.env.docker` va volume MongoDB hien co; khong dung `down --volumes` cho du lieu that.

CD o bai nay la tu dong phat hanh image len Docker Hub. De tu dong cap nhat server/VM
can them dia chi may dich va co che trien khai rieng; workflow nay chua co buoc do.

## Tai lieu

- https://docs.docker.com/build/ci/github-actions/share-image-jobs/
- https://docs.docker.com/security/access-tokens/personal-access-tokens/
