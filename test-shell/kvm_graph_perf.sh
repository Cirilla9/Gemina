#!/bin/bash

# 获取当前日期和时间
current_date=$(date +"%m.%d")
current_time=$(date +"%H.%M")

# 获取当前运行的内核名称
kernel_name=$(uname -r)

# 定义输出文件路径
output_directory="./$kernel_name/graph/${current_date}_${current_time}"

# 创建输出文件目录
mkdir -p "$output_directory"

# 定义输出文件名的前缀
output_prefix="Ubuntu"

# 定义虚拟机列表
vm_list=$(virsh list --name --all)

# 创建一个数组来存储后台任务
declare -a tasks

sleep 5

# 循环遍历每个虚拟机
for vm_name in $vm_list; do
  # 检查虚拟机名称是否匹配特定规则，例如vm1
  if [[ $vm_name =~ ^Ubuntu[0-9]+$ ]]; then
    # 检查虚拟机状态
    vm_status=$(virsh domstate $vm_name)

    if [[ $vm_status =~ "running" ]]; then
      echo "虚拟机 $vm_name 已经开机，执行强制重启"
      virsh reset $vm_name
    else
      echo "启动虚拟机 $vm_name"
      virsh start $vm_name
    fi
  fi
done

# 等待所有虚拟机启动完成
sleep 30
echo "Log KSM & CPU......"
./stat_ksm.sh "$output_directory" &
script_two_pid=$!

./stat_khugepage.sh "$output_directory" &
script_third_pid=$!

./stat_memory.sh "$output_directory" &
script_four_pid=$!

./stat_numa.sh "$output_directory" &
script_five_pid=$!

function killSubproc(){
    kill $(jobs -p -r)
}

trap killSubproc INT
trap 'echo "Cleaning up..."; kill ${script_four_pid} 2>/dev/null' EXIT
trap 'echo "Cleaning up..."; kill ${script_five_pid} 2>/dev/null' EXIT

