use serde_json::{json, Value};
use std::process::Stdio;
use tokio::process::Command;
use tokio::sync::mpsc;
use tracing::{error, info};

pub async fn handle_command(msg: &Value, device_id: &str, extra_tx: mpsc::Sender<Value>) -> Option<Value> {
    let cmd = msg.get("cmd")?.as_str()?;
    info!("Komut alındı: {}", cmd);

    match cmd {
        "EXEC" => {
            let payload = msg.get("payload").and_then(|v| v.as_str()).unwrap_or("");
            exec_shell(payload, device_id).await
        }
        "PING" => Some(json!({
            "type": "CMD_RESULT",
            "device_id": device_id,
            "cmd": "PING",
            "stdout": "pong",
            "exit_code": 0
        })),
        "STATUS" => {
            let info = system_status();
            Some(json!({
                "type": "CMD_RESULT",
                "device_id": device_id,
                "cmd": "STATUS",
                "stdout": info,
                "exit_code": 0
            }))
        }
        "KILL_PROCESS" => {
            let name = msg.get("payload").and_then(|v| v.as_str()).unwrap_or("");
            kill_process(name, device_id).await
        }
        "PROXY_START" => {
            start_gost_proxy(device_id).await
        }
        "SET_PROXY" => {
            let host = msg.get("proxy_host").and_then(|v| v.as_str()).unwrap_or("127.0.0.1");
            let port = msg.get("proxy_port").and_then(|v| v.as_u64()).unwrap_or(1080);
            let proxy_type = msg.get("proxy_type").and_then(|v| v.as_str()).unwrap_or("socks5");
            set_system_proxy(host, port as u16, proxy_type, device_id).await
        }
        "CLEAR_PROXY" => {
            clear_system_proxy(device_id).await
        }
        "SYNC_INIT" => {
            let job_id = msg.get("job_id").and_then(|v| v.as_str()).unwrap_or("");
            let source_path = msg.get("source_path").and_then(|v| v.as_str()).unwrap_or("");
            let target_path = msg.get("target_path").and_then(|v| v.as_str()).unwrap_or("");
            let peer_hostname = msg.get("peer_hostname").and_then(|v| v.as_str()).unwrap_or("");
            let peer_ip = msg.get("peer_ip").and_then(|v| v.as_str());
            sync_init(job_id, source_path, target_path, peer_hostname, peer_ip, device_id).await
        }
        "SYNC_STOP" => {
            let job_id = msg.get("job_id").and_then(|v| v.as_str()).unwrap_or("");
            sync_stop(job_id, device_id).await
        }
        "VSCODE_TUNNEL_START" => {
            vscode_tunnel_start(device_id, extra_tx).await
        }
        "VSCODE_TUNNEL_STOP" => {
            vscode_tunnel_stop(device_id).await
        }
        "AUDIO_START" => {
            let role = msg.get("role").and_then(|v| v.as_str()).unwrap_or("sender");
            let peer_id = msg.get("peer_device_id").and_then(|v| v.as_str()).unwrap_or("");
            audio_start(role, peer_id, device_id).await
        }
        "AUDIO_STOP" => {
            audio_stop(device_id).await
        }
        _ => {
            error!("Bilinmeyen komut: {}", cmd);
            None
        }
    }
}

async fn exec_shell(payload: &str, device_id: &str) -> Option<Value> {
    let (shell, flag) = if cfg!(target_os = "windows") {
        ("cmd", "/C")
    } else {
        ("sh", "-c")
    };

    let output = Command::new(shell)
        .arg(flag)
        .arg(payload)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await;

    match output {
        Ok(out) => Some(json!({
            "type": "CMD_RESULT",
            "device_id": device_id,
            "cmd": payload,
            "stdout": String::from_utf8_lossy(&out.stdout).trim().to_string(),
            "stderr": String::from_utf8_lossy(&out.stderr).trim().to_string(),
            "exit_code": out.status.code().unwrap_or(-1)
        })),
        Err(e) => Some(json!({
            "type": "CMD_RESULT",
            "device_id": device_id,
            "cmd": payload,
            "stderr": e.to_string(),
            "exit_code": -1
        })),
    }
}

