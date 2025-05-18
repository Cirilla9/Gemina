#!/bin/bash

# 启动 KSM
echo "Starting KSM..."
TRACE_DIR=/sys/kernel/debug/tracing

# 判断 mm 目录下的子目录是 ksm 还是 uksm
if [ -d "/sys/kernel/mm/ksm" ]; then
  mm_directory="/sys/kernel/mm/ksm"
  sudo echo 2 >"$mm_directory/run"
  sudo echo 0 >"$mm_directory/run"
  sudo echo 1 >"$mm_directory/run"
  sudo echo 10001 >"$mm_directory/pages_to_scan"
  sudo echo 20 >"$mm_directory/sleep_millisecs"
elif [ -d "/sys/kernel/mm/uksm" ]; then
  mm_directory="/sys/kernel/mm/uksm"
  sudo echo 0 >"$mm_directory/run"
  sudo echo 1 >"$mm_directory/run"
else
  echo "KSM or UKSM directory not found."
  exit 1
fi

# 1 > large trace
sudo echo 40960 > /sys/kernel/debug/tracing/buffer_size_kb
sudo echo 1 > /sys/kernel/debug/tracing/tracing_on
sudo echo > $TRACE_DIR/trace

# 1 > transparent_page
echo "never" > /sys/kernel/mm/transparent_hugepage/enabled
echo "never" > /sys/kernel/mm/transparent_hugepage/defrag

# 100 > khugepage
sudo echo 10000 > /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan
# sudo echo 511 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_shared
sudo echo 100 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
sudo echo 20 > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
sudo echo 20 > /sys/kernel/mm/transparent_hugepage/khugepaged/alloc_sleep_millisecs

# 获取时间间隔参数（默认为5秒）
output_dir="$1"
interval=5

# 获取当前日期和时间
start_time=$(date +"%s")
date_time=$(date +"%m%d_%H%M")

# 计算下一个5秒间隔的起始时间
next_time=$((start_time + (interval - (start_time % interval))))

# 获取当前内核名称
kernel_name=$(uname -r | tr '.' '-')

# 定义输出文件路径
output_name="LogKSM.csv"
output_file="${output_dir}/${output_name}"

# 获取要统计的文件列表
file_list=()
while IFS= read -r -d '' file; do
  file_list+=("$file")
done < <(find "$mm_directory" -type f -print0)

# 检查输出文件是否存在，如果不存在则创建新的 CSV 表头
if [ ! -f "$output_file" ]; then
  # 写入表头
  header="Time Elapsed"
  for file in "${file_list[@]}"; do
    header+=",$(basename "$file")"
  done
  # 添加 CPU 占用的表头
  header+=",KSM CPU Usage,my_merge CPU Usage"
  header+=",Node0_KSM_Pages,Node1_KSM_Pages"
  echo "$header" > "$output_file"
fi

# 获取 ksmd 进程的 PID
ksmd_pid=$(pgrep ksmd)
my_merge_pid=$(pgrep my_merge)
uksmd_pid=$(pgrep uksmd)

# 主循环
while true; do
  # 计算时间差
  current_time=$(date +"%s")
  time_elapsed=$((current_time - start_time))

  # 如果当前时间超过下一个5秒间隔的起始时间，记录数据并更新下一个时间点
  if [ "$current_time" -ge "$next_time" ]; then
    # 追加数据到 CSV 表格
    data="$((time_elapsed / interval * interval))"
    for file in "${file_list[@]}"; do
      # 读取文件的值
      value=$(cat "$file")

      # 将值添加到数据行中
      data+=",$value"
    done

    # 获取 ksmd 进程的 CPU 使用率
# 获取 ksmd 进程的 CPU 使用率
  ksmd_cpu_usage=$(pidstat -u -p "$ksmd_pid" 1 1 | awk 'NR==4 {print $6}')
  ksmd_cpu_usage="${ksmd_cpu_usage:-}"  # 如果为空则默认空
  data+=",$ksmd_cpu_usage"

  # 获取 my_merge 进程的 CPU 使用率
  my_merge_cpu_usage=$(pidstat -u -p "$my_merge_pid" 1 1 | awk 'NR==4 {gsub(/%system/, ""); print $6}' | tr -d '\n')
  my_merge_cpu_usage="${my_merge_cpu_usage:-}"
  data+=",$my_merge_cpu_usage"

  # 获取 uksmd 进程的 CPU 使用率
  uksmd_cpu_usage=$(pidstat -u -p "$uksmd_pid" 1 1 | awk 'NR==4 {gsub(/%system/, ""); print $6}' | tr -d '\n')
  uksmd_cpu_usage="${uksmd_cpu_usage:-}"
  data+=",$uksmd_cpu_usage"

  # 获取 KSM NUMA Ratio
  ksm_numa_ratio=$(cat /proc/ksm_numa_ratio 2>/dev/null)
  node_0_pages=$(echo "$ksm_numa_ratio" | grep "Node 0:" | awk '{print $3}')
  node_1_pages=$(echo "$ksm_numa_ratio" | grep "Node 1:" | awk '{print $3}')
  node_0_pages="${node_0_pages:-}"
  node_1_pages="${node_1_pages:-}"
  data+=",$node_0_pages,$node_1_pages"

    # 将数据行写入 CSV 表格
    echo "$data" >> "$output_file"

    # 更新下一个时间点
    next_time=$((next_time + interval))
    # sudo echo 0 >"$mm_directory/run"
  fi

  # 计算剩余时间并等待
  sleep "$((next_time - current_time))"
  # sudo echo 1 >"$mm_directory/run"
done

# 停止 KSM
echo "Stopping KSM..."
if [ -d "/sys/kernel/mm/ksm" ]; then
  sudo echo 2 >"$mm_directory/run"
  sudo echo 0 >"$mm_directory/run"
fi

echo "KSM logging complete. Output saved to: $output_file"