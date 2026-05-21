package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/apiresponse"
	"github.com/ligson/secure-x/securex-be/internal/auth"
)

const userIDKey = "userID"

func RequireAuth(tokens *auth.TokenManager) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" {
			apiresponse.RespondFailure(c, http.StatusUnauthorized, "请先登录")
			c.Abort()
			return
		}

		tokenString := strings.TrimSpace(strings.TrimPrefix(header, "Bearer"))
		if tokenString == "" {
			apiresponse.RespondFailure(c, http.StatusUnauthorized, "登录凭证格式不正确")
			c.Abort()
			return
		}

		userID, err := tokens.Parse(tokenString)
		if err != nil {
			apiresponse.RespondFailure(c, http.StatusUnauthorized, "登录状态已失效，请重新登录")
			c.Abort()
			return
		}

		c.Set(userIDKey, userID)
		c.Next()
	}
}

func CurrentUserID(c *gin.Context) string {
	value, _ := c.Get(userIDKey)
	userID, _ := value.(string)
	return userID
}
