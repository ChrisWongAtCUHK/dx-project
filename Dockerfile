# --- 第一階段：編譯環境 (改用 Ubuntu 24.04 以支援新版 GLIBC) ---
FROM ubuntu:24.04 AS builder

# 1. 安裝系統依賴
RUN apt-get update && apt-get install -y --no-install-recommends \
  curl build-essential ca-certificates gnupg dirmngr \
  pkg-config \
  libssl-dev \
  git \
  && rm -rf /var/lib/apt/lists/* \
  && curl https://sh.rustup.rs -sSf | sh -s -- -y \
  && . "$HOME/.cargo/env" \
  && cargo install --locked dioxus-cli@0.6.0

WORKDIR /app
COPY . .

# 3. 執行編譯 (這會產生 target/release/render-dx-project 和 dist/ 目錄)
RUN dx build --release --platform fullstack

# --- 第二階段：執行環境 ---
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
  ca-certificates \
  libssl3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 4. 重要修正：移除第二階段的 dx build
# 執行環境沒有 Rust 和 dx 指令，必須從 builder 階段拷貝成品
COPY --from=builder /app/target/release/render-dx-project ./server
COPY --from=builder /app/dist ./dist

# 5. 設定執行權限
RUN chmod +x ./server

# 6. Hugging Face 規範
ENV IP=0.0.0.0
ENV PORT=7860
EXPOSE 7860

# 啟動伺服器
CMD ["./server"]
