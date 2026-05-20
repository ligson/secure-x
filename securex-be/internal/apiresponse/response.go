package apiresponse

import "github.com/gin-gonic/gin"

type Payload struct {
	Success  bool   `json:"success"`
	Message  string `json:"message"`
	HTTPCode int    `json:"httpCode"`
	Data     any    `json:"data"`
}

func Respond(c *gin.Context, httpCode int, success bool, message string, data any) {
	if data == nil {
		data = gin.H{}
	}

	c.JSON(httpCode, Payload{
		Success:  success,
		Message:  message,
		HTTPCode: httpCode,
		Data:     data,
	})
}

func RespondSuccess(c *gin.Context, httpCode int, message string, data any) {
	Respond(c, httpCode, true, message, data)
}

func RespondFailure(c *gin.Context, httpCode int, message string) {
	Respond(c, httpCode, false, message, gin.H{})
}
