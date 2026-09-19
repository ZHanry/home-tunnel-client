//go:build darwin && cgo

package state

/*
#cgo LDFLAGS: -framework Security -framework CoreFoundation
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static CFMutableDictionaryRef htQuery(const char *account) {
  CFMutableDictionaryRef query=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
  CFStringRef name=CFStringCreateWithCString(NULL,account,kCFStringEncodingUTF8);
  CFDictionarySetValue(query,kSecClass,kSecClassGenericPassword);
  CFDictionarySetValue(query,kSecAttrService,CFSTR("io.github.zhanry.home-tunnel.device"));
  CFDictionarySetValue(query,kSecAttrAccount,name); CFRelease(name);
  CFDictionarySetValue(query,kSecUseAuthenticationUI,kSecUseAuthenticationUIFail);
  if (geteuid()==0) {
    SecKeychainRef system=NULL;
    if(SecKeychainOpen("/Library/Keychains/System.keychain",&system)==errSecSuccess) {
      CFDictionarySetValue(query,kSecUseKeychain,system); CFRelease(system);
    }
  }
  return query;
}
static int htSave(const char *account,const void *data,int size) {
  CFMutableDictionaryRef query=htQuery(account);
  CFDataRef value=CFDataCreate(NULL,data,size);
  CFDictionarySetValue(query,kSecValueData,value); CFRelease(value);
  OSStatus status=SecItemAdd(query,NULL); CFRelease(query);
  return status==errSecDuplicateItem?0:status;
}
static int htRead(const char *account,void **output,int *size) {
  CFMutableDictionaryRef query=htQuery(account);
  CFDictionarySetValue(query,kSecReturnData,kCFBooleanTrue);
  CFDictionarySetValue(query,kSecMatchLimit,kSecMatchLimitOne);
  CFTypeRef value=NULL; OSStatus status=SecItemCopyMatching(query,&value); CFRelease(query);
  if(status!=errSecSuccess)return status;
  if(CFGetTypeID(value)!=CFDataGetTypeID()){CFRelease(value);return errSecDecode;}
  *size=(int)CFDataGetLength(value); *output=malloc(*size);
  if(!*output){CFRelease(value);return errSecAllocate;}
  memcpy(*output,CFDataGetBytePtr(value),*size); CFRelease(value);return 0;
}
static void htDelete(const char *account) {
  CFMutableDictionaryRef query=htQuery(account);SecItemDelete(query);CFRelease(query);
}
static void htFree(void *data,int size) { if(data){memset(data,0,size);free(data);} }
*/
import "C"

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"path/filepath"
	"strings"
	"unsafe"
)

func CredentialProtection() string { return "macOS Keychain" }

func protectCredential(plain, path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	key := sha256.Sum256([]byte(abs + "\x00" + plain))
	reference := hex.EncodeToString(key[:])
	account := C.CString(reference)
	defer C.free(unsafe.Pointer(account))
	data := C.CBytes([]byte(plain))
	defer C.htFree(data, C.int(len(plain)))
	if status := C.htSave(account, data, C.int(len(plain))); status != 0 {
		return "", fmt.Errorf("save device credential in Keychain: OSStatus %d", status)
	}
	return "keychain:" + reference, nil
}

func unprotectCredential(stored, _ string) (string, error) {
	if !strings.HasPrefix(stored, "keychain:") {
		return "", fmt.Errorf("credential belongs to a different operating system")
	}
	account := C.CString(strings.TrimPrefix(stored, "keychain:"))
	defer C.free(unsafe.Pointer(account))
	var data unsafe.Pointer
	var size C.int
	if status := C.htRead(account, &data, &size); status != 0 {
		return "", fmt.Errorf("unlock original macOS Keychain: OSStatus %d", status)
	}
	defer C.htFree(data, size)
	return string(C.GoBytes(data, size)), nil
}

func forgetCredential(stored, _ string) {
	if !strings.HasPrefix(stored, "keychain:") {
		return
	}
	account := C.CString(strings.TrimPrefix(stored, "keychain:"))
	defer C.free(unsafe.Pointer(account))
	C.htDelete(account)
}
