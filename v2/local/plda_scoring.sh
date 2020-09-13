#!/bin/bash
# Copyright 2015   David Snyder
# Apache 2.0.
#
# This script trains PLDA models and does scoring.

use_existing_models=false
lda_dim=150
covar_factor=0.1
simple_length_norm=false # If true, replace the default length normalization
                         # performed in PLDA  by an alternative that
                         # normalizes the length of the iVectors to be equal
                         # to the square root of the iVector dimension.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 8 ]; then
  echo "Usage: $0 <plda-data-dir> <enroll-data-dir> <test-data-dir> <plda-ivec-dir> <enroll-ivec-dir> <test-ivec-dir> <trials-file> <scores-dir>"
fi

plda_data_dir=$1
enroll_data_dir=$2
test_data_dir=$3
plda_ivec_dir=$4
enroll_ivec_dir=$5
test_ivec_dir=$6
trials=$7
scores_dir=$8

if [ "$use_existing_models" == "true" ]; then
  for f in ${plda_ivec_dir}/mean.vec ${plda_ivec_dir}/plda ; do
    [ ! -f $f ] && echo "No such file $f" && exit 1;
  done
else
  # Use LDA to decrease the dimensionality prior to PLDA
  run.pl $plda_ivec_dir/log/lda.log \
    ivector-compute-lda --total-covariance-factor=$covar_factor --dim=$lda_dim \
    "ark:ivector-normalize-length scp:${plda_ivec_dir}/ivector.scp ark:- |" \
    ark:$plda_data_dir/utt2spk ${plda_ivec_dir}/transform.mat || exit 1;

  # Train the PLDA model.
  run.pl $plda_ivec_dir/log/plda.log \
    ivector-compute-plda ark:$plda_data_dir/spk2utt \
    "ark:ivector-normalize-length scp:${plda_ivec_dir}/ivector.scp  ark:- | transform-vec ${plda_ivec_dir}/transform.mat ark:- ark:- |" \
    $plda_ivec_dir/plda || exit 1;
fi

# Compute i-vector mean.
run.pl ${plda_ivec_dir}/log/compute_mean.log \
  ivector-normalize-length scp:${plda_ivec_dir}/ivector.scp \
  ark:- \| ivector-mean ark:- ${plda_ivec_dir}/mean.vec || exit 1;

mkdir -p $scores_dir/log

run.pl $scores_dir/log/plda_scoring.log \
  ivector-plda-scoring --normalize-length=true \
    --simple-length-normalization=$simple_length_norm \
    --num-utts=ark:${enroll_ivec_dir}/num_utts.ark \
    "ivector-copy-plda --smoothing=0.0 ${plda_ivec_dir}/plda - |" \
    "ark:ivector-subtract-global-mean ${plda_ivec_dir}/mean.vec scp:${enroll_ivec_dir}/spk_ivector.scp ark:- | transform-vec ${plda_ivec_dir}/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "ark:ivector-normalize-length scp:${test_ivec_dir}/ivector.scp ark:- | ivector-subtract-global-mean ${plda_ivec_dir}/mean.vec ark:- ark:- | transform-vec ${plda_ivec_dir}/transform.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
    "cat '$trials' | cut -d\  --fields=1,2 |" $scores_dir/plda_scores || exit 1;

