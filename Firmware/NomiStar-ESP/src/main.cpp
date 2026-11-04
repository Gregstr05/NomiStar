#include <stdio.h>
#include <iostream>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "sdkconfig.h"

#define BLINK_GPIO GPIO_NUM_8

#ifdef __cplusplus
extern "C" {
#endif


void app_main()
{
  gpio_reset_pin(BLINK_GPIO);
  gpio_set_direction(BLINK_GPIO, GPIO_MODE_OUTPUT);

  while(1)
  {
    std::cout << "LED: Off" << std::endl;
    gpio_set_level(BLINK_GPIO, 1);
    vTaskDelay(500 / portTICK_PERIOD_MS);
    
    
    std::cout << "LED: On" << std::endl;
    gpio_set_level(BLINK_GPIO, 0);
    vTaskDelay(500 / portTICK_PERIOD_MS);
  }
}

#ifdef __cplusplus
}
#endif