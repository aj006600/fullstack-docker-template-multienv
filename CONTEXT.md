# fullstack-docker-template-multienv

多環境容器範本的共用詞彙。這個 repo 有幾個詞天生一詞多義（尤其 `dev`），這份表是唯一定義處——
其他文檔只連過來，不重述定義。

## Language

### Environment and configuration

**Environment**:
dev / qas / prod 三者之一。「是哪個環境」= 載入了哪份 `env/.env.<env>`，不是哪顆 image。
由 `ENV` 參數選定。
_Avoid_: 階段、stage（`stage` 專指 Dockerfile 的建置階段）

**APP_ENV**:
寫在 `env/.env.*` 裡的變數，值等於該檔對應的 environment。compose 用它解析要載入哪份 env 檔。

**dev**:
依上下文有三個意思，不可混用——
`ENV=dev` 是 **environment**；`make dev` 是**本機開發指令**；Dockerfile 的 `dev` 是 **stage**。
提到後兩者時一律寫全（`make dev` / dev stage），不要單寫 dev。

**stage**:
Dockerfile 的建置階段（`base` / `dev` / `runtime`）。決定 image **內容**，與 environment 無關。
runtime stage 出貨、非 root；dev stage 含 pytest 與 ruff，只給本機用，永不部署。

### Deployment

**Deployment**:
在某台主機上讓某個 environment 跑起來。`make up` 與 `make deploy` **都是** deployment，
差別只在 image provenance。
_Avoid_: preview（本 repo 不使用此詞——它曾被用來暗示 `make up` 比較次等，但兩者都是真的部署）

**Image provenance**:
這次 deployment 的 image 從哪來。只有兩個值：**build**（`make up`，用本機當前 code 現場建）
與 **registry**（`make deploy`，拉 CI 測過的不可變映像）。

**Topology**:
這個 environment 怎麼對外曝露。三選一：`separate-hosts`（獨佔主機、綁 80）、
`same-host-by-port`（同機不同埠）、`same-host-by-domain`（同機、Traefik 依 domain）。
由 `MODE` 參數選定，對應 `deploy/compose.<mode>.yaml`。
_Avoid_: mode（`MODE` 是參數名，敘述時用 topology）、部署方式

**Promotion**:
把**同一顆**已測過的 image 往下一個 environment 送，不重新 build。
本 repo 用 tag 層級的 promotion：`:sha` 給 dev/qas，發版時重新標籤成 `:vX.Y.Z` 給 prod。
_Avoid_: 重新部署、rebuild

### Images and versions

**`:sha`**:
以 git commit SHA 為標籤的映像，由 CI 在每個 main commit 上建立。這是版本的**真相來源**——
promotion、rollback、稽核都靠它。慣例上不可變。

**latest**:
本 repo 的 registry 上**不存在** `latest`。CI 只推 `:sha` 與 `:vX.Y.Z`。
`compose.yaml` 的 `${TAG:-latest}` 是 Docker 對本機 build 的預設標籤，與 registry 無關。

**IMAGE / TAG**:
`make deploy` 的兩個必填參數，決定要拉哪顆映像。environment 不「知道」自己該跑哪一版——
版本永遠是傳入的，由 promotion 流程或人工 rollback 決定。
