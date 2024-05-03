package main

import (
	"log/slog"
	"net/http"
	"os"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	log.Info("Starting server", slog.Int("port", 8080))
	http.ListenAndServe(":8080", nil)
}
