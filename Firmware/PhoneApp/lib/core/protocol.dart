/// The app <-> ornament contract. Keep in sync with the ESP32 firmware.
class StarProtocol {

  /// Firmware must use a name starting with this prefix.
  static const String bleNamePrefix = "PROV_STAR";

  /// Must match the Security 2 credentials in the firmware
  /// (wifi_prov_mgr_start_provisioning(WIFI_PROV_SECURITY_2, ...)).
  static const String provUsername = "star";
  static const String provPassword = "nomi";

  // REST endpoints served by esp_http_server on the ESP32.
  static const String epInfo = "/api/info";
  static const String epStatus = "/api/status";
  static const String epAnimations = "/api/animations";
  static const String epPlay = "/api/play";
  static const String epStop = "/api/stop";
  static const String epBrightness = "/api/brightness";
  static const String epUpload = "/api/upload";
  static const String epOta = "/api/ota";
  static const String epReboot = "/api/reboot";
  static const String epReprovision = "/api/reprovision";
}
