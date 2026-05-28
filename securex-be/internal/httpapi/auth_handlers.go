package httpapi

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net/http"
	"path"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

const maxProfileAvatarBytes = 1024 * 1024

func (h *Handler) register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	req.Username = strings.TrimSpace(req.Username)
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.MasterKeyIterations < 100_000 {
		RespondFailure(c, http.StatusBadRequest, "主密钥派生迭代次数不能低于 100000")
		return
	}

	var existing model.User
	err := h.db.Where("username = ? OR email = ?", req.Username, req.Email).First(&existing).Error
	if err == nil {
		RespondFailure(c, http.StatusConflict, "用户名或邮箱已被使用")
		return
	}
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		RespondFailure(c, http.StatusInternalServerError, "检查账号是否存在失败")
		return
	}

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "处理登录密码失败")
		return
	}

	user := model.User{
		ID:                  uuid.NewString(),
		Username:            req.Username,
		Nickname:            req.Username,
		AvatarPreset:        defaultAvatarPreset(""),
		Email:               req.Email,
		PasswordHash:        string(passwordHash),
		KDFAlgorithm:        req.KDFAlgorithm,
		MasterKeySalt:       req.MasterKeySalt,
		MasterKeyIterations: req.MasterKeyIterations,
		WrappedVaultKey:     req.WrappedVaultKey,
	}

	if err := h.db.Create(&user).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "创建账号失败")
		return
	}

	token, err := h.tokens.Issue(user.ID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "生成登录会话失败")
		return
	}

	RespondSuccess(c, http.StatusCreated, "账号创建成功", gin.H{
		"token": token,
		"user":  userResponse(user),
	})
}

func (h *Handler) login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	var user model.User
	err := h.db.Where("username = ? OR email = ?", req.Identifier, strings.ToLower(req.Identifier)).First(&user).Error
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusInternalServerError, "登录服务暂时不可用，请稍后重试")
			return
		}
		RespondFailure(c, http.StatusUnauthorized, "用户名、邮箱或登录密码不正确")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		RespondFailure(c, http.StatusUnauthorized, "用户名、邮箱或登录密码不正确")
		return
	}

	token, err := h.tokens.Issue(user.ID)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "生成登录会话失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "登录成功", gin.H{
		"token": token,
		"user":  userResponse(user),
	})
}

func (h *Handler) me(c *gin.Context) {
	user, err := h.findUserByID(middleware.CurrentUserID(c))
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusInternalServerError, "加载用户信息失败，请稍后重试")
			return
		}
		RespondFailure(c, http.StatusNotFound, "用户不存在")
		return
	}

	RespondSuccess(c, http.StatusOK, "用户信息已加载", gin.H{"user": userResponse(*user)})
}

func (h *Handler) updateProfile(c *gin.Context) {
	var req updateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	user, err := h.findUserByID(middleware.CurrentUserID(c))
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusInternalServerError, "加载用户信息失败，请稍后重试")
			return
		}
		RespondFailure(c, http.StatusNotFound, "用户不存在")
		return
	}

	nickname := strings.TrimSpace(req.Nickname)
	if nickname != "" {
		user.Nickname = nickname
	}
	avatarPreset := normalizeAvatarPreset(req.AvatarPreset)
	avatarPresetProvided := strings.TrimSpace(req.AvatarPreset) != ""
	if avatarPresetProvided && avatarPreset == "" {
		RespondFailure(c, http.StatusBadRequest, "头像预设不存在")
		return
	}
	if avatarPresetProvided {
		user.AvatarPreset = avatarPreset
		user.AvatarURL = ""
	}
	if nickname == "" && !avatarPresetProvided {
		RespondFailure(c, http.StatusBadRequest, "请至少修改昵称或头像")
		return
	}
	if err := h.db.Save(user).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "更新个人信息失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "个人信息已更新", gin.H{"user": userResponse(*user)})
}

