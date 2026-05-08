#include "em_alg.h"
#include "hal/em_motor.h"

//移动方向
int moveX;
int moveY;
int moveZ;

//舵机角度
float angleA;
float angleB;
float angleC;
//夹爪绝对坐标
float  absoluteX;
float  absoluteY;
float  absoluteZ;

#define MIN(a, b) ((a) < (b) ? (a) : (b))

float square(float n) {
  return n * n;
}

float sgn(float num)
{
    if(num > 0) {
        return 1.0;
    } else if(num < 0) {
        return -1.0;
    } else {
        return 0.0;
    }
}

/**
 * @brief 输入绝对坐标、输出舵机角度
 * 
 * @param x 
 * @param y 
 * @param z 
 */
void inverse_operation(float x,float y,float z){
  //=-DEGREES(ATAN(D10/B10))*(72/28)+90
  angleA = -degrees(atan(z/x))*(72.0/28.0)+90.0;
  // Serial.printf("angleA = %f\n",angleA);

  //=180-69-(DEGREES( ACOS((135^2+(-SIGN(B15)*SQRT(B15^2+D15^2)-7-60)^2+(C15-65.5)^2-145^2)/(2*135*SQRT((-SIGN(B15)*SQRT(B15^2+D15^2)-7-60)^2+(C15-65.5)^2)))))-(DEGREES(ATAN((C15-65.5)/(-SIGN(B15)*SQRT(B15^2+D15^2)-7-60))))
  //DEGREES(ATAN((C15-65.5)/(-SIGN(B15)*SQRT(B15^2+D15^2)-7-60))))
  float temp1 = degrees(atan((y-65.5)/(-sgn(x)*sqrt(x*x+z*z)-7.0-60.0)));
  // Serial.printf("temp1 = %f\n",temp1);
  //DEGREES( ACOS((135^2+(-SIGN(B15)*SQRT(B15^2+D15^2)-7-60)^2+(C15-65.5)^2-145^2)/(2*135*SQRT((-SIGN(B15)*SQRT(B15^2+D15^2)-7-60)^2+(C15-65.5)^2))))
  float temp2 = degrees(acos((135.0*135.0+square(-sgn(x)*sqrt(x*x+z*z)-7.0-60.0)+square(y-65.5)-145.0*145.0)/(2.0*135.0*sqrt(square(-sgn(x)*sqrt(x*x+z*z)-7.0-60.0)+square(y-65.5)))));
  // Serial.printf("temp2 = %f\n",temp2);
  angleB = 180.0-69.0-temp2-temp1;
  // Serial.printf("angleB = %f\n",angleB);

  //=180-(83.5+(180-69-(temp2)-(temp1)-(DEGREES(ACOS((145^2+135^2-(-SIGN(B15)*SQRT(B15^2+D15^2)-67)^2-(C15-65.5)^2)/(2*145*135)))))
  float temp3 = degrees(acos((145.0*145.0+135.0*135.0-square(-sgn(x)*sqrt(x*x+z*z)-67.0)-square(y-65.5))/(2.0*145.0*135.0)));
  angleC =180.0-(83.5+(180.0-69.0-temp2-temp1)-temp3);
  // Serial.printf("angleC = %f\n",angleC);

  Serial.printf("angle=[%f,%f,%f]\n",angleA,angleB,angleC);
} 

/**
 * @brief 输入角度，输出绝对坐标
 * 
 * @param angleA 
 * @param angleB 
 * @param angleC 
 */
void alg_positive_operation(float angleA,float angleB,float angleC){
  float temp = -(135.0*cos(radians(111.0-angleB))+145.0*sin(radians((83.5+angleB-(180.0-angleC))-angleB+21.0))+67.0);
  
  //=COS(RADIANS((B8-90)/(72/28)))*-(135*COS(RADIANS(111-C8))+145*SIN(RADIANS((83.5+C8-(180-D8))-C8+21))+67)
  absoluteX = cos(radians((angleA-90.0)/(72.0/28.0)))*temp;
  // Serial.printf("x = %f\n",x);

  //=65.5+135*SIN(RADIANS(111-C8))-(145*COS(RADIANS((83.5+C8-(180-D8))-C8+21)))
  absoluteY = 65.5+135.0*sin(radians(111.0-angleB))-(145.0*cos(radians((83.5+angleB-(180.0-angleC))-angleB+21.0)));
  // Serial.printf("y = %f\n",y);

  //=-SIN(RADIANS((B8-90)/(72/28)))*-(135*COS(RADIANS(111-C8))+145*SIN(RADIANS((83.5+C8-(180-D8))-C8+21))+67)
  absoluteZ = -sin(radians((angleA-90.0)/(72.0/28.0)))*temp;
  // Serial.printf("z = %f\n",z);
  Serial.printf("coordinate=[%f,%f,%f]\n",absoluteX,absoluteY,absoluteZ);
}

/**
 * @brief 判断角度是否在可到达范围内
 * 
 * @param angleA 
 * @param angleB 
 * @param angleC 
 * @return true 
 * @return false 
 */
bool check_angle(int angleA,int angleB,int angleC){
  if(angleA < 0 || angleA > 180){
    Serial.printf("angleA error %d , must in 0<a<180\n",angleA);
    return false;
  }

  if(angleB < 0 || angleB > 85){
    Serial.printf("angleB error %d , must in 0<b<85\n",angleB);
    return false;
  }

  float angleCMin = 140-angleB;
  float angleCMax = MIN((196-angleB),180);
  if(angleC < angleCMin || angleC > angleCMax){
    Serial.printf("angleC error %d , must in %f<c<%f\n",angleC,angleCMin,angleCMax);
    return false;
  }
  return true;
}

/**
 * @brief 设置移动动作
 * 
 */
void alg_set_move_action(uint8_t *data){
  moveX = data[0];
  moveY = data[1];
  moveZ = data[2];
  if(moveX == 255)
    moveX = -1;
  if(moveY == 255)
    moveY = -1;
  if(moveZ == 255)
    moveZ = -1;
}

/**
 * @brief 根据动作运行舵机
 * 
 */
void alg_move_run(){
  float offset = 0.4;
  if(moveX == 0 && moveY == 0 && moveZ == 0){
    return;
  }
  if(moveX > 0)
    absoluteX = absoluteX + offset;
  else if(moveX < 0)
    absoluteX = absoluteX - offset;

  if(moveY > 0)
    absoluteY = absoluteY + offset;
  else if(moveY < 0)
    absoluteY = absoluteY - offset;

  if(moveZ > 0)
    absoluteZ = absoluteZ + offset;
  else if(moveZ < 0)
    absoluteZ = absoluteZ - offset;
  inverse_operation(absoluteX,absoluteY,absoluteZ);
  if(check_angle(angleA,angleB,angleC) == true){
    //TODO run
    em_motor_run_by_angle(angleA,angleB,angleC,0);
  }else{
    //TODO reset
    if(moveX > 0)
    absoluteX = absoluteX - offset;
    else if(moveX < 0)
      absoluteX = absoluteX + offset;

    if(moveY > 0)
      absoluteY = absoluteY - offset;
    else if(moveY < 0)
      absoluteY = absoluteY + offset;

    if(moveZ > 0)
      absoluteZ = absoluteZ - offset;
    else if(moveZ < 0)
      absoluteZ = absoluteZ + offset;
    }
}