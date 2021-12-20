#!/usr/bin/env bash
# hk3129: Decoding code taken from ../../s5b/local/chain/run_tdnn.sh

set -e -o pipefail
cmd=run.pl
stage=18
mic=ihm
nj=1
min_seg_len=1.55
use_ihm_ali=false
train_set=train_cleaned
gmm=tri3_cleaned
ihm_gmm=tri3
nnet3_affix=_cleaned

tree_affix= 
tdnn_affix=1j

echo "$0 $@"  # Print the command line for logging

. ./utils/parse_options.sh
. ./cmd.sh
. ./path.sh

dir=../s5b/exp/$mic/chain${nnet3_affix}/tdnn${tdnn_affix}_sp_bi

final_lm=`cat ../s5b/data/local/lm/final_lm`
LM=$final_lm.pr1-7
graph_dir=$dir/graph_${LM}

if [ $stage -le 18 ]; then
  rm $dir/.error 2>/dev/null || true
  features_to_decode_folder=$1
  set_name=$2
  dset=$3
  (
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
      --nj $nj --cmd "$decode_cmd" \
      --online-ivector-dir ../s5b/exp/$mic/nnet3${nnet3_affix}/ivectors_${dset}_hires \
      --scoring-opts "--min-lmwt 5 " \
      $graph_dir $features_to_decode_folder ../s5b/exp/$mic/chain_cleaned/tdnn1j_sp_bi/decode_${dset}_${set_name} || exit 1;
  ) || touch $dir/.error &

  wait
  if [ -f $dir/.error ]; then
    echo "$0: something went wrong in decoding"
    exit 1
  fi
fi
exit 0


