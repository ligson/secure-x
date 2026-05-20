package httpapi

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/auth"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"github.com/ligson/secure-x/securex-be/internal/storage"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type Handler struct {
	db        *gorm.DB
	tokens    *auth.TokenManager
	fileStore *storage.FileStore
}

type registerRequest struct {
	Username            string `json:"username" binding:"required"`
	Email               string `json:"email" binding:"required,email"`
	Password            string `json:"password" binding:"required,min=8"`
	KDFAlgorithm        string `json:"kdfAlgorithm" binding:"required"`
	MasterKeySalt       string `json:"masterKeySalt" binding:"required"`
	MasterKeyIterations int    `json:"masterKeyIterations" binding:"required"`
	WrappedVaultKey     string `json:"wrappedVaultKey" binding:"required"`
}

type loginRequest struct {
	Identifier string `json:"identifier" binding:"required"`
	Password   string `json:"password" binding:"required"`
}

type folderUpsertRequest struct {
	ParentFolderID *string `json:"parentFolderId"`
	Payload        string  `json:"payload" binding:"required"`
	Version        int     `json:"version"`
}

type itemUpsertRequest struct {
	FolderID *string `json:"folderId"`
	Kind     string  `json:"kind" binding:"required"`
	Payload  string  `json:"payload" binding:"required"`
	Version  int     `json:"version"`
}

type fileMetadataRequest struct {
	FolderID *string `json:"folderId"`
	Payload  string  `json:"payload" binding:"required"`
	Version  int     `json:"version"`
}

func NewRouter(db *gorm.DB, tokens *auth.TokenManager, fileStore *storage.FileStore) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)

	handler := &Handler{
		db:        db,
		tokens:    tokens,
		fileStore: fileStore,
	}

	router := gin.Default()
	router.GET("/healthz", func(c *gin.Context) {
		RespondSuccess(c, http.StatusOK, "ok", gin.H{"status": "ok"})
	})

	v1 := router.Group("/api/v1")
	{
		authGroup := v1.Group("/auth")
		authGroup.POST("/register", handler.register)
		authGroup.POST("/login", handler.login)
		authGroup.GET("/me", middleware.RequireAuth(tokens), handler.me)

		protected := v1.Group("/")
		protected.Use(middleware.RequireAuth(tokens))
		protected.GET("/sync/export", handler.exportVault)

		protected.GET("/folders", handler.listFolders)
		protected.POST("/folders", handler.createFolder)
		protected.PUT("/folders/:id", handler.updateFolder)
		protected.DELETE("/folders/:id", handler.deleteFolder)

		protected.GET("/items", handler.listItems)
		protected.POST("/items", handler.createItem)
		protected.PUT("/items/:id", handler.updateItem)
		protected.DELETE("/items/:id", handler.deleteItem)

		protected.GET("/files", handler.listFiles)
		protected.GET("/files/:id", handler.getFileMetadata)
		protected.POST("/files", handler.uploadFile)
		protected.PUT("/files/:id", handler.updateFileMetadata)
		protected.GET("/files/:id/download", handler.downloadFile)
		protected.DELETE("/files/:id", handler.deleteFile)
	}

	return router
}

func (h *Handler) register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, err.Error())
		return
	}

	req.Username = strings.TrimSpace(req.Username)
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.MasterKeyIterations < 100_000 {
		RespondFailure(c, http.StatusBadRequest, "masterKeyIterations must be at least 100000")
		return
	}

	var existing model.User
	err := h.db.Where("username = ? OR email = ?", req.Username, req.Email).First(&existing).Error
	if err == nil {
		RespondFailure(c, http.StatusConflict, "user already exists")
		return
	}
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		RespondFailure(c, http.StatusInternalServerError, "failed to check user")
		return
	}

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to hash password")
		return
	}

	user := model.User{
		ID:                  uuid.NewString(),
		Username:            req.Username,
		Email:               req.Email,
		PasswordHash:        string(passwordHash),
		KDFAlgorithm:        req.KDFAlgorithm,
		MasterKeySalt:       req.MasterKeySalt,
		MasterKeyIterations: req.MasterKeyIterations,
		WrappedVaultKey:     req.WrappedVaultKey,
	}

	if err := h.db.Create(&user).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to create user")
		return
	}

	token, err := h.tokens.Issue(user.ID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to issue token")
		return
	}

	RespondSuccess(c, http.StatusCreated, "user created", gin.H{
		"token": token,
		"user":  userResponse(user),
	})
}

func (h *Handler) login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, err.Error())
		return
	}

	var user model.User
	err := h.db.Where("username = ? OR email = ?", req.Identifier, strings.ToLower(req.Identifier)).First(&user).Error
	if err != nil {
		RespondFailure(c, http.StatusUnauthorized, "invalid credentials")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		RespondFailure(c, http.StatusUnauthorized, "invalid credentials")
		return
	}

	token, err := h.tokens.Issue(user.ID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to issue token")
		return
	}

	RespondSuccess(c, http.StatusOK, "login successful", gin.H{
		"token": token,
		"user":  userResponse(user),
	})
}

