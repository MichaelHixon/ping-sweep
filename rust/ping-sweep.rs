// ping-sweep (Rust) — concurrent host discovery across a /24.
//
// One thread per host driving the system pinger; live host numbers flow back
// over an mpsc channel. std-only, so it builds with a bare `rustc` — no Cargo,
// no crates. Same contract as the rest of the repo:
//
//     rustc rust/ping-sweep.rs -o ping-sweep && ./ping-sweep 192.168.1.0/24
use std::env;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: ping-sweep <network>   e.g. 192.168.1.0/24 or 192.168.1");
        std::process::exit(2);
    }
    let net = args[1].split('/').next().unwrap();
    let octets: Vec<&str> = net.split('.').collect();
    let valid = octets.len() >= 3
        && octets[..3].iter().all(|o| o.parse::<u16>().is_ok_and(|n| n <= 255));
    if !valid {
        eprintln!("invalid network: {}", args[1]);
        std::process::exit(1);
    }
    let base = format!("{}.{}.{}", octets[0], octets[1], octets[2]);

    // macOS `ping -W` is milliseconds; Linux `-W` is seconds.
    let wait: &'static [&'static str] = if cfg!(target_os = "macos") {
        &["-W", "1000"]
    } else {
        &["-W", "1"]
    };

    let (tx, rx) = mpsc::channel();
    for h in 1..=254u16 {
        let ip = format!("{}.{}", base, h);
        let tx = tx.clone();
        thread::spawn(move || {
            let ok = Command::new("ping")
                .arg("-c").arg("1")
                .args(wait)
                .arg("--").arg(&ip)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if ok {
                let _ = tx.send(h);
            }
        });
    }
    // rx.iter() ends once every sender is dropped, i.e. once every thread has finished
    drop(tx);

    // every host shares `base`, so the host number alone orders the output
    let mut up: Vec<u16> = rx.iter().collect();
    up.sort();
    for h in &up {
        println!("{}.{}", base, h);
    }
    let plural = if up.len() == 1 { "" } else { "s" };
    eprintln!("{} host{} up on {}.0/24", up.len(), plural, base);
}
