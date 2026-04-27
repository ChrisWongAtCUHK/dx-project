#![allow(non_snake_case)]
use dioxus::prelude::*;
use gloo_storage::{LocalStorage, Storage};
use serde::{Deserialize, Serialize};
use std::env;

// 定義歷史紀錄的資料結構
#[derive(Clone, Serialize, Deserialize, PartialEq)]
struct MessageItem {
    content: String,
    time: String,
}

fn main() {
    launch(App);
}

#[component]
fn App() -> Element {
    let mut msg_status = use_signal(|| "等待發送...".to_string());
    let mut input_text = use_signal(|| "QuickTest".to_string());
    let mut is_loading = use_signal(|| false); // 這裡定義一個新的 state 來追蹤是否正在發送訊息
    let mut history = use_signal(|| Vec::<MessageItem>::new()); // 先初始化為空向量
    let mut is_dark = use_signal(|| false);

    // 💡 透過 eval 切換全域深色模式
    let toggle_dark = move |_| {
        let next = !is_dark();
        is_dark.set(next);
        let js = if next {
            "document.documentElement.classList.add('dark')"
        } else {
            "document.documentElement.classList.remove('dark')"
        };
        document::eval(js);
    };

    // 使用 use_effect 在組件掛載後（僅在瀏覽器端執行）讀取資料
    use_effect(move || {
        if let Ok(saved) = LocalStorage::get::<Vec<MessageItem>>("mq_history") {
            history.set(saved);
        }
    });

    let send_msg = move |_: ()| async move {
        // 在執行 await 之前，先將值取出，讓 read() 的借用立即結束
        let text = input_text.cloned();

        // 如果正在發送中或輸入框為空，則不執行
        if is_loading() || text.is_empty() {
            return;
        }

        // 開始發送：設定 loading 為 true，並更新狀態文字
        is_loading.set(true);
        msg_status.set("發送中...".to_string());

        // 先 Clone 一份複本給 RPC
        let rpc_content = text.clone();

        // 取得目前時間戳記
        let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string();

        // 傳入 timestamp 的克隆版本給 RPC
        // 2. 傳入 timestamp 的克隆版本給 RPC
        let rpc_res = send_mq_rpc(rpc_content, timestamp.clone()).await;

        match rpc_res {
            Ok(res) => {
                msg_status.set(res);
                input_text.set("".to_string()); // 發送成功後清空輸入框

                // 建立帶有時間戳記的物件
                let new_item = MessageItem {
                    content: text,
                    time: timestamp, // 使用傳入的時間戳記
                };

                let mut h = history.write(); // 發送成功，將訊息加入歷史清單的最前面
                h.insert(0, new_item);
                if h.len() > 5 {
                    h.pop();
                } // 只保留最近 5 筆
                  // 使用 cloned() 獲取資料複本進行存檔
                let _ = LocalStorage::set("mq_history", h.clone());
            }
            Err(e) => {
                // 失敗則保留輸入內容，僅更新狀態文字
                msg_status.set(format!("發送失敗: {}", e));
            }
        }

        // 結束發送：無論成功或失敗，都要把 loading 設回 false
        is_loading.set(false);
    };

    // 💡 將 JS 配置移出 rsx! 宏，徹底避開解析錯誤
    const TW_CONFIG: &str = "window.tailwind = { config: { darkMode: 'class', safelist: ['dark', 'bg-slate-900', 'border-slate-800'] } };";

    rsx! {
        document::Script { src: "https://cdn.tailwindcss.com" }
        // 透過 Script 注入 Dark Mode 配置 (使用雙大括號轉義)
        // 2. 注入配置 (透過變數插值)
        document::Script { dangerous_inner_html: "{TW_CONFIG}" }

        // 3. 補丁 CSS (注意 Dioxus 0.6 的 style 標籤寫法)
        style {
            r#"
            .dark .custom-history-card {{ 
                background-color: #0f172a !important; 
                border-color: #1e293b !important;
            }}
            .dark .custom-history-card h2 {{ color: #94a3b8 !important; }}
            "#
        }
        div {
            // 💡 增加 transition-colors 讓切換更平滑
            class: "min-h-screen w-full bg-gray-100 dark:bg-slate-950 flex flex-col items-center justify-center p-6 transition-colors duration-500",

            // 🌙 深色模式切換按鈕
            div { class: "absolute top-6 right-6",
                button {
                    class: "p-3 rounded-full bg-white dark:bg-slate-800 shadow-lg hover:scale-110 transition-all",
                    onclick: toggle_dark,
                    if is_dark() { "🌙" } else { "☀️" }
                }
            }

            // 主控制台卡片
            div {
                class: "w-full max-w-md bg-white dark:bg-slate-900 rounded-2xl shadow-xl p-8 space-y-6 border dark:border-slate-800",
                h1 { class: "text-2xl font-bold text-gray-800 dark:text-white text-center", "RabbitMQ 控制台" }

                div { class: "space-y-2",
                    label { class: "text-sm font-medium text-gray-600 dark:text-gray-400", "訊息內容" }
                    input {
                        class: "w-full px-4 py-2 border border-gray-300 dark:border-slate-700 rounded-lg bg-white dark:bg-slate-800 text-gray-900 dark:text-white focus:ring-2 focus:ring-blue-500 outline-none transition-all",
                        placeholder: "輸入訊息...",
                        value: "{input_text}",
                        oninput: move |evt| input_text.set(evt.value()),
                        onkeydown: move |evt| {
                            if evt.key() == Key::Enter {
                                // 鍵盤事件需要手動 spawn
                                spawn(send_msg(()));
                            }
                        }
                    }
                }

                button {
                    class: format!(
                        "w-full py-3 rounded-lg font-semibold text-white transition-all {} ",
                        if is_loading() { "bg-gray-400" } else { "bg-blue-600 hover:bg-blue-700 shadow-lg shadow-blue-500/30" }
                    ),
                    disabled: is_loading(), // 根據 is_loading 禁用按鈕
                    onclick: move |_| async move {
                        send_msg(()).await;
                    },
                    if is_loading() { "處理中..." } else { "發送訊息" }
                }

                // 狀態顯示
                div {
                    class: format!(
                        "p-4 rounded-xl text-sm font-medium border transition-all {}",
                        if is_dark() { "bg-slate-800/50 border-slate-700" } else { "bg-blue-50 border-blue-100" }
                    ),
                    span { class: "text-blue-600 dark:text-blue-400", "{msg_status}" }
                }
            }
            // 歷史紀錄卡片放在外面，與主卡片同級
            // 歷史紀錄顯示部分
            if !history.read().is_empty() {
                div {
                    // 💡 加上 custom-history-card class 來對應上面的 CSS 補丁
                    class: format!(
                        "w-full max-w-md bg-white rounded-xl shadow-md p-6 animate-fade-in flex-none border custom-history-card {}",
                        if is_dark() { "dark" } else { "" }
                    ),

                    h2 {
                        class: "text-sm font-bold text-gray-500 uppercase tracking-wider mb-4",
                        "最近發送紀錄"
                    }
                    ul {
                        class: "divide-y divide-gray-100 dark:divide-slate-800",
                        for (i, item) in history.read().iter().enumerate() {
                            li { key: "{i}", class: "py-3 flex flex-col gap-1",
                                div { class: "flex items-center justify-between",
                                    span { class: "text-gray-800 dark:text-gray-100 font-medium break-words", "{item.content}" }
                                    span {
                                        class: "shrink-0 text-[10px] bg-green-100 dark:bg-green-900/30 text-green-600 dark:text-green-400 px-2 py-0.5 rounded",
                                        "成功"
                                    }
                                }
                                // 顯示時間戳記
                                span { class: "text-[10px] text-gray-400 dark:text-gray-500 font-mono", "🕒 {item.time}" }
                            }
                        }
                    }
                }
            }
        }
    }
}

#[server]
async fn send_mq_rpc(msg: String, timestamp: String) -> Result<String, ServerFnError> {
    let client = reqwest::Client::new();

    // read from .env or use default
    let rabbitmq_url = format!(
        "{}/rabbitmq/sendTopic",
        env::var("RABBITMQ_URL").unwrap_or("/rabbitmq".to_string())
    );

    // 建立查詢參數
    // 對應 curl 中的 ?routingKey=hk.news&name=Chris&msg=...
    let params = [("routingKey", "hk.news"), ("name", "Chris"), ("msg", &msg)];

    let response = client
        .get(rabbitmq_url)
        .query(&params) // reqwest 會自動處理 URL 編碼 (URL Encoding)
        // --- 加入自訂 Header ---
        .header("X-Send-Time", &timestamp)
        .header("X-Client-Source", "Dioxus-Web")
        .send()
        .await
        .map_err(|e| {
            // 處理連線層級的錯誤（例如：伺服器沒開、網址打錯）
            if e.is_connect() {
                ServerFnError::new("無法連線至 Spring Boot 伺服器，請檢查後端是否啟動。")
            } else if e.is_timeout() {
                ServerFnError::new("伺服器回應超時。")
            } else {
                ServerFnError::new(format!("網路請求異常: {}", e))
            }
        })?;

    match response.status() {
        s if s.is_success() => Ok(format!(
            "成功！伺服器回應: {}",
            response.text().await.unwrap_or_default()
        )),
        reqwest::StatusCode::NOT_FOUND => Err(ServerFnError::new(format!(
            "找不到該 API 路徑 (404)，請檢查 Spring Boot 路由是否正確: {}",
            response.url()
        ))),
        reqwest::StatusCode::INTERNAL_SERVER_ERROR => Err(ServerFnError::new(
            "Spring Boot 內部錯誤 (500)，可能是 RabbitMQ 連線失敗。",
        )),
        other => Err(ServerFnError::new(format!(
            "伺服器回傳未預期狀態: {}",
            other
        ))),
    }
}
