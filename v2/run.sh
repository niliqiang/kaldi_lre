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

mfccdir=`pwd`/mfcc
vaddir=`pwd`/mfcc

# 设置语料存放路径和语料URL
#（如需重新训练带瓶颈层的神经网络，注意local/train_bottleneck_nnet.sh中的数据路径）
# 工作站（10.112.212.188）数据集路径
# data=/mnt/HD1/niliqiang/cv_corpus
# 服务器（10.103.238.151）数据集路径
data=/mnt/DataDrive172/niliqiang/cv_corpus
musan_data=/mnt/DataDrive172/niliqiang/musan
rirs_data=/mnt/DataDrive172/niliqiang/RIRS_NOISES

# 设置trials文件路径
trials=data/lre/test_bnf/trials

# 指示系统的执行阶段
stage=2

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
  # 计算MFCC、CMVN、VAD
  for part in train test; do
    # --nj 指示：number of parallel jobs, 默认为4，需要注意的是nj不能超过说话人数（语种数），以免分割数据的时候被拒绝
    # 三个目录分别为：数据目录，log目录，mfcc生成目录
    # make MFCC plus pitch features
    local/make_mfcc_pitch.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_mfcc/$part $mfccdir || exit 1
    utils/fix_data_dir.sh data/lre/$part
    steps/compute_cmvn_stats.sh data/lre/$part exp/make_mfcc/$part $mfccdir
    utils/fix_data_dir.sh data/lre/$part
    steps/compute_vad_decision.sh --cmd "$train_cmd" --nj 5 data/lre/$part exp/make_vad/$part $vaddir
    utils/fix_data_dir.sh data/lre/$part
  done
fi

if [ $stage -le 3 ]; then
  # 提取BNF特征、VAD
  [ ! -d exp/param_bnf ] && mkdir -p exp/param_bnf
  for part in train test; do
    steps/nnet2/dump_bottleneck_features.sh --nj 4 \
      data/lre/$part data/lre/${part}_bnf exp/nnet_bottleneck_clean_100 exp/param_bnf exp/dump_bnf
    utils/fix_data_dir.sh data/lre/${part}_bnf
    steps/compute_vad_decision.sh --cmd "$train_cmd" --nj 5 data/lre/${part}_bnf exp/make_vad/${part}_bnf $vaddir
    utils/fix_data_dir.sh data/lre/${part}_bnf
  done
fi

if [ $stage -le 4 ]; then
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

# 数据增强
# 加混响：混响包含了real和simulated
# 加性噪声：加性包含人声babble，音乐背景声和真实噪声
if [ $stage -le 64 ]; then
  utils/data/get_utt2num_frames.sh --nj 5 --cmd "$train_cmd" data/lre/train_bnf
  frame_shift=0.01
  awk -v frame_shift=$frame_shift '{print $1, $2*frame_shift;}' data/lre/train_bnf/utt2num_frames > data/lre/train_bnf/reco2dur
  
  # Make a version with reverberated speech
  rvb_opts=()
  rvb_opts+=(--rir-set-parameters "0.5, ${rirs_data}/simulated_rirs/smallroom/rir_list")
  rvb_opts+=(--rir-set-parameters "0.5, ${rirs_data}/simulated_rirs/mediumroom/rir_list")

  # Make a reverberated version of the lre.train_bnf list.  Note that we don't add any
  # additive noise here.
  steps/data/reverberate_data_dir.py \
    "${rvb_opts[@]}" \
    --speech-rvb-probability 1 \
    --pointsource-noise-addition-probability 0 \
    --isotropic-noise-addition-probability 0 \
    --num-replications 1 \
    --source-sampling-rate 16000 \
    data/lre/train_bnf data/lre/train_bnf_reverb
  cp data/lre/train_bnf/vad.scp data/lre/train_bnf_reverb/
  utils/copy_data_dir.sh --utt-suffix "-reverb" data/lre/train_bnf_reverb data/lre/train_bnf_reverb.new
  rm -rf data/lre/train_bnf_reverb
  mv data/lre/train_bnf_reverb.new data/lre/train_bnf_reverb
  
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
  steps/data/augment_data_dir.py --utt-suffix "noise" --fg-interval 1 --fg-snrs "15:10:5:0" --fg-noise-dir "data/musan_noise" data/lre/train_bnf data/lre/train_bnf_noise
  # Augment with musan_music
  steps/data/augment_data_dir.py --utt-suffix "music" --bg-snrs "15:10:8:5" --num-bg-noises "1" --bg-noise-dir "data/musan_music" data/lre/train_bnf data/lre/train_bnf_music
  # Augment with musan_speech
  steps/data/augment_data_dir.py --utt-suffix "babble" --bg-snrs "20:17:15:13" --num-bg-noises "3:4:5:6:7" --bg-noise-dir "data/musan_speech" data/lre/train_bnf data/lre/train_bnf_babble
  
  # Combine reverb, noise, music, and babble into one directory.
  utils/combine_data.sh data/lre/train_bnf_aug data/lre/train_bnf_reverb data/lre/train_bnf_noise data/lre/train_bnf_music data/lre/train_bnf_babble

  # Take a random subset of the augmentations (13k is roughly the size of the CommonVoice dataset)
  utils/subset_data_dir.sh data/lre/train_bnf_aug 13000 data/lre/train_bnf_aug_13k
  utils/fix_data_dir.sh data/lre/train_bnf_aug_13k
  
  # Make MFCCs for the augmented data.  Note that we want we should alreay have the vad.scp
  # from the clean version at this point, which is identical to the clean version!
  steps/make_mfcc_pitch.sh --mfcc-config conf/mfcc.conf --nj 5 --cmd "$train_cmd" \
    data/lre/train_bnf_aug_13k exp/make_mfcc/train_bnf_aug_13k $mfccdir

  # Combine the clean and augmented SRE list.  This is now roughly
  # double the size of the original clean list.
  utils/combine_data.sh data/lre/train_bnf_combined data/lre/train_bnf_aug_13k data/lre/train_bnf
