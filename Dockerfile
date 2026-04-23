# --- 第一階段：編譯環境 (改用 Ubuntu 24.04 以支援新版 GLIBC) ---
FROM ubuntu:24.04 AS builder

WORKDIR /app
COPY . /app

# 安裝必要工具 (加入 unzip)
RUN apt-get update && apt-get install -y --no-install-recommends \
  curl build-essential ca-certificates pkg-config libssl-dev git unzip \
  && rm -rf /var/lib/apt/lists/*

# 安裝 Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# 【關鍵修正】使用腳本安裝 dx，避免 cargo install 編譯耗時
RUN curl -sSL https://raw.githubusercontent.com/dioxuslabs/cli/main/install.sh | bash

# 編譯專案 (請確保使用了 --release 以優化效能)
RUN dx build --release --platform web

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