fn system_status() -> String {
    let sys = sysinfo::System::new_all();
    let procs: Vec<String> = sys
        .processes()
        .iter()
        .take(10)
        .map(|(pid, p)| format!("{}: {} ({:.1}%)", pid, p.name().to_string_lossy(), p.cpu_usage()))
        .collect();
    procs.join("\n")
}

async fn kill_process(name: &str, device_id: &str) -> Option<Value> {
    let (shell, flag, cmd) = if cfg!(target_os = "windows") {
        ("cmd", "/C", format!("taskkill /F /IM {}", name))
    } else {
        ("sh", "-c", format!("pkill -f {}", name))
    };

    let output = Command::new(shell)
        .arg(flag)
        .arg(&cmd)
        .output()
        .await;

    match output {
        Ok(out) => Some(json!({
            "type": "CMD_RESULT",
            "device_id": device_id,
            "cmd": format!("kill {}", name),
            "exit_code": out.status.code().unwrap_or(-1)
        })),
        Err(e) => Some(json!({
            "type": "CMD_RESULT",
            "device_id": device_id,
            "cmd": format!("kill {}", name),
            "stderr": e.to_string(),
            "exit_code": -1
        })),
    }
}

async fn start_gost_proxy(device_id: &str) -> Option<Value> {
    let result = Command::new("gost")
        .args(["-L", "socks5://:1080"])
        .spawn();

    match result {
        Ok(_) => Some(json!({
            "type": "VPN_STATUS",
            "device_id": device_id,
            "connected": true,
            "proxy_port": 1080
        })),
        Err(e) => Some(json!({
            "type": "CMD_RESULT",
            "device_id": device_id,
            "cmd": "PROXY_START",
            "stderr": format!("gost başlatılamadı: {}", e),
            "exit_code": -1
        })),
    }
}

async fn set_system_proxy(host: &str, port: u16, proxy_type: &str, device_id: &str) -> Option<Value> {
    #[cfg(target_os = "macos")]
    {
        let service = "Wi-Fi";
        let cmd = match proxy_type {
            "socks5" => format!(
                "networksetup -setsocksproxy {} {} {} on",
                service, host, port
            ),
            _ => format!(
                "networksetup -setwebproxy {} {} {} on && networksetup -setsecurewebproxy {} {} {} on",
                service, host, port, service, host, port
            ),
        };
        return exec_shell(&cmd, device_id).await;
    }

    #[cfg(target_os = "windows")]
    {
        use winreg::enums::*;
        use winreg::RegKey;
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let path = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
        if let Ok(key) = hkcu.open_subkey_with_flags(path, KEY_WRITE) {
            let proxy_str = format!("{}://{}:{}", proxy_type, host, port);
            let _ = key.set_value("ProxyServer", &proxy_str);
            let _ = key.set_value("ProxyEnable", &1u32);
        }
        return Some(json!({
            "type": "CMD_RESULT",
            "device_id": device_id,
            "cmd": "SET_PROXY",
            "stdout": format!("Proxy ayarlandı: {}:{}", host, port),
            "exit_code": 0
        }));
    }

    #[allow(unreachable_code)]
    Some(json!({
        "type": "CMD_RESULT",
        "device_id": device_id,
        "cmd": "SET_PROXY",
        "stderr": "Bu platform desteklenmiyor",
        "exit_code": 1
    }))
}

async fn clear_system_proxy(device_id: &str) -> Option<Value> {
    #[cfg(target_os = "macos")]
    {
        let cmd = "networksetup -setsocksproxy Wi-Fi '' 0 off && networksetup -setwebproxy Wi-Fi '' 0 off";
        return exec_shell(cmd, device_id).await;
    }

    #[cfg(target_os = "windows")]
    {
        use winreg::enums::*;
        use winreg::RegKey;
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let path = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
        if let Ok(key) = hkcu.open_subkey_with_flags(path, KEY_WRITE) {
            let _ = key.set_value("ProxyEnable", &0u32);
        }
        return Some(json!({
            "type": "CMD_RESULT",
            "device_id": device_id,
            "cmd": "CLEAR_PROXY",
            "stdout": "Proxy temizlendi",
            "exit_code": 0
        }));
    }

    #[allow(unreachable_code)]
    Some(json!({
        "type": "CMD_RESULT",
        "device_id": device_id,
        "cmd": "CLEAR_PROXY",
        "stderr": "Bu platform desteklenmiyor",
        "exit_code": 1
    }))
}

