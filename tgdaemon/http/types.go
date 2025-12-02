package http

import (
	"html/template"

	"github.com/juhovh/tailguard/tgdaemon/client/tailscale"
	"github.com/juhovh/tailguard/tgdaemon/client/wireguard"
	"github.com/juhovh/tailguard/tgdaemon/env"
)

type TemplateData struct {
	Title string
	Style template.CSS
	Logo  template.HTML

	TailGuardConfig env.TailGuardConfig

	TailscaleStatus *tailscale.Status
	TailscaleError  string

	WireGuardStatus *wireguard.Status
	WireGuardError  string
}
