package main

import (
	"flag"
	"log"

	"github.com/ligson/secure-x/securex-be/internal/app"
)

func main() {
	configPath := flag.String("config", "", "path to securex-be YAML config file")
	flag.Parse()

	server, err := app.NewServer(*configPath)
	if err != nil {
		log.Fatalf("failed to create server: %v", err)
	}

	if err := server.Run(); err != nil {
		log.Fatalf("server stopped with error: %v", err)
	}
}
