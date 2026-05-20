package main

import (
	"log"

	"github.com/ligson/secure-x/securex-be/internal/app"
)

func main() {
	server, err := app.NewServer()
	if err != nil {
		log.Fatalf("failed to create server: %v", err)
	}

	if err := server.Run(); err != nil {
		log.Fatalf("server stopped with error: %v", err)
	}
}
