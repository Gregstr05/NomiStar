#include <cstdio>
#include <cstring>

#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"

#include "driver/gpio.h"
#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "nvs_flash.h"

#include "wifi_provisioning/manager.h"
#include "wifi_provisioning/scheme_ble.h"
#include "protocomm_security2.h"

#include "cJSON.h"

extern "C" void app_main(void);

static const char *TAG = "NomiStar";

static const char sec2_salt[] = {
    0xd7, 0x4c, 0x6c, 0xfe, 0xd5, 0x83, 0x64, 0x7a, 0x95, 0xbe, 0x26, 0xf3, 0x9a, 0x4d, 0xdb, 0x9e
};

static const char sec2_verifier[] = {
    0x4b, 0x53, 0x90, 0x8c, 0xc7, 0x0e, 0xfd, 0x12, 0xde, 0xe5, 0x85, 0x21, 0x94, 0x59, 0x79, 0x10, 
    0xa9, 0x7c, 0xca, 0xf4, 0x2a, 0xda, 0xca, 0x66, 0xbd, 0x94, 0x60, 0x51, 0x8e, 0x92, 0x79, 0x56, 
    0xe8, 0xea, 0x7e, 0x96, 0xbd, 0x0c, 0xc5, 0xff, 0x50, 0x19, 0xb9, 0x76, 0xad, 0xa9, 0x65, 0x65, 
    0x11, 0x5b, 0xf0, 0x0a, 0xc3, 0x61, 0x9d, 0xdf, 0x5a, 0x2e, 0x76, 0xad, 0x7a, 0x21, 0xeb, 0xb3, 
    0x96, 0x90, 0x09, 0x47, 0x27, 0x34, 0x68, 0x71, 0x18, 0xe1, 0x91, 0xf4, 0xb9, 0x59, 0xfd, 0x44, 
    0x88, 0xf8, 0x10, 0x48, 0x8c, 0xef, 0x2d, 0xb0, 0x80, 0x6d, 0x52, 0x6d, 0x6f, 0x60, 0xbb, 0xf4, 
    0xa1, 0xa5, 0x17, 0x57, 0x3a, 0x52, 0x63, 0xab, 0xfa, 0x67, 0x1d, 0xdb, 0xc9, 0xef, 0xf6, 0x86, 
    0xc9, 0x6a, 0x8c, 0x0b, 0x93, 0x7f, 0x96, 0x84, 0xb0, 0xbd, 0xb8, 0x53, 0xca, 0x03, 0xfb, 0x7a, 
    0xcf, 0xe3, 0x6e, 0x78, 0xdb, 0xa6, 0xdd, 0x5c, 0xe1, 0xbc, 0xfa, 0xd6, 0xb7, 0x26, 0x2d, 0x6f, 
    0x07, 0xd5, 0xe9, 0x89, 0x31, 0xa2, 0x1f, 0x2e, 0x08, 0x51, 0x35, 0xa7, 0xd0, 0x89, 0x83, 0x68, 
    0xb2, 0x6f, 0xb5, 0xf1, 0xcf, 0xff, 0x6f, 0x2b, 0xa2, 0x30, 0x79, 0xc3, 0xf1, 0xeb, 0x2e, 0xb0, 
    0xf6, 0x4d, 0xd8, 0xdd, 0x7e, 0xdb, 0x2a, 0xf6, 0xfc, 0xe6, 0x97, 0xf4, 0x35, 0x98, 0x65, 0xc6, 
    0x8a, 0x77, 0xae, 0x3e, 0x7a, 0xc2, 0x1b, 0x12, 0xe2, 0xec, 0x48, 0x8b, 0x84, 0x7d, 0x58, 0x9e, 
    0x7f, 0x2e, 0x2a, 0xe8, 0x0a, 0xc8, 0x1a, 0x77, 0xcb, 0xb0, 0x0e, 0x69, 0x1e, 0xab, 0x61, 0xd4, 
    0x7c, 0x10, 0x18, 0x3d, 0x7c, 0x76, 0xf3, 0x07, 0xd0, 0xb4, 0x96, 0xd5, 0x70, 0x7b, 0xea, 0xab, 
    0x39, 0xab, 0xa0, 0xc4, 0x62, 0x7c, 0x5c, 0xd2, 0xe7, 0x79, 0xb7, 0x01, 0xaf, 0x0c, 0xfe, 0xb1, 
    0x7b, 0xb1, 0xc3, 0x3d, 0xb6, 0xbf, 0x4e, 0x1e, 0xe7, 0xde, 0x36, 0x7e, 0x2b, 0xa5, 0xdf, 0xe6, 
    0x1c, 0x85, 0x83, 0xf5, 0x7f, 0xce, 0xd2, 0x92, 0x95, 0xfa, 0xec, 0x01, 0x64, 0xed, 0x57, 0xab, 
    0x61, 0xe7, 0x12, 0xfc, 0x78, 0x0c, 0x8d, 0x32, 0xe3, 0x19, 0xa0, 0x47, 0x74, 0x52, 0xe9, 0x47, 
    0xa6, 0x6f, 0x35, 0x07, 0xcc, 0xd4, 0x4d, 0x00, 0xdc, 0xc5, 0xec, 0xd9, 0x15, 0x54, 0x37, 0x1a, 
    0x90, 0xbe, 0xad, 0x64, 0xa1, 0x1b, 0x88, 0xf0, 0x04, 0x73, 0x13, 0x9c, 0x52, 0x70, 0x05, 0x34, 
    0x25, 0xf8, 0xc7, 0x5f, 0x0b, 0x3f, 0xc2, 0x82, 0x58, 0xbb, 0xb7, 0x59, 0xcd, 0x82, 0x52, 0xea, 
    0x06, 0x8a, 0x65, 0x7c, 0x7b, 0x97, 0xf6, 0xeb, 0x63, 0xf6, 0x84, 0x51, 0x8c, 0xfd, 0x0c, 0x06, 
    0x49, 0xf6, 0x44, 0x80, 0xb1, 0x42, 0x23, 0x79, 0xcc, 0x05, 0xab, 0xea, 0x03, 0xdf, 0xae, 0xe5
};

