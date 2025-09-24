package main

import (
	"os"
)

func main() {
	cli := NewCLICommands()
	if err := cli.Execute(); err != nil {
		os.Exit(1)
	}
}
