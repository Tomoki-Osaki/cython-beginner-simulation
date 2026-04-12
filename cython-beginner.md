## Cythonとは
[Cython](https://cython.org/)は, PythonにC言語の静的型付けを行うことでC言語並みの実行速度を実現する静的コンパイラです。

Pythonは動的型付けを行うことから実行速度が遅い言語ですが, 高速化する方法はいくつか用意されていて, 「[Pythonの実行を高速化する方法を一覧でまとめてみた](https://qiita.com/yuki_2020/items/36da0281c8af5c2c745f)」という記事によくまとまっています。

このように, Pythonを高速化する方法は色々あるのですが ([PyPy](https://pypy.org/)や[Numba](https://numba.pydata.org/)など), Cythonを選ぶ理由としては以下のようなものがあると思います。
1. Pythonのライブラリを使えること
2. C/C++のライブラリを使えること
3. 静的型付けによるコードの堅牢化

Cythonの一番大きな特徴は, 3つ目の静的型付けによる高速化です。C言語などのコンパイル言語では変数の定義や関数の戻り値の型を宣言する必要がありますが PythonやRubyのようなインタプリタ言語ではその必要がありません。インタプリタ言語ではその分高速に開発を行うことができますが, 実行速度が遅かったり, 型が異なることによるエラーやバグが起きやすかったりします。

この記事を書こうとした背景としては, Cythonの解説記事は公式も含めて少なからずあるものの, それらが1つの関数を高速化するだけで終わってることが多く, 1つのまとまったプログラムとして参考にできるものが見つからなかったからです。個人的に, 新しいツールを学ぶ際には, とにかくたくさんの**動かせる**サンプルコードに触れることが重要だと思っているので, この記事が参考になれば幸いです。

この記事では, Cythonの基本的な書き方を簡単に紹介した後, マルチエージェントシミュレーションの高速化を実践例として説明します。なお, シミュレーションのコードはあくまでCython実装の例として用意しているため, シミュレーションの設計自体は詳細に説明しません。
シミュレーションは, 「Pythonによる数値計算とシミュレーション」の「6.2.2 マルチエージェントシミュレーションプログラム」を参考に改変して実装しています[1]。

https://www.ohmsha.co.jp/book/9784274221705/

[1] リンク先のページに本のソースコードのリンクがありますが, 「本ファイルは、本書をお買い求めになった方のみご利用いただけます。」とありますので, 利用にはご注意ください。この記事でも, ソースコードをそのままではなく, かなりリファクタリングして使用しています。

また, 私が研究でCythonを実装する際や, 本記事の執筆にあたり, **参考資料**セクションに載せている記事に多いに助けられました。ぜひそれらを参考にした後, 必要であればこの記事を読んでください。

## Cythonを使う準備
本記事での動作環境は以下の通りです。
- OS: Ubuntu 24.04 (Windows 11 (ver. 25H2)とのデュアルブート) 
- CPU: AMD Ryzen 7 7735U
- GPU: AMD Radeon(TM) Graphics 
- IDE: Spyder (ver. 5.5.1)
- Python 3.12.13
- Cython 3.2.4

Cythonはcondaでもpipでもインストールできます。
```
(base) conda create -n cython
(base) conda activate cython
(cython) conda install cython
```

```python
import cython
print(cython.__version__) # '3.2.4'
```

Cythonでのプログラム作成の基本は以下の流れです。
1. .pyxファイルにCythonコードを書く
2. setup.pyを実行して.pyxファイルをコンパイル・ビルドする
3. .pyファイルで2の出力ファイル(.so / .pyd)をインポートして使用する

この他に.pydファイルや.hファイルなどを利用してC/C++で書いた関数を使用するなどの方法もありますが, この記事では扱いません。

.pyxを変更した場合, 変更前の.pyxを使用しているプロセスをキルしてからsetup.pyを再度実行しないと, 出力ファイルに.pyxファイルへの変更が反映されません。

## Cythonの型付けの基本
シミュレーションの実装の前に, Cythonの基本である型付けについて, ほんの少しだけ説明します。
Cython (.pyx) では, C/C++などのように変数を定義する際に型を明示的に宣言することができます。例えば, 整数型のnumという変数を宣言する時は, 以下のようにします。
```python
# 構文: cdef 型 変数名
cdef int num # 変数宣言
num = 5 # 代入
cdef str language = "cython" # このように宣言と代入を同時に行うこともできます
```
宣言できる代表的な型は以下の通りです。「[【Python】Cythonで高速化、3行足すだけで100倍速くなる](https://qiita.com/Aqua-218/items/28ee5fe85f3e3924f08c)」という記事を参考にしました。
```
int 整数
long 長整数
float 浮動小数点
double 倍精度
bint ブール値
char 文字
str 文字列
```
[公式サイト](https://cython.readthedocs.io/en/latest/src/userguide/language_basics.html#types)では, 利用可能な型を全て確認することができます。なお, 今回は説明しませんが, C言語のポインタも利用できます。

## シミュレーションの実装

これ以降は, このシミュレーションコードのうち, Cython高速化に関わるヒントや, つまずきやすいポイントを解説しながら進めていきます。説明しないコードもあります。再度の注意ですが, シミュレーションの仕様自体の詳細な説明はしませんが, 概要は記述しておきます。

- 感染が拡大する様子のシミュレーション
- エージェントは感染エージェントと非感染エージェントの2種類
- シミュレーションは決められたステップ数が経過するまで継続する
- それぞれのエージェントは, 毎ステップごとに移動を行う
- 最初に一体のエージェントだけが感染エージェントとして設定され, 毎ステップごとに, 感染エージェントの近くにいた非感染エージェントは, 感染エージェントに変化する

マルチエージェントシミュレーションを題材として選んだ理由は, 全てのエージェントが自分以外の他の全てのエージェントに対して計算を行うという処理が, 正にPythonが苦手とし, Cythonが得意とするところだからです。

### シミュレーション全コード
まずはCythonコードであるinfection_cy.pyxファイルです。
```python
# cython: language_level=3, boundscheck=False, wraparound=False, cdivision=True

from tqdm import tqdm
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

cdef class InfectionSimulation:
    cdef public:
        int num_agents
        double[:,:] pos
        double[:,:,:] all_pos
        int[:] if_infected
        int[:,:] all_if_infected
        float R
        float factor
        int timelimits
        int seed

    def __init__(self,
                  int num_agents = 1000,
                  int timelimits = 1000,
                  float R = 0.5,
                  float factor = 1.0,
                  int seed = 0,
                  float field_size = 20.0):
        cdef int i

        srand(seed)
        self.num_agents = num_agents

        self.pos = np.empty([num_agents, 2])
        for i in range(num_agents):
            self.pos[i, 0] = (c_rand() - 0.5) * field_size
            self.pos[i, 1] = (c_rand() - 0.5) * field_size
        self.pos[0, 0] = -2
        self.pos[0, 1] = -2

        self.all_pos = np.empty([timelimits+1, num_agents, 2])
        self.all_pos[0] = self.pos

        self.if_infected = np.zeros(num_agents, dtype=np.int32)
        self.if_infected[0] = 1

        self.all_if_infected = np.zeros([timelimits+1, num_agents], dtype=np.int32)
        self.all_if_infected[0] = self.if_infected

        self.timelimits = timelimits
        self.R = R
        self.factor = factor
        self.seed = seed

    cpdef void calc_next_state(self, int i):  # 次時刻の状態の計算
        cdef:
            int j
            float ax, ay, c0x, x0y

        if self.if_infected[i] == 0:
            self.check_if_infected(i)

        self.pos[i, 0] += (c_rand() - 0.5)
        self.pos[i, 1] += (c_rand() - 0.5)


    cpdef void check_if_infected(self, int i):
        cdef:
            int j
            float ax, ay, c0x, c0y

        for j in range(self.num_agents):
            if i == j:
                continue

            if self.if_infected[j] == 1:
                ax = self.pos[j, 0]
                ay = self.pos[j, 1]

                c0x = self.pos[i, 0]
                c0y = self.pos[i, 1]

                if ((c0x-ax) * (c0x-ax) + (c0y-ay) * (c0y-ay)) < self.R:
                # 隣接してカテゴリ1のエージェントがいる
                    self.if_infected[i] = 1  # カテゴリ1に変身

    cpdef void run(self):
        cdef int t, i

        srand(self.seed)
        for t in range(self.timelimits):
            for i in range(self.num_agents):
                self.calc_next_state(i)
                self.all_pos[t+1, i] = self.pos[i]
                self.all_if_infected[t+1, i] = self.if_infected[i]
```
次に, setup.pyファイルです。
```python
from setuptools import setup
from Cython.Build import cythonize
import numpy as np

setup(
    ext_modules=cythonize('infection_cy.pyx'),
    include_dirs=[np.get_include()]
)
```

最後のスクリプトは, ビルドしたCythonコードを呼び出して実行するrun_simulation.pyファイルです。
```python
import infection_cy

num_agents = 100
timelimits = 100

simulation_cy = infection_cy.InfectionSimulation(
    num_agents=num_agents,
    timelimits=timelimits,
    seed=0
)
simulation_cy.run()
```
今回の感染シミュレーションのgifです。


### マジックコマンド
```python
# cython: language_level=3, boundscheck=False, wraparound=False, cdivision=True
```
まず冒頭のマジックコマンドです。実行速度上昇のためによく使用されるものに絞って記載しています。「[【目的別】コピペから始めるCython入門](https://hack.nikkei.com/blog/advent20211225/)」という記事で分かりやすく解説されています。公式サイトの説明は[こちら](https://cython.readthedocs.io/en/latest/src/userguide/source_files_and_compilation.html#compiler-directives)。
- language_level: モジュールのコンパイル時に用いられるPythonの言語を設定しています。これを書かない場合(すなわちデフォルト), Cythonのバージョンが3.x (e.g., 3.2.4)の場合はPython3が使用され, Cythonのバージョンが0.x (e.g., 0.29)の場合はPython2が使用されます。よって, Cythonのバージョンが0.xの場合はこの指定を忘れないようにします。
- boundscheck: これをFalseにすると, 配列やリストへのアクセスといったインデックス操作の際に, 範囲外の要素を指定してもIndexErrorを発生させないようになります (デフォルトはTrue)。
- wraparound: これをFalseにすると, Pythonの負のインデックス指定 (e.g., arr[-1]) が利用できなくなります (デフォルトはTrue)。
- cdivision: これをTrueにすると, 剰余(%)や商(//)演算子の挙動がC型の仕様になります (デフォルトはFalse)。

### ライブラリのインポート
```python
from tqdm import tqdm
import numpy as np
cimport numpy as cnp
cnp.import_array()
from libc.stdlib cimport rand, srand, RAND_MAX
```
次のコードはライブラリのインポートです。Cython (.pyx) に特異な点は, cimportでC/C++の関数や変数をインポートできることです。3行目のcimport numpy as cnpでは, NumPyのC言語APIを利用できるようにしています。これにより, NumPyの配列をデータ型として宣言することができるようになります (e.g., cnp.ndarray[cnp.int_t, ndim=2])[2]。公式サイトの説明は[こちら](https://cython.readthedocs.io/en/latest/src/tutorial/numpy.html#adding-types)。
4行目のcnp.import_array()は, numpy PyArray_* APIを使用する時に必要となります。Cython3からは, 型付きNumPy配列への.shapeのようなアトリビュートへのアクセス時にこのAPIを使うため, cimport numpyを呼び出す時は, 常にセットでcnp.import_array()を呼び出すことが推奨されます。
5行目では, cimportを使ってC言語のライブラリ (rand, srand) と変数 (RAND_MAX) をインポートしています。
なお, C++のモジュールをインポートする際はlibcではなくlibcppにして, ファイル冒頭にg++コンパイラを使うためのマジックコマンドを追記します。以下のコードはC++のvectorをインポートする例です。
```python
# distutils: language=c++ 
from libcpp.vector cimport vector
```
これにより.pyxファイルのコンパイラがgccからg++になり, C++のモジュールをインポートできるようになります。このマジックコマンドなしでlibcppからインポートしようとするとコンパイルエラーが発生します。
なお, 利用できるC/C++の関数や変数は, libcおよびlibcppディレクトリ内のファイルから確認でき, それらはminiconda3環境では以下にあります (ファイル名のバージョンの違いにご留意ください)。
~/miniconda3/pkgs/cython-3.2.4-py312h47b2149_0/lib/python3.12/site-packages/Cython/Includes/

[2] 時折, cimport numpy as npというインポートをしているコードを見ますが, .pyxファイル内での通常のnumpyインポート(import numpy as np)とエイリアスが被らないようにしてください。以下の例では, import numpy as np由来のモジュールとcimport numpy as np由来のモジュールが混在してしまっていて, 非常にバグが起きやすい状況となってしまっています。
```python
import numpy as np
cimport numpy as np
np.import_array()

cpdef np.ndarray[np.int32_t, ndim=1] zero_array_1d(int length):
    return np.zeros(length, dtype=np.int32)
# cimport由来: np.import_array(), np.ndarray, np.int32_t
#  import由来: np.zeros, np.int32
```

### 関数・クラスの定義
次に, 乱数を生成する関数の定義です。
```python
# 関数定義の構文: c(p)def 戻り値の型 関数名(引数の型 引数)
cdef double c_rand(bint normalize = True):
    cdef double val = rand()
    
    if normalize:
        return val / RAND_MAX
    else:
        return val
```
関数の定義では, 戻り値に加えて引数の型も宣言できます。宣言しなくてもエラーは起きませんが, 高速化には宣言が重要です。また, 関数を定義する際はcpdefかcdefを利用することができます。cpdefで定義すると.pyxファイル内でも, インポート先の.pyファイル内でも呼び出せます。cdefで定義すると.pyxファイル内でしか呼び出せませんが, cpdefよりも高速です。

次に, クラスの定義です。
```python
# クラス定義の構文: cdef class クラス名
cdef class InfectionSimulation:
    cdef public:
        int num_agents
        double[:,:,:] all_pos
        int[:,:] all_if_infected
        float R
        float factor
        int timelimits
    cdef readonly:
        int seed
    cdef:
        double[:,:] pos
        int[:] if_infected
    ......
```
クラスの定義は, 「cdef class クラス名」で行います。クラスのアトリビュートは, 型だけでなくアクセス範囲も指定でき, インポート先の.pyファイルでの挙動が変わります。
- cdef public: .pyファイルで値の呼び出しと代入ができます
- cdef readonly: .pyファイルで値を呼び出すことはできますが, 代入はできません
- cdef: .pyファイルで呼び出すことはできません

### NumPy配列と型付きメモリービュー
また, double[:,:,:] pos や, int[:] if_infected はCythonでのNumPyとの連携で非常に重要な部分です。
Cythonでは, 以下のようにNumPyのデータ型も型宣言に使用することができます。
```python
cimport numpy as cnp
# NumPyデータ型の宣言の構文: cnp.ndarray[データ型, ndim=次元数]
cdef cnp.ndarray[cnp.int64_t, ndim=1] arr = np.zeros(3)
```
しかし, この方法での宣言ではグローバル変数として用いることができず, 関数内やメソッド内でしか使用できません (グローバル環境で宣言すると「Buffer types only allowed as function local variables」というコンパイルエラーが出ます)。

そこで, Cythonでは配列として型付きメモリービュー (Typed Memoryviews) の使用が推奨されています。
基本的な構文としては, double[:,:,:] pos のように, 型に加えて次元数を「:」の数で表すことによって宣言します。型付きメモリービューは, グローバル変数としても利用することができ, またNumPyのデータ型として宣言した場合よりも高速に動作します。
しかし, NumPy配列と比較して以下のような注意点があります。

例えば, メモリービューオブジェクトでは, 以下のようなオブジェクト同士の直接の計算ができません。
```python
# メモリービュー宣言の構文: 型[:] # セミコロンは次元数
cdef double[:] arr1, arr2

arr1 = np.array([3, 4])
arr2 = np.array([1, 5])
arr3 = arr1 + arr2 # メモリービューオブジェクトでは無理
```
よって, まず空の配列を用意して個別の要素をインデックスアクセスで取り出して計算する必要があります。
```python
cdef double[:] arr1, arr2, arr3

arr1 = np.array([3, 4])
arr2 = np.array([1, 5])

arr3 = np.empty(2)
arr3[0] = arr1[0] + arr2[0]
arr3[1] = arr1[1] + arr2[1]
```
なお, NumPyモジュールを使用して生成する配列は, デフォルトではdouble型と一致します。ですので, int型の配列を用意する場合は, 配列生成時にデータ型を指定する必要があります。
```python
cdef int[:,:] int_arr

int_arr = np.zeros([2, 3], dtype=np.int32)
```
最後に, 型付きメモリービューをNumPyのndarrayにするには, asarray関数を使います。特にインポート側の.pyファイルで配列の中身を見たい場合に重宝します。
```python
# .pyファイル
import numpy as np
from any_pyx_file import mv_arr

print(mv_arr) # <MemoryView of 'ndarray' object>
arr = np.asarray(mv_arr)
print(arr) # [3 4]
```

### クラスの初期化メソッド
続いてクラスの初期化メソッドです。Cythonのクラスでは, ダブルアンダースコアで始まる特殊メソッドは, cdefやcpdefではなくdefを使って定義します。また, この時__init__ではなく__cinit__を使うことができますが, 基本的に__init__の方が安全なようです。クラスのオーバーライドや継承を行う場合はこの__init__と__cinit__の違いが重要になってきます。特殊メソッドに関する[公式サイト](https://cython.readthedocs.io/en/latest/src/userguide/special_methods.html)を参照ください。

コード内のcdef int iは, __init__メソッド内だけで用いられる変数の宣言です。
self.num_agents = num_agents では, 通常のPythonのクラスと同様に, 初期化引数をクラスのアトリビュートとして設定しています。
```python
    def __init__(self,
                 int num_agents = 1000,
                 int timelimits = 1000,
                 float R = 0.5,
                 float factor = 1.0,
                 int seed = 0,
                 float field_size = 20.0):
        cdef int i

        srand(seed)
        self.num_agents = num_agents
        ......
```

### インデックスアクセスによる配列の準備
Cythonに特徴的なself.pos以下です。
まずself.pos = np.empty([num_agents, 2])のように, 空の配列を用意します。その後, forループで配列の各要素にインデックスアクセスをして, c_rand関数で生成した乱数を代入しています。

```python
        self.pos = np.empty([num_agents, 2])
        for i in range(num_agents):
            self.pos[i, 0] = (c_rand() - 0.5) * field_size
            self.pos[i, 1] = (c_rand() - 0.5) * field_size
        self.pos[0, 0] = -2
        self.pos[0, 1] = -2

        self.all_pos = np.empty([timelimits+1, num_agents, 2])
        self.all_pos[0] = self.pos

        self.if_infected = np.zeros(num_agents, dtype=np.int32)
        self.if_infected[0] = 1
        ......
```

### 型付きメモリービューの計算
calc_next_stateメソッドのブロックは飛ばして, calc_next_stateメソッドです。クラスのメソッドも, 上で見た関数のように.pyxファイル内だけで呼び出せるcdefか, .pyファイルでも呼び出せるcpdefで定義します。また, 戻り値が無い場合は, voidとして設定します。
このメソッドでは, ax = self.pos[j, 0]以降のコードで型付きメモリービューでの計算のコツが分かります。ax = self.pos[j, 0]以降のコードは, 典型的な2点の距離を求めるコードで, NumPy配列であればnumpy.linalg.norm関数を用いて簡単に計算できますが, 型付きメモリービューではそれぞれの要素を展開してから計算する必要があります。
```python
    cpdef void calc_next_state(self, int i):
        cdef:
            int j
            float ax, ay, c0x, c0y

        for j in range(self.num_agents):
            if i == j:
                continue

            if self.if_infected[j] == 1:
                ax = self.pos[j, 0]
                ay = self.pos[j, 1]

                c0x = self.pos[i, 0]
                c0y = self.pos[i, 1]

                if ((c0x-ax) * (c0x-ax) + (c0y-ay) * (c0y-ay)) < self.R:
                # 隣接してカテゴリ1のエージェントがいる
                    self.if_infected[i] = 1  # カテゴリ1に変身
```

シミュレーションコードで特筆すべき点は以上です。次からはコンパイル・ビルド, および.pyファイルでの呼び出しを見ていきます。

### setup.pyファイルの設定
この記事でのsetup.pyファイルは, NumPyモジュールを含めた場合の最小構成です。すなわち, cythonizeの引数に.pyxファイル名を指定し, include_dirsの引数に, NumPyのincludeディレクトリのパスを設定します。
```python
from setuptools import setup
from Cython.Build import cythonize
import numpy as np

setup(
    ext_modules=cythonize('infection_cy.pyx'),
    include_dirs=[np.get_include()]
)
```
setup.pyファイルの詳しい説明については, 「[【目的別】コピペから始めるCython入門](https://hack.nikkei.com/blog/advent20211225/)」が大変参考になります。

### Cythonコードのコンパイル・ビルド
コマンドラインでsetup.pyファイルの存在するディレクトリに移動し, 以下のコマンドを実行します。
```
python setup.py build_ext
```
これを実行してコンパイルエラーが起きなければ, 同一ディレクトリにbuildというフォルダが作成されます。その中身は次のようになっています。
```
build/
├── lib.linux-x86_64-cpython-312
│   └── infection_cy.cpython-312-x86_64-linux-gnu.so
├── temp.linux-x86_64-cpython-312
    └── infection_cy.o
```
このうち, .pyファイルでインポートするのは.soファイルで (Windowsでは.pyd), import文で.pyxファイルの名前を指定してインポートします。ただし, このような階層構造だとインポートを行う時にパスの設定が面倒なので, -iオプション (または--inplace) をつけます。これにより, setup.pyファイルのあるディレクトリに.soファイルがコピーされます (出力に, copying build/lib.linux-x86_64-cpython-312/infection_cy.cpython-312-x86_64-linux-gnu.so -> という文が追加されます)。
```
python setup.py build_ext -i
```
注意点として, .soファイルをビルドした際のPythonのバージョン,　CPUアーキテクチャ (x86/x64 or ARM), およびOSが, .soファイルをインポートして実行する環境と一致している必要があります。これらが異なると, インポートしようとした時にModuleNotFoundErrorが発生します。今回の例で言うと, .soファイルのファイル名にもある通り, インポートして使用する環境は, Python3.12, x86_64, Linuxである必要があります。作成された.soファイルを他のPCで使用する場合などはご注意ください。なお, buildディレクトリは不要なので, 他のプロジェクトで使用する際には.soファイルのコピーだけで十分です。

### .pyファイルでのインポートおよび実行
いよいよCythonコードのインポートです。
```python
import infection_cy

num_agents = 100
timelimits = 100

simulation_cy = infection_cy.InfectionSimulation(
    num_agents=num_agents,
    timelimits=timelimits,
    seed=0
)
simulation_cy.run()
```
実行速度は, 私の環境ではおおよそ0.0017-0.0018秒でした。

また, 純粋Pythonでも実行してみると, おおよそ0.25秒ほどだったので, 約140倍の高速化です。今回ぐらいの処理だと純粋Pythonでも十分に早いですが, 研究用のコードなどで処理が複雑化していくと, 信じられないほどCythonの恩恵が大きくなります。実際, 私が研究で行っていた移動シミュレーションでは, Cythonへの移行により, 純粋Pythonで2時間近く掛かっていたプログラムが10秒で終わるようになり, 研究の試行錯誤のスピードが飛躍的に向上しました。

## まとめ
Cythonは, Pythonと比べてやはり柔軟性は劣りますが, その分圧倒的な速さと, 静的型付けによるコードの堅牢性が魅力だと思います。公式の開発はつい最近も更新があるぐらい活発なのですが, 残念なことに日本語で書かれている記事は少なく, それが入門ハードルを上げているように感じます。私はぜひCythonに流行って欲しいので, この記事がその足がかりになれば幸いです。
なお, 本記事で使用したコード (純粋Python版や可視化も含めて)は, GitHubに挙げていますので, よければご確認ください。

## 参考資料
### 体系的に学ぶ
https://cython.readthedocs.io/en/latest/
↑Cythonの公式サイト。記事執筆付近の更新で, 非常にモダンな見た目のサイトになりました。

https://github.com/cython/cython
↑Cythonの公式ソースコードです。

https://www.oreilly.co.jp/books/9784873117270/
↑Cythonを網羅的に説明した本です。ただし出版日が2015/06/19と古く, 第2版も出版されていません。Cython3.xには対応していないので注意が必要です。

### 入門
https://qiita.com/pashango2/items/45cb85390193d97523ca
↑(更新日: 2017/01/12) Jupyterを使ってとにかく手軽にCythonを実行することにより, Cythonの使用ハードルを下げることができます。また, Cythonを使うべき箇所とそうでない箇所についても, 簡単に説明されています。

https://qiita.com/en3/items/1f1a609c4d7c8f3066a7
↑(更新日: 2020/06/03) Cythonの使い方を簡潔に紹介しています。C言語で書いた関数を扱う方法も説明されています。setup.pyを使った実行です。

https://qiita.com/Aqua-218/items/28ee5fe85f3e3924f08c
↑(更新日: 2025/12/25) かなり新しい記事で, 要点が端的に説明されていて分かりやすいです。型一覧があるため, リファレンスとしても利用できます。setup.pyを使った実行です。

### 高速化のコツ
https://qiita.com/shmpwk/items/d235b258bd11d0ae92dc
↑(更新日: 2020/01/11) CythonでのNumPy配列の扱い方に特化した記事です。NumPy配列オブジェクトをグローバル変数として使えないという点と, 解決策としてのmemoryviewオブジェクトの扱いを説明しています。Jupyterを使った実行です。

https://qiita.com/nena0undefined/items/730424bdffc623ab305a
↑(更新日: 2018/09/28) Cythonにおいて, 型指定による高速化の違いを検証した記事です。結論として, 1.変数の型指定, 2.numpy配列の型指定, 3.関数をcdefで定義して返り値を設定する, の3つが重要であると導かれています。Jupyterを使った実行です。

https://qiita.com/neruoneru/items/6c0fc0496620d2968b57
↑(更新日: 2020/12/06) CythonとNumPyを連携して高速化を図る際のコツを7個, 簡潔にまとめた記事です。参考記事のリンクが充実しています。また, setup.pyとJupyter両方の実行方法を説明しています。

https://qiita.com/Sosuke115/items/a84dad0828ad1b4a8541
↑(更新日: 2020/05/17) Cythonにおいて, コードのどの箇所の型付けが高速化に大きく寄与するのかを調査した記事です。1つの結論として, イテレータ変数の型付けが高速化への影響が大きいということが導かれています。

https://qiita.com/Chippppp/items/d20303f79342cb9c2423
↑(更新日: 2023/09/18) At coderでCythonを使う場合という, 非常にニッチなケースを扱った記事です。C/C++との連携も参考になります。

### 一歩踏み込んだ解説
https://hack.nikkei.com/blog/advent20211225/
↑(更新日: 2021/12/25) 正直Cythonの入門としては難しいです。しかし, 他の記事ではあまり説明されていない, pyxファイル冒頭のマジックコマンドの意味やsetup.pyファイルの中身についても丁寧に説明されています。listやdictといったPythonオブジェクトを使用すると速度が落ちてしまうという点もしっかり注意しつつ, NumPyとの連携方法やC++のvectorを使った方法も紹介されています。全てを説明するのではなく, 他の記事で紹介されている部分 (jupyterでのCython実行、型宣言やクラスの書き方など) は, 適宜記事のリンクによる誘導があります。
