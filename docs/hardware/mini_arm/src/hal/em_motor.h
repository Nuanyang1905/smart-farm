#ifndef _EM_MOTOR_H_
#define _EM_MOTOR_H_

#include <ESP32Servo.h>

#include "em_config.h"
#include "em_alg.h"

void em_motor_init();

void em_motor_run(uint8_t *angle);

void em_motor_run_by_angle(uint8_t angle1,uint8_t angle2,uint8_t angle3,uint8_t angle4);

/// 只更新位置，不动夹爪
void em_motor_move_position(uint8_t angle1,uint8_t angle2,uint8_t angle3);

#endif