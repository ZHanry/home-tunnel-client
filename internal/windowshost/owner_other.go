//go:build !windows

package windowshost

func AcquireOwner(string) (func(), bool, error)                { return func() {}, false, nil }
func AcquireServiceOwner(string, string) (func(), bool, error) { return func() {}, false, nil }
