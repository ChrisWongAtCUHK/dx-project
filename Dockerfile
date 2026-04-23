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

# 2. 用 binstall 安裝 dx (直接下載二進制，不編譯)
# 安裝最新的 dioxus-cli (目前建議不指定版本，或指定最新 v0.6.3+)
# 這樣它內建的 wasm-bindgen 就能支援 0.2.100 以上
RUN cargo binstall dioxus-cli

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
COPY --from=builder /app/target/release/dx-project ./server
COPY --from=builder /app/dist ./dist

# 5. 設定執行權限
RUN chmod +x ./server

# 6. Hugging Face 規範
ENV IP=0.0.0.0
ENV PORT=7860
EXPOSE 7860

# 啟動伺服器
CMD ["./server"]
