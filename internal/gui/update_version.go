package gui

import (
	"fmt"
	"regexp"
	"strings"
)

var updateSemver = regexp.MustCompile(`^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$`)
var numericIdentifier = regexp.MustCompile(`^[0-9]+$`)

type updateVersion struct {
	core []string
	pre  []string
}

func parseUpdateVersion(value string) (updateVersion, error) {
	match := updateSemver.FindStringSubmatch(value)
	if match == nil {
		return updateVersion{}, fmt.Errorf("无效版本号 %q", value)
	}
	v := updateVersion{core: match[1:4]}
	if match[4] != "" {
		v.pre = strings.Split(match[4], ".")
	}
	for _, id := range v.pre {
		if numericIdentifier.MatchString(id) && len(id) > 1 && id[0] == '0' {
			return updateVersion{}, fmt.Errorf("无效预发布版本号")
		}
	}
	return v, nil
}

func compareNumericIdentifier(a, b string) int {
	if len(a) < len(b) {
		return -1
	}
	if len(a) > len(b) {
		return 1
	}
	return strings.Compare(a, b)
}

func compareUpdateVersions(a, b string) (int, error) {
	av, err := parseUpdateVersion(a)
	if err != nil {
		return 0, err
	}
	bv, err := parseUpdateVersion(b)
	if err != nil {
		return 0, err
	}
	for i := range av.core {
		if c := compareNumericIdentifier(av.core[i], bv.core[i]); c != 0 {
			return c, nil
		}
	}
	if len(av.pre) == 0 && len(bv.pre) == 0 {
		return 0, nil
	}
	if len(av.pre) == 0 {
		return 1, nil
	}
	if len(bv.pre) == 0 {
		return -1, nil
	}
	for i := 0; i < len(av.pre) && i < len(bv.pre); i++ {
		aa, bb := av.pre[i], bv.pre[i]
		an, bn := numericIdentifier.MatchString(aa), numericIdentifier.MatchString(bb)
		if an && !bn {
			return -1, nil
		}
		if !an && bn {
			return 1, nil
		}
		c := strings.Compare(aa, bb)
		if an && bn {
			c = compareNumericIdentifier(aa, bb)
		}
		if c != 0 {
			return c, nil
		}
	}
	if len(av.pre) < len(bv.pre) {
		return -1, nil
	}
	if len(av.pre) > len(bv.pre) {
		return 1, nil
	}
	return 0, nil
}
