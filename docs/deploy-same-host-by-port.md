# Topology B: same-host-by-port

[← README](../README.md) ｜ 其他 topology：[A. separate-hosts](deploy-separate-hosts.md) ｜ [C. same-host-by-domain](deploy-same-host-by-domain.md)

三個環境**跑在同一台機器**，用**不同的 host port** 區分。

- **適合**：只有一台機器、想最快跑起來、能接受網址帶 port（`IP:3001`）
- **代價**：三環境同機，**沒有實體隔離**；網址會帶 port（`IP:3001`），較不簡潔
- **對外曝露**：`deploy/compose.same-host-by-port.yaml`（前端 `${HTTP_PORT}:80`，埠由 env 檔決定）

## Port map (defaults)

| 環境 | `HTTP_PORT`（在 `env/.env.*`） | 網址 |
|------|------------------------------|------|
| dev  | 3000 | `http://<host>:3000` |
| qas  | 3001 | `http://<host>:3001` |
| prod | 3002 | `http://<host>:3002` |

## Steps

### 1. Create your repo from this template

GitHub「Use this template」或 clone，改成你的 app。

### 2. Check each environment's port

`env/.env.dev|qas|prod` 各有一行 `HTTP_PORT`，三個**必須不同**（同機的埠不能重複）。預設 3000/3001/3002，如需更改在此調整。

### 3. Start all three environments (side by side)

```bash
make up-port-dev     # → http://<host>:3000
make up-port-qas     # → http://<host>:3001
make up-port-prod    # → http://<host>:3002
```

每個環境是**獨立的 compose project**（獨立 network/container），dev 的前端只連 dev 的後端，互不干擾。

### 4. Access

- **你自己**：`http://localhost:3000`（dev）/ `:3001` / `:3002`
- **團隊（同網路）**：`http://<你的機器IP>:3000` 等——topology B 不需要 domain/nip.io，直接 IP:port。
  - 查你的 IP：`ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"`

### 5. Stop (one environment, others unaffected)

```bash
make down-port-dev
make down-port-qas
make down-port-prod
```

## Changing ports

改 `env/.env.<env>` 的 `HTTP_PORT`（換一個沒被占用的），再重跑 `make up-port-<env>`。

## Troubleshooting

**`Bind for 0.0.0.0:<port> failed: port is already allocated`** — 該埠被占用：

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN     # 看什麼程式占用
docker ps --filter publish=<port>       # 或看是哪個 container
```

解法：改 `env/.env.*` 的 `HTTP_PORT` 換一個沒被占的埠，或停掉占用者（`docker stop <容器>`）。

> 三環境同機沒有故障/安全隔離——prod 若重要，改用 [A. separate-hosts](deploy-separate-hosts.md)。
