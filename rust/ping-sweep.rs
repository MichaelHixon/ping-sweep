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
    // args_os: env::args() panics on an argument that isn't valid UTF-8
    let Some(raw) = env::args_os().nth(1) else {
        eprintln!("usage: ping-sweep <network>   e.g. 192.168.1.0/24 or 192.168.1");
        std::process::exit(2);
    };
    let arg = raw.to_string_lossy();   // non-UTF-8 bytes become U+FFFD, which fails validation
    let net = arg.split('/').next().unwrap();
    // 1–3 ASCII digits (parse alone would also accept "+1" and "0010"), and u8 does
    // the 0–255 range check; a bad or missing octet leaves fewer than 3
    let nums: Vec<u8> = net
        .split('.')
        .take(3)
        .filter(|o| o.len() <= 3 && o.bytes().all(|b| b.is_ascii_digit()))
        .filter_map(|o| o.parse().ok())
        .collect();
    if nums.len() < 3 {
        eprintln!("invalid network: {}", arg);
        std::process::exit(1);
    }
    // rebuild from the numeric values: `ping` would read a leading-zero "010" as octal 8
    let base = format!("{}.{}.{}", nums[0], nums[1], nums[2]);

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
