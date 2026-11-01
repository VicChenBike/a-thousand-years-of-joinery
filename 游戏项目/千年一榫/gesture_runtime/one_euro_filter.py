"""One Euro Filter——批次 T（spec §4-T7）：光标防抖滤波（Python 采集端）。

算法出处：Casiez, Roussel, Vogel — CHI 2012 «1€ Filter: A Simple Speed-based
Low-pass Filter for Noisy Input in Interactive Systems»。本文件为按论文公式
自行实现（低通 alpha = 1/(1 + tau/dt)，tau = 1/(2*pi*f_c)；自适应截止
f_c = min_cutoff + beta*|dx/dt|，微分通道经 d_cutoff 低通），未复制任何第三方
代码；GitHub one-euro-filter 系（MIT）参考实现仅作数值对照（W7 合规注记）。

作用域红线（spec §1.2-2）：仅作用于 lm[8] 食指尖输出通道（tip_x/tip_y），
landmarks 原样透传，判定内核 gesture_engine.py 零改动。
"""
import numpy as np

ONE_EURO_MIN_CUTOFF = 1.8  # 批次 AC（领域三 §4.3-2）：1.2→1.8 Hz（快速位移相位滞后下降；旧值留痕）
ONE_EURO_BETA = 3.0        # 批次 AC（§4.3-2）：1.7→3.0（旧值留痕：1.0=批次T、1.7=批次U U8-3）
ONE_EURO_D_CUTOFF = 1.0    # Hz，微分通道截止
# 批次 AA（W2-9，spec §5.3/§15#8）：dt 钳制域 [1/120, 1/15]【暂定值·待用户复验】——
# 上限 1/15：主循环卡顿帧 dt 暴增 → alpha→1 直通跳变（旧 max(t−tp,1e-6) 无上限）；
# 下限 1/120：同帧级 dt→0 → alpha→0 输出假死（旧仅 1e-6 防除零，微步几乎不过滤波）。
# _t_prev 始终记真实时间戳（钳制只作用于 alpha 计算，不积累时间债）。
ONE_EURO_DT_MIN = 1.0 / 120.0
ONE_EURO_DT_MAX = 1.0 / 15.0


class OneEuroFilter:
    """单轴 One Euro 滤波器。每手每轴一个实例（server 主循环每手 2 实例）。"""

    def __init__(self, min_cutoff: float = ONE_EURO_MIN_CUTOFF,
                 beta: float = ONE_EURO_BETA,
                 d_cutoff: float = ONE_EURO_D_CUTOFF):
        self.min_cutoff = float(min_cutoff)
        self.beta = float(beta)
        self.d_cutoff = float(d_cutoff)
        self._x_prev = None
        self._dx_prev = 0.0
        self._t_prev = None

    @staticmethod
    def _alpha(cutoff: float, dt: float) -> float:
        tau = 1.0 / (2.0 * np.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)

    def reset(self) -> None:
        """手离场复位（spec §4-T7：手离场时实例复位）。"""
        self._x_prev = None
        self._dx_prev = 0.0
        self._t_prev = None

    def filter(self, x: float, t: float) -> float:
        """喂入归一坐标 x 与单调递增时间戳 t（秒），返回滤波后坐标。"""
        if self._x_prev is None:
            self._x_prev = float(x)
            self._t_prev = float(t)
            return float(x)
        # 批次 AA（W2-9）：dt 上下限钳制 [1/120, 1/15]——防卡顿帧 alpha→1 直通跳变、
        # 防同帧级 alpha→0 输出假死；_t_prev 记真实时间（不积累时间债）。
        dt = min(max(float(t) - self._t_prev, ONE_EURO_DT_MIN), ONE_EURO_DT_MAX)
        dx = (float(x) - self._x_prev) / dt
        a_d = self._alpha(self.d_cutoff, dt)
        dx_hat = a_d * dx + (1.0 - a_d) * self._dx_prev
        cutoff = self.min_cutoff + self.beta * abs(dx_hat)
        a = self._alpha(cutoff, dt)
        x_hat = a * float(x) + (1.0 - a) * self._x_prev
        self._x_prev = x_hat
        self._dx_prev = dx_hat
        self._t_prev = float(t)
        return x_hat
