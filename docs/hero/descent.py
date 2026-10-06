# /// script
# dependencies = ["matplotlib", "numpy", "pillow"]
# ///
"""Animation of gradient descent with momentum, saved as descent.gif."""
import sys

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.animation import FuncAnimation, PillowWriter


def f(x, y):
    return (1 - x) ** 2 + 4 * (y - x**2) ** 2


def grad(x, y):
    return np.array([-2 * (1 - x) - 16 * x * (y - x**2), 8 * (y - x**2)])


p, v, path = np.array([-1.6, 2.2]), np.zeros(2), []
for _ in range(56):
    path.append(p.copy())
    v = 0.85 * v - 0.016 * grad(*p)
    p = p + v
path = np.array(path + [path[-1]] * 14)  # hold the end

X, Y = np.meshgrid(np.linspace(-2, 2, 300), np.linspace(-0.8, 3, 300))
fig, ax = plt.subplots(figsize=(4.8, 3.6), dpi=100)
fig.subplots_adjust(0.02, 0.02, 0.98, 0.98)
ax.contourf(X, Y, np.log1p(f(X, Y)), levels=24, cmap="viridis")
ax.plot(1, 1, "*", color="white", ms=14, mec="black")
ax.set_axis_off()
(trail,) = ax.plot([], [], "-", color="#ff5c5c", lw=2)
(head,) = ax.plot([], [], "o", color="#ff5c5c", ms=9, mec="white", mew=1.5)


def update(i):
    trail.set_data(path[: i + 1, 0], path[: i + 1, 1])
    head.set_data(path[i : i + 1, 0], path[i : i + 1, 1])
    return trail, head


FuncAnimation(fig, update, frames=len(path)).save(
    sys.argv[1] if len(sys.argv) > 1 else "descent.gif", writer=PillowWriter(fps=15), dpi=100
)
