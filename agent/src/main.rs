mod commands;
mod config;
mod system;

use clap::Parser;
use config::Config;
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::sync::Arc;
use std::time::Duration;
use system::{SystemInfo, check_vpn_active, get_hostname, get_local_ip, get_platform, get_rustdesk_id};
use tokio::sync::{mpsc, Mutex};
use tokio::time::{interval, sleep};
use tokio_tungstenite::{connect_async, tungstenite::protocol::Message};
use tracing::{error, info, warn};
#[allow(unused_imports)]
use url as _;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter("agent=info,warn")
        .init();

    let config = Config::parse();
    info!("Orkestra Agent başlatılıyor...");
    info!("Sunucu: {}", config.server_url);

    let mut reconnect_delay = config.reconnect_delay;

    loop {
        match run_agent(&config).await {
            Ok(_) => {
                info!("Agent oturumu kapandı, yeniden bağlanılıyor...");
            }
            Err(e) => {
                error!("Bağlantı hatası: {}", e);
                warn!("{}s sonra yeniden denenecek...", reconnect_delay);
                sleep(Duration::from_secs(reconnect_delay)).await;
                reconnect_delay = (reconnect_delay * 2).min(config.max_reconnect_delay);
                continue;
            }
        }
        reconnect_delay = config.reconnect_delay;
        sleep(Duration::from_secs(reconnect_delay)).await;
    }
}

async fn run_agent(config: &Config) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let url = config.server_url.clone();
    info!("Bağlanılıyor: {}", url);

    let (ws_stream, _) = connect_async(&url).await?;
    info!("WebSocket bağlantısı kuruldu");

    let (write, mut read) = ws_stream.split();
    let write = Arc::new(Mutex::new(write));

    let hostname = get_hostname();
    let platform = get_platform();
    let local_ip = get_local_ip();

    let register_msg = json!({
        "type": "REGISTER",
        "hostname": hostname,
        "platform": platform,
        "local_ip": local_ip,
        "api_key": config.api_key
    });

    {
        let mut w = write.lock().await;
        w.send(Message::Text(register_msg.to_string().into())).await?;
    }
    info!("Kayıt mesajı gönderildi: {} ({})", hostname, platform);

    let device_id: Arc<Mutex<String>> = Arc::new(Mutex::new(String::new()));
    let device_id_clone = device_id.clone();

    let write_heartbeat = write.clone();
    let heartbeat_interval_secs = config.heartbeat_interval;
    let heartbeat_device_id = device_id.clone();

    let rustdesk_id = tokio::time::timeout(
        Duration::from_secs(3),
        tokio::task::spawn_blocking(get_rustdesk_id),
    )
    .await
    .ok()
    .and_then(|r| r.ok())
    .flatten();
    let hostname_hb = hostname.clone();

    tokio::spawn(async move {
        let mut sys = SystemInfo::new();
        let mut ticker = interval(Duration::from_secs(heartbeat_interval_secs));
        loop {
            ticker.tick().await;
            sys.refresh();
            let cpu = sys.cpu_usage();
            let ram = sys.ram_usage();
            let vpn = check_vpn_active();

            let id = heartbeat_device_id.lock().await.clone();
            if id.is_empty() {
                continue;
            }

            let hb = json!({
                "type": "HEARTBEAT",
                "hostname": hostname_hb,
                "device_id": id,
                "cpu": cpu,
                "ram": ram,
                "vpn_active": vpn,
                "rustdesk_id": rustdesk_id
            });

            let mut w = write_heartbeat.lock().await;
            if let Err(e) = w.send(Message::Text(hb.to_string().into())).await {
                error!("Heartbeat gönderilemedi: {}", e);
                break;
            }
        }
    });

    let (extra_tx, mut extra_rx) = mpsc::channel::<serde_json::Value>(32);

    let write_extra = write.clone();
    tokio::spawn(async move {
        while let Some(msg) = extra_rx.recv().await {
            let mut w = write_extra.lock().await;
            if let Err(e) = w.send(Message::Text(msg.to_string().into())).await {
                error!("Extra mesaj gönderilemedi: {}", e);
            }
        }
    });

    while let Some(msg) = read.next().await {
        let msg = match msg {
            Ok(m) => m,
            Err(e) => {
                error!("Mesaj alınamadı: {}", e);
                break;
            }
        };

        match msg {
            Message::Text(text) => {
                let value: serde_json::Value = match serde_json::from_str(&text) {
                    Ok(v) => v,
                    Err(_) => continue,
                };

                let msg_type = value.get("type").and_then(|v| v.as_str()).unwrap_or("");

                match msg_type {
                    "REGISTERED" => {
                        let id = value.get("device_id").and_then(|v| v.as_str()).unwrap_or("");
                        *device_id_clone.lock().await = id.to_string();
                        info!("Kayıt onaylandı. Device ID: {}", id);
                    }
                    _ => {
                        let current_id = device_id_clone.lock().await.clone();
                        if let Some(response) = commands::handle_command(&value, &current_id, extra_tx.clone()).await {
                            let mut w = write.lock().await;
                            if let Err(e) = w.send(Message::Text(response.to_string().into())).await {
                                error!("Yanıt gönderilemedi: {}", e);
                            }
                        }
                    }
                }
            }
            Message::Ping(data) => {
                let mut w = write.lock().await;
                let _ = w.send(Message::Pong(data)).await;
            }
            Message::Close(_) => {
                info!("Sunucu bağlantıyı kapattı");
                break;
            }
            _ => {}
        }
    }

    Ok(())
}
