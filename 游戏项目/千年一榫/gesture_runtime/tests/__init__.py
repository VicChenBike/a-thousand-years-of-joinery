# -*- coding: utf-8 -*-
"""gesture_runtime 逻辑测试包（批次 V-B1 起）。

零摄像头纪律：本包内全部测试不依赖真实摄像头/真实端口，
cv2.VideoCapture 与 socket 均以 unittest.mock 打桩。
"""
