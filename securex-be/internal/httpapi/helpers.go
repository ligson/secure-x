package httpapi

import (
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/model"
)

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

func normalizeOptionalID(value *string) *string {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func (h *Handler) ownedPasswordFolderID(userID string, folderID *string) (*string, bool, error) {
	normalizedID := normalizeOptionalID(folderID)
	if normalizedID == nil {
		return nil, true, nil
	}

	var count int64
	if err := h.db.Model(&model.Folder{}).
		Where("id = ? AND user_id = ?", *normalizedID, userID).
		Count(&count).Error; err != nil {
		return nil, false, err
	}

	return normalizedID, count > 0, nil
}

func (h *Handler) ownedFileFolderID(userID string, folderID *string) (*string, bool, error) {
	normalizedID := normalizeOptionalID(folderID)
	if normalizedID == nil {
		return nil, true, nil
	}

	var count int64
	if err := h.db.Model(&model.FileFolder{}).
		Where("id = ? AND user_id = ?", *normalizedID, userID).
		Count(&count).Error; err != nil {
		return nil, false, err
	}

	return normalizedID, count > 0, nil
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

	return false, nil
}

func (h *Handler) fileFolderInUse(userID, folderID string) (bool, error) {
	var childCount int64
	if err := h.db.Model(&model.FileFolder{}).
		Where("user_id = ? AND parent_folder_id = ?", userID, folderID).
		Count(&childCount).Error; err != nil {
		return false, err
	}
	if childCount > 0 {
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