fi


if [ $stage -le 6 ]; then
  # i-vector提取
  # for part in train dev test; do
  for part in train test; do
    # 三个目录分别为：i-vector提取器，数据目录，ivectors生成目录
    sid/extract_ivectors.sh --cmd "$train_cmd" --nj 5 exp/extractor data/lre/${part}_bnf exp/ivectors_${part}_bnf
  done
  # 提取增强后数据的i-vector
  sid/extract_ivectors.sh --cmd "$train_cmd" --nj 5 exp/extractor data/lre/train_bnf_combined exp/ivectors_train_bnf_combined
 fi

# 基于说话人识别的思路
if [ $stage -le 7 ]; then
  # 如果基于说话人识别的思路，需要生成trials文件
  # 由于数据库中没有直接的数据来生成trials文件，需要自己组合生成
  # 这个文件是说话人识别特有的，简单来说，就是告诉系统，哪段语音是说话人X说的，哪段语音不是。
  local/produce_trials.py data/lre/test_bnf/utt2spk $trials
fi

echo -e '\nBefore Data Augment...'
if [ $stage -le 8 ]; then 
  # 余弦距离打分 CDS
  local/cosine_scoring.sh data/lre/train_bnf data/lre/test_bnf \
  exp/ivectors_train_bnf exp/ivectors_test_bnf $trials exp/scores_cosine_gmm_1024
  # 计算EER，其中'-'表示从标准输入中读一次数据
  awk '{print $3}' exp/scores_cosine_gmm_1024/cosine_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

if [ $stage -le 9 ]; then
  # LDA + CDS
  local/lda_scoring.sh data/lre/train_bnf data/lre/train_bnf data/lre/test_bnf \
  exp/ivectors_train_bnf exp/ivectors_train_bnf exp/ivectors_test_bnf $trials exp/scores_lda_gmm_1024
  
  awk '{print $3}' exp/scores_lda_gmm_1024/lda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

if [ $stage -le 10 ]; then
  # LDA + PLDA
  local/plda_scoring.sh data/lre/train_bnf data/lre/train_bnf data/lre/test_bnf \
  exp/ivectors_train_bnf exp/ivectors_train_bnf exp/ivectors_test_bnf $trials exp/scores_plda_gmm_1024
  
  awk '{print $3}' exp/scores_plda_gmm_1024/plda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

echo -e '\nAfter Data Augment...'
if [ $stage -le 11 ]; then 
  # 余弦距离打分 CDS
  local/cosine_scoring.sh data/lre/train_bnf_combined data/lre/test_bnf \
  exp/ivectors_train_bnf_combined exp/ivectors_test_bnf $trials exp/scores_cosine_gmm_1024_train_bnf_combined

  awk '{print $3}' exp/scores_cosine_gmm_1024_train_bnf_combined/cosine_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

if [ $stage -le 12 ]; then
  # LDA + CDS
  local/lda_scoring.sh data/lre/train_bnf_combined data/lre/train_bnf_combined data/lre/test_bnf \
  exp/ivectors_train_bnf_combined exp/ivectors_train_bnf_combined exp/ivectors_test_bnf $trials exp/scores_lda_gmm_1024_train_bnf_combined

  awk '{print $3}' exp/scores_lda_gmm_1024_train_bnf_combined/lda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi

if [ $stage -le 13 ]; then
  # LDA + PLDA
  local/plda_scoring.sh data/lre/train_bnf_combined data/lre/train_bnf_combined data/lre/test_bnf \
  exp/ivectors_train_bnf_combined exp/ivectors_train_bnf_combined exp/ivectors_test_bnf $trials exp/scores_plda_gmm_1024_train_bnf_combined
  
  awk '{print $3}' exp/scores_plda_gmm_1024_train_bnf_combined/plda_scores | paste - $trials | awk '{print $1, $4}' | compute-eer -
  # Equal error rate is , at threshold 
  echo ''
fi
