package http

import (
	_ "embed"
	"html/template"
	"log"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/juhovh/tailguard/tgdaemon/client/tailscale"
	"github.com/juhovh/tailguard/tgdaemon/client/wireguard"
	"github.com/juhovh/tailguard/tgdaemon/env"
)

//go:embed favicon.svg
var favicon string

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

	lastRequest time.Time
	mu          sync.Mutex
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

func (s *Server) rateLimitMiddleware(next http.HandlerFunc, cooldown time.Duration) http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		s.mu.Lock()
		now := time.Now()
		if !s.lastRequest.IsZero() && now.Sub(s.lastRequest) < cooldown {
			s.mu.Unlock()
			http.Error(w, "Rate limit exceeded. Try again later.", http.StatusTooManyRequests)
			return
		}
		s.lastRequest = now
		s.mu.Unlock()

		next(w, req)
	}
}

func (s *Server) index(w http.ResponseWriter, req *http.Request) {
	var tsError, wgError string

	tsStatus, err := s.tsClient.GetStatus(req.Context(), req.RemoteAddr)
	if err != nil {
		tsError = err.Error()
	}

	wgStatus, err := s.wgClient.GetStatus(req.Context(), "wg0")
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
		if req.URL.Path == "/" {
			s.rateLimitMiddleware(s.index, time.Second)(w, req)
			return
		} else if req.URL.Path == "/favicon.svg" {
			w.Header().Set("Content-Type", "image/svg+xml")
			_, _ = w.Write([]byte(favicon))
			return
		}

		s.log.Warn("404 Not Found", slog.String("path", req.URL.Path))
		http.NotFound(w, req)
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