// Must match lib/core/protocol.dart in the phone app
static const char *kServiceName  = "PROV_STAR";  // BLE device name
static const char *kSec2Username = "star";
static const char *kSec2Password = "nomi";
static const char *kFwVersion    = "0.1.0-esp";
static const int   kLedCount     = 45;  // 5 points x 9 LEDs

#define LED_GPIO GPIO_NUM_8  // super mini onboard LED, active LOW
#define LED_ON   0
#define LED_OFF  1

static volatile bool s_ready = false;  // LED solid once HTTP is up

static EventGroupHandle_t s_wifi_events;
#define WIFI_CONNECTED_BIT BIT0

static httpd_handle_t s_http   = nullptr;
static int s_brightness        = 255;

// Shared receive buffer; the esp_http_server worker task is
// single-threaded, so handlers never overlap.
static char s_io_buf[4096];

// Events
static void on_wifi_event(void *, esp_event_base_t base, int32_t id,
                          void *data) {
  if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
    esp_wifi_connect();
  } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
    ESP_LOGW(TAG, "Wi-Fi disconnected, reconnecting...");
    xEventGroupClearBits(s_wifi_events, WIFI_CONNECTED_BIT);
    esp_wifi_connect();
  } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
    auto *e = (ip_event_got_ip_t *)data;
    ESP_LOGI(TAG, "Got IP: " IPSTR, IP2STR(&e->ip_info.ip));
    xEventGroupSetBits(s_wifi_events, WIFI_CONNECTED_BIT);
  }
}

static void on_prov_event(void *, esp_event_base_t base, int32_t id,
                         void *data) {
  if (base != WIFI_PROV_EVENT) return;
  switch (id) {
    case WIFI_PROV_START:
      ESP_LOGI(TAG, "Provisioning started");
      break;
    case WIFI_PROV_CRED_RECV: {
      auto *cfg = (wifi_sta_config_t *)data;
      ESP_LOGI(TAG, "Credentials received, SSID: %.32s", cfg->ssid);
      break;
    }
    case WIFI_PROV_CRED_FAIL:
      ESP_LOGE(TAG, "Provisioning failed (wrong password or AP not "
                    "found)");
      break;
    case WIFI_PROV_CRED_SUCCESS:
      ESP_LOGI(TAG, "Provisioning successful");
      break;
    case WIFI_PROV_END:
      ESP_LOGI(TAG, "Provisioning service ended");
      break;
    default:
      break;
  }
}


// Status LED
static void led_task(void *) {
  gpio_reset_pin(LED_GPIO);
  gpio_set_direction(LED_GPIO, GPIO_MODE_OUTPUT);
  bool on = false;
  while (true) {
    if (s_ready) {
      gpio_set_level(LED_GPIO, LED_ON);
      vTaskDelay(pdMS_TO_TICKS(1000));
    } else {
      gpio_set_level(LED_GPIO, on ? LED_ON : LED_OFF);
      on = !on;
      vTaskDelay(pdMS_TO_TICKS(250));
    }
  }
}


