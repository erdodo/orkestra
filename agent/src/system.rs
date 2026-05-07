use sysinfo::System;

pub struct SystemInfo {
    sys: System,
}

impl SystemInfo {
    pub fn new() -> Self {
        let mut sys = System::new_all();
        sys.refresh_all();
        Self { sys }
    }

    pub fn refresh(&mut self) {
        self.sys.refresh_cpu_usage();
        self.sys.refresh_memory();
    }

    pub fn cpu_usage(&self) -> f32 {
        let cpus = self.sys.cpus();
        if cpus.is_empty() {
            return 0.0;
        }
        let total: f32 = cpus.iter().map(|c| c.cpu_usage()).sum();
        total / cpus.len() as f32
    }

    pub fn ram_usage(&self) -> f32 {
        let total = self.sys.total_memory();
        if total == 0 {
            return 0.0;
        }
        let used = self.sys.used_memory();
        (used as f32 / total as f32) * 100.0
    }
}

pub fn get_hostname() -> String {
    hostname::get()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string()
}

pub fn get_platform() -> &'static str {
    if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else {
        "linux"
    }
}

pub fn get_local_ip() -> Option<String> {
    local_ip_address::local_ip()
        .ok()
        .map(|ip| ip.to_string())
}

pub fn check_vpn_active() -> bool {
    if let Ok(interfaces) = local_ip_address::list_afinet_netifas() {
        return interfaces.iter().any(|(name, _)| {
            name.starts_with("utun") || name.starts_with("ppp") || name.starts_with("tun")
        });
    }
    false
}

pub fn get_rustdesk_id() -> Option<String> {
    use std::process::{Command, Stdio};
    let out = Command::new("rustdesk")
        .arg("--get-id")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    let id = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if id.is_empty() { None } else { Some(id) }
}
