package http

import (
	"html/template"

	"github.com/juhovh/tailguard/daemon/client/tailscale"
	"github.com/juhovh/tailguard/daemon/client/wireguard"
)

type TemplateData struct {
	Title string
	Style template.CSS

	TailscaleStatus *tailscale.Status
	TailscaleError  string

	WireGuardDevice string
	WireGuardStatus *wireguard.Status
	WireGuardError  string
}
