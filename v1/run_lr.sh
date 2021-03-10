#!/bin/bash
#
# This script runs Common Voice Language Recognition Closed-Set evaluation.

# 包含cmd文件和path文件
. ./cmd.sh
. ./path.sh
# set -e 代表只要出错就停止运行.
set -e

if [ $# -ne 1 ]; then
  echo "Usage: run_lr.sh <date-time>/<audio-file-name>"
  echo "e.g.:"
  echo " run_lr.sh 2021-01-01/audio_file_name.mp3"
  exit 1
fi

# 工作站（10.112.212.188）语种识别上传文件目录
upload_files=/mnt/HD1/niliqiang/upload_files
# 设置trials文件路径
trials=lr_output/data/trials
# 获取输入参数
file_path=$1

# 指示系统的执行阶段
stage=0

# 清空输出文件夹
if [ $stage -le 0 ]; then 
  rm -rf lr_output/data/* lr_output/exp/*
fi

if [ $stage -le 1 ]; then
  # 数据准备，去掉file_path中的日期和/
  utt_id_with_suffix=${file_path#*/}
  utt_id=${utt_id_with_suffix%.*}
  echo "$utt_id language" > lr_output/data/utt2spk
  echo "language $utt_id" > lr_output/data/spk2utt
  echo "$utt_id sox $upload_files/$file_path -t wav -r 16k -b 16 -e signed - |" > lr_output/data/wav.scp
fi

if [ $stage -le 2 ]; then
  # 计算MFCC、进行端点检测（VAD）
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 1 lr_output/data lr_output/exp/make_mfcc lr_output/exp/mfcc >/dev/null
  # make MFCC plus pitch features
  # steps/make_mfcc_pitch.sh --cmd "$train_cmd" --nj 1 lr_output/data lr_output/exp/make_mfcc lr_output/exp/mfcc >/dev/null
  steps/compute_vad_decision.sh --cmd "$train_cmd" --nj 1 lr_output/data lr_output/exp/make_vad lr_output/exp/vad >/dev/null
fi

if [ $stage -le 3 ]; then
  # i-vector提取
  # 三个目录分别为：i-vector提取器，数据目录，ivectors生成目录
  sid/extract_ivectors.sh --cmd "$train_cmd" --nj 1 --num-threads 8 lr_output/model/extractor lr_output/data lr_output/exp/ivectors_test >/dev/null
fi

if [ $stage -le 4 ]; then
  # 如果基于说话人识别的思路，需要生成trials文件
  for lang in zh-CN en ru es ar; do
    echo "$lang $utt_id target" >> $trials
  done
fi

if [ $stage -le 5 ]; then
  # 打分
  mkdir -p lr_output/exp/scores/log
  run.pl lr_output/exp/scores/log/cosine_scoring.log \
    cat $trials \| awk '{print $1" "$2}' \| \
    ivector-compute-dot-products - \
    scp:lr_output/model/ivectors/spk_ivector.scp \
    "ark:ivector-normalize-length scp:lr_output/exp/ivectors_test/ivector.scp ark:- |" \
    lr_output/exp/scores/cosine_scores || exit 1;
fi

if [ $stage -le 6 ]; then
  # 输出结果
  awk '{if(score<$3)target=$1} END {print target}' lr_output/exp/scores/cosine_scores
fi
