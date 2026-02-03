Feature: RFC-0015 Pluggable Transport Skins
  As a Libertaria node operator in a censored region
  I want to automatically select camouflaged transport protocols
  So that my traffic evades detection by state-level DPI (GFW, RKN, etc.)

  Background:
    Given the L0 transport layer is initialized
    And the node has a valid relay endpoint configuration
    And the Polymorphic Noise Generator (PNG) is seeded with ECDH secret

  # ============================================================================
  # Skin Selection and Probing
  # ============================================================================

  Scenario: Automatic skin selection succeeds with RAW UDP
    Given the network allows outbound UDP to port 7844
    When the skin probe sequence starts
    And the RAW UDP probe completes within 100ms
    Then the transport skin should be "RAW"
    And the LWF frames should be sent unmodified over UDP

  Scenario: Automatic skin selection falls back to HTTPS
    Given the network blocks UDP port 7844
    And HTTPS traffic to port 443 is allowed
    When the RAW UDP probe times out after 100ms
    And the HTTPS WebSocket probe completes within 500ms
    Then the transport skin should be "MIMIC_HTTPS"
    And the LWF frames should be wrapped in WebSocket frames over TLS 1.3

  Scenario: Automatic skin selection falls back to DNS tunnel
    Given the network blocks all UDP except DNS
    And blocks HTTPS to non-whitelisted domains
    When the RAW UDP probe times out
    And the HTTPS probe times out after 500ms
    And the DNS DoH probe completes within 1s
    Then the transport skin should be "MIMIC_DNS"
    And the LWF frames should be encoded as DNS queries over HTTPS

  Scenario: Automatic skin selection reaches nuclear option
    Given the network implements deep packet inspection on all protocols
    And all previous probes fail
    When the probe sequence reaches the steganography fallback
    Then the transport skin should be "STEGO_IMAGE"
    And the user should be warned of extreme latency

  # ============================================================================
  # Polymorphic Noise Generator (PNG)
  # ============================================================================

  Scenario: PNG generates per-session unique noise
    Given two independent sessions to the same relay
    And both sessions complete ECDH handshake
    When Session A derives PNG seed from shared secret
    And Session B derives PNG seed from its shared secret
    Then the PNG seeds should be different
    And the epoch profiles should be different
    And the packet size distributions should not correlate

  Scenario: PNG generates deterministic noise for session peers
    Given a single session between Alice and Bob
    And they complete ECDH handshake
    When Alice derives PNG seed from shared secret
    And Bob derives PNG seed from same shared secret
    Then the PNG seeds should be identical
    And Alice's noise can be subtracted by Bob

  Scenario: PNG epoch rotation prevents long-term analysis
    Given a session using MIMIC_HTTPS skin
    And the epoch length is set to 500 packets
    When 499 packets have been transmitted
    Then the packet size distribution should follow Profile A
    When the 500th packet is transmitted
    Then the epoch should rotate
    And the packet size distribution should follow Profile B
    And Profile B should be different from Profile A

  Scenario: PNG matches real-world distributions
    Given MIMIC_HTTPS skin with Netflix emulation
    When the PNG samples packet sizes
    Then the distribution should be Pareto with mean 1440 bytes
    And the distribution should match Netflix video chunk captures

  # ============================================================================
  # MIMIC_HTTPS Skin (WebSocket over TLS)
  # ============================================================================

  Scenario: HTTPS skin mimics Chrome TLS fingerprint
    Given the transport skin is "MIMIC_HTTPS"
    When the TLS handshake initiates
    Then the ClientHello should match Chrome 120 JA3 signature
    And the cipher suites should match Chrome defaults
    And the extensions order should match Chrome
    And the ALPN should be "h2,http/1.1"

  Scenario: HTTPS skin WebSocket handshake looks legitimate
    Given the transport skin is "MIMIC_HTTPS"
    When the WebSocket upgrade request is sent
    Then the HTTP headers should include legitimate User-Agent
    And the request path should look like a real API endpoint
    And the Origin header should be set appropriately

  Scenario: HTTPS skin hides LWF magic bytes
    Given an LWF frame with magic bytes "LWF\0"
    When wrapped in MIMIC_HTTPS skin
    Then the wire format should be TLS ciphertext
    And the magic bytes should not appear in cleartext
    And DPI signature matching should fail

  Scenario: HTTPS skin with domain fronting
    Given the relay supports domain fronting
    And the cover domain is "cdn.cloudflare.com"
    And the real endpoint is "relay.libertaria.network"
    When the TLS handshake initiates
    Then the SNI should be "cdn.cloudflare.com"
    And the HTTP Host header should be "relay.libertaria.network"

  Scenario: HTTPS skin with ECH (Encrypted Client Hello)
    Given the relay supports ECH
    And the client has ECH config for the relay
    When the TLS handshake initiates
    Then the ClientHelloInner should contain real SNI
    And the ClientHelloOuter should have encrypted SNI
    And passive DPI should not see the real destination

  # ============================================================================
  # MIMIC_DNS Skin (DoH Tunnel)
  # ============================================================================

  Scenario: DNS skin uses DoH not raw DNS
    Given the transport skin is "MIMIC_DNS"
    When a DNS query is sent
    Then it should be an HTTPS POST to 1.1.1.1
    And the Content-Type should be "application/dns-message"
    And not use raw port 53 UDP

  Scenario: DNS skin avoids high-entropy labels
    Given the transport skin is "MIMIC_DNS"
    When encoding LWF data as DNS queries
    Then subdomain labels should use dictionary words
    And the Shannon entropy should be < 3.5 bits/char
    And not use Base32/Base64 encoding

  Scenario: DNS skin matches real DoH timing
    Given the transport skin is "MIMIC_DNS"
    When sending queries
    Then the inter-query timing should follow Gamma distribution
    And not be perfectly regular
    And should match Cloudflare DoH query patterns

  # ============================================================================
  # Anti-Fingerprinting and Active Defense
  # ============================================================================

  Scenario: Active probe receives honeytrap response
    Given an adversary sends probe traffic to relay
    And the probe has no valid session cookie
    When the relay receives the probe
    Then it should respond as nginx default server
    And return HTTP 200 with generic index.html
    And not reveal itself as Libertaria relay

  Scenario: Rate limiting on failed handshakes
    Given an adversary attempts rapid handshake scanning
    When more than 10 failed handshakes occur from same IP in 1 minute
    Then subsequent connections should be rate limited
    And exponential backoff should apply

  Scenario: PoW prevents relay enumeration
    Given the relay requires proof-of-work
    When a client connects without valid PoW
    Then the connection should be rejected
    When a client connects with valid Argon2 PoW (100ms compute)
    Then the connection should proceed to handshake

  # ============================================================================
  # Multi-Path Agility
  # ============================================================================

  Scenario: Primary skin throttling triggers fallback
    Given primary skin is MIMIC_HTTPS at 90% bandwidth
    And secondary skin is MIMIC_DNS at 10% bandwidth
    When GFW detects and throttles HTTPS traffic
    Then the secondary channel should signal endpoint switch
    And the primary should migrate to new relay IP

  Scenario: Seamless skin switching without rekeying
    Given an active session with MIMIC_HTTPS
    When the skin switches to MIMIC_DNS due to blocking
    Then the LWF encryption keys should remain valid
    And no re-handshake should be required
    And in-flight packets should not be lost

  # ============================================================================
  # Error Handling and Edge Cases
  # ============================================================================

  Scenario: All probes fail raises alert
    Given all network paths are blocked
    When the skin probe sequence completes
    And no viable skin is found
    Then the user should receive "Network severely restricted" alert
    And manual configuration option should be offered

  Scenario: Skin mid-session failure recovery
    Given a session is active with MIMIC_HTTPS
    When the TLS connection drops unexpectedly
    Then automatic reconnection should attempt same skin first
    And fallback to next skin after 3 retries

  Scenario: Invalid skin configuration is rejected
    Given the configuration specifies unknown skin "MIMIC_UNKNOWN"
    When the transport initializes
    Then initialization should fail with "Invalid skin"
    And fallback to automatic selection should occur
