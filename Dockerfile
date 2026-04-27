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

# 1. 先安裝 binstall (很快)
RUN curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash

# 必須安裝 wasm target
RUN rustup target add wasm32-unknown-unknown

# 用 binstall 安裝 dx (直接下載二進制，不編譯)
# 安裝最新的 dioxus-cli (目前建議不指定版本，或指定最新 v0.6.3+)
# 這樣它內建的 wasm-bindgen 就能支援 0.2.100 以上
RUN cargo binstall dioxus-cli

# 編譯專案 (Fullstack 模式)
RUN dx build --release

# 在 Builder 階段就先把東西準備好，避免第二階段路徑混亂
# 動態抓取執行檔
RUN mkdir -p /app/ready_to_deploy && \
  cp -r /app/target/dx/dx-project/release/web/public /app/ready_to_deploy/public && \
  # 這裡改成：去 web 目錄下找那個沒有副檔名的執行檔 (可能是 server 或 dx-project)
  (cp /app/target/dx/dx-project/release/web/server /app/ready_to_deploy/server || \
  cp /app/target/dx/dx-project/release/web/dx-project /app/ready_to_deploy/server)

# --- 第二階段：執行環境 (改用 Ubuntu 確保 GLIBC 相容) ---
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
  ca-certificates \
  libssl3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 直接從準備好的資料夾拷貝，保證結構絕對是 /app/public 和 /app/server
COPY --from=builder /app/ready_to_deploy/ .

# 設定執行權限
RUN chmod +x ./server

# Hugging Face 規範
ENV IP=0.0.0.0
ENV PORT=7860
ENV DIOXUS_ASSET_DIR=/app/public
ENV DIOXUS_PUBLIC_DIR=/app/public
EXPOSE 7860

# 啟動伺服器
CMD ["./server"]

# docker build -t dx-project .
# docker run -e RABBITMQ_URL -p 7860:7860 dx-project