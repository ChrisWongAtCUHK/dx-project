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

# 編譯專案 (Fullstack 模式)
RUN dx build --release

# --- 第二階段：執行環境 (改用 Ubuntu 確保 GLIBC 相容) ---
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
  ca-certificates \
  libssl3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 靜態資源（Wasm/JS/Assets）在這個路徑
COPY --from=builder /app/target/dx/dx-project/release/web/public ./dist

# Server 執行檔在它的上一層目錄
# Dioxus 0.6 會將執行檔命名為與專案同名 (dx-project) 或 server
COPY --from=builder /app/target/dx/dx-project/release/web/dx-project ./server

# 自動搜尋執行檔並改名為 server
# Dioxus 0.6 可能會把執行檔放在 target/dx/.../release/ 下
RUN --mount=type=bind,from=builder,source=/app/target,target=/temp_target \
  find /temp_target -type f -name "dx-project" -exec cp {} ./server \; || \
  find /temp_target -type f -name "server" -exec cp {} ./server \;

# 設定執行權限
RUN chmod +x ./server

# Hugging Face 規範
ENV IP=0.0.0.0
ENV PORT=7860
ENV DIOXUS_ASSET_DIR=/app/dist
EXPOSE 7860

# 啟動伺服器
CMD ["./server"]
