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

# 设置语料存放路径和语料URL
# Ubuntu双系统数据集路径
#data=/dataset/cv_corpus
# 工作站（10.112.212.188）数据集路径
data=/mnt/HD1/niliqiang/cv_corpus/cv-corpus-6.1-2020-12-11
musan_data=/mnt/HD1/niliqiang/musan
rirs_data=/mnt/HD1/niliqiang/RIRS_NOISES
# 服务器（10.103.238.161）数据集路径
# data=/mnt/DataDrive172/niliqiang/cv_corpus
# musan_data=/mnt/DataDrive172/niliqiang/musan
# rirs_data=/mnt/DataDrive172/niliqiang/RIRS_NOISES

# 设置trials文件路径
trials=data/lre/test/trials

# 指示系统的执行阶段
stage=0

# 清空输出文件夹
if [ $stage -le 0 ]; then 
  rm -rf data/* exp/*
fi

# :<<!
if [ $stage -le 1 ]; then
  # 数据准备（已验证的训练集，开发集，测试集）
  for part in train dev test; do
    # # 汉语(zh_CN)
    # local/data_prep.pl $data/zh_CN $part data/zh_CN/$part
    # # 土耳其语(tr)
    # local/data_prep.pl $data/tr $part data/tr/$part
    # # 意大利语(it)
    # local/data_prep.pl $data/it $part data/it/$part
    # # 俄语(ru)
    # local/data_prep.pl $data/ru $part data/ru/$part
    # # 爱尔兰语(ga_IE)
    # local/data_prep.pl $data/ga_IE $part data/ga_IE/$part

    # 汉语(zh-CN)
    local/data_prep.pl $data/zh-CN $part data/zh-CN/$part
    # 英语(en)
    local/data_prep.pl $data/en $part data/en/$part
    # 俄语(ru)
    local/data_prep.pl $data/ru $part data/ru/$part
    # 西班牙语(es)
    local/data_prep.pl $data/es $part data/es/$part
    # 阿拉伯语(ar)
    local/data_prep.pl $data/ar $part data/ar/$part
  done
  
  # 使用修改之后的combine_data.sh，将之前准备的数据整合到一起
  # train与dev独立
  # for part in train dev test; do
  #   local/combine_data.sh data/lre/$part \
  #     data/zh_CN/$part data/tr/$part data/it/$part data/ru/$part data/ga_IE/$part
  #   utils/validate_data_dir.sh --no-text --no-feats data/lre/$part
  #   utils/fix_data_dir.sh data/lre/$part
  # done

  # train与dev合并
  # local/combine_data.sh data/lre/train \
  #   data/zh_CN/train data/tr/train data/it/train data/ru/train data/ga_IE/train \
	#   data/zh_CN/dev   data/tr/dev   data/it/dev   data/ru/dev   data/ga_IE/dev
  # local/combine_data.sh data/lre/test \
  #   data/zh_CN/test data/tr/test data/it/test data/ru/test data/ga_IE/test

  # train与dev合并
  local/combine_data.sh data/lre/train \
    data/zh-CN/train data/en/train data/ru/train data/es/train data/ar/train \
	  data/zh-CN/dev   data/en/dev   data/ru/dev   data/es/dev   data/ar/dev
  local/combine_data.sh data/lre/test \
    data/zh-CN/test data/en/test data/ru/test data/es/test data/ar/test

  # 过滤短语音
  for part in train test; do
    utils/data/get_utt2dur.sh data/lre/$part
    mv data/lre/${part}/utt2dur data/lre/${part}/utt2dur.bk
    mv data/lre/${part}/wav.scp data/lre/${part}/wav.scp.bk
    mv data/lre/${part}/utt2spk data/lre/${part}/utt2spk.bk
    awk '$2>=3 {print $0}' data/lre/${part}/utt2dur.bk > data/lre/${part}/utt2dur
    awk 'NR==FNR {target[$1]=$2; next} {if($1 in target) print $0}' data/lre/${part}/utt2dur data/lre/${part}/wav.scp.bk > data/lre/${part}/wav.scp
    awk 'NR==FNR {target[$1]=$2; next} {if($1 in target) print $0}' data/lre/${part}/utt2dur data/lre/${part}/utt2spk.bk > data/lre/${part}/utt2spk
    utils/utt2spk_to_spk2utt.pl data/lre/${part}/utt2spk > data/lre/${part}/spk2utt
    cp data/lre/${part}/utt2spk data/lre/${part}/utt2lang
    cp data/lre/${part}/spk2utt data/lre/${part}/lang2utt

    utils/validate_data_dir.sh --no-text --no-feats data/lre/$part
    utils/fix_data_dir.sh data/lre/$part
  done
  # 音速扰动sp
  # 音量扰动vp
  # local/data/perturb_data_dir_speed_3way.sh data/lre/train data/lre/train_sp
  # local/data/perturb_data_dir_volume_handler.sh data/lre/train data/lre/train_vp
  # utils/combine_data.sh data/lre/train_tmp data/lre/train_sp data/lre/train_vp
  # rm -rf data/lre/train
  # mv data/lre/train_tmp data/lre/train
fi

if [ $stage -le 2 ]; then
  # 计算MFCC、进行端点检测（VAD）
  # for part in train dev test; do
  for part in train test; do
    # --cmd 指示：how to run jobs, run.pl或queue.pl
    # --nj 指示：number of parallel jobs, 默认为4，需要注意的是nj不能超过说话人数（语种数），以免分割数据的时候被拒绝
    # 三个目录分别为：数据目录，log目录，mfcc生成目录
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_mfcc/$part exp/mfcc || exit 1
    # make MFCC plus pitch features
    # steps/make_mfcc_pitch.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_mfcc/$part exp/mfcc || exit 1
    utils/fix_data_dir.sh data/lre/$part
    steps/compute_vad_decision.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_vad/$part exp/vad
    utils/fix_data_dir.sh data/lre/$part
  done
fi
# !
# :<<!
if [ $stage -le 3 ]; then
  # 使用训练集训练UBM
  # 使用train_diag_ubm.sh脚本的speaker-id版本，二阶动态MFCC，不是SDC，训练一个1024的混合高斯
  sid/train_diag_ubm.sh --cmd "$train_cmd" --nj 5 data/lre/train 1024 exp/diag_ubm
  # 用先训练的diag_ubm来训练完整的UBM
  sid/train_full_ubm.sh --cmd "$train_cmd" --nj 5 --remove-low-count-gaussians false data/lre/train exp/diag_ubm exp/full_ubm
fi

if [ $stage -le 3 ]; then
  # 使用训练集训练i-vector提取器，实际运行的线程数是nj*num_processes*num_threads，会消耗大量内存，防止程序崩溃，降低nj、num_threads、num_processes（16G内存需要都降到2）
  # 还需要注意的是数据分块数为nj*num_processes，这个数据不能超过说话人数（语种数）
  sid/train_ivector_extractor.sh --cmd "$train_cmd" --nj 5 --num_threads 2 --num_processes 1 --num-iters 8 exp/full_ubm/final.ubm data/lre/train exp/extractor
fi
# !

# 数据增强
# 加混响：混响包含了real和simulated
# 加性噪声：加性包含人声babble，音乐背景声和真实噪声
if [ $stage -le 4 ]; then
  utils/data/get_utt2num_frames.sh --nj 5 --cmd "$train_cmd" data/lre/train
  frame_shift=0.01
  awk -v frame_shift=$frame_shift '{print $1, $2*frame_shift;}' data/lre/train/utt2num_frames > data/lre/train/reco2dur
  
  # Make a version with reverberated speech
  rvb_opts=()
  rvb_opts+=(--rir-set-parameters "0.5, ${rirs_data}/simulated_rirs/smallroom/rir_list")
  rvb_opts+=(--rir-set-parameters "0.5, ${rirs_data}/simulated_rirs/mediumroom/rir_list")

  # Make a reverberated version of the lre.train list.  Note that we don't add any
  # additive noise here.
  steps/data/reverberate_data_dir.py \
    "${rvb_opts[@]}" \
    --speech-rvb-probability 1 \
    --pointsource-noise-addition-probability 0 \
    --isotropic-noise-addition-probability 0 \
    --num-replications 1 \
    --source-sampling-rate 16000 \
    data/lre/train data/lre/train_reverb
  cp data/lre/train/vad.scp data/lre/train_reverb/
  utils/copy_data_dir.sh --utt-suffix "-reverb" data/lre/train_reverb data/lre/train_reverb.new
  rm -rf data/lre/train_reverb
  mv data/lre/train_reverb.new data/lre/train_reverb
  
  # Prepare the MUSAN corpus, which consists of music, speech, and noise
  # suitable for augmentation.
  steps/data/make_musan.sh --sampling-rate 16000 $musan_data data
  
  # Get the duration of the MUSAN recordings.  This will be used by the
  # script augment_data_dir.py.
  for name in speech noise music; do
    utils/data/get_utt2dur.sh data/musan_${name}
    mv data/musan_${name}/utt2dur data/musan_${name}/reco2dur
  done
  
  # Augment with musan_noise
  steps/data/augment_data_dir.py --utt-suffix "noise" --fg-interval 1 --fg-snrs "15:10:5:0" --fg-noise-dir "data/musan_noise" data/lre/train data/lre/train_noise
  # Augment with musan_music
  steps/data/augment_data_dir.py --utt-suffix "music" --bg-snrs "15:10:8:5" --num-bg-noises "1" --bg-noise-dir "data/musan_music" data/lre/train data/lre/train_music
  # Augment with musan_speech
  steps/data/augment_data_dir.py --utt-suffix "babble" --bg-snrs "20:17:15:13" --num-bg-noises "3:4:5:6:7" --bg-noise-dir "data/musan_speech" data/lre/train data/lre/train_babble
  
  # Combine reverb, noise, music, and babble into one directory.
  utils/combine_data.sh data/lre/train_aug data/lre/train_reverb data/lre/train_noise data/lre/train_music data/lre/train_babble

  # Take a random subset of the augmentations (100k is roughly the size of the CommonVoice dataset)
  utils/subset_data_dir.sh data/lre/train_aug 100000 data/lre/train_aug_100k
  utils/fix_data_dir.sh data/lre/train_aug_100k
  
  # Make MFCCs for the augmented data.  Note that we want we should alreay have the vad.scp
  # from the clean version at this point, which is identical to the clean version!
  # steps/make_mfcc_pitch.sh --mfcc-config conf/mfcc.conf --nj 5 --cmd "$train_cmd" \
  #   data/lre/train_aug_100k exp/make_mfcc/train_aug_100k exp/mfcc
  steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --nj 5 --cmd "$train_cmd" \
    data/lre/train_aug_100k exp/make_mfcc/train_aug_100k exp/mfcc

  # Combine the clean and augmented SRE list.  This is now roughly
  # double the size of the original clean list.
  utils/combine_data.sh data/lre/train_combined data/lre/train_aug_100k data/lre/train
fi

if [ $stage -le 5 ]; then
  # i-vector提取
  # for part in train dev test; do
  for part in train test; do
    # 三个目录分别为：i-vector提取器，数据目录，ivectors生成目录
    sid/extract_ivectors.sh --cmd "$train_cmd" --nj 5 exp/extractor data/lre/$part exp/ivectors_$part
  done
  # 提取增强后数据的i-vector
  sid/extract_ivectors.sh --cmd "$train_cmd" --nj 5 exp/extractor data/lre/train_combined exp/ivectors_train_combined
fi

:<<!
echo 'Before Data Augment...\n'
# 基于语种识别lre07的思路
if [ $stage -le 6 ]; then
  # 基于语种识别lre07的思路，需要根据i-vector，训练逻辑回归模型
  lid/run_logistic_regression.sh --prior-scale 0.70 --conf conf/logistic-regression.conf
  # Train error-rate: %ER 0.03
  # Test error-rate: %ER 36.63
  # 基于语种识别lre07的思路，计算ER和C_avg
  local/lre07_cv_eval.sh exp/ivectors_test local/general_lr_closed_set_langs.txt
  # Duration (sec):    avg
  #         ER (%):  36.63
  #      C_avg (%):  34.07
  
  echo ''
fi
!

# :<<!
echo -e '\nBefore Data Augment...'
# 基于说话人识别的思路
if [ $stage -le 6 ]; then
  # 如果基于说话人识别的思路，需要生成trials文件
  # 由于数据库中没有直接的数据来生成trials文件，需要自己组合生成
  # 这个文件是说话人识别特有的，简单来说，就是告诉系统，哪段语音是说话人X说的，哪段语音不是。
  lid/produce_trials.py data/lre/test/utt2lang $trials
fi

if [ $stage -le 7 ]; then 
  # 余弦距离打分 CDS
  local/cosine_scoring.sh data/lre/train data/lre/test \
  exp/ivectors_train exp/ivectors_test $trials exp/scores_cosine_gmm_1024
  # 计算EER，其中'-'表示从标准输入中读一次数据
  awk '{print $3}' exp/scores_cosine_gmm_1024/cosine_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

if [ $stage -le 8 ]; then
  # LDA + CDS
  local/lda_scoring.sh data/lre/train data/lre/train data/lre/test \
  exp/ivectors_train exp/ivectors_train exp/ivectors_test $trials exp/scores_lda_gmm_1024
  
  awk '{print $3}' exp/scores_lda_gmm_1024/lda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

if [ $stage -le 9 ]; then
  # LDA + PLDA
  local/plda_scoring.sh data/lre/train data/lre/train data/lre/test \
  exp/ivectors_train exp/ivectors_train exp/ivectors_test $trials exp/scores_plda_gmm_1024
  
  awk '{print $3}' exp/scores_plda_gmm_1024/plda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi
# !


echo -e '\nAfter Data Augment...'
if [ $stage -le 10 ]; then 
  # 余弦距离打分 CDS
  local/cosine_scoring.sh data/lre/train_combined data/lre/test \
  exp/ivectors_train_combined exp/ivectors_test $trials exp/scores_cosine_gmm_1024_train_combined

  awk '{print $3}' exp/scores_cosine_gmm_1024_train_combined/cosine_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

if [ $stage -le 11 ]; then
  # LDA + CDS
  local/lda_scoring.sh data/lre/train_combined data/lre/train_combined data/lre/test \
  exp/ivectors_train_combined exp/ivectors_train_combined exp/ivectors_test $trials exp/scores_lda_gmm_1024_train_combined

  awk '{print $3}' exp/scores_lda_gmm_1024_train_combined/lda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

if [ $stage -le 12 ]; then
  # LDA + PLDA
  local/plda_scoring.sh data/lre/train_combined data/lre/train_combined data/lre/test \
  exp/ivectors_train_combined exp/ivectors_train_combined exp/ivectors_test $trials exp/scores_plda_gmm_1024_train_combined
  
  awk '{print $3}' exp/scores_plda_gmm_1024_train_combined/plda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

