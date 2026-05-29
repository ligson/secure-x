package httpapi_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestLiveKitCallTokenRequiresConfiguredService(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	createTestUser(t, db, "user-a", "user-a", "user-a@example.com")
	createTestUser(t, db, "user-b", "user-b", "user-b@example.com")
	createTestFriendship(t, db, "user-a", "user-b")
	token := issueTestToken(t, tokens, "user-a")

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/calls/livekit-token", token, map[string]any{
		"peerUserId": "user-b",
		"callId":     "call-1",
		"media":      "video",
	}, http.StatusServiceUnavailable)
}

func TestLiveKitCallTokenRequiresRealtimePermission(t *testing.T) {
	router, tokens, db := newAccessControlRouterWithConfig(
		t,
		config.ServerConfig{},
		testLiveKitRealtimeConfig(),
	)
	createTestUser(t, db, "user-a", "user-a", "user-a@example.com")
	createTestUser(t, db, "user-c", "user-c", "user-c@example.com")
	token := issueTestToken(t, tokens, "user-a")

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/calls/livekit-token", token, map[string]any{
		"peerUserId": "user-c",
		"callId":     "call-1",
		"media":      "audio",
	}, http.StatusForbidden)
}

func TestLiveKitCallTokenForFriend(t *testing.T) {
	router, tokens, db := newAccessControlRouterWithConfig(
		t,
		config.ServerConfig{},
		testLiveKitRealtimeConfig(),
	)
	createTestUser(t, db, "user-a", "user-a", "user-a@example.com")
	createTestUser(t, db, "user-b", "user-b", "user-b@example.com")
	createTestFriendship(t, db, "user-a", "user-b")
	token := issueTestToken(t, tokens, "user-a")

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/calls/livekit-token",
		strings.NewReader(`{"peerUserId":"user-b","callId":"call-1","media":"video"}`),
	)
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}
	var body struct {
		Data struct {
			LiveKit struct {
				URL   string `json:"url"`
				Token string `json:"token"`
				Room  string `json:"room"`
				Media string `json:"media"`
			} `json:"livekit"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if body.Data.LiveKit.URL != "wss://rtc.secure-x.example" {
		t.Fatalf("unexpected livekit url: %s", body.Data.LiveKit.URL)
	}
	if body.Data.LiveKit.Token == "" {
		t.Fatal("expected non-empty livekit token")
	}
	if !strings.Contains(body.Data.LiveKit.Room, "call-1") {
		t.Fatalf("expected room to include call id, got %s", body.Data.LiveKit.Room)
	}
	if body.Data.LiveKit.Media != "video" {
		t.Fatalf("expected video media, got %s", body.Data.LiveKit.Media)
	}
}

func testLiveKitRealtimeConfig() config.RealtimeConfig {
	return config.RealtimeConfig{
		LiveKit: config.LiveKitConfig{
			Enabled:   true,
			URL:       "wss://rtc.secure-x.example",
			APIKey:    "dev-key",
			APISecret: "dev-secret",
			TurnMode:  "turn_tls_443",
		},
	}
}
