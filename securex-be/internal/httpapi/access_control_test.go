package httpapi_test

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/glebarez/sqlite"
	"github.com/ligson/secure-x/securex-be/internal/auth"
	"github.com/ligson/secure-x/securex-be/internal/config"
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

func TestChatAttachmentDownloadRequiresAllowedUser(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	createTestUser(t, db, "user-a", "alice", "alice@example.com")
	createTestUser(t, db, "user-b", "bob", "bob@example.com")
	createTestUser(t, db, "user-c", "charlie", "charlie@example.com")
	createTestFriendship(t, db, "user-a", "user-b")
	tokenA := issueTestToken(t, tokens, "user-a")
	tokenB := issueTestToken(t, tokens, "user-b")
	tokenC := issueTestToken(t, tokens, "user-c")

	attachmentID := uploadChatAttachmentForTest(t, router, tokenA, []string{"user-b"})
	assertJSONStatus(t, router, http.MethodGet, "/api/v1/chat/attachments/"+attachmentID+"/download", tokenB, nil, http.StatusOK)
	assertJSONStatus(t, router, http.MethodGet, "/api/v1/chat/attachments/"+attachmentID+"/download", tokenC, nil, http.StatusForbidden)
}

func TestChatAttachmentUploadRejectsUnrelatedRecipients(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	createTestUser(t, db, "user-a", "alice", "alice@example.com")
	createTestUser(t, db, "user-c", "charlie", "charlie@example.com")
	tokenA := issueTestToken(t, tokens, "user-a")

	assertMultipartChatAttachmentStatus(t, router, tokenA, []string{"user-c"}, http.StatusForbidden)
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

	if response.Code != http.StatusForbidden {
		t.Fatalf("expected %d, got %d: %s", http.StatusForbidden, response.Code, response.Body.String())
	}
}

func TestSharedFileDownloadAllowsFriendOnly(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	createTestFriendship(t, db, "user-a", "user-b")
	tokenA := issueTestToken(t, tokens, "user-a")
	tokenB := issueTestToken(t, tokens, "user-b")
	tokenC := issueTestToken(t, tokens, "user-c")

	cipherPath := filepath.Join(t.TempDir(), "cipher.bin")
	if err := writeTestFile(cipherPath, []byte("cipher data")); err != nil {
		t.Fatalf("write cipher file: %v", err)
	}
	fileA := model.StoredFile{
		ID:             "file-shared",
		UserID:         "user-a",
		Payload:        "cipher-metadata",
		AllowedUserIDs: "[]",
		StoragePath:    cipherPath,
		CipherSize:     int64(len("cipher data")),
		Version:        1,
		CreatedAt:      time.Now(),
		UpdatedAt:      time.Now(),
	}
	if err := db.Create(&fileA).Error; err != nil {
		t.Fatalf("create file record: %v", err)
	}

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/files/file-shared/share", tokenA, map[string]any{
		"allowedUserIds": []string{"user-b"},
	}, http.StatusOK)
	assertJSONStatus(t, router, http.MethodGet, "/api/v1/files/file-shared/download", tokenB, nil, http.StatusOK)
	assertJSONStatus(t, router, http.MethodGet, "/api/v1/files/file-shared/download", tokenC, nil, http.StatusForbidden)
}

func TestFileShareRejectsUnrelatedRecipient(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	tokenA := issueTestToken(t, tokens, "user-a")

	cipherPath := filepath.Join(t.TempDir(), "cipher.bin")
	if err := writeTestFile(cipherPath, []byte("cipher data")); err != nil {
		t.Fatalf("write cipher file: %v", err)
	}
	fileA := model.StoredFile{
		ID:             "file-not-shared",
		UserID:         "user-a",
		Payload:        "cipher-metadata",
		AllowedUserIDs: "[]",
		StoragePath:    cipherPath,
		CipherSize:     int64(len("cipher data")),
		Version:        1,
		CreatedAt:      time.Now(),
		UpdatedAt:      time.Now(),
	}
	if err := db.Create(&fileA).Error; err != nil {
		t.Fatalf("create file record: %v", err)
	}

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/files/file-not-shared/share", tokenA, map[string]any{
		"allowedUserIds": []string{"user-c"},
	}, http.StatusForbidden)
}

