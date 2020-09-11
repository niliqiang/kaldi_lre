#!/bin/bash
# Copyright  2014-2015  David Snyder
#                       Daniel Povey
#				2020	niliqiang
# Apache 2.0.
#

# 包含cmd文件和path文件
. ./cmd.sh
. ./path.sh
# set -e 代表只要出错就停止运行.
set -e

# 设置语料存放路径和语料URL
#（如需重新训练带瓶颈层的神经网络，注意local/train_bottleneck_nnet.sh中的数据路径）
# 工作站（10.112.212.188）数据集路径
# data=/mnt/HD1/niliqiang/cv_corpus
# 服务器（10.103.238.151）数据集路径
data=/mnt/DataDrive172/niliqiang/cv_corpus

mfccdir=`pwd`/mfcc

# 指示系统的执行阶段
stage=4

if [ $stage -le 0 ]
then
  # Train a NN on about 100 hours of the librispeech clean data set.
  local/train_nnet_bottleneck.sh
fi

if [ $stage -le 1 ]; then
  # 数据准备（已验证的训练集，开发集，测试集）
  for part in train dev test; do
    # 汉语(zh_CN)
    local/data_prep_cv.pl $data/zh_CN $part data/zh_CN/$part
    # 土耳其语(tr)
    local/data_prep_cv.pl $data/tr $part data/tr/$part
    # 意大利语(it)
    local/data_prep_cv.pl $data/it $part data/it/$part
    # 俄语(ru)
    local/data_prep_cv.pl $data/ru $part data/ru/$part
    # 爱尔兰语(ga_IE)
    local/data_prep_cv.pl $data/ga_IE $part data/ga_IE/$part
  done

  # train与dev合并
  local/combine_data.sh data/lre/train \
    data/zh_CN/train data/tr/train data/it/train data/ru/train data/ga_IE/train \
	  data/zh_CN/dev   data/tr/dev   data/it/dev   data/ru/dev   data/ga_IE/dev
  local/combine_data.sh data/lre/test \
    data/zh_CN/test data/tr/test data/it/test data/ru/test data/ga_IE/test
  for part in train test; do
    utils/validate_data_dir.sh --no-text --no-feats data/lre/$part
    utils/fix_data_dir.sh data/lre/$part
  done
fi

if [ $stage -le 2 ]; then
  # 计算MFCC、CMVN
  for part in train test; do
    # --nj 指示：number of parallel jobs, 默认为4，需要注意的是nj不能超过说话人数（语种数），以免分割数据的时候被拒绝
    # 三个目录分别为：数据目录，log目录，mfcc生成目录
    # make MFCC plus pitch features
    local/make_mfcc_pitch.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_mfcc/$part $mfccdir || exit 1
    steps/compute_cmvn_stats.sh data/lre/$part exp/make_mfcc/$part $mfccdir
  done
fi

if [ $stage -le 3 ]; then
  # 提取BNF特征
  [ ! -d exp/param_bnf ] && mkdir -p exp/param_bnf
  for part in train test; do
    steps/nnet2/dump_bottleneck_features.sh --nj 4 \
      data/lre/$part data/lre/${part}_bnf exp/nnet_bottleneck_clean_100 exp/param_bnf exp/dump_bnf
  done
fi

if [ $stage -le 4 ]; then
  # VAD
  for part in train test; do
    steps/compute_vad_decision.sh --cmd "$train_cmd" --nj 5 data/lre/${part}_bnf exp/make_vad/$part $vaddir
    utils/fix_data_dir.sh data/lre/${part}_bnf
  done
fi

if [ $stage -le 4 ]; then
  steps/compute_vad_decision.sh --cmd "$train_cmd" --nj 5 data/lre/${part}_bnf exp/make_vad/$part $vaddir
    utils/fix_data_dir.sh data/lre/$part
  # 使用训练集训练UBM
  # 使用train_diag_ubm.sh脚本的speaker-id版本，BNF特征，训练一个1024的混合高斯
  sid/train_diag_ubm.sh --cmd "$train_cmd" --nj 5 data/lre/train_bnf 1024 exp/diag_ubm
  # 用先训练的diag_ubm来训练完整的UBM
  sid/train_full_ubm.sh --cmd "$train_cmd" --nj 5 --remove-low-count-gaussians false data/lre/train_bnf exp/diag_ubm exp/full_ubm
fi

if [ $stage -le 5 ]; then
  # 使用训练集训练i-vector提取器，实际运行的线程数是nj*num_processes*num_threads，会消耗大量内存，防止程序崩溃，降低nj、num_threads、num_processes（16G内存需要都降到2）
  # 还需要注意的是数据分块数为nj*num_processes，这个数据不能超过说话人数（语种数）
  sid/train_ivector_extractor.sh --cmd "$train_cmd" --nj 5 --num_threads 2 --num_processes 1 --num-iters 8 exp/full_ubm/final.ubm data/lre/train_bnf exp/extractor
fi

