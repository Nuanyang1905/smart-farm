#include "em_ble.h"
#include "em_motor.h"
#include "em_alg.h"

BLECharacteristic *pCharacteristic = NULL;
bool bleConnected = false;

bool get_ble_connect(){
    return bleConnected;
}

// Server回调函数声明
class bleServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *pServer)
    {
        bleConnected = true;
        Serial.println("现在有设备接入~");
    }

    void onDisconnect(BLEServer *pServer)
    {
        bleConnected = false;
        Serial.println("现在有设备断开连接~");
        // 在有设备接入后Advertising广播会被停止，所以要在设备断开连接时重新开启广播
        // 不然的话只有重启ESP32后才能重新搜索到
        pServer->startAdvertising(); // 该行效果同 BLEDevice::startAdvertising();
    }
};

class bleCharacteristicCallbacks : public BLECharacteristicCallbacks
{
    void onRead(BLECharacteristic *pCharacteristic)
    { // 客户端读取事件回调函数
        Serial.println("触发读取事件");
    }

    void onWrite(BLECharacteristic *pCharacteristic)
    { // 客户端写入事件回调函数
        size_t length = pCharacteristic->getLength();
        uint8_t *pdata = pCharacteristic->getData();
        if(length == 8){
            //0xA5 0xA5 0x01 angle1 angle2 angle3 angle4 
            if(pdata[0] == 0xA5 && pdata[1] == 0xA5 && pdata[2] == 0x01 ){
                //控制指令
                // Serial.printf("控制指令\n");
                Serial.write(pdata,8);
                em_motor_run(pdata+3);
            }
        }
        if(length == 6){
            if(pdata[0] == 0xA5 && pdata[1] == 0xA5 && pdata[2] == 0x02 ){
                //移动指令
                alg_set_move_action(pdata+3);
            }
        }
        for (int index = 0; index < length; index++)
        {
            Serial.printf(" %d", pdata[index]);
        }
        Serial.printf("\n");
    }
};

void init_ble()
{
    BLEDevice::init(BLE_NAME); // 填写自身对外显示的蓝牙设备名称，并初始化蓝牙功能
    BLEDevice::startAdvertising();   // 开启Advertising广播

    BLEServer *pServer = BLEDevice::createServer();  // 创建服务器
    pServer->setCallbacks(new bleServerCallbacks()); // 绑定回调函数

    BLEService *pService = pServer->createService(SERVICE_UUID); // 创建服务
    pCharacteristic = pService->createCharacteristic(            // 创建特征
        CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_READ |
            BLECharacteristic::PROPERTY_NOTIFY |
            BLECharacteristic::PROPERTY_WRITE);
    // 如果客户端连上设备后没有任何写入的情况下第一次读取到的数据应该是这里设置的值
    pCharacteristic->setCallbacks(new bleCharacteristicCallbacks());
    pCharacteristic->addDescriptor(new BLE2902()); // 添加描述 
    pService->start(); // 启动服务
    BLEDevice::startAdvertising();
}