func (h *Handler) me(c *gin.Context) {
	user, err := h.findUserByID(middleware.CurrentUserID(c))
	if err != nil {
		RespondFailure(c, http.StatusNotFound, "user not found")
		return
	}

	RespondSuccess(c, http.StatusOK, "user loaded", gin.H{"user": userResponse(*user)})
}

func (h *Handler) exportVault(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	var folders []model.Folder
	var items []model.VaultItem
	var files []model.StoredFile

	if err := h.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&folders).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load folders")
		return
	}
	if err := h.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&items).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load items")
		return
	}
	if err := h.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&files).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load files")
		return
	}

	RespondSuccess(c, http.StatusOK, "vault exported", gin.H{
		"folders": folders,
		"items":   items,
		"files":   files,
	})
}

func (h *Handler) listFolders(c *gin.Context) {
	var folders []model.Folder
	if err := h.db.Where("user_id = ?", middleware.CurrentUserID(c)).Order("updated_at desc").Find(&folders).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load folders")
		return
	}
	RespondSuccess(c, http.StatusOK, "folders loaded", gin.H{"folders": folders})
}

func (h *Handler) createFolder(c *gin.Context) {
	var req folderUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, err.Error())
		return
	}

	folder := model.Folder{
		ID:             uuid.NewString(),
		UserID:         middleware.CurrentUserID(c),
		ParentFolderID: req.ParentFolderID,
		Payload:        req.Payload,
		Version:        normalizeVersion(req.Version),
	}

	if err := h.db.Create(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to create folder")
		return
	}

	RespondSuccess(c, http.StatusCreated, "folder created", gin.H{"folder": folder})
}

func (h *Handler) updateFolder(c *gin.Context) {
	var req folderUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, err.Error())
		return
	}

	var folder model.Folder
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&folder).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "folder not found")
		return
	}

	folder.ParentFolderID = req.ParentFolderID
	folder.Payload = req.Payload
	folder.Version = normalizeVersion(req.Version)

	if err := h.db.Save(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to update folder")
		return
	}

	RespondSuccess(c, http.StatusOK, "folder updated", gin.H{"folder": folder})
}

func (h *Handler) deleteFolder(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var folder model.Folder
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), userID).First(&folder).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "folder not found")
		return
	}

	inUse, err := h.folderInUse(userID, folder.ID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to inspect folder dependencies")
		return
	}
	if inUse {
		RespondFailure(c, http.StatusConflict, "folder is not empty")
		return
	}

	if err := h.db.Delete(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to delete folder")
		return
	}

	RespondSuccess(c, http.StatusOK, "folder deleted", gin.H{})
}

func (h *Handler) listItems(c *gin.Context) {
	var items []model.VaultItem
	if err := h.db.Where("user_id = ?", middleware.CurrentUserID(c)).Order("updated_at desc").Find(&items).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load items")
		return
	}
	RespondSuccess(c, http.StatusOK, "items loaded", gin.H{"items": items})
}

func (h *Handler) createItem(c *gin.Context) {
	var req itemUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, err.Error())
		return
	}

	item := model.VaultItem{
		ID:       uuid.NewString(),
		UserID:   middleware.CurrentUserID(c),
		FolderID: req.FolderID,
		Kind:     req.Kind,
		Payload:  req.Payload,
		Version:  normalizeVersion(req.Version),
	}

	if err := h.db.Create(&item).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to create item")
		return
	}

	RespondSuccess(c, http.StatusCreated, "item created", gin.H{"item": item})
}

func (h *Handler) updateItem(c *gin.Context) {
	var req itemUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, err.Error())
		return
	}

	var item model.VaultItem
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&item).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "item not found")
		return
	}

	item.FolderID = req.FolderID
	item.Kind = req.Kind
	item.Payload = req.Payload
	item.Version = normalizeVersion(req.Version)

	if err := h.db.Save(&item).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to update item")
		return
	}

	RespondSuccess(c, http.StatusOK, "item updated", gin.H{"item": item})
}

func (h *Handler) deleteItem(c *gin.Context) {
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).Delete(&model.VaultItem{}).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to delete item")
		return
	}

	RespondSuccess(c, http.StatusOK, "item deleted", gin.H{})
}

func (h *Handler) listFiles(c *gin.Context) {
	var files []model.StoredFile
	if err := h.db.Where("user_id = ?", middleware.CurrentUserID(c)).Order("updated_at desc").Find(&files).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load files")
		return
	}
	RespondSuccess(c, http.StatusOK, "files loaded", gin.H{"files": files})
}