func (h *Handler) uploadProfileAvatar(c *gin.Context) {
	user, err := h.findUserByID(middleware.CurrentUserID(c))
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusInternalServerError, "加载用户信息失败，请稍后重试")
			return
		}
		RespondFailure(c, http.StatusNotFound, "用户不存在")
		return
	}

	fileHeader, err := c.FormFile("avatar")
	if err != nil {
		RespondFailure(c, http.StatusBadRequest, "请选择要上传的头像图片")
		return
	}
	if fileHeader.Size <= 0 || fileHeader.Size > maxProfileAvatarBytes {
		RespondFailure(c, http.StatusBadRequest, "头像图片不能超过 1MB")
		return
	}

	ext := normalizedAvatarExt(fileHeader.Filename, fileHeader.Header.Get("Content-Type"))
	if ext == "" {
		RespondFailure(c, http.StatusBadRequest, "头像仅支持 jpg、png 或 webp 图片")
		return
	}

	source, err := fileHeader.Open()
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "读取头像文件失败")
		return
	}
	defer source.Close()
	content, err := io.ReadAll(source)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "读取头像文件失败")
		return
	}
	if len(content) == 0 || len(content) > maxProfileAvatarBytes {
		RespondFailure(c, http.StatusBadRequest, "头像图片不能超过 1MB")
		return
	}
	ext = normalizedAvatarExt(fileHeader.Filename, http.DetectContentType(content))
	if ext == "" {
		RespondFailure(c, http.StatusBadRequest, "头像仅支持 jpg、png 或 webp 图片")
		return
	}

	fileName := fmt.Sprintf("%s%s", uuid.NewString(), ext)
	relativePath := filepath.Join("avatars", user.ID, fileName)
	if _, _, err := h.fileStore.Save(relativePath, bytes.NewReader(content)); err != nil {
		RespondFailure(c, http.StatusInternalServerError, "保存头像文件失败")
		return
	}

	oldAvatarURL := user.AvatarURL
	user.AvatarURL = path.Join("api/v1/avatars", user.ID, fileName)
	if user.AvatarPreset == "" {
		user.AvatarPreset = defaultAvatarPreset("")
	}
	if err := h.db.Save(user).Error; err != nil {
		_ = h.fileStore.Delete(h.fileStore.Resolve(relativePath))
		RespondFailure(c, http.StatusInternalServerError, "更新头像失败")
		return
	}
	if oldRelativePath := avatarStoragePathFromURL(user.ID, oldAvatarURL); oldRelativePath != "" {
		_ = h.fileStore.Delete(h.fileStore.Resolve(oldRelativePath))
	}

	RespondSuccess(c, http.StatusOK, "头像已更新", gin.H{"user": userResponse(*user)})
}

func (h *Handler) serveAvatar(c *gin.Context) {
	userID := strings.TrimSpace(c.Param("userID"))
	filename := strings.TrimSpace(c.Param("filename"))
	if userID == "" || filename == "" || filename != filepath.Base(filename) {
		RespondFailure(c, http.StatusBadRequest, "头像路径不正确")
		return
	}
	if normalizedAvatarExt(filename, "") == "" {
		RespondFailure(c, http.StatusBadRequest, "头像格式不正确")
		return
	}

	c.Header("Cache-Control", "public, max-age=86400")
	c.File(h.fileStore.Resolve(filepath.Join("avatars", userID, filename)))
}

func normalizedAvatarExt(filename string, contentType string) string {
	switch strings.ToLower(strings.TrimSpace(contentType)) {
	case "image/jpeg", "image/jpg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	}
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".jpg", ".jpeg":
		return ".jpg"
	case ".png", ".webp":
		return ext
	default:
		return ""
	}
}

func avatarStoragePathFromURL(userID string, avatarURL string) string {
	cleanURL := strings.Trim(strings.TrimSpace(avatarURL), "/")
	prefix := path.Join("api/v1/avatars", userID)
	if cleanURL == "" || !strings.HasPrefix(cleanURL, prefix+"/") {
		return ""
	}
	filename := path.Base(cleanURL)
	if filename == "." || filename == "/" || filename == "" || filename != filepath.Base(filename) {
		return ""
	}
	return filepath.Join("avatars", userID, filename)
}

func (h *Handler) changePassword(c *gin.Context) {
	var req changePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	user, err := h.findUserByID(middleware.CurrentUserID(c))
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusInternalServerError, "加载用户信息失败，请稍后重试")
			return
		}
		RespondFailure(c, http.StatusNotFound, "用户不存在")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.CurrentPassword)); err != nil {
		RespondFailure(c, http.StatusUnauthorized, "当前登录密码不正确")
		return
	}

	if req.CurrentPassword == req.NewPassword {
		RespondFailure(c, http.StatusBadRequest, "新登录密码不能和当前登录密码相同")
		return
	}

	passwordHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		RespondFailure(c, http.StatusInternalServerError, "处理新登录密码失败")
		return
	}

	if err := h.db.Model(&model.User{}).
		Where("id = ?", user.ID).
		Update("password_hash", string(passwordHash)).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "更新登录密码失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "登录密码已修改", gin.H{})
}

func (h *Handler) changeUnlockPassword(c *gin.Context) {
	var req changeUnlockPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	if req.MasterKeyIterations < 100_000 {
		RespondFailure(c, http.StatusBadRequest, "密钥派生迭代次数不能低于 100000")
		return
	}

	user, err := h.findUserByID(middleware.CurrentUserID(c))
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			RespondFailure(c, http.StatusInternalServerError, "加载用户信息失败，请稍后重试")
			return
		}
		RespondFailure(c, http.StatusNotFound, "用户不存在")
		return
	}

	user.KDFAlgorithm = req.KDFAlgorithm
	user.MasterKeySalt = req.MasterKeySalt
	user.MasterKeyIterations = req.MasterKeyIterations
	user.WrappedVaultKey = req.WrappedVaultKey

	if err := h.db.Save(user).Error; err != nil {
		RespondFailure(c, http.StatusInternalServerError, "更新解锁密码配置失败")
		return
	}

	RespondSuccess(c, http.StatusOK, "解锁密码已修改", gin.H{"user": userResponse(*user)})
}
