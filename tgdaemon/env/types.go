package env

type TailGuardStatus struct {
	ExposeHost  bool
	ClientMode  bool
	Nameservers string

	WireGuardDevice       string
	WireGuardIsolatePeers bool

	TailscaleDevice string
	TailscalePort   int

	StartupTime *string // time.RFC3339
	HealthyTime *string // time.RFC3339
}