func (h *Handler) getFileMetadata(c *gin.Context) {
	var file model.StoredFile
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&file).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "file not found")
		return
	}
	RespondSuccess(c, http.StatusOK, "file loaded", gin.H{"file": file})
}

func (h *Handler) uploadFile(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	var metadata fileMetadataRequest
	if err := json.Unmarshal([]byte(c.PostForm("metadata")), &metadata); err != nil {
		RespondFailure(c, http.StatusBadRequest, "invalid metadata")
		return
	}

	fileHeader, err := c.FormFile("cipher_file")
	if err != nil {
		RespondFailure(c, http.StatusBadRequest, "missing cipher_file")
		return
	}

	fileReader, err := fileHeader.Open()
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to open upload")
		return
	}
	defer fileReader.Close()

	fileID := uuid.NewString()
	relativePath := filepath.Join(userID, fmt.Sprintf("%s.bin", fileID))
	cipherSize, fullPath, err := h.fileStore.Save(relativePath, fileReader)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to store file")
		return
	}

	record := model.StoredFile{
		ID:          fileID,
		UserID:      userID,
		FolderID:    metadata.FolderID,
		Payload:     metadata.Payload,
		StoragePath: fullPath,
		CipherSize:  cipherSize,
		Version:     normalizeVersion(metadata.Version),
	}

	if err := h.db.Create(&record).Error; err != nil {
		_ = h.fileStore.Delete(fullPath)
		RespondFailure(c, http.StatusInternalServerError, "failed to create file record")
		return
	}

	RespondSuccess(c, http.StatusCreated, "file uploaded", gin.H{"file": record})
}

func (h *Handler) updateFileMetadata(c *gin.Context) {
	var req fileMetadataRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, err.Error())
		return
	}

	var file model.StoredFile
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&file).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "file not found")
		return
	}

	file.FolderID = req.FolderID
	file.Payload = req.Payload
	file.Version = normalizeVersion(req.Version)

	if err := h.db.Save(&file).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to update file")
		return
	}

	RespondSuccess(c, http.StatusOK, "file updated", gin.H{"file": file})
}

func (h *Handler) downloadFile(c *gin.Context) {
	var file model.StoredFile
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&file).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "file not found")
		return
	}

	if _, err := os.Stat(file.StoragePath); err != nil {
		RespondFailure(c, http.StatusNotFound, "cipher file missing")
		return
	}

	cipherBytes, err := os.ReadFile(file.StoragePath)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to read cipher file")
		return
	}

	RespondSuccess(c, http.StatusOK, "file downloaded", gin.H{
		"fileId":           file.ID,
		"cipherTextBase64": base64.StdEncoding.EncodeToString(cipherBytes),
	})
}

func (h *Handler) deleteFile(c *gin.Context) {
	var file model.StoredFile
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&file).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "file not found")
		return
	}

	if err := h.db.Delete(&file).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to delete file")
		return
	}

	if err := h.fileStore.Delete(file.StoragePath); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to delete stored file")
		return
	}

	RespondSuccess(c, http.StatusOK, "file deleted", gin.H{})
}

func (h *Handler) findUserByID(userID string) (*model.User, error) {
	var user model.User
	if err := h.db.First(&user, "id = ?", userID).Error; err != nil {
		return nil, err
	}
	return &user, nil
}

func userResponse(user model.User) gin.H {
	return gin.H{
		"id":                  user.ID,
		"username":            user.Username,
		"email":               user.Email,
		"kdfAlgorithm":        user.KDFAlgorithm,
		"masterKeySalt":       user.MasterKeySalt,
		"masterKeyIterations": user.MasterKeyIterations,
		"wrappedVaultKey":     user.WrappedVaultKey,
		"createdAt":           user.CreatedAt,
		"updatedAt":           user.UpdatedAt,
	}
}

func normalizeVersion(version int) int {
	if version <= 0 {
		return 1
	}
	return version
}

func (h *Handler) folderInUse(userID, folderID string) (bool, error) {
	var childCount int64
	if err := h.db.Model(&model.Folder{}).
		Where("user_id = ? AND parent_folder_id = ?", userID, folderID).
		Count(&childCount).Error; err != nil {
		return false, err
	}
	if childCount > 0 {
		return true, nil
	}

	var itemCount int64
	if err := h.db.Model(&model.VaultItem{}).
		Where("user_id = ? AND folder_id = ?", userID, folderID).
		Count(&itemCount).Error; err != nil {
		return false, err
	}
	if itemCount > 0 {
		return true, nil
	}

	var fileCount int64
	if err := h.db.Model(&model.StoredFile{}).
		Where("user_id = ? AND folder_id = ?", userID, folderID).
		Count(&fileCount).Error; err != nil {
		return false, err
	}

	return fileCount > 0, nil
}
