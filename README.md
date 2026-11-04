# Ti60F225 SC431HAI to HDMI

基于 Efinix Titanium Ti60F225 FPGA 的 SC431HAI 摄像头视频处理工程，包含摄像头接入、DDR 帧缓存、图像处理及显示相关 RTL。

## 工程结构

```text
rtl/
  ti60f225_oob_top.v     顶层模块
  image_edge/           图像处理、识别及 OSD
  cam_i2c_ctrl/          摄像头 I2C 配置
  ddr3_controller/       DDR 控制相关 RTL（部分依赖未收录）
  frame_buffer_V3/      视频帧缓存
  uart_index/           UART 控制
ip/                     保留的 IP 配置文件
ti60f225_oob.xml         Efinity 工程
ti60f225_oob.peri.xml    外设/引脚配置
ti60f225_oob.sdc         时序约束
UART.md                 UART 操作说明
```

## 使用

工程记录的工具版本为 Efinity 2026.1.132.3.9，器件 Ti60F225，速度/时序模型 I3，顶层 `ti60f225_oob_top`。使用匹配硬件及合法授权的 Efinity 环境，补齐下述依赖后打开 `ti60f225_oob.xml`，检查 IP、引脚及时钟配置，再运行综合、布局布线与位流生成。

本仓库是筛选后的源码快照，**不能保证直接完整编译**。专有声明或加密保护的厂商 RTL/IP、厂商手册和原理图未上传，需从原项目或合法授权的厂商工具中取得。IP 配置保留用于核对，不能保证所有依赖可由 IP Manager 自动重新生成。

当前工程引用但本快照未包含的文件：

- `rtl/uart_index/integer_divider.v`
- `rtl/uart_index/uart_receiver.v`
- `rtl/uart_index/uart_transfer.v`
- `rtl/user_dual_port_ram.v`
- `rtl/ddr3_controller/ddr3_top.v`
- `rtl/ddr3_controller/axi4_bus_ctl/axi4_bus_ctl.v`
- `rtl/ddr3_controller/local_bus_ctl/local_bus_ctl.v`
- `rtl/ddr3_controller/memory_bus_ctl/memory_bus_ctl.v`
- `rtl/ddr3_controller/phy_ctl/ddr_phy_wrlvl.v`
- `rtl/ddr3_controller/phy_ctl/ddr_phy_rdlvl_dqs.v`
- `rtl/ddr3_controller/phy_ctl/ddr_phy_wrcal.v`
- `rtl/ddr3_controller/phy_ctl/ddr_calibration_ini.v`
- `rtl/ddr3_controller/phy_ctl/ddr_phy_if.v`
- `rtl/ddr3_controller/phy_ctl/phy_ctl.v`
- `rtl/ddr3_controller/phy_ctl/ddr_mpr_rdlvl.v`
- `rtl/ddr3_controller/lb2_axi_clk.v`
- `rtl/ddr3_controller/common/efx_fifo_v2.3/efx_fifo_wrapper.v`
- `rtl/dvi_tx/efx_fifo.v`
- `rtl/dvi_tx/encode.v_encrypted.v`
- `rtl/dvi_tx/tx_aux.v_encrypted.v`
- `rtl/dvi_tx/dvi_encoder.v_encrypted.v`
- `rtl/csi_rx_controller.sv`

## 快照范围与验证

仅提取指定工程子目录的当前文件，不导入父目录 Git 历史、其他报告或其他项目。编译输出、波形、缓存、重复压缩包及本地调试配置均已排除。`readme.txt` 为原始示例版本记录；`UART.md` 含历史记录及指向父目录验证资料的链接，这些外部资料不在本快照中，以实际 RTL 为准。

上传准备只验证文件范围、凭据特征及 Git 内容；未重新综合、仿真或上板验证。配置及初始化数据文件保留原样。

## 权利说明

本仓库未新增开源许可证，也不授予第三方代码的再分发权。保留的第三方代码沿用原有版权及许可声明。默认使用私有仓库存储，公开前须重新审查第三方许可和文档权利。
