package httpapi

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/ligson/secure-x/securex-be/internal/apiresponse"
)

func RespondSuccess(c *gin.Context, httpCode int, message string, data any) {
	apiresponse.RespondSuccess(c, httpCode, message, data)
}

func RespondFailure(c *gin.Context, httpCode int, message string) {
	apiresponse.RespondFailure(c, httpCode, message)
}

func RespondOK(c *gin.Context, message string, data any) {
	apiresponse.RespondSuccess(c, http.StatusOK, message, data)
}