// BLE provisioning (Security 2), then release the Bluetooth memory
static void provision_wifi(void) {
  wifi_prov_mgr_config_t cfg = {
    .scheme = wifi_prov_scheme_ble,
    .scheme_event_handler = WIFI_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM,
    .app_event_handler = WIFI_PROV_EVENT_HANDLER_NONE,
  };
  ESP_ERROR_CHECK(wifi_prov_mgr_init(cfg));

  bool provisioned = false;
  ESP_ERROR_CHECK(wifi_prov_mgr_is_provisioned(&provisioned));

  if (!provisioned) {
    ESP_LOGI(TAG, "Not provisioned - advertising as \"%s\"", kServiceName);

    // Static: must stay valid for the lifetime of the provisioning
    // service (which outlives this function).
    static protocomm_security2_params_t sec2_params = {
      .salt = sec2_salt,
      .salt_len = sizeof(sec2_salt),
      .verifier = sec2_verifier,
      .verifier_len = sizeof(sec2_verifier),
    };

    ESP_ERROR_CHECK(wifi_prov_mgr_start_provisioning(
        WIFI_PROV_SECURITY_2, &sec2_params, kServiceName, nullptr));

    wifi_prov_mgr_wait();
    wifi_prov_mgr_deinit();
  } else {
    ESP_LOGI(TAG, "Already provisioned");
    wifi_prov_mgr_deinit();
    ESP_ERROR_CHECK(esp_wifi_start());
  }
}

// HTTP helpers
static esp_err_t send_json(httpd_req_t *req, const char *body) {
  httpd_resp_set_type(req, "application/json");
  return httpd_resp_send(req, body, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t send_json_obj(httpd_req_t *req, cJSON *root) {
  char *s = cJSON_PrintUnformatted(root);
  cJSON_Delete(root);
  if (s == nullptr) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, nullptr);
    return ESP_FAIL;
  }
  esp_err_t err = send_json(req, s);
  free(s);
  return err;
}

static esp_err_t bad_request(httpd_req_t *req) {
  httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "malformed request");
  return ESP_FAIL;
}

// Reads the whole body (small requests only: play/stop/brightness).
static esp_err_t read_body(httpd_req_t *req, char *buf, size_t cap) {
  size_t remaining = req->content_len;
  if (remaining >= cap) return ESP_ERR_INVALID_SIZE;
  size_t total = 0;
  while (remaining > 0) {
    int n = httpd_req_recv(req, buf + total, remaining);
    if (n == HTTPD_SOCK_ERR_TIMEOUT) continue;
    if (n <= 0) return ESP_FAIL;
    total += (size_t)n;
    remaining -= (size_t)n;
  }
  buf[total] = '\0';
  return ESP_OK;
}

// Reads and discards the body (keeps the connection clean).
static void drain_body(httpd_req_t *req) {
  size_t remaining = req->content_len;
  while (remaining > 0) {
    size_t want = remaining < sizeof(s_io_buf) ? remaining
                                               : sizeof(s_io_buf);
    int n = httpd_req_recv(req, s_io_buf, want);
    if (n == HTTPD_SOCK_ERR_TIMEOUT) continue;
    if (n <= 0) return;
    remaining -= (size_t)n;
  }
}

// HTTP handlers - the app's contract (see StarProtocol in the app)
static esp_err_t info_get(httpd_req_t *req) {
  wifi_config_t wc = {};
  esp_wifi_get_config(WIFI_IF_STA, &wc);

  char ip_str[20] = "0.0.0.0";
  esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
  if (netif != nullptr) {
    esp_netif_ip_info_t ip_info = {};
    esp_netif_get_ip_info(netif, &ip_info);
    snprintf(ip_str, sizeof ip_str, "%s",
             ip4addr_ntoa((const ip4_addr_t *)&ip_info.ip));
  }

  wifi_ap_record_t ap = {};
  const bool have_ap = esp_wifi_sta_get_ap_info(&ap) == ESP_OK;

  cJSON *root = cJSON_CreateObject();
  cJSON_AddStringToObject(root, "fw_version", kFwVersion);
  cJSON_AddNullToObject(root, "stm_fw_version");
  cJSON_AddNumberToObject(root, "led_count", kLedCount);
  cJSON_AddNumberToObject(root, "uptime_s",
                          (double)(esp_timer_get_time() / 1000000LL));
  cJSON_AddNumberToObject(root, "free_heap",
                          (double)esp_get_free_heap_size());
  cJSON_AddStringToObject(root, "ip", ip_str);
  cJSON_AddStringToObject(root, "ssid", (const char *)wc.sta.ssid);
  if (have_ap) {
    cJSON_AddNumberToObject(root, "rssi", ap.rssi);
  } else {
    cJSON_AddNullToObject(root, "rssi");
  }
  return send_json_obj(req, root);
}

