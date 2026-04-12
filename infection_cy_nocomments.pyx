# cython: language_level=3, boundscheck=False, wraparound=False, cdivision=True

import numpy as np
cimport numpy as cnp
cnp.import_array()
from libc.stdlib cimport rand, srand, RAND_MAX


cpdef double c_rand(bint normalize = True):
    cdef double val = rand()

    if normalize:
        return val / RAND_MAX
    else:
        return val


cdef class InfectionSimulationCy:
    cdef public:
        int num_agents
        int timelimits
        float R
        float stride
        float field_size
        double[:,:,:] all_pos
        int[:,:] all_if_infected

    cdef readonly:
        int seed

    cdef:
        double[:,:] pos
        int[:] if_infected


    def __init__(self,
                 int num_agents = 1000,
                 int timelimits = 1000,
                 float R = 0.5,
                 float stride = 1.0,
                 float field_size = 20.0,
                 int seed = 0):
        cdef int i

        self.num_agents = num_agents
        self.timelimits = timelimits
        self.R = R
        self.stride = stride
        self.field_size = field_size
        self.seed = seed

        srand(seed)
        self.pos = np.empty([num_agents, 2])
        for i in range(num_agents):
            self.pos[i, 0] = (c_rand() - 0.5) * field_size
            self.pos[i, 1] = (c_rand() - 0.5) * field_size
        self.pos[0, 0] = 0
        self.pos[0, 1] = 0

        self.all_pos = np.empty([timelimits+1, num_agents, 2])
        self.all_pos[0] = self.pos

        self.if_infected = np.zeros(num_agents, dtype=np.int32)
        self.if_infected[0] = 1

        self.all_if_infected = np.zeros([timelimits+1, num_agents], dtype=np.int32)
        self.all_if_infected[0] = self.if_infected


    cdef void calc_next_state(self, int i):
        cdef:
            int j
            float ax, ay, c0x, x0y

        if self.if_infected[i] == 0:
            self.check_if_infected(i)

        self.pos[i, 0] += (c_rand() - 0.5) * self.stride
        self.pos[i, 1] += (c_rand() - 0.5) * self.stride


    cdef void check_if_infected(self, int i):
        cdef:
            int j
            float j_posx, j_posy, i_posx, i_posy

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


    cpdef void run(self):
        cdef int t, i

        srand(self.seed)
        for t in range(self.timelimits):
            for i in range(self.num_agents):
                self.calc_next_state(i)
                self.all_pos[t+1, i] = self.pos[i]
                self.all_if_infected[t+1, i] = self.if_infected[i]