func TestChatMessageDispatchRejectsUnauthorizedTargetDevice(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	createTestUser(t, db, "user-a", "alice", "alice@example.com")
	createTestUser(t, db, "user-b", "bob", "bob@example.com")
	tokenB := issueTestToken(t, tokens, "user-b")

	deviceA := model.ChatDevice{
		ID:              "device-a-1",
		UserID:          "user-a",
		Protocol:        "securex-e2ee-v1",
		ProtocolVersion: 1,
		PublicKey:       "pub-a",
		AppInstance:     "test-a",
		LastSeenAt:      time.Now(),
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}
	if err := db.Create(&deviceA).Error; err != nil {
		t.Fatalf("create chat device: %v", err)
	}

	assertJSONStatus(t, router, http.MethodPost, "/api/v1/chat/messages", tokenB, map[string]any{
		"messages": []map[string]any{
			{
				"recipientUserId":   "user-a",
				"recipientDeviceId": "device-a-1",
				"senderDeviceId":    "device-b-1",
				"protocol":          "securex-e2ee-v1",
				"payload":           "{\"cipher\":\"opaque\"}",
				"expiresInSeconds":  300,
			},
		},
	}, http.StatusForbidden)
}

func TestOnlyAdminCanDissolveGroup(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	createTestUser(t, db, "user-a", "alice", "alice@example.com")
	createTestUser(t, db, "user-b", "bob", "bob@example.com")
	tokenB := issueTestToken(t, tokens, "user-b")

	createTestGroup(t, db, "group-test", "user-a", []string{"user-a", "user-b"})

	assertJSONStatus(
		t,
		router,
		http.MethodPost,
		"/api/v1/groups/group-test/dissolve",
		tokenB,
		map[string]any{},
		http.StatusForbidden,
	)
}

