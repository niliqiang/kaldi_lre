#!/bin/bash
# Copyright  2014-2015  David Snyder
#                       Daniel Povey
#				2020	niliqiang
# Apache 2.0.
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
vaddir=`pwd`/mfcc

# 设置语料存放路径和语料URL
# Ubuntu双系统数据集路径
#data=/dataset/cv_corpus
# 工作站（10.112.212.188）数据集路径
#data=/mnt/HD1/niliqiang/cv_corpus 
# 服务器（10.103.238.161）数据集路径
data=/mnt/DataDrive172/niliqiang/cv_corpus 

# 设置trials文件路径
trials=data/lre/test/trials

# 指示系统的执行阶段
stage=0

# :<<!
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
	# 爱尔兰语(ga_IE)
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
  # 计算MFCC、进行端点检测（VAD）
  for part in train dev test; do
    # --cmd 指示：how to run jobs, run.pl或queue.pl
	# --nj 指示：number of parallel jobs, 默认为4，需要注意的是nj不能超过说话人数（语种数），以免分割数据的时候被拒绝
	# 三个目录分别为：数据目录，log目录，mfcc生成目录
    # steps/make_mfcc.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_mfcc/$part $mfccdir
	# make MFCC plus pitch features
	steps/make_mfcc_pitch.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_mfcc/$part $mfccdir || exit 1
	utils/fix_data_dir.sh data/lre/$part
    steps/compute_vad_decision.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_vad/$part $vaddir
    utils/fix_data_dir.sh data/lre/$part
  done
fi
# !
# :<<!
if [ $stage -le 2 ]; then
  # 使用训练集训练UBM
  # 使用train_diag_ubm.sh脚本的speaker-id版本，二阶动态MFCC，不是SDC，训练一个256的混合高斯
  sid/train_diag_ubm.sh --cmd "$train_cmd" --nj 5 data/lre/train 256 exp/diag_ubm
  # 用先训练的diag_ubm来训练完整的UBM
  sid/train_full_ubm.sh --cmd "$train_cmd" --nj 5 --remove-low-count-gaussians false data/lre/train exp/diag_ubm exp/full_ubm
fi

if [ $stage -le 3 ]; then
  # 使用训练集训练i-vector提取器，实际运行的线程数是nj*num_processes*num_threads，会消耗大量内存，防止程序崩溃，降低nj、num_threads、num_processes（16G内存需要都降到2）
  # 还需要注意的是数据分块数为nj*num_processes，这个数据不能超过说话人数（语种数）
  sid/train_ivector_extractor.sh --cmd "$train_cmd" --nj 5 --num_threads 2 --num_processes 1 --num-iters 5 exp/full_ubm/final.ubm data/lre/train exp/extractor
fi
# !

if [ $stage -le 4 ]; then
  # i-vector提取
  for part in train dev test; do
    # 三个目录分别为：i-vector提取器，数据目录，ivectors生成目录
    sid/extract_ivectors.sh --cmd "$train_cmd" --nj 5 exp/extractor data/lre/$part exp/ivectors_$part
  done
fi

:<<!
# 基于语种识别lre07的思路
if [ $stage -le 5 ]; then
  # 基于语种识别lre07的思路，需要根据i-vector，训练逻辑回归模型
  lid/run_logistic_regression.sh --prior-scale 0.70 --conf conf/logistic-regression.conf
  # Train error-rate: %ER 0.03
  # Test error-rate: %ER 36.63

  # 基于语种识别lre07的思路，计算ER和C_avg
  local/lre07_cv_eval.sh exp/ivectors_test local/general_lr_closed_set_langs.txt
  # Duration (sec):    avg
  #         ER (%):  36.63
  #      C_avg (%):  34.07
fi
!

# :<<!
# 基于说话人识别的思路
if [ $stage -le 5 ]; then
  # 如果基于说话人识别的思路，需要生成trials文件
  # 由于数据库中没有直接的数据来生成trials文件，需要自己组合生成
  # 这个文件是说话人识别特有的，简单来说，就是告诉系统，哪段语音是说话人X说的，哪段语音不是。
  lid/produce_trials.py data/lre/test/utt2lang $trials
  # 余弦距离打分
  local/cosine_scoring.sh data/lre/train data/lre/test \
  exp/ivectors_train exp/ivectors_test $trials exp/scores_cosine_gmm_256
  # 计算EER，其中'-'表示从标准输入中读一次数据
  awk '{print $3}' exp/scores_cosine_gmm_256/cosine_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is 23.3611%, at threshold 5.10275
  echo '\n'
fi

if [ $stage -le 6 ]; then
  # LDA
  local/lda_scoring.sh data/lre/train data/lre/train data/lre/test \
  exp/ivectors_train exp/ivectors_train exp/ivectors_test $trials exp/scores_lda_gmm_256
  # 计算EER，其中'-'表示从标准输入中读一次数据
  awk '{print $3}' exp/scores_lda_gmm_256/lda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is 22.1683%, at threshold 5.84638
  echo '\n'
fi

if [ $stage -le 7 ]; then
  # PLDA
  local/plda_scoring.sh data/lre/train data/lre/train data/lre/test \
  exp/ivectors_train exp/ivectors_train exp/ivectors_test $trials exp/scores_plda_gmm_256
  # 计算EER，其中'-'表示从标准输入中读一次数据
  awk '{print $3}' exp/scores_plda_gmm_256/plda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Without i-vector mean compute: Equal error rate is 29.3057%, at threshold -170.614
  # With i-vector mean compute: Equal error rate is 30.2269%, at threshold -206.967
fi
# !


