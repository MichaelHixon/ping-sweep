// ping-sweep (Rust) — concurrent host discovery across a /24.
//
// One thread per host driving the system pinger; live hosts flow back over an
// mpsc channel. std-only, so it builds with a bare `rustc` — no Cargo, no
// crates. Same contract as the rest of the repo:
//
//     rustc rust/ping-sweep.rs -o ping-sweep && ./ping-sweep 192.168.1.0/24
use std::env;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;

fn ip_key(ip: &str) -> u32 {
    ip.split('.').fold(0u32, |acc, o| acc * 256 + o.parse::<u32>().unwrap_or(0))
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: ping-sweep <network>   e.g. 192.168.1.0/24 or 192.168.1");
        std::process::exit(2);
    }
    let net = args[1].split('/').next().unwrap();
    let octets: Vec<&str> = net.split('.').collect();
    let valid = octets.len() >= 3
        && octets[..3].iter().all(|o| o.parse::<u16>().map_or(false, |n| n <= 255));
    if !valid {
        eprintln!("invalid network: {}", args[1]);
        std::process::exit(1);
    }
    let base = format!("{}.{}.{}", octets[0], octets[1], octets[2]);

    // macOS `ping -W` is milliseconds; Linux `-W` is seconds.
    let wait: Vec<&str> = if cfg!(target_os = "macos") {
        vec!["-W", "1000"]
    } else {
        vec!["-W", "1"]
    };

    let (tx, rx) = mpsc::channel();
    let mut handles = Vec::new();
    for h in 1..=254u16 {
        let ip = format!("{}.{}", base, h);
        let tx = tx.clone();
        let wait: Vec<String> = wait.iter().map(|s| s.to_string()).collect();
        handles.push(thread::spawn(move || {
            let ok = Command::new("ping")
                .arg("-c").arg("1")
                .args(&wait)
                .arg("--").arg(&ip)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if ok {
                let _ = tx.send(ip);
            }
        }));
    }
    drop(tx);
    for h in handles {
        let _ = h.join();
    }

    let mut up: Vec<String> = rx.iter().collect();
    up.sort_by_key(|ip| ip_key(ip));
    for ip in &up {
        println!("{}", ip);
    }
    let plural = if up.len() == 1 { "" } else { "s" };
    eprintln!("{} host{} up on {}.0/24", up.len(), plural, base);
}
