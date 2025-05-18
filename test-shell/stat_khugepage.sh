#!/bin/bash

# 启动 khugepaged
echo "Starting khugepaged..."

if [ -d "/sys/kernel/mm/transparent_hugepage/khugepaged" ]; then
  mm_directory="/sys/kernel/mm/transparent_hugepage/khugepaged"
  pages_colla="$mm_directory/pages_collapsed"
else
  echo "directory not found."
  exit 1
fi

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
output_name="LogKhuge.csv"
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
  header+=",Khuge CPU Usage,meminfo Hpages"
  echo "$header" > "$output_file"
fi

# 获取 ksmd 进程的 PID
khugepage_pid=$(pgrep khugepaged)

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

    # 获取 khugepaged 进程的 CPU 使用率
    khugepaged_cpu_usage=$(top -bn1 | grep "khugepage_pid" | awk '{print $9}' | tr -d '\n')
        if [ -z "$khugepaged_cpu_usage" ]; then
      # echo "Failed to get khugepaged CPU usage with pidstat, trying top."
      khugepaged_cpu_usage=$(top -bn1 | grep "khugepaged" | awk '{print $9}')
    fi
    # 去掉 CPU 使用率字段中的 "%system" 字样
    # khugepaged_cpu_usage="${khugepaged_cpu_usage/%,*}"
    # 将 ksmd CPU 使用率添加到数据行中
    data+=",$khugepaged_cpu_usage"

    # 获取 AnonHugePages 的值
    meminfo_hpage=$(grep "AnonHugePages" /proc/meminfo | awk '{print $2}')
    # 将 AnonHugePages 值添加到数据行中
    data+=",$meminfo_hpage"

    # 获取 AnonPages 的值
    meminfo_page=$(grep "AnonPages" /proc/meminfo | awk '{print $2}')
    # 将 AnonHugePages 值添加到数据行中
    data+=",$meminfo_page"

    # 将数据行写入 CSV 表格
    echo "$data" >> "$output_file"

    # 更新下一个时间点
    next_time=$((next_time + interval))
  fi

  # 计算剩余时间并等待
  sleep "$((next_time - current_time))"
done

echo "Khugepage logging complete. Output saved to: $output_file"
