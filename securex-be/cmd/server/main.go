package main

import (
	"flag"
	"log"

	"github.com/ligson/secure-x/securex-be/internal/app"
)

func main() {
	configPath := flag.String("config", "", "Secure X 后端 YAML 配置文件路径")
	flag.Parse()

	server, err := app.NewServer(*configPath)
	if err != nil {
		log.Fatalf("Secure X 后端初始化失败：%v", err)
	}

	if err := server.Run(); err != nil {
		log.Fatalf("Secure X 后端异常停止：%v", err)
	}
}
