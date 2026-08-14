# OpenHarmony 手柄/游戏手柄适配方案

## 参考资料

OpenHarmony 提供了 **Game Controller Kit**（`libohgame_controller.z.so`），支持手柄外设。
官方文档路径：

```
zh-cn/application-dev/game-controller/
├── game-controller-introduction.md       # Kit 简介
├── game-controller-monitor-device.md     # 监听设备上下线（C/C++）
├── game-controller-monitor-pad.md       # 监听轴和按键事件（C/C++）
```

API 参考头文件：`<GameControllerKit/game_pad.h>`

## 支持的能力

### 按键（Button）
每个按键有独立注册函数，对应 Godot 的 `JoypadButton` 枚举：

| OHOS API | 按键码 | Godot 对应 |
|----------|--------|------------|
| `ButtonA_RegisterButtonInputMonitor` | 2301 | `JOY_BUTTON_A` |
| `ButtonB_RegisterButtonInputMonitor` | 2302 | `JOY_BUTTON_B` |
| `ButtonC_RegisterButtonInputMonitor` | 2303 | `JOY_BUTTON_C` (无标准对应) |
| `ButtonX_RegisterButtonInputMonitor` | 2304 | `JOY_BUTTON_X` |
| `ButtonY_RegisterButtonInputMonitor` | 2305 | `JOY_BUTTON_Y` |
| `LeftShoulder_RegisterButtonInputMonitor` | 2307 | `JOY_BUTTON_LEFT_SHOULDER` |
| `RightShoulder_RegisterButtonInputMonitor` | 2308 | `JOY_BUTTON_RIGHT_SHOULDER` |
| `LeftTrigger_RegisterButtonInputMonitor` | 2309 | `JOY_BUTTON_L2` |
| `RightTrigger_RegisterButtonInputMonitor` | 2310 | `JOY_BUTTON_R2` |
| `ButtonMenu_RegisterButtonInputMonitor` | 2312 | `JOY_BUTTON_START` |
| `ButtonHome_RegisterButtonInputMonitor` | 2311 | `JOY_BUTTON_GUIDE` |
| `LeftThumbstick_RegisterButtonInputMonitor` | 2314 | `JOY_BUTTON_LEFT_STICK` |
| `RightThumbstick_RegisterButtonInputMonitor` | 2315 | `JOY_BUTTON_RIGHT_STICK` |
| `Dpad_UpButton_RegisterButtonInputMonitor` | 2012 | `JOY_BUTTON_DPAD_UP` |
| `Dpad_DownButton_RegisterButtonInputMonitor` | 2013 | `JOY_BUTTON_DPAD_DOWN` |
| `Dpad_LeftButton_RegisterButtonInputMonitor` | 2014 | `JOY_BUTTON_DPAD_LEFT` |
| `Dpad_RightButton_RegisterButtonInputMonitor` | 2015 | `JOY_BUTTON_DPAD_RIGHT` |

### 轴（Axis）
轴事件通过回调获取浮点值（-1.0 ~ 1.0），对应 Godot 的 `JoyAxis` 枚举：

| OHOS API | 获取轴值 | Godot 对应 |
|----------|----------|------------|
| `LeftThumbstick_RegisterAxisInputMonitor` | `GetXAxisValue` / `GetYAxisValue` | `JOY_AXIS_LEFT_X` / `JOY_AXIS_LEFT_Y` |
| `RightThumbstick_RegisterAxisInputMonitor` | `GetZAxisValue` / `GetRZAxisValue` | `JOY_AXIS_RIGHT_X` / `JOY_AXIS_RIGHT_Y` |
| `Dpad_RegisterAxisInputMonitor` | `GetHatXAxisValue` / `GetHatYAxisValue` | D-Pad 作为 HAT 轴 |
| `LeftTrigger_RegisterAxisInputMonitor` | `GetBrakeAxisValue` | `JOY_AXIS_TRIGGER_LEFT` |
| `RightTrigger_RegisterAxisInputMonitor` | `GetGasAxisValue` | `JOY_AXIS_TRIGGER_RIGHT` |

### 设备上下线
- `OH_GamePad_RegisterDeviceOnlineMonitor()` — 设备上线回调
- `OH_GamePad_RegisterDeviceOfflineMonitor()` — 设备下线回调
- `OH_GamePad_GetDeviceList()` — 获取所有在线设备

## 实现架构

### 方案：C++ 直接调用 Game Controller Kit

与传感器实现不同，Game Controller Kit 的 API 是纯 C/C++ 回调模式，不需要经过 ArkTS 桥接。

```
Game Controller Kit C callback
  → bridge_openharmony.cpp: 映射按键码/轴值到 Godot 枚举
    → Input::get_singleton()->joy_button(device_id, button, pressed)
    → Input::get_singleton()->joy_axis(device_id, axis, value)
```

### 文件改动

| 文件 | 操作 |
|------|------|
| `bridge_openharmony.h` | 新增 GodotGamepadEvent 类型、回调注册函数 |
| `bridge_openharmony.cpp` | 实现 Game Controller Kit 回调注册，在 godot_step 中转发事件 |
| `os_openharmony.h` | 可选：添加手柄初始化/清理 |
| `os_openharmony.cpp` | 在 `initialize_joypads()` 中注册所有按键/轴回调 |
| `SCsub` 或 `detect.py` | 链接 `libohgame_controller.z.so` |

### 关键实现细节

1. **设备 ID 管理**：一个 `HashMap<String, int>` 保存 deviceId → Godot 设备索引的映射

2. **按键事件回调**：
   ```cpp
   static void _on_button_event(const struct GamePad_ButtonEvent *event) {
       char *deviceId;
       OH_GamePad_ButtonEvent_GetDeviceId(event, &deviceId);
       GamePad_Button_ActionType action;
       OH_GamePad_ButtonEvent_GetButtonAction(event, &action);
       int32_t buttonCode;
       OH_GamePad_ButtonEvent_GetButtonCode(event, &buttonCode);
       // 映射 buttonCode 到 Godot 的 JoypadButton
       JoypadButton godot_button = _ohos_to_godot_button(buttonCode);
       bool pressed = (action == GAME_PAD_BUTTON_PRESSED);
       Input::get_singleton()->joy_button(device_index, godot_button, pressed);
       free(deviceId);
   }
   ```

3. **轴事件回调**：
   ```cpp
   static void _on_axis_event(const struct GamePad_AxisEvent *event) {
       double x, y;
       OH_GamePad_AxisEvent_GetXAxisValue(event, &x);
       OH_GamePad_AxisEvent_GetYAxisValue(event, &y);
       Input::get_singleton()->joy_axis(device_index, JOY_AXIS_LEFT_X, x);
       Input::get_singleton()->joy_axis(device_index, JOY_AXIS_LEFT_Y, y);
   }
   ```

4. **CMakeLists.txt**：添加 `libohgame_controller.z.so` 链接
   ```cmake
   target_link_libraries(entry PUBLIC libohgame_controller.z.so)
   ```
   在 `detect.py` 中不需要额外 LIBS（通过 dlopen 或 NDK 链接）

## 验证

1. `scons platform=openharmony target=template_release generate_bundle=yes` 构建通过
2. 连接蓝牙/USB 手柄
3. 用 `hdc_std shell hidumper -s 3301 -a -a` 检查手柄设备是否识别
4. 游戏内通过 `Input.get_connected_joypads()` 验证连接
5. 打印 `Input.get_joy_axis()` / `Input.is_joy_button_pressed()` 验证输入
