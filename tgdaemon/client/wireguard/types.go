package wireguard

import (
	"net"
	"time"
)

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
	LastHandshakeTime           string // time.RFC3339
	LastHandshakeTimeAgo        string
	ReceiveBytes                int64
	ReceiveBytesStr             string
	TransmitBytes               int64
	TransmitBytesStr            string
	AllowedIPs                  []string
}
