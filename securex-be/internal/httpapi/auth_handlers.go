package httpapi

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/ligson/secure-x/securex-be/internal/middleware"
	"github.com/ligson/secure-x/securex-be/internal/model"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

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
		RespondFailure(c, http.StatusNotFound, "用户不存在")
		return
	}

	RespondSuccess(c, http.StatusOK, "用户信息已加载", gin.H{"user": userResponse(*user)})
}

func (h *Handler) changePassword(c *gin.Context) {
	var req changePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondFailure(c, http.StatusBadRequest, bindErrorMessage(err))
		return
	}

	user, err := h.findUserByID(middleware.CurrentUserID(c))
	if err != nil {
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
