package tailscale

import (
	"context"
	"log/slog"
	"net/netip"
	"strings"
	"time"

	"tailscale.com/client/local"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/net/tsaddr"
)

type Client struct {
	log *slog.Logger
	lc  *local.Client
}

func NewClient() (*Client, error) {
	return &Client{
		log: slog.Default(),
		lc:  &local.Client{},
	}, nil
}

func (c *Client) selfNodeAddresses(ctx context.Context, st *ipnstate.Status, remoteAddr string) (ipv4, ipv6 netip.Addr) {
	for _, ip := range st.Self.TailscaleIPs {
		if ip.Is4() {
			ipv4 = ip
		} else if ip.Is6() {
			ipv6 = ip
		}
		if ipv4.IsValid() && ipv6.IsValid() {
			break // found both IPs
		}
	}
	if whois, err := c.lc.WhoIs(ctx, remoteAddr); err == nil {
		// The source peer connecting to this node may know it by a different
		// IP than the node knows itself as. Specifically, this may be the case
		// if the peer is coming from a different tailnet (sharee node), as IPs
		// are specific to each tailnet.
		// Here, we check if the source peer knows the node by a different IP,
		// and return the peer's version if so.
		if knownIPv4 := whois.Node.SelfNodeV4MasqAddrForThisPeer; knownIPv4 != nil {
			ipv4 = *knownIPv4
		}
		if knownIPv6 := whois.Node.SelfNodeV6MasqAddrForThisPeer; knownIPv6 != nil {
			ipv6 = *knownIPv6
		}
	}
	return ipv4, ipv6
}

func (c *Client) selfNodeNames(ctx context.Context, st *ipnstate.Status) (tailnetName, domainName string) {
	profile, _, err := c.lc.ProfileStatus(ctx)
	if err != nil {
		// If for some reason we can't fetch profiles,
		// continue to use st.CurrentTailnet if set.
		if st.CurrentTailnet != nil {
			return st.CurrentTailnet.MagicDNSSuffix, st.CurrentTailnet.Name
		}
		return "", ""
	}
	return profile.NetworkProfile.MagicDNSName, profile.NetworkProfile.DisplayNameOrDefault()
}

func (c *Client) selfUserProfile(st *ipnstate.Status) UserProfile {
	profile := st.User[st.Self.UserID]
	return UserProfile{
		ID:          int64(profile.ID),
		LoginName:   profile.LoginName,
		DisplayName: profile.DisplayName,
	}
}

func (c *Client) selfRouteStatuses(ctx context.Context, st *ipnstate.Status) (*RouteInfo, error) {
	prefs, err := c.lc.GetPrefs(ctx)
	if err != nil {
		return nil, err
	}

	ri := &RouteInfo{}
	routeApproved := func(route netip.Prefix) bool {
		if st.Self == nil || st.Self.AllowedIPs == nil {
			return false
		}
		return st.Self.AllowedIPs.ContainsFunc(func(p netip.Prefix) bool {
			return p == route
		})
	}
	ri.AdvertisingExitNodeApproved = routeApproved(tsaddr.AllIPv4()) || routeApproved(tsaddr.AllIPv6())

	for _, r := range prefs.AdvertiseRoutes {
		if tsaddr.IsExitRoute(r) {
			ri.AdvertisingExitNode = true
		} else {
			ri.AdvertisedRoutes = append(ri.AdvertisedRoutes, SubnetRoute{
				Route:    r.String(),
				Approved: routeApproved(r),
			})
		}
	}
	if e := st.ExitNodeStatus; e != nil {
		ri.UsingExitNode = &ExitNode{
			ID:     string(e.ID),
			Online: e.Online,
		}
		for _, ps := range st.Peer {
			if ps.ID == e.ID {
				ri.UsingExitNode.Name = ps.DNSName
				break
			}
		}
		if ri.UsingExitNode.Name == "" {
			// Falling back to TailscaleIP/StableNodeID when the peer
			// is no longer included in status.
			if len(e.TailscaleIPs) > 0 {
				ri.UsingExitNode.Name = e.TailscaleIPs[0].Addr().String()
			} else {
				ri.UsingExitNode.Name = string(e.ID)
			}
		}
	}
	return ri, nil
}

func (c *Client) GetStatus(ctx context.Context, remoteAddr string) (*Status, error) {
	st, err := c.lc.Status(ctx)
	if err != nil {
		return nil, err
	}

	ipv4, ipv6 := c.selfNodeAddresses(ctx, st, remoteAddr)
	tailnetName, domainName := c.selfNodeNames(ctx, st)
	profile := c.selfUserProfile(st)

	var tags []string
	if st.Self.Tags != nil {
		tags = st.Self.Tags.AsSlice()
	}

	var keyExpiry string
	if st.Self.KeyExpiry != nil {
		keyExpiry = st.Self.KeyExpiry.Format(time.RFC3339)
	}
	routeInfo, _ := c.selfRouteStatuses(ctx, st)

	status := &Status{
		ID:          string(st.Self.ID),
		Status:      st.BackendState,
		DeviceName:  strings.Split(st.Self.DNSName, ".")[0],
		TailnetName: tailnetName,
		DomainName:  domainName,
		IPv4:        ipv4,
		IPv6:        ipv6,
		OS:          st.Self.OS,
		IPNVersion:  strings.Split(st.Version, "-")[0],

		Profile:  profile,
		IsTagged: st.Self.IsTagged(),
		Tags:     tags,

		KeyExpiry:  keyExpiry,
		KeyExpired: st.Self.Expired,

		TUNMode: st.TUN,

		RouteInfo: routeInfo,
	}

	return status, nil
}

func (c *Client) Close() {
	c.log.Info("Closing Tailscale client")
}
