use std::net::{SocketAddr, TcpStream};
use std::sync::mpsc::{channel, Receiver};
use std::thread;
use std::time::Duration;
use serde_json::Value;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct DiscoveredBox {
    pub ip: String,
    pub port: u16,
    pub brand: String,
    pub model: String,
    pub boxtype: String,
}

pub struct NetworkScanner;

impl NetworkScanner {
    pub fn start_scan(subnet_prefix: String) -> Receiver<DiscoveredBox> {
        let (tx, rx) = channel();

        thread::spawn(move || {
            let mut handles = Vec::new();
            for i in 1..=120 {
                let ip = format!("{}{}", subnet_prefix, i);
                let tx = tx.clone();
                let handle = thread::spawn(move || {
                    let addr_str = format!("{}:80", ip);
                    if let Ok(addr) = addr_str.parse::<SocketAddr>() {
                        if let Ok(stream) = TcpStream::connect_timeout(&addr, Duration::from_millis(250)) {
                            drop(stream);
                            // Query /api/about
                            let agent = ureq::AgentBuilder::new()
                                .timeout(Duration::from_millis(800))
                                .build();
                            if let Ok(resp) = agent.get(&format!("http://{}/api/about", ip)).call() {
                                if let Ok(val) = resp.into_json::<Value>() {
                                    let info = val.get("info").unwrap_or(&val);
                                    let brand = info.get("brand").and_then(|v| v.as_str()).unwrap_or("Enigma2").to_string();
                                    let model = info.get("model").and_then(|v| v.as_str()).unwrap_or("Vu+").to_string();
                                    let boxtype = info.get("boxtype").and_then(|v| v.as_str()).unwrap_or("").to_string();

                                    let _ = tx.send(DiscoveredBox {
                                        ip,
                                        port: 80,
                                        brand,
                                        model,
                                        boxtype,
                                    });
                                }
                            }
                        }
                    }
                });
                handles.push(handle);
            }

            for h in handles {
                let _ = h.join();
            }
        });

        rx
    }
}
