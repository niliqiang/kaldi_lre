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
data=/mnt/HD1/niliqiang/cv_corpus

mfccdir=`pwd`/mfcc

# 指示系统的执行阶段
stage=0

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
  for part in train test; do
    steps/nnet2/dump_bottleneck_features.sh --nj 4 \
      data/lre/$part data/lre/${part}_bnf exp/nnet_bottleneck_clean_100_gpu exp/param_bnf exp/dump_bnf
fi




