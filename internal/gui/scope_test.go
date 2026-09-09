package gui

import (
	"testing"

	"github.com/ZHanry/home-tunnel-client/internal/model"
)

func TestLocalConnectionsRejectsOtherMachinesAndUnboundCache(t *testing.T) {
	items := []model.Connection{{ID: "local", DeviceID: "this"}, {ID: "remote", DeviceID: "other"}, {ID: "unbound"}}
	local := localConnections(items, "this")
	if len(local) != 1 || local[0].ID != "local" {
		t.Fatalf("local scope leaked another device: %#v", local)
	}
	if len(localConnections(items, "")) != 0 {
		t.Fatal("unenrolled computers must never display cached account resources")
	}
}
