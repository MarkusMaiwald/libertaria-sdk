//! Membrane Agent Daemon
//!
//! L2 trust-based policy enforcement daemon for Libertaria.

use membrane_agent::{
    QvlClient, PolicyEnforcer, AnomalyAlertSystem,
    EventListener, EventListenerConfig, L0Event, PolicyDecision,
};
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, warn, error};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();
    
    info!("🛡️  Membrane Agent starting...");
    
    // Initialize QVL client
    let qvl = Arc::new(QvlClient::new()?);
    info!("✅ QVL client initialized");
    
    // Initialize components
    let policy_enforcer = Arc::new(PolicyEnforcer::new(qvl.clone()));
    let alert_system = Arc::new(AnomalyAlertSystem::new());
    let config = EventListenerConfig::default();
    let (event_listener, mut event_rx) = EventListener::new(config);
    
    info!("✅ Policy enforcer initialized");
    info!("✅ Alert system initialized");
    info!("✅ Event listener initialized");
    
    // Spawn event listener task
    let listener_handle = tokio::spawn(async move {
        if let Err(e) = event_listener.start().await {
            error!("Event listener error: {}", e);
        }
    });
    
    // Spawn periodic betrayal detection
    let qvl_clone = qvl.clone();
    let alerts_clone = alert_system.clone();
    let betrayal_handle = tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(10));
        
        loop {
            interval.tick().await;
            
            // TODO: Get actual node list from registry
            // For now, check a small set of test nodes
            for node_id in 0..10 {
                match qvl_clone.detect_betrayal(node_id) {
                    Ok(anomaly) if anomaly.score > 0.5 => {
                        alerts_clone.emit(anomaly);
                    }
                    Ok(_) => {}, // No anomaly
                    Err(e) => {
                        warn!("Betrayal check failed for node {}: {}", node_id, e);
                    }
                }
            }
            
            // Log alert stats every cycle
            let p0_count = alerts_clone.count_by_priority(membrane_agent::AlertPriority::Critical);
            let p1_count = alerts_clone.count_by_priority(membrane_agent::AlertPriority::Warning);
            
            if p0_count > 0 || p1_count > 0 {
                info!("📊 Alert stats: P0={}, P1={}", p0_count, p1_count);
            }
        }
    });
    
    info!("🚀 Membrane Agent running");
    info!("   - Event listener: STUB MODE (TODO: L0 integration)");
    info!("   - Betrayal detection: every 10 seconds");
    info!("   - Policy enforcement: ready");
    
    // Main event loop
    loop {
        tokio::select! {
            Some(event) = event_rx.recv() => {
                match event {
                    L0Event::PacketReceived { sender_did, packet_type, payload_size } => {
                        let decision = policy_enforcer.should_accept_packet(&sender_did);
                        
                        match decision {
                            PolicyDecision::Accept => {
                                info!("✅ ACCEPT packet type={} size={} from={:?}", 
                                    packet_type, payload_size, &sender_did[..4]);
                            },
                            PolicyDecision::Deprioritize => {
                                warn!("⬇️  DEPRIORITIZE packet type={} from={:?}",
                                    packet_type, &sender_did[..4]);
                            },
                            PolicyDecision::Drop => {
                                error!("🚫 DROP packet type={} from={:?}",
                                    packet_type, &sender_did[..4]);
                            },
                            PolicyDecision::Neutral => {
                                info!("⚪ NEUTRAL packet type={} from={:?} (no trust data)",
                                    packet_type, &sender_did[..4]);
                            },
                        }
                    },
                    L0Event::ConnectionEstablished { peer_did } => {
                        info!("🔗 Connection established with {:?}", &peer_did[..4]);
                    },
                    L0Event::ConnectionDropped { peer_did, reason } => {
                        warn!("❌ Connection dropped with {:?}: {}", &peer_did[..4], reason);
                    },
                }
            },
            
            _ = tokio::signal::ctrl_c() => {
                info!("Received Ctrl+C, shutting down...");
                break;
            }
        }
    }
    
    // Cleanup
    listener_handle.abort();
    betrayal_handle.abort();
    
    info!("Membrane Agent stopped");
    
    Ok(())
}
