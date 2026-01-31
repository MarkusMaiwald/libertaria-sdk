//! Event Listener - L0 IPC Integration (Unix Domain Sockets)
//!
//! Listens for events from the Zig L0 Transport Layer via `/tmp/libertaria_l0.sock`.

use tokio::net::{UnixListener, UnixStream};
use tokio::io::{AsyncReadExt, BufReader};
use tokio::sync::mpsc;
use std::path::Path;
use tracing::{info, error, warn, debug};

/// IPC Protocol Magic Number (0x55AA)
const IPC_MAGIC: u16 = 0x55AA;

/// L0 transport events
#[derive(Debug, Clone)]
pub enum L0Event {
    /// Packet received from peer (Type 0x01)
    PacketReceived {
        sender_did: [u8; 32],
        packet_type: u8,
        payload_size: usize,
    },
    
    /// Connection established (Type 0x02)
    ConnectionEstablished {
        peer_did: [u8; 32],
    },
    
    /// Connection dropped (Type 0x03)
    ConnectionDropped {
        peer_did: [u8; 32],
        reason: String,
    },
}

/// Event listener configuration
#[derive(Debug, Clone)]
pub struct EventListenerConfig {
    /// Channel buffer size
    pub buffer_size: usize,
    /// Socket path
    pub socket_path: String,
}

impl Default for EventListenerConfig {
    fn default() -> Self {
        Self {
            buffer_size: 1000,
            socket_path: "/tmp/libertaria_l0.sock".to_string(),
        }
    }
}

/// Event listener for L0 transport events
pub struct EventListener {
    event_tx: mpsc::Sender<L0Event>,
    config: EventListenerConfig,
}

impl EventListener {
    /// Create new event listener
    pub fn new(config: EventListenerConfig) -> (Self, mpsc::Receiver<L0Event>) {
        let (tx, rx) = mpsc::channel(config.buffer_size);
        (
            Self {
                event_tx: tx,
                config,
            },
            rx,
        )
    }
    
    /// Start listening for L0 IPC connections
    pub async fn start(&self) -> Result<(), EventListenerError> {
        // Remove existing socket if it exists
        if Path::new(&self.config.socket_path).exists() {
            let _ = std::fs::remove_file(&self.config.socket_path);
        }
        
        // Ensure parent dir exists (if not /tmp)
        if let Some(parent) = Path::new(&self.config.socket_path).parent() {
            if !parent.exists() {
                let _ = std::fs::create_dir_all(parent);
            }
        }
        
        let listener = UnixListener::bind(&self.config.socket_path)
            .map_err(|e| EventListenerError::BindFailed(e.to_string()))?;
            
        info!("🎧 IPC Server listening on {}", self.config.socket_path);
        
        loop {
            match listener.accept().await {
                Ok((stream, _addr)) => {
                    info!("🔌 L0 Client connected");
                    let tx = self.event_tx.clone();
                    tokio::spawn(async move {
                        if let Err(e) = handle_connection(stream, tx).await {
                            warn!("IPC connection error: {}", e);
                        }
                        info!("🔌 L0 Client disconnected");
                    });
                }
                Err(e) => {
                    error!("IPC accept failed: {}", e);
                }
            }
        }
    }
    
    /// Inject a test event (for testing without socket)
    #[cfg(test)]
    pub async fn inject_event(&self, event: L0Event) -> Result<(), EventListenerError> {
        self.event_tx.send(event).await
            .map_err(|_| EventListenerError::ChannelClosed)
    }

    /// Helper to get socket path
    pub fn socket_path(&self) -> &str {
        &self.config.socket_path
    }
}

