#!/usr/bin/env python3
"""《千年一榫》手势识别入口壳（批次 R spec §3.1/§3.4）。

argparse：--port（基准端口 P，默认 9876）/ --camera（auto 或数字索引，默认 auto）。
端口派生规则（spec §3.3 终态）：手势 JSON=P、摄像头 JPEG=P+1、控制命令=P+2。
解析后调用 hand_tracking_server.main(port=P, frame_port=P+1, control_port=P+2, camera=…)。
本文件与 models/ 的相对位置不可拆散（server 顶部 os.chdir(SCRIPT_DIR) 相对路径依赖）。
"""

import argparse

import hand_tracking_server


def main() -> None:
    parser = argparse.ArgumentParser(description="千年一榫手势识别入口")
    parser.add_argument("--port", type=int, default=9876,
                        help="基准端口 P（手势 JSON=P，JPEG=P+1，控制=P+2；默认 9876）")
    parser.add_argument("--camera", type=str, default="auto",
                        help="摄像头：auto=自动枚举，或数字索引（默认 auto）")
    parser.add_argument("--owner-pid", type=int, default=None,
                        help="Z4-① 宿主进程 PID（编辑器态=游戏进程/打包态=launcher）——"
                             "父进程看门狗主判据；缺省回退自然父判据")
    args = parser.parse_args()

    camera = None
    if args.camera != "auto":
        camera = int(args.camera)

    print(f"[main.py] 启动手势识别：P={args.port} "
          f"(JSON={args.port}, JPEG={args.port + 1}, CTRL={args.port + 2}), camera={args.camera}, "
          f"owner_pid={args.owner_pid}")
    hand_tracking_server.main(port=args.port,
                              frame_port=args.port + 1,
                              control_port=args.port + 2,
                              camera=camera,
                              headless=True,
                              owner_pid=args.owner_pid)


if __name__ == "__main__":
    main()
