package http

import (
	_ "embed"
	"html/template"
	"log"
	"log/slog"
	"net/http"

	"github.com/juhovh/tailguard/tgdaemon/client/tailscale"
	"github.com/juhovh/tailguard/tgdaemon/client/wireguard"
	"github.com/juhovh/tailguard/tgdaemon/env"
)

//go:embed logo.svg
var logo string

//go:embed style.css
var style string

//go:embed template.html
var tpl string

type Server struct {
	log         *slog.Logger
	idxTemplate *template.Template

	tgConfig env.TailGuardConfig
	tsClient *tailscale.Client
	wgClient *wireguard.Client
}

func NewServer(cfg env.TailGuardConfig) *Server {
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

		tgConfig: cfg,
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

	wgStatus, err := s.wgClient.GetStatus("wg0")
	if err != nil {
		wgError = err.Error()
	}

	data := TemplateData{
		Title: "TailGuard Status",
		Style: template.CSS(style),
		Logo:  template.HTML(logo),

		TailGuardConfig: s.tgConfig,

		TailscaleStatus: tsStatus,
		TailscaleError:  tsError,

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
