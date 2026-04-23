# --- 第一階段：編譯環境 ---
FROM rust:1.81-slim AS builder

# 安裝編譯所需的系統套件
RUN apt-get update && apt-get install -y \
  curl \
  pkg-config \
  libssl-dev \
  git \
  && rm -rf /var/lib/apt/lists/*

# 安裝 Dioxus CLI (針對 Fullstack 編譯)
RUN curl -L https://github.com | tar xz -C /usr/local/bin

WORKDIR /app
COPY . .

# 執行 Dioxus Fullstack 編譯
# 這會生成：
# 1. target/release/render-dx-project (後端執行檔)
# 2. dist/ (前端 WASM 與 靜態資源)
RUN dx build --release --platform fullstack

# --- 第二階段：執行環境 ---
FROM debian:bookworm-slim

# 安裝執行時需要的基本套件 (如 OpenSSL)
RUN apt-get update && apt-get install -y \
  ca-certificates \
  libssl3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 從編譯階段拷貝成品
# 注意：請將 'render-dx-project' 換成你 Cargo.toml 裡的 binary 名稱
COPY --from=builder /app/target/release/render-dx-project ./server
COPY --from=builder /app/dist ./dist

# 修改這部分以符合 Hugging Face 規範
ENV IP=0.0.0.0
ENV PORT=7860

# 確保暴露正確的埠號
EXPOSE 7860

# 啟動伺服器
CMD ["./server"]
