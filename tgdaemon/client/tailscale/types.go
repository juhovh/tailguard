package tailscale

import (
	"net/netip"
)

type UserProfile struct {
	ID          int64
	LoginName   string // "alice@smith.com"; for display purposes only (provider is not listed)
	DisplayName string // "Alice Smith"
}

type RouteInfo struct {
	UsingExitNode               *ExitNode
	AdvertisingExitNode         bool
	AdvertisingExitNodeApproved bool          // whether running this node as an exit node has been approved by an admin
	AdvertisedRoutes            []SubnetRoute // excludes exit node routes
}

type ExitNode struct {
	ID     string
	Name   string
	Online bool
}

type SubnetRoute struct {
	Route    string
	Approved bool // approved by control server
}

type Status struct {
	ID          string
	Status      string
	DeviceName  string
	TailnetName string // TLS cert name
	DomainName  string
	IPv4        netip.Addr
	IPv6        netip.Addr
	OS          string
	IPNVersion  string

	Profile  UserProfile
	IsTagged bool
	Tags     []string

	KeyExpiry  string // time.RFC3339
	KeyExpired bool

	RouteInfo *RouteInfo

	TUNMode bool
}