# 循环遍历每个虚拟机
for vm_name in $vm_list; do
  if [[ $vm_name =~ ^Ubuntu[0-9]+$ ]]; then
    vm_ip=$(virsh domifaddr $vm_name | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
    if [ -z "$vm_ip" ]; then
      echo "无法获取虚拟机 $vm_name 的IP地址"
      continue
    fi

    echo "虚拟机 $vm_name，IP地址为 $vm_ip"
    echo "run graph..."

    ssh zz@$vm_ip 'echo "123456" | sudo -S sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag; echo 0 | sudo tee /proc/sys/kernel/randomize_va_space"'

    # 启动 VM 中负载并记录 PID
    ssh zz@$vm_ip "~/benchmarks/graph500-master/./seq-csr/seq-csr -s 23 -e 16" > "${output_directory}/${vm_name}.txt" &
    vm_pid=$!

    # 记录本地和远程内存访问
    # 获取对应的QEMU进程PID
    qemu_pid=$(ps aux | grep "guest=$vm_name" | grep -v grep | awk '{print $2}')
    if [ -z "$qemu_pid" ]; then
      echo "无法找到 $vm_name 的 QEMU 进程！"
      continue
    fi

    echo "绑定 QEMU 进程 PID: $qemu_pid，开始记录NUMA内存访问..."
    
    /home/zz/2025data/perf/pmu-tools/ocperf.py stat -e ocr.reads_to_core.local_dram,ocr.reads_to_core.remote_dram \
    -p "$qemu_pid" > "${output_directory}/${vm_name}_dram.txt" 2>&1 &

    tasks+=($vm_pid)
  fi
done


TRACE_DIR=/sys/kernel/debug/tracing
# 等待所有后台任务完成
for task in "${tasks[@]}"; do
  # sudo cat "$TRACE_DIR/trace" >> "${output_directory}/trace.txt"
  wait $task
done

echo "run expr success , stop log"
kill "$script_two_pid"
kill "$script_third_pid"
kill "$script_four_pid"
kill "$script_five_pid"

# 停止 KSM
echo "Stopping KSM..."
sudo echo 2 >/sys/kernel/mm/ksm/run
sudo echo 0 >/sys/kernel/mm/ksm/run

# 循环遍历每个虚拟机
for vm_name in $vm_list; do
  # 检查虚拟机名称是否匹配特定规则，例如vm1
  if [[ $vm_name =~ ^Ubuntu[0-9]+$ ]]; then
    # 检查虚拟机状态
    vm_status=$(virsh domstate $vm_name)

    if [[ $vm_status =~ "running" ]]; then
      echo "run $vm_name over，shut down"
      virsh destroy $vm_name
    fi
  fi
done

csv_file="${output_directory}/dram_access.csv"
echo "vm_name,local_dram_reads,remote_dram_reads" > "$csv_file"

for vm_name in $vm_list; do
  if [[ $vm_name =~ ^Ubuntu[0-9]+$ ]]; then
    dram_file="${output_directory}/${vm_name}_dram.txt"
    if [ -f "$dram_file" ]; then
      local_val=$(awk '/ocr_reads_to_core_local_dram/ && $1 ~ /^[0-9,]+$/{gsub(",", "", $1); print $1}' "$dram_file")
      remote_val=$(awk '/ocr_reads_to_core_remote_dram/ && $1 ~ /^[0-9,]+$/{gsub(",", "", $1); print $1}' "$dram_file")
      echo "$vm_name,${local_val:-0},${remote_val:-0}" >> "$csv_file"
    fi
  fi
done

# 统计各输出文件中 harmonic_mean_TEPS 的平均值、最大值和最小值
teps_metric="harmonic_mean_TEPS"
teps_values=()
for vm_name in $vm_list; do
  # 检查虚拟机名称是否匹配特定规则，例如vm1
  if [[ $vm_name =~ ^Ubuntu[0-9]+$ ]]; then
    output_file="${output_directory}/${vm_name}.txt"

    # 从输出文件中提取 harmonic_mean_TEPS 属性的值
    teps_value=$(grep "$teps_metric" "$output_file" | awk '{print $2}')

    # 检查是否成功获取到 TEPS 值
    if [ -z "$teps_value" ]; then
      echo "无法获取虚拟机 $vm_name 的 $teps_metric 值"
      continue
    fi

    # 添加 TEPS 值到数组中
    teps_values+=("$teps_value")
  fi
done

# 检查是否有有效的 TEPS 值
if [ ${#teps_values[@]} -eq 0 ]; then
  echo "0 = $teps_metric 值"
  exit
fi

# 计算 TEPS 值的平均值
sum=0
for teps in "${teps_values[@]}"; do
  sum=$(awk "BEGIN {print $sum + $teps; exit}")
done
average=$(awk "BEGIN{print $sum / ${#teps_values[@]}; exit}")

# 计算 TEPS 值的最大值和最小值
max_value=$(printf '%s\n' "${teps_values[@]}" | sort -rn | head -n1)
min_value=$(printf '%s\n' "${teps_values[@]}" | sort -n | head -n1)

# 创建 harmonic_mean_TEPS.txt 文件并保存统计结果
result_file="${output_directory}/out_num.txt"
echo "average_$teps_metric,max_$teps_metric,min_$teps_metric" > "$result_file"
echo "$average,$max_value,$min_value" >> "$result_file"

echo "所有负载执行完毕，并将输出保存到目录：$output_directory"
echo "统计结果已保存到文件：$result_file"
TRACE_DIR=/sys/kernel/debug/tracing
sudo cat "$TRACE_DIR/trace" > "${output_directory}/trace1.txt"
sleep 10
# kill $(jobs -p -r)
# echo "Killing leftover pcm-numa and pcm-memory processes..."
# sudo pkill -f pcm-numa
# sudo pkill -f pcm-memory