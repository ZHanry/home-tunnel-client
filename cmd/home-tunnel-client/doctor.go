package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/ZHanry/home-tunnel-client/internal/diagnostics"
)

func doctor(arguments []string, bundle bool) error {
	flags := flag.NewFlagSet("doctor", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	statePath := flags.String("state", defaultStatePath(), "state file")
	server := flags.String("server", "", "optional HTTPS server origin")
	agentPath := flags.String("agent", defaultAgentPath(), "managed Agent binary")
	jsonOutput := flags.Bool("json", false, "emit redacted JSON")
	output := flags.String("output", "home-tunnel-support-"+time.Now().UTC().Format("20060102T150405Z")+".zip", "support bundle destination")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected doctor arguments")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	report := diagnostics.Run(ctx, diagnostics.Options{StatePath: *statePath, Server: *server, AgentPath: *agentPath, ExpectedAgentHash: expectedAgentSHA256})
	if bundle {
		if err := diagnostics.WriteBundle(report, *output); err != nil {
			return err
		}
		fmt.Printf("Redacted support bundle: %s\n", *output)
		return nil
	}
	if *jsonOutput {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetIndent("", "  ")
		return encoder.Encode(report)
	}
	fmt.Printf("Home Tunnel %s · %s/%s\nCredential storage: %s\n", report.Version, report.OS, report.Architecture, report.CredentialStorage)
	for _, check := range report.Checks {
		fmt.Printf("[%s] %s: %s (%d ms)\n", check.Status, check.Name, check.Message, check.LatencyMS)
	}
	return nil
}