static esp_err_t status_get(httpd_req_t *req) {
  return send_json(req,
                   "{\"state\":\"idle\",\"file\":null,"
                   "\"frames_played\":0,\"buffer\":0,\"drops\":0,"
                   "\"fps_actual\":null}");
}

static esp_err_t animations_get(httpd_req_t *req) {
  // No SD-card manifest yet - the app shows "no animations".
  return send_json(req, "{\"animations\":[]}");
}

static esp_err_t animations_delete(httpd_req_t *req) {
  drain_body(req);
  return send_json(req, "{\"ok\":true,\"note\":\"storage is a stub\"}");
}

static esp_err_t play_post(httpd_req_t *req) {
  char buf[256];
  if (read_body(req, buf, sizeof buf) != ESP_OK) {
    return bad_request(req);
  }
  cJSON *j = cJSON_Parse(buf);
  if (j != nullptr) {
    const cJSON *n = cJSON_GetObjectItem(j, "name");
    if (cJSON_IsString(n)) {
      ESP_LOGI(TAG, "Play requested: \"%s\" (no storage yet)", n->valuestring);
    }
    cJSON_Delete(j);
  }
  return send_json(req, "{\"ok\":true,\"note\":\"stub - nothing to play\"}");
}

static esp_err_t stop_post(httpd_req_t *req) {
  drain_body(req);
  return send_json(req, "{\"ok\":true}");
}

static esp_err_t brightness_post(httpd_req_t *req) {
  char buf[128];
  if (read_body(req, buf, sizeof buf) != ESP_OK) {
    return bad_request(req);
  }
  cJSON *j = cJSON_Parse(buf);
  if (j == nullptr) return bad_request(req);
  const cJSON *v = cJSON_GetObjectItem(j, "value");
  if (cJSON_IsNumber(v)) {
    s_brightness = (int)v->valuedouble;
    if (s_brightness < 0) s_brightness = 0;
    if (s_brightness > 255) s_brightness = 255;
  }
  cJSON_Delete(j);
  char out[48];
  snprintf(out, sizeof out, "{\"ok\":true,\"value\":%d}", s_brightness);
  return send_json(req, out);
}

static esp_err_t upload_post(httpd_req_t *req) {
  // Nothing is stored yet - count the bytes and throw them away.
  size_t received = 0;
  size_t remaining = req->content_len;
  while (remaining > 0) {
    size_t want = remaining < sizeof(s_io_buf) ? remaining
                                                : sizeof(s_io_buf);
    int n = httpd_req_recv(req, s_io_buf, want);
    if (n == HTTPD_SOCK_ERR_TIMEOUT) continue;
    if (n <= 0) {
      httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "upload aborted");
      return ESP_FAIL;
    }
    received += (size_t)n;
    remaining -= (size_t)n;
  }
  ESP_LOGI(TAG, "Upload received and discarded (%u bytes)",
           (unsigned)received);
  char out[96];
  snprintf(out, sizeof out,
           "{\"ok\":true,\"received\":%u,"
           "\"note\":\"no storage yet, discarded\"}",
           (unsigned)received);
  return send_json(req, out);
}

