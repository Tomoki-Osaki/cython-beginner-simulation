import numpy as np

class InfectionSimulationPy:
    def __init__(self,
                 num_agents: int = 1000,
                 timelimits: int = 1000,
                 R: float = 0.5,
                 stride: float = 1.0,
                 field_size: float = 20.0,
                 seed: int = 0):

        self.num_agents = num_agents
        self.timelimits = timelimits
        self.R = R
        self.stride = stride
        self.field_size = field_size
        self.seed = seed

        np.random.seed(seed)
        self.num_agents = num_agents
        self.timelimits = timelimits

        self.pos = (np.random.rand(num_agents, 2) - 0.5) * field_size
        self.pos[0] = np.zeros(2)

        self.all_pos = np.empty([timelimits+1, num_agents, 2])
        self.all_pos[0] = self.pos

        self.if_infected = np.zeros(num_agents, dtype=np.int32)
        self.if_infected[0] = 1

        self.all_if_infected = np.zeros([timelimits+1, num_agents], dtype=np.int32)
        self.all_if_infected[0] = self.if_infected


    def calc_next_state(self, i: int):
        if self.if_infected[i] == 0:
            self.check_if_infected(i)

        self.pos[i] += (np.random.rand(2) - 0.5) * self.stride


    def check_if_infected(self, i: int):
        for j in range(self.num_agents):
            if i == j:
                continue

            if self.if_infected[j] == 1:
                j_posx = self.pos[j, 0]
                j_posy = self.pos[j, 1]

                i_posx = self.pos[i, 0]
                i_posy = self.pos[i, 1]

                if ((i_posx - j_posx)**2 + (i_posy - j_posy)**2) < self.R:
                    self.if_infected[i] = 1


    def run(self):
        np.random.seed(self.seed)
        for t in range(self.timelimits):
            for i in range(self.num_agents):
                self.calc_next_state(i)
                self.all_pos[t+1, i] = self.pos[i]
                self.all_if_infected[t+1, i] = self.if_infected[i]
