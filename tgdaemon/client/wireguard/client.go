package wireguard

import (
	"golang.zx2c4.com/wireguard/wgctrl"
)

type Client struct {
	wgc *wgctrl.Client
}

func NewClient() (*Client, error) {
	wgc, err := wgctrl.New()
	if err != nil {
		return nil, err
	}
	return &Client{wgc: wgc}, nil
}

func (c *Client) GetStatus(deviceName string) (*Status, error) {
	dev, err := c.wgc.Device(deviceName)
	if err != nil {
		return nil, err
	}
	peers := make([]Peer, len(dev.Peers))
	for i, peer := range dev.Peers {
		peers[i] = Peer{
			PublicKey:                   peer.PublicKey.String(),
			Endpoint:                    peer.Endpoint,
			PersistentKeepaliveInterval: peer.PersistentKeepaliveInterval,
			LastHandshakeTime:           peer.LastHandshakeTime,
			ReceiveBytes:                peer.ReceiveBytes,
			TransmitBytes:               peer.TransmitBytes,
			AllowedIPs:                  peer.AllowedIPs,
		}
	}
	return &Status{
		Name:         dev.Name,
		PublicKey:    dev.PublicKey.String(),
		ListenPort:   dev.ListenPort,
		FirewallMark: dev.FirewallMark,
		Peers:        peers,
	}, nil
}

func (c *Client) Close() error {
	return c.wgc.Close()
}
