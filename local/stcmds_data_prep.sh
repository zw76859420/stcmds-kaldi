#!/bin/bash
#author:zhangwei

. ./path.sh || exit 1;

stcmds_data_dir=stcmds_data/ST-CMDS-20170001_1-OS/
stcmds_text=stcmds_data/transcript/stcmds_space.txt

train_dir=data/local/train
test_dir=data/local/test
tmp_dir=data/local/tmp


mkdir -p $train_dir
mkdir -p $test_dir
mkdir -p $tmp_dir

find $stcmds_data_dir -iname "*.wav" > $tmp_dir/wav.flist

local/train_test_split.pl data/local/tmp/wav.flist data/local/tmp/waves.test data/local/tmp/waves.train

cp data/local/tmp/waves.test data/local/train/wav.flist || exit 1;
cp data/local/tmp/waves.train data/local/test/wav.flist || exit 1;

rm -rf $tmp_dir


for dir in $train_dir $test_dir; do
  echo Preparing $dir transcriptions 
  sed -e 's/\.wav//' $dir/wav.flist | awk -F '/' '{print $NF}' > $dir/utt.list
  sed -e 's/\.wav//' $dir/wav.flist | awk -F '/' '{print $NF}' \
  | awk -F '[P]' '{print $NF}' | awk -F 'A' '{print $1}' \
  | awk -F 'I' '{print $1}' > $dir/spk_all
  paste -d' ' $dir/utt.list $dir/spk_all > $dir/utt2spk_all
  paste -d' ' $dir/utt.list $dir/wav.flist > $dir/wav.scp_all
  utils/filter_scp.pl -f 1 $dir/utt.list $stcmds_text > $dir/transcripts.txt
  awk '{print $1}' $dir/transcripts.txt > $dir/utt.list
  utils/filter_scp.pl -f 1 $dir/utt.list $dir/utt2spk_all | sort -u > $dir/utt2spk
  utils/filter_scp.pl -f 1 $dir/utt.list $dir/wav.scp_all | sort -u > $dir/wav.scp
  sort -u $dir/transcripts.txt > $dir/text
  utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt
done

mkdir -p data/train data/test

for f in spk2utt utt2spk wav.scp text; do
  cp $train_dir/$f data/train/$f || exit 1;
  cp $test_dir/$f data/test/$f || exit 1;
done

echo "ST-CMDS data preparation succeed"
exit 0;