async fn sync_init(
    job_id: &str,
    source_path: &str,
    target_path: &str,
    peer_hostname: &str,
    peer_ip: Option<&str>,
    device_id: &str,
) -> Option<Value> {
    let peer = peer_ip.unwrap_or(peer_hostname);
    let remote = format!("{}:{}", peer, target_path);

    let ignore_args = [
        "--ignore=node_modules/",
        "--ignore=dist/",
        "--ignore=.git/",
        "--ignore=*.log",
        "--ignore=target/",
        "--ignore=.next/",
    ];

    let mut args = vec![
        "sync".to_string(),
        "create".to_string(),
        "--name".to_string(),
        job_id.to_string(),
        "--sync-mode".to_string(),
        "two-way-safe".to_string(),
    ];

    for ignore in &ignore_args {
        args.push(ignore.to_string());
    }

    args.push(source_path.to_string());
    args.push(remote);

    let output = Command::new("mutagen")
        .args(&args)
        .output()
        .await;

    match output {
        Ok(out) => Some(json!({
            "type": "SYNC_STATUS",
            "device_id": device_id,
            "job_id": job_id,
            "status": if out.status.success() { "syncing" } else { "error" },
            "stdout": String::from_utf8_lossy(&out.stdout).trim().to_string(),
            "stderr": String::from_utf8_lossy(&out.stderr).trim().to_string(),
        })),
        Err(e) => Some(json!({
            "type": "SYNC_STATUS",
            "device_id": device_id,
            "job_id": job_id,
            "status": "error",
            "stderr": e.to_string()
        })),
    }
}

async fn sync_stop(job_id: &str, device_id: &str) -> Option<Value> {
    let output = Command::new("mutagen")
        .args(["sync", "terminate", job_id])
        .output()
        .await;

    match output {
        Ok(_) => Some(json!({
            "type": "SYNC_STATUS",
            "device_id": device_id,
            "job_id": job_id,
            "status": "stopped"
        })),
        Err(e) => Some(json!({
            "type": "SYNC_STATUS",
            "device_id": device_id,
            "job_id": job_id,
            "status": "error",
            "stderr": e.to_string()
        })),
    }
}

async fn vscode_tunnel_start(device_id: &str, tx: mpsc::Sender<Value>) -> Option<Value> {
    let device_id_owned = device_id.to_string();

    tokio::spawn(async move {
        let child = Command::new("code")
            .args(["tunnel", "--accept-server-license-terms", "--no-sleep"])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();

        if let Ok(mut child) = child {
            use tokio::io::{AsyncBufReadExt, BufReader};
            if let Some(stdout) = child.stdout.take() {
                let mut reader = BufReader::new(stdout).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    if let Some(start) = line.find("https://vscode.dev/tunnel") {
                        let url = line[start..].split_whitespace().next().unwrap_or("").to_string();
                        info!("VS Code Tunnel URL: {}", url);
                        let msg = json!({
                            "type": "TUNNEL_URL",
                            "device_id": device_id_owned,
                            "url": url
                        });
                        let _ = tx.send(msg).await;
                        break;
                    }
                }
            }
        }
    });

    Some(json!({
        "type": "CMD_RESULT",
        "device_id": device_id,
        "cmd": "VSCODE_TUNNEL_START",
        "stdout": "VS Code Tunnel başlatılıyor...",
        "exit_code": 0
    }))
}

async fn vscode_tunnel_stop(device_id: &str) -> Option<Value> {
    exec_shell("pkill -f 'code tunnel'", device_id).await
}

async fn audio_start(role: &str, _peer_id: &str, device_id: &str) -> Option<Value> {
    Some(json!({
        "type": "AUDIO_STATUS",
        "device_id": device_id,
        "status": "starting",
        "role": role
    }))
}

async fn audio_stop(device_id: &str) -> Option<Value> {
    Some(json!({
        "type": "AUDIO_STATUS",
        "device_id": device_id,
        "status": "stopped"
    }))
}
