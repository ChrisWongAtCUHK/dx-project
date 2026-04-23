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

# 用 binstall 安裝 dx (直接下載二進制，不編譯)
# 安裝最新的 dioxus-cli (目前建議不指定版本，或指定最新 v0.6.3+)
# 這樣它內建的 wasm-bindgen 就能支援 0.2.100 以上
RUN cargo binstall dioxus-cli

# 編譯專案 (請確保使用了 --release 以優化效能)
RUN dx build --release --platform web

# --- 第二階段：執行環境 (改用 Ubuntu 確保 GLIBC 相容) ---
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
  ca-certificates \
  libssl3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 先拷貝整個 dist 目錄 (包含 index.html, wasm 等)
COPY --from=builder /app/dist ./dist

# 尋找並拷貝執行檔 (假設名稱為 dx-project，請根據實際情況修改)
COPY --from=builder /app/target/release/dx-project ./server

# 設定執行權限
RUN chmod +x ./server

# Hugging Face 規範
ENV IP=0.0.0.0
ENV PORT=7860
EXPOSE 7860

# 啟動伺服器
CMD ["./server"]
