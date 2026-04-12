import infection_py
import infection_cy
import time
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from tqdm import tqdm

num_agents = 100
timelimits = 100

# %% Cython版のシミュレーション
start_cy = time.time()
simulation_cy = infection_cy.InfectionSimulationCy(
    num_agents=num_agents,
    timelimits=timelimits,
    seed=5,
    field_size=20
)
simulation_cy.run()
dur_cy = time.time() - start_cy
print(dur_cy)

# %% 純粋Python版のシミュレーション
start_pure = time.time()
simulation_pure = infection_py.InfectionSimulationPy(
    num_agents=num_agents,
    timelimits=timelimits,
    field_size=100
)
simulation_pure.run()
dur_pure = time.time() - start_pure
print(dur_pure)

print('cython is faster: ', dur_pure / dur_cy)

# %% シミュレーションの様子をアニメーションにする
def animate_simulation(sim, duration, save_as='tmp.gif'):

    fig, ax = plt.subplots(figsize=(6, 6))

    def update(frame):
        ax.cla()
        lim = (-sim.field_size/2, sim.field_size/2)
        ax.set(xlim=lim, ylim=lim)
        ax.set_title(f'step: {frame}')
        for i in range(sim.num_agents):
            if sim.all_if_infected[frame, i] == 0:
                color = 'blue'
            elif sim.all_if_infected[frame, i] == 1:
                color = 'red'

            xy = np.asarray(sim.all_pos[frame, i])
            ax.scatter(*xy, color=color, alpha=0.5, s=100)

        ax.grid()

    anim = FuncAnimation(fig, update, frames=tqdm(duration))
    anim.save(save_as)
    plt.close()

# animate_simulation(simulation_cy, range(100), save_as='simulation.gif')
