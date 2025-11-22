package http

import (
	_ "embed"
	"html/template"
	"log"
	"log/slog"
	"net/http"
	"os"

	"github.com/juhovh/tailguard/daemon/client/tailscale"
	"github.com/juhovh/tailguard/daemon/client/wireguard"
)

//go:embed style.css
var style string

//go:embed template.html
var tpl string

type Server struct {
	log         *slog.Logger
	idxTemplate *template.Template

	tsClient *tailscale.Client
	wgClient *wireguard.Client
}

func NewServer() *Server {
	tsClient, err := tailscale.NewClient()
	if err != nil {
		log.Fatalf("Failed to create Tailscale client: %v", err)
	}
	wgClient, err := wireguard.NewClient()
	if err != nil {
		log.Fatalf("Failed to create WireGuard client: %v", err)
	}
	idxTemplate, err := template.New("index").Parse(tpl)
	if err != nil {
		log.Fatalf("Failed to create template: %v", err)
	}
	return &Server{
		log:         slog.Default(),
		idxTemplate: idxTemplate,

		tsClient: tsClient,
		wgClient: wgClient,
	}
}

func (s *Server) index(w http.ResponseWriter, req *http.Request) {
	var tsError, wgError string
	tsStatus, err := s.tsClient.GetStatus(req.Context(), req.RemoteAddr)
	if err != nil {
		tsError = err.Error()
	}

	wgDevice, wgDeviceExists := os.LookupEnv("WG_DEVICE")
	if !wgDeviceExists {
		wgDevice = "wg0"
	}
	wgStatus, err := s.wgClient.GetStatus("wg0")
	if err != nil {
		wgError = err.Error()
	}

	data := TemplateData{
		Title: "TailGuard Status",
		Style: template.CSS(style),

		TailscaleStatus: tsStatus,
		TailscaleError:  tsError,

		WireGuardDevice: wgDevice,
		WireGuardStatus: wgStatus,
		WireGuardError:  wgError,
	}
	err = s.idxTemplate.Execute(w, data)
	if err != nil {
		s.log.Error("Error executing template", slog.String("path", req.URL.Path))
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
	}
}

func (s *Server) ListenAndServe(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path != "/" {
			s.log.Warn("404 Not Found", slog.String("path", req.URL.Path))
			http.NotFound(w, req)
			return
		}
		s.index(w, req)
	})
	err := http.ListenAndServe(addr, mux)
	if err != nil {
		log.Fatal(err)
	}
	s.log.Info("Listening on " + addr)
}

func (s *Server) Close() {
	s.tsClient.Close()
	err := s.wgClient.Close()
	if err != nil {
		s.log.Warn("Error closing WireGuard client: %v", err)
	}
}
