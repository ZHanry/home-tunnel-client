package remotehost

func ValidEmergencyKey(key string) bool {
	return key == "X" || key == "Q" || key == "F12"
}

func (s *Service) SetEmergencyKey(key string) error {
	if !ValidEmergencyKey(key) {
		return ErrLocalApproval
	}
	return s.config.Store.update(func(state *diskState) error {
		state.EmergencyKey = key
		return nil
	})
}
