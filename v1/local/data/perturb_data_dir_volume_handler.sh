#!/usr/bin/env bash

# Copyright 2016  Johns Hopkins University (author: Daniel Povey)
# Apache 2.0

# This script operates on a data directory, such as in data/train/, and modifies
# the wav.scp to perturb the volume (typically useful for training data when
# using systems that don't have cepstral mean normalization).

. utils/parse_options.sh

if [ $# != 2 ]; then
  echo "Usage: $0 <srcdir> <destdir>"
  echo "e.g.:"
  echo " $0 data/train data/train_vp"
  exit 1
fi

srcdir=$1
destdir=$2

utt_prefix="-vp"

if [ ! -f $srcdir/utt2spk ]; then
  echo "$0: no such file $srcdir/utt2spk"
  exit 1;
fi

if [ ! -f $srcdir/wav.scp ]; then
  echo "$0: Expected $srcdir/wav.scp to exist"
  exit 1
fi

if [ "$destdir" == "$srcdir" ]; then
  echo "$0: this script requires <srcdir> and <destdir> to be different."
  exit 1
fi

set -e;
set -o pipefail

mkdir -p $destdir

cat $srcdir/utt2spk | awk -v p=$utt_prefix '{printf("%s %s%s\n", $1, $1, p);}' > $destdir/utt_map
cat $srcdir/spk2utt | awk '{printf("%s %s\n", $1, $1);}' > $destdir/spk_map
if [ ! -f $srcdir/utt2uniq ]; then
  cat $srcdir/utt2spk | awk -v p=$utt_prefix '{printf("%s%s %s\n", $1, p, $1);}' > $destdir/utt2uniq
else
  cat $srcdir/utt2uniq | awk -v p=$utt_prefix '{printf("%s%s %s\n", $1, p, $2);}' > $destdir/utt2uniq
fi

cat $srcdir/utt2spk | utils/apply_map.pl -f 1 $destdir/utt_map  | \
  utils/apply_map.pl -f 2 $destdir/spk_map >$destdir/utt2spk

utils/utt2spk_to_spk2utt.pl <$destdir/utt2spk >$destdir/spk2utt

if [ -f $srcdir/text ]; then
  utils/apply_map.pl -f 1 $destdir/utt_map <$srcdir/text >$destdir/text
fi
if [ -f $srcdir/spk2gender ]; then
  utils/apply_map.pl -f 1 $destdir/spk_map <$srcdir/spk2gender >$destdir/spk2gender
fi
if [ -f $srcdir/utt2lang ]; then
  utils/apply_map.pl -f 1 $destdir/utt_map <$srcdir/utt2lang >$destdir/utt2lang
fi

if [ -f $srcdir/wav.scp ]; then
  cat $srcdir/wav.scp | awk '$1=$1"-vp" {print $0}' > $destdir/wav.scp
  utils/data/perturb_data_dir_volume.sh $destdir
fi

rm $destdir/spk_map $destdir/utt_map 2>/dev/null
echo "$0: generated volume-perturbed version of data in $srcdir, in $destdir"

utils/validate_data_dir.sh --no-feats --no-text $destdir
