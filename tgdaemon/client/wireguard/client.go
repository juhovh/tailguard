package wireguard

import (
	"context"
	"fmt"
	"time"

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

func bytes(b uint64) string {
	if b < 1024 {
		return fmt.Sprintf("%d B", b)
	} else if b < 1024*1024 {
		return fmt.Sprintf("%.2f KiB", float64(b)/1024)
	} else if b < 1024*1024*1024 {
		return fmt.Sprintf("%.2f MiB", float64(b)/(1024*1024))
	} else if b < 1024*1024*1024*1024 {
		return fmt.Sprintf("%.2f GiB", float64(b)/(1024*1024*1024))
	} else {
		return fmt.Sprintf("%.2f TiB", float64(b)/(1024*1024*1024*1024))
	}
}

func (c *Client) GetStatus(ctx context.Context, deviceName string) (*Status, error) {
	dev, err := c.wgc.Device(deviceName)
	if err != nil {
		return nil, err
	}
	if err = ctx.Err(); err != nil {
		return nil, err
	}
	peers := make([]Peer, len(dev.Peers))
	for i, peer := range dev.Peers {
		allowedIPs := make([]string, len(peer.AllowedIPs))
		for j, ip := range peer.AllowedIPs {
			allowedIPs[j] = ip.String()
		}
		var lastHandshakeTime, lastHandshakeTimeAgo string
		if !peer.LastHandshakeTime.IsZero() {
			lastHandshakeTime = peer.LastHandshakeTime.Format(time.RFC3339)
			lastHandshakeTimeAgo = time.Now().Sub(peer.LastHandshakeTime).Round(time.Second).String()
		}
		peers[i] = Peer{
			PublicKey:                   peer.PublicKey.String(),
			Endpoint:                    peer.Endpoint,
			PersistentKeepaliveInterval: peer.PersistentKeepaliveInterval,
			LastHandshakeTime:           lastHandshakeTime,
			LastHandshakeTimeAgo:        lastHandshakeTimeAgo,
			ReceiveBytes:                peer.ReceiveBytes,
			ReceiveBytesStr:             bytes(uint64(peer.ReceiveBytes)),
			TransmitBytes:               peer.TransmitBytes,
			TransmitBytesStr:            bytes(uint64(peer.TransmitBytes)),
			AllowedIPs:                  allowedIPs,
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
