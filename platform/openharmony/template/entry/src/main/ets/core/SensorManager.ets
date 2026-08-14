import { sensor } from '@kit.SensorServiceKit';
import plugin from 'libentry.so';
import { Logger } from './Logger';

const logger = new Logger('SensorManager')

export class SensorManager {
  /**
   * Subscribe to accelerometer and gyroscope if permissions are granted.
   * Sensor data is forwarded to the native layer via plugin.inputSensor().
   */
  startSensors(allowedPermissions: string): void {
    // Accelerometer (type 0)
    if (allowedPermissions.includes('ohos.permission.ACCELEROMETER')) {
      try {
        sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
          plugin.inputSensor({ type: 0, x: data.x, y: data.y, z: data.z })
        }, { interval: 200000000 }) // 200ms
      } catch (e) {
        logger.error('Failed to subscribe accelerometer', e)
      }
    }

    // Gyroscope (type 1)
    if (allowedPermissions.includes('ohos.permission.GYROSCOPE')) {
      try {
        sensor.on(sensor.SensorId.GYROSCOPE, (data: sensor.GyroscopeResponse) => {
          plugin.inputSensor({ type: 1, x: data.x, y: data.y, z: data.z })
        }, { interval: 200000000 }) // 200ms
      } catch (e) {
        logger.error('Failed to subscribe gyroscope', e)
      }
    }
  }
}
