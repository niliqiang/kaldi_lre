#!/usr/bin/perl
#
# Copyright 2017   Ewald Enzinger
#			2020	niliqiang
# Apache 2.0
#
# Usage: data_prep_cv.pl /export/data/cv_corpus/zh_CN train out_dir

if (@ARGV != 3) {
  print STDERR "Usage: $0 <path-to-commonvoice-corpus> <dataset> <path-to-output>\n";
  print STDERR "e.g. $0 /export/data/cv_corpus/zh_CN train out_dir\n";
  exit(1);
}

($db_base, $dataset, $out_dir) = @ARGV;

# 获取语种信息
$lang = (split("/", $db_base))[-1];

# 依次创建文件夹
mkdir data unless -d data;
mkdir "data/$lang" unless -d "data/$lang";
mkdir $out_dir unless -d $out_dir;

#打开/创建相应文件
open(META, "<", "$db_base/$dataset.tsv") or die "cannot open dataset TSV file $db_base/$dataset.tsv";
open(UTT2LANG, ">", "$out_dir/utt2lang") or die "Could not open the output file $out_dir/utt2lang";
open(UTT2SPK, ">", "$out_dir/utt2spk") or die "Could not open the output file $out_dir/utt2spk";
open(WAV, ">", "$out_dir/wav.scp") or die "Could not open the output file $out_dir/wav.scp";

# 不使用说话人信息，只关注语种信息
readline META;    # 第一行为标头 skip the first line
while(<META>) {
  chomp;
  ($client_id, $path, $sentence, $up_votes, $down_votes, $age, $gender, $accent) = split(" ", $_);
  $uttId = $path;
  $uttId =~ s/\.mp3//g;
  # No speaker information is provided, so we treat each utterance as coming from a different speaker
  $spkr = $uttId;
  # sox指令要跟例程中的一致，最后的 '- |' 不能缺少
  print WAV "$uttId"," sox $db_base/clips/$path -t wav -r 16k -b 16 -e signed - |\n";
  # 由于现在的程序主要是根据sre修改而来，为了更快的搭建语种识别系统，将语种信息存到utt2spk文件中，把语种当成speaker训练，待对系统有了更深刻的理解再修改
  # print UTT2SPK "$uttId"," $spkr","\n";
  print UTT2SPK "$uttId"," $lang","\n";
  print UTT2LANG "$uttId"," $lang","\n";
}
close(META) || die;
close(UTT2LANG) || die;
close(UTT2SPK) || die;
close(WAV) || die;

# =pod  # 块注释，与=cut对应
# 生成语音和说话人/语种的对应文件
if (system(
  "utils/utt2spk_to_spk2utt.pl $out_dir/utt2lang >$out_dir/lang2utt") != 0) {
  die "Error creating lang2utt file in directory $out_dir";
}
if (system(
  "utils/utt2spk_to_spk2utt.pl $out_dir/utt2spk >$out_dir/spk2utt") != 0) {
  die "Error creating spk2utt file in directory $out_dir";
}

# 按行修正和验证
# LC_COLLATE 定义该环境的排序和比较规则，保证文件是有序的
system("env LC_COLLATE=C utils/fix_data_dir.sh $out_dir");
if (system("env LC_COLLATE=C utils/validate_data_dir.sh --no-text --no-feats $out_dir") != 0) {
  die "Error validating directory $out_dir";
}
# =cut
