package httpapi

import (
	"slices"
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
		"nickname":            user.Nickname,
		"avatarPreset":        defaultAvatarPreset(user.AvatarPreset),
		"avatarUrl":           user.AvatarURL,
		"email":               user.Email,
		"kdfAlgorithm":        user.KDFAlgorithm,
		"masterKeySalt":       user.MasterKeySalt,
		"masterKeyIterations": user.MasterKeyIterations,
		"wrappedVaultKey":     user.WrappedVaultKey,
		"createdAt":           user.CreatedAt,
		"updatedAt":           user.UpdatedAt,
	}
}

func friendAliasResponse(alias model.FriendAlias) gin.H {
	return gin.H{
		"friendId":  alias.FriendID,
		"payload":   alias.Payload,
		"version":   alias.Version,
		"createdAt": alias.CreatedAt,
		"updatedAt": alias.UpdatedAt,
	}
}

var allowedAvatarPresets = map[string]struct{}{
	"sunrise": {},
	"forest":  {},
	"ocean":   {},
	"ember":   {},
	"violet":  {},
	"sky":     {},
	"stone":   {},
	"mint":    {},
	"orbit":   {},
	"shield":  {},
}

func defaultAvatarPreset(value string) string {
	normalized := strings.TrimSpace(value)
	if normalized == "" {
		return "sunrise"
	}
	if _, ok := allowedAvatarPresets[normalized]; ok {
		return normalized
	}
	return "sunrise"
}

func normalizeAvatarPreset(value string) string {
	normalized := strings.TrimSpace(value)
	if normalized == "" {
		return ""
	}
	if _, ok := allowedAvatarPresets[normalized]; ok {
		return normalized
	}
	return ""
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

func (h *Handler) passwordFolderIsDescendant(userID, folderID, candidateParentID string) (bool, error) {
	currentIDs := []string{folderID}
	visited := map[string]struct{}{}
	for len(currentIDs) > 0 {
		nextIDs := make([]string, 0)
		var children []model.Folder
		if err := h.db.Where("user_id = ? AND parent_folder_id IN ?", userID, currentIDs).Find(&children).Error; err != nil {
			return false, err
		}
		for _, child := range children {
			if child.ID == candidateParentID {
				return true, nil
			}
			if _, ok := visited[child.ID]; ok {
				continue
			}
			visited[child.ID] = struct{}{}
			nextIDs = append(nextIDs, child.ID)
		}
		currentIDs = nextIDs
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

func normalizeUniqueIDs(ids []string) []string {
	result := make([]string, 0, len(ids))
	seen := map[string]struct{}{}
	for _, raw := range ids {
		id := strings.TrimSpace(raw)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		result = append(result, id)
	}
	return result
}

func normalizeGroupMemberIDs(currentUserID string, memberIDs []string) []string {
	result := []string{currentUserID}
	seen := map[string]struct{}{currentUserID: {}}
	for _, raw := range memberIDs {
		id := strings.TrimSpace(raw)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		result = append(result, id)
	}
	return result
}

func uniqueWithout(ids []string, exclude string) []string {
	result := make([]string, 0, len(ids))
	for _, id := range normalizeUniqueIDs(ids) {
		if id == exclude {
			continue
		}
		result = append(result, id)
	}
	return result
}

func containsID(ids []string, target string) bool {
	for _, id := range ids {
		if id == target {
			return true
		}
	}
	return false
}

func diffIDs(current []string, next []string) (added []string, removed []string) {
	currentSet := map[string]struct{}{}
	nextSet := map[string]struct{}{}
	for _, id := range normalizeUniqueIDs(current) {
		currentSet[id] = struct{}{}
	}
	for _, id := range normalizeUniqueIDs(next) {
		nextSet[id] = struct{}{}
		if _, ok := currentSet[id]; !ok {
			added = append(added, id)
		}
	}
	for _, id := range normalizeUniqueIDs(current) {
		if _, ok := nextSet[id]; !ok {
			removed = append(removed, id)
		}
	}
	slices.Sort(added)
	slices.Sort(removed)
	return added, removed
}
