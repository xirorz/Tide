//! The smallest WebSocket client that can talk to Steam's DevTools port: text messages
//! over plain TCP to this machine only. No TLS, no extensions, no compression.
//!
//! The address is always 127.0.0.1. Nothing in this crate can be pointed at another
//! machine, because whoever reaches that port controls the Steam client.

use std::io::{self, Read, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpStream};
use std::time::Duration;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(2);
/// DevTools answers with whole results, so a message can be large (a full library).
const MAX_MESSAGE: usize = 64 << 20;

fn local(port: u16) -> SocketAddr {
    SocketAddr::from((Ipv4Addr::LOCALHOST, port))
}

fn bad(text: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, text.into())
}

/// One plain HTTP GET, for DevTools' target list. Returns the body.
pub fn http_get(port: u16, path: &str, timeout: Duration) -> io::Result<String> {
    let mut stream = TcpStream::connect_timeout(&local(port), CONNECT_TIMEOUT)?;
    stream.set_read_timeout(Some(timeout))?;
    stream.set_write_timeout(Some(timeout))?;
    stream.write_all(format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n").as_bytes())?;
    // DevTools keeps the connection open whatever we ask, so the body is read by its
    // announced length, not until the end.
    let mut answer = Vec::new();
    let mut chunk = [0u8; 4096];
    let (head_end, length) = loop {
        let n = stream.read(&mut chunk)?;
        if n == 0 {
            return Err(bad("the HTTP answer ended early"));
        }
        answer.extend_from_slice(&chunk[..n]);
        if let Some(at) = answer.windows(4).position(|w| w == b"\r\n\r\n") {
            let head = String::from_utf8_lossy(&answer[..at]).to_ascii_lowercase();
            let status = head.lines().next().unwrap_or_default().to_string();
            if status.split_whitespace().nth(1) != Some("200") {
                return Err(bad(format!("HTTP answer: {status}")));
            }
            let length = head.lines().find_map(|l| l.strip_prefix("content-length:")).and_then(|v| v.trim().parse::<usize>().ok());
            break (at + 4, length.ok_or_else(|| bad("HTTP answer without a length"))?);
        }
        if answer.len() > 65536 {
            return Err(bad("HTTP header is too long"));
        }
    };
    if length > MAX_MESSAGE {
        return Err(bad("HTTP answer is too large"));
    }
    while answer.len() < head_end + length {
        let n = stream.read(&mut chunk)?;
        if n == 0 {
            return Err(bad("the HTTP answer ended early"));
        }
        answer.extend_from_slice(&chunk[..n]);
    }
    Ok(String::from_utf8_lossy(&answer[head_end..head_end + length]).into_owned())
}

pub struct WebSocket {
    stream: TcpStream,
    seed: u64,
}

impl WebSocket {
    pub fn connect(port: u16, path: &str) -> io::Result<WebSocket> {
        let mut stream = TcpStream::connect_timeout(&local(port), CONNECT_TIMEOUT)?;
        stream.set_nodelay(true)?;
        stream.set_read_timeout(Some(Duration::from_secs(10)))?;
        stream.set_write_timeout(Some(Duration::from_secs(10)))?;
        let mut socket = WebSocket { stream: stream.try_clone()?, seed: seed() };
        let key = base64(&socket.random::<16>());
        let request = format!(
            "GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\
             Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        );
        stream.write_all(request.as_bytes())?;
        // Read the answer one byte at a time, so nothing of the first frame is swallowed.
        let mut head = Vec::new();
        let mut byte = [0u8; 1];
        while !head.ends_with(b"\r\n\r\n") {
            stream.read_exact(&mut byte)?;
            head.push(byte[0]);
            if head.len() > 8192 {
                return Err(bad("WebSocket handshake answer is too long"));
            }
        }
        let head = String::from_utf8_lossy(&head);
        if head.split_whitespace().nth(1) != Some("101") {
            return Err(bad(format!("WebSocket refused: {}", head.lines().next().unwrap_or_default())));
        }
        Ok(socket)
    }

    pub fn set_timeout(&self, timeout: Duration) -> io::Result<()> {
        self.stream.set_read_timeout(Some(timeout))
    }

    fn random<const N: usize>(&mut self) -> [u8; N] {
        // Masking is required by the protocol; it is not a secret, so a small generator does.
        let mut out = [0u8; N];
        for b in &mut out {
            self.seed ^= self.seed << 13;
            self.seed ^= self.seed >> 7;
            self.seed ^= self.seed << 17;
            *b = (self.seed >> 24) as u8;
        }
        out
    }

    fn send_frame(&mut self, opcode: u8, payload: &[u8]) -> io::Result<()> {
        let mask = self.random::<4>();
        self.stream.write_all(&encode_frame(opcode, payload, mask))?;
        self.stream.flush()
    }

    pub fn send_text(&mut self, text: &str) -> io::Result<()> {
        self.send_frame(0x1, text.as_bytes())
    }

    /// The next whole text message. Pings are answered, other control frames skipped.
    pub fn read_text(&mut self) -> io::Result<String> {
        let mut message = Vec::new();
        loop {
            let mut head = [0u8; 2];
            self.stream.read_exact(&mut head)?;
            let last = head[0] & 0x80 != 0;
            let opcode = head[0] & 0x0f;
            let masked = head[1] & 0x80 != 0;
            let mut len = (head[1] & 0x7f) as u64;
            if len == 126 {
                let mut b = [0u8; 2];
                self.stream.read_exact(&mut b)?;
                len = u16::from_be_bytes(b) as u64;
            } else if len == 127 {
                let mut b = [0u8; 8];
                self.stream.read_exact(&mut b)?;
                len = u64::from_be_bytes(b);
            }
            if len as usize > MAX_MESSAGE || message.len() + len as usize > MAX_MESSAGE {
                return Err(bad("WebSocket message is too large"));
            }
            let mut mask = [0u8; 4];
            if masked {
                self.stream.read_exact(&mut mask)?;
            }
            let mut payload = vec![0u8; len as usize];
            self.stream.read_exact(&mut payload)?;
            if masked {
                for (i, b) in payload.iter_mut().enumerate() {
                    *b ^= mask[i % 4];
                }
            }
            match opcode {
                0x0..=0x2 => {
                    message.extend_from_slice(&payload);
                    if last {
                        return String::from_utf8(message).map_err(|_| bad("WebSocket message is not text"));
                    }
                }
                0x8 => return Err(io::Error::new(io::ErrorKind::ConnectionAborted, "Steam closed the connection")),
                0x9 => self.send_frame(0xA, &payload)?,
                _ => {}
            }
        }
    }
}

fn seed() -> u64 {
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(1);
    (now ^ ((std::process::id() as u64) << 32)) | 1
}

fn encode_frame(opcode: u8, payload: &[u8], mask: [u8; 4]) -> Vec<u8> {
    let mut frame = Vec::with_capacity(payload.len() + 14);
    frame.push(0x80 | opcode);
    match payload.len() {
        n if n < 126 => frame.push(0x80 | n as u8),
        n if n <= u16::MAX as usize => {
            frame.push(0x80 | 126);
            frame.extend_from_slice(&(n as u16).to_be_bytes());
        }
        n => {
            frame.push(0x80 | 127);
            frame.extend_from_slice(&(n as u64).to_be_bytes());
        }
    }
    frame.extend_from_slice(&mask);
    frame.extend(payload.iter().enumerate().map(|(i, b)| b ^ mask[i % 4]));
    frame
}

pub fn base64(bytes: &[u8]) -> String {
    const ABC: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = (chunk[0] as u32) << 16 | (*chunk.get(1).unwrap_or(&0) as u32) << 8 | *chunk.get(2).unwrap_or(&0) as u32;
        out.push(ABC[(n >> 18) as usize & 63] as char);
        out.push(ABC[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { ABC[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { ABC[n as usize & 63] as char } else { '=' });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;

    #[test]
    fn base64_matches_the_standard_examples() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn frames_carry_their_length_in_the_right_form() {
        let mask = [1, 2, 3, 4];
        let short = encode_frame(1, b"hi", mask);
        assert_eq!(&short[..6], &[0x81, 0x82, 1, 2, 3, 4]);
        assert_eq!(&short[6..], &[b'h' ^ 1, b'i' ^ 2]);
        let medium = encode_frame(1, &[0u8; 300], mask);
        assert_eq!(&medium[..4], &[0x81, 0x80 | 126, 1, 44]);
        let long = encode_frame(1, &vec![0u8; 70_000], mask);
        assert_eq!(long[1], 0x80 | 127);
        assert_eq!(long.len(), 2 + 8 + 4 + 70_000);
    }

    /// A pretend DevTools end: accepts the handshake, sends a ping and then one text
    /// message split over two frames, and expects the client's message back.
    #[test]
    fn talks_to_a_server_that_pings_and_splits_messages() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut head = Vec::new();
            let mut b = [0u8; 1];
            while !head.ends_with(b"\r\n\r\n") {
                s.read_exact(&mut b).unwrap();
                head.push(b[0]);
            }
            assert!(String::from_utf8_lossy(&head).contains("Sec-WebSocket-Key: "));
            s.write_all(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n").unwrap();
            s.write_all(&[0x89, 0x01, b'p']).unwrap();
            s.write_all(&[0x01, 0x03, b'h', b'e', b'l']).unwrap();
            s.write_all(&[0x80, 0x02, b'l', b'o']).unwrap();
            // The pong, then the client's text frame, both masked.
            let mut read_frame = || {
                let mut h = [0u8; 6];
                s.read_exact(&mut h).unwrap();
                let mut p = vec![0u8; (h[1] & 0x7f) as usize];
                s.read_exact(&mut p).unwrap();
                for (i, b) in p.iter_mut().enumerate() {
                    *b ^= h[2 + i % 4];
                }
                (h[0] & 0x0f, p)
            };
            assert_eq!(read_frame(), (0xA, b"p".to_vec()));
            assert_eq!(read_frame(), (0x1, b"thanks".to_vec()));
        });
        let mut ws = WebSocket::connect(port, "/devtools/page/1").unwrap();
        assert_eq!(ws.read_text().unwrap(), "hello");
        ws.send_text("thanks").unwrap();
        server.join().unwrap();
    }

    #[test]
    fn http_get_returns_the_body() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut buf = [0u8; 512];
            let n = s.read(&mut buf).unwrap();
            assert!(String::from_utf8_lossy(&buf[..n]).starts_with("GET /json HTTP/1.1\r\nHost: 127.0.0.1:"));
            s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n[]").unwrap();
        });
        assert_eq!(http_get(port, "/json", Duration::from_secs(2)).unwrap(), "[]");
        server.join().unwrap();
    }
}
