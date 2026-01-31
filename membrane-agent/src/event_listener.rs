//! Event Listener - L0 UTCP event monitoring stub
//!
//! Placeholder for future L0 integration via IPC/shared memory.

use tokio::sync::mpsc;
use std::time::Duration;

/// L0 transport events
#[derive(Debug, Clone)]
pub enum L0Event {
    /// Packet received from peer
    PacketReceived {
        sender_did: [u8; 32],
        packet_type: u8,
        payload_size: usize,
    },
    
    /// Connection established with peer
    ConnectionEstablished {
        peer_did: [u8; 32],
    },
    
    /// Connection dropped
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
    /// Polling interval (for stub mode)
    pub poll_interval_ms: u64,
}

impl Default for EventListenerConfig {
    fn default() -> Self {
        Self {
            buffer_size: 1000,
            poll_interval_ms: 100,
        }
    }
}

/// Event listener for L0 transport events
pub struct EventListener {
    #[allow(dead_code)]
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
    
    /// Start listening for L0 events (stub implementation)
    pub async fn start(&self) -> Result<(), EventListenerError> {
        tracing::info!("🎧 Event listener started (STUB MODE)");
        tracing::info!("   TODO: Integrate with L0 UTCP via IPC/shared memory");
        
        // TODO: Replace with actual L0 integration
        // For now, just keep the task alive
        loop {
            tokio::time::sleep(Duration::from_millis(self.config.poll_interval_ms)).await;
        }
    }
    
    /// Inject a test event (for testing)
    #[cfg(test)]
    pub async fn inject_event(&self, event: L0Event) -> Result<(), EventListenerError> {
        self.event_tx
            .send(event)
            .await
            .map_err(|_| EventListenerError::ChannelClosed)
    }
}

/// Event listener errors
#[derive(Debug, thiserror::Error)]
pub enum EventListenerError {
    #[error("Event channel closed")]
    ChannelClosed,
    
    #[error("L0 integration not implemented")]
    NotImplemented,
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_event_listener_creation() {
        let config = EventListenerConfig::default();
        let (_listener, mut rx) = EventListener::new(config);
        
        // Should not block
        tokio::select! {
            _ = rx.recv() => panic!("Should not receive events in stub mode"),
            _ = tokio::time::sleep(Duration::from_millis(10)) => {}
        }
    }
    
    #[tokio::test]
    async fn test_inject_event() {
        let config = EventListenerConfig::default();
        let (listener, mut rx) = EventListener::new(config);
        
        let test_event = L0Event::PacketReceived {
            sender_did: [1u8; 32],
            packet_type: 42,
            payload_size: 1024,
        };
        
        listener.inject_event(test_event).await.unwrap();
        
        let received = rx.recv().await.unwrap();
        match received {
            L0Event::PacketReceived { packet_type, .. } => {
                assert_eq!(packet_type, 42);
            }
            _ => panic!("Wrong event type"),
        }
    }
}
