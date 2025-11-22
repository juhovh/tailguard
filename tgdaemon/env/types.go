package env

type TailGuardConfig struct {
	ExposeHost  bool
	ClientMode  bool
	Nameservers string

	WireGuardDevice       string
	WireGuardIsolatePeers bool

	TailscaleDevice string
	TailscalePort   int
}
