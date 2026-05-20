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
			apiresponse.RespondFailure(c, http.StatusUnauthorized, "missing authorization header")
			c.Abort()
			return
		}

		tokenString := strings.TrimSpace(strings.TrimPrefix(header, "Bearer"))
		if tokenString == "" {
			apiresponse.RespondFailure(c, http.StatusUnauthorized, "invalid authorization header")
			c.Abort()
			return
		}

		userID, err := tokens.Parse(tokenString)
		if err != nil {
			apiresponse.RespondFailure(c, http.StatusUnauthorized, "invalid token")
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
