#ifndef _EM_ALG_H_
#define _EM_ALG_H_

#include <math.h>
#include "em_config.h"

void alg_positive_operation(float angleA,float angleB,float angleC);

void alg_set_move_action(uint8_t *data);

void alg_move_run();

#endif