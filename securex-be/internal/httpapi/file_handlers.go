package httpapi

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
)

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
	folderID, ok, err := h.ownedFileFolderID(userID, metadata.FolderID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验文件目录失败")
		return
	}
	if !ok {
		RespondFailure(c, http.StatusBadRequest, "文件目录不存在或不属于当前用户")
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
		FolderID:    folderID,
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
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	var file model.StoredFile
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&file).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "file not found")
		return
	}

	userID := middleware.CurrentUserID(c)
	folderID, ok, err := h.ownedFileFolderID(userID, req.FolderID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验文件目录失败")
		return
	}
	if !ok {
		RespondFailure(c, http.StatusBadRequest, "文件目录不存在或不属于当前用户")
		return
	}

	file.FolderID = folderID
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
