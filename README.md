```
|--- patch  (my methods & others code)
|--- test-shell  (test memory save & performance & CPU & NUMA in VM)
|--- vm  (set up for virtual machines, need Ubuntu img)
```

## 配置步骤：

先安装和配置虚拟机

```bash
sudo apt install -y qemu-kvm qemu-system libvirt-daemon-system libvirt-clients bridge-utils virt-manager
```

复制一下虚拟机的镜像，例如我复制到了/home/zz/vm-img/这里

```bash
zz@8001:~$ ls /home/zz/vm-img/
Ubuntu20-clone1.qcow2  Ubuntu20-clone2.qcow2  Ubuntu20-clone3.qcow2  Ubuntu20-clone4.qcow2
```

然后注意一下xml里面的cpu memory和img镜像的位置，没问题之后创建虚拟机

```bash
sudo virsh define ~/gemina-data/vm/Ubuntu1.xml
sudo virsh define ~/gemina-data/vm/Ubuntu2.xml
sudo virsh define ~/gemina-data/vm/Ubuntu3.xml
sudo virsh define ~/gemina-data/vm/Ubuntu4.xml
```

安装Linux的编译工具链

```bash
sudo apt install build-essential bc rsync liblz4-tool libelf-dev cmake autoconf \
     libgoogle-perftools-dev libdaxctl-dev libndctl-dev libipmctl-dev \
     libudev-dev libkmod-dev uuid-dev openssh-server vim git make gcc \
     flex bison dpkg-dev libssl-dev htop ndctl python2 libnuma-dev libtool \
     libkmod-dev gnuplot pkg-config libcapstone-dev \
     ninja-build valgrind libaio1 libaio-dev  numactl libncurses-dev \
     python-is-python3 python3-pip libboost-dev \
```

可能不全，这部分有问题GPT问一下应该可以安装上

之后下载Linux Kernel源码并解压

```bash
wget https://www.kernel.org/pub/linux/kernel/v5.x/linux-5.10.tar.gz
tar -xf linux-5.10.tar.gz
```

把patch打上去，patch是其他方法在原生linux上修改的代码

```bash
cd linux-5.10
#在Makefile里修改一下EXTRAVERSION = -orgin
git init
git add .
git commit -m "orgin"

#例如这里打smartmd的patch
git checkout -b smartmd
patch -p1 < ../gemina-data/patch/SmartMD-5.10-cow.patch
#此时你就可以在vscode的[源代码管理部分]看到它修改了哪些代码
#然后根据需要git commit

#Linux kernel代码很大，需要LSP，即vscode里安装clangd插件，把c/c++插件禁用
#安装clangd后vscode右下角会提示安装clangd-server，点击安装即可
#编译安装内核，之前需要sudo apt install bear
make menuconfig
#之后点击save即可
bear make -j$(nproc) && sudo make modules_install && sudo make install
#bear make之后就会生成clangd的代码提示，这样你就可以点击函数跳转了
#上述命令安装了内核，如果遇到pem报错，需要去.config里查找pem
#需要把它设置为空CONFIG_SYSTEM_TRUSTED_KEYS=""
```

内核安装好后去grub更换内核，更改这部分内容为对应的内核名

```bash
GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 5.4.0-144-generic"
```

如果不知道内核名称用sudo update-grub查看

例如上述把5.4.0-144-generic的内容换为5.10.0-gemina-old+

然后再sudo update-grub刷新一下，重启后就可以测试新换内核，uname -r查看当前内核名

```bash
cd gemina-data/test-shell
sudo ./run_kvm_short.sh
```

如果遇到虚拟机登录密钥的问题，问一下GPT差不多可以解决

跟连服务器的步骤差不多

KSM的测试指标可以看一下论文或者博客

https://pfzuo.github.io/2016/03/16/Memory-Deduplication/

https://github.com/ustcadsl/SmartMD

https://github.com/dolohow/uksm

graph500的性能是harmonic_mean_TEPS越大越好

其他大部分负载性能是运行时间，越小越好