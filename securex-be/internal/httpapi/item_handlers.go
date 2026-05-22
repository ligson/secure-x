package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
)

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
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	folderID, ok, err := h.ownedPasswordFolderID(userID, req.FolderID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验密码分类失败")
		return
	}
	if !ok {
		RespondFailure(c, http.StatusBadRequest, "密码分类不存在或不属于当前用户")
		return
	}

	item := model.VaultItem{
		ID:       uuid.NewString(),
		UserID:   userID,
		FolderID: folderID,
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
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	var item model.VaultItem
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&item).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "item not found")
		return
	}

	userID := middleware.CurrentUserID(c)
	folderID, ok, err := h.ownedPasswordFolderID(userID, req.FolderID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验密码分类失败")
		return
	}
	if !ok {
		RespondFailure(c, http.StatusBadRequest, "密码分类不存在或不属于当前用户")
		return
	}

	item.FolderID = folderID
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
