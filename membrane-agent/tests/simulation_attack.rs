//! Simulation Attack - Red Team Live Fire Exercise

use membrane_agent::qvl_ffi::{QvlClient, QvlRiskEdge};
use membrane_agent::policy_enforcer::PolicyEnforcer;
use std::sync::Arc;

#[test]
fn test_live_fire_betrayal_simulation() {
    println!(">>> INITIATING BETRAYAL SIMULATION <<<");
    
    // 1. Init
    let qvl = Arc::new(QvlClient::new().unwrap());
    let enforcer = PolicyEnforcer::new(qvl.clone());
    
    // 2. Register Actors
    let traitor_did = [0xAAu8; 32];
    let accomplice_did = [0xBBu8; 32];
    
    // Node 0 is Local Root (created by init)
    // Node 1 = Traitor
    let traitor_id = qvl.register_node(&traitor_did).expect("Failed to register traitor");
    println!("[+] Registered Traitor (ID: {})", traitor_id);
    
    // Node 2 = Accomplice
    let accomplice_id = qvl.register_node(&accomplice_did).expect("Failed to register accomplice");
    println!("[+] Registered Accomplice (ID: {})", accomplice_id);
    
    // 3. Seed Betrayal Cycle (Negative Risk to trigger Bellman-Ford)
    // Traitor -> Accomplice (Risk -0.5)
    qvl.add_trust_edge(QvlRiskEdge {
        from: traitor_id,
        to: accomplice_id,
        risk: -0.5,
        timestamp_ns: 1000,
        nonce: 1,
        level: 3,
        expires_at_ns: 999999,
    }).expect("Failed edge 1");
    
    // Accomplice -> Traitor (Risk -0.5)
    // Loop sum = -1.0
    qvl.add_trust_edge(QvlRiskEdge {
        from: accomplice_id,
        to: traitor_id,
        risk: -0.5,
        timestamp_ns: 1000,
        nonce: 2,
        level: 3,
        expires_at_ns: 999999,
    }).expect("Failed edge 2");
    
    println!("[+] Betrayal Cycle Seeded: {} <--> {} (Weight -1.0)", traitor_id, accomplice_id);
    
    // 4. Trigger Defense
    println!("[*] Scanning Traitor Node {}...", traitor_id);
    
    // This calls detect -> get_did -> issue_slash
    let punishment = enforcer.punish_if_guilty(traitor_id);
    
    match punishment {
        Some(signal) => {
            println!("[!] BETRAYAL DETECTED! Slash Signal Generated.");
            println!("[!] Payload Size: {} bytes", signal.len());
            
            // Verify content
            // Target DID should be Traitor DID (first 32 bytes)
            assert_eq!(&signal[0..32], &traitor_did);
            
            // Reason should be BetrayalCycle (1)
            assert_eq!(signal[32], 1);
            
            // Evidence Payload should be present (offset 33..65)
            let evidence_start = 33;
            // First byte of evidence hash should match mock (0xEE) or real
            // Since we implemented Mock Hash 0xEE in PolicyEnforcer for now:
            assert_eq!(signal[evidence_start], 0xEE);
            
            println!("[+] SUCCESS: Traitor identified and sentenced.");
            println!("[+] Target DID matches expectation: {:X?}", &signal[0..4]);
        },
        None => {
            // Debugging
            println!("[-] NO signal generated.");
            println!("[-] Trust Graph DID lookup check:");
            if let Some(did) = qvl.get_did(traitor_id) {
                 println!("    ID {} -> DID found", traitor_id);
                 assert_eq!(&did, &traitor_did);
            } else {
                 println!("    ID {} -> DID NOT FOUND!", traitor_id);
            }
            
            // Force fail
            panic!("[-] FAILURE: Traitor escaped detection!");
        }
    }
}
