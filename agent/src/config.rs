use clap::Parser;

#[derive(Parser, Debug, Clone)]
#[command(name = "orkestra-agent", about = "Orkestra Cihaz Ajanı")]
pub struct Config {
    #[arg(long, env = "ORKESTRA_SERVER", default_value = "ws://192.168.1.50:3081/agent")]
    pub server_url: String,

    #[arg(long, env = "ORKESTRA_API_KEY", default_value = "")]
    pub api_key: String,

    #[arg(long, default_value = "5")]
    pub heartbeat_interval: u64,

    #[arg(long, default_value = "3")]
    pub reconnect_delay: u64,

    #[arg(long, default_value = "30")]
    pub max_reconnect_delay: u64,
}
