#!/bin/bash
# Copyright  2014   David Snyder
#			2020	niliqiang
# Apache 2.0.
#
# Calculates the 3s, 10s, and 30s error rates and C_avgs on the LRE07 
# General Language Recognition closed-set using the directory containing 
# the language identification posteriors.  Detailed results such as the 
# probability of misses for individual languages are computed in 
# local/lre07_eval/lre07_results.

# Calculate eer and C_avgs on the common voice dataset

. ./cmd.sh
. ./path.sh
set -e

posterior_dir=$1
languages_file=$2

mkdir -p local/lre07_cv_eval/lre07_cv_results
lre07_cv_dir=local/lre07_cv_eval/lre07_cv_results

local/lre07_targets.pl $posterior_dir/posteriors data/lre/test/utt2lang \
  $languages_file $lre07_cv_dir/targets \
  $lre07_cv_dir/nontargets>/dev/null

# Create the the score (eg, targets.scr) file.
local/score_lre07.v01d.pl -t $lre07_cv_dir/targets -n $lre07_cv_dir/nontargets

# Compute the posterior probabilities for avg duration, as well as
# the target and nontarget files.
# % 15s表示右对齐、宽度为 15 个字符字符串格式，不足 15 个字符，左侧补充相应数量的空格符
printf '% 15s' 'Duration (sec):'
printf '% 7s' 'avg';
# 使用echo插入换行符
echo
printf '% 15s' 'ER (%):'

# Get the overall classification error rates.
er=$(compute-wer --text ark:<(lid/remove_dialect.pl data/lre/test/utt2lang) \
  ark:$posterior_dir/output 2>/dev/null | grep "WER" | awk '{print $2 }')
# % 7.2f 表示在正值前置一个空格，在负值前置一个负号，右对齐、7 个字符长度的浮点数，其中一个是小数点，小数点后面保留两位。
printf '% 7.2f' $er

echo

printf '% 15s' 'C_avg (%):'

# Get the overall C_avg.
cavg=$(tail -n 1 $lre07_cv_dir/targets.scr \
     | awk '{print 100*$4 }')
printf '% 7.2f' $cavg

echo
