// HOMEDESK: 旧版自动附加的测试品牌不作为用户设备名展示，服务端原始数据保留。
String homeDeskDeviceLabel(String name) {
  for (final suffix in [' · HomeDeskAcceptance', ' · HomeDest', ' · HomeDesk']) {
    if (name.endsWith(suffix) && name.length > suffix.length) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}
