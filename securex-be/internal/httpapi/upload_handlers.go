package httpapi

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
)

func (h *Handler) startFileUpload(c *gin.Context) {
	var req fileUploadStartRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}
	if req.TotalChunks <= 0 {
		RespondFailure(c, http.StatusBadRequest, "文件分片数量不正确")
		return
	}

	session := model.FileUploadSession{
		ID:          uuid.NewString(),
		UserID:      middleware.CurrentUserID(c),
		FolderID:    req.FolderID,
		Version:     normalizeVersion(req.Version),
		TotalChunks: req.TotalChunks,
	}
	if err := h.db.Create(&session).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "创建上传任务失败")
		return
	}

	RespondSuccess(c, http.StatusCreated, "上传任务已创建", gin.H{
		"upload":         session,
		"uploadedChunks": []int{},
	})
}

func (h *Handler) getFileUpload(c *gin.Context) {
	session, ok := h.findUploadSession(c)
	if !ok {
		return
	}

	chunks, err := h.uploadedChunks(*session)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "读取上传进度失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "上传进度已加载", gin.H{
		"upload":         session,
		"uploadedChunks": chunks,
	})
}

func (h *Handler) uploadFileChunk(c *gin.Context) {
	session, ok := h.findUploadSession(c)
	if !ok {
		return
	}

	index, err := strconv.Atoi(c.Param("index"))
	if err != nil || index < 0 || index >= session.TotalChunks {
		RespondFailure(c, http.StatusBadRequest, "文件分片序号不正确")
		return
	}

	relativePath := h.uploadChunkRelativePath(session.UserID, session.ID, index)
	cipherSize, _, err := h.fileStore.Save(relativePath, c.Request.Body)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存文件分片失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "文件分片已上传", gin.H{
		"index":      index,
		"cipherSize": cipherSize,
	})
}

func (h *Handler) completeFileUpload(c *gin.Context) {
	session, ok := h.findUploadSession(c)
	if !ok {
		return
	}

	var req fileUploadCompleteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	chunks, err := h.uploadedChunks(*session)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "读取上传进度失败")
		return
	}
	if len(chunks) != session.TotalChunks {
		RespondFailure(c, http.StatusConflict, "文件分片还没有全部上传完成")
		return
	}

	fileID := uuid.NewString()
	relativePath := filepath.Join(session.UserID, fmt.Sprintf("%s.bin", fileID))
	fullPath := h.fileStore.Resolve(relativePath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0o755); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "创建文件目录失败")
		return
	}

	output, err := os.Create(fullPath)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "创建密文文件失败")
		return
	}

	var cipherSize int64
	for index := 0; index < session.TotalChunks; index++ {
		chunkPath := h.fileStore.Resolve(h.uploadChunkRelativePath(session.UserID, session.ID, index))
		input, err := os.Open(chunkPath)
		if err != nil {
			_ = output.Close()
			_ = h.fileStore.Delete(fullPath)
			RespondFailure(c, http.StatusConflict, "文件分片还没有全部上传完成")
			return
		}
		written, copyErr := io.Copy(output, input)
		closeErr := input.Close()
		if copyErr != nil || closeErr != nil {
			_ = output.Close()
			_ = h.fileStore.Delete(fullPath)
			RespondFailure(c, http.StatusInternalServerError, "合并文件分片失败")
			return
		}
		cipherSize += written
	}
	if err := output.Close(); err != nil {
		_ = h.fileStore.Delete(fullPath)
		RespondFailure(c, http.StatusInternalServerError, "保存密文文件失败")
		return
	}

	record := model.StoredFile{
		ID:          fileID,
		UserID:      session.UserID,
		FolderID:    session.FolderID,
		Payload:     req.Payload,
		StoragePath: fullPath,
		CipherSize:  cipherSize,
		Version:     normalizeVersion(session.Version),
	}
	if err := h.db.Create(&record).Error; err != nil {
		_ = h.fileStore.Delete(fullPath)
		RespondFailure(c, http.StatusInternalServerError, "创建文件记录失败")
		return
	}

	for index := 0; index < session.TotalChunks; index++ {
		_ = h.fileStore.Delete(h.fileStore.Resolve(h.uploadChunkRelativePath(session.UserID, session.ID, index)))
	}
	_ = os.RemoveAll(h.fileStore.Resolve(filepath.Join("uploads", session.UserID, session.ID)))
	_ = h.db.Delete(session).Error

	RespondSuccess(c, http.StatusCreated, "文件已上传", gin.H{"file": record})
}

func (h *Handler) findUploadSession(c *gin.Context) (*model.FileUploadSession, bool) {
	var session model.FileUploadSession
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&session).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "上传任务不存在")
		return nil, false
	}
	return &session, true
}

func (h *Handler) uploadedChunks(session model.FileUploadSession) ([]int, error) {
	chunks := make([]int, 0, session.TotalChunks)
	for index := 0; index < session.TotalChunks; index++ {
		chunkPath := h.fileStore.Resolve(h.uploadChunkRelativePath(session.UserID, session.ID, index))
		if _, err := os.Stat(chunkPath); err == nil {
			chunks = append(chunks, index)
		} else if !os.IsNotExist(err) {
			return nil, err
		}
	}
	return chunks, nil
}

func (h *Handler) uploadChunkRelativePath(userID, uploadID string, index int) string {
	return filepath.Join("uploads", userID, uploadID, fmt.Sprintf("%06d.part", index))
}
