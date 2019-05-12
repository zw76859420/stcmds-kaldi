#/bin/bash

# This script is based on swbd/s5c/local/nnet3/run_tdnn.sh

# this is the standard "tdnn" system, built in nnet3; it's what we use to
# call multi-splice.

# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call train_tdnn.sh with --gpu false,
# --num-threads 16 and --minibatch-size 128.
set -e

stage=0
train_stage=9
affix=
common_egs_dir=

# training options
initial_effective_lrate=0.0015
final_effective_lrate=0.00015
num_epochs=4
num_jobs_initial=2
num_jobs_final=2
remove_egs=true

# feature options
use_ivectors=false

# End configuration section.

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

dir=exp/nnet3/tdnn_sp${affix:+_$affix}
gmm_dir=exp/tri5a
train_set=train_sp
ali_dir=exp/tri5a_ali
graph_dir=$gmm_dir/graph

#local/nnet3/run_ivector_common.sh --stage $stage || exit 1;
:<<!
if [ $stage -le 7 ]; then
  echo "$0: creating neural net configs";

  num_targets=$(tree-info $ali_dir/tree |grep num-pdfs|awk '{print $2}')
  echo "$num_targets"

  mkdir -p $dir/configs
  cat <<EOF > $dir/configs/network.xconfig
  #input dim=100 name=ivector
  input dim=16 name=input

  # please note that it is important to have input layer with the name=input
  # as the layer immediately preceding the fixed-affine-layer to enable
  # the use of short notation for the descriptor
  fixed-affine-layer name=lda input=Append(-2,-1,0,1) affine-transform-file=$dir/configs/lda.mat

  # the first splicing is moved before the lda layer, so no splicing here
  relu-batchnorm-layer name=tdnn1 dim=850
  relu-batchnorm-layer name=tdnn2 dim=850 input=Append(-1,0,1)
  relu-batchnorm-layer name=tdnn3 dim=850 input=Append(-1,0,1)
  relu-batchnorm-layer name=tdnn4 dim=850 input=Append(-1,0,1)
  relu-batchnorm-layer name=tdnn5 dim=850 input=Append(-1,0,1)
  relu-batchnorm-layer name=tdnn6 dim=850
  output-layer name=output input=tdnn6 dim=$num_targets max-change=1.5
EOF
  steps/nnet3/xconfig_to_configs.py --xconfig-file $dir/configs/network.xconfig --config-dir $dir/configs/
fi

if [ $stage -le 8 ]; then
  python steps/nnet3/train_dnn.py --stage=$train_stage \
    --cmd="$decode_cmd" \
    --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.minibatch-size 64 \
    --trainer.optimization.num-jobs-initial $num_jobs_initial \
    --trainer.optimization.num-jobs-final $num_jobs_final \
    --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
    --trainer.optimization.final-effective-lrate $final_effective_lrate \
    --egs.dir "$common_egs_dir" \
    --cleanup.remove-egs $remove_egs \
    --cleanup.preserve-model-interval 500 \
    --use-gpu true \
    --feat-dir=data/train \
    --ali-dir $ali_dir \
    --lang data/lang \
    --reporting.email="$reporting_email" \
    --dir=$dir  || exit 1;
fi
!
if [ $stage -le 9 ]; then
  # this version of the decoding treats each utterance separately
  # without carrying forward speaker information.
  for decode_set in test; do
    # num_jobs=`cat data/$decode_set/utt2spk|cut -d' ' -f2|sort -u|wc -l`
    decode_dir=$dir/decode_$decode_set
    steps/nnet3/decode.sh --nj 8 --cmd "$decode_cmd" \
    $graph_dir data/$decode_set $decode_dir || exit 1;
  done
fi

wait;
exit 0;
