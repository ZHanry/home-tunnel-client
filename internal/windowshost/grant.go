package windowshost

import "encoding/binary"

const grantBytes = 52

func EncodeGrant(session uint32, expires uint64) []byte {
	buffer := make([]byte, grantBytes)
	binary.LittleEndian.PutUint32(buffer[0:], 0x48544447)
	binary.LittleEndian.PutUint32(buffer[4:], 1)
	binary.LittleEndian.PutUint32(buffer[8:], session)
	binary.LittleEndian.PutUint64(buffer[12:], expires)
	return buffer
}

func GrantAccepts(buffer []byte, session uint32, now uint64) bool {
	if len(buffer) != grantBytes || binary.LittleEndian.Uint32(buffer[0:]) != 0x48544447 || binary.LittleEndian.Uint32(buffer[4:]) != 1 {
		return false
	}
	stored := binary.LittleEndian.Uint32(buffer[8:])
	expires := binary.LittleEndian.Uint64(buffer[12:])
	return stored != 0 && stored != 0xffffffff && stored == session && expires != 0 && now < expires
}
