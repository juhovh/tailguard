package wireguard

import (
	"net"
	"time"
)

// KeyLen is the expected key length for a WireGuard key.
const KeyLen = 32 // wgh.KeyLen

// A Key is a public, private, or pre-shared secret key.  The Key constructor
// functions in this package can be used to create Keys suitable for each of
// these applications.
type Key [KeyLen]byte

type Status struct {
	Name         string
	PublicKey    string
	ListenPort   int
	FirewallMark int
	Peers        []Peer
}

type Peer struct {
	PublicKey                   string
	Endpoint                    *net.UDPAddr
	PersistentKeepaliveInterval time.Duration
	LastHandshakeTime           time.Time
	ReceiveBytes                int64
	TransmitBytes               int64
	AllowedIPs                  []net.IPNet
}