static esp_err_t ota_post(httpd_req_t *req) {
  ESP_LOGI(TAG, "OTA: receiving %u bytes", (unsigned)req->content_len);
  const esp_partition_t *part = esp_ota_get_next_update_partition(nullptr);
  if (part == nullptr) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                        "no OTA partition");
    return ESP_FAIL;
  }
  esp_ota_handle_t handle;
  if (esp_ota_begin(part, OTA_SIZE_UNKNOWN, &handle) != ESP_OK) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                        "esp_ota_begin failed");
    return ESP_FAIL;
  }

  size_t remaining = req->content_len;
  while (remaining > 0) {
    size_t want = remaining < sizeof(s_io_buf) ? remaining
                                                : sizeof(s_io_buf);
    int n = httpd_req_recv(req, s_io_buf, want);
    if (n == HTTPD_SOCK_ERR_TIMEOUT) continue;
    if (n <= 0) {
      esp_ota_abort(handle);
      httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST,
                          "connection dropped");
      return ESP_FAIL;
    }
    if (esp_ota_write(handle, s_io_buf, n) != ESP_OK) {
      esp_ota_abort(handle);
      httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                          "esp_ota_write failed");
      return ESP_FAIL;
    }
    remaining -= (size_t)n;
  }

  if (esp_ota_end(handle) != ESP_OK) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                        "invalid image");
    return ESP_FAIL;
  }
  if (esp_ota_set_boot_partition(part) != ESP_OK) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                        "set_boot_partition failed");
    return ESP_FAIL;
  }

  ESP_LOGI(TAG, "OTA: success, rebooting");
  send_json(req, "{\"ok\":true}");
  vTaskDelay(pdMS_TO_TICKS(1000));  // let the response flush
  esp_restart();
  return ESP_OK;  // not reached
}

static esp_err_t reboot_post(httpd_req_t *req) {
  drain_body(req);
  send_json(req, "{\"ok\":true}");
  vTaskDelay(pdMS_TO_TICKS(1000));
  esp_restart();
  return ESP_OK;
}

static esp_err_t reprovision_post(httpd_req_t *req) {
  drain_body(req);
  send_json(req, "{\"ok\":true}");
  vTaskDelay(pdMS_TO_TICKS(1000));
  esp_wifi_stop();       // stop NVS writers before erasing
  nvs_flash_erase();     // wipes Wi-Fi credentials -> BLE mode on boot
  esp_restart();
  return ESP_OK;
}

static esp_err_t start_httpd(void) {
  httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
  ESP_ERROR_CHECK(httpd_start(&s_http, &cfg));

  static const httpd_uri_t routes[] = {
    {.uri = "/api/info", .method = HTTP_GET, .handler = info_get,
     .user_ctx = nullptr},
    {.uri = "/api/status", .method = HTTP_GET, .handler = status_get,
     .user_ctx = nullptr},
    {.uri = "/api/animations", .method = HTTP_GET,
     .handler = animations_get},
    {.uri = "/api/animations", .method = HTTP_DELETE,
     .handler = animations_delete},
    {.uri = "/api/play", .method = HTTP_POST, .handler = play_post},
    {.uri = "/api/stop", .method = HTTP_POST, .handler = stop_post},
    {.uri = "/api/brightness", .method = HTTP_POST,
     .handler = brightness_post},
    {.uri = "/api/upload", .method = HTTP_POST, .handler = upload_post},
    {.uri = "/api/ota", .method = HTTP_POST, .handler = ota_post},
    {.uri = "/api/reboot", .method = HTTP_POST, .handler = reboot_post},
    {.uri = "/api/reprovision", .method = HTTP_POST,
     .handler = reprovision_post},
  };
  for (const auto &r : routes) {
    ESP_ERROR_CHECK(httpd_register_uri_handler(s_http, &r));
  }
  return ESP_OK;
}

// Entry point
void app_main(void) {
  // Confirm the current app is healthy (OTA rollback support).
  esp_ota_mark_app_valid_cancel_rollback();

  esp_err_t ret = nvs_flash_init();
  if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
      ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    ESP_ERROR_CHECK(nvs_flash_init());
  }

  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  s_wifi_events = xEventGroupCreate();

  ESP_ERROR_CHECK(esp_event_handler_register(
      WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, nullptr));
  ESP_ERROR_CHECK(esp_event_handler_register(
      IP_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, nullptr));
  ESP_ERROR_CHECK(esp_event_handler_register(
      WIFI_PROV_EVENT, ESP_EVENT_ANY_ID, on_prov_event, nullptr));

  xTaskCreate(led_task, "led", 2048, nullptr, 5, nullptr);

  // Wi-Fi driver must be initialized before the provisioning manager.
  esp_netif_create_default_wifi_sta();
  wifi_init_config_t wcfg = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&wcfg));

  // Blocks until the device is provisioned (BLE) or, on later boots,
  // just checks NVS and starts the station directly.
  provision_wifi();

  ESP_LOGI(TAG, "Waiting for an IP address...");
  xEventGroupWaitBits(
      s_wifi_events, WIFI_CONNECTED_BIT, pdFALSE, pdFALSE,
      portMAX_DELAY);

  ESP_ERROR_CHECK(start_httpd());
  s_ready = true;  // LED goes solid: the hardware is ready
  ESP_LOGI(TAG, "NomiStar ready, firmware %s", kFwVersion);
}
