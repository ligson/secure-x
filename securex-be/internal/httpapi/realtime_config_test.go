package httpapi_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ligson/secure-x/securex-be/internal/config"
)

func TestRealtimeConfigUsesForwardedPrefix(t *testing.T) {
	router, tokens, db := newAccessControlRouterWithServerConfig(
		t,
		config.ServerConfig{},
	)
	createTestUser(t, db, "user-a", "user-a", "user-a@example.com")
	token := issueTestToken(t, tokens, "user-a")

	request := httptest.NewRequest(http.MethodGet, "/api/v1/realtime/config", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("X-Forwarded-Proto", "https")
	request.Header.Set("X-Forwarded-Host", "ydf-ops.yonyougov.top")
	request.Header.Set("X-Forwarded-Prefix", "/securex-be/")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}

	var body struct {
		Data struct {
			SignalingURL string `json:"signalingUrl"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	expected := "wss://ydf-ops.yonyougov.top/securex-be/api/v1/realtime/ws"
	if body.Data.SignalingURL != expected {
		t.Fatalf("expected signaling url %q, got %q", expected, body.Data.SignalingURL)
	}
}

func TestRealtimeConfigFallsBackToConfiguredPublicBasePath(t *testing.T) {
	router, tokens, db := newAccessControlRouterWithServerConfig(
		t,
		config.ServerConfig{PublicBasePath: "/securex-be"},
	)
	createTestUser(t, db, "user-a", "user-a", "user-a@example.com")
	token := issueTestToken(t, tokens, "user-a")

	request := httptest.NewRequest(http.MethodGet, "/api/v1/realtime/config", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("X-Forwarded-Proto", "https")
	request.Header.Set("X-Forwarded-Host", "ydf-ops.yonyougov.top")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}

	var body struct {
		Data struct {
			SignalingURL string `json:"signalingUrl"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	expected := "wss://ydf-ops.yonyougov.top/securex-be/api/v1/realtime/ws"
	if body.Data.SignalingURL != expected {
		t.Fatalf("expected signaling url %q, got %q", expected, body.Data.SignalingURL)
	}
}
