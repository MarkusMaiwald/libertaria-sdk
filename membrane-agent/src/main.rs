//! Membrane Agent Daemon
//!
//! L2 trust-based policy enforcement daemon for Libertaria.

use membrane_agent::QvlClient;
use tracing::{info, error};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();
    
    info!("🛡️  Membrane Agent starting...");
    
    // Initialize QVL client
    let qvl = QvlClient::new()?;
    info!("✅ QVL client initialized");
    
    // Test basic functionality
    let reputation = qvl.get_reputation(0)?;
    info!("Node 0 reputation: {:.2}", reputation);
    
    let anomaly = qvl.detect_betrayal(0)?;
    info!("Betrayal check: score={:.2}, reason={:?}", anomaly.score, anomaly.reason);
    
    info!("🚀 Membrane Agent running (stub mode)");
    info!("TODO: Implement event listener, policy enforcer, alert system");
    
    // Keep daemon alive
    tokio::signal::ctrl_c().await?;
    info!("Shutting down...");
    
    Ok(())
}