/// Handle a single L0 IPC connection
async fn handle_connection(stream: UnixStream, tx: mpsc::Sender<L0Event>) -> Result<(), EventListenerError> {
    let mut reader = BufReader::new(stream);
    
    loop {
        // 1. Read Header (8 bytes)
        let mut header_buf = [0u8; 8];
        match reader.read_exact(&mut header_buf).await {
            Ok(_) => {}, // Continue
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break, // Clean disconnect
            Err(e) => return Err(EventListenerError::IoError(e.to_string())),
        };
        
        // Deserialize Header: Magic(2), Type(1), Flags(1), Length(4)
        let magic = u16::from_le_bytes([header_buf[0], header_buf[1]]);
        let event_type = header_buf[2];
        let _flags = header_buf[3];
        let length = u32::from_le_bytes([header_buf[4], header_buf[5], header_buf[6], header_buf[7]]);
        
        if magic != IPC_MAGIC {
            warn!("Invalid IPC magic: {:04x}", magic);
            return Err(EventListenerError::ProtocolError("Invalid Magic".into()));
        }
        
        // 2. Read Payload
        let mut payload = vec![0u8; length as usize];
        if length > 0 {
            reader.read_exact(&mut payload).await
                .map_err(|e| EventListenerError::IoError(e.to_string()))?;
        }
            
        // 3. Parse Event
        match event_type {
            0x01 => { // PacketReceived
                if payload.len() < 37 { // 32 DID + 1 Type + 4 Size
                    warn!("Invalid PacketReceived payload size: {}", payload.len());
                    continue; 
                }
                let mut did = [0u8; 32];
                did.copy_from_slice(&payload[0..32]);
                let p_type = payload[32];
                let size = u32::from_le_bytes([payload[33], payload[34], payload[35], payload[36]]);
                
                let event = L0Event::PacketReceived {
                    sender_did: did,
                    packet_type: p_type,
                    payload_size: size as usize,
                };
                
                if tx.send(event).await.is_err() {
                    break; // Receiver closed
                }
            },
            0x02 => { // ConnectionEstablished
                 if payload.len() < 32 {
                     continue;
                 }
                 let mut did = [0u8; 32];
                 did.copy_from_slice(&payload[0..32]);
                 let event = L0Event::ConnectionEstablished {
                     peer_did: did,
                 };
                 if tx.send(event).await.is_err() { break; }
            },
            _ => {
                debug!("Unknown event type: {}", event_type);
            }
        }
    }
    
    Ok(())
}

/// Event listener errors
#[derive(Debug, thiserror::Error)]
pub enum EventListenerError {
    #[error("Bind failed: {0}")]
    BindFailed(String),
    
    #[error("Protocol error: {0}")]
    ProtocolError(String),
    
    #[error("IO error: {0}")]
    IoError(String),
    
    #[error("Channel closed")]
    ChannelClosed,
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::UnixStream;
    use tokio::io::AsyncWriteExt;
    
    #[tokio::test]
    async fn test_ipc_server() {
        let mut config = EventListenerConfig::default();
        config.socket_path = "/tmp/test_ipc.sock".to_string();
        
        let (listener, mut rx) = EventListener::new(config.clone());
        
        // Spawn server
        let server_handle = tokio::spawn(async move {
            listener.start().await.unwrap();
        });
        
        // Wait for server to bind
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        
        // Connect client
        let mut stream = UnixStream::connect(&config.socket_path).await.expect("Connect failed");
        
        // Construct message: Header + Payload
        // Header: Magic(0x55AA), Type(0x01), Flags(0), Len(37)
        let mut msg = Vec::new();
        msg.extend_from_slice(&0x55AAu16.to_le_bytes()); // Magic
        msg.push(0x01); // Type=PacketReceived
        msg.push(0x00); // Flags
        msg.extend_from_slice(&37u32.to_le_bytes()); // Length
        
        // Payload: DID(32) + Type(1) + Size(4)
        msg.extend_from_slice(&[0xFF; 32]); // DID
        msg.push(42); // Packet Type
        msg.extend_from_slice(&1024u32.to_le_bytes()); // Payload Size
        
        stream.write_all(&msg).await.expect("Write failed");
        
        // Receive
        let event = rx.recv().await.expect("Receive failed");
        match event {
            L0Event::PacketReceived { packet_type, payload_size, .. } => {
                assert_eq!(packet_type, 42);
                assert_eq!(payload_size, 1024);
            }
            _ => panic!("Wrong event type"),
        }
        
        server_handle.abort();
    }
}
