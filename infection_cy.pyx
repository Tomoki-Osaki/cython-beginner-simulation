# cython: language_level=3, boundscheck=False, wraparound=False, cdivision=True

import numpy as np
cimport numpy as cnp
cnp.import_array()

from libc.stdlib cimport rand, srand, RAND_MAX

cpdef double c_rand(bint normalize = True):
    """
    C言語の関数を使った乱数生成。
    normalizeをTrueにすると, 値の範囲を0-1に限定できる。
    """
    cdef double val = rand()

    if normalize:
        return val / RAND_MAX
    else:
        return val


cdef class InfectionSimulationCy:
    """
    感染が広まっていく様子のシミュレーション。
    非感染エージェントは感染エージェントの近くにいると, 感染エージェントに変化する。
    インスタンス生成後, run()メソッドでシミュレーションを実行する。
    実行終了後は, all_posにアクセスすることで, 各ステップでの全エージェントの位置を
    把握できる。
    """
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
        """
        num_agents: エージェントの数
        timelimits: シミュレーションの実行ステップ数。
        R: 感染エージェントとこれ以上近いと感染する距離。
        stride: 1ステップ毎のエージェントの移動幅。
        field_size: シミュレーション空間の広さ。
        seed: 乱数シード。
        """
        cdef int i

        self.num_agents = num_agents
        self.timelimits = timelimits
        self.R = R
        self.stride = stride
        self.field_size = field_size
        self.seed = seed

        # それぞれのエージェントは, シミュレーション開始時にランダムな初期位置に出現する
        srand(seed)
        self.pos = np.empty([num_agents, 2])
        for i in range(num_agents):
            self.pos[i, 0] = (c_rand() - 0.5) * field_size
            self.pos[i, 1] = (c_rand() - 0.5) * field_size
        # 一体目の感染エージェントは必ず空間の中央に出現する
        self.pos[0, 0] = 0
        self.pos[0, 1] = 0

        # self.all_posは, 各ステップでのエージェントの位置を格納する
        self.all_pos = np.empty([timelimits+1, num_agents, 2])
        self.all_pos[0] = self.pos

        # self.if_infectedは, そのエージェントが感染エージェントかどうかのフラグ
        self.if_infected = np.zeros(num_agents, dtype=np.int32)
        self.if_infected[0] = 1

        self.all_if_infected = np.zeros([timelimits+1, num_agents], dtype=np.int32)
        self.all_if_infected[0] = self.if_infected


    cpdef void calc_next_state(self, int i):
        """
        各エージェントの感染状態をチェックした後, 次のステップでの位置を計算する
        """
        cdef:
            int j
            float ax, ay, c0x, x0y

        if self.if_infected[i] == 0:
            self.check_if_infected(i)

        self.pos[i, 0] += (c_rand() - 0.5) * self.stride
        self.pos[i, 1] += (c_rand() - 0.5) * self.stride


    cpdef void check_if_infected(self, int i):
        """
        各エージェントの感染状態のチェック。
        感染エージェントからself.Rの閾値より近い距離にいる場合, 非感染エージェントは
        次ステップから感染エージェントに変化する。
        """
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
        """
        シミュレーションの実行。
        """
        cdef int t, i

        srand(self.seed)
        for t in range(self.timelimits):
            for i in range(self.num_agents):
                self.calc_next_state(i)
                self.all_pos[t+1, i] = self.pos[i]
                self.all_if_infected[t+1, i] = self.if_infected[i]
