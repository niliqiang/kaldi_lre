#!/bin/bash
# Copyright  2014-2015  David Snyder
#                       Daniel Povey
# Apache 2.0.
# modified by niliqiang
#
# This script runs the NIST 2007 General Language Recognition Closed-Set
# evaluation.

# 根据 sre16 v1 以及 lre07 v1 改写，由于 lre07 的代码结构可读性一般，主要根据 sre16 改写
# 使用common voice数据库

# 包含cmd文件和path文件
. ./cmd.sh
. ./path.sh
# set -e 代表只要出错就停止运行.
set -e

mfccdir=`pwd`/mfcc
# 暂时不进行VAD
# vaddir=`pwd`/mfcc

# 设置语料存放路径和语料URL
data=/dataset/cv_corpus
# 指示系统的执行阶段
stage=0

if [ $stage -le 0 ]; then
  # 数据准备（已验证的训练集，开发集，测试集）
  for part in train dev test; do
    # 汉语(zh_CN)
    local/data_prep.pl $data/zh_CN $part data/zh_CN/$part
	# 土耳其语(tr)
	local/data_prep.pl $data/tr $part data/tr/$part
	# 意大利语(it)
	local/data_prep.pl $data/it $part data/it/$part
	# 俄语(ru)
	local/data_prep.pl $data/ru $part data/ru/$part
	# 爱尔兰语(ru)
	local/data_prep.pl $data/ga_IE $part data/ga_IE/$part
  done
  
  # 使用修改之后的combine_data.sh，将之前准备的数据整合到一起
  for part in train dev test; do
    local/combine_data.sh data/lre/$part \
      data/zh_CN/$part data/tr/$part data/it/$part data/ru/$part data/ga_IE/$part
    utils/validate_data_dir.sh --no-text --no-feats data/lre/$part
    utils/fix_data_dir.sh data/lre/$part
  done
fi

if [ $stage -le 1 ]; then
  # 计算MFCC
  for part in train dev test; do
    # --cmd 指示：how to run jobs, run.pl或queue.pl
	# --nj 指示：number of parallel jobs, 默认为4
	# 三个目录分别为：数据目录，log目录，mfcc生成目录
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 20 data/lre/$part exp/make_mfcc/$part $mfccdir
  done
fi