func TestDissolveGroupRemovesAdminMembershipButKeepsMembersVisible(t *testing.T) {
	router, tokens, db := newAccessControlRouter(t)
	createTestUser(t, db, "user-a", "alice", "alice@example.com")
	createTestUser(t, db, "user-b", "bob", "bob@example.com")
	createTestUser(t, db, "user-c", "cindy", "cindy@example.com")
	tokenA := issueTestToken(t, tokens, "user-a")
	tokenB := issueTestToken(t, tokens, "user-b")

	createTestGroup(
		t,
		db,
		"group-test",
		"user-a",
		[]string{"user-a", "user-b", "user-c"},
	)

	assertJSONStatus(
		t,
		router,
		http.MethodPost,
		"/api/v1/groups/group-test/dissolve",
		tokenA,
		map[string]any{},
		http.StatusOK,
	)

	var adminMembershipCount int64
	if err := db.Model(&model.GroupMembership{}).
		Where("group_id = ? AND user_id = ?", "group-test", "user-a").
		Count(&adminMembershipCount).Error; err != nil {
		t.Fatalf("count admin membership: %v", err)
	}
	if adminMembershipCount != 0 {
		t.Fatalf("expected admin membership removed after dissolve, got %d", adminMembershipCount)
	}

	var room model.GroupRoom
	if err := db.Where("id = ?", "group-test").First(&room).Error; err != nil {
		t.Fatalf("find group room: %v", err)
	}
	if room.Status != "dissolved" {
		t.Fatalf("expected group status dissolved, got %s", room.Status)
	}

	request := httptest.NewRequest(http.MethodGet, "/api/v1/groups", nil)
	request.Header.Set("Authorization", "Bearer "+tokenB)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected %d, got %d: %s", http.StatusOK, response.Code, response.Body.String())
	}

	var body struct {
		Data struct {
			Groups []struct {
				ID          string `json:"id"`
				IsDissolved bool   `json:"isDissolved"`
			} `json:"groups"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode group list: %v", err)
	}
	if len(body.Data.Groups) != 1 {
		t.Fatalf("expected 1 dissolved group for remaining member, got %d", len(body.Data.Groups))
	}
	if body.Data.Groups[0].ID != "group-test" || !body.Data.Groups[0].IsDissolved {
		t.Fatalf("expected remaining member to see dissolved group, got %+v", body.Data.Groups[0])
	}
}

func newAccessControlRouter(t *testing.T) (http.Handler, *auth.TokenManager, *gorm.DB) {
	return newAccessControlRouterWithServerConfig(t, config.ServerConfig{})
}

func newAccessControlRouterWithServerConfig(
	t *testing.T,
	serverConfig config.ServerConfig,
) (http.Handler, *auth.TokenManager, *gorm.DB) {
	return newAccessControlRouterWithConfig(t, serverConfig, config.RealtimeConfig{})
}

func newAccessControlRouterWithConfig(
	t *testing.T,
	serverConfig config.ServerConfig,
	realtimeConfig config.RealtimeConfig,
) (http.Handler, *auth.TokenManager, *gorm.DB) {
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
		&model.GroupRoom{},
		&model.GroupMembership{},
		&model.GroupSnapshot{},
		&model.ChatArchive{},
		&model.ChatDevice{},
		&model.ChatQueuedEnvelope{},
		&model.ChatAttachment{},
	); err != nil {
		t.Fatalf("migrate sqlite: %v", err)
	}

	fileStore, err := storage.NewFileStore(t.TempDir())
	if err != nil {
		t.Fatalf("create file store: %v", err)
	}
	tokens := auth.NewTokenManager("test-secret")
	router := httpapi.NewRouter(db, tokens, fileStore, serverConfig, realtimeConfig)

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

func createTestGroup(t *testing.T, db *gorm.DB, groupID string, adminUserID string, memberIDs []string) {
	t.Helper()

	room := model.GroupRoom{
		ID:            groupID,
		CreatorUserID: adminUserID,
		AdminUserID:   adminUserID,
		Status:        "active",
		Version:       1,
		CreatedAt:     time.Now(),
		UpdatedAt:     time.Now(),
	}
	if err := db.Create(&room).Error; err != nil {
		t.Fatalf("create test group: %v", err)
	}
	for _, memberID := range memberIDs {
		membership := model.GroupMembership{
			ID:            memberID + "-" + groupID,
			GroupID:       groupID,
			UserID:        memberID,
			AddedByUserID: adminUserID,
			CreatedAt:     time.Now(),
			UpdatedAt:     time.Now(),
		}
		if err := db.Create(&membership).Error; err != nil {
			t.Fatalf("create test group membership: %v", err)
		}
	}
}

func createTestFriendship(t *testing.T, db *gorm.DB, userID string, friendID string) {
	t.Helper()

	pairs := [][2]string{{userID, friendID}, {friendID, userID}}
	for _, pair := range pairs {
		friendship := model.Friendship{
			ID:        pair[0] + "-" + pair[1],
			UserID:    pair[0],
			FriendID:  pair[1],
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
		if err := db.Create(&friendship).Error; err != nil {
			t.Fatalf("create test friendship: %v", err)
		}
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

func uploadChatAttachmentForTest(
	t *testing.T,
	router http.Handler,
	token string,
	allowedUserIDs []string,
) string {
	t.Helper()

	response := assertMultipartChatAttachmentStatus(t, router, token, allowedUserIDs, http.StatusOK)
	var decoded struct {
		Data struct {
			Attachment struct {
				ID string `json:"id"`
			} `json:"attachment"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("decode upload response: %v", err)
	}
	if decoded.Data.Attachment.ID == "" {
		t.Fatalf("upload response missing attachment id: %s", response.Body.String())
	}
	return decoded.Data.Attachment.ID
}

func assertMultipartChatAttachmentStatus(
	t *testing.T,
	router http.Handler,
	token string,
	allowedUserIDs []string,
	expectedStatus int,
) *httptest.ResponseRecorder {
	t.Helper()

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	metadata, err := json.Marshal(map[string]any{"allowedUserIds": allowedUserIDs})
	if err != nil {
		t.Fatalf("marshal metadata: %v", err)
	}
	if err := writer.WriteField("metadata", string(metadata)); err != nil {
		t.Fatalf("write metadata: %v", err)
	}
	part, err := writer.CreateFormFile("cipher_file", "cipher.bin")
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := io.Copy(part, bytes.NewReader([]byte("cipher-bytes"))); err != nil {
		t.Fatalf("write form file: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	request := httptest.NewRequest(http.MethodPost, "/api/v1/chat/attachments", &body)
	request.Header.Set("Authorization", "Bearer "+token)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != expectedStatus {
		t.Fatalf("upload chat attachment expected %d, got %d: %s", expectedStatus, response.Code, response.Body.String())
	}
	return response
}

func writeTestFile(path string, content []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, content, 0o600)
}
