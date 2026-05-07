#include "em_config.h"
#include "hal/em_ble.h"
#include "hal/em_motor.h"
#include "hal/em_alg.h"

void setup()
{
  Serial.begin(115200);
  Serial.print("init_task\n");
  init_ble();
  em_motor_init();
}

void loop()
{
  // em_motor_run_by_angle(30,30,150,30);
  // delay(5000);
  // em_motor_run_by_angle(0,0,180,0);
  // delay(5000);
}
