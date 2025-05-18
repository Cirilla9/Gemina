#!/bin/bash
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
output_name="LogPCM-memory.csv"
output_file="${output_dir}/${output_name}"

# 写入表头（如果文件已存在则覆盖）
echo "SKT 0 Memory (MB/s),SKT 1 Memory (MB/s)" > "$output_file"

# 启动 PCM 监控，并行缓冲 → 逐行抓取 → 提取浮点数 → 写入 CSV
sudo /home/zz/pcm/build/bin/pcm-memory "$interval" \
  | stdbuf -oL grep --line-buffered "SKT  0 Memory\|SKT  1 Memory" \
  | sed -u -n \
      's/.*SKT  0 Memory.*: *\([0-9]\+\.[0-9]\+\).*SKT  1 Memory.*: *\([0-9]\+\.[0-9]\+\).*/\1,\2/p' \
  >> "$output_file"
