#!/bin/bash
#author:zhangwei

data=stcmds_data
stage=13
n=8

. ./cmd.sh
. ./path.sh

if [ $stage -le 0 ]; then
  echo "==========================Preparing Lexicon======================"
  local/stcmds_prepare_dict.sh $data/resource_stcmds || exit 1;
fi

if [ $stage -le 1 ]; then 
  echo "==========================Lang preparetion======================="
  utils/prepare_lang.sh --position-dependent-phones false data/local/dict "<SPOKEN_NOISE>" data/local/lang data/lang || exit 1;
fi

if [ $stage -le 2 ]; then
  echo "==========================Language Model Training================"
  local/stcmds_train_lms.sh || exit 1;
fi

if [ $stage -le 3 ]; then
  echo "===========================L G combination======================="
  utils/format_lm.sh data/lang data/local/lm/3gram-mincount/lm_unpruned.gz \
    data/local/dict/lexicon.txt data/lang_test || exit 1;
fi

if [ $stage -le 4 ]; then
  echo "===========================feature extract======================="
  mfccdir=mfcc
  for x in train test; do
  steps/make_mfcc_pitch.sh --cmd "$train_cmd" --nj $n data/$x exp/make_mfcc/$x $mfccdir || exit 1;
  steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir || exit 1;
  utils/fix_data_dir.sh data/$x || exit 1;
  done
fi

if [ $stage -le 5 ]; then
  echo "===========================Monophone Training===================="
  steps/train_mono.sh --cmd "$train_cmd" --nj $n data/train data/lang exp/mono || exit 1;
  utils/mkgraph.sh data/lang_test exp/mono exp/mono/graph || exit 1;
  steps/decode.sh --cmd "$decode_cmd" --config conf/decode.conf --nj $n \
  exp/mono/graph data/test exp/mono/decode_test || exit 1;
  steps/align_si.sh --cmd "$train_cmd" --nj $n \
  data/train data/lang exp/mono exp/mono_ali || exit 1;   
fi

if [ $stage -le 6 ]; then
  echo "============================Triphone Training====================="
  steps/train_deltas.sh --cmd "$train_cmd" \
  2500 20000 data/train data/lang exp/mono_ali exp/tri1 || exit 1;
  utils/mkgraph.sh data/lang_test exp/tri1 exp/tri1/graph || exit 1;
  steps/decode.sh --cmd "$decode_cmd" --config conf/decode.conf --nj 8 \
  exp/tri1/graph data/test exp/tri1/decode_test
  steps/align_si.sh --cmd "$train_cmd" --nj 8 \
  data/train data/lang exp/tri1 exp/tri1_ali || exit 1;
fi

if [ $stage -le 7 ]; then
  echo "============================Triphone Training====================="
  steps/train_deltas.sh --cmd "$train_cmd" \
  2500 20000 data/train data/lang exp/tri1_ali exp/tri2 || exit 1;
  utils/mkgraph.sh data/lang_test exp/tri2 exp/tri2/graph || exit 1;
  steps/decode.sh --cmd "$decode_cmd" --config conf/decode.conf --nj 8 \
  exp/tri2/graph data/test exp/tri2/decode_test
  steps/align_si.sh --cmd "$train_cmd" --nj 8 \
  data/train data/lang exp/tri2 exp/tri2_ali || exit 1;
fi

if [ $stage -le 8 ]; then
  echo "============================LDA+MLLT Training====================="
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
  2500 20000 data/train data/lang exp/tri2_ali exp/tri3a || exit 1;
  utils/mkgraph.sh data/lang_test exp/tri3a exp/tri3a/graph || exit 1;
  steps/decode.sh --cmd "$decode_cmd" --nj 8 --config conf/decode.conf \
  exp/tri3a/graph data/test exp/tri3a/decode_test
  steps/align_si.sh --cmd "$train_cmd" --nj 8 \
  data/train data/lang exp/tri3a exp/tri3a_ali || exit 1;
fi

if [ $stage -le 9 ]; then
  echo "============================SAT Training========================="
  steps/train_sat.sh --cmd "$train_cmd" \
  2500 20000 data/train data/lang exp/tri3a_ali exp/tri4a || exit 1;
  utils/mkgraph.sh data/lang_test exp/tri4a exp/tri4a/graph || exit 1;
  steps/decode_fmllr.sh --cmd "$decode_cmd" --nj 8 --config conf/decode.conf \
  exp/tri4a/graph data/test exp/tri4a/decode_test
  steps/align_fmllr.sh  --cmd "$train_cmd" --nj 8\
  data/train data/lang exp/tri4a exp/tri4a_ali || exit 1;
fi

if [ $stage -le 10 ]; then
  echo "============================Big SAT Training====================="
  steps/train_sat.sh --cmd "$train_cmd" \
  3500 100000 data/train data/lang exp/tri4a_ali exp/tri5a || exit 1;
  utils/mkgraph.sh data/lang_test exp/tri5a exp/tri5a/graph || exit 1;
  steps/decode_fmllr.sh --cmd "$decode_cmd" --nj 8 --config conf/decode.conf \
  exp/tri5a/graph data/test exp/tri5a/decode_test || exit 1;
  steps/align_fmllr.sh --cmd "$train_cmd" --nj 8 \
  data/train data/lang exp/tri5a exp/tri5a_ali || exit 1;
fi

if [ $stage -le 11 ]; then
  echo "============================Triphone Training====================="
  steps/train_deltas.sh --cmd "$train_cmd" \
  4200 40000 data/train data/lang exp/tri5a_ali exp/tri6a || exit 1;
  utils/mkgraph.sh data/lang_test exp/tri6a exp/tri6a/graph || exit 1;
  steps/decode.sh --cmd "$decode_cmd" --config conf/decode.conf --nj 8 \
  exp/tri6a/graph data/test exp/tri6a/decode_test
  steps/align_si.sh --cmd "$train_cmd" --nj 8 \
  data/train data/lang exp/tri6a exp/tri6a_ali || exit 1;
fi

if [ $stage -le 12 ]; then
  echo "============================DNN Training==========================="
  local/nnet3/run_tdnn.sh  
fi

if [ $stage -le 13 ]; then
  echo "============================chain Training==========================="
  local/chain/run_tdnn.sh
fi

local/show_results.sh

