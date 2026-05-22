package httpapi_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/ligson/secure-x/securex-be/internal/auth"
	"github.com/ligson/secure-x/securex-be/internal/httpapi"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"github.com/ligson/secure-x/securex-be/internal/storage"
	"gorm.io/gorm"
)

func TestProtectedWritesRejectCrossUserFolderReferences(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	tokenB := issueTestToken(t, tokens, "user-b")

	passwordFolderA := model.Folder{
		ID:        "password-folder-a",
		UserID:    "user-a",
		Payload:   "cipher-folder",
		Version:   1,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	fileFolderA := model.FileFolder{
		ID:        "file-folder-a",
		UserID:    "user-a",
		Payload:   "cipher-file-folder",
		Version:   1,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	if err := db.Create(&passwordFolderA).Error; err != nil {
		t.Fatalf("create password folder: %v", err)
	}
	if err := db.Create(&fileFolderA).Error; err != nil {
		t.Fatalf("create file folder: %v", err)
	}

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/items", tokenB, map[string]any{
		"folderId": "password-folder-a",
		"kind":     "login",
		"payload":  "cipher-item",
		"version":  1,
	}, http.StatusBadRequest)

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/file-folders", tokenB, map[string]any{
		"parentFolderId": "file-folder-a",
		"payload":        "cipher-child-folder",
		"version":        1,
	}, http.StatusBadRequest)

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/file-uploads", tokenB, map[string]any{
		"folderId":    "file-folder-a",
		"version":     1,
		"totalChunks": 1,
	}, http.StatusBadRequest)
}

func TestFriendRequestsRequireApprovalBeforeFriendship(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	createTestUser(t, db, "user-a", "alice", "alice@example.com")
	createTestUser(t, db, "user-b", "bob", "bob@example.com")
	tokenA := issueTestToken(t, tokens, "user-a")
	tokenB := issueTestToken(t, tokens, "user-b")

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/friend-requests", tokenA, map[string]any{
		"identifier": "bob",
		"message":    "我是 Alice",
	}, http.StatusCreated)

	var friendshipCount int64
	if err := db.Model(&model.Friendship{}).Count(&friendshipCount).Error; err != nil {
		t.Fatalf("count friendships: %v", err)
	}
	if friendshipCount != 0 {
		t.Fatalf("friendship should not be created before approval, got %d", friendshipCount)
	}

	var request model.FriendRequest
	if err := db.Where(
		"requester_id = ? AND addressee_id = ? AND status = ?",
		"user-a",
		"user-b",
		"pending",
	).First(&request).Error; err != nil {
		t.Fatalf("find pending friend request: %v", err)
	}

	assertJSONStatus(t, router, http.MethodGet, "/api/v1/friend-requests", tokenB, nil, http.StatusOK)
	assertJSONStatus(
		t,
		router,
		http.MethodPut,
		"/api/v1/friend-requests/"+request.ID+"/accept",
		tokenB,
		nil,
		http.StatusOK,
	)

	for _, pair := range [][2]string{{"user-a", "user-b"}, {"user-b", "user-a"}} {
		var count int64
		if err := db.Model(&model.Friendship{}).
			Where("user_id = ? AND friend_id = ?", pair[0], pair[1]).
			Count(&count).Error; err != nil {
			t.Fatalf("count friendship pair: %v", err)
		}
		if count != 1 {
			t.Fatalf("expected friendship pair %s -> %s", pair[0], pair[1])
		}
	}
}

func TestRealtimeConfigComesFromHTTP(t *testing.T) {
	router, tokens, _ := newAccessControlRouter(t)
	token := issueTestToken(t, tokens, "user-a")

	request := httptest.NewRequest(http.MethodGet, "/api/v1/realtime/config", nil)
	request.Host = "secure-x.example"
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected %d, got %d: %s", http.StatusOK, response.Code, response.Body.String())
	}
	var body struct {
		Data struct {
			SignalingURL string `json:"signalingUrl"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode realtime config: %v", err)
	}
	if body.Data.SignalingURL != "ws://secure-x.example/api/v1/realtime/ws" {
		t.Fatalf("unexpected signaling url: %s", body.Data.SignalingURL)
	}
}

func TestDownloadRejectsCrossUserFileAccess(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	tokenB := issueTestToken(t, tokens, "user-b")

	cipherPath := filepath.Join(t.TempDir(), "cipher.bin")
	if err := writeTestFile(cipherPath, []byte("cipher data")); err != nil {
		t.Fatalf("write cipher file: %v", err)
	}
	fileA := model.StoredFile{
		ID:          "file-a",
		UserID:      "user-a",
		Payload:     "cipher-metadata",
		StoragePath: cipherPath,
		CipherSize:  int64(len("cipher data")),
		Version:     1,
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}
	if err := db.Create(&fileA).Error; err != nil {
		t.Fatalf("create file record: %v", err)
	}

	request := httptest.NewRequest(http.MethodGet, "/api/v1/files/file-a/download", nil)
	request.Header.Set("Authorization", "Bearer "+tokenB)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("expected %d, got %d: %s", http.StatusNotFound, response.Code, response.Body.String())
	}
}

func newAccessControlRouter(t *testing.T) (http.Handler, *auth.TokenManager, *gorm.DB) {
	t.Helper()

	db, err := gorm.Open(sqlite.Open(filepath.Join(t.TempDir(), "securex-test.db")), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	if err := db.AutoMigrate(
		&model.User{},
		&model.Folder{},
		&model.FileFolder{},
		&model.VaultItem{},
		&model.StoredFile{},
		&model.FileUploadSession{},
		&model.FriendRequest{},
		&model.Friendship{},
	); err != nil {
		t.Fatalf("migrate sqlite: %v", err)
	}

	fileStore, err := storage.NewFileStore(t.TempDir())
	if err != nil {
		t.Fatalf("create file store: %v", err)
	}
	tokens := auth.NewTokenManager("test-secret")
	router := httpapi.NewRouter(db, tokens, fileStore)

	return router, tokens, db
}

func createTestUser(t *testing.T, db *gorm.DB, id string, username string, email string) {
	t.Helper()

	user := model.User{
		ID:                  id,
		Username:            username,
		Email:               email,
		PasswordHash:        "hash",
		KDFAlgorithm:        "PBKDF2-SHA256",
		MasterKeySalt:       "salt",
		MasterKeyIterations: 100000,
		WrappedVaultKey:     "wrapped",
		CreatedAt:           time.Now(),
		UpdatedAt:           time.Now(),
	}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("create test user %s: %v", id, err)
	}
}

func issueTestToken(t *testing.T, tokens *auth.TokenManager, userID string) string {
	t.Helper()

	token, err := tokens.Issue(userID)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}
	return token
}

func assertJSONStatus(
	t *testing.T,
	router http.Handler,
	method string,
	path string,
	token string,
	payload map[string]any,
	expectedStatus int,
) {
	t.Helper()

	body, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	request := httptest.NewRequest(method, path, bytes.NewReader(body))
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	if response.Code != expectedStatus {
		t.Fatalf("expected %d, got %d: %s", expectedStatus, response.Code, response.Body.String())
	}
}

func writeTestFile(path string, content []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, content, 0o600)
}
