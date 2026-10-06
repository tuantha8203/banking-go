// Package httpapi builds the admin-api REST API for staff (web-admin): chi router + Huma v2, OpenAPI 3.1 (AD-9).
package httpapi

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humachi"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// Title and Version appear in the exported OpenAPI document (api/openapi/admin-api.yaml).
const (
	Title   = "banking-go admin-api"
	Version = "0.1.0"
)

// PingOutput is the body of GET /v1/ping.
type PingOutput struct {
	Body struct {
		Status string `json:"status" example:"ok" doc:"Always ok when the service answers."`
	}
}

// New returns the HTTP handler and the Huma API (used to export OpenAPI).
func New() (http.Handler, huma.API) {
	r := chi.NewRouter()
	r.Use(middleware.Recoverer)

	cfg := huma.DefaultConfig(Title, Version)
	// No $schema links in bodies: responses stay exactly as documented.
	cfg.CreateHooks = nil
	api := humachi.New(r, cfg)

	huma.Register(api, huma.Operation{
		OperationID: "ping",
		Method:      http.MethodGet,
		Path:        "/v1/ping",
		Summary:     "Liveness ping of the admin API",
		Tags:        []string{"system"},
	}, func(context.Context, *struct{}) (*PingOutput, error) {
		out := &PingOutput{}
		out.Body.Status = "ok"
		return out, nil
	})
	return r, api
}

// OpenAPIYAML renders the OpenAPI 3.1 document.
func OpenAPIYAML() ([]byte, error) {
	_, api := New()
	return api.OpenAPI().YAML()
}
