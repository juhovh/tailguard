package http

import (
	"bytes"
	"context"
	_ "embed"
	"html/template"
	"log"
	"log/slog"
	"net"
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

	tgStatus env.TailGuardStatus
	tsClient *tailscale.Client
	wgClient *wireguard.Client

	mu           sync.Mutex
	lastRequests map[string]time.Time

	httpServer *http.Server
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

		tgStatus: env.LoadStatus(),
		tsClient: tsClient,
		wgClient: wgClient,

		lastRequests: make(map[string]time.Time),
	}
}

func (s *Server) rateLimitMiddleware(next http.HandlerFunc, cooldown time.Duration) http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		client, _, err := net.SplitHostPort(req.RemoteAddr)
		if err != nil {
			client = req.RemoteAddr
		}

		s.mu.Lock()
		now := time.Now()
		if last, ok := s.lastRequests[client]; ok && now.Sub(last) < cooldown {
			s.mu.Unlock()
			http.Error(w, "Rate limit exceeded. Try again later.", http.StatusTooManyRequests)
			return
		}
		s.lastRequests[client] = now
		for ip, t := range s.lastRequests {
			if now.Sub(t) > time.Hour {
				delete(s.lastRequests, ip)
			}
		}
		s.mu.Unlock()

		next(w, req)
	}
}

func (s *Server) index(w http.ResponseWriter, req *http.Request) {
	var tsError, wgError string

	tgStatus := s.tgStatus
	tgStatus.RefreshTimes()

	tsStatus, err := s.tsClient.GetStatus(req.Context(), req.RemoteAddr)
	if err != nil {
		tsError = err.Error()
	}

	wgStatus, err := s.wgClient.GetStatus(req.Context(), tgStatus.WireGuardDevice)
	if err != nil {
		wgError = err.Error()
	}

	data := TemplateData{
		Title: "TailGuard Status",
		Style: template.CSS(style),
		Logo:  template.HTML(logo),

		TailGuardStatus: tgStatus,

		TailscaleStatus: tsStatus,
		TailscaleError:  tsError,

		WireGuardStatus: wgStatus,
		WireGuardError:  wgError,
	}

	// Render into a buffer first to avoid writing partial content on error
	var buf bytes.Buffer
	if err := s.idxTemplate.Execute(&buf, data); err != nil {
		s.log.Error("Error executing template", slog.String("path", req.URL.Path), slog.Any("err", err))
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if _, err := w.Write(buf.Bytes()); err != nil {
		s.log.Warn("Error writing response", slog.String("path", req.URL.Path), slog.Any("err", err))
	}
}

func (s *Server) ListenAndServe(addr string) error {
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

	s.httpServer = &http.Server{Addr: addr, Handler: mux}
	s.log.Info("Listening", slog.String("addr", addr))
	return s.httpServer.ListenAndServe()
}

func (s *Server) Shutdown(ctx context.Context) error {
	if s.httpServer == nil {
		return nil
	}
	return s.httpServer.Shutdown(ctx)
}

func (s *Server) Close() {
	s.tsClient.Close()
	if err := s.wgClient.Close(); err != nil {
		s.log.Warn("Error closing WireGuard client", slog.Any("err", err))
	}
}
