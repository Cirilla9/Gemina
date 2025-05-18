#!/bin/bash
#
# log_numa_summary.sh
# 每 interval 秒从 pcm-numa 抓取汇总行(*)，输出到 CSV
#
# 用法：./log_numa_summary.sh [interval] [output_file]
#   interval    采样间隔（秒），默认 5
#   output_file 输出文件，默认 numa_summary.csv

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
output_name="LogPCM-numa.csv"
output_file="${output_dir}/${output_name}"

# 写入表头（如果文件已存在则覆盖）
echo "Time,IPC,Instructions,Cycles,LocalDRAM,RemoteDRAM" > "$output_file"

# 启动 pcm-numa，抓取“*”行，提取 5 列数字并追加到 CSV
stdbuf -oL sudo /home/zz/pcm/build/bin/pcm-numa 5 2>&1 \
  | stdbuf -oL grep --line-buffered '^[[:space:]]*\*' \
  | awk '{
      # 增加时间戳
      cmd="date +\"%Y-%m-%d %H:%M:%S\""; cmd|getline t; close(cmd);
      # $2=IPC; $3,$4=Inst; $5,$6=Cycles; $7,$8=Local; $9,$10=Remote
      printf "%s,%s,%s%s,%s%s,%s%s,%s%s\n", t, $2, $3,$4, $5,$6, $7,$8, $9,$10
    }' \
  >> "$output_file"
