package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
)

func (h *Handler) exportVault(c *gin.Context) {
	userID := middleware.CurrentUserID(c)

	var folders []model.Folder
	var fileFolders []model.FileFolder
	var items []model.VaultItem
	var files []model.StoredFile

	if err := h.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&folders).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load folders")
		return
	}
	if err := h.db.Where("user_id = ?", userID).Order("updated_at desc").Find(&fileFolders).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load file folders")
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
		"folders":     folders,
		"fileFolders": fileFolders,
		"items":       items,
		"files":       files,
	})
}
