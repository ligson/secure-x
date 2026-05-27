package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
)

func (h *Handler) listFolders(c *gin.Context) {
	var folders []model.Folder
	if err := h.db.Where("user_id = ?", middleware.CurrentUserID(c)).Order("updated_at desc").Find(&folders).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load categories")
		return
	}
	RespondSuccess(c, http.StatusOK, "categories loaded", gin.H{"folders": folders})
}

func (h *Handler) createFolder(c *gin.Context) {
	var req folderUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	parentFolderID, ok, err := h.ownedPasswordFolderID(userID, req.ParentFolderID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验父级分类失败")
		return
	}
	if !ok {
		RespondFailure(c, http.StatusBadRequest, "父级分类不存在或不属于当前用户")
		return
	}

	folder := model.Folder{
		ID:             uuid.NewString(),
		UserID:         userID,
		ParentFolderID: parentFolderID,
		Payload:        req.Payload,
		Version:        normalizeVersion(req.Version),
	}

	if err := h.db.Create(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to create category")
		return
	}

	RespondSuccess(c, http.StatusCreated, "category created", gin.H{"folder": folder})
}

func (h *Handler) updateFolder(c *gin.Context) {
	var req folderUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	var folder model.Folder
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&folder).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "category not found")
		return
	}

	userID := middleware.CurrentUserID(c)
	parentFolderID, ok, err := h.ownedPasswordFolderID(userID, req.ParentFolderID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验父级分类失败")
		return
	}
	if !ok {
		RespondFailure(c, http.StatusBadRequest, "父级分类不存在或不属于当前用户")
		return
	}
	if parentFolderID != nil && *parentFolderID == folder.ID {
		RespondFailure(c, http.StatusBadRequest, "父级分类不能选择当前分类")
		return
	}
	if parentFolderID != nil {
		descendant, err := h.passwordFolderIsDescendant(userID, folder.ID, *parentFolderID)
		if err != nil {
			RespondFailure(c, http.StatusInternalServerError, "校验分类层级失败")
			return
		}
		if descendant {
			RespondFailure(c, http.StatusBadRequest, "父级分类不能选择当前分类的子分类")
			return
		}
	}

	folder.ParentFolderID = parentFolderID
	folder.Payload = req.Payload
	folder.Version = normalizeVersion(req.Version)

	if err := h.db.Save(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to update category")
		return
	}

	RespondSuccess(c, http.StatusOK, "category updated", gin.H{"folder": folder})
}

func (h *Handler) deleteFolder(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var folder model.Folder
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), userID).First(&folder).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "category not found")
		return
	}

	inUse, err := h.folderInUse(userID, folder.ID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to inspect category dependencies")
		return
	}
	if inUse {
		RespondFailure(c, http.StatusConflict, "分类下还有密码或子分类，请先处理后再删除")
		return
	}

	if err := h.db.Delete(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to delete category")
		return
	}

	RespondSuccess(c, http.StatusOK, "category deleted", gin.H{})
}

func (h *Handler) listFileFolders(c *gin.Context) {
	var folders []model.FileFolder
	if err := h.db.Where("user_id = ?", middleware.CurrentUserID(c)).Order("updated_at desc").Find(&folders).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to load file folders")
		return
	}
	RespondSuccess(c, http.StatusOK, "file folders loaded", gin.H{"fileFolders": folders})
}

func (h *Handler) createFileFolder(c *gin.Context) {
	var req folderUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	userID := middleware.CurrentUserID(c)
	parentFolderID, ok, err := h.ownedFileFolderID(userID, req.ParentFolderID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验父级文件夹失败")
		return
	}
	if !ok {
		RespondFailure(c, http.StatusBadRequest, "父级文件夹不存在或不属于当前用户")
		return
	}

	folder := model.FileFolder{
		ID:             uuid.NewString(),
		UserID:         userID,
		ParentFolderID: parentFolderID,
		Payload:        req.Payload,
		Version:        normalizeVersion(req.Version),
	}

	if err := h.db.Create(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to create file folder")
		return
	}

	RespondSuccess(c, http.StatusCreated, "file folder created", gin.H{"fileFolder": folder})
}

func (h *Handler) updateFileFolder(c *gin.Context) {
	var req folderUpsertRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	var folder model.FileFolder
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), middleware.CurrentUserID(c)).First(&folder).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "file folder not found")
		return
	}

	userID := middleware.CurrentUserID(c)
	parentFolderID, ok, err := h.ownedFileFolderID(userID, req.ParentFolderID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "校验父级文件夹失败")
		return
	}
	if !ok {
		RespondFailure(c, http.StatusBadRequest, "父级文件夹不存在或不属于当前用户")
		return
	}
	if parentFolderID != nil && *parentFolderID == folder.ID {
		RespondFailure(c, http.StatusBadRequest, "父级文件夹不能选择当前文件夹")
		return
	}

	folder.ParentFolderID = parentFolderID
	folder.Payload = req.Payload
	folder.Version = normalizeVersion(req.Version)

	if err := h.db.Save(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to update file folder")
		return
	}

	RespondSuccess(c, http.StatusOK, "file folder updated", gin.H{"fileFolder": folder})
}

func (h *Handler) deleteFileFolder(c *gin.Context) {
	userID := middleware.CurrentUserID(c)
	var folder model.FileFolder
	if err := h.db.Where("id = ? AND user_id = ?", c.Param("id"), userID).First(&folder).Error; err != nil {
		RespondFailure(c, http.StatusNotFound, "file folder not found")
		return
	}

	inUse, err := h.fileFolderInUse(userID, folder.ID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to inspect file folder dependencies")
		return
	}
	if inUse {
		RespondFailure(c, http.StatusConflict, "file folder is not empty")
		return
	}

	if err := h.db.Delete(&folder).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "failed to delete file folder")
		return
	}

	RespondSuccess(c, http.StatusOK, "file folder deleted", gin.H{})
}
